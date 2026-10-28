#!/bin/sh
# Build a matching kernel/module set on a disposable ARM64 Linux builder.
set -eu
trap 'sync; reboot -f' EXIT
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
apk --no-network --no-progress --no-scripts --force-non-repository --repositories-file /dev/null add /packages/*.apk
modprobe virtio_pci
modprobe virtio_blk
modprobe 9p
modprobe ext4
mkdir -p /host /work
mount -t 9p -o trans=virtio,version=9p2000.L host /host
while [ ! -b /dev/vda ]; do sleep 1; done
if [ ! -f /host/disk-initialized ]; then
    mke2fs -q -t ext4 -F /dev/vda
    touch /host/disk-initialized
fi
mount /dev/vda /work
trap 'cd /; sync; umount /work || true; reboot -f' EXIT
if [ ! -d /work/linux ]; then
    rm -rf /work/linux.extracting
    mkdir /work/linux.extracting
    tar -xf /host/linux-xlnx.tar.gz -C /work/linux.extracting --strip-components=1
    mv /work/linux.extracting /work/linux
fi
cd /work/linux
export ARCH=arm CROSS_COMPILE=arm-none-eabi-
export TZ=UTC KBUILD_BUILD_USER=erl-hls KBUILD_BUILD_HOST=arm-builder KBUILD_BUILD_TIMESTAMP='2024-10-25 18:00:30'
cp /host/kernel.config .config
scripts/config --set-str LOCALVERSION '-erlhls-dma' --disable LOCALVERSION_AUTO
make olddefconfig
make -j4 zImage modules
mkdir -p /host/output
rm -f /host/output/*.ko
cp arch/arm/boot/zImage .config Module.symvers /host/output/
rm -rf /work/modules
make INSTALL_MOD_PATH=/work/modules INSTALL_MOD_STRIP=1 modules_install
tar -C /work/modules -czf /host/output/modules.tar.gz lib/modules
if [ -f /host/driver/Makefile ]; then
    rm -rf /work/driver
    mkdir -p /work/driver
    cp /host/driver/* /work/driver/
    make -j4 M=/work/driver W=1 KCFLAGS=-Werror modules
    cp /work/driver/*.ko /host/output/
fi
make -s kernelrelease > /host/output/kernel.release
echo 'PASS: matching Zynq kernel and modules built'
