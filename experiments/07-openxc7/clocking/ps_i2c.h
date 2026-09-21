#ifndef HLS_PS_I2C_H
#define HLS_PS_I2C_H
#include <stdint.h>

// Exclusive, polled PS I2C1 access. MMIO callbacks use byte offsets. The delay
// callback waits at least the requested microseconds; no interrupts are needed.
struct ps_i2c {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    void (*delay)(void *, unsigned);
    uint32_t status, interrupts;
};

// Negative software timeouts; positive failures retain the controller ISR bits.
enum ps_i2c_error { PS_I2C_BUSY = -1, PS_I2C_TIMEOUT = -2, PS_I2C_SHORT = -3 };

// Set 7-bit addressing and <=100 kHz from the pinned 111111115-Hz PS input clock.
// Refuse a busy bus; this driver neither steals ownership nor emits recovery clocks.
int ps_i2c_init(struct ps_i2c *bus);

// Read/write one register at the fixed Si5338 address 0x70; each idle/completion
// wait has a 10-ms poll budget. A read uses two transfers, a write one. Failed
// transfers clear the local FIFO/HOLD, without retries.
int ps_i2c_read(void *context, uint8_t reg, uint8_t *value);
int ps_i2c_write(void *context, uint8_t reg, uint8_t value);
#endif
