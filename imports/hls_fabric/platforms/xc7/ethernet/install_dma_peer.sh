#!/bin/sh
# Add only peer-test access files to a retained, matching DMA root filesystem.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /target
mount /dev/mmcblk0 /target 2>/dev/null || grep -q ' /target ' /proc/mounts
mkdir -p /target/opt/erl-hls/bin /target/root/.ssh /target/etc/local.d
cp /check_dma_peer /target/opt/erl-hls/bin/check_dma_peer
cp /authorized_key.pub /target/root/.ssh/authorized_keys
cp /dropbear.start /target/etc/local.d/dropbear.start
chmod 755 /target/opt/erl-hls/bin/check_dma_peer /target/etc/local.d/dropbear.start
chmod 700 /target/root/.ssh
chmod 600 /target/root/.ssh/authorized_keys
cmp /check_dma_peer /target/opt/erl-hls/bin/check_dma_peer
cmp /authorized_key.pub /target/root/.ssh/authorized_keys
cmp /dropbear.start /target/etc/local.d/dropbear.start
test -x /target/usr/sbin/dropbear
test -L /target/etc/runlevels/default/local
sync
umount /target
echo 'PASS: Ethernet DMA peer files installed'
