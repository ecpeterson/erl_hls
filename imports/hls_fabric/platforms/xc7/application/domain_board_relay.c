/* One opaque routed-frame lane over authenticated stdio (for example SSH).
 * Exactly one TX and one RX packet slot, each <=1028 bytes. The private wire is
 * a big-endian u32 length followed by a type byte and optional unchanged frame:
 * H,version=1,bank; T,frame; A (write returned); R,frame; C (RX credit); Q; Z.
 * A means published to DMA, never device admission. Q closes the native FD,
 * preserves already captured R until C, and rejects further T/Q. Z follows
 * retirement of that slot and all preceding stdio output; it never
 * claims DMA cancellation/drain. No retry except pre-admission EAGAIN, no replay,
 * reconnect, host-session change or actor/endpoint reset. EOF is terminal.
 * --test-fd accepts a packet-preserving socket fixture, never opens a device. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define FRAME_MAX 1028
struct relay {
    int device, bank, closing, hello, acknowledge;
    uint8_t tx[FRAME_MAX], rx[FRAME_MAX], input_header[5], output_header[5];
    size_t tx_size, tx_received, rx_size, input_used, output_used;
    unsigned input_length;
    int tx_valid, rx_sent;
    char output_type;
    const char *failure;
    int failure_errno;
};

/* Retain one terminal reason and errno; never log packet payloads or guess DMA outcome. */
static int failed(struct relay *s, const char *stage, int error)
{
    s->failure=stage; s->failure_errno=error;
    return -1;
}

/* A process-wide deadline bounds a lost peer without guessing native outcomes. */
static int64_t milliseconds(void)
{
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now)) return -1;
    return (int64_t)now.tv_sec*1000 + now.tv_nsec/1000000;
}

/* Preserve flags and poll for admission. A published DMA copy may still use
 * the driver's existing bounded synchronous transfer timeout. */
static int nonblocking(int fd)
{
    int flags=fcntl(fd,F_GETFL);
    return flags<0 ? -1 : fcntl(fd,F_SETFL,flags|O_NONBLOCK);
}

/* Reject noncanonical packet sizes before publishing anything to DMA. */
static int frame_valid(const uint8_t *frame, size_t length)
{
    return length>=8 && length<=FRAME_MAX && length==8+4*(size_t)frame[4];
}

/* Read one control prefix or the unique pending TX payload, never a second frame. */
static int input(struct relay *s)
{
    uint8_t *target;
    size_t needed;
    if(s->input_used<5) {
        target=s->input_header+s->input_used;
        needed=5-s->input_used;
    } else {
        target=s->tx+s->tx_received;
        needed=s->tx_size-s->tx_received;
    }
    ssize_t n=read(STDIN_FILENO,target,needed);
    if(n<0 && errno==EAGAIN) return 0;
    if(n<=0) return failed(s,n<0 ? "input-read" : "input-eof",n<0 ? errno : 0);
    if(s->input_used<5) {
        s->input_used+=(size_t)n;
        if(s->input_used!=5) return 0;
        s->input_length=((unsigned)s->input_header[0]<<24)|((unsigned)s->input_header[1]<<16)|
            ((unsigned)s->input_header[2]<<8)|s->input_header[3];
        char type=(char)s->input_header[4];
        if(s->closing && type!='C') return failed(s,"input-after-close",0);
        if(type=='T' && s->input_length>=9 && s->input_length<=FRAME_MAX+1 && !s->tx_valid && !s->acknowledge) {
            s->tx_size=s->input_length-1; s->tx_received=0;
            return 0;
        }
        if(s->input_length!=1) return failed(s,"input-length",0);
        if(type=='C' && s->rx_size && s->rx_sent) {
            s->rx_size=0; s->rx_sent=0;
        } else if(type=='Q' && !s->tx_valid && !s->acknowledge) {
            if(close(s->device)) return failed(s,"device-close",errno);
            s->device=-1; s->closing=1;
        } else return failed(s,"input-control",0);
        s->input_used=0;
    } else {
        s->tx_received+=(size_t)n;
        if(s->tx_received==s->tx_size) {
            if(!frame_valid(s->tx,s->tx_size)) return failed(s,"input-frame",0);
            s->tx_valid=1; s->input_used=0;
        }
    }
    return 0;
}

/* Reserve an immutable output until every prefix/payload byte is written. */
static void select_output(struct relay *s)
{
    if(s->output_type) return;
    char type=s->hello ? 'H' : s->acknowledge ? 'A' :
        s->rx_size && !s->rx_sent ? 'R' : s->closing && !s->rx_size ? 'Z' : 0;
    if(!type) return;
    unsigned length=type=='H' ? 3 : type=='R' ? (unsigned)s->rx_size+1 : 1;
    s->output_header[0]=(uint8_t)(length>>24); s->output_header[1]=(uint8_t)(length>>16);
    s->output_header[2]=(uint8_t)(length>>8); s->output_header[3]=(uint8_t)length;
    s->output_header[4]=(uint8_t)type; s->output_type=type; s->output_used=0;
}

/* Partial stdio writes preserve the one RX slot; its credit releases it later. */
static int output(struct relay *s)
{
    uint8_t hello[2]={1,(uint8_t)s->bank};
    const uint8_t *bytes=s->output_header;
    size_t length=5;
    if(s->output_used>=5) {
        bytes=s->output_type=='H' ? hello : s->rx;
        length=s->output_type=='H' ? 2 : s->rx_size;
        bytes+=s->output_used-5; length-=s->output_used-5;
    } else { bytes+=s->output_used; length-=s->output_used; }
    ssize_t n=write(STDOUT_FILENO,bytes,length);
    if(n<0 && errno==EAGAIN) return 0;
    if(n<=0) return failed(s,n<0 ? "output-write" : "output-zero",n<0 ? errno : 0);
    s->output_used+=(size_t)n;
    size_t total=5+(s->output_type=='H' ? 2 : s->output_type=='R' ? s->rx_size : 0);
    if(s->output_used==total) {
        char type=s->output_type; s->output_type=0;
        if(type=='H') s->hello=0;
        if(type=='A') s->acknowledge=0;
        if(type=='R') s->rx_sent=1;
        if(type=='Z') return 1;
    }
    return 0;
}

/* The existing driver guarantees one complete frame for this maximum-size read. */
static int receive_device(struct relay *s)
{
    ssize_t n=read(s->device,s->rx,sizeof(s->rx));
    if(n<0 && errno==EAGAIN) return 0;
    if(n<=0) return failed(s,n<0 ? "device-read" : "device-eof",n<0 ? errno : 0);
    if(!frame_valid(s->rx,(size_t)n)) return failed(s,"device-frame",0);
    s->rx_size=(size_t)n; s->rx_sent=0;
    return 0;
}

/* A partial/error write is terminal: its native outcome must never be replayed. */
static int send_device(struct relay *s)
{
    ssize_t n=write(s->device,s->tx,s->tx_size);
    if(n<0 && errno==EAGAIN) return 0;
    if(n!=(ssize_t)s->tx_size) return failed(s,n<0 ? "device-write" : "device-short-write",n<0 ? errno : 0);
    s->tx_valid=0; s->tx_size=0; s->acknowledge=1;
    return 0;
}

/* Bound both directional slots; independent banks use independent helper processes. */
static int run(struct relay *s, int timeout_ms)
{
    int64_t start=milliseconds();
    if(start<0) return failed(s,"clock",errno);
    int64_t deadline=start+timeout_ms;
    while(1) {
        select_output(s);
        int64_t now=milliseconds(), left=deadline-now;
        if(now<0 || left<=0) return failed(s,now<0 ? "clock" : "deadline",now<0 ? errno : 0);
        struct pollfd fds[3]={
            /* C remains required after Q while a captured R is retained. */
            {.fd=STDIN_FILENO,.events=POLLIN},
            {.fd=STDOUT_FILENO,.events=s->output_type ? POLLOUT : 0},
            {.fd=s->device,.events=(short)((!s->rx_size && !s->closing ? POLLIN : 0)|
                                           (s->tx_valid ? POLLOUT : 0))}};
        int n=poll(fds,3,(int)(left>1000 ? 1000 : left));
        if(n<0) return failed(s,"poll",errno);
        if((fds[0].revents|fds[1].revents|fds[2].revents)&(POLLERR|POLLNVAL)) return failed(s,"poll-error",0);
        if(fds[0].revents&POLLIN) { if(input(s)) return -1; }
        else if(fds[0].revents&POLLHUP) return failed(s,"input-hangup",0);
        if(fds[1].revents&POLLOUT) {
            int result=output(s); if(result) return result==1 ? 0 : -1;
        }
        if(fds[1].revents&POLLHUP) return failed(s,"output-hangup",0);
        if(!s->closing && fds[2].revents&POLLIN) { if(receive_device(s)) return -1; }
        if(!s->closing && fds[2].revents&POLLOUT) { if(send_device(s)) return -1; }
        if(!s->closing && fds[2].revents&POLLHUP) return failed(s,"device-hangup",0);
    }
}

/* Parse explicit finite bounds; normal mode admits only the two existing DMA aliases. */
int main(int argc, char **argv)
{
    struct relay state={.device=-1,.hello=1};
    const char *path=NULL;
    int test_fd=-1, timeout_ms=180000;
    for(int i=1;i+1<argc;i+=2) {
        char *end=NULL;
        if(!strcmp(argv[i],"--device")) path=argv[i+1];
        else {
            long value=strtol(argv[i+1],&end,10);
            if(!end || end==argv[i+1] || *end || value<0 || value>INT_MAX) return 2;
            if(!strcmp(argv[i],"--bank") && value<=1) state.bank=(int)value;
            else if(!strcmp(argv[i],"--timeout-ms") && value>0 && value<=3600000) timeout_ms=(int)value;
            else if(!strcmp(argv[i],"--test-fd") && value>=3) test_fd=(int)value;
            else return 2;
        }
    }
    if(argc%2!=1 || (!!path)+(test_fd>=0)!=1) return 2;
    if(path && strcmp(path,state.bank ? "/dev/hls-dma1" : "/dev/hls-dma0")) return 2;
    signal(SIGPIPE,SIG_IGN);
    state.device=path ? open(path,O_RDWR|O_NONBLOCK|O_CLOEXEC) : test_fd;
    if(state.device<0 || nonblocking(state.device) || nonblocking(STDIN_FILENO) || nonblocking(STDOUT_FILENO)) return 2;
    int result=run(&state,timeout_ms);
    if(state.device>=0) close(state.device);
    if(result) fprintf(stderr,"domain board relay terminated stage=%s errno=%d bank=%d closing=%d tx_valid=%d rx_size=%zu rx_sent=%d input_used=%zu input_type=%u output_type=%u output_used=%zu; native DMA outcome is not reconciled\n",
        state.failure ? state.failure : "unknown",state.failure_errno,state.bank,state.closing,
        state.tx_valid,state.rx_size,state.rx_sent,state.input_used,(unsigned)state.input_header[4],
        (unsigned)(unsigned char)state.output_type,state.output_used);
    return result ? 1 : 0;
}
