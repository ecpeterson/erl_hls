#include "ps_i2c.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

// Controller fault cases include error+complete, a missing STOP, and a short RX.
enum fault { HEALTHY, INITIAL_BUSY, NACK, ARBITRATION, HW_TIMEOUT, RX_OVERRUN,
             NO_COMPLETION, NO_RX_DATA, SHORT_RX, NO_STOP, POINTER_NACK };
struct controller {
    uint32_t regs[11]; uint8_t bytes[2];
    unsigned count, transactions, reads, writes, delays;
    enum fault fault; bool receive;
};

// Completion follows address launch; errors must win even when COMPLETE is set.
static uint32_t read_controller(void *context, unsigned offset) {
    struct controller *c=context; ++c->reads;
    if (offset==4) {
        if (c->fault==INITIAL_BUSY || (c->transactions && c->fault==NO_STOP)) return 0x100;
        return c->receive && c->fault!=NO_RX_DATA ? 0x20 : 0;
    }
    if (offset==16 && c->transactions) {
        switch (c->fault) {
            case NACK: case POINTER_NACK: return 5;
            case ARBITRATION: return 0x201;
            case HW_TIMEOUT: return 9;
            case RX_OVERRUN: return 0x21;
            case NO_COMPLETION: return 0;
            default: return 1;
        }
    }
    if (offset==20) return c->fault==SHORT_RX ? 1 : 0;
    if (offset==12) { assert(c->receive); return 0x5a; }
    return c->regs[offset/4];
}

// Require FIFO setup and clean interrupt state before addressing the fixed chip.
static void write_controller(void *context, unsigned offset, uint32_t value) {
    struct controller *c=context; ++c->writes;
    if (offset==0) {
        assert((value&0xfffe)==0x324e); // /51, ACK, 7-bit master, clear FIFO, never HOLD.
        c->receive=value&1; c->count=0;
    } else if (offset==12) {
        assert(c->count<2); c->bytes[c->count++]=value;
    } else if (offset==8) {
        assert(value==0x70 && c->regs[16/4]==0x2ff);
        if (c->receive) assert(c->regs[20/4]==1);
        else {
            assert(c->count>=1 && c->bytes[0]==0x27);
            if (c->count==2) assert(c->bytes[1]==0xa5);
        }
        ++c->transactions;
    }
    c->regs[offset/4]=value;
}

// Capture the maximum wait budget without making unit tests depend on wall time.
static void delay_controller(void *context, unsigned us) {
    struct controller *c=context; assert(us==10); c->delays+=us;
}

// Test the actual polled transport without the vendor's unbounded I2C wrappers.
int main(void) {
    for (enum fault fault=HEALTHY; fault<=POINTER_NACK; ++fault) {
        struct controller c={.fault=fault};
        struct ps_i2c b={&c,read_controller,write_controller,delay_controller,0,0};
        int error=ps_i2c_init(&b);
        if (fault==INITIAL_BUSY) {
            assert(error==PS_I2C_BUSY && !c.writes && c.delays==10000); continue;
        }
        assert(!error);
        uint8_t value=0xff;
        error=ps_i2c_read(&b,0x27,&value);
        assert((error==0)==(fault==HEALTHY));
        if (!error) assert(value==0x5a && c.transactions==2);
        if (fault==POINTER_NACK) assert(c.transactions==1 && value==0xff);
        if (fault==NO_RX_DATA || fault==SHORT_RX) assert(error==PS_I2C_SHORT);
        if (fault==NO_COMPLETION) assert(error==PS_I2C_TIMEOUT);
        if (fault==NO_STOP) assert(error==PS_I2C_BUSY);
        assert(c.delays<=10000 && c.regs[0]==0x324e);
    }
    struct controller c={0};
    struct ps_i2c b={&c,read_controller,write_controller,delay_controller,0,0};
    assert(!ps_i2c_init(&b) && !ps_i2c_write(&b,0x27,0xa5));
    assert(c.transactions==1);
    puts("PASS: PS I2C register sequencing, short reads, NACK/arbitration/timeout, stuck bus and bounded cleanup");
    return 0;
}
