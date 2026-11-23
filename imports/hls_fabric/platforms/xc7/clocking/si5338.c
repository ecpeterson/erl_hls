// Skyworks Si5338 datasheet Figure 9, with bounded polling and checked I/O.
#include "si5338.h"
#include <stddef.h>
#include <string.h>

// Pinned configuration byte; address includes the register page.
struct si_register { uint16_t address; uint8_t value, mask; };
#include "profile.h"

// A transaction latches its first failure so subsequent configuration writes stop.
struct access { struct si_io io; struct si_report *r; uint8_t page; };

// Record an I2C failure without obscuring the first failing register.
static void failed(struct access *a, int error, uint16_t reg) {
    if (error && !a->r->error) {
        a->r->error = SI_IO; a->r->bus_error = error; a->r->reg = reg;
    }
}

// Select a register page explicitly, including after an interrupted earlier user.
static void page(struct access *a, uint8_t value) {
    if (!a->r->error && a->page != value) {
        failed(a, a->io.write(a->io.context, 255, value), 255);
        if (!a->r->error) a->page = value;
    }
}

// Read one byte; failure latches in the report and suppresses later configuration.
static uint8_t read_reg(struct access *a, uint16_t reg) {
    uint8_t value = 0;
    page(a, reg >> 8);
    if (!a->r->error) failed(a, a->io.read(a->io.context, reg & 255, &value), reg);
    return value;
}

// Write one byte without retrying a possibly accepted transaction.
static void write_reg(struct access *a, uint16_t reg, uint8_t value) {
    page(a, reg >> 8);
    if (!a->r->error) failed(a, a->io.write(a->io.context, reg & 255, value), reg);
}

// Compare writable bits while retaining the first difference and total count.
static void compare(struct access *a, uint16_t reg, uint8_t expected, uint8_t mask) {
    uint8_t actual = read_reg(a, reg);
    if (!a->r->error && ((actual ^ expected) & mask)) {
        if (!a->r->mismatches) {
            a->r->reg = reg; a->r->expected = expected; a->r->actual = actual; a->r->mask = mask;
        }
        ++a->r->mismatches;
    }
}

// Preserve all bits excluded by the vendor mask and check that the write stuck.
static void masked_write(struct access *a, uint16_t reg, uint8_t value, uint8_t mask) {
    uint8_t old = mask == 255 ? 0 : read_reg(a, reg);
    write_reg(a, reg, (old & ~mask) | (value & mask));
    compare(a, reg, value, mask);
    if (!a->r->error && a->r->mismatches) a->r->error = SI_VERIFY;
}

// Require Si5338A, silicon revision B, and retain the module's factory NVM code.
static void identify(struct access *a) {
    a->r->revision = read_reg(a, 0) & 7;
    uint8_t part = read_reg(a, 2) & 63, grade = read_reg(a, 3);
    a->r->grade = grade >> 3;
    a->r->nvm_code = (uint32_t)(grade & 1) << 16;
    a->r->nvm_code |= (uint32_t)read_reg(a, 4) << 8;
    a->r->nvm_code |= read_reg(a, 5);
    if (!a->r->error && (part != 38 || a->r->grade != 1 || a->r->revision != 1))
        a->r->error = SI_IDENTITY;
}

// Check static profile bits and the retained calibration against the live FCAL result.
static void check_profile(struct access *a, bool enabled) {
    for (unsigned i = 0; i < sizeof(si_profile) / sizeof(si_profile[0]); ++i) {
        struct si_register r = si_profile[i];
        if (r.address == 45 || r.address == 46) continue;
        if (r.address == 47) r.mask &= 0xfc;
        if (r.address == 49) r.mask &= 0x7f;
        compare(a, r.address, r.value, r.mask);
    }
    compare(a, 230, enabled ? 3 : 0x13, 0x1f); // Individual enables survive global muting.
    compare(a, 241, 0x65, 0xff); // Loss-of-lock observation must remain active.
    compare(a, 49, 0x80, 0x80);
    uint8_t low = read_reg(a, 235), middle = read_reg(a, 236), high = read_reg(a, 237);
    compare(a, 45, low, 255); compare(a, 46, middle, 255); compare(a, 47, high, 3);
    a->r->status = read_reg(a, 218);
    a->r->enables = read_reg(a, 230);
    // Feedback LOS is irrelevant: the pinned profile uses internal feedback.
    if (!a->r->error && (a->r->mismatches || (a->r->status & 0x15))) a->r->error = SI_VERIFY;
}

// Always attempt page-zero restoration; after a failed write sequence also mute
// the outputs. Preserve the main error and report cleanup transport errors apart.
static void finish(struct access *a, bool disable) {
    int error = (a->page != 0 || a->r->error == SI_IO) ? a->io.write(a->io.context, 255, 0) : 0;
    if (!error && disable) {
        uint8_t value;
        error = a->io.read(a->io.context, 230, &value);
        if (!error) error = a->io.write(a->io.context, 230, value | 0x10);
    }
    a->r->cleanup_error = error;
    failed(a, error, 255);
}

// Bound each input/PLL poll to one second plus the bounded I2C operation costs.
static void wait_clear(struct access *a, uint8_t mask, enum si_error timeout) {
    for (unsigned i = 0; i < 1000 && !a->r->error; ++i) {
        a->r->status = read_reg(a, 218);
        if (!(a->r->status & mask)) return;
        a->io.delay(a->io.context, 1);
    }
    if (!a->r->error) { a->r->error = timeout; a->r->reg = 218; }
}

// Readback leaves functional clock state untouched, even on a profile mismatch.
enum si_error si5338_readback(struct si_io io, struct si_report *report) {
    memset(report, 0, sizeof(*report));
    struct access a = {io, report, 255};
    identify(&a);
    if (!report->error) check_profile(&a, true);
    finish(&a, false);
    return report->error;
}

// Only the documented soft-reset operation is used; no hard reset or NVM writes.
enum si_error si5338_configure(struct si_io io, struct si_report *report) {
    memset(report, 0, sizeof(*report));
    struct access a = {io, report, 255};
    identify(&a);
    if (report->error) { finish(&a, false); return report->error; }
    masked_write(&a, 230, 0x10, 0x10);
    masked_write(&a, 241, 0x80, 0x80);
    for (unsigned i = 0; i < sizeof(si_profile) / sizeof(si_profile[0]) && !report->error; ++i) {
        struct si_register r = si_profile[i];
        masked_write(&a, r.address, r.value, r.mask);
    }
    wait_clear(&a, 4, SI_INPUT_TIMEOUT);
    masked_write(&a, 49, 0, 0x80);
    write_reg(&a, 246, 2);
    if (!report->error) io.delay(io.context, 25);
    masked_write(&a, 241, 0x65, 0xff);
    wait_clear(&a, 0x15, SI_LOCK_TIMEOUT);
    uint8_t high = read_reg(&a, 237), middle = read_reg(&a, 236), low = read_reg(&a, 235);
    masked_write(&a, 47, (high & 3) | 0x14, 0x3f);
    masked_write(&a, 46, middle, 0xff);
    masked_write(&a, 45, low, 0xff);
    masked_write(&a, 49, 0x80, 0x80);
    // Check all programmed state before the final output-enable transition.
    if (!report->error) check_profile(&a, false);
    masked_write(&a, 230, 3, 0x1f);
    report->status = read_reg(&a, 218);
    report->enables = read_reg(&a, 230);
    if (!report->error && (report->status & 0x15)) report->error = SI_VERIFY;
    finish(&a, report->error != SI_OK);
    return report->error;
}
