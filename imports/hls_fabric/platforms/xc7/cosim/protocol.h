/* Local simulator RPC: eight little-endian u32s per request/reply, one in flight.
 * Request: magic, version, op, sequence, address, data, amount, zero.
 * Reply: magic, version, op|REPLY, sequence, AXI response, data, IRQ bitmap, cycles.
 * IRQ bits 0/1 are the independent application/debug mailbox levels.
 * READ/WRITE amount is four bytes; STEP amount is 1..4096 clock cycles.
 * RESET is permitted only between transactions and discards mailbox ownership.
 */
#ifndef HLS_COSIM_PROTOCOL_H
#define HLS_COSIM_PROTOCOL_H
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <sys/socket.h>
#include <unistd.h>

#define COSIM_MAGIC 0x484c5343u
#define COSIM_VERSION 2u
#define COSIM_REPLY 0x80000000u
#define COSIM_READ 1u
#define COSIM_WRITE 2u
#define COSIM_STEP 3u
#define COSIM_RESET 4u
#define COSIM_BYTES 32u

/* Decode a word without host-endian or alignment assumptions. */
static inline uint32_t cosim_get(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* Encode one word into a caller-owned four-byte field. */
static inline void cosim_put(uint8_t *p, uint32_t value)
{
    for (unsigned i = 0; i < 4; i++) p[i] = value >> (8*i);
}

/* Copy exactly one packet, tolerating fragmentation/EINTR but bounding silence.
 * Return 1 on success, 0 on clean EOF, -1 on error (including partial EOF).
 */
static inline int cosim_transfer(int fd, uint8_t *packet, int sending)
{
    size_t offset = 0;
    while (offset < COSIM_BYTES) {
        struct pollfd wait = {.fd = fd, .events = sending ? POLLOUT : POLLIN};
        int ready = poll(&wait, 1, 20000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) { if (!ready) errno = ETIMEDOUT; return -1; }
        int flags = 0;
#ifdef MSG_NOSIGNAL
        flags = MSG_NOSIGNAL;
#endif
        ssize_t n = sending ? send(fd, packet + offset, COSIM_BYTES - offset, flags) :
                              recv(fd, packet + offset, COSIM_BYTES - offset, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return -1;
        if (!n) { if (!offset) return 0; errno = EPROTO; return -1; }
        offset += (size_t)n;
    }
    return 1;
}
#endif
