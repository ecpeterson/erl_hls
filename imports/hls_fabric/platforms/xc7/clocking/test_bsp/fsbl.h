// Minimal standalone BSP contract used only by the host hook integration test.
#include <stdint.h>
typedef uint32_t u32;
enum { XST_SUCCESS=0, XST_FAILURE=1 };
// Hardware access is forbidden in the hook test; the PS transport is substituted.
uint32_t Xil_In32(uint32_t address);
void Xil_Out32(uint32_t address, uint32_t value);
// The test discards UART diagnostics; real builds use the pinned BSP formatter.
void xil_printf(const char *format, ...);
