// Linux readback of the TE0715 Si5338 at its fixed 7-bit address. No clock reprogramming.
#define _POSIX_C_SOURCE 200809L
#include "si5338.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

// Linux UAPI linux/i2c{,-dev}.h layouts. Kept explicit for the native ARM/musl SDK,
// which has libc headers but no Linux device headers; pointers use the target ABI.
struct i2c_msg { uint16_t addr, flags, len; uint8_t *buf; };
struct i2c_rdwr { struct i2c_msg *msgs; uint32_t nmsgs; };
enum { I2C_SLAVE=0x0703, I2C_RDWR=0x0707, I2C_M_RD=1 };

// One register read with a repeated start; require both messages to complete.
static int read_i2c(void *context, uint8_t reg, uint8_t *value) {
    struct i2c_msg messages[]={{0x70,0,1,&reg},{0x70,I2C_M_RD,1,value}};
    struct i2c_rdwr request={messages,2};
    int result=ioctl(*(int *)context,I2C_RDWR,&request);
    return result==2 ? 0 : (result<0 ? errno : EIO);
}

// Readback permits only page-selection writes; reject accidental configuration.
static int select_page(void *context, uint8_t reg, uint8_t value) {
    if (reg!=255 || value>1) return EPERM;
    uint8_t bytes[]={reg,value};
    struct i2c_msg message={0x70,0,2,bytes};
    struct i2c_rdwr request={&message,1};
    int result=ioctl(*(int *)context,I2C_RDWR,&request);
    return result==1 ? 0 : (result<0 ? errno : EIO);
}

// The readback operation needs no delay; configuring clocks is not a Linux command.
static void no_delay(void *context, unsigned milliseconds) { (void)context; (void)milliseconds; }

// Use an explicitly selected PS I2C device with exclusive access; do not force a bound driver.
int main(int argc, char **argv) {
    if (argc!=2) { fprintf(stderr,"usage: %s /dev/i2c-N\n",argv[0]); return 2; }
    int fd=open(argv[1],O_RDWR);
    if (fd<0) { perror("open I2C"); return 1; }
    if (ioctl(fd,I2C_SLAVE,0x70)<0) { perror("select Si5338"); close(fd); return 1; }
    struct si_io io={&fd,read_i2c,select_page,no_delay};
    struct si_report r;
    enum si_error error=si5338_readback(io,&r);
    printf("error=%d bus=%d cleanup=%d revision=%u grade=%u nvm=%u status=%02x enables=%02x\n",
           error,r.bus_error,r.cleanup_error,r.revision,r.grade,(unsigned)r.nvm_code,r.status,r.enables);
    printf("differences=%u register=%u expected=%02x actual=%02x mask=%02x\n",
           r.mismatches,r.reg,r.expected,r.actual,r.mask);
    if (!error) puts("PASS: 125-MHz CLK2 / 50-MHz CLK3 profile and live lock match; frequency not measured");
    close(fd);
    return error ? 1 : 0;
}
