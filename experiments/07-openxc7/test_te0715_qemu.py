#!/usr/bin/env python3
"""Boot the candidate's Linux/DTB in native QEMU; test userspace and UIO, without PL MMIO."""

import argparse
import gzip
import os
import selectors
import shutil
import subprocess
import time
from pathlib import Path

# Bypass interactive vendor init/login only in the disposable test initramfs.
INIT = b"""#!/bin/sh
set -eux
export PATH=/sbin:/bin:/usr/sbin:/usr/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
modprobe uio_pdrv_genirq of_id=generic-uio
test "$(cat /sys/class/uio/uio0/name)" = erl-hls-probe
test "$(cat /sys/class/uio/uio0/maps/map0/addr)" = 0x40000000
test "$(cat /sys/class/uio/uio0/maps/map0/size)" = 0x00001000
test "$(( $(cat /sys/class/uio/uio0/maps/map0/offset) ))" -eq 0
/test_probe_zynq_ps
status=0
/probe_zynq_ps || status=$?
test "$status" -eq 2
status=0
/probe_zynq_ps /definitely-not-a-device || status=$?
test "$status" -eq 1
dd if=/dev/zero of=/tmp/inert-page bs=4096 count=1
status=0
message="$(/probe_zynq_ps /tmp/inert-page 2>&1)" || status=$?
test "$status" -eq 1
test "$message" = 'unexpected identity/ABI; no writes attempted'
echo 'PASS: TE0715 Linux userspace and UIO mapping; PL access not exercised'
while :; do sleep 60; done
"""
SUCCESS = b"PASS: TE0715 Linux userspace and UIO mapping; PL access not exercised"


def cpio(files: list[tuple[str, bytes, int]]) -> bytes:
    """Encode a small newc archive for a disposable initramfs overlay."""
    output = bytearray()
    for index, (name, data, mode) in enumerate(files + [("TRAILER!!!", b"", 0)]):
        encoded = name.encode() + b"\0"
        fields = [index + 1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
        output.extend(b"070701" + b"".join(f"{field:08x}".encode() for field in fields))
        output.extend(encoded)
        output.extend(b"\0" * (-len(output) % 4))
        output.extend(data)
        output.extend(b"\0" * (-len(output) % 4))
    return bytes(output)


def run(candidate: Path, timeout: float, *, programs: tuple[str, ...] = ("probe_zynq_ps", "test_probe_zynq_ps"),
        init: bytes = INIT) -> Path:
    """Check a candidate's diagnostic and UIO in Linux, retaining UART output and stopping QEMU.

    Alternative diagnostics supply program basenames and an init script that
    emits SUCCESS only after checking them. No physical PL access is attempted.
    """
    executable = shutil.which("qemu-system-arm")
    if executable is None:
        raise ValueError("qemu-system-arm is required for the optional Linux smoke test")
    work = candidate.parent / "qemu"
    work.mkdir(exist_ok=True)
    overlay = cpio([("boot-check", init, 0o100755)] +
                   [(name, (candidate / name).read_bytes(), 0o100755)
                    for name in programs])
    initrd = work / "test-initramfs.gz"
    initrd.write_bytes((candidate / "rootfs.cpio.gz").read_bytes() + gzip.compress(overlay, mtime=0))
    # QEMU 10.2's Zynq SMP direct-boot stubs overlap. Userspace tests need one CPU.
    command = [executable, "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1", "-nographic",
               "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(candidate / "zImage"), "-dtb", str(candidate / "system.dtb"),
               "-initrd", str(initrd), "-append", "console=ttyPS0,115200 rdinit=/boot-check panic=-1"]
    output = bytearray()
    log = work / "uart.log"
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        assert process.stdout is not None
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + timeout
            while SUCCESS not in output.splitlines() and time.monotonic() < deadline:
                if not selector.select(min(1.0, max(0, deadline - time.monotonic()))):
                    continue
                data = os.read(process.stdout.fileno(), 65536)
                if not data:
                    break
                output.extend(data)
            if SUCCESS not in output.splitlines():
                raise RuntimeError(f"QEMU Linux test did not pass; see {log}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        log.write_bytes(output)
    return log


def main() -> None:
    """Run the optional, bounded Linux smoke test against an assembled candidate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--timeout", type=float, default=45)
    args = parser.parse_args()
    print(f"PASS: native QEMU Linux smoke test; UART log: {run(args.candidate.resolve(), args.timeout)}")


if __name__ == "__main__":
    main()
