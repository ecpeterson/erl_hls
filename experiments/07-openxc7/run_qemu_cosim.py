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
from build_regsvc_rtl import sources as regsvc_sources
from dma.device_tree import mailbox_tree
from prepare_te0715_boot import digest, fetch
from prepare_te0715_dma import check_manifest, diagnostic
from prepare_te0715_runtime import tar_entries
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/cosim"


def run(base: Path, kernel: Path, qemu: Path, runtime: Path | None, timeout: int,
        regsvc: Path | None = None) -> Path:
    """Require end-to-end guest/RTL witnesses, retaining logs and input provenance."""
    check_manifest(base)
    kernel_manifest = check_manifest(kernel)
    if kernel_manifest["base_kernel_sha256"] != digest(base / "zImage"):
        raise ValueError("kernel was built for a different boot candidate")
    for name, sha256 in kernel_manifest["inputs"].items():
        if digest(ROOT / name) != sha256:
            raise ValueError(f"kernel input changed; rebuild first: {name}")
    if regsvc and not runtime:
        raise ValueError("routed application requires an ARM BEAM runtime image")
    runtime_manifest = check_manifest(runtime) if runtime else None
    if regsvc:
        if ((runtime_manifest.get("routed_payload") or {}).get("rtl_manifest_sha256") !=
                digest(regsvc / "manifest.json")):
            raise ValueError("routed test requires the matching assembled SD runtime")
        if runtime_manifest["kernel_manifest_sha256"] != digest(kernel / "manifest.json"):
            raise ValueError("routed runtime and co-simulation must use the same kernel/driver")
    stage = BUILD / ("routed" if regsvc else "run")
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "report.json").unlink(missing_ok=True)
    compile_rtl(stage, regsvc_sources(regsvc) if regsvc else None)
    diagnostic(stage / "check_dma_device")
    lock = json.loads((ROOT / "runtime/packages.lock.json").read_text())
    entries = tar_entries(fetch(lock["rootfs"], ROOT / "build/runtime/downloads"))
    init = ROOT / "cosim" / ("regsvc-init.sh" if regsvc else "guest-init.sh")
    entries += [("init", init.read_bytes(), stat.S_IFREG | 0o755),
                ("hls_dma_mailbox.ko", (kernel / "hls_dma_mailbox.ko").read_bytes(), stat.S_IFREG | 0o644),
                ("check_dma_device", (stage / "check_dma_device").read_bytes(), stat.S_IFREG | 0o755)]
    (stage / "test.cpio.gz").write_bytes(gzip.compress(cpio(entries), mtime=0))
    mailbox_tree(base / "system.dtb", stage / "system.dtb", debug=bool(regsvc))
    if regsvc and digest(stage / "system.dtb") != runtime_manifest["files"]["system.dtb"]["sha256"]:
        raise ValueError("routed runtime and co-simulation device trees differ")
    command = [str(qemu), "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(kernel / "zImage"), "-dtb", str(stage / "system.dtb"),
               "-initrd", str(stage / "test.cpio.gz"),
               "-append", "console=ttyPS0,115200 rdinit=/init panic=-1"]
    image = stage / "runtime.ext4"
    try:
        if runtime:
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
    if regsvc:
        markers = ["PASS: debug counters and trace remain usable while application RX is full",
                   "PASS: two DMA-routed actors, isolated registers and transaction-ID reuse",
                   "PASS: full 64-event debug trace over DMA, then empty drain",
                   "PASS: DMA owners closed; reverse-order rebind preserved names and actor state",
                   "PASS: ARM BEAM routed application and independent DMA debug",
                   "PASS: Linux PL330 and Icarus routed application integration"]
    elif runtime:
        markers.append("PASS: ARM BEAM raw-file DMA loopback, all 256 frame sizes")
    for marker in markers:
        if marker not in uart:
            raise RuntimeError(f"missing {marker!r}; see {stage / 'uart.log'}")
    match = re.search(r"COSIM (.*)", (stage / "rtl.log").read_text())
    if not match:
        raise RuntimeError("missing RTL completion counters")
    counts = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", match[1])}
    activity = ("steps", "irq_rises") if regsvc else ("steps", "stalls", "irq_rises")
    if (not regsvc and counts["frames"] != (515 if runtime else 259)) or not all(counts[key] for key in activity):
        raise RuntimeError(f"missing RTL activity: {counts}")
    if regsvc:
        # Routed congestion evidence comes from public debug counters in the guest.
        for loopback_only in ("frames", "stalls"):
            counts.pop(loopback_only)
    report = {"wall_seconds": round(elapsed, 3), "hardware_validated": False,
              "host": platform.platform(),
              "qemu_version": subprocess.check_output([qemu, "--version"], text=True).splitlines()[0],
              "qemu_sha256": digest(qemu), "kernel_manifest_sha256": digest(kernel / "manifest.json"),
              "base_manifest_sha256": digest(base / "manifest.json"),
              "device_tree_sha256": digest(stage / "system.dtb"),
              "regsvc_manifest_sha256": digest(regsvc / "manifest.json") if regsvc else None,
              "runtime_manifest_sha256": digest(runtime / "manifest.json") if runtime else None,
              "rtl": counts, "guest_checks": markers,
              "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                         [Path(__file__), ROOT / "dma/zynq_dma_mailbox.v", ROOT / "dma/check_dma_device.c",
                          ROOT / "dma/device_tree.py", ROOT / "dma/zynq_dma_pair.v",
                          ROOT / "dma/zynq_regsvc_core.sv", ROOT / "dma/check_regsvc_dma.escript",
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
    parser.add_argument("--regsvc", type=Path, help="verified RTL from build_regsvc_rtl.py")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    print(run(args.base.resolve(), args.kernel.resolve(), args.qemu.resolve(),
              args.runtime.resolve() if args.runtime else None, args.timeout,
              args.regsvc.resolve() if args.regsvc else None))


if __name__ == "__main__":
    main()
