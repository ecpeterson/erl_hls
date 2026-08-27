#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vpi_user.h"

#define BUFFER_SIZE 65536
#define PATH_SIZE 4096

typedef struct {
    uint8_t bytes[BUFFER_SIZE];
    size_t head;
    size_t count;
} byte_ring_t;

typedef struct {
    const char *name;
    vpiHandle h_s_data;
    vpiHandle h_s_valid;
    vpiHandle h_s_ready;
    vpiHandle h_s_last;
    vpiHandle h_m_data;
    vpiHandle h_m_valid;
    vpiHandle h_m_ready;
    int fd_host_to_sim;
    int fd_sim_to_host;
    byte_ring_t input_bytes;
    byte_ring_t output_bytes;
    uint32_t s_data;
    int s_valid;
    int s_last;
    int s_ready_sample;
    int m_ready;
    unsigned input_payload_words;
    unsigned input_phase;
    unsigned input_beat_number;
    unsigned output_beat_number;
    int output_armed;
} axis_endpoint_t;

static vpiHandle h_clk;
static vpiHandle h_resetn;
static axis_endpoint_t app_endpoint;
static axis_endpoint_t debug_endpoint;

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
            vpi_printf("xls_sim_bridge[%s]: input FIFO read failed: %s\n",
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
        vpi_printf("xls_sim_bridge[%s]: output FIFO write failed: %s\n",
                   endpoint->name, strerror(errno));
    }
}

static void load_input_beat(axis_endpoint_t *endpoint) {
    uint32_t word;

    if (endpoint->s_valid || endpoint->input_bytes.count < 4)
        return;

    word = ring_pop_word(&endpoint->input_bytes);
    endpoint->s_data = word;
    endpoint->s_valid = 1;
    if (endpoint->input_phase == 0) {
        endpoint->s_last = 0;
        endpoint->input_phase = 1;
    } else if (endpoint->input_phase == 1) {
        endpoint->input_payload_words = word & 0xffU;
        endpoint->s_last = endpoint->input_payload_words == 0;
        endpoint->input_phase = endpoint->s_last ? 0 : 2;
    } else {
        endpoint->s_last = endpoint->input_payload_words == 1;
        endpoint->input_payload_words--;
        if (endpoint->s_last)
            endpoint->input_phase = 0;
    }
    vpi_printf("xls_sim_bridge[%s]: input beat %u data=%08x last=%d\n",
               endpoint->name, ++endpoint->input_beat_number, word, endpoint->s_last);
}

static void reset_endpoint(axis_endpoint_t *endpoint) {
    endpoint->s_data = 0;
    endpoint->s_valid = 0;
    endpoint->s_last = 0;
    endpoint->m_ready = 1;
    endpoint->input_payload_words = 0;
    endpoint->input_phase = 0;
    endpoint->output_armed = 0;
}

static void step_endpoint(axis_endpoint_t *endpoint) {
    if (endpoint->s_valid && endpoint->s_ready_sample) {
        vpi_printf("xls_sim_bridge[%s]: accepted input beat %u\n",
                   endpoint->name, endpoint->input_beat_number);
        if (endpoint->s_last)
            endpoint->output_armed = 1;
        endpoint->s_valid = 0;
        endpoint->s_last = 0;
    }

    if (get_bit(endpoint->h_m_valid) && endpoint->m_ready) {
        if (endpoint->output_armed) {
            vpi_printf("xls_sim_bridge[%s]: output beat %u data=%08x\n",
                       endpoint->name, ++endpoint->output_beat_number,
                       get_u32(endpoint->h_m_data));
            if (ring_free(&endpoint->output_bytes) >= 4)
                ring_push_word(&endpoint->output_bytes, get_u32(endpoint->h_m_data));
            else
                vpi_printf("xls_sim_bridge[%s]: internal output buffer overflow\n",
                           endpoint->name);
        } else {
            vpi_printf("xls_sim_bridge[%s]: discarded pre-request output %08x\n",
                       endpoint->name, get_u32(endpoint->h_m_data));
        }
    }

    pump_output(endpoint);
    endpoint->m_ready = ring_free(&endpoint->output_bytes) >= 4;
    load_input_beat(endpoint);
}

static void apply_drives(axis_endpoint_t *endpoint) {
    put_u32(endpoint->h_s_data, endpoint->s_data);
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

static PLI_INT32 cb_readwrite(p_cb_data cb) {
    (void)cb;
    apply_drives(&app_endpoint);
    apply_drives(&debug_endpoint);
    return 0;
}

static PLI_INT32 cb_readonly(p_cb_data cb) {
    (void)cb;
    if (!get_bit(h_clk)) {
        app_endpoint.s_ready_sample = get_bit(app_endpoint.h_s_ready);
        debug_endpoint.s_ready_sample = get_bit(debug_endpoint.h_s_ready);
        return 0;
    }

    pump_input(&app_endpoint);
    pump_input(&debug_endpoint);
    pump_output(&app_endpoint);
    pump_output(&debug_endpoint);

    if (!get_bit(h_resetn)) {
        reset_endpoint(&app_endpoint);
        reset_endpoint(&debug_endpoint);
        return 0;
    }

    step_endpoint(&app_endpoint);
    step_endpoint(&debug_endpoint);
    return 0;
}

static PLI_INT32 cb_clk_change(p_cb_data cb) {
    (void)cb;
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    return 0;
}

static vpiHandle find_signal(const char *name) {
    char path[PATH_SIZE];
    snprintf(path, sizeof(path), "regsvc_bridge_tb.%s", name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static int find_endpoint_signals(
    axis_endpoint_t *endpoint,
    const char *s_prefix,
    const char *m_prefix
) {
    char name[128];
#define FIND(handle, prefix, suffix) do { \
    snprintf(name, sizeof(name), "%s_%s", prefix, suffix); \
    endpoint->handle = find_signal(name); \
} while (0)
    FIND(h_s_data, s_prefix, "tdata");
    FIND(h_s_valid, s_prefix, "tvalid");
    FIND(h_s_ready, s_prefix, "tready");
    FIND(h_s_last, s_prefix, "tlast");
    FIND(h_m_data, m_prefix, "tdata");
    FIND(h_m_valid, m_prefix, "tvalid");
    FIND(h_m_ready, m_prefix, "tready");
#undef FIND
    return endpoint->h_s_data && endpoint->h_s_valid && endpoint->h_s_ready &&
           endpoint->h_s_last && endpoint->h_m_data && endpoint->h_m_valid &&
           endpoint->h_m_ready;
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
    const char *directory = getenv("ERL_XLS_SIM_DIR");
    s_cb_data clock_cb;
    (void)cb;

    if (!directory) {
        vpi_printf("xls_sim_bridge: ERL_XLS_SIM_DIR is not set\n");
        return 0;
    }

    memset(&app_endpoint, 0, sizeof(app_endpoint));
    memset(&debug_endpoint, 0, sizeof(debug_endpoint));
    app_endpoint.name = "app";
    debug_endpoint.name = "debug";
    h_clk = find_signal("clk");
    h_resetn = find_signal("resetn");
    if (!h_clk || !h_resetn ||
        !find_endpoint_signals(&app_endpoint, "s_axis", "m_axis") ||
        !find_endpoint_signals(&debug_endpoint, "s_dbg", "m_dbg")) {
        vpi_printf("xls_sim_bridge: failed to find regsvc_bridge_tb AXIS signals\n");
        return 0;
    }

    if (!open_endpoint_fifos(&app_endpoint, directory, "app") ||
        !open_endpoint_fifos(&debug_endpoint, directory, "debug")) {
        vpi_printf("xls_sim_bridge: failed to open transport FIFOs\n");
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
    vpi_printf("xls_sim_bridge: application and debug endpoints listening in %s\n",
               directory);
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
