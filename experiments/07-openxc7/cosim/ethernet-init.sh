#!/bin/sh
# Exercise the optional packet fixture through the same Linux PL330 driver.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
insmod /hls_dma_mailbox.ko
test -c /dev/hls-dma0
/check_dma_packets /dev/hls-dma0 --cosim
cat /sys/bus/platform/devices/40000000.dma-mailbox/status
rmmod hls_dma_mailbox
echo 'PASS: Linux PL330 and Icarus Ethernet fixture integration'
