// Verify the actual board hooks propagate failures and order controller/profile checks.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "test_bsp/fsbl.h"
#include "ps_i2c.h"
#include "si5338.h"

// Hook entry points match the vendor wrapper; neither test implements its own boot flow.
u32 TE_FsblHookBeforeBitstreamDload_Custom(void);
u32 TE_FsblHookBeforeHandoff_Custom(void);

// Configurable driver outcomes and event order for one startup attempt.
static int init_error, sequence, configurations, observations;
static enum si_error read_error, config_error;

// MMIO and timer access would escape the substituted transport and fail the test.
uint32_t Xil_In32(uint32_t address) { (void)address; assert(0); return 0; }
void Xil_Out32(uint32_t address, uint32_t value) { (void)address; (void)value; assert(0); }
void usleep(unsigned microseconds) { (void)microseconds; assert(0); }
// Suppress UART noise while exercising every failure outcome.
void xil_printf(const char *format, ...) { (void)format; }

// The first hook operation must initialize the exclusive PS bus.
int ps_i2c_init(struct ps_i2c *bus) {
    assert(sequence++ == 0 && bus->read && bus->write && bus->delay);
    return init_error;
}
// Clock API substitutions must retain these real transport callbacks.
int ps_i2c_read(void *context, uint8_t reg, uint8_t *value) {
    (void)context; (void)reg; (void)value; assert(0); return -1;
}
int ps_i2c_write(void *context, uint8_t reg, uint8_t value) {
    (void)context; (void)reg; (void)value; assert(0); return -1;
}

// Observe before configuration and again at handoff, with the same bus callbacks.
enum si_error si5338_readback(struct si_io io, struct si_report *report) {
    assert(io.read == ps_i2c_read && io.write == ps_i2c_write && io.context && io.delay);
    assert(sequence == 1 || sequence == 3);
    ++sequence; ++observations;
    memset(report, 0, sizeof(*report));
    return report->error = read_error;
}
// Configure exactly once after an acceptable initial observation.
enum si_error si5338_configure(struct si_io io, struct si_report *report) {
    assert(sequence++ == 2 && io.context);
    ++configurations;
    memset(report, 0, sizeof(*report));
    return report->error = config_error;
}

// Every init/identity/configuration error blocks PL loading; late failures block handoff.
int main(void) {
    for (init_error=0; init_error<=1; ++init_error)
        for (read_error=SI_OK; read_error<=SI_VERIFY; ++read_error)
            for (config_error=SI_OK; config_error<=SI_VERIFY; ++config_error) {
                sequence=configurations=observations=0;
                int eligible=!init_error && (read_error==SI_OK || read_error==SI_VERIFY);
                u32 result=TE_FsblHookBeforeBitstreamDload_Custom();
                assert((result==XST_SUCCESS) == (eligible && config_error==SI_OK));
                assert(configurations==eligible && observations==!init_error);
            }
    for (read_error=SI_OK; read_error<=SI_VERIFY; ++read_error) {
        sequence=3;
        assert((TE_FsblHookBeforeHandoff_Custom()==XST_SUCCESS) == (read_error==SI_OK));
    }
    puts("PASS: FSBL hook ordering, initial-profile tolerance and startup/handoff failures");
    return 0;
}
