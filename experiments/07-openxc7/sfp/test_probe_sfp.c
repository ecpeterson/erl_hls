#define SFP_TEST
#include "probe_sfp.c"
#include <assert.h>
#include <string.h>

/* Fake MMIO models delayed replies, not serial framing (tested against HDL). */
struct fake { uint32_t words[8]; unsigned mode, writes, waits; };

/* Return a register without causing progress. */
static uint32_t read_fake(void *context, unsigned word) {
    return ((struct fake *)context)->words[word];
}

/* Remember challenge writes so restoration and identity gating are observable. */
static void write_fake(void *context, unsigned word, uint32_t value) {
    struct fake *f = context;
    assert(word == SFP_CHALLENGE);
    f->words[word] = value;
    f->writes++;
}

/* Modes: healthy, stuck-zero, stuck-one, stale echo, frozen count, invalid marker. */
static void wait_fake(void *context) {
    struct fake *f = context;
    if (++f->waits % 3) return;
    if (f->mode != 4) f->words[SFP_FRAMES]++;
    uint32_t echo = f->mode == 3 ? 0x5a : f->words[SFP_CHALLENGE] & 0xff;
    f->words[SFP_RAW] = f->mode == 1 ? 0 : f->mode == 2 ? UINT32_MAX :
        (f->mode == 5 ? UINT32_C(0xb00e0000) : UINT32_C(0xa00e0000)) | echo;
}

/* Valid liveness permits an absent/faulting module; broken communication fails. */
int main(void) {
    for (unsigned mode = 0; mode <= 5; ++mode) {
        struct fake f = {.mode = mode};
        f.words[SFP_ID] = UINT32_C(0x53465037);
        f.words[SFP_ABI] = 1;
        f.words[SFP_CHALLENGE] = UINT32_C(0xdeadbeef);
        f.words[SFP_FRAMES] = UINT32_MAX; // progress across wrap still counts
        struct sfp_io io = {&f, read_fake, write_fake, wait_fake};
        uint32_t status;
        const char *error = sfp_probe(io, &status);
        assert((error == NULL) == (mode == 0));
        assert(f.words[SFP_CHALLENGE] == UINT32_C(0xdeadbeef));
        if (!mode) assert(status == UINT32_C(0xa00e00a5));
    }
    struct fake bad = {0};
    struct sfp_io io = {&bad, read_fake, write_fake, wait_fake};
    uint32_t status;
    assert(sfp_probe(io, &status));
    assert(bad.writes == 0 && bad.waits == 0);
    puts("PASS: SFP identity, fresh echoes, status, faults, bounded polls, challenge restoration");
    return 0;
}
