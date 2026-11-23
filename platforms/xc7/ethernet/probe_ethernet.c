// Read ETH7 GP0 diagnostics through Linux UIO. --run explicitly starts one
// five-second attempt with fixed test frames, then stops it. Default is read-only.
// Build for the board with the same ARM compiler as probe_zynq_ps.c.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

// Wait in the host without depending on user clocks or retrying device faults.
static void pause_ms(unsigned ms) {
    struct timespec delay = {ms / 1000, (long)(ms % 1000) * 1000000};
    while (nanosleep(&delay, &delay) && errno == EINTR) {}
}

// Take one bounded register sample; counters may lag and are not one global snapshot.
static void show(volatile uint32_t *regs) {
    uint32_t status = regs[5];
    printf("status=%08" PRIx32 " state=%u fault=%u tx_link=%u rx_link=%u "
           "tx_mmcm=%u rx_mmcm=%u sent=%" PRIu32 " received=%" PRIu32 " bad=%" PRIu32 "\n",
           status, status & 7, (status >> 12) & 15, (status >> 16) & 1,
           (status >> 17) & 1, (status >> 18) & 1, (status >> 19) & 1,
           regs[6], regs[7], regs[8]);
}

// Check identity before any write; an explicit attempt always leaves run disabled.
int main(int argc, char **argv) {
    bool run = argc == 3 && strcmp(argv[2], "--run") == 0;
    if (argc != 2 && !run) {
        fprintf(stderr, "usage: %s /dev/uioN [--run]\n", argv[0]);
        return 2;
    }
    int fd = open(argv[1], (run ? O_RDWR : O_RDONLY) | O_SYNC);
    if (fd < 0) { perror("open UIO"); return 1; }
    volatile uint32_t *regs = mmap(NULL, 4096, PROT_READ | (run ? PROT_WRITE : 0), MAP_SHARED, fd, 0);
    close(fd);
    if (regs == MAP_FAILED) { perror("mmap UIO"); return 1; }
    int result = 0;
    if (regs[0] != UINT32_C(0x45544837) || regs[1] != 1) {
        fprintf(stderr, "not an ETH7 ABI-1 register bank\n"); result = 1;
    } else if (!run) {
        show(regs);
    } else {
        regs[2] = 0; __sync_synchronize(); pause_ms(1);
        regs[2] = 3; __sync_synchronize();
        result = 1;
        for (unsigned poll = 0; poll < 500; ++poll) {
            pause_ms(10);
            uint32_t status = regs[5];
            if ((status & 7) == 7 || regs[8] != 0) break;
            if ((status & UINT32_C(0x30000)) == UINT32_C(0x30000) && regs[6] >= 5 && regs[7] >= 5) {
                result = 0; break;
            }
        }
        show(regs);
        regs[2] = 0; __sync_synchronize();
        puts(result ? "FAIL: no clean bidirectional packet progress" : "PASS: packet progress (not timing/BER qualification)");
    }
    munmap((void *)regs, 4096);
    return result;
}
