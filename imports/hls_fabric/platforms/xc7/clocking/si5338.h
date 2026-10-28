#ifndef HLS_SI5338_H
#define HLS_SI5338_H
#include <stdbool.h>
#include <stdint.h>

// One exclusive controller of the TE0715's Si5338 at address 0x70. Each callback
// must terminate; return zero on I/O success. Delay is measured in milliseconds.
struct si_io {
    void *context;
    int (*read)(void *, uint8_t, uint8_t *);
    int (*write)(void *, uint8_t, uint8_t);
    void (*delay)(void *, unsigned);
};

// Failure categories distinguish transport, identity, input, lock and readback.
enum si_error { SI_OK, SI_IO, SI_IDENTITY, SI_INPUT_TIMEOUT, SI_LOCK_TIMEOUT, SI_VERIFY };

// Readback evidence; register is absolute (page*256+offset). cleanup_error is a
// separate transport failure while trying to restore page zero/disable outputs.
struct si_report {
    enum si_error error;
    int bus_error, cleanup_error;
    uint16_t reg, mismatches;
    uint8_t expected, actual, mask, revision, grade, status, enables;
    uint32_t nvm_code;
};

// Observe identity, clock profile and live alarms. Only the register-page selector
// is written; no output, divider, calibration, reset or NVM setting is changed.
enum si_error si5338_readback(struct si_io io, struct si_report *report);

// Apply the pinned volatile CLK2=125 MHz / CLK3=50 MHz profile, verify writes,
// calibrate and check lock. Caller must quiesce all clock consumers beforehand.
// Never programs NVM. On failure after disabling outputs, attempts to leave them
// disabled; a failed I2C bus cannot guarantee that cleanup reached the chip.
enum si_error si5338_configure(struct si_io io, struct si_report *report);
#endif
