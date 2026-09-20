#!/bin/sh
# Run the shipped smoke test from the SD root, then stop the disposable QEMU guest.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys || mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
mountpoint -q /tmp || mount -t tmpfs tmpfs /tmp
/opt/erl-hls/bin/runtime-check
modprobe uio_pdrv_genirq of_id=generic-uio
test "$(cat /sys/class/uio/uio0/name)" = erl-hls-probe
test -d /sys/bus/platform/drivers/xilinx-vdma
echo 'PASS: Xilinx DMAengine provider registered; no DMA channels exercised'
echo 'PASS: SD-root ARM runtime boot'
sync
reboot -f
