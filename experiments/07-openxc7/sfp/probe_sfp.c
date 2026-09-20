#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>

/* Word offsets in the SFP7 ABI-1 page at GP0 0x40000000. */
enum { SFP_ID, SFP_ABI, SFP_CHALLENGE, SFP_CYCLES, SFP_WRITES,
       SFP_RAW, SFP_FRAMES, SFP_DIVISOR };

/* Ordered word I/O; wait must delay at least 1 ms at a 25-MHz FCLK. */
struct sfp_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    void (*wait)(void *);
};

/* Check two distinct echoes and an advancing transaction count before returning
 * one atomic status word. Requires exclusive access; always restores challenge
 * after accepting the identity. A valid marker is not a CRC or firmware ID.
 */
static const char *sfp_probe(struct sfp_io io, uint32_t *status) {
    if (io.read(io.context, SFP_ID) != UINT32_C(0x53465037) ||
        io.read(io.context, SFP_ABI) != 1)
        return "unexpected identity/ABI; no writes attempted";
    uint32_t original = io.read(io.context, SFP_CHALLENGE);
    const uint8_t challenges[] = {0x5a, 0xa5};
    const char *error = NULL;
    for (unsigned i = 0; i < 2; ++i) {
        uint32_t before = io.read(io.context, SFP_FRAMES);
        io.write(io.context, SFP_CHALLENGE, challenges[i]);
        unsigned attempt;
        for (attempt = 0; attempt < 20; ++attempt) {
            io.wait(io.context);
            *status = io.read(io.context, SFP_RAW);
            if ((*status & UINT32_C(0xf00000ff)) == (UINT32_C(0xa0000000) | challenges[i]) &&
                io.read(io.context, SFP_FRAMES) != before) break;
        }
        if (attempt == 20) {
            error = "no fresh RGPIO echo; check FCLK, carrier firmware, VCCIOA and wiring";
            break;
        }
    }
    io.write(io.context, SFP_CHALLENGE, original);
    return error;
}

#ifndef SFP_TEST
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* Ordered, aligned accesses to UIO's device-memory mapping. */
static uint32_t sfp_read(void *context, unsigned word) {
    volatile uint32_t *registers = context;
    __sync_synchronize();
    uint32_t value = registers[word];
    __sync_synchronize();
    return value;
}

/* A write changes only the probe's non-activating echo challenge. */
static void sfp_write(void *context, unsigned word, uint32_t value) {
    volatile uint32_t *registers = context;
    __sync_synchronize();
    registers[word] = value;
    __sync_synchronize();
}

/* Allow several 128-us RGPIO frames for the round-trip challenge. */
static void sfp_wait(void *context) {
    (void)context;
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000};
    while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
}

/* Report carrier communication and SFP status through the probe's UIO page.
 * FPGA configuration and 25-MHz FCLK initialization precede this operation.
 */
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s /dev/uioN\n", argv[0]); return 2; }
    int fd = open(argv[1], O_RDWR | O_SYNC);
    if (fd < 0) { perror("open UIO"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) { perror("mmap UIO"); close(fd); return 1; }
    struct sfp_io io = {mapping, sfp_read, sfp_write, sfp_wait};
    uint32_t status = 0;
    const char *error = sfp_probe(io, &status);
    if (error) fprintf(stderr, "%s (raw=%08x)\n", error, status);
    else printf("RGPIO responding: raw=%08x present=%u los=%u tx_fault=%u\n",
                status, !(status & (1u << 18)), !!(status & (1u << 17)), !!(status & (1u << 19)));
    munmap(mapping, 4096);
    close(fd);
    return error ? 1 : 0;
}
#endif
