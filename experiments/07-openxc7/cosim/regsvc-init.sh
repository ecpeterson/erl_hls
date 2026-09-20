#!/bin/sh
# Run the public BEAM clients against both real DMA devices and generated actors.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
insmod /hls_dma_mailbox.ko
test -c /dev/hls-dma0
test -c /dev/hls-dma1
mkdir -p /mnt
mount -o ro /dev/mmcblk0 /mnt
mount -t devtmpfs devtmpfs /mnt/dev
mount -t proc proc /mnt/proc
mount -t sysfs sysfs /mnt/sys
chroot /mnt /usr/bin/env ERL_LIBS=/opt/erl-hls/lib \
    escript /opt/erl-hls/bin/check_regsvc_dma.escript
test ! -e /dev/hls-dma0
test ! -e /dev/hls-dma1
rmmod hls_dma_mailbox
echo 'PASS: Linux PL330 and Icarus routed application integration'
