// GTX7 ABI-1 Linux/UIO diagnostic. Reads are passive; --run performs one bounded
// clean/injected-error/recovered PRBS check and leaves run disabled on return.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

// Word indices of the existing GP0 diagnostic page. Only CONTROL is writable.
enum { ID, ABI, CONTROL, CYCLES, WRITES, STATUS, RX_WORDS, ERRORS, TX_WORDS };

// Exclusive ordered MMIO plus a cancellable delay of at least the requested ms.
struct gtx_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    bool (*wait)(void *, unsigned);
};

// One sampled window; the RX/TX snapshots are coherent individually, not jointly.
struct gtx_window { uint32_t control, rx, tx; };

// Evidence retained before the final reset clears the hardware snapshots.
struct gtx_result { struct gtx_window clean, recovered; uint32_t forced_errors, status; };

// Require an active measurement, lock/reset completion and no latched fault.
static bool ready(uint32_t status) {
    return (status & UINT32_C(0xf177)) == UINT32_C(0x0176);
}

// Restart with zero error/clock snapshots; do not accept readiness from an old run.
static const char *start(struct gtx_io io, struct gtx_result *result) {
    io.write(io.context, CONTROL, 0);
    if (!io.wait(io.context, 2)) return "interrupted";
    result->status = io.read(io.context, STATUS);
    if ((result->status & UINT32_C(0xf107)) != 1 ||
        io.read(io.context, RX_WORDS) || io.read(io.context, TX_WORDS) || io.read(io.context, ERRORS))
        return "reset did not clear the previous attempt";
    io.write(io.context, CONTROL, 1);
    for (unsigned poll = 0; poll < 1000; ++poll) {
        if (!io.wait(io.context, 1)) return "interrupted";
        result->status = io.read(io.context, STATUS);
        if ((result->status & 7) == 7 || (result->status & 0xf000)) return "GTX startup fault";
        if (ready(result->status)) return NULL;
    }
    return "GTX startup timed out";
}

// Demand sustained clean progress and the expected 62.5/25-MHz counter ratio.
// Twenty short polls catch transient faults; unsigned subtraction permits wrap.
static const char *clean_window(struct gtx_io io, struct gtx_result *result, struct gtx_window *window) {
    uint32_t control = io.read(io.context, CYCLES);
    uint32_t rx = io.read(io.context, RX_WORDS), tx = io.read(io.context, TX_WORDS);
    for (unsigned poll = 0; poll < 20; ++poll) {
        if (!io.wait(io.context, 1)) return "interrupted";
        result->status = io.read(io.context, STATUS);
        if (!ready(result->status)) return "GTX lost readiness";
        if (io.read(io.context, ERRORS)) return "PRBS errors during clean reception";
    }
    *window = (struct gtx_window){io.read(io.context, CYCLES) - control,
        io.read(io.context, RX_WORDS) - rx, io.read(io.context, TX_WORDS) - tx};
    if (!window->control || !window->rx || !window->tx) return "stopped control or user clock";
    // Loose 10% bounds accommodate delayed snapshots; this is not frequency/BER qualification.
    uint64_t low = (uint64_t)window->control * 225, high = (uint64_t)window->control * 275;
    if ((uint64_t)window->rx * 100 < low || (uint64_t)window->rx * 100 > high ||
        (uint64_t)window->tx * 100 < low || (uint64_t)window->tx * 100 > high)
        return "user/control clock ratio differs from 62.5/25 MHz";
    return NULL;
}

// Test the current register ABI; wrong identity never writes, all started paths stop.
static const char *probe(struct gtx_io io, struct gtx_result *result) {
    memset(result, 0, sizeof(*result));
    if (io.read(io.context, ID) != UINT32_C(0x47545837) || io.read(io.context, ABI) != 1)
        return "not a GTX7 ABI-1 register bank";
    const char *error = start(io, result);
    if (!error) error = clean_window(io, result, &result->clean);
    if (!error) {
        io.write(io.context, CONTROL, 3);
        error = "forced PRBS error was not observed";
        for (unsigned poll = 0; poll < 100; ++poll) {
            if (!io.wait(io.context, 1)) { error = "interrupted"; break; }
            result->status = io.read(io.context, STATUS);
            if (!ready(result->status)) { error = "GTX fault during error injection"; break; }
            result->forced_errors = io.read(io.context, ERRORS);
            if (result->forced_errors) { error = NULL; break; }
        }
    }
    if (!error) error = start(io, result);
    if (!error) error = clean_window(io, result, &result->recovered);
    io.write(io.context, CONTROL, 0);
    return error;
}

#ifndef GTX_TEST
// Signals request orderly cleanup from ordinary code; handlers never access MMIO.
static volatile sig_atomic_t interrupted;
static void interrupt_probe(int signal_number) { (void)signal_number; interrupted = 1; }

// Order device reads against surrounding MMIO accesses.
static uint32_t read_mmio(void *context, unsigned word) {
    __sync_synchronize();
    uint32_t value = ((volatile uint32_t *)context)[word];
    __sync_synchronize();
    return value;
}

// Complete the control write before waiting or observing a resulting snapshot.
static void write_mmio(void *context, unsigned word, uint32_t value) {
    ((volatile uint32_t *)context)[word] = value;
    __sync_synchronize();
}

// Stop waiting promptly on SIGINT/SIGTERM, allowing the attempt to clear run.
static bool wait_mmio(void *context, unsigned milliseconds) {
    (void)context;
    struct timespec delay = {milliseconds / 1000, (long)(milliseconds % 1000) * 1000000};
    if (interrupted) return false;
    while (nanosleep(&delay, &delay)) {
        if (errno != EINTR || interrupted) return false;
    }
    return !interrupted;
}

// Report useful failure state and raw counters without changing the device.
static void show(struct gtx_io io) {
    uint32_t status = io.read(io.context, STATUS);
    printf("status=%08" PRIx32 " state=%u fault=%u control_cycles=%" PRIu32
           " rx_words=%" PRIu32 " tx_words=%" PRIu32 " error_cycles=%" PRIu32 "\n",
           status, status & 7, (status >> 12) & 15, io.read(io.context, CYCLES),
           io.read(io.context, RX_WORDS), io.read(io.context, TX_WORDS), io.read(io.context, ERRORS));
}

// Read by default; explicit --run owns the page until the attempt is stopped.
int main(int argc, char **argv) {
    bool run = argc == 3 && strcmp(argv[2], "--run") == 0;
    if (argc != 2 && !run) {
        fprintf(stderr, "usage: %s /dev/uioN [--run]\n", argv[0]); return 2;
    }
    int fd = open(argv[1], (run ? O_RDWR : O_RDONLY) | O_SYNC);
    if (fd < 0) { perror("open UIO"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ | (run ? PROT_WRITE : 0), MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) { perror("mmap UIO"); return 1; }
    struct gtx_io io = {mapping, read_mmio, write_mmio, wait_mmio};
    const char *error = NULL;
    if (io.read(io.context, ID) != UINT32_C(0x47545837) || io.read(io.context, ABI) != 1) {
        error = "not a GTX7 ABI-1 register bank";
    } else if (!run) {
        show(io);
    } else {
        struct sigaction action = {.sa_handler = interrupt_probe};
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGINT, &action, NULL) || sigaction(SIGTERM, &action, NULL)) {
            perror("sigaction"); munmap(mapping, 4096); return 1;
        }
        struct gtx_result result;
        error = probe(io, &result);
        printf("last_status=%08" PRIx32 " clean_delta(control/rx/tx)=%" PRIu32 "/%" PRIu32 "/%" PRIu32
               " forced_error_cycles=%" PRIu32 " recovered_delta=%" PRIu32 "/%" PRIu32 "/%" PRIu32 "\n",
               result.status, result.clean.control, result.clean.rx, result.clean.tx, result.forced_errors,
               result.recovered.control, result.recovered.rx, result.recovered.tx);
        if (!error) puts("PASS: clean PRBS, forced-error detection and clean restart (not BER qualification)");
    }
    if (error) fprintf(stderr, "%s\n", error);
    munmap(mapping, 4096);
    return error ? 1 : 0;
}
#endif
