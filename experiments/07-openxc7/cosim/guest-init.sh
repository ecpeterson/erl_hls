#!/bin/sh
# Run the shipped board diagnostic against RTL, including blocked-reader teardown.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
insmod /hls_dma_mailbox.ko
test -c /dev/hls-dma0
cat /sys/bus/platform/devices/40000000.dma-mailbox/status
/check_dma_device /dev/hls-dma0 --unbind
echo 40000000.dma-mailbox > /sys/bus/platform/drivers/hls-dma-mailbox/bind
test -c /dev/hls-dma0
if [ -b /dev/mmcblk0 ]; then
    mkdir -p /mnt
    mount -o ro /dev/mmcblk0 /mnt
    mount -t devtmpfs devtmpfs /mnt/dev
    mount -t proc proc /mnt/proc
    chroot /mnt /usr/bin/env ERL_LIBS=/opt/erl-hls/lib \
        escript /opt/erl-hls/bin/check_dma_beam.escript /dev/hls-dma0
fi
cat /sys/bus/platform/devices/40000000.dma-mailbox/status
rmmod hls_dma_mailbox
test ! -e /dev/hls-dma0
echo 'PASS: Linux PL330 and Icarus mailbox integration'
