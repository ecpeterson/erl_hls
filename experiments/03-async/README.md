# async

Extends `zynqberrydemo` with sample RTL + DMA transfer system that smells more
like a message passing system.

## Setup

Start from `zynqberrydemo`.

+ Enable Scatter-Gather engine on the AXI DMA IP.  Add another slave port to the interconnect and wire the AXI DMA IP's SG port to it.  Replace the old custom RTL with `axis_regsvc.v` from this project.  Wire it up the same way.  As before, synthesize and export the hardware + bitstream to `xsa/`.
+ Copy `0002...patch` into `os/petalinux/project-spec/meta-user/recipes-kernel/linux/linux-xlnx`.  Edit `os/petalinux/project-spec/meta-user/recipes-kernel/linux/linux-xlnx_%.bbappend` to include the `0002...patch` filename.  Compile the kernel.  Use `zynqberrydemo`'s `system_bin.bif` to repackage the bitstream: `bootgen -image system_bit.bif -arch zynq -process_bitstream bin -w -o system.bit.bin`.
+ Build the device shim by running `make` in `axismsg_shim/`.  Also build the `.dtbo` by running `dtc -@ -I dts -O dtb -o axismsg-test.dtbo axismsg-test.dts`.
+ Build the interactive client by `${CC} -O2 -Wall -o axismsg_cli axismsg_cli.c`.
+ Copy `image.ub`, `pl.dtbo`, `system.bit.bin` (as `zsys_wrapper.bit.bin`), `axismsg-test.dtbo`, `axismsg_shim.ko`, and `axismsg_cli` to the SD card.

## Use

```sh
mkdir /mnt/sd
mount /dev/mmcblk0p1 /mnt/sd
cd /mnt/sd

# Fix HP0 width, just as in zynqberrydemo
devmem 0xF8008000 32 0x00000001
devmem 0xF8008014 32 0x00000001

# Load bitstream + base overlay, just as in zynqberrydemo
fpgautil -b zsys_wrapper.bit.bin -o pl.dtbo

# Load message overlay
mkdir -p /sys/kernel/config/device-tree/overlays/axismsg_test || true
cat axismsg-test.dtbo > /sys/kernel/config/device-tree/overlays/axismsg_test/dtbo

# Load driver
insmod axismsg_shim.ko || true

# Run CLI
./axismsg_cli

# help
# set 0 2 ffffffff
# get 0
# set 1 4 ffffffff
# set 2 8 ffffffff
# ping 1234
# set 3 9 ffffffff
# bulkget 0 4
# set 0 1 ffffffff  # expect a bunch of spam
```

## Notes

+ Kernel patch might want to take min of `config.coalesc` and the number of submitted descriptors.  When `config.coalesc == 1`, it doesn't matter.
+ The kernel shim is pretty chatty.  Stripping `dev_info` won't harm anything.
+ The shim has the potential for an interrupt storm.  Could tune the delay field.  In our target use case, we're offloading high-throughput processing to the PL, so low latency and low throughput might be preferable for PL-PS signals.
+ I realized you don't have to bother packaging the `.v` as custom IP; you can just add it to the project and then drag-drop it into the block design. ez pz.
