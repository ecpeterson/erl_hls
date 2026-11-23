#define PCS_TEST
#include "probe_pcs.c"
#include <assert.h>

struct fake {
    uint32_t control, ticks, counters[5][3];
    bool bad_identity, stop_raw, interrupt;
    unsigned waits, writes;
};

// Return one selected synthetic status page without advancing simulated time.
static uint32_t read_fake(void *context, unsigned word) {
    struct fake *f = context;
    if (word == ID) return f->bad_identity ? 0 : UINT32_C(0x50435337);
    if (word == ABI) return 1;
    if (word == CONTROL) return f->control;
    if (word == STATUS) return f->control & RUN ? UINT32_C(0x176) : 1;
    if (word >= DATA0 && word <= DATA2)
        return f->counters[(f->control >> PAGE_SHIFT) & 7][word - DATA0];
    return 0;
}

// Apply the run/page control and count diagnostic writes.
static void write_fake(void *context, unsigned word, uint32_t value) {
    struct fake *f = context;
    assert(word == CONTROL);
    f->control = value;
    ++f->writes;
}

// Advance ideal raw/full-clock observations without a wall-clock delay.
static bool wait_fake(void *context, unsigned milliseconds) {
    struct fake *f = context;
    ++f->waits;
    if (f->interrupt && f->waits == 12) return false;
    if ((f->control & RUN) && !f->stop_raw) {
        uint32_t raw = milliseconds * 62500;
        uint32_t full = raw * 2;
        f->counters[0][0] += raw;
        f->counters[0][1] += raw / 4;
        f->counters[0][2] += raw / 4;
        f->counters[1][0] += full;
        f->counters[1][2] += full / 4;
        f->counters[2][0] += full / 8;
        f->counters[2][1] += full / 8;
        f->counters[2][2] += full / 8;
        f->counters[3][0] += full / 4;
        f->counters[3][2] = UINT32_C(0x00200020);
        f->counters[4][2] = UINT32_C(1) << 21;
    }
    return true;
}

// Cover both roles, stopped data, cancellation and an unrelated UIO identity.
int main(void) {
    for (unsigned lead = 0; lead < 2; ++lead) {
        struct fake f = {0};
        struct pcs_io io = {&f, read_fake, write_fake, wait_fake};
        struct pcs_result result;
        assert(!probe(io, lead, &result));
        assert(!f.control && result.after.raw_words > result.before.raw_words);
        assert(!strcmp(boundary(&result), "link reached RUNNING; post-link idle window"));
        assert(lead ? f.waits > 400 : f.waits < 400);
    }
    for (unsigned mode = 0; mode < 2; ++mode) {
        struct fake f = {.stop_raw = mode == 0, .interrupt = mode == 1};
        struct pcs_io io = {&f, read_fake, write_fake, wait_fake};
        struct pcs_result result;
        assert(probe(io, false, &result));
        assert(!f.control);
    }
    struct fake bystander = {.control = 0x55, .bad_identity = true};
    struct pcs_io io = {&bystander, read_fake, write_fake, wait_fake};
    struct pcs_result result;
    assert(probe(io, false, &result));
    assert(!bystander.writes && !bystander.waits && bystander.control == 0x55);
    puts("PASS: PCS boundary lead/follow sequencing, snapshots, faults and cleanup");
    return 0;
}
