// Optional Ethernet diagnostic: Linux frame I/O through PL330, CDC and MAC/PCS.
// --cosim additionally controls an emulated link fault; that MMIO is not board IP.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* Stop immediately on a missing witness; the process alarm also bounds blocked I/O. */
static void require(int condition, const char *message)
{
    if (!condition) { fprintf(stderr, "%s: %s\n", message, strerror(errno)); exit(1); }
}

/* Build locally administered experimental frames with distinct byte positions. */
static void frame(uint8_t *data, size_t length, unsigned key)
{
    for (size_t i=0; i<length; i++) data[i]=(i*37)^(i>>3)^key;
    memset(data, 0xff, 6);
    data[6]=2; data[12]=0x88; data[13]=0xb5;
}

/* Successful publication says nothing about network delivery. */
static void send_frame(int fd, const uint8_t *data, size_t length)
{
    require(write(fd, data, length)==(ssize_t)length, "publish Ethernet frame");
}

/* Partial reads must preserve a single frame, including visible MAC padding. */
static void receive_frame(int fd, const uint8_t *data, size_t length)
{
    uint8_t received[1514];
    size_t expected=length<60 ? 60 : length;
    size_t offset=0;
    while (offset<expected) {
        struct pollfd event={.fd=fd, .events=POLLIN};
        require(poll(&event,1,5000)==1 && (event.revents&POLLIN) && !(event.revents&POLLERR),
                "wait for received frame");
        size_t chunk=(offset%113)+1;
        if (chunk>expected-offset) chunk=expected-offset;
        ssize_t count=read(fd,received+offset,chunk);
        require(count>0 && (size_t)count<=chunk,"read received bytes");
        offset+=(size_t)count;
    }
    require(!memcmp(data,received,length),"received payload differs");
    for(size_t i=length;i<expected;i++) require(received[i]==0,"nonzero MAC padding");
}

/* Await public test-fixture flags, allowing QEMU's independent stepping timer to run. */
static void wait_flags(volatile uint32_t *control, uint32_t mask, uint32_t value)
{
    struct timespec delay={.tv_nsec=1000000};
    for(int i=0;i<5000;i++) {
        if((control[2]&mask)==value) return;
        nanosleep(&delay,NULL);
    }
    require(0,"test link transition timed out");
}

/* Exercise byte boundaries and explicit co-simulation recovery without resetting DMA. */
int main(int argc, char **argv)
{
    require(argc==2 || (argc==3 && !strcmp(argv[2],"--cosim")),
            "usage: check_dma_packets /dev/hls-dma0 [--cosim]");
    alarm(60);
    int fd=open(argv[1],O_RDWR|O_CLOEXEC);
    require(fd>=0,"open packet diagnostic");
    uint8_t data[1515];
    const size_t lengths[]={14,15,16,17,59,60,61,64,255,256,257,1021,1513,1514};
    for(size_t i=0;i<sizeof(lengths)/sizeof(lengths[0]);i++) {
        frame(data,lengths[i],i+13);
        send_frame(fd,data,lengths[i]);
        receive_frame(fd,data,lengths[i]);
    }
    errno=0; require(write(fd,data,13)==-1 && errno==EMSGSIZE,"short frame accepted");
    errno=0; require(write(fd,data,1515)==-1 && errno==EMSGSIZE,"long frame accepted");
    puts("PASS: Linux PL330 Ethernet frames, exact byte lengths, padding and partial reads");
    if(argc==3) {
        int memory=open("/dev/mem",O_RDWR|O_SYNC|O_CLOEXEC);
        require(memory>=0,"open fixture MMIO");
        volatile uint32_t *control=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,memory,0x40003000);
        require(control!=MAP_FAILED,"map fixture MMIO");
        require(control[0]==0x4543544c,"wrong fixture identity");
        control[1]=2;
        frame(data,93,91); send_frame(fd,data,93);
        wait_flags(control,8,8);
        control[1]=3; wait_flags(control,3,0);
        control[1]=1; receive_frame(fd,data,93);
        control[1]=0; wait_flags(control,3,3);
        frame(data,67,211); send_frame(fd,data,67); receive_frame(fd,data,67);
        require(!(control[2]&4),"valid DMA envelope rejected");
        munmap((void *)control,4096); close(memory);
        puts("PASS: committed receive survives link loss; fresh packets follow renegotiation");
    }
    close(fd);
    return 0;
}
