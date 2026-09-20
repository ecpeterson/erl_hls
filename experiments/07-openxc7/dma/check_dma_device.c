// Exercise a loopback endpoint; --unbind additionally detaches its driver.
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

// Consume one frame in small slices and require byte-exact order and payload.
static void read_frame(int fd, const uint8_t *expected, size_t bytes)
{
    uint8_t rx[1028];
    size_t offset = 0;
    while (offset < bytes) {
        size_t amount = 1 + (offset % 17);
        if (amount > bytes - offset) amount = bytes - offset;
        ready(fd, POLLIN);
        ssize_t got = read(fd, rx + offset, amount);
        require(got > 0 && got <= (ssize_t)amount, "partial frame read");
        offset += (size_t)got;
    }
    require(memcmp(expected, rx, bytes) == 0, "loopback payload mismatch");
}

// Publish one routed frame with deterministic data and read it back in small slices.
static void roundtrip(int fd, unsigned words)
{
    uint8_t tx[1028];
    size_t bytes = 8 + 4 * words;
    for (size_t i = 0; i < bytes; i++) tx[i] = (uint8_t)(i * 37 + words);
    tx[4] = (uint8_t)words;
    ready(fd, POLLOUT);
    require(write(fd, tx, bytes) == (ssize_t)bytes, "complete frame write");
    read_frame(fd, tx, bytes);
}

// Fill RX and TX; a third frame must wait until reading releases receive storage.
static void check_backpressure(int fd)
{
    uint8_t first[12] = {1}, second[1028] = {2};
    first[4] = 1; second[4] = 255;
    ready(fd, POLLOUT);
    require(write(fd, first, sizeof(first)) == sizeof(first), "first queued frame");
    ready(fd, POLLIN); ready(fd, POLLOUT);
    require(write(fd, second, sizeof(second)) == sizeof(second), "second queued frame");
    require(write(fd, first, sizeof(first)) == -1 && errno == EAGAIN, "full TX rejected third frame");
    struct pollfd p = {.fd = fd, .events = POLLOUT};
    require(poll(&p, 1, 0) == 0, "full TX not writable");
    read_frame(fd, first, sizeof(first));
    read_frame(fd, second, sizeof(second));
    ready(fd, POLLOUT);
    puts("PASS: full RX/TX backpressure and ordered drain");
}

// After its pipe notification, this child can sleep only in the device read.
static void wait_sleeping(pid_t pid)
{
    char path[64], state[512];
    snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
    for (unsigned attempt = 0; attempt < 1000; attempt++) {
        FILE *file = fopen(path, "r");
        require(file != NULL, "reader process exists");
        require(fgets(state, sizeof(state), file) != NULL, "reader state");
        fclose(file);
        char *end = strrchr(state, ')');
        require(end != NULL, "reader state format");
        if (end[1] == ' ' && end[2] == 'S') return;
        struct timespec pause = {.tv_nsec = 1000000};
        nanosleep(&pause, NULL);
    }
    require(0, "reader did not block");
}

// A sleeping read must wake from the real PL interrupt when a frame completes.
static void check_blocked_read(int fd)
{
    uint8_t frame[1028] = {3};
    frame[4] = 255;
    int flags = fcntl(fd, F_GETFL), sync_pipe[2], status;
    require(flags >= 0 && fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0,
            "blocking reader mode");
    require(pipe(sync_pipe) == 0, "reader notification pipe");
    pid_t pid = fork();
    require(pid >= 0, "fork blocking reader");
    if (pid == 0) {
        uint8_t rx[1028];
        close(sync_pipe[0]); alarm(10);
        require(write(sync_pipe[1], "R", 1) == 1, "reader ready");
        ssize_t bytes = read(fd, rx, sizeof(rx));
        _exit(bytes == sizeof(rx) && memcmp(rx, frame, sizeof(rx)) == 0 ? 0 : 1);
    }
    close(sync_pipe[1]);
    char byte;
    require(read(sync_pipe[0], &byte, 1) == 1, "reader started");
    close(sync_pipe[0]);
    wait_sleeping(pid);
    require(write(fd, frame, sizeof(frame)) == sizeof(frame), "wake blocking reader");
    require(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "reader woke with complete frame");
    require(fcntl(fd, F_SETFL, flags) == 0, "restore nonblocking mode");
    puts("PASS: blocked read woke on completed frame");
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
    wait_sleeping(pid);
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
    check_backpressure(fd);
    check_blocked_read(fd);
    for (unsigned words = 0; words <= 255; words++) roundtrip(fd, words);
    close(fd);
    puts("PASS: all 256 routed frame sizes, partial reads and admission checks");
    if (unbind) check_unbind(argv[1]);
    return 0;
}
