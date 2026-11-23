#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <time.h>

/* Word offsets in the version-1 register page. */
enum { PROBE_ID, PROBE_VERSION, PROBE_SCRATCH, PROBE_CYCLES, PROBE_WRITES };
#define PROBE_IDENTITY UINT32_C(0x45524c48)

/* Ordered 32-bit register access; wait advances time without changing registers. */
struct probe_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    void (*wait)(void *);
};

/* Successful test accounting, including the final scratch restoration write. */
struct probe_result { uint32_t writes, cycles; };

/* Verify identity before writes; restore scratch on every subsequent exit.
 * Requires exclusive access. Return NULL on success, otherwise a static error.
 * Counter arithmetic wraps modulo 2^32. MMIO bus faults/timeouts are OS concerns.
 */
static const char *probe_run(struct probe_io io, struct probe_result *result) {
    if (io.read(io.context, PROBE_ID) != PROBE_IDENTITY ||
        io.read(io.context, PROBE_VERSION) != 1)
        return "unexpected identity/ABI; no writes attempted";
    uint32_t original = io.read(io.context, PROBE_SCRATCH);
    uint32_t writes_before = io.read(io.context, PROBE_WRITES);
    uint32_t cycles_before = io.read(io.context, PROBE_CYCLES);
    const uint32_t mixed[] = {0, UINT32_MAX, UINT32_C(0x01234567), UINT32_C(0x89abcdef)};
    const char *error = NULL;
    for (unsigned i = 0; i < 36; ++i) {
        uint32_t value = i < 4 ? mixed[i] : UINT32_C(1) << (i - 4);
        io.write(io.context, PROBE_SCRATCH, value);
        if (io.read(io.context, PROBE_SCRATCH) != value) {
            error = "scratch readback mismatch";
            break;
        }
    }
    if (!error) {
        io.wait(io.context);
        result->cycles = io.read(io.context, PROBE_CYCLES) - cycles_before;
        if (!result->cycles) error = "fabric cycle counter did not advance";
    }
    io.write(io.context, PROBE_SCRATCH, original);
    if (io.read(io.context, PROBE_SCRATCH) != original) return "scratch restore failed";
    if (error) return error;
    result->writes = io.read(io.context, PROBE_WRITES) - writes_before;
    return result->writes == 37 ? NULL : "unexpected write count (interference, reset or lost/duplicate write)";
}

#ifndef PROBE_TEST
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

/* Device memory still requires explicit ordering with respect to the processor. */
static void mmio_barrier(void) {
    __sync_synchronize();
}

/* Volatile aligned uint32_t prevents byte-wise accesses from generic packers. */
static uint32_t mmio_read(void *context, unsigned word) {
    volatile uint32_t *registers = context;
    mmio_barrier();
    uint32_t value = registers[word];
    mmio_barrier();
    return value;
}

/* Commit one word, then order it before any following register read. */
static void mmio_write(void *context, unsigned word, uint32_t value) {
    volatile uint32_t *registers = context;
    mmio_barrier();
    registers[word] = value;
    mmio_barrier();
}

/* Wait for the enabled FCLK counter, retrying only an interrupted sleep. */
static void mmio_wait(void *context) {
    (void)context;
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 10000000};
    while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
}

/* Map the first UIO page. Clock/reset/FPGA configuration is a prerequisite. */
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s /dev/uioN\n", argv[0]);
        return 2;
    }
    int descriptor = open(argv[1], O_RDWR | O_SYNC);
    if (descriptor < 0) { perror("open UIO"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (mapping == MAP_FAILED) { perror("mmap UIO"); close(descriptor); return 1; }
    struct probe_io io = {mapping, mmio_read, mmio_write, mmio_wait};
    struct probe_result result = {0};
    const char *error = probe_run(io, &result);
    if (error) fprintf(stderr, "%s\n", error);
    else printf("PASS: identity 0x%08x, ABI 1, %u writes, %u FCLK cycles; scratch restored\n",
                PROBE_IDENTITY, result.writes, result.cycles);
    munmap(mapping, 4096);
    close(descriptor);
    return error ? 1 : 0;
}
#endif
