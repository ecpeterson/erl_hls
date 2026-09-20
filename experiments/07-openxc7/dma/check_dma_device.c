// Exercise the physical loopback endpoint; --unbind additionally detaches its driver.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// Stop at the first failed syscall/contract, retaining errno for the UART log.
static void require(int condition, const char *message)
{
    if (!condition) { perror(message); exit(1); }
}

// Wait at most five seconds for the requested endpoint readiness.
static void ready(int fd, short events)
{
    struct pollfd p = {.fd = fd, .events = events};
    require(poll(&p, 1, 5000) == 1 && (p.revents & events), "DMA readiness");
}

// Publish one routed frame with deterministic data and read it back in small slices.
static void roundtrip(int fd, unsigned words)
{
    uint8_t tx[1028], rx[1028];
    size_t bytes = 8 + 4 * words, offset = 0;
    for (size_t i = 0; i < bytes; i++) tx[i] = (uint8_t)(i * 37 + words);
    tx[4] = (uint8_t)words;
    ready(fd, POLLOUT);
    require(write(fd, tx, bytes) == (ssize_t)bytes, "complete frame write");
    while (offset < bytes) {
        size_t amount = 1 + (offset % 17);
        if (amount > bytes - offset) amount = bytes - offset;
        ready(fd, POLLIN);
        ssize_t got = read(fd, rx + offset, amount);
        require(got > 0 && got <= (ssize_t)amount, "partial frame read");
        offset += (size_t)got;
    }
    require(memcmp(tx, rx, bytes) == 0, "loopback payload mismatch");
}

// Unbind with an open blocked reader; the reader must wake with ENODEV and exit.
static void check_unbind(const char *path)
{
    int fd = open(path, O_RDONLY), sync_pipe[2], status;
    require(fd >= 0 && pipe(sync_pipe) == 0, "unbind reader setup");
    pid_t pid = fork();
    require(pid >= 0, "fork reader");
    if (pid == 0) {
        char byte;
        close(sync_pipe[0]);
        alarm(10);
        require(write(sync_pipe[1], "R", 1) == 1, "reader ready");
        ssize_t got = read(fd, &byte, 1);
        _exit(got < 0 && errno == ENODEV ? 0 : 1);
    }
    close(sync_pipe[1]); close(fd);
    char byte;
    require(read(sync_pipe[0], &byte, 1) == 1, "reader started");
    close(sync_pipe[0]);
    struct timespec pause = {.tv_nsec = 50000000};
    nanosleep(&pause, NULL);
    int control = open("/sys/bus/platform/drivers/hls-dma-mailbox/unbind", O_WRONLY);
    const char device[] = "40000000.dma-mailbox";
    require(control >= 0 && write(control, device, sizeof(device)-1) == sizeof(device)-1,
            "driver unbind");
    close(control);
    require(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "blocked reader survived unbind");
    puts("PASS: open reader woke with ENODEV on driver unbind");
}

// Run only against the explicit loopback bitstream, never a live application.
int main(int argc, char **argv)
{
    int unbind = argc == 3 && strcmp(argv[2], "--unbind") == 0;
    if (argc < 2 || argc > 3 || (argc == 3 && !unbind)) {
        fprintf(stderr, "usage: %s /dev/hls-dma0 [--unbind]\n", argv[0]);
        return 2;
    }
    int fd = open(argv[1], O_RDWR | O_NONBLOCK);
    require(fd >= 0, "open DMA loopback");
    int duplicate = open(argv[1], O_RDONLY);
    require(duplicate < 0 && errno == EBUSY, "duplicate reader rejected");
    uint8_t frame[12] = {0};
    require(write(fd, frame, 7) == -1 && errno == EMSGSIZE, "short write rejected");
    require(write(fd, frame, sizeof(frame)) == -1 && errno == EPROTO, "bad length rejected");
    require(read(fd, frame, 1) == -1 && errno == EAGAIN, "empty nonblocking read");
    for (unsigned words = 0; words <= 255; words++) roundtrip(fd, words);
    close(fd);
    puts("PASS: all 256 routed frame sizes, partial reads and admission checks");
    if (unbind) check_unbind(argv[1]);
    return 0;
}
