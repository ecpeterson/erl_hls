/* Test the host diagnostic against observable register behavior without MMIO. */
#define PROBE_TEST
#include "probe_zynq_ps.c"
#include <assert.h>
#include <string.h>

/* Controllable clock and write faults for the diagnostic's host-side contract. */
struct fake { uint32_t words[5]; unsigned attempts; int drop, duplicate, stopped, restore_bad; };

/* Read register values without advancing simulated time. */
static uint32_t fake_read(void *context, unsigned word) {
    return ((struct fake *)context)->words[word];
}

/* Only scratch is writable; optionally lose, duplicate or corrupt a commit. */
static void fake_write(void *context, unsigned word, uint32_t value) {
    struct fake *state = context;
    assert(word == PROBE_SCRATCH);
    state->attempts++;
    if (state->drop && state->attempts == 1) return;
    state->words[word] = state->restore_bad && value == 0x1234 ? 0 : value;
    state->words[PROBE_WRITES] += state->duplicate ? 2 : 1;
}

/* Cross the counter wrap unless this fixture represents a stopped clock. */
static void fake_wait(void *context) {
    struct fake *state = context;
    if (!state->stopped) state->words[PROBE_CYCLES] += 100;
}

/* Return an initialized page with counters deliberately near wrap. */
static struct fake fresh(void) {
    struct fake state = {{PROBE_IDENTITY, 1, 0x1234, 0xfffffff0, 0xfffffff0}, 0, 0, 0, 0, 0};
    return state;
}

/* Run the same diagnostic used by the native UIO executable. */
static const char *run_fake(struct fake *state, struct probe_result *result) {
    struct probe_io io = {state, fake_read, fake_write, fake_wait};
    return probe_run(io, result);
}

/* Assert compatibility checks, restoration on failure and modular accounting. */
int main(void) {
    struct probe_result result = {0};
    struct fake state = fresh();
    assert(run_fake(&state, &result) == NULL);
    assert(result.writes == 37 && result.cycles == 100 && state.words[PROBE_SCRATCH] == 0x1234);
    for (unsigned word = PROBE_ID; word <= PROBE_VERSION; word++) {
        state = fresh(); state.words[word] = 0;
        assert(strstr(run_fake(&state, &result), "no writes attempted"));
        assert(state.attempts == 0);
    }
    state = fresh(); state.drop = 1;
    assert(strstr(run_fake(&state, &result), "readback mismatch"));
    assert(state.attempts == 2 && state.words[PROBE_SCRATCH] == 0x1234);
    state = fresh(); state.stopped = 1;
    assert(strstr(run_fake(&state, &result), "did not advance"));
    assert(state.words[PROBE_SCRATCH] == 0x1234);
    state = fresh(); state.duplicate = 1;
    assert(strstr(run_fake(&state, &result), "write count"));
    assert(state.words[PROBE_SCRATCH] == 0x1234);
    state = fresh(); state.restore_bad = 1;
    assert(strstr(run_fake(&state, &result), "restore failed"));
    puts("PASS: host probe identity, ABI, wrap, faults and scratch restoration");
    return 0;
}
