#!/bin/sh
# QEMU-only acceptance hook, selected explicitly by hls.runtime_check=1.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
/opt/erl-hls/bin/runtime-check
modprobe hls_dma_selftest
rmmod hls_dma_selftest
modprobe hls_dma_mailbox
test ! -e /dev/hls-dma0
rmmod hls_dma_mailbox
status=0
ERL_LIBS=/opt/erl-hls/lib escript /opt/erl-hls/bin/check_dma_beam.escript || status=$?
test "$status" -eq 2
echo 'PASS: SD-root ARM runtime boot'
echo 'PASS: SD-root DMA candidate; PL not exercised'
sync
reboot -f
