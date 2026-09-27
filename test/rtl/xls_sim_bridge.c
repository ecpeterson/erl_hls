#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vpi_user.h"
#include "xls_sim_axis.h"

#define BUFFER_SIZE 65536
#define PATH_SIZE 4096

typedef struct {
    uint8_t bytes[BUFFER_SIZE];
    size_t head;
    size_t count;
} byte_ring_t;

typedef enum {
    INPUT_ROUTE_HEADER,
    INPUT_FRAME_HEADER,
    INPUT_FRAME_PAYLOAD
} input_phase_t;

typedef struct {
    const char *name;
    int enabled;
    vpiHandle h_s_data;
    vpiHandle h_s_valid;
    vpiHandle h_s_ready;
    vpiHandle h_s_last;
    vpiHandle h_s_keep;
    vpiHandle h_m_data;
    vpiHandle h_m_valid;
    vpiHandle h_m_ready;
    vpiHandle h_m_last;
    vpiHandle h_m_keep;
    int fd_host_to_sim;
    int fd_sim_to_host;
    byte_ring_t input_bytes;
    byte_ring_t output_bytes;
    uint32_t s_data;
    int s_valid;
    int s_last;
    axis_sample_t s_sample, m_sample;
    axis_monitor_t s_monitor, m_monitor;
    int m_ready;
    /* Remaining payload words after the inner four-byte frame header. */
    unsigned input_payload_words;
    /* Which word comes next in the routed packet read from the byte FIFO. */
    input_phase_t input_phase;
    /* Diagnostic counters used only to make VPI logs easier to correlate. */
    unsigned input_beat_number;
    unsigned output_beat_number;
    /* Suppress reset-time output until the host begins its first request. */
    int output_armed;
} axis_endpoint_t;

static vpiHandle h_clk;
static vpiHandle h_resetn;
static const char *hierarchy_root;
static uint64_t cycle_number;
static int bridge_failed;

static axis_endpoint_t app_endpoint;
static axis_endpoint_t debug_endpoint;
static void bridge_fail(const char *format, ...) {
    va_list args;
    if (bridge_failed) return;
    bridge_failed = 1;
    vpi_printf("xls_sim_bridge: FAIL cycle=%llu: ",
               (unsigned long long)cycle_number);
    va_start(args, format);
    vpi_vprintf(format, args);
    va_end(args);
    vpi_printf("\n");
    /* vpiFinish's argument controls diagnostics, not the process exit code. */
    vpip_set_return_value(1);
    vpi_control(vpiFinish, 1);
}

static axis_value_t sample_value(vpiHandle signal) {
    s_vpi_value value = { .format = vpiVectorVal };
    vpi_get_value(signal, &value);
    return (axis_value_t) { value.value.vector[0].aval,
                            value.value.vector[0].bval };
}

static void sample_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled) return;
#define SAMPLE(direction) endpoint->direction##_sample = (axis_sample_t) { \
    sample_value(endpoint->h_##direction##_data), \
    sample_value(endpoint->h_##direction##_keep), \
    sample_value(endpoint->h_##direction##_last), \
    sample_value(endpoint->h_##direction##_valid), \
    sample_value(endpoint->h_##direction##_ready) }
    SAMPLE(s);
    SAMPLE(m);
#undef SAMPLE
}

static void check_endpoint(axis_endpoint_t *endpoint, int finishing) {
    if (!endpoint->enabled || bridge_failed) return;
    const char *error = finishing ? axis_finish(&endpoint->s_monitor) :
        axis_check(&endpoint->s_monitor, endpoint->s_sample);
    if (error) bridge_fail("%s host->DUT: %s", endpoint->name, error);
    error = finishing ? axis_finish(&endpoint->m_monitor) :
        axis_check(&endpoint->m_monitor, endpoint->m_sample);
    if (error) bridge_fail("%s DUT->host: %s", endpoint->name, error);
    if (finishing && (endpoint->s_valid || endpoint->input_bytes.count ||
                      endpoint->output_bytes.count))
        bridge_fail("%s: simulation ended with pending FIFO bytes", endpoint->name);
}

static void check_reset_boundary(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled) return;
    if (axis_finish(&endpoint->s_monitor) || axis_finish(&endpoint->m_monitor) ||
        endpoint->s_valid || endpoint->input_bytes.count || endpoint->output_bytes.count)
        bridge_fail("%s: reset interrupted transport; restart simulation and FIFOs",
                    endpoint->name);
}

static size_t ring_free(const byte_ring_t *ring) {
    return BUFFER_SIZE - ring->count;
}

static int ring_push(byte_ring_t *ring, uint8_t byte) {
    size_t tail;
    if (ring->count == BUFFER_SIZE)
        return 0;
    tail = (ring->head + ring->count) % BUFFER_SIZE;
    ring->bytes[tail] = byte;
    ring->count++;
    return 1;
}

static int ring_pop(byte_ring_t *ring, uint8_t *byte) {
    if (ring->count == 0)
        return 0;
    *byte = ring->bytes[ring->head];
    ring->head = (ring->head + 1) % BUFFER_SIZE;
    ring->count--;
    return 1;
}

static void ring_push_word(byte_ring_t *ring, uint32_t word) {
    unsigned shift;
    for (shift = 0; shift < 32; shift += 8)
        ring_push(ring, (uint8_t)(word >> shift));
}

static uint32_t ring_pop_word(byte_ring_t *ring) {
    uint32_t word = 0;
    uint8_t byte = 0;
    unsigned shift;
    for (shift = 0; shift < 32; shift += 8) {
        ring_pop(ring, &byte);
        word |= (uint32_t)byte << shift;
    }
    return word;
}

static uint32_t get_u32(vpiHandle signal) {
    s_vpi_value value;
    value.format = vpiIntVal;
    vpi_get_value(signal, &value);
    return (uint32_t)value.value.integer;
}

static int get_bit(vpiHandle signal) {
    return (get_u32(signal) & 1U) != 0;
}

static void put_u32(vpiHandle signal, uint32_t word) {
    s_vpi_value value;
    value.format = vpiIntVal;
    value.value.integer = (PLI_INT32)word;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

static void put_bit(vpiHandle signal, int bit) {
    s_vpi_value value;
    value.format = vpiScalarVal;
    value.value.scalar = bit ? vpi1 : vpi0;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

static void pump_input(axis_endpoint_t *endpoint) {
    uint8_t buffer[4096];
    ssize_t count;
    size_t index;

    if (!endpoint->enabled)
        return;

    while (ring_free(&endpoint->input_bytes) >= sizeof(buffer)) {
        count = read(endpoint->fd_host_to_sim, buffer, sizeof(buffer));
        if (count > 0) {
            vpi_printf("xls_sim_bridge[%s]: read %ld host byte(s)\n",
                       endpoint->name, (long)count);
            for (index = 0; index < (size_t)count; index++)
                ring_push(&endpoint->input_bytes, buffer[index]);
        } else if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        } else if (errno != EINTR) {
            bridge_fail("%s input FIFO read failed: %s",
                       endpoint->name, strerror(errno));
            return;
        }
    }
}

static void pump_output(axis_endpoint_t *endpoint) {
    uint8_t buffer[4096];
    size_t count = endpoint->output_bytes.count;
    size_t index;
    ssize_t written;

    if (!endpoint->enabled)
        return;

    if (count > sizeof(buffer))
        count = sizeof(buffer);
    for (index = 0; index < count; index++)
        buffer[index] = endpoint->output_bytes.bytes[
            (endpoint->output_bytes.head + index) % BUFFER_SIZE
        ];

    if (count == 0)
        return;
    written = write(endpoint->fd_sim_to_host, buffer, count);
    if (written > 0) {
        endpoint->output_bytes.head =
            (endpoint->output_bytes.head + (size_t)written) % BUFFER_SIZE;
        endpoint->output_bytes.count -= (size_t)written;
    } else if (written < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
        bridge_fail("%s output FIFO write failed: %s",
                   endpoint->name, strerror(errno));
    }
}

static void load_input_beat(axis_endpoint_t *endpoint) {
    uint32_t word;

    if (!endpoint->enabled || endpoint->s_valid ||
        endpoint->input_bytes.count < 4)
        return;

    word = ring_pop_word(&endpoint->input_bytes);
    endpoint->s_data = word;
    endpoint->s_valid = 1;
    if (endpoint->input_phase == INPUT_ROUTE_HEADER) {
        endpoint->s_last = 0;
        endpoint->input_phase = INPUT_FRAME_HEADER;
    } else if (endpoint->input_phase == INPUT_FRAME_HEADER) {
        endpoint->input_payload_words = word & 0xffU;
        endpoint->s_last = endpoint->input_payload_words == 0;
        endpoint->input_phase = endpoint->s_last ?
            INPUT_ROUTE_HEADER : INPUT_FRAME_PAYLOAD;
    } else {
        endpoint->s_last = endpoint->input_payload_words == 1;
        endpoint->input_payload_words--;
        if (endpoint->s_last)
            endpoint->input_phase = INPUT_ROUTE_HEADER;
    }
    vpi_printf("xls_sim_bridge[%s]: input beat %u data=%08x last=%d\n",
               endpoint->name, ++endpoint->input_beat_number, word, endpoint->s_last);
}

static void reset_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;
    endpoint->s_data = 0;
    endpoint->s_valid = 0;
    endpoint->s_last = 0;
    endpoint->s_sample = (axis_sample_t) {0};
    endpoint->m_sample = (axis_sample_t) {0};
    endpoint->s_monitor = (axis_monitor_t) {0};
    endpoint->m_monitor = (axis_monitor_t) {0};
    endpoint->m_ready = 1;
    endpoint->input_payload_words = 0;
    endpoint->input_phase = INPUT_ROUTE_HEADER;
    endpoint->output_armed = 0;
}

static void step_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled || bridge_failed)
        return;

    if (endpoint->s_sample.valid.value && endpoint->s_sample.ready.value) {
        vpi_printf("xls_sim_bridge[%s]: cycle=%llu accepted input beat %u\n",
                   endpoint->name, (unsigned long long)cycle_number,
                   endpoint->input_beat_number);
        endpoint->output_armed = 1;
        endpoint->s_valid = 0;
        endpoint->s_last = 0;
    }

    if (endpoint->m_sample.valid.value && endpoint->m_sample.ready.value) {
        if (endpoint->output_armed) {
            vpi_printf(
                "xls_sim_bridge[%s]: cycle=%llu output beat %u data=%08x\n",
                endpoint->name, (unsigned long long)cycle_number,
                ++endpoint->output_beat_number, endpoint->m_sample.data.value);
            if (ring_free(&endpoint->output_bytes) >= 4)
                ring_push_word(&endpoint->output_bytes, endpoint->m_sample.data.value);
            else
                bridge_fail("%s internal output buffer overflow",
                           endpoint->name);
        } else {
            vpi_printf("xls_sim_bridge[%s]: discarded pre-request output %08x\n",
                       endpoint->name, endpoint->m_sample.data.value);
        }
    }

    pump_output(endpoint);
    endpoint->m_ready = ring_free(&endpoint->output_bytes) >= 4;
    load_input_beat(endpoint);
}

static void apply_drives(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;
    put_u32(endpoint->h_s_data, endpoint->s_data);
    put_u32(endpoint->h_s_keep, 0xf);
    put_bit(endpoint->h_s_valid, endpoint->s_valid);
    put_bit(endpoint->h_s_last, endpoint->s_last);
    put_bit(endpoint->h_m_ready, endpoint->m_ready);
}

static void schedule_sync_cb(PLI_INT32 reason, PLI_INT32 (*callback)(p_cb_data)) {
    static s_vpi_time time;
    s_cb_data cb;
    memset(&cb, 0, sizeof(cb));
    time.type = vpiSimTime;
    cb.reason = reason;
    cb.cb_rtn = callback;
    cb.time = &time;
    vpi_register_cb(&cb);
}

// Optional passive observer; the transport itself knows only AXI streams.
#ifdef XLS_SIM_OBSERVER
#include XLS_SIM_OBSERVER
#else
static void sim_observer_reset(void) {}
static void sim_observer_step(unsigned before, int armed) { (void)before; (void)armed; }
static void sim_observer_finish(void) {}
static void sim_observer_start(int only) { (void)only; }
#endif

static PLI_INT32 cb_readwrite(p_cb_data cb) {
    (void)cb;
    if (bridge_failed) return 0;
    apply_drives(&app_endpoint);
    apply_drives(&debug_endpoint);
    return 0;
}

static PLI_INT32 cb_readonly(p_cb_data cb) {
    unsigned app_output_before;
    int app_armed_before;
    (void)cb;
    if (bridge_failed) return 0;
    if (!get_bit(h_clk)) return 0;

    pump_input(&app_endpoint);
    pump_input(&debug_endpoint);
    pump_output(&app_endpoint);
    pump_output(&debug_endpoint);

    axis_value_t resetn = sample_value(h_resetn);
    if (resetn.unknown) {
        bridge_fail("unknown resetn");
        return 0;
    }
    if (!resetn.value) {
        // Initial reset permits queued startup input. A later reset cannot
        // resynchronize partially delivered byte streams: require a fresh run.
        if (cycle_number) {
            check_reset_boundary(&app_endpoint);
            check_reset_boundary(&debug_endpoint);
        }
        cycle_number = 0;
        reset_endpoint(&app_endpoint);
        reset_endpoint(&debug_endpoint);
        sim_observer_reset();
        return 0;
    }

    cycle_number++;
    check_endpoint(&app_endpoint, 0);
    check_endpoint(&debug_endpoint, 0);
    if (bridge_failed) return 0;
    app_output_before = app_endpoint.output_beat_number;
    app_armed_before = app_endpoint.output_armed;
    step_endpoint(&app_endpoint);
    step_endpoint(&debug_endpoint);
    sim_observer_step(app_output_before, app_armed_before);
    return 0;
}

static PLI_INT32 cb_end_of_sim(p_cb_data cb) {
    (void)cb;
    check_endpoint(&app_endpoint, 1);
    check_endpoint(&debug_endpoint, 1);
    sim_observer_finish();
    return 0;
}

static PLI_INT32 cb_clk_change(p_cb_data cb) {
    (void)cb;
    if (bridge_failed) return 0;
    // Capture the accepting edge before nonblocking RTL register updates.
    // A falling-edge snapshot misses changes in the second half of a cycle.
    if (get_bit(h_clk)) {
        sample_endpoint(&app_endpoint);
        sample_endpoint(&debug_endpoint);
    }
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    return 0;
}

static vpiHandle find_signal(const char *name) {
    char path[PATH_SIZE];
    snprintf(path, sizeof(path), "%s.%s", hierarchy_root, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static vpiHandle require_signal(const char *name, int width) {
    vpiHandle signal = find_signal(name);
    if (!signal)
        bridge_fail("missing signal %s.%s", hierarchy_root, name);
    else if (vpi_get(vpiSize, signal) != width)
        bridge_fail("signal %s.%s must be %d bits (got %d)",
                    hierarchy_root, name, width, vpi_get(vpiSize, signal));
    return signal;
}

static int find_endpoint_signals(
    axis_endpoint_t *endpoint,
    const char *s_prefix,
    const char *m_prefix
) {
    char name[128];
#define FIND(handle, prefix, suffix, width) do { \
    snprintf(name, sizeof(name), "%s_%s", prefix, suffix); \
    endpoint->handle = require_signal(name, width); \
} while (0)
    FIND(h_s_data, s_prefix, "tdata", 32);
    FIND(h_s_valid, s_prefix, "tvalid", 1);
    FIND(h_s_ready, s_prefix, "tready", 1);
    FIND(h_s_last, s_prefix, "tlast", 1);
    FIND(h_s_keep, s_prefix, "tkeep", 4);
    FIND(h_m_data, m_prefix, "tdata", 32);
    FIND(h_m_valid, m_prefix, "tvalid", 1);
    FIND(h_m_ready, m_prefix, "tready", 1);
    FIND(h_m_last, m_prefix, "tlast", 1);
    FIND(h_m_keep, m_prefix, "tkeep", 4);
#undef FIND
    return !bridge_failed;
}

static int open_fifo(const char *path) {
    int fd;
    if (unlink(path) != 0 && errno != ENOENT) {
        vpi_printf("xls_sim_bridge: cannot remove %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (mkfifo(path, 0600) != 0) {
        vpi_printf("xls_sim_bridge: cannot create %s: %s\n", path, strerror(errno));
        return -1;
    }
    fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0)
        vpi_printf("xls_sim_bridge: cannot open %s: %s\n", path, strerror(errno));
    return fd;
}

static int open_endpoint_fifos(
    axis_endpoint_t *endpoint,
    const char *directory,
    const char *prefix
) {
    char host_to_sim[PATH_SIZE];
    char sim_to_host[PATH_SIZE];
    snprintf(host_to_sim, sizeof(host_to_sim), "%s/%s_tx", directory, prefix);
    snprintf(sim_to_host, sizeof(sim_to_host), "%s/%s_rx", directory, prefix);
    endpoint->fd_host_to_sim = open_fifo(host_to_sim);
    endpoint->fd_sim_to_host = open_fifo(sim_to_host);
    return endpoint->fd_host_to_sim >= 0 && endpoint->fd_sim_to_host >= 0;
}

static PLI_INT32 cb_start_of_sim(p_cb_data cb) {
    const char *directory = getenv("ERL_HLS_SIM_DIR");
    const char *configured_root = getenv("ERL_HLS_SIM_TOP");
    const char *debug_only_value = getenv("ERL_HLS_SIM_DEBUG_ONLY");
    const char *app_only_value = getenv("ERL_HLS_SIM_APP_ONLY");
    const char *profile_only_value = getenv("ERL_HLS_SIM_PROFILE_ONLY");
    int debug_only = debug_only_value && strcmp(debug_only_value, "1") == 0;
    int app_only = app_only_value && strcmp(app_only_value, "1") == 0;
    s_cb_data clock_cb;
    s_cb_data end_cb;
    (void)cb;

    int observer_only = profile_only_value &&
        strcmp(profile_only_value, "1") == 0;
    if ((app_only + debug_only + observer_only) > 1) {
        bridge_fail("APP_ONLY, DEBUG_ONLY and PROFILE_ONLY are mutually exclusive");
        return 0;
    }
    if (!directory && !observer_only) {
        bridge_fail("ERL_HLS_SIM_DIR is not set");
        return 0;
    }

    memset(&app_endpoint, 0, sizeof(app_endpoint));
    memset(&debug_endpoint, 0, sizeof(debug_endpoint));
    hierarchy_root = configured_root && configured_root[0] != '\0' ?
        configured_root : "regsvc_bridge_tb";
    app_endpoint.name = "app";
    app_endpoint.enabled = !observer_only && !debug_only;
    debug_endpoint.name = "debug";
    debug_endpoint.enabled = !observer_only && !app_only;
    h_clk = require_signal("clk", 1);
    h_resetn = require_signal("resetn", 1);
    if (bridge_failed ||
        (app_endpoint.enabled &&
         !find_endpoint_signals(&app_endpoint, "s_axis", "m_axis")) ||
        (debug_endpoint.enabled &&
         !find_endpoint_signals(&debug_endpoint, "s_dbg", "m_dbg"))) {
        return 0;
    }

    sim_observer_start(observer_only);

    if ((app_endpoint.enabled &&
         !open_endpoint_fifos(&app_endpoint, directory, "app")) ||
        (debug_endpoint.enabled &&
         !open_endpoint_fifos(&debug_endpoint, directory, "debug"))) {
        bridge_fail("failed to open transport FIFOs");
        return 0;
    }

    reset_endpoint(&app_endpoint);
    reset_endpoint(&debug_endpoint);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);

    memset(&clock_cb, 0, sizeof(clock_cb));
    clock_cb.reason = cbValueChange;
    clock_cb.cb_rtn = cb_clk_change;
    clock_cb.obj = h_clk;
    vpi_register_cb(&clock_cb);
    memset(&end_cb, 0, sizeof(end_cb));
    end_cb.reason = cbEndOfSimulation;
    end_cb.cb_rtn = cb_end_of_sim;
    vpi_register_cb(&end_cb);
    if (observer_only) {
        vpi_printf("xls_sim_bridge: observation-only mode enabled\n");
    } else if (debug_only) {
        vpi_printf("xls_sim_bridge: debug endpoint listening in %s\n", directory);
    } else {
        vpi_printf("xls_sim_bridge: application%s endpoint%s listening in %s\n",
                   debug_endpoint.enabled ? " and debug" : "",
                   debug_endpoint.enabled ? "s" : "", directory);
    }
    return 0;
}

static void entry_point(void) {
    s_cb_data cb;
    memset(&cb, 0, sizeof(cb));
    cb.reason = cbStartOfSimulation;
    cb.cb_rtn = cb_start_of_sim;
    vpi_register_cb(&cb);
}

void (*vlog_startup_routines[])(void) = {
    entry_point,
    0
};
