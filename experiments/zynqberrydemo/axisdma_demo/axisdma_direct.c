// axisdma_direct.c

#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <string.h>

#define AXISDMA_IOC_MAGIC  'q'
struct axisdma_info {
    uint32_t bufsz;
    uint32_t _pad;
    uint64_t tx_dma;
    uint64_t rx_dma;
};
#define AXISDMA_IOC_GET_INFO _IOR(AXISDMA_IOC_MAGIC, 3, struct axisdma_info)

#define DMA_BASE 0x40400000
#define DMA_MAP_SIZE 0x1000

#define MM2S_DMACR   0x00
#define MM2S_DMASR   0x04
#define MM2S_SA      0x18
#define MM2S_LENGTH  0x28

#define S2MM_DMACR   0x30
#define S2MM_DMASR   0x34
#define S2MM_DA      0x48
#define S2MM_LENGTH  0x58

static inline void reg_write(volatile uint32_t *base, uint32_t off, uint32_t v)
{
    base[off / 4] = v;
}

static inline uint32_t reg_read(volatile uint32_t *base, uint32_t off)
{
    return base[off / 4];
}

int main(void)
{
    int fd = open("/dev/axisdma0", O_RDWR);
    if (fd < 0) { perror("open axisdma0"); return 1; }

    struct axisdma_info info;
    if (ioctl(fd, AXISDMA_IOC_GET_INFO, &info) < 0) {
        perror("GET_INFO");
        return 1;
    }

    uint32_t *tx = mmap(NULL, info.bufsz, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (tx == MAP_FAILED) { perror("mmap tx"); return 1; }

    uint32_t *rx = mmap(NULL, info.bufsz, PROT_READ|PROT_WRITE, MAP_SHARED, fd, info.bufsz);
    if (rx == MAP_FAILED) { perror("mmap rx"); return 1; }

    const uint32_t words = 1024;
    const uint32_t len = words * sizeof(uint32_t);

    for (uint32_t i = 0; i < words; i++) {
        tx[i] = i;
        rx[i] = 0xdeadbeef;
    }

    int memfd = open("/dev/mem", O_RDWR | O_SYNC);
    if (memfd < 0) { perror("open /dev/mem"); return 1; }

    volatile uint32_t *regs = mmap(NULL, DMA_MAP_SIZE, PROT_READ|PROT_WRITE,
                                   MAP_SHARED, memfd, DMA_BASE);
    if (regs == MAP_FAILED) { perror("mmap regs"); return 1; }

    /* Start channels */
    reg_write(regs, S2MM_DMACR, 0x00000001);
    reg_write(regs, MM2S_DMACR, 0x00000001);

    /* Program destination/source addresses */
    reg_write(regs, S2MM_DA, (uint32_t)info.rx_dma);
    reg_write(regs, MM2S_SA, (uint32_t)info.tx_dma);

    /* Kick transfers: RX first, then TX */
    reg_write(regs, S2MM_LENGTH, len);
    reg_write(regs, MM2S_LENGTH, len);

    /* Poll for idle */
    for (int i = 0; i < 1000000; i++) {
        uint32_t s2mm = reg_read(regs, S2MM_DMASR);
        uint32_t mm2s = reg_read(regs, MM2S_DMASR);
        if ((s2mm & 0x2) && (mm2s & 0x2))
            break;
    }

    printf("MM2S_DMASR=%08x S2MM_DMASR=%08x\n",
           reg_read(regs, MM2S_DMASR), reg_read(regs, S2MM_DMASR));

    for (uint32_t i = 0; i < 8; i++) {
        printf("[%u] tx=%08x rx=%08x expect=%08x\n",
               i, tx[i], rx[i], tx[i] + 1);
    }

    return 0;
}