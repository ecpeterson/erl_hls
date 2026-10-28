#!/bin/sh
# Add the current partition runtime, fixture actor and acceptance command.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /target
mount /dev/mmcblk0 /target
rm -rf /target/opt/erl-hls/lib/erl_hls /target/opt/erl-hls/lib/hls_lowering
rm -rf /target/opt/erl-hls/lib/hls_runtime/ebin
rm -rf /target/opt/erl-hls/lib/hls_fabric/ebin
mkdir -p /target/opt/erl-hls/lib/hls_runtime
mkdir -p /target/opt/erl-hls/lib/hls_fabric
mkdir -p /target/opt/erl-hls/share/partition-link
cp -a /hls-runtime/ebin /target/opt/erl-hls/lib/hls_runtime/
cp -a /hls-fabric/ebin /target/opt/erl-hls/lib/hls_fabric/
cp /actor/hls_link_probe_actor.beam /target/opt/erl-hls/lib/hls_fabric/ebin/
cp /deployment-a.etf /target/opt/erl-hls/share/partition-link/
cp /deployment-b.etf /target/opt/erl-hls/share/partition-link/
cp /check_partition_link.escript /target/opt/erl-hls/bin/check_partition_link
chmod 755 /target/opt/erl-hls/bin/check_partition_link
test -s /target/opt/erl-hls/lib/hls_runtime/ebin/hls_fabric.beam
test -s /target/opt/erl-hls/lib/hls_fabric/ebin/hls_partition_stream.beam
test -s /target/opt/erl-hls/lib/hls_fabric/ebin/hls_link_probe_actor.beam
test -s /target/root/.ssh/authorized_keys
test -x /target/etc/local.d/dropbear.start
grep -F '/usr/sbin/dropbear -R -s -p 22' /target/etc/local.d/dropbear.start >/dev/null
test -L /target/etc/runlevels/default/local
cmp /check_partition_link.escript /target/opt/erl-hls/bin/check_partition_link
mount -t proc proc /target/proc
mount -t sysfs sysfs /target/sys
mount -t devtmpfs devtmpfs /target/dev
chroot /target /opt/erl-hls/bin/check_partition_link --check-install
umount /target/dev
umount /target/sys
umount /target/proc
sync
umount /target
echo 'PASS: partition-link application files installed'
