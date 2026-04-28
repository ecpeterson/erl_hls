// axisdma_test.c

#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdlib.h>

#define AXISDMA_IOC_MAGIC  'q'
#define AXISDMA_IOC_GET_BUFSZ _IOR(AXISDMA_IOC_MAGIC, 1, uint32_t)
#define AXISDMA_IOC_START     _IOW(AXISDMA_IOC_MAGIC, 2, uint32_t)
// NOTE: AXISDMS_IOC_START triggers read and write on data buffers, but ioctl
//       only writes the len to the driver + returns nothing to the caller, so
//       the ioctl call gets designated _IOW.

int main(void)
{
    int fd = open("/dev/axisdma0", O_RDWR);
    if (fd < 0) { perror("open"); return 1; }

    uint32_t bufsz;
    if (ioctl(fd, AXISDMA_IOC_GET_BUFSZ, &bufsz) < 0) {
        perror("GET_BUFSZ");
        return 1;
    }

    uint32_t *tx = mmap(NULL, bufsz, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    uint32_t *rx = mmap(NULL, bufsz, PROT_READ|PROT_WRITE, MAP_SHARED, fd, bufsz);
    if (tx == MAP_FAILED || rx == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    const uint32_t words = 1024;
    for (uint32_t i = 0; i < words; i++)
        tx[i] = i;
    for (uint32_t i = 0; i < words; i++)
        rx[i] = 0xdeadbeef;

    uint32_t len = words * sizeof(uint32_t);
    if (ioctl(fd, AXISDMA_IOC_START, &len) < 0) {
        perror("START");
        return 1;
    }

    printf("bare results:\n");
    for (uint32_t i = 0; i < 8; i++) {
        printf("[%u] tx=%08x rx=%08x expect=%08x\n",
               i, tx[i], rx[i], tx[i] + 1);
    }

    printf("\nmatch results:\n");
    int bad = 0;
    for (uint32_t i = 0; i < words; i++) {
        uint32_t expect = tx[i] + 1;
        if (rx[i] != expect) {
            printf("mismatch[%u]: tx=%08x rx=%08x expect=%08x\n",
                   i, tx[i], rx[i], expect);
            bad = 1;
            break;
        }
    }

    if (!bad)
        printf("PASS\n");

    return bad ? 1 : 0;
}
