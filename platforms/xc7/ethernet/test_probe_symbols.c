#define SYMBOL_TEST
#include "probe_symbols.c"
#include <assert.h>

enum fake_mode { HEALTHY, NO_PATTERN, BAD_PHASE, INTERRUPTED };
struct fake {
    uint32_t control, cycles, words, patterns, aligned, swapped, changes;
    enum fake_mode mode;
    unsigned writes, waits;
    bool aligned_once, bad_identity;
};

// Return the selected synthetic status page without advancing simulated time.
static uint32_t read_fake(void *context, unsigned word) {
    struct fake *f = context;
    if (word == ID) return f->bad_identity ? 0 : UINT32_C(0x53594d37);
    if (word == ABI) return 1;
    if (word == CONTROL) return f->control;
    if (word == CYCLES) return f->cycles;
    if (word == STATUS) return f->control & RUN ? UINT32_C(0x176) : 1;
    if (!(f->control & PAGE_ONE)) {
        if (word == DATA0) {
            uint32_t phase = f->control & ALIGN ? (f->mode == BAD_PHASE ? 5 : 0) : 3;
            uint32_t raw = f->control & ALIGN ? PATTERN : UINT32_C(0x6be50);
            return (UINT32_C(1) << 25) | phase << 20 | raw;
        }
        if (word == DATA1) return f->words;
        if (word == DATA2) return f->patterns;
    } else {
        if (word == DATA0) return f->aligned;
        if (word == DATA1) return f->swapped;
        if (word == DATA2) return f->changes;
    }
    return 0;
}

// Apply run/page/alignment control and model reset-cleared counters.
static void write_fake(void *context, unsigned word, uint32_t value) {
    struct fake *f = context;
    assert(word == CONTROL);
    if (!(value & RUN)) {
        f->words = f->patterns = f->aligned = f->swapped = f->changes = 0;
        f->aligned_once = false;
    }
    if ((value & ALIGN) && !f->aligned_once) { ++f->changes; f->aligned_once = true; }
    f->control = value;
    ++f->writes;
}

// Advance ideal 25/62.5-MHz counters without wall-clock delay.
static bool wait_fake(void *context, unsigned milliseconds) {
    struct fake *f = context;
    ++f->waits;
    if (f->mode == INTERRUPTED && f->waits == 12) return false;
    f->cycles += milliseconds * 25000;
    if (f->control & RUN) {
        uint32_t delta = milliseconds * 62500;
        f->words += delta;
        if (f->mode != NO_PATTERN) f->patterns += delta;
        if (f->control & ALIGN) f->aligned += delta;
    }
    return true;
}

// Cover both roles, absent patterns, bad alignment, cancellation and bystanders.
int main(void) {
    for (unsigned lead = 0; lead < 2; ++lead) {
        struct fake f = {.mode = HEALTHY};
        struct symbol_io io = {&f, read_fake, write_fake, wait_fake};
        struct symbol_result result;
        assert(!probe(io, lead, &result));
        assert(!f.control && result.after.words > result.before.words);
        assert(result.after.patterns > result.before.patterns);
        assert(lead ? f.waits > 400 : f.waits < 300);
    }
    for (enum fake_mode mode = NO_PATTERN; mode <= INTERRUPTED; ++mode) {
        struct fake f = {.mode = mode};
        struct symbol_io io = {&f, read_fake, write_fake, wait_fake};
        struct symbol_result result;
        assert(probe(io, false, &result));
        assert(!f.control);
    }
    struct fake bystander = {.control = 3, .bad_identity = true};
    struct symbol_io io = {&bystander, read_fake, write_fake, wait_fake};
    struct symbol_result result;
    assert(probe(io, false, &result));
    assert(!bystander.writes && !bystander.waits && bystander.control == 3);
    puts("PASS: raw-symbol lead/follow sequencing, classification, faults and cleanup");
    return 0;
}
