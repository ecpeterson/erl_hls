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
/* Fixed-capacity byte queue; all simulator I/O remains nonblocking. */
typedef struct {
    uint8_t bytes[BUFFER_SIZE];
    size_t head;
    size_t count;
} byte_ring_t;

/* Position within the routed frame currently read from the host FIFO. */
typedef enum {
    INPUT_ROUTE_HEADER,
    INPUT_FRAME_HEADER,
    INPUT_FRAME_PAYLOAD
} input_phase_t;

/* Public signals, byte queues and protocol monitors for one stream. */
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

// Four transport endpoints; no hierarchy/state discovery is performed.
static axis_endpoint_t endpoints[4];
static vpiHandle h_clk, h_resetn;
static const char *hierarchy_root;
static uint64_t cycle_number;
static int bridge_failed;
static int transport_active, transport_retired;
static const char *transport_directory;
/* Fail the regression once, retaining a nonzero simulator exit code. */
static void bridge_fail(const char *format, ...) {
    va_list args;
    if (bridge_failed) return;
    bridge_failed = 1;
    vpi_printf("partition_sim_bridge: FAIL cycle=%llu: ",
               (unsigned long long)cycle_number);
    va_start(args, format);
    vpi_vprintf(format, args);
    va_end(args);
    vpi_printf("\n");
    /* vpiFinish's argument controls diagnostics, not the process exit code. */
    vpip_set_return_value(1);
    vpi_control(vpiFinish, 1);
}

/* Preserve X/Z masks when sampling a public signal. */
static axis_value_t sample_value(vpiHandle signal) {
    s_vpi_value value = { .format = vpiVectorVal };
    vpi_get_value(signal, &value);
    return (axis_value_t) { value.value.vector[0].aval,
                            value.value.vector[0].bval };
}

/* Snapshot both AXI directions at their common accepting edge. */
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

/* Check complete words, framing and held-beat stability. */
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

/* Return remaining bounded byte-buffer capacity. */
static size_t ring_free(const byte_ring_t *ring) {
    return BUFFER_SIZE - ring->count;
}

/* Append one byte without overwriting unread data. */
static int ring_push(byte_ring_t *ring, uint8_t byte) {
    size_t tail;
    if (ring->count == BUFFER_SIZE)
        return 0;
    tail = (ring->head + ring->count) % BUFFER_SIZE;
    ring->bytes[tail] = byte;
    ring->count++;
    return 1;
}

/* Remove one queued byte, reporting an empty buffer. */
static int ring_pop(byte_ring_t *ring, uint8_t *byte) {
    if (ring->count == 0)
        return 0;
    *byte = ring->bytes[ring->head];
    ring->head = (ring->head + 1) % BUFFER_SIZE;
    ring->count--;
    return 1;
}

/* Queue a little-endian transport word. */
static void ring_push_word(byte_ring_t *ring, uint32_t word) {
    unsigned shift;
    for (shift = 0; shift < 32; shift += 8)
        ring_push(ring, (uint8_t)(word >> shift));
}

/* Assemble one little-endian transport word. */
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

/* Read a known scalar or word signal. */
static uint32_t get_u32(vpiHandle signal) {
    s_vpi_value value;
    value.format = vpiIntVal;
    vpi_get_value(signal, &value);
    return (uint32_t)value.value.integer;
}

/* Read the least significant bit of a known signal. */
static int get_bit(vpiHandle signal) {
    return (get_u32(signal) & 1U) != 0;
}

/* Drive one public word port. */
static void put_u32(vpiHandle signal, uint32_t word) {
    s_vpi_value value;
    value.format = vpiIntVal;
    value.value.integer = (PLI_INT32)word;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

/* Drive a known public handshake or framing bit. */
static void put_bit(vpiHandle signal, int bit) {
    s_vpi_value value;
    value.format = vpiScalarVal;
    value.value.scalar = bit ? vpi1 : vpi0;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

/* Read host bytes without blocking the simulator. */
static void pump_input(axis_endpoint_t *endpoint) {
    uint8_t buffer[4096];
    ssize_t count;
    size_t index;

    if (!endpoint->enabled)
        return;

    while (ring_free(&endpoint->input_bytes) >= sizeof(buffer)) {
        count = read(endpoint->fd_host_to_sim, buffer, sizeof(buffer));
        if (count > 0) {
            vpi_printf("partition_sim_bridge[%s]: read %ld host byte(s)\n",
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

/* Flush only bytes accepted on the public output handshake. */
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

/* Hold a word until accepted; derive TLAST from the routed byte protocol. */
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
    vpi_printf("partition_sim_bridge[%s]: input beat %u data=%08x last=%d\n",
               endpoint->name, ++endpoint->input_beat_number, word, endpoint->s_last);
}

/* Start a fresh transport epoch without dropping queued initial input. */
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
    endpoint->output_armed = 1;
}

/* Retire accepted transfers and prepare the next bounded transfer. */
static void step_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled || bridge_failed)
        return;

    if (endpoint->s_sample.valid.value && endpoint->s_sample.ready.value) {
        vpi_printf("partition_sim_bridge[%s]: cycle=%llu accepted input beat %u\n",
                   endpoint->name, (unsigned long long)cycle_number,
                   endpoint->input_beat_number);
        endpoint->output_armed = 1;
        endpoint->s_valid = 0;
        endpoint->s_last = 0;
    }

    if (endpoint->m_sample.valid.value && endpoint->m_sample.ready.value) {
        if (endpoint->output_armed) {
            vpi_printf(
                "partition_sim_bridge[%s]: cycle=%llu output beat %u data=%08x\n",
                endpoint->name, (unsigned long long)cycle_number,
                ++endpoint->output_beat_number, endpoint->m_sample.data.value);
            if (ring_free(&endpoint->output_bytes) >= 4)
                ring_push_word(&endpoint->output_bytes, endpoint->m_sample.data.value);
            else
                bridge_fail("%s internal output buffer overflow",
                           endpoint->name);
        } else {
            vpi_printf("partition_sim_bridge[%s]: discarded pre-request output %08x\n",
                       endpoint->name, endpoint->m_sample.data.value);
        }
    }

    pump_output(endpoint);
    endpoint->m_ready = ring_free(&endpoint->output_bytes) >= 4;
    load_input_beat(endpoint);
}

/* Publish prepared values outside the sampling phase. */
static void apply_drives(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;
    put_u32(endpoint->h_s_data, endpoint->s_data);
    put_u32(endpoint->h_s_keep, 0xf);
    put_bit(endpoint->h_s_valid, endpoint->s_valid);
    put_bit(endpoint->h_s_last, endpoint->s_last);
    put_bit(endpoint->h_m_ready, endpoint->m_ready);
}

/* Schedule work after the current RTL update phase. */
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

/* Resolve one explicitly named public testbench signal. */
static vpiHandle find_signal(const char *name) {
    char path[PATH_SIZE];
    snprintf(path, sizeof(path), "%s.%s", hierarchy_root, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

/* Reject absent or incorrectly sized public ports. */
static vpiHandle require_signal(const char *name, int width) {
    vpiHandle signal = find_signal(name);
    if (!signal)
        bridge_fail("missing signal %s.%s", hierarchy_root, name);
    else if (vpi_get(vpiSize, signal) != width)
        bridge_fail("signal %s.%s must be %d bits (got %d)",
                    hierarchy_root, name, width, vpi_get(vpiSize, signal));
    return signal;
}

/* Bind the ten public AXI signals of one endpoint. */
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

/* Create and open a fresh nonblocking FIFO for this isolated run. */
static int open_fifo(const char *path) {
    int fd;
    if (unlink(path) != 0 && errno != ENOENT) {
        vpi_printf("partition_sim_bridge: cannot remove %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (mkfifo(path, 0600) != 0) {
        vpi_printf("partition_sim_bridge: cannot create %s: %s\n", path, strerror(errno));
        return -1;
    }
    fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0)
        vpi_printf("partition_sim_bridge: cannot open %s: %s\n", path, strerror(errno));
    return fd;
}

/* Open the host-facing byte FIFOs for one endpoint. */
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

/* Acknowledgment of an out-of-band physical reset action, never application I/O. */
static void acknowledge(const char *name) {
    FILE *file = fopen(name, "w");
    if (!file) { bridge_fail("cannot acknowledge %s: %s", name, strerror(errno)); return; }
    fclose(file);
}

/* Isolate every old transport before releasing blocked OS readers/writers.
 * Keep the FIFO pathnames unchanged until BEAM confirms all old leases closed.
 * Only public word/byte transport state is observed, never generated state. */
static void retire_transport(void) {
    FILE *file = fopen("retired-transport.json", "w");
    if (!file) { bridge_fail("cannot record retired transport"); return; }
    fprintf(file, "[");
    for (unsigned i = 0; i < 4; ++i) {
        axis_endpoint_t *endpoint = &endpoints[i];
        fprintf(file, "%s{\"stream\":\"%s\",\"input_bytes\":%zu,\"output_bytes\":%zu,"
                "\"input_word\":%d,\"partial_input\":%s,\"partial_output\":%s}",
                i ? "," : "", endpoint->name, endpoint->input_bytes.count,
                endpoint->output_bytes.count, endpoint->s_valid,
                axis_finish(&endpoint->s_monitor) ? "true" : "false",
                axis_finish(&endpoint->m_monitor) ? "true" : "false");
        close(endpoint->fd_host_to_sim);
        close(endpoint->fd_sim_to_host);
        endpoint->fd_host_to_sim = endpoint->fd_sim_to_host = -1;
        endpoint->input_bytes = (byte_ring_t) {0};
        endpoint->output_bytes = (byte_ring_t) {0};
        reset_endpoint(endpoint);
    }
    fprintf(file, "]\n");
    fclose(file);
    transport_retired = 1;
    acknowledge("transport_held");
}

/* Fresh FIFO objects discard kernel-buffered bytes from the retired activation.
 * The host publishes reset_release only after every raw descriptor closes. */
static void reopen_transport(void) {
    if (access("reset_release", F_OK) || access("leases_closed", F_OK)) {
        bridge_fail("reset released before transport barrier"); return;
    }
    for (unsigned i = 0; i < 4; ++i) {
        axis_endpoint_t *endpoint = &endpoints[i];
        if (!open_endpoint_fifos(endpoint, transport_directory, endpoint->name)) {
            bridge_fail("cannot reopen %s", endpoint->name); return;
        }
        reset_endpoint(endpoint);
    }
    transport_retired = 0;
    acknowledge("transport_reopened");
}


/* Drive between accepting edges; sample before nonblocking register updates. */
static PLI_INT32 cb_readwrite(p_cb_data cb) {
    (void)cb;
    if (!bridge_failed)
        for (unsigned i = 0; i < 4; ++i) apply_drives(&endpoints[i]);
    return 0;
}

/* Advance byte queues only against public ready/valid handshakes. */
static PLI_INT32 cb_readonly(p_cb_data cb) {
    (void)cb;
    if (bridge_failed || !get_bit(h_clk)) return 0;
    axis_value_t resetn = sample_value(h_resetn);
    if (resetn.unknown) { bridge_fail("unknown resetn"); return 0; }
    if (!resetn.value) {
        if (transport_active) {
            if (access("reset_hold", F_OK)) { bridge_fail("unannounced live reset"); return 0; }
            retire_transport();
            transport_active = 0;
        }
        for (unsigned i = 0; i < 4; ++i) reset_endpoint(&endpoints[i]);
        cycle_number = 0;
        return 0;
    }
    if (transport_retired) {
        reopen_transport();
        transport_active = 1;
        return 0;
    }
    transport_active = 1;
    for (unsigned i = 0; i < 4; ++i) {
        axis_endpoint_t *endpoint = &endpoints[i];
        pump_input(endpoint);
        pump_output(endpoint);
        check_endpoint(endpoint, 0);
        step_endpoint(endpoint);
    }
    cycle_number++;
    return 0;
}

/* A completed witness may abort ongoing status output, but not a host command. */
static PLI_INT32 cb_end(p_cb_data cb) {
    (void)cb;
    for (unsigned i = 0; i < 4; ++i) {
        axis_endpoint_t *endpoint = &endpoints[i];
        if (axis_finish(&endpoint->s_monitor) || endpoint->s_valid || endpoint->input_bytes.count)
            bridge_fail("%s: unfinished host command at shutdown", endpoint->name);
        close(endpoint->fd_host_to_sim);
        close(endpoint->fd_sim_to_host);
    }
    return 0;
}

/* The shared host clock is the only VPI sampling domain; RTL supplies CDC. */
static PLI_INT32 cb_clock(p_cb_data cb) {
    (void)cb;
    if (bridge_failed) return 0;
    if (get_bit(h_clk))
        for (unsigned i = 0; i < 4; ++i) sample_endpoint(&endpoints[i]);
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    return 0;
}

/* Bind explicitly named public ports and create fresh per-run OS FIFOs. */
static PLI_INT32 cb_start(p_cb_data cb) {
    (void)cb;
    const char *directory = getenv("ERL_HLS_SIM_DIR");
    transport_directory = directory;
    hierarchy_root = getenv("ERL_HLS_SIM_TOP");
    if (!directory || !hierarchy_root) { bridge_fail("missing simulation paths"); return 0; }
    const char *names[4] = {"app", "debug", "data0", "data1"};
    const char *inputs[4] = {"s_axis", "s_dbg", "s_app0", "s_app1"};
    const char *outputs[4] = {"m_axis", "m_dbg", "m_app0", "m_app1"};
    h_clk = require_signal("clk", 1);
    h_resetn = require_signal("resetn", 1);
    for (unsigned i = 0; i < 4 && !bridge_failed; ++i) {
        endpoints[i].name = names[i];
        endpoints[i].enabled = 1;
        if (!find_endpoint_signals(&endpoints[i], inputs[i], outputs[i]) ||
            !open_endpoint_fifos(&endpoints[i], directory, names[i])) {
            bridge_fail("cannot open %s", names[i]); return 0;
        }
        reset_endpoint(&endpoints[i]);
    }
    if (bridge_failed) return 0;
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    s_cb_data clock_cb = { .reason = cbValueChange, .cb_rtn = cb_clock, .obj = h_clk };
    vpi_register_cb(&clock_cb);
    s_cb_data end_cb = { .reason = cbEndOfSimulation, .cb_rtn = cb_end };
    vpi_register_cb(&end_cb);
    return 0;
}

/* Register transport callbacks when Icarus loads the adapter. */
static void entry_point(void) {
    s_cb_data cb = { .reason = cbStartOfSimulation, .cb_rtn = cb_start };
    vpi_register_cb(&cb);
}

void (*vlog_startup_routines[])(void) = {entry_point, 0};
