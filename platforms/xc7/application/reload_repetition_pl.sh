#!/bin/sh
# Reload one complete role image through Linux FPGA Manager. Run both roles
# concurrently: the private link, its transport storage and both actor graphs
# share one activation and must all restart together.
set -eu

driver=/sys/bus/platform/drivers/hls-dma-mailbox
manager=/sys/class/fpga_manager/fpga0
lock=/run/repetition-pl-reload.lock

case "${1-}" in
    a|b) role=$1 ;;
    *) echo "usage: reload_repetition_pl a|b" >&2; exit 2 ;;
esac

firmware="repetition-link-$role.bit.bin"
firmware_path="/lib/firmware/$firmware"
checksum_path="$firmware_path.sha256"

exec 9>"$lock"
flock -n 9 || { echo "another PL reload is active" >&2; exit 1; }
test "$(id -u)" -eq 0
test -w "$manager/firmware"
test -r "$firmware_path"
test -r "$checksum_path"
(cd /lib/firmware && sha256sum -c "$(basename "$checksum_path")")

for node in /dev/hls-dma0 /dev/hls-dma1; do
    if test -e "$node" && fuser "$node" >/dev/null 2>&1; then
        echo "$node is still in use; stop its BEAM owner before reloading PL" >&2
        exit 1
    fi
done

for device in 40004000.dma-mailbox 40000000.dma-mailbox; do
    platform="/sys/bus/platform/devices/$device"
    if test -L "$platform/driver"; then
        printf '%s' "$device" > "$driver/unbind"
    fi
done

printf '0' > "$manager/flags"
printf '%s' "$firmware" > "$manager/firmware"
test "$(cat "$manager/state")" = operating

for device in 40000000.dma-mailbox 40004000.dma-mailbox; do
    platform="/sys/bus/platform/devices/$device"
    if ! test -L "$platform/driver"; then
        printf '%s' "$device" > "$driver/bind"
    fi
done
mdev -s

deadline=$((SECONDS + 5))
while ! test -c /dev/hls-dma0 || ! test -c /dev/hls-dma1; do
    test "$SECONDS" -lt "$deadline" || {
        echo "DMA devices did not return after PL reload" >&2
        exit 1
    }
    sleep 0.05
    mdev -s
done

for device in 40000000.dma-mailbox 40004000.dma-mailbox; do
    status=$(cat "/sys/bus/platform/devices/$device/status")
    case "$status" in
        *"fault=0"*"failed=0"*) ;;
        *) echo "$device unhealthy after PL reload: $status" >&2; exit 1 ;;
    esac
done

hash=$(sha256sum "$firmware_path" | cut -d ' ' -f 1)
echo "PASS: role $role PL reloaded; state=operating firmware_sha256=$hash"
