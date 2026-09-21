// Zynq-7000 UG585 I2C register interface, restricted to one/two-byte transfers.
// Bit definitions agree with pinned AMD 2023.2 xiicps_hw.h.
#include "ps_i2c.h"
#include <stdbool.h>

enum { CR=0, SR=4, ADDR=8, DATA=12, ISR=16, SIZE=20, TIMEOUT=28, IDR=40 };
enum { BUS_ACTIVE=0x100, RX_DATA=0x20, FIFO_CLEAR=0x40, RX=1,
       COMPLETE=1, ERRORS=0x2ec, ALL=0x2ff, CONTROL=(50<<8)|0x0e };

// Wait for STOP/bus idle, retaining the last status when another owner or fault blocks it.
static int idle(struct ps_i2c *b) {
    for (unsigned poll=0; poll<1000; ++poll) {
        b->status=b->read(b->context, SR);
        if (!(b->status & BUS_ACTIVE)) return 0;
        b->delay(b->context, 10);
    }
    return PS_I2C_BUSY;
}

// Configure the local controller only after idle; divisor B=50 gives 99.03 kHz.
int ps_i2c_init(struct ps_i2c *b) {
    b->interrupts=0;
    int error=idle(b);
    if (error) return error;
    b->write(b->context, IDR, ALL);
    b->write(b->context, CR, CONTROL|FIFO_CLEAR);
    b->write(b->context, ISR, ALL);
    b->write(b->context, TIMEOUT, 255);
    return 0;
}

// A complete transaction must have no errors, exact RX data and a completed STOP.
// No HOLD or repeated-start path is used; reads use pointer-write then receive.
static int transfer(struct ps_i2c *b, bool receive, uint8_t *bytes, unsigned count) {
    b->interrupts=0;
    int error=idle(b);
    if (error) return error;
    b->write(b->context, CR, CONTROL|FIFO_CLEAR|(receive ? RX : 0));
    b->write(b->context, ISR, ALL);
    if (receive) b->write(b->context, SIZE, 1);
    else for (unsigned i=0; i<count; ++i) b->write(b->context, DATA, bytes[i]);
    b->write(b->context, ADDR, 0x70);
    error=PS_I2C_TIMEOUT;
    for (unsigned poll=0; poll<1000; ++poll) {
        b->interrupts=b->read(b->context, ISR);
        if (b->interrupts & ERRORS) { error=(int)(b->interrupts & ERRORS); break; }
        if (b->interrupts & COMPLETE) {
            b->status=b->read(b->context, SR);
            if (receive && (!(b->status & RX_DATA) || b->read(b->context, SIZE))) error=PS_I2C_SHORT;
            else {
                if (receive) bytes[0]=(uint8_t)b->read(b->context, DATA);
                error=idle(b);
            }
            break;
        }
        b->delay(b->context, 10);
    }
    // Leave no queued byte or held SCL. The physical bus may still be stuck low.
    b->write(b->context, CR, CONTROL|FIFO_CLEAR);
    return error;
}

// Address byte and register value are committed in one non-retried transaction.
int ps_i2c_write(void *context, uint8_t reg, uint8_t value) {
    uint8_t bytes[2]={reg,value};
    return transfer(context, false, bytes, 2);
}

// Abort on a failed pointer write; never read stale FIFO data as a register value.
int ps_i2c_read(void *context, uint8_t reg, uint8_t *value) {
    int error=transfer(context, false, &reg, 1);
    return error ? error : transfer(context, true, value, 1);
}
