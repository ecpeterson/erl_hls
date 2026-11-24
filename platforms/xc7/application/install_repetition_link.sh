#!/bin/sh
# Add the current 3+3 deployment and physical smoke command to the checked root.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /target
mount /dev/mmcblk0 /target
rm -rf /target/opt/erl-hls/lib/erl_hls /target/opt/erl-hls/lib/hls_target
rm -rf /target/opt/erl-hls/lib/hls_runtime/ebin
rm -rf /target/opt/erl-hls/lib/hls_fabric/ebin
mkdir -p /target/opt/erl-hls/bin
mkdir -p /target/opt/erl-hls/lib/hls_runtime
mkdir -p /target/opt/erl-hls/lib/hls_fabric
mkdir -p /target/opt/erl-hls/share/repetition-link
mkdir -p /target/etc/local.d
cp -a /hls-runtime/ebin /target/opt/erl-hls/lib/hls_runtime/
cp -a /hls-fabric/ebin /target/opt/erl-hls/lib/hls_fabric/
mkdir -p /target/opt/erl-hls/lib/hls_board_examples
cp -a /examples/ebin /target/opt/erl-hls/lib/hls_board_examples/
cp /deployment-a.etf /target/opt/erl-hls/share/repetition-link/
cp /deployment-b.etf /target/opt/erl-hls/share/repetition-link/
cp /fixture.json /target/opt/erl-hls/share/repetition-link/
cp /check_repetition_link.escript /target/opt/erl-hls/bin/check_repetition_link
cp /reload_repetition_pl.sh /target/opt/erl-hls/bin/reload_repetition_pl
cp /hls-dma.start /target/etc/local.d/hls-dma.start
cp /repetition-network.start /target/etc/local.d/repetition-network.start
mkdir -p /target/lib/firmware
cp /repetition-link-a.bit.bin /target/lib/firmware/
cp /repetition-link-a.bit.bin.sha256 /target/lib/firmware/
cp /repetition-link-b.bit.bin /target/lib/firmware/
cp /repetition-link-b.bit.bin.sha256 /target/lib/firmware/
chmod 755 /target/opt/erl-hls/bin/check_repetition_link
chmod 755 /target/opt/erl-hls/bin/reload_repetition_pl
chmod 755 /target/etc/local.d/hls-dma.start
chmod 755 /target/etc/local.d/repetition-network.start
test -s /target/opt/erl-hls/lib/hls_runtime/ebin/hls_fabric.beam
test -s /target/opt/erl-hls/lib/hls_fabric/ebin/hls_partition_stream.beam
test -s /target/root/.ssh/authorized_keys
test -x /target/etc/local.d/dropbear.start
grep -F '/usr/sbin/dropbear -R -s -p 22' /target/etc/local.d/dropbear.start >/dev/null
grep -F 'modprobe hls_dma_mailbox' /target/etc/local.d/hls-dma.start >/dev/null
grep -F 'mdev -s' /target/etc/local.d/hls-dma.start >/dev/null
grep -F 'repetition-role' /target/etc/local.d/repetition-network.start >/dev/null
test -L /target/etc/runlevels/default/local
cmp /check_repetition_link.escript /target/opt/erl-hls/bin/check_repetition_link
cmp /reload_repetition_pl.sh /target/opt/erl-hls/bin/reload_repetition_pl
cmp /hls-dma.start /target/etc/local.d/hls-dma.start
cmp /repetition-network.start /target/etc/local.d/repetition-network.start
(cd /target/lib/firmware && sha256sum -c repetition-link-a.bit.bin.sha256)
(cd /target/lib/firmware && sha256sum -c repetition-link-b.bit.bin.sha256)
mount -t proc proc /target/proc
mount -t sysfs sysfs /target/sys
mount -t devtmpfs devtmpfs /target/dev
chroot /target /opt/erl-hls/bin/check_repetition_link --check-install
umount /target/dev
umount /target/sys
umount /target/proc
sync
umount /target
echo 'PASS: repetition-link application files installed'
