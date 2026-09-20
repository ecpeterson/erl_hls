#include "sfp_eeprom.h"
#include <assert.h>
#include <string.h>

/* Independent edge-driven EEPROM peer, with no knowledge of driver call order.
 * It accepts only address/pointer/read, checks every ACK, and exposes no data-write
 * path. Synthetic ID bytes exercise decoding; they are not a cable's real EEPROM.
 */
struct peer {
    uint32_t control, identity, abi;
    uint8_t bytes[96], received[3], shift;
    unsigned bits, commands, index, starts, stops, clocks, writes, delays, acks, nacks;
    unsigned nack_at, remove_at, stuck_at;
    int scl, sda, slave_low, sending, active, stuck, absent, bad_ack;
};

/* Resolve the physical SDA wire, including an independent stuck-low fault. */
static unsigned line(const struct peer *p) { return p->sda && !p->slave_low && !p->stuck && !(p->stuck_at && p->index >= p->stuck_at); }

/* Expose only the registers used by the EEPROM diagnostic. */
static uint32_t peer_read(void *context, unsigned word) {
    struct peer *p = context;
    switch (word) {
    case SFP_ID: return p->identity;
    case SFP_ABI: return p->abi;
    case SFP_CONTROL: return p->control;
    case SFP_SDA: return line(p);
    case SFP_RAW: return (p->absent || (p->remove_at && p->index >= p->remove_at)) ? 1u << 18 : 0;
    default: assert(0); return 0;
    }
}

/* Decode wire edges, driving ACK/data only while SCL is low. */
static void peer_write(void *context, unsigned word, uint32_t value) {
    struct peer *p = context;
    assert(word == SFP_CONTROL);
    assert(p->delays == p->writes + 1);
    assert((value & ~SFP_I2C_MASK) == 0x75); // preserve unrelated RGPIO challenge
    int old_scl = p->scl, old_line = line(p);
    p->control = value;
    p->scl = !(value & SFP_SCL_LOW);
    p->sda = !(value & SFP_SDA_LOW);
    p->writes++;
    if (old_scl && p->scl && old_line != (int)line(p)) {
        if (!line(p)) {
            p->starts++;
            p->active = 1; p->sending = 0; p->bits = 0; p->shift = 0;
        } else { p->stops++; p->active = 0; }
        return;
    }
    if (!p->active) return;
    if (!old_scl && p->scl) {
        p->clocks++;
        if (p->bits < 8 && !p->sending) p->shift = (uint8_t)((p->shift << 1) | line(p));
        if (p->bits == 8 && p->sending) {
            if (line(p)) p->nacks++; else p->acks++;
            // Only the last byte may be NACKed on a complete read.
            p->bad_ack |= (!!line(p) != (p->index == 95)) && !p->remove_at;
        }
        p->bits++;
        if (p->bits == 8 && !p->sending) {
            assert(p->commands < 3); // a data write would land here and fail
            p->received[p->commands++] = p->shift;
        }
    } else if (old_scl && !p->scl) {
        if (p->bits == 9) {
            p->slave_low = 0;
            if (p->sending) {
                p->index++;
                if (p->nacks) p->active = 0;
            } else if (p->commands == p->nack_at) p->active = 0;
            else if (p->commands == 3) p->sending = 1;
            p->bits = 0; p->shift = 0;
        }
        if (p->active) {
            if (p->sending) {
                assert(p->index < 96 || p->stuck_at);
                uint8_t byte = p->index < 96 ? p->bytes[p->index] : 0xff;
                p->slave_low = p->bits < 8 && !(byte & (0x80u >> p->bits));
            } else p->slave_low = p->bits == 8 && p->commands != p->nack_at;
        }
    }
}

/* Require a settling delay between every GPIO write and subsequent read/write. */
static void peer_wait(void *context, unsigned microseconds) {
    struct peer *p = context;
    assert(microseconds == 5);
    p->delays++;
}

/* Produce a checksummed passive-cable fixture with bounded ASCII fields. */
static struct peer fixture(void) {
    struct peer p = {.control = 0x75, .identity = UINT32_C(0x53465037), .abi = 2, .scl = 1, .sda = 1};
    p.bytes[0] = 3; p.bytes[1] = 4; p.bytes[2] = 0x21;
    p.bytes[8] = 4; p.bytes[11] = 1; p.bytes[12] = 103;
    memset(p.bytes + 20, ' ', 16); memcpy(p.bytes + 20, "Test vendor", 11);
    memcpy(p.bytes + 40, "PASSIVE-1M     \033", 16);
    memcpy(p.bytes + 56, "A1  ", 4);
    memcpy(p.bytes + 68, "TEST-SERIAL-00001", 16);
    memcpy(p.bytes + 84, "260920  ", 8);
    p.bytes[94] = 8;
    for (unsigned i = 0; i < 63; ++i) p.bytes[63] += p.bytes[i];
    for (unsigned i = 64; i < 95; ++i) p.bytes[95] += p.bytes[i];
    return p;
}

/* Assemble callbacks without coupling the EEPROM peer to driver's internals. */
static struct sfp_io peer_io(struct peer *p) {
    return (struct sfp_io){p, peer_read, peer_write, peer_wait};
}

/* Exercise reads, command conservation, errors and human-readable identification. */
int main(void) {
    struct peer p = fixture();
    uint8_t bytes[96];
    assert(!sfp_eeprom_read(peer_io(&p), bytes));
    assert(!memcmp(bytes, p.bytes, sizeof bytes));
    assert(p.starts == 2 && p.stops == 1 && p.commands == 3);
    assert(!memcmp(p.received, "\xa0\x00\xa1", 3));
    assert(p.acks == 95 && p.nacks == 1 && !p.bad_ack);
    assert(p.control == 0x75 && p.scl && p.sda && !p.slave_low);
    assert(p.delays == p.writes + 1);
    assert(!sfp_eeprom_check(bytes));
    FILE *output = tmpfile(); assert(output);
    sfp_eeprom_report(output, bytes); rewind(output);
    char text[1024] = {0}; assert(fread(text, 1, sizeof text - 1, output)); fclose(output);
    assert(strstr(text, "vendor=Test vendor part=PASSIVE-1M     ?"));
    assert(strstr(text, "nominal_rate=10300 MBd (advertised)"));
    assert(strstr(text, "passive_cable=1 active_cable=0"));
    assert(strstr(text, "A0[0..95]="));
    bytes[20] ^= 1; assert(!strcmp(sfp_eeprom_check(bytes), "EEPROM CC_BASE mismatch"));
    bytes[20] ^= 1; bytes[70] ^= 1;
    assert(!strcmp(sfp_eeprom_check(bytes), "EEPROM CC_EXT mismatch"));
    memset(bytes, 0, sizeof bytes); assert(sfp_eeprom_check(bytes));
    memset(bytes, 255, sizeof bytes); assert(sfp_eeprom_check(bytes));
    for (unsigned command = 1; command <= 3; ++command) {
        p = fixture(); p.nack_at = command;
        assert(sfp_eeprom_read(peer_io(&p), bytes));
        assert(p.commands == command && p.stops == 1 && p.control == 0x75);
        assert(p.clocks < 30);
    }
    for (unsigned mode = 0; mode < 5; ++mode) {
        p = fixture();
        if (mode == 0) p.stuck = 1;
        if (mode == 1) p.absent = 1;
        if (mode == 2) p.control |= SFP_SCL_LOW;
        if (mode == 3) p.identity = 0;
        if (mode == 4) p.abi = 1;
        assert(sfp_eeprom_read(peer_io(&p), bytes));
        assert(p.writes == 0); // no blind recovery clocks or writes to wrong ABI
    }
    p = fixture(); p.remove_at = 4;
    assert(!strcmp(sfp_eeprom_read(peer_io(&p), bytes), "SFP removed during EEPROM read"));
    assert(p.control == 0x75 && p.clocks < 80);
    p = fixture(); p.stuck_at = 4;
    assert(!strcmp(sfp_eeprom_read(peer_io(&p), bytes), "SDA held low after STOP"));
    assert(p.control == 0x75 && p.clocks < 900);
    puts("PASS: EEPROM wire protocol, 96 bytes, ACK/NACK, no data writes, faults, checksums and bounded text");
    return 0;
}
