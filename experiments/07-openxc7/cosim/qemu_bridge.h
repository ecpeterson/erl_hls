#ifndef HLS_QEMU_BRIDGE_H
#define HLS_QEMU_BRIDGE_H
#include "system/memory.h"
#include "hw/irq.h"
/* Attach the experiment's optional PL window and IRQ when HLS_COSIM_SOCKET is set. */
void hls_cosim_init(MemoryRegion *memory, qemu_irq app_irq, qemu_irq debug_irq);
#endif
