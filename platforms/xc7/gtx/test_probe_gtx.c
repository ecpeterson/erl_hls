#define GTX_TEST
#include "probe_gtx.c"
#include <assert.h>

// Fault modes distinguish reset, stale readiness, clean/error/recovery and clocks.
enum mode { HEALTHY, BAD_ID, BAD_ABI, RESET_STUCK, STARTUP_FAULT, STARTUP_STUCK,
            DIRTY, NO_INJECTION, RECOVERY_DIRTY, STOPPED, WRONG_RATIO, INTERRUPTED };
struct fake {
    uint32_t regs[9];
    enum mode mode;
    unsigned writes, waits, starts, age, injections, remote_error_at;
    bool external;
};

// Sampling alone never advances the simulated device.
static uint32_t read_fake(void *context, unsigned word) { return ((struct fake *)context)->regs[word]; }

// Reset clears delayed snapshots; repeated starts remain observable to the fixture.
static void write_fake(void *context, unsigned word, uint32_t value) {
    struct fake *f = context;
    assert(word == CONTROL && value <= 3);
    if (value == 1 && f->regs[CONTROL] == 0) { ++f->starts; f->age = 0; }
    if (value == 3) ++f->injections;
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
        (!f->external && f->regs[CONTROL] == 3 && f->mode != NO_INJECTION) ||
        (f->external && f->remote_error_at && f->age >= f->remote_error_at &&
         !f->regs[ERRORS])) f->regs[ERRORS] += 7;
    return true;
}

// Construct a reset-ready ABI-1 fixture for the coordinated external roles.
static struct fake external_fake(void) {
    struct fake f = {.mode = HEALTHY, .external = true};
    f.regs[ID] = UINT32_C(0x47545837);
    f.regs[ABI] = 1;
    f.regs[STATUS] = 1;
    return f;
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

    struct fake monitor = external_fake();
    monitor.remote_error_at = 3300;
    struct gtx_io monitor_io = {&monitor, read_fake, write_fake, wait_fake};
    struct external_result monitor_result;
    assert(!external_monitor(monitor_io, &monitor_result));
    assert(monitor.regs[CONTROL] == 0 && monitor_result.baseline_errors == 0);
    assert(monitor_result.final_errors == 7 && monitor_result.quiet.control == 25000000);
    assert(monitor_result.quiet.rx == 62500000 && monitor_result.quiet.tx == 62500000);

    struct fake inject = external_fake();
    struct gtx_io inject_io = {&inject, read_fake, write_fake, wait_fake};
    struct external_result inject_result;
    assert(!external_inject(inject_io, &inject_result));
    assert(inject.regs[CONTROL] == 0 && inject.injections == 1);
    assert(inject_result.baseline_errors == 0 && inject_result.final_errors == 0);

    struct fake absent = external_fake();
    struct gtx_io absent_io = {&absent, read_fake, write_fake, wait_fake};
    assert(external_monitor(absent_io, &monitor_result));
    assert(absent.regs[CONTROL] == 0);

    struct fake dirty = external_fake();
    dirty.mode = DIRTY;
    struct gtx_io dirty_io = {&dirty, read_fake, write_fake, wait_fake};
    assert(external_inject(dirty_io, &inject_result));
    assert(dirty.regs[CONTROL] == 0 && dirty.injections == 0);

    struct fake bystander = external_fake();
    bystander.regs[ID] = 0;
    bystander.regs[CONTROL] = 3;
    struct gtx_io bystander_io = {&bystander, read_fake, write_fake, wait_fake};
    assert(external_monitor(bystander_io, &monitor_result));
    assert(!bystander.writes && !bystander.waits && bystander.regs[CONTROL] == 3);

    puts("PASS: internal and coordinated external PRBS sequencing, clocks, faults and cancellation");
    return 0;
}
