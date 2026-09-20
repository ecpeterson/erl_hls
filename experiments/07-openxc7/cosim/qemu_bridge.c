/* SPDX-License-Identifier: GPL-2.0-or-later
 * Functional PS/PL bridge for QEMU's xilinx-zynq-a9 machine. No mailbox state
 * or packet bytes are emulated here: CPU and DMA accesses reach the RTL.
 */
#include "qemu/osdep.h"
#include "qemu/error-report.h"
#include "qemu/sockets.h"
#include "qemu/timer.h"
#include "system/reset.h"
#include "hls_cosim.h"
#include "hls_cosim_protocol.h"
#include <sys/un.h>

/* One serialized connection, with a virtual timer for progress while Linux sleeps. */
typedef struct HlsCosim {
    MemoryRegion mmio;
    QEMUTimer *timer;
    qemu_irq irq;
    int fd;
    uint32_t sequence;
    bool running;
} HlsCosim;

/* Protocol loss is a failed experiment; never return invented device contents. */
static void bridge_failed(const char *reason)
{
    error_report("HLS co-simulation: %s (%s)", reason, strerror(errno));
    exit(EXIT_FAILURE);
}

/* Complete one transaction before updating the level IRQ and returning its result. */
static MemTxResult bridge_rpc(HlsCosim *s, uint32_t op, uint32_t address,
                             uint32_t value, uint32_t amount, uint64_t *data)
{
    uint8_t packet[COSIM_BYTES] = {0};
    uint32_t sequence = ++s->sequence;
    cosim_put(packet, COSIM_MAGIC);
    cosim_put(packet + 4, COSIM_VERSION);
    cosim_put(packet + 8, op);
    cosim_put(packet + 12, sequence);
    cosim_put(packet + 16, address);
    cosim_put(packet + 20, value);
    cosim_put(packet + 24, amount);
    if (cosim_transfer(s->fd, packet, 1) != 1 ||
        cosim_transfer(s->fd, packet, 0) != 1) {
        bridge_failed("disconnected or timed out");
    }
    if (cosim_get(packet) != COSIM_MAGIC || cosim_get(packet + 4) != COSIM_VERSION ||
        cosim_get(packet + 8) != (op | COSIM_REPLY) ||
        cosim_get(packet + 12) != sequence || cosim_get(packet + 16) > 3 ||
        cosim_get(packet + 24) > 1 || cosim_get(packet + 28) > 4096) {
        errno = EPROTO;
        bridge_failed("invalid reply");
    }
    qemu_set_irq(s->irq, cosim_get(packet + 24));
    if (data) *data = cosim_get(packet + 20);
    return cosim_get(packet + 16) ? MEMTX_ERROR : MEMTX_OK;
}

/* A slow synthetic fabric clock preserves eventual progress, not board timing. */
static void bridge_tick(void *opaque)
{
    HlsCosim *s = opaque;
    bridge_rpc(s, COSIM_STEP, 0, 0, 64, NULL);
    timer_mod(s->timer, qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) + 1000000);
}

/* Avoid clocking an idle RTL model throughout Linux boot before its first access. */
static void bridge_start(HlsCosim *s)
{
    if (!s->running) {
        s->running = true;
        timer_mod(s->timer, qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) + 1000000);
    }
}

/* QEMU splits wide DMA accesses into ordered four-byte RTL bus transactions. */
static MemTxResult bridge_read(void *opaque, hwaddr offset, uint64_t *data,
                              unsigned size, MemTxAttrs attrs)
{
    HlsCosim *s = opaque;
    bridge_start(s);
    return bridge_rpc(s, COSIM_READ, 0x40000000 + offset, 0, size, data);
}

/* A write returns only after the RTL's AXI write response has been accepted. */
static MemTxResult bridge_write(void *opaque, hwaddr offset, uint64_t data,
                               unsigned size, MemTxAttrs attrs)
{
    HlsCosim *s = opaque;
    bridge_start(s);
    return bridge_rpc(s, COSIM_WRITE, 0x40000000 + offset, data, size, NULL);
}

/* CPU and DMA clients share a little-endian window with word-sized RTL accesses. */
static const MemoryRegionOps bridge_ops = {
    .read_with_attrs = bridge_read,
    .write_with_attrs = bridge_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {.min_access_size = 4, .max_access_size = 8, .unaligned = false},
    .impl = {.min_access_size = 4, .max_access_size = 4},
};

/* A whole-machine reset clears RTL ownership and stops the synthetic clock. */
static void bridge_reset(void *opaque)
{
    HlsCosim *s = opaque;
    timer_del(s->timer);
    s->running = false;
    bridge_rpc(s, COSIM_RESET, 0, 0, 0, NULL);
}

/* Map the PL window and wire its interrupt only when this experiment is requested. */
void hls_cosim_init(MemoryRegion *memory, qemu_irq irq)
{
    const char *path = getenv("HLS_COSIM_SOCKET");
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    HlsCosim *s;
    if (!path) return;
    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        bridge_failed("socket path");
    }
    s = g_new0(HlsCosim, 1);
    s->irq = irq;
    s->fd = qemu_socket(AF_UNIX, SOCK_STREAM, 0);
    strcpy(address.sun_path, path);
    if (s->fd < 0 || connect(s->fd, (struct sockaddr *)&address, sizeof(address))) {
        bridge_failed("connect");
    }
    s->timer = timer_new_ns(QEMU_CLOCK_VIRTUAL, bridge_tick, s);
    memory_region_init_io(&s->mmio, NULL, &bridge_ops, s, "hls-cosim", 0x3000);
    memory_region_add_subregion(memory, 0x40000000, &s->mmio);
    qemu_register_reset(bridge_reset, s);
}
