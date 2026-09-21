#include "si5338.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

// The independent device model enforces page selection, masks and lock/calibration ordering.
struct si_register { uint16_t address; uint8_t value, mask; };
#include "profile.h"
struct chip {
    uint8_t regs[512], page;
    unsigned calls, writes, fail_at, corrupt_reg, after_reset_ms, resets, delay_ms;
    bool missing_input, no_lock, cleanup_broken, configured, enabled, fail_after_write;
};

// Preserve unrelated bits; known dynamic controls are separate from the vendor table.
static unsigned write_mask(unsigned reg) {
    if (reg==230) return 31;
    if (reg==241) return 255;
    if (reg==246) return 2;
    for (unsigned i=0;i<sizeof(si_profile)/sizeof(si_profile[0]);++i)
        if (si_profile[i].address==reg) return si_profile[i].mask;
    return 0;
}

// A 25-ms soft-reset interval is required before successful lock/calibration readback.
static uint8_t status(struct chip *c) {
    return (c->missing_input ? 4 : 0) | (c->no_lock || !c->resets || c->after_reset_ms<25 ? 0x11 : 0);
}

// Inject a one-shot transport fault at every call boundary, including page switches.
static int read_chip(void *context, uint8_t reg, uint8_t *value) {
    struct chip *c=context;
    if (++c->calls==c->fail_at) return 71;
    unsigned address=c->page*256+reg;
    *value=reg==255 ? c->page : address==218 ? status(c) : c->regs[address];
    if (c->configured && address==c->corrupt_reg) *value^=1;
    return 0;
}

// Never accept NVM, identity or unmasked writes, or premature clock enabling.
static int write_chip(void *context, uint8_t reg, uint8_t value) {
    struct chip *c=context;
    bool fault=++c->calls==c->fail_at;
    if ((fault && !c->fail_after_write) || (c->cleanup_broken && c->calls>c->fail_at)) return 71;
    if (reg==255) { assert(value<=1); c->page=value; return fault ? 71 : 0; }
    unsigned address=c->page*256+reg, mask=write_mask(address);
    assert(mask && !((c->regs[address]^value)&~mask));
    ++c->writes;
    if (address==246) { assert(value==2); ++c->resets; c->after_reset_ms=0; }
    if (address==230 && !(value&0x10)) {
        assert(c->resets && !status(c) && c->regs[45]==0x56 && c->regs[46]==0x34);
        assert((c->regs[47]&3)==2 && (c->regs[49]&0x80) && c->regs[241]==0x65);
        assert((value&15)==3); c->enabled=true;
    }
    c->regs[address]=value;
    if (address==49 && (value&0x80)) c->configured=true;
    return fault ? 71 : 0;
}

// Advance only simulated clock time; no real sleep is needed for timeout cases.
static void delay_chip(void *context, unsigned ms) {
    struct chip *c=context; c->delay_ms+=ms;
    if (c->resets) c->after_reset_ms+=ms;
}

// Start with a different profile, nonzero reserved bits, and the second page selected.
static struct chip fresh(void) {
    struct chip c={.page=1,.corrupt_reg=65535};
    memset(c.regs,0xa5,sizeof(c.regs));
    c.regs[0]=1; c.regs[2]=0x66; c.regs[3]=8; c.regs[4]=1; c.regs[5]=2;
    c.regs[230]=0x10; c.regs[241]=0x65; c.regs[246]=0;
    c.regs[235]=0x56; c.regs[236]=0x34; c.regs[237]=0x92;
    return c;
}

// Run the complete configuration through the same interface used by the FSBL.
static enum si_error configure(struct chip *c, struct si_report *r) {
    struct si_io io={c,read_chip,write_chip,delay_chip};
    return si5338_configure(io,r);
}

// Test successful programming, inert readback, alarms, every I/O failure and retry after failure.
int main(void) {
    struct si_report r;
    struct chip good=fresh();
    assert(configure(&good,&r)==SI_OK && good.enabled && good.page==0 && good.resets==1);
    unsigned successful_calls=good.calls, writes=good.writes;
    uint8_t before[512]; memcpy(before,good.regs,sizeof(before));
    struct si_io io={&good,read_chip,write_chip,delay_chip};
    assert(si5338_readback(io,&r)==SI_OK && good.writes==writes);
    assert(!memcmp(before,good.regs,sizeof(before)) && r.nvm_code==258);
    unsigned readback_calls=good.calls-successful_calls;
    for (unsigned fault=1;fault<=readback_calls;++fault) {
        struct chip c=good; c.calls=0; c.fail_at=fault;
        struct si_io read_io={&c,read_chip,write_chip,delay_chip};
        assert(si5338_readback(read_io,&r)==SI_IO && r.bus_error==71);
        assert(c.page==0 && c.writes==writes && !memcmp(before,c.regs,sizeof(before)));
    }
    good.regs[49]^=0x80;
    assert(si5338_readback(io,&r)==SI_VERIFY && r.reg==49);
    good.regs[49]^=0x80;
    good.regs[45]^=1;
    assert(si5338_readback(io,&r)==SI_VERIFY && r.reg==45);
    good.regs[45]^=1;
    good.regs[76]^=1;
    assert(si5338_readback(io,&r)==SI_VERIFY && r.reg==76 && r.mismatches==1);
    good.regs[76]^=1; good.no_lock=true;
    assert(si5338_readback(io,&r)==SI_VERIFY && r.status==0x11);
    for (unsigned mode=0;mode<2;++mode) for (unsigned fault=1;fault<=successful_calls;++fault) {
        struct chip c=fresh(); c.fail_at=fault; c.fail_after_write=mode;
        assert(configure(&c,&r)==SI_IO && r.bus_error==71);
        assert(c.calls<=successful_calls+3 && c.page==0);
        if (c.writes) assert(c.regs[230]&0x10);
        c.fail_at=0;
        assert(configure(&c,&r)==SI_OK);
    }
    for (unsigned mode=0;mode<6;++mode) {
        struct chip c=fresh();
        if (mode==0) c.regs[2]=0x67;
        if (mode==1) c.regs[0]=0;
        if (mode==2) c.missing_input=true;
        if (mode==3) c.no_lock=true;
        if (mode==4) c.corrupt_reg=76;
        if (mode==5) { c.fail_at=30; c.cleanup_broken=true; }
        enum si_error expected=mode<2 ? SI_IDENTITY : mode==2 ? SI_INPUT_TIMEOUT :
            mode==3 ? SI_LOCK_TIMEOUT : mode==4 ? SI_VERIFY : SI_IO;
        assert(configure(&c,&r)==expected);
        if (mode<2) assert(!c.writes);
        else if (mode!=5) assert(c.regs[230]&0x10);
        if (mode==4) assert(!c.enabled);
        if (mode==5) assert(r.cleanup_error==71);
        assert(c.delay_ms<=1025);
    }
    printf("PASS: Si5338 profile/readback, identity, input/lock timeouts, calibration, cleanup and %u/%u configure/readback I/O faults\n",successful_calls,readback_calls);
    return 0;
}
