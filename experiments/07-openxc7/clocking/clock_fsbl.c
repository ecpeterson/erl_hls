// TE0715 clock-specific FSBL hooks. Cold boot only; VCCIO34 must be 1.8 V.
#include "fsbl.h"
#include "sleep.h"
#include "xparameters.h"
#include "ps_i2c.h"
#include "si5338.h"

#if XPAR_PS7_I2C_1_BASEADDR != 0xE0005000 || XPAR_PS7_I2C_1_I2C_CLK_FREQ_HZ != 111111115
#error Clock probe requires the pinned TE0715 PS I2C1 configuration
#endif

// Order PS peripheral reads with the BSP's MMIO primitives.
static uint32_t read_ps(void *context, unsigned offset) {
    (void)context;
    return Xil_In32(XPAR_PS7_I2C_1_BASEADDR + offset);
}

// The standalone BSP supplies the required device-memory ordering.
static void write_ps(void *context, unsigned offset, uint32_t value) {
    (void)context;
    Xil_Out32(XPAR_PS7_I2C_1_BASEADDR + offset, value);
}

// PS timer delays remain available while the independent Si5338 outputs stop.
static void delay_us(void *context, unsigned microseconds) { (void)context; usleep(microseconds); }

// Translate the clock driver's millisecond delay into the standalone timer API.
static void delay_ms(void *context, unsigned milliseconds) { delay_us(context, milliseconds * 1000); }

// Include the last register, bus fault and cleanup outcome in every phase report.
static void report(const char *phase, struct si_report *r) {
    xil_printf("CLOCK %s error=%d bus=%d cleanup=%d revision=%u grade=%u nvm=%u status=%02x enables=%02x\r\n",
               phase, r->error, r->bus_error, r->cleanup_error, r->revision, r->grade,
               (unsigned)r->nvm_code, r->status, r->enables);
    xil_printf("CLOCK differences=%u register=%u expected=%02x actual=%02x mask=%02x\r\n",
               r->mismatches, r->reg, r->expected, r->actual, r->mask);
}

// Shared exclusive PS bus; startup precedes PL configuration and is repeated only on cold boot.
static struct ps_i2c bus = {0, read_ps, write_ps, delay_us, 0, 0};

// Record existing state, then initialize and verify volatile clocks before PL load.
u32 TE_FsblHookBeforeBitstreamDload_Custom(void) {
    struct si_io io = {&bus, ps_i2c_read, ps_i2c_write, delay_ms};
    struct si_report r;
    int error = ps_i2c_init(&bus);
    if (error) { xil_printf("CLOCK controller error=%d status=%08x\r\n", error, (unsigned)bus.status); return XST_FAILURE; }
    enum si_error previous = si5338_readback(io, &r);
    report("before", &r);
    if (previous != SI_OK && previous != SI_VERIFY) return XST_FAILURE;
    error = si5338_configure(io, &r);
    report("configured", &r);
    if (error) return XST_FAILURE;
    xil_printf("CLOCK profile verified: CLK2=125000000 LVDS18 CLK3=50000000 CMOS18; frequency not measured\r\n");
    return XST_SUCCESS;
}

// No post-bitstream action is needed; consumers remain controlled by the probe.
u32 TE_FsblHookAfterBitstreamDload_Custom(void) { return XST_SUCCESS; }

// Refuse Linux handoff if the profile or live lock no longer passes readback.
u32 TE_FsblHookBeforeHandoff_Custom(void) {
    struct si_io io = {&bus, ps_i2c_read, ps_i2c_write, delay_ms};
    struct si_report r;
    enum si_error error = si5338_readback(io, &r);
    report("handoff", &r);
    return error ? XST_FAILURE : XST_SUCCESS;
}

// Preserve the normal FSBL fallback policy after printing the failing clock phase.
void TE_FsblHookFallback_Custom(void) {}
