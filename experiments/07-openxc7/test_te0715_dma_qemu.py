#!/usr/bin/env python3
"""Check the built kernel ABI and actual emulated PL330 copies; QEMU has no PL RTL."""

import argparse
import gzip
import json
import stat
import subprocess
from pathlib import Path

from dma.device_tree import mailbox_tree
from prepare_te0715_boot import fetch
from prepare_te0715_runtime import tar_entries
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
INIT = b"""#!/bin/sh
set -eu
trap 'reboot -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
insmod /hls_dma_selftest.ko
rmmod hls_dma_selftest
# The transport must reject QEMU's absent PL instead of exposing an inert device.
insmod /hls_dma_mailbox.ko
test ! -e /dev/hls-dma0
rmmod hls_dma_mailbox
echo 'PASS: Zynq DMA kernel ABI and absent-PL rejection'
"""


def run(base: Path, kernel: Path, timeout: int) -> Path:
    """Boot once, requiring both real DMA copies and the driver's negative probe check."""
    work = ROOT / "build/dma-qemu"
    work.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "runtime/packages.lock.json").read_text())
    downloads = ROOT / "build/runtime/downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    entries = tar_entries(fetch(lock["rootfs"], downloads))
    entries += [("init", INIT, stat.S_IFREG | 0o755)]
    entries += [(name, (kernel / name).read_bytes(), stat.S_IFREG | 0o644)
                for name in ("hls_dma_selftest.ko", "hls_dma_mailbox.ko")]
    (work / "test.cpio.gz").write_bytes(gzip.compress(cpio(entries), mtime=0))
    mailbox_tree(base / "system.dtb", work / "system.dtb")
    command = ["qemu-system-arm", "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(kernel / "zImage"), "-dtb", str(work / "system.dtb"),
               "-initrd", str(work / "test.cpio.gz"),
               "-append", "console=ttyPS0,115200 rdinit=/init panic=-1"]
    log = work / "uart.log"
    with log.open("wb") as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
    contents = log.read_text()
    for marker in ("PASS: PL330 DMAengine copied five frame sizes on both channels",
                   "PASS: Zynq DMA kernel ABI and absent-PL rejection"):
        if marker not in contents:
            raise RuntimeError(f"DMA QEMU check failed; see {log}")
    print(contents[contents.index("PASS: PL330"):].split("reboot:")[0])
    return log


def main() -> None:
    """Accept the register-probe base and the matching freshly built kernel/modules."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    print(run(args.base.resolve(), args.kernel.resolve(), args.timeout))


if __name__ == "__main__":
    main()
