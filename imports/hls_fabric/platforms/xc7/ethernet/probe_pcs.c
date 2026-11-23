// External 1000BASE-X ABI-1 boundary diagnostic. Run --lead first and --follow
// on the peer within one second; both retain the real PCS negotiation stream.
// --startup tightly samples the existing physical controller and MMCM flags so
// a sub-millisecond startup failure can be localized without a new bitstream.
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
enum { RUN = 1, PAGE_SHIFT = 4 };

struct pcs_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    bool (*wait)(void *, unsigned);
};

struct pcs_snapshot {
    uint32_t status;
    uint32_t raw_words, low_commas, high_commas;
    uint32_t symbols, invalids, k28_5;
    uint32_t c1, c2, configs;
    uint32_t ci, restarts, abilities;
    uint32_t raw_last, decoded_last, tx_state;
};

struct pcs_result { struct pcs_snapshot before, after; };

// Compute a wrapping 32-bit counter delta.
static uint32_t delta(uint32_t after, uint32_t before) { return after - before; }

// Recognize a completed, clock-live GTX startup with no latched fault.
static bool ready(uint32_t status) {
    return (status & UINT32_C(0xf177)) == UINT32_C(0x0176);
}

// Retain physical readiness throughout a bounded coordination interval.
static const char *wait_ready(struct pcs_io io, uint32_t *status, unsigned milliseconds) {
    for (unsigned elapsed = 0; elapsed < milliseconds; elapsed += 10) {
        if (!io.wait(io.context, 10)) return "interrupted";
        *status = io.read(io.context, STATUS);
        if (!ready(*status)) return "GTX lost readiness";
    }
    return NULL;
}

// Select one status page and capture its physical status plus three values.
static const char *read_page(struct pcs_io io, unsigned page, uint32_t values[4]) {
    io.write(io.context, CONTROL, RUN | page << PAGE_SHIFT);
    if (!io.wait(io.context, 20)) return "interrupted";
    for (unsigned index = 0; index < 4; ++index)
        values[index] = io.read(io.context, STATUS + index);
    return ready(values[0]) ? NULL : "GTX lost readiness";
}

// Read all five pages while leaving the lane running between page accesses.
static const char *snapshot(struct pcs_io io, struct pcs_snapshot *sample) {
    uint32_t page[4];
    const char *error;
    if ((error = read_page(io, 0, page))) return error;
    sample->status = page[0];
    sample->raw_words = page[1]; sample->low_commas = page[2]; sample->high_commas = page[3];
    if ((error = read_page(io, 1, page))) return error;
    sample->symbols = page[1]; sample->invalids = page[2]; sample->k28_5 = page[3];
    if ((error = read_page(io, 2, page))) return error;
    sample->c1 = page[1]; sample->c2 = page[2]; sample->configs = page[3];
    if ((error = read_page(io, 3, page))) return error;
    sample->ci = page[1]; sample->restarts = page[2]; sample->abilities = page[3];
    if ((error = read_page(io, 4, page))) return error;
    sample->raw_last = page[1]; sample->decoded_last = page[2]; sample->tx_state = page[3];
    return NULL;
}

// Coordinate peers, retain a one-second counter window and always stop this lane.
static const char *probe(struct pcs_io io, bool lead, struct pcs_result *result) {
    memset(result, 0, sizeof(*result));
    if (io.read(io.context, ID) != UINT32_C(0x50435337) || io.read(io.context, ABI) != 1)
        return "not a PCS7 ABI-1 register bank";
    io.write(io.context, CONTROL, 0);
    if (!io.wait(io.context, 20)) return "interrupted";
    if ((io.read(io.context, STATUS) & UINT32_C(0xf107)) != 1)
        return "reset did not clear the previous attempt";
    io.write(io.context, CONTROL, RUN);
    const char *error = "GTX startup timed out";
    for (unsigned poll = 0; poll < 1000; ++poll) {
        if (!io.wait(io.context, 1)) { error = "interrupted"; break; }
        result->before.status = io.read(io.context, STATUS);
        if ((result->before.status & 7) == 7 || (result->before.status & UINT32_C(0xf000))) {
            error = "GTX startup fault"; break;
        }
        if (ready(result->before.status)) { error = NULL; break; }
    }
    if (!error) error = wait_ready(io, &result->before.status, lead ? 2000 : 1000);
    if (!error) error = snapshot(io, &result->before);
    if (!error) error = wait_ready(io, &result->after.status, 1000);
    if (!error) error = snapshot(io, &result->after);
    if (!error && result->after.raw_words == result->before.raw_words)
        error = "recovered raw-word clock did not advance";
    // Keep the lead transmitting until the follower's later snapshots complete.
    if (!error && lead) error = wait_ready(io, &result->after.status, 1000);
    io.write(io.context, CONTROL, 0);
    return error;
}

// Name the first receive layer that did not make progress during the window.
static const char *boundary(const struct pcs_result *result) {
    const struct pcs_snapshot *a = &result->after, *b = &result->before;
    // RUNNING replaces configuration ordered sets with idles, so a healthy
    // post-link window normally has no new C1/C2 or complete config words.
    if (a->tx_state & (UINT32_C(1) << 21))
        return "link reached RUNNING; post-link idle window";
    if (!delta(a->low_commas, b->low_commas) && !delta(a->high_commas, b->high_commas))
        return "raw stream has no K28.5 comma";
    if (!delta(a->k28_5, b->k28_5)) return "gearbox/decoder does not recover K28.5";
    if (!delta(a->c1, b->c1) && !delta(a->c2, b->c2))
        return "decoded stream has no C1/C2 prefix after K28.5";
    if (!delta(a->configs, b->configs)) return "PCS does not complete configuration words";
    return "configuration reaches autonegotiation but link stays down";
}

#ifndef PCS_TEST
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

// Name one physical-controller state from the PCS probe register contract.
static const char *state_name(uint32_t status) {
    static const char *const names[] = {
        "BOOT", "HOLD", "LOCK", "CLOCKS", "DONE", "SETTLE", "READY", "FAULT"
    };
    return names[status & 7];
}

// Capture every observable startup transition before the one-millisecond FPGA watchdog expires.
static int trace_startup(struct pcs_io io) {
    if (io.read(io.context, ID) != UINT32_C(0x50435337) || io.read(io.context, ABI) != 1) {
        fprintf(stderr, "not a PCS7 ABI-1 register bank\n");
        return 1;
    }
    io.write(io.context, CONTROL, 0);
    if (!io.wait(io.context, 20)) {
        fprintf(stderr, "interrupted\n");
        return 1;
    }
    uint32_t reset_status = io.read(io.context, STATUS);
    if ((reset_status & UINT32_C(0xf107)) != 1) {
        fprintf(stderr, "reset did not clear the previous attempt: %08" PRIx32 "\n", reset_status);
        return 1;
    }

    io.write(io.context, CONTROL, RUN | 4 << PAGE_SHIFT);
    uint32_t start = io.read(io.context, CYCLES);
    uint32_t previous_status = UINT32_MAX, previous_flags = UINT32_MAX;
    uint32_t status = 0, flags = 0, elapsed = 0;
    do {
        elapsed = delta(io.read(io.context, CYCLES), start);
        status = io.read(io.context, STATUS);
        flags = io.read(io.context, DATA2);
        if (status != previous_status || flags != previous_flags) {
            printf("cycle=%" PRIu32 " status=%08" PRIx32 " state=%s fault=%x"
                   " pll=%u tx_done=%u rx_done=%u tx_mmcm=%u rx_mmcm=%u\n",
                   elapsed, status, state_name(status), (status >> 12) & 0xf,
                   (status >> 4) & 1, (status >> 5) & 1, (status >> 6) & 1,
                   (flags >> 16) & 1, (flags >> 17) & 1);
            previous_status = status;
            previous_flags = flags;
        }
    } while ((status & 7) != 7 && !ready(status) && elapsed < 100000);
    io.write(io.context, CONTROL, 0);
    if (ready(status)) {
        puts("PASS: physical startup reached READY");
        return 0;
    }
    if ((status & 7) != 7)
        fprintf(stderr, "host trace ended before a terminal FPGA state\n");
    return 1;
}

// Print the complete retained trace and its diagnostic classification.
static void show(const struct pcs_result *result) {
    const struct pcs_snapshot *a = &result->after, *b = &result->before;
    uint32_t abilities = a->abilities, decoded = a->decoded_last, state = a->tx_state;
    printf("raw status=%08" PRIx32 " words=%" PRIu32 " comma_low=%" PRIu32
           " comma_high=%" PRIu32 " last=%05" PRIx32 "\n",
           a->status, delta(a->raw_words, b->raw_words),
           delta(a->low_commas, b->low_commas), delta(a->high_commas, b->high_commas),
           a->raw_last & UINT32_C(0xfffff));
    printf("decode symbols=%" PRIu32 " invalid=%" PRIu32 " k28.5=%" PRIu32
           " last_tbi=%03" PRIx32 " last_data=%02" PRIx32 " k=%u bad=%u\n",
           delta(a->symbols, b->symbols), delta(a->invalids, b->invalids),
           delta(a->k28_5, b->k28_5), (decoded >> 10) & 0x3ff,
           decoded & 0xff, (decoded >> 8) & 1, (decoded >> 9) & 1);
    printf("ordered_sets c1=%" PRIu32 " c2=%" PRIu32 " ci=%" PRIu32
           " configs=%" PRIu32 " restarts=%" PRIu32 "\n",
           delta(a->c1, b->c1), delta(a->c2, b->c2), delta(a->ci, b->ci),
           delta(a->configs, b->configs), delta(a->restarts, b->restarts));
    printf("autoneg last_config=%04" PRIx32 " lp_abi=%04" PRIx32
           " align=%u ack=%u empty=%u link=%u locks=%u/%u\n",
           abilities & 0xffff, abilities >> 16,
           (state >> 18) & 1, (state >> 19) & 1, (state >> 20) & 1,
           (state >> 21) & 1, (state >> 16) & 1, (state >> 17) & 1);
    printf("boundary=%s\n", boundary(result));
}

// Map one UIO page and execute exactly one coordinated lead/follow attempt.
int main(int argc, char **argv) {
    bool lead = argc == 3 && strcmp(argv[2], "--lead") == 0;
    bool follow = argc == 3 && strcmp(argv[2], "--follow") == 0;
    bool startup = argc == 3 && strcmp(argv[2], "--startup") == 0;
    if (!lead && !follow && !startup) {
        fprintf(stderr, "usage: %s /dev/uioN (--lead|--follow|--startup)\n", argv[0]); return 2;
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
    struct pcs_io io = {mapping, read_mmio, write_mmio, wait_mmio};
    if (startup) {
        int result = trace_startup(io);
        munmap(mapping, 4096);
        return result;
    }
    struct pcs_result result;
    const char *error = probe(io, lead, &result);
    if (!error || strcmp(error, "not a PCS7 ABI-1 register bank") != 0) show(&result);
    if (error) fprintf(stderr, "%s\n", error);
    else puts("PASS: 1000BASE-X PCS boundary trace captured (diagnostic, not link/BER qualification)");
    munmap(mapping, 4096);
    return error != NULL;
}
#endif
