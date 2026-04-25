// axismsg_cli.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>

#include "axismsg_shim/axismsg_proto.h"

#define DEVNODE "/dev/axismsg0"

static uint8_t next_txid = 1;

static void dump_msg(const uint32_t *w, size_t words)
{
    if (words == 0)
        return;

    struct axismsg_hdr_fields h = axismsg_decode_hdr(w[0]);
    printf("< opcode=0x%02x flags=0x%02x txid=%u payload=%u",
           h.opcode, h.flags, h.txid, h.payload_words);

    switch (h.opcode) {
    case AXISMSG_OP_ACK:
        if (h.flags == 0x01 && words >= 2)
            printf(" ACK/PING cookie=0x%08x", w[1]);
        else if (words >= 3)
            printf(" ACK reg=%u value=0x%08x", w[1] & 0xffu, w[2]);
        break;
    case AXISMSG_OP_READ_RSP:
        if (words >= 3)
            printf(" READ_RSP reg=%u value=0x%08x", w[1] & 0xffu, w[2]);
        break;
    case AXISMSG_OP_BULK_RSP:
        if (words >= 2) {
            uint8_t start = (w[1] >> 8) & 0xffu;
            uint8_t count = w[1] & 0xffu;
            printf(" BULK_RSP start=%u count=%u", start, count);
            for (size_t i = 0; i < count && (2 + i) < words; i++)
                printf(" [%zu]=0x%08x", i, w[2 + i]);
        }
        break;
    case AXISMSG_OP_ERROR:
        if (words >= 2)
            printf(" ERROR code=%u", w[1] & 0xffu);
        break;
    case AXISMSG_OP_EVENT:
        if (words >= 3)
            printf(" EVENT id=%u value=0x%08x", w[1] & 0xffu, w[2]);
        break;
    default:
        break;
    }

    printf("\n");
}

static int send_words(int fd, const uint32_t *w, size_t words)
{
    size_t bytes = words * sizeof(uint32_t);
    ssize_t rc = write(fd, w, bytes);
    if (rc < 0) {
        perror("write");
        return -1;
    }
    if ((size_t)rc != bytes) {
        fprintf(stderr, "short write: %zd/%zu\n", rc, bytes);
        return -1;
    }
    return 0;
}

static int handle_command(int fd, char *line)
{
    char cmd[32];
    unsigned reg, start, count;
    unsigned value, mask, cookie;
    uint32_t msg[AXISMSG_MAX_MSG_WORDS];

    if (sscanf(line, "%31s", cmd) != 1)
        return 0;

    if (!strcmp(cmd, "help")) {
        printf("Commands:\n");
        printf("  get <reg>\n");
        printf("  set <reg> <value> <mask>\n");
        printf("  bulkget <start> <count>\n");
        printf("  ping <cookie>\n");
        printf("  quit\n");
        return 0;
    }

    if (!strcmp(cmd, "quit") || !strcmp(cmd, "exit"))
        return 1;

    if (!strcmp(cmd, "get")) {
        if (sscanf(line, "%*s %u", &reg) != 1) {
            fprintf(stderr, "usage: get <reg>\n");
            return 0;
        }
        msg[0] = AXISMSG_HDR(AXISMSG_OP_GET, 0, next_txid++, 1);
        msg[1] = reg & 0xffu;
        send_words(fd, msg, 2);
        return 0;
    }

    if (!strcmp(cmd, "set")) {
        if (sscanf(line, "%*s %u %x %x", &reg, &value, &mask) != 3) {
            fprintf(stderr, "usage: set <reg> <value> <mask>\n");
            return 0;
        }
        msg[0] = AXISMSG_HDR(AXISMSG_OP_SET, 0, next_txid++, 3);
        msg[1] = reg & 0xffu;
        msg[2] = value;
        msg[3] = mask;
        send_words(fd, msg, 4);
        return 0;
    }

    if (!strcmp(cmd, "bulkget")) {
        if (sscanf(line, "%*s %u %u", &start, &count) != 2) {
            fprintf(stderr, "usage: bulkget <start> <count>\n");
            return 0;
        }
        msg[0] = AXISMSG_HDR(AXISMSG_OP_BULK_GET, 0, next_txid++, 2);
        msg[1] = start & 0xffu;
        msg[2] = count & 0xffu;
        send_words(fd, msg, 3);
        return 0;
    }

    if (!strcmp(cmd, "ping")) {
        if (sscanf(line, "%*s %x", &cookie) != 1) {
            fprintf(stderr, "usage: ping <cookie>\n");
            return 0;
        }
        msg[0] = AXISMSG_HDR(AXISMSG_OP_PING, 0, next_txid++, 1);
        msg[1] = cookie;
        send_words(fd, msg, 2);
        return 0;
    }

    fprintf(stderr, "unknown command: %s\n", cmd);
    return 0;
}

int main(void)
{
    int fd = open(DEVNODE, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        perror("open " DEVNODE);
        return 1;
    }

    printf("axismsg_cli ready. Type 'help'.\n");

    for (;;) {
        struct pollfd pfd[2];
        char line[256];
        uint8_t rxbuf[AXISMSG_MAX_MSG_BYTES];

        pfd[0].fd = 0;
        pfd[0].events = POLLIN;

        pfd[1].fd = fd;
        pfd[1].events = POLLIN | POLLOUT;

        int rc = poll(pfd, 2, -1);
        if (rc < 0) {
            perror("poll");
            return 1;
        }

        if (pfd[1].revents & POLLIN) {
            ssize_t n = read(fd, rxbuf, sizeof(rxbuf));
            if (n < 0) {
                if (errno != EAGAIN)
                    perror("read");
            } else if (n > 0) {
                size_t words = n / 4;
                dump_msg((const uint32_t *)rxbuf, words);
            }
        }

        if (pfd[0].revents & POLLIN) {
            if (!fgets(line, sizeof(line), stdin))
                break;
            if (handle_command(fd, line))
                break;
        }
    }

    close(fd);
    return 0;
}
