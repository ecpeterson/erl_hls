// External raw-symbol ABI-1 Linux/UIO diagnostic. --lead starts one second
// before --follow; both observe the free phase, enable hard comma alignment,
// and require a stable alternating-K28.5 stream before stopping the lane.
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

enum { ID, ABI, CONTROL, CYCLES, WRITES, STATUS, DATA0, DATA1, DATA2 };
enum { RUN = 1, ALIGN = 2, PAGE_ONE = 16 };
enum { PATTERN = 0xa0d7c, SWAPPED = 0x5f283 };

struct symbol_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    bool (*wait)(void *, unsigned);
};

struct symbol_snapshot {
    uint32_t status, raw_phase, words, patterns, aligned, swapped, changes;
};

struct symbol_result { struct symbol_snapshot before, after; };

// Require completed reset sequencing, active measurement and no latched fault.
static bool ready(uint32_t status) {
    return (status & UINT32_C(0xf177)) == UINT32_C(0x0176);
}

// Wait in short intervals so signal cancellation and transient faults are observed.
static const char *wait_ready(struct symbol_io io, uint32_t *status, unsigned milliseconds) {
    for (unsigned elapsed = 0; elapsed < milliseconds; elapsed += 10) {
        if (!io.wait(io.context, 10)) return "interrupted";
        *status = io.read(io.context, STATUS);
        if (!ready(*status)) return "GTX lost readiness";
    }
    return NULL;
}

// Read both status pages while retaining run/alignment controls.
static const char *snapshot(struct symbol_io io, bool align, struct symbol_snapshot *sample) {
    uint32_t base = RUN | (align ? ALIGN : 0);
    io.write(io.context, CONTROL, base);
    if (!io.wait(io.context, 20)) return "interrupted";
    sample->status = io.read(io.context, STATUS);
    sample->raw_phase = io.read(io.context, DATA0);
    sample->words = io.read(io.context, DATA1);
    sample->patterns = io.read(io.context, DATA2);
    io.write(io.context, CONTROL, base | PAGE_ONE);
    if (!io.wait(io.context, 20)) return "interrupted";
    sample->aligned = io.read(io.context, DATA0);
    sample->swapped = io.read(io.context, DATA1);
    sample->changes = io.read(io.context, DATA2);
    return ready(sample->status) ? NULL : "GTX lost readiness";
}

// Coordinate two peers, then classify the stream after enabling hard alignment.
static const char *probe(struct symbol_io io, bool lead, struct symbol_result *result) {
    memset(result, 0, sizeof(*result));
    if (io.read(io.context, ID) != UINT32_C(0x53594d37) || io.read(io.context, ABI) != 1)
        return "not a SYM7 ABI-1 register bank";
    io.write(io.context, CONTROL, 0);
    if (!io.wait(io.context, 20)) return "interrupted";
    if ((io.read(io.context, STATUS) & UINT32_C(0xf107)) != 1)
        return "reset did not clear the previous attempt";
    io.write(io.context, CONTROL, RUN);
    const char *error = "GTX startup timed out";
    for (unsigned poll = 0; poll < 1000; ++poll) {
        if (!io.wait(io.context, 1)) { error = "interrupted"; break; }
        result->before.status = io.read(io.context, STATUS);
        if ((result->before.status & 7) == 7 || (result->before.status & 0xf000)) {
            error = "GTX startup fault"; break;
        }
        if (ready(result->before.status)) { error = NULL; break; }
    }
    if (!error) error = wait_ready(io, &result->before.status, lead ? 2000 : 1000);
    if (!error) error = snapshot(io, false, &result->before);
    if (!error) {
        io.write(io.context, CONTROL, RUN | ALIGN);
        error = wait_ready(io, &result->after.status, 1000);
    }
    if (!error) error = snapshot(io, true, &result->after);
    if (!error) {
        uint32_t words = result->after.words - result->before.words;
        uint32_t patterns = result->after.patterns - result->before.patterns;
        uint32_t aligned = result->after.aligned - result->before.aligned;
        uint32_t swapped = result->after.swapped - result->before.swapped;
        uint32_t changes = result->after.changes - result->before.changes;
        uint32_t raw = result->after.raw_phase & UINT32_C(0xfffff);
        uint32_t phase = (result->after.raw_phase >> 20) & 31;
        if (!words) error = "recovered word clock did not advance";
        else if ((uint64_t)patterns * 100 < (uint64_t)words * 90)
            error = "transmitted 20-bit pattern was not stably recovered";
        else if ((uint64_t)(aligned + swapped) * 100 < (uint64_t)words * 90)
            error = "hard comma alignment did not reach a 10-bit word boundary";
        else if (!(result->after.raw_phase & (UINT32_C(1) << 25)) ||
                 (phase != 0 && phase != 10) || (raw != PATTERN && raw != SWAPPED))
            error = "aligned raw word or phase is unexpected";
        else if (changes > 8)
            error = "recovered pattern phase remained unstable after alignment";
    }
    // The lead keeps transmitting after its last sample so the follower can
    // finish its slightly later page reads without observing reset fill.
    if (!error && lead)
        error = wait_ready(io, &result->after.status, 1000);
    io.write(io.context, CONTROL, 0);
    return error;
}

#ifndef SYMBOL_TEST
static volatile sig_atomic_t interrupted;

// Convert termination into bounded cleanup at the next diagnostic delay.
static void interrupt_probe(int signal_number) { (void)signal_number; interrupted = 1; }

// Perform one ordered MMIO read from the mapped register page.
static uint32_t read_mmio(void *context, unsigned word) {
    return ((volatile uint32_t *)context)[word];
}

// Perform one ordered MMIO write to the mapped register page.
static void write_mmio(void *context, unsigned word, uint32_t value) {
    ((volatile uint32_t *)context)[word] = value;
}

// Delay for at least the requested interval unless a handled signal arrives.
static bool wait_mmio(void *context, unsigned milliseconds) {
    (void)context;
    struct timespec delay = {milliseconds / 1000, (long)(milliseconds % 1000) * 1000000};
    while (nanosleep(&delay, &delay) && errno == EINTR && !interrupted) {}
    return !interrupted;
}

// Print one phase/counter sample in a form suitable for retaining as evidence.
static void show(const char *name, const struct symbol_snapshot *sample) {
    printf("%s status=%08" PRIx32 " raw=%05" PRIx32 " phase_valid=%u phase=%u "
           "words=%" PRIu32 " patterns=%" PRIu32 " aligned=%" PRIu32
           " swapped=%" PRIu32 " changes=%" PRIu32 "\n",
           name, sample->status, sample->raw_phase & UINT32_C(0xfffff),
           (sample->raw_phase >> 25) & 1, (sample->raw_phase >> 20) & 31,
           sample->words, sample->patterns, sample->aligned, sample->swapped, sample->changes);
}

// Map one UIO page and execute exactly one coordinated lead/follow attempt.
int main(int argc, char **argv) {
    bool lead = argc == 3 && strcmp(argv[2], "--lead") == 0;
    bool follow = argc == 3 && strcmp(argv[2], "--follow") == 0;
    if (!lead && !follow) {
        fprintf(stderr, "usage: %s /dev/uioN (--lead|--follow)\n", argv[0]); return 2;
    }
    int fd = open(argv[1], O_RDWR | O_SYNC);
    if (fd < 0) { perror("open UIO"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) { perror("mmap UIO"); return 1; }
    struct sigaction action = {.sa_handler = interrupt_probe};
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) || sigaction(SIGTERM, &action, NULL)) {
        perror("sigaction"); munmap(mapping, 4096); return 1;
    }
    struct symbol_io io = {mapping, read_mmio, write_mmio, wait_mmio};
    struct symbol_result result;
    const char *error = probe(io, lead, &result);
    if (!error || strcmp(error, "not a SYM7 ABI-1 register bank") != 0) {
        show("free", &result.before);
        show("aligned", &result.after);
    }
    if (error) fprintf(stderr, "%s\n", error);
    else puts("PASS: stable raw 20-bit stream and hard comma alignment (not Ethernet/BER qualification)");
    munmap(mapping, 4096);
    return error != NULL;
}
#endif
