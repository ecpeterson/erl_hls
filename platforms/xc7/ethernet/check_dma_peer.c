// Exchange deterministic Ethernet frames through two physical DMA fixtures.
// This proves transparent plumbing, not the intended application topology.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s: %s\n", message, errno ? strerror(errno) : "failed");
        exit(1);
    }
}

static void frame(uint8_t *data, size_t length, unsigned key, unsigned role)
{
    for (size_t i=0; i<length; i++) data[i]=(uint8_t)((i*37)^(i>>3)^key^(role*83));
    memset(data,0xff,6);
    data[6]=2; data[7]=0x45; data[8]=0x52; data[9]=0x4c;
    data[10]=(uint8_t)role; data[11]=(uint8_t)key;
    data[12]=0x88; data[13]=0xb5;
}

static void send_frame(int fd, const uint8_t *data, size_t length)
{
    ssize_t count;
    do count=write(fd,data,length); while(count<0 && errno==EINTR);
    require(count==(ssize_t)length,"publish Ethernet frame");
}

static void receive_frame(int fd, const uint8_t *expected, size_t length)
{
    uint8_t received[1514];
    size_t wire_length=length<60 ? 60 : length;
    size_t offset=0;
    while(offset<wire_length) {
        struct pollfd event={.fd=fd,.events=POLLIN};
        int ready;
        do ready=poll(&event,1,15000); while(ready<0 && errno==EINTR);
        require(ready==1 && (event.revents&POLLIN) && !(event.revents&(POLLERR|POLLHUP)),
                "wait for peer frame");
        size_t chunk=(offset%113)+1;
        if(chunk>wire_length-offset) chunk=wire_length-offset;
        ssize_t count;
        do count=read(fd,received+offset,chunk); while(count<0 && errno==EINTR);
        require(count>0 && (size_t)count<=chunk,"read peer frame");
        offset+=(size_t)count;
    }
    require(!memcmp(received,expected,length),"peer frame payload differs");
    for(size_t i=length;i<wire_length;i++) require(received[i]==0,"peer MAC padding is nonzero");
}

int main(int argc, char **argv)
{
    require(argc==3 && (!strcmp(argv[2],"--lead") || !strcmp(argv[2],"--follow")),
            "usage: check_dma_peer /dev/hls-dma0 --lead|--follow");
    int lead=!strcmp(argv[2],"--lead");
    alarm(240);
    int fd=open(argv[1],O_RDWR|O_CLOEXEC);
    require(fd>=0,"open Ethernet DMA fixture");
    const size_t lengths[]={14,15,16,17,59,60,61,64,255,256,257,1021,1513,1514};
    uint8_t data[1514];
    for(size_t i=0;i<sizeof(lengths)/sizeof(lengths[0]);i++) {
        unsigned request_key=(unsigned)i+13;
        unsigned reply_key=(unsigned)i+149;
        if(lead) {
            frame(data,lengths[i],request_key,1); send_frame(fd,data,lengths[i]);
            frame(data,lengths[i],reply_key,2); receive_frame(fd,data,lengths[i]);
        } else {
            frame(data,lengths[i],request_key,1); receive_frame(fd,data,lengths[i]);
            frame(data,lengths[i],reply_key,2); send_frame(fd,data,lengths[i]);
        }
        printf("%s frame %zu/%zu length=%zu ok\n",lead?"lead":"follow",i+1,
               sizeof(lengths)/sizeof(lengths[0]),lengths[i]);
        fflush(stdout);
    }
    close(fd);
    puts("PASS: reciprocal PS-PL-DMA-CDC-Ethernet frames, boundaries, padding and partial reads");
    return 0;
}
