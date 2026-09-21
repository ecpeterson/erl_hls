#define GTX_TEST
#include "probe_gtx.c"
#include <assert.h>

// Fault modes distinguish reset, stale readiness, clean/error/recovery and clocks.
enum mode { HEALTHY, BAD_ID, BAD_ABI, RESET_STUCK, STARTUP_FAULT, STARTUP_STUCK,
            DIRTY, NO_INJECTION, RECOVERY_DIRTY, STOPPED, WRONG_RATIO, INTERRUPTED };
struct fake { uint32_t regs[9]; enum mode mode; unsigned writes, waits, starts, age; };

// Sampling alone never advances the simulated device.
static uint32_t read_fake(void *context, unsigned word) { return ((struct fake *)context)->regs[word]; }

// Reset clears delayed snapshots; repeated starts remain observable to the fixture.
static void write_fake(void *context, unsigned word, uint32_t value) {
    struct fake *f = context;
    assert(word == CONTROL && value <= 3);
    if (value == 1 && f->regs[CONTROL] == 0) { ++f->starts; f->age = 0; }
    f->regs[word] = value;
    ++f->writes;
}

// Progress models a three-ms startup and a 62.5/25-MHz counter ratio, including wrap.
static bool wait_fake(void *context, unsigned milliseconds) {
    struct fake *f = context;
    ++f->waits;
    if (f->mode == INTERRUPTED && f->waits == 12) return false;
    f->regs[CYCLES] += milliseconds * 25000;
    if (!f->regs[CONTROL]) {
        if (f->mode != RESET_STUCK) {
            f->regs[STATUS] = 1;
            f->regs[RX_WORDS] = f->regs[TX_WORDS] = f->regs[ERRORS] = 0;
        }
        return true;
    }
    f->age += milliseconds;
    f->regs[STATUS] = f->mode == STARTUP_FAULT ? 0x1007 :
        f->mode == STARTUP_STUCK || f->age < 3 ? 2 : 0x176;
    if (f->mode != STOPPED) {
        // Start near wrap so the observation interval crosses it.
        if (f->age == 3) f->regs[RX_WORDS] = f->regs[TX_WORDS] = UINT32_MAX - 62500;
        f->regs[RX_WORDS] += milliseconds * (f->mode == WRONG_RATIO ? 12500 : 62500);
        f->regs[TX_WORDS] += milliseconds * 62500;
    }
    if (f->mode == DIRTY || (f->mode == RECOVERY_DIRTY && f->starts == 2) ||
        (f->regs[CONTROL] == 3 && f->mode != NO_INJECTION)) f->regs[ERRORS] += 7;
    return true;
}

// Reject unhealthy attempts without leaking run/error-injection state; never write a bystander.
int main(void) {
    for (enum mode mode = HEALTHY; mode <= INTERRUPTED; ++mode) {
        struct fake f = {.mode = mode};
        f.regs[ID] = mode == BAD_ID ? 0 : UINT32_C(0x47545837);
        f.regs[ABI] = mode == BAD_ABI ? 2 : 1;
        f.regs[CONTROL] = 3; f.regs[STATUS] = 0x176; f.regs[ERRORS] = 42;
        f.regs[CYCLES] = UINT32_MAX - 100000;
        struct gtx_io io = {&f, read_fake, write_fake, wait_fake};
        struct gtx_result result;
        const char *error = probe(io, &result);
        assert((error == NULL) == (mode == HEALTHY));
        if (mode == BAD_ID || mode == BAD_ABI) {
            assert(!f.writes && !f.waits && f.regs[CONTROL] == 3);
        } else {
            assert(f.regs[CONTROL] == 0 && f.waits <= 1001);
        }
        if (mode == HEALTHY) {
            assert(f.starts == 2 && result.forced_errors == 7);
            assert(result.clean.control == 500000 && result.clean.rx == 1250000);
            assert(result.recovered.tx == 1250000);
        }
    }
    puts("PASS: PRBS reset, clean reception, injection, restart, clock wrap/ratio, faults and cancellation");
    return 0;
}
