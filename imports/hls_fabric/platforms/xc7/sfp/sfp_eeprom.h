#ifndef SFP_EEPROM_H
#define SFP_EEPROM_H
#include "sfp_io.h"
#include <stdio.h>

/* Drive the carrier's SCL and open-drain SDA command, preserving other controls.
 * A 5-us settling delay also covers the SDA synchronizer. No SCL feedback exists.
 */
static void sfp_i2c_lines(struct sfp_io io, uint32_t saved, int scl, int sda) {
    io.write(io.context, SFP_CONTROL, saved | (scl ? 0 : SFP_SCL_LOW) |
             (sda ? 0 : SFP_SDA_LOW));
    io.wait(io.context, 5);
}

/* Return the synchronized wired-AND of all carrier management SDA inputs. */
static unsigned sfp_i2c_sda(struct sfp_io io) {
    return io.read(io.context, SFP_SDA) & 1;
}

/* START or repeated START; enter/leave with SCL low except the initial idle bus. */
static void sfp_i2c_start(struct sfp_io io, uint32_t saved) {
    sfp_i2c_lines(io, saved, 0, 1);
    sfp_i2c_lines(io, saved, 1, 1);
    sfp_i2c_lines(io, saved, 1, 0);
    sfp_i2c_lines(io, saved, 0, 0);
}

/* End a transaction and leave both command lines released/high on every return. */
static void sfp_i2c_stop(struct sfp_io io, uint32_t saved) {
    sfp_i2c_lines(io, saved, 0, 0);
    sfp_i2c_lines(io, saved, 1, 0);
    sfp_i2c_lines(io, saved, 1, 1);
}

/* Send one address/pointer byte MSB first; return whether the device ACKed. */
static int sfp_i2c_send(struct sfp_io io, uint32_t saved, uint8_t byte) {
    for (unsigned bit = 0; bit < 8; ++bit) {
        unsigned value = (byte >> (7 - bit)) & 1;
        sfp_i2c_lines(io, saved, 0, value);
        sfp_i2c_lines(io, saved, 1, value);
        sfp_i2c_lines(io, saved, 0, value);
    }
    sfp_i2c_lines(io, saved, 0, 1);
    sfp_i2c_lines(io, saved, 1, 1);
    int ack = !sfp_i2c_sda(io);
    sfp_i2c_lines(io, saved, 0, 1);
    return ack;
}

/* Receive one byte; ACK requests the next byte, final NACK ends the read. */
static uint8_t sfp_i2c_receive(struct sfp_io io, uint32_t saved, int last) {
    uint8_t byte = 0;
    for (unsigned bit = 0; bit < 8; ++bit) {
        sfp_i2c_lines(io, saved, 0, 1);
        sfp_i2c_lines(io, saved, 1, 1);
        byte = (uint8_t)((byte << 1) | sfp_i2c_sda(io));
        sfp_i2c_lines(io, saved, 0, 1);
    }
    sfp_i2c_lines(io, saved, 0, last);
    sfp_i2c_lines(io, saved, 1, last);
    sfp_i2c_lines(io, saved, 0, last);
    sfp_i2c_lines(io, saved, 0, 1);
    return byte;
}

/* Read only A0h/7-bit 0x50 bytes 0..95 using a pointer write and repeated START.
 * Require fresh presence from sfp_probe, stable insertion, idle commands, no
 * other bus owner, no clock stretching and idle expansion-device SDA inputs.
 * No EEPROM data, page-select or diagnostic-control writes are issued. No bus
 * clearing clocks: following an interrupted pointer write they could write data.
 * The caller ignores the output on failure; ordinary exits leave commands idle.
 */
static const char *sfp_eeprom_read(struct sfp_io io, uint8_t bytes[96]) {
    if (io.read(io.context, SFP_ID) != UINT32_C(0x53465037) ||
        io.read(io.context, SFP_ABI) != 2)
        return "unexpected identity/ABI; no writes attempted";
    if (io.read(io.context, SFP_RAW) & (1u << 18)) return "SFP absent";
    uint32_t saved = io.read(io.context, SFP_CONTROL);
    if (saved & SFP_I2C_MASK) return "I2C commands not idle; cold-boot the probe";
    io.wait(io.context, 5);
    if (!sfp_i2c_sda(io)) return "SDA held low; check cable and expansion buses";
    const char *error = NULL;
    sfp_i2c_start(io, saved);
    if (!sfp_i2c_send(io, saved, 0xa0)) error = "EEPROM write address NACK";
    else if (!sfp_i2c_send(io, saved, 0)) error = "EEPROM offset NACK";
    else {
        sfp_i2c_start(io, saved);
        if (!sfp_i2c_send(io, saved, 0xa1)) error = "EEPROM read address NACK";
        else for (unsigned i = 0; i < 96; ++i) {
            bytes[i] = sfp_i2c_receive(io, saved, i == 95);
            if (io.read(io.context, SFP_RAW) & (1u << 18)) {
                error = "SFP removed during EEPROM read";
                break;
            }
        }
    }
    sfp_i2c_stop(io, saved);
    if (!error && !sfp_i2c_sda(io)) error = "SDA held low after STOP";
    return error;
}

/* Check SFP identity and both SFF-8472 sums before interpreting any fields. */
static const char *sfp_eeprom_check(const uint8_t bytes[96]) {
    if (bytes[0] != 3 || bytes[1] != 4) return "unsupported SFP identifier/extended identifier";
    uint8_t base = 0, ext = 0;
    for (unsigned i = 0; i < 63; ++i) base += bytes[i];
    for (unsigned i = 64; i < 95; ++i) ext += bytes[i];
    if (base != bytes[63]) return "EEPROM CC_BASE mismatch";
    if (ext != bytes[95]) return "EEPROM CC_EXT mismatch";
    return NULL;
}

/* Print bounded ASCII, replacing control/non-ASCII bytes and trimming padding. */
static void sfp_eeprom_text(FILE *out, const uint8_t *bytes, unsigned length) {
    while (length && (bytes[length-1] == ' ' || !bytes[length-1])) --length;
    for (unsigned i = 0; i < length; ++i)
        fputc(bytes[i] >= 32 && bytes[i] <= 126 ? bytes[i] : '?', out);
}

/* Report advertised fields, not measured rates or a verdict on link compatibility.
 * Raw codes retain information for optics and newer encodings without guessing.
 */
static void sfp_eeprom_report(FILE *out, const uint8_t bytes[96]) {
    fputs("SFP vendor=", out); sfp_eeprom_text(out, bytes + 20, 16);
    fputs(" part=", out); sfp_eeprom_text(out, bytes + 40, 16);
    fputs(" revision=", out); sfp_eeprom_text(out, bytes + 56, 4);
    fputs(" serial=", out); sfp_eeprom_text(out, bytes + 68, 16);
    fputs(" date=", out); sfp_eeprom_text(out, bytes + 84, 8);
    fprintf(out, "\nOUI=%02x:%02x:%02x connector=0x%02x encoding=0x%02x "
            "passive_cable=%u active_cable=%u\n",
            bytes[37], bytes[38], bytes[39], bytes[2], bytes[11],
            !!(bytes[8] & 4), !!(bytes[8] & 8));
    // The 255 sentinel needs fields outside this reader's deliberately small map.
    if (bytes[12] == 0 || bytes[12] == 255)
        fprintf(out, "nominal_rate=unspecified_or_extended (code=0x%02x)\n", bytes[12]);
    else fprintf(out, "nominal_rate=%u MBd (advertised)\n", bytes[12] * 100u);
    fprintf(out, "diagnostics=%u sff8472=0x%02x CC_BASE=ok CC_EXT=ok\n",
            !!(bytes[92] & 64), bytes[94]);
    fputs("A0[0..95]=", out);
    for (unsigned i = 0; i < 96; ++i) fprintf(out, "%02x", bytes[i]);
    fputc('\n', out);
}
#endif
