#ifndef SFP_IO_H
#define SFP_IO_H
#include <stdint.h>

/* Word offsets in the SFP7 ABI-2 GP0 page; only CONTROL is writable. */
enum { SFP_ID, SFP_ABI, SFP_CONTROL, SFP_CYCLES, SFP_WRITES,
       SFP_RAW, SFP_FRAMES, SFP_DIVISOR, SFP_SDA };
enum { SFP_SCL_LOW = 1u << 8, SFP_SDA_LOW = 1u << 9,
       SFP_I2C_MASK = SFP_SCL_LOW | SFP_SDA_LOW };

/* Ordered word I/O and a delay of at least the requested microseconds.
 * Callers own the page exclusively and provide a running 25-MHz FCLK.
 */
struct sfp_io {
    void *context;
    uint32_t (*read)(void *, unsigned);
    void (*write)(void *, unsigned, uint32_t);
    void (*wait)(void *, unsigned);
};
#endif
