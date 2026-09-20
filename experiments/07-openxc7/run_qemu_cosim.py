#!/usr/bin/env python3
"""Boot the real DMA driver against Icarus RTL; optionally exercise the ARM BEAM image."""

import argparse
import gzip
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import tempfile
import time
from pathlib import Path

from cosim.runtime import compile_rtl, rtl_server
from dma.device_tree import mailbox_tree
from prepare_te0715_boot import digest, fetch
from prepare_te0715_dma import check_manifest, diagnostic
from prepare_te0715_runtime import tar_entries
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/cosim"


def run(base: Path, kernel: Path, qemu: Path, runtime: Path | None, timeout: int) -> Path:
    """Require end-to-end guest/RTL witnesses, retaining logs and input provenance."""
    check_manifest(base)
    kernel_manifest = check_manifest(kernel)
    if kernel_manifest["base_kernel_sha256"] != digest(base / "zImage"):
        raise ValueError("kernel was built for a different boot candidate")
    for name, sha256 in kernel_manifest["inputs"].items():
        if digest(ROOT / name) != sha256:
            raise ValueError(f"kernel input changed; rebuild first: {name}")
    stage = BUILD / "run"
    stage.mkdir(parents=True, exist_ok=True)
    compile_rtl(stage)
    diagnostic(stage / "check_dma_device")
    lock = json.loads((ROOT / "runtime/packages.lock.json").read_text())
    entries = tar_entries(fetch(lock["rootfs"], ROOT / "build/runtime/downloads"))
    entries += [("init", (ROOT / "cosim/guest-init.sh").read_bytes(), stat.S_IFREG | 0o755),
                ("hls_dma_mailbox.ko", (kernel / "hls_dma_mailbox.ko").read_bytes(), stat.S_IFREG | 0o644),
                ("check_dma_device", (stage / "check_dma_device").read_bytes(), stat.S_IFREG | 0o755)]
    (stage / "test.cpio.gz").write_bytes(gzip.compress(cpio(entries), mtime=0))
    mailbox_tree(base / "system.dtb", stage / "system.dtb")
    command = [str(qemu), "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(kernel / "zImage"), "-dtb", str(stage / "system.dtb"),
               "-initrd", str(stage / "test.cpio.gz"),
               "-append", "console=ttyPS0,115200 rdinit=/init panic=-1"]
    image = stage / "runtime.ext4"
    runtime_manifest = None
    try:
        if runtime:
            runtime_manifest = check_manifest(runtime)
            with gzip.open(runtime / "rootfs.ext4.gz", "rb") as source, image.open("wb") as output:
                shutil.copyfileobj(source, output)
            if digest(image) != runtime_manifest["rootfs_uncompressed"]["sha256"]:
                raise ValueError("uncompressed runtime image differs")
            command += ["-drive", f"file={image},if=sd,format=raw"]
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="hls-cosim-", dir="/tmp") as temporary:
            socket = Path(temporary) / "rtl.sock"
            with rtl_server(stage, socket, stage / "rtl.log") as rtl:
                with (stage / "uart.log").open("w") as output:
                    subprocess.run(command, env=dict(os.environ, HLS_COSIM_SOCKET=str(socket)),
                                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
                if rtl.wait(timeout=5):
                    raise RuntimeError(f"RTL peer failed; see {stage / 'rtl.log'}")
        elapsed = time.monotonic() - started
    finally:
        image.unlink(missing_ok=True)
    uart = (stage / "uart.log").read_text()
    markers = ["PASS: all 256 routed frame sizes, partial reads and admission checks",
               "PASS: full RX/TX backpressure and ordered drain",
               "PASS: blocked read woke on completed frame",
               "PASS: open reader woke with ENODEV on driver unbind",
               "PASS: Linux PL330 and Icarus mailbox integration"]
    if runtime:
        markers.append("PASS: ARM BEAM raw-file DMA loopback, all 256 frame sizes")
    for marker in markers:
        if marker not in uart:
            raise RuntimeError(f"missing {marker!r}; see {stage / 'uart.log'}")
    match = re.search(r"COSIM (.*)", (stage / "rtl.log").read_text())
    if not match:
        raise RuntimeError("missing RTL completion counters")
    counts = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", match[1])}
    if counts["frames"] != (515 if runtime else 259) or not all(counts[key] for key in
                                                                          ("steps", "stalls", "irq_rises")):
        raise RuntimeError(f"missing RTL activity: {counts}")
    report = {"wall_seconds": round(elapsed, 3), "hardware_validated": False,
              "host": platform.platform(),
              "qemu_version": subprocess.check_output([qemu, "--version"], text=True).splitlines()[0],
              "qemu_sha256": digest(qemu), "kernel_manifest_sha256": digest(kernel / "manifest.json"),
              "base_manifest_sha256": digest(base / "manifest.json"),
              "device_tree_sha256": digest(stage / "system.dtb"),
              "runtime_manifest_sha256": digest(runtime / "manifest.json") if runtime else None,
              "rtl": counts, "guest_checks": markers,
              "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                         [Path(__file__), ROOT / "dma/zynq_dma_mailbox.v", ROOT / "dma/check_dma_device.c",
                          *sorted((ROOT / "cosim").glob("*"))] if p.is_file()}}
    path = stage / "report.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    print("\n".join(markers))
    return path


def main() -> None:
    """Accept verified boot/kernel inputs and an optional existing DMA runtime image."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("--qemu", type=Path, default=BUILD / "qemu-build/qemu-system-arm")
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    print(run(args.base.resolve(), args.kernel.resolve(), args.qemu.resolve(),
              args.runtime.resolve() if args.runtime else None, args.timeout))


if __name__ == "__main__":
    main()
