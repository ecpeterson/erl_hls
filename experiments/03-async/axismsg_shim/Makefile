obj-m += axismsg_shim.o

KDIR ?= /home/ubuntu/xilinx/zynqberrydemo/os/petalinux/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/linux-xlnx/6.6.40+git/linux-zynq_generic_7z010-standard-build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=arm CROSS_COMPILE=$(TARGET_PREFIX) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=arm CROSS_COMPILE=$(TARGET_PREFIX) clean
