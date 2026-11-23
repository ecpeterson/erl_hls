#!/bin/sh
# Replace BOOT.bin on a running board only after checking the requested digest.

set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: write_boot SOURCE EXPECTED_SHA256 [FAT_DEVICE]" >&2
    exit 2
fi

source_file=$1
expected=$2
device=${3:-/dev/mmcblk0p1}

case "$expected" in
    *[!0-9a-f]*|'') echo "invalid lowercase SHA-256 digest" >&2; exit 2 ;;
esac
[ "${#expected}" -eq 64 ] || { echo "invalid SHA-256 digest length" >&2; exit 2; }
[ -f "$source_file" ] || { echo "missing source: $source_file" >&2; exit 2; }
[ -b "$device" ] || { echo "not a block device: $device" >&2; exit 2; }

actual=$(sha256sum "$source_file" | awk '{print $1}')
[ "$actual" = "$expected" ] || {
    echo "source BOOT.bin hash mismatch: $actual" >&2
    exit 1
}

mount_point=$(awk -v device="$device" '$1 == device {print $2; exit}' /proc/mounts)
mounted_here=0
if [ -z "$mount_point" ]; then
    mount_point=/tmp/erl-hls-boot
    mkdir -p "$mount_point"
    mount -t vfat -o rw "$device" "$mount_point"
    mounted_here=1
fi

cleanup() {
    if [ "$mounted_here" -eq 1 ]; then
        umount "$mount_point" || true
    fi
}
trap cleanup EXIT INT TERM

temporary="$mount_point/.BOOT.bin.new"
cp "$source_file" "$temporary"
sync
mv "$temporary" "$mount_point/BOOT.bin"
sync

installed=$(sha256sum "$mount_point/BOOT.bin" | awk '{print $1}')
[ "$installed" = "$expected" ] || {
    echo "on-media BOOT.bin hash mismatch: $installed" >&2
    exit 1
}

echo "PASS: on-media BOOT.bin $installed"
