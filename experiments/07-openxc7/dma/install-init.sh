#!/bin/sh
# Update only the disposable copy of the preceding SD image, using the new kernel.
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
release=$(uname -r)
insmod "/lib/modules/$release/extra/hls_dma_selftest.ko"
rmmod hls_dma_selftest
insmod "/lib/modules/$release/extra/hls_dma_mailbox.ko"
test ! -e /dev/hls-dma0
rmmod hls_dma_mailbox
status=0
/check_dma_device || status=$?
test "$status" -eq 2
mkdir -p /target
mount /dev/mmcblk0 /target
rm -rf /target/lib/modules
cp -a /lib/modules /target/lib/
depmod -b /target "$release"
cp /check_dma_device /check_dma_beam.escript /target/opt/erl-hls/bin/
if [ -d /regsvc ]; then
    rm -rf /target/opt/erl-hls/lib/erl_hls/ebin
    cp -a /regsvc/ebin /target/opt/erl-hls/lib/erl_hls/
    cp /regsvc/check_regsvc_dma.escript /target/opt/erl-hls/bin/
fi
cp /dma-runtime-check /target/opt/erl-hls/check-init
rm -f /target/etc/modprobe.d/erl-hls-probe.conf
sync
umount /target
echo 'PASS: DMA SD root assembled'
