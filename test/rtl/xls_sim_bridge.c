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

typedef struct {
    uint8_t bytes[BUFFER_SIZE];
    size_t head;
    size_t count;
} byte_ring_t;

typedef struct {
    uint32_t s_data;
    int s_valid;
    int s_last;
    int m_ready;
} drives_t;

static vpiHandle h_clk;
static vpiHandle h_resetn;
static vpiHandle h_s_data;
static vpiHandle h_s_valid;
static vpiHandle h_s_ready;
static vpiHandle h_s_last;
static vpiHandle h_m_data;
static vpiHandle h_m_valid;
static vpiHandle h_m_ready;

static int fd_host_to_sim = -1;
static int fd_sim_to_host = -1;
static byte_ring_t input_bytes;
static byte_ring_t output_bytes;
static drives_t drv;
static unsigned input_payload_words;
static unsigned input_beat_number;
static unsigned output_beat_number;
static int output_armed;

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

static void pump_input(void) {
    uint8_t buffer[4096];
    ssize_t count;
    size_t index;

    while (ring_free(&input_bytes) >= sizeof(buffer)) {
        count = read(fd_host_to_sim, buffer, sizeof(buffer));
        if (count > 0) {
            vpi_printf("xls_sim_bridge: read %ld host byte(s)\n", (long)count);
            for (index = 0; index < (size_t)count; index++)
                ring_push(&input_bytes, buffer[index]);
        } else if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        } else if (errno != EINTR) {
            vpi_printf("xls_sim_bridge: input FIFO read failed: %s\n", strerror(errno));
            return;
        }
    }
}

static void pump_output(void) {
    uint8_t buffer[4096];
    size_t count = output_bytes.count;
    size_t index;
    ssize_t written;

    if (count > sizeof(buffer))
        count = sizeof(buffer);
    for (index = 0; index < count; index++)
        buffer[index] = output_bytes.bytes[(output_bytes.head + index) % BUFFER_SIZE];

    if (count == 0)
        return;
    written = write(fd_sim_to_host, buffer, count);
    if (written > 0) {
        output_bytes.head = (output_bytes.head + (size_t)written) % BUFFER_SIZE;
        output_bytes.count -= (size_t)written;
    } else if (written < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
        vpi_printf("xls_sim_bridge: output FIFO write failed: %s\n", strerror(errno));
    }
}

static void load_input_beat(void) {
    uint32_t word;

    if (drv.s_valid || input_bytes.count < 4)
        return;

    word = ring_pop_word(&input_bytes);
    drv.s_data = word;
    drv.s_valid = 1;
    if (input_payload_words == 0) {
        input_payload_words = word & 0xffU;
        drv.s_last = input_payload_words == 0;
    } else {
        drv.s_last = input_payload_words == 1;
        input_payload_words--;
    }
    vpi_printf("xls_sim_bridge: input beat %u data=%08x last=%d\n",
               ++input_beat_number, word, drv.s_last);
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
    put_u32(h_s_data, drv.s_data);
    put_bit(h_s_valid, drv.s_valid);
    put_bit(h_s_last, drv.s_last);
    put_bit(h_m_ready, drv.m_ready);
    return 0;
}

static PLI_INT32 cb_readonly(p_cb_data cb) {
    (void)cb;
    if (!get_bit(h_clk))
        return 0;

    pump_input();
    pump_output();

    if (!get_bit(h_resetn)) {
        drv.s_data = 0;
        drv.s_valid = 0;
        drv.s_last = 0;
        drv.m_ready = 1;
        input_payload_words = 0;
        output_armed = 0;
        return 0;
    }

    if (drv.s_valid && get_bit(h_s_ready)) {
        vpi_printf("xls_sim_bridge: accepted input beat %u\n", input_beat_number);
        if (drv.s_last)
            output_armed = 1;
        drv.s_valid = 0;
        drv.s_last = 0;
    }

    if (get_bit(h_m_valid) && drv.m_ready) {
        if (output_armed) {
            vpi_printf("xls_sim_bridge: output beat %u data=%08x\n",
                       ++output_beat_number, get_u32(h_m_data));
            if (ring_free(&output_bytes) >= 4)
                ring_push_word(&output_bytes, get_u32(h_m_data));
            else
                vpi_printf("xls_sim_bridge: internal output buffer overflow\n");
        } else {
            vpi_printf("xls_sim_bridge: discarded pre-request output %08x\n",
                       get_u32(h_m_data));
        }
    }

    pump_output();
    drv.m_ready = ring_free(&output_bytes) >= 4;
    load_input_beat();
    return 0;
}

static PLI_INT32 cb_clk_change(p_cb_data cb) {
    (void)cb;
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    return 0;
}

static int find_signals(void) {
#define FIND(handle, name) handle = vpi_handle_by_name((PLI_BYTE8 *)"regsvc_bridge_tb." name, NULL)
    FIND(h_clk, "clk");
    FIND(h_resetn, "resetn");
    FIND(h_s_data, "s_axis_tdata");
    FIND(h_s_valid, "s_axis_tvalid");
    FIND(h_s_ready, "s_axis_tready");
    FIND(h_s_last, "s_axis_tlast");
    FIND(h_m_data, "m_axis_tdata");
    FIND(h_m_valid, "m_axis_tvalid");
    FIND(h_m_ready, "m_axis_tready");
#undef FIND
    return h_clk && h_resetn && h_s_data && h_s_valid && h_s_ready && h_s_last &&
           h_m_data && h_m_valid && h_m_ready;
}

static int open_fifo(const char *path) {
    if (unlink(path) != 0 && errno != ENOENT) {
        vpi_printf("xls_sim_bridge: cannot remove %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (mkfifo(path, 0600) != 0) {
        vpi_printf("xls_sim_bridge: cannot create %s: %s\n", path, strerror(errno));
        return -1;
    }
    return open(path, O_RDWR | O_NONBLOCK);
}

static PLI_INT32 cb_start_of_sim(p_cb_data cb) {
    const char *directory = getenv("ERL_XLS_SIM_DIR");
    char host_to_sim[4096];
    char sim_to_host[4096];
    s_cb_data clock_cb;
    (void)cb;

    if (!directory) {
        vpi_printf("xls_sim_bridge: ERL_XLS_SIM_DIR is not set\n");
        return 0;
    }
    if (!find_signals()) {
        vpi_printf("xls_sim_bridge: failed to find regsvc_bridge_tb AXIS signals\n");
        return 0;
    }

    snprintf(host_to_sim, sizeof(host_to_sim), "%s/app_tx", directory);
    snprintf(sim_to_host, sizeof(sim_to_host), "%s/app_rx", directory);
    fd_host_to_sim = open_fifo(host_to_sim);
    fd_sim_to_host = open_fifo(sim_to_host);
    if (fd_host_to_sim < 0 || fd_sim_to_host < 0) {
        vpi_printf("xls_sim_bridge: failed to open transport FIFOs\n");
        return 0;
    }

    memset(&drv, 0, sizeof(drv));
    drv.m_ready = 1;
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);

    memset(&clock_cb, 0, sizeof(clock_cb));
    clock_cb.reason = cbValueChange;
    clock_cb.cb_rtn = cb_clk_change;
    clock_cb.obj = h_clk;
    vpi_register_cb(&clock_cb);
    vpi_printf("xls_sim_bridge: listening in %s\n", directory);
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
