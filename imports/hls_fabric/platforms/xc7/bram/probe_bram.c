#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum { REG_ID, REG_ABI, REG_CONTROL, REG_CYCLES, REG_WRITES, REG_STATUS,
       REG_DETAIL, REG_VALUE_A, REG_VALUE_B };
#define BRAM_ID UINT32_C(0x4252414d)

/* Order one MMIO access before the next CPU/device observation. */
static void barrier(void) { __sync_synchronize(); }

/* Read one aligned register from the mapped UIO page. */
static uint32_t read_word(volatile uint32_t *registers, unsigned word) {
    barrier();
    uint32_t value = registers[word];
    barrier();
    return value;
}

/* Select a bank/detail page through the byte-writeable control register. */
static void write_control(volatile uint32_t *registers, uint32_t value) {
    barrier();
    registers[REG_CONTROL] = value;
    barrier();
}

/* Wait for the autonomous bounded test, then report every bank's first mismatch. */
static int run(volatile uint32_t *registers) {
    if (read_word(registers, REG_ID) != BRAM_ID || read_word(registers, REG_ABI) != 1) {
        fprintf(stderr, "unexpected BRAM probe identity/ABI\n");
        return 1;
    }
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000};
    uint32_t header = 0;
    for (unsigned attempt = 0; attempt < 1000; ++attempt) {
        header = read_word(registers, REG_STATUS);
        if (header & UINT32_C(4)) break;
        while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
    }
    if (!(header & UINT32_C(4))) {
        fprintf(stderr, "BRAM self-test did not complete: status=%08x\n", header);
        return 1;
    }
    int failed = 0;
    static const char *names[] = {"state-387x4", "state-537x4",
                                  "mailbox-128x16", "trace-192x32"};
    for (unsigned bank = 0; bank < 4; ++bank) {
        write_control(registers, bank);
        uint32_t bank_status = read_word(registers, REG_STATUS);
        uint32_t detail = read_word(registers, REG_DETAIL);
        uint32_t lanes = read_word(registers, REG_VALUE_A);
        uint32_t digest = read_word(registers, REG_VALUE_B);
        write_control(registers, bank | UINT32_C(0x10));
        uint32_t actual = read_word(registers, REG_VALUE_A);
        uint32_t expected = read_word(registers, REG_VALUE_B);
        unsigned count = detail >> 16;
        unsigned pattern = (detail >> 9) & 7;
        unsigned address = (detail >> 4) & 31;
        int bank_failed = (bank_status & UINT32_C(2)) != 0;
        printf("bank=%u name=%s done=%u failed=%u mismatches=%u pattern=%u "
               "address=%u lanes=%04x digest=%08x actual_low=%08x expected_low=%08x\n",
               bank, names[bank], bank_status & 1, bank_failed, count, pattern,
               address, lanes & UINT32_C(0xffff), digest, actual, expected);
        failed |= bank_failed || !(bank_status & 1);
    }
    if (failed || (header & UINT32_C(8))) {
        fprintf(stderr, "FAIL: inferred BRAM readback mismatch\n");
        return 1;
    }
    puts("PASS: inferred scheduler and trace BRAM shapes preserved all test patterns");
    return 0;
}

/* Map the generic-UIO register page and run the non-destructive PL self-test. */
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s /dev/uioN\n", argv[0]);
        return 2;
    }
    int descriptor = open(argv[1], O_RDWR | O_SYNC);
    if (descriptor < 0) { perror("open UIO"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED,
                         descriptor, 0);
    if (mapping == MAP_FAILED) { perror("mmap UIO"); close(descriptor); return 1; }
    int result = run(mapping);
    munmap(mapping, 4096);
    close(descriptor);
    return result;
}
