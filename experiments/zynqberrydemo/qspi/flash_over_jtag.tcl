connect -url tcp:127.0.0.1:3121
targets
# 1 is APU, 2 is CPU0, 3 is CPU1, 4 is Zynq

# targets APU, reset system state
target 1
rst -system

# halt both CPUs
target 2
stop
target 3
stop

# load boot script
target 1
source /home/ubuntu/xilinx/zynqberrydemo/workspace/sdk/TE0726-04-41C98-A/export/TE0726-04-41C98-A/hw/ps7_init.tcl
# board LEDs will switch to solid green + red off in the middle of this.
ps7_init
ps7_post_config

# upload and run FSBL
target 2
dow /home/ubuntu/xilinx/zynqberrydemo/os/petalinux/images/linux/zynq_fsbl.elf
con
stop
# PC should be in ~0x16NNN range, which is the handoff loop

# upload and run u-boot with device tree baked in
dow /home/ubuntu/xilinx/zynqberrydemo/os/petalinux/images/linux/u-boot-dtb.elf
con
# be prepared to interrupt boot on ZB via picocom!!

# # over on ZB's u-boot, run the following sequence:
# mmc rescan                         # bring up flash drive
# fatload mmc 0 0x08000000 BOOT.BIN  # load BOOT.BIN into out-of-the-way DDR
# sf probe 0 0 0                     # bring up QSPI
# sf erase 0 0x1000000               # this is sized to whole QSPI
# sf write 0x08000000 0 ${filesize}  # filesize is printed in decimal by `fatload`. round up to next multiple of `0x10000`.
