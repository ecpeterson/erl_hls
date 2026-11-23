#!/usr/bin/env python3
"""Package the transparent two-board PS-DMA/Ethernet peer diagnostic."""

import argparse
import gzip
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

from check_zynq_boot import check_directory, check_linux_elf
from dma.device_tree import mailbox_tree
from ethernet.prepare import digest
from lut_legality.check import check as check_luts
from prepare_link_probe import check_candidate as check_link, normalize_authorized_key
from prepare_te0715_boot import fdt
from prepare_te0715_dma import check_manifest, diagnostic
from initramfs import cpio
from packaging_commands import execute

ROOT = Path(__file__).resolve().parent
INSTALLER = ROOT / "ethernet/install_dma_peer.sh"
DROPBEAR_START = ROOT / "ethernet/dropbear.start"
RUNTIME_ITS = ROOT / "runtime/runtime.its"
BOOT_COMMAND = ROOT / "runtime/boot.cmd"
CRITICAL_DMA_INPUTS = (
    "dma/device_tree.py",
    "dma/driver/hls_dma_mailbox.c",
    "dma/zynq_dma_mailbox.v",
)


def verify_fit(candidate: Path, log: Path, environment: dict[str, str]) -> None:
    """Require the SD-root FIT to select and hash this kernel and device tree."""
    image = candidate / "image.ub"
    if fdt(image, "/configurations", "default") != "runtime":
        raise ValueError("unexpected SD-root FIT default")
    for index, name in enumerate(("kernel", "fdt")):
        filename = "zImage" if name == "kernel" else "system.dtb"
        if fdt(image, "/configurations/runtime", name) != name:
            raise ValueError(f"FIT does not select {name}")
        extracted = candidate / f"verify-{name}"
        execute(["dumpimage", "-T", "flat_dt", "-p", str(index), "-o",
                 extracted, image], candidate, log, environment)
        if extracted.read_bytes() != (candidate / filename).read_bytes():
            raise ValueError(f"FIT payload differs: {name}")
        actual = bytes(int(byte, 16) for byte in
                       fdt(image, f"/images/{name}/hash", "value", "bx").split())
        if fdt(image, f"/images/{name}/hash", "algo") != "sha256" or \
                actual.hex() != digest(extracted):
            raise ValueError(f"FIT digest differs: {name}")
        extracted.unlink()


def route_evidence(route: Path, database: Path) -> dict:
    """Check one legal routed candidate and retain its explicitly partial timing model."""
    parent = route.parent
    log = (route / "nextpnr.log").read_text()
    if "0 errors" not in log or "failed to find a route using dedicated resources" in log:
        raise ValueError("selected route is not a clean dedicated-clock route")
    legality = check_luts(parent / "packed.json", route / "routed.json", route / "probe.fasm",
                          database / "xc7z030/tilegrid.json")
    timing = json.loads((route / "timing.json").read_text())
    return {
        "seed": int(route.name.removeprefix("seed-")),
        "router": "router2",
        "synthesis_and_route": "passed",
        "fasm_sha256": digest(route / "probe.fasm"),
        "routed_netlist_sha256": digest(route / "routed.json"),
        "packed_netlist_sha256": digest(parent / "packed.json"),
        "partial_timing": timing,
        "lut_check": legality,
        "timing_qualified": False,
        "limits": "Native timing is incomplete and misses the modeled 125-MHz TX/RX targets; this is a hardware diagnostic, not timing signoff.",
    }


def assembly_evidence(first: Path, second: Path, route: dict) -> tuple[Path, dict]:
    """Require two independent assemblies to reproduce the same checked bitstream."""
    results = [json.loads((path / "result.json").read_text()) for path in (first, second)]
    comparable = ("part", "profile", "reference_bitstream_sha256", "bitstream_sha256",
                  "artifacts_sha256", "recovered_non_ecc_bits", "bitstream_bytes")
    if any(results[0][key] != results[1][key] for key in comparable):
        raise ValueError("independent assemblies differ")
    if results[0]["artifacts_sha256"]["input.fasm"] != route["fasm_sha256"]:
        raise ValueError("assembly does not consume the selected route")
    for result in results:
        for comparison in ("vendor_comparison", "native_comparison"):
            record = result[comparison]
            if record["missing_enabled_features"] or record["extra_known_bits"]:
                raise ValueError("assembly known-mask comparison failed")
    bitstream = first / "candidate.bit"
    if digest(bitstream) != results[0]["bitstream_sha256"] or \
            digest(second / "candidate.bit") != results[0]["bitstream_sha256"]:
        raise ValueError("assembled bitstream differs from its record")
    evidence = {key: results[0][key] for key in comparable}
    evidence.update({"reproducible": True,
                     "known_bit_mask": results[0]["native_comparison"]["known_bit_mask"],
                     "missing_enabled_features": [], "extra_known_bits": [],
                     "hardware_qualified": False, "timing_qualified": False})
    return bitstream, evidence


def install_root(dma: Path, link: Path, candidate: Path, timeout: int) -> dict:
    """Install the peer client and SSH access into the retained matching DMA root."""
    raw = candidate / "rootfs.ext4"
    with gzip.open(dma / "rootfs.ext4.gz", "rb") as source, raw.open("wb") as output:
        shutil.copyfileobj(source, output)
    dma_manifest = json.loads((dma / "manifest.json").read_text())
    if digest(raw) != dma_manifest["rootfs_uncompressed"]["sha256"]:
        raise ValueError("DMA root filesystem differs after decompression")
    entries = [
        ("peer-init", INSTALLER.read_bytes(), stat.S_IFREG | 0o755),
        ("check_dma_peer", (candidate / "check_dma_peer").read_bytes(), stat.S_IFREG | 0o755),
        ("authorized_key.pub", (candidate / "authorized_key.pub").read_bytes(), stat.S_IFREG | 0o600),
        ("dropbear.start", DROPBEAR_START.read_bytes(), stat.S_IFREG | 0o755),
    ]
    initrd = candidate / "install.cpio.gz"
    initrd.write_bytes((link / "rootfs.cpio.gz").read_bytes() +
                       gzip.compress(cpio(entries), mtime=0))
    command = ["qemu-system-arm", "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", candidate / "zImage", "-dtb", candidate / "system.dtb",
               "-initrd", initrd, "-append", "console=ttyPS0,115200 rdinit=/peer-init panic=-1",
               "-drive", f"file={raw},if=sd,format=raw"]
    log = candidate / "install-uart.log"
    with log.open("wb") as output:
        try:
            result = subprocess.run([str(value) for value in command], stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"QEMU installer timed out; see {log}") from error
    if result.returncode or b"PASS: Ethernet DMA peer files installed" not in log.read_bytes().splitlines():
        raise RuntimeError(f"QEMU installation failed; see {log}")
    installed = {"bytes": raw.stat().st_size, "sha256": digest(raw)}
    with raw.open("rb") as source, (candidate / "rootfs.ext4.gz").open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    raw.unlink()
    initrd.unlink()
    return installed


def check_output(candidate: Path) -> dict:
    """Verify every published file, boot container, DT binding and diagnostic ABI."""
    manifest = json.loads((candidate / "manifest.json").read_text())
    for name, expected in manifest["files"].items():
        if Path(name).name != name or digest(candidate / name) != expected["sha256"] or \
                (candidate / name).stat().st_size != expected["bytes"]:
            raise ValueError(f"candidate file differs: {name}")
    if check_directory(candidate) != manifest["boot_partitions"]:
        raise ValueError("BOOT.bin partition map differs")
    verify_fit(candidate, candidate / "verify.log", dict(os.environ))
    node = "/amba_pl/dma-mailbox@40000000"
    for name, kind, value in (
            ("compatible", "s", "erl-hls,ethernet-diagnostic-v1"),
            ("reg", "x", "40000000 3000"),
            ("dma-names", "s", "tx rx")):
        if fdt(candidate / "system.dtb", node, name, kind) != value:
            raise ValueError(f"Ethernet DMA device-tree property differs: {name}")
    if fdt(candidate / "system.dtb", "/aliases", "hlsdma0", "s") != node:
        raise ValueError("Ethernet DMA alias differs")
    check_linux_elf((candidate / "check_dma_peer").read_bytes())
    key, fingerprint = normalize_authorized_key(candidate / "authorized_key.pub")
    if manifest["authorized_key"] != {
            "path": "/root/.ssh/authorized_keys",
            "sha256": digest(candidate / "authorized_key.pub"),
            "fingerprint": fingerprint,
            "host_key_store": "/etc/dropbear",
            "service": "/etc/local.d/dropbear.start",
            "runlevel": "default"} or \
            key != (candidate / "authorized_key.pub").read_bytes():
        raise ValueError("authorized-key record differs")
    return manifest


def build(dma: Path, link: Path, route: Path, database: Path, first: Path, second: Path,
          output: Path, timeout: int) -> Path:
    """Create a fresh, checked FAT bundle and ext4 root image for both boards."""
    if timeout < 1:
        raise ValueError("timeout must be positive")
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    dma_manifest = check_manifest(dma)
    for name in CRITICAL_DMA_INPUTS:
        if dma_manifest["inputs"][name] != digest(ROOT / name):
            raise ValueError(f"retained DMA kernel/driver input changed: {name}")
    link_manifest = check_link(link)
    if link_manifest["profile"] != "ethernet-external-autoneg" or \
            not link_manifest.get("fsbl_programs_si5338") or \
            link_manifest.get("fclk0_hz") != 25_000_000:
        raise ValueError("link base lacks the verified external clock startup")
    route_record = route_evidence(route, database)
    bitstream, assembly_record = assembly_evidence(first, second, route_record)
    output.mkdir(parents=True)
    for source, name in ((link / "fsbl.elf", "fsbl.elf"),
                         (dma / "u-boot.elf", "u-boot.elf"),
                         (dma / "zImage", "zImage"),
                         (bitstream, "probe.bit"),
                         (link / "authorized_key.pub", "authorized_key.pub"),
                         (link / "probe_clock", "probe_clock")):
        shutil.copyfile(source, output / name)
    mailbox_tree(link / "system.dtb", output / "system.dtb", ethernet=True)
    diagnostic(output / "check_dma_peer", ROOT / "ethernet/check_dma_peer.c")
    shutil.copyfile(RUNTIME_ITS, output / "runtime.its")
    shutil.copyfile(BOOT_COMMAND, output / "boot.cmd")
    (output / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n"
                                     " u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    environment = dict(os.environ, SOURCE_DATE_EPOCH="1729850430")
    log = output / "build.log"
    execute(["mkimage", "-f", "runtime.its", "image.ub"], output, log, environment)
    execute(["mkimage", "-A", "arm", "-T", "script", "-C", "none",
             "-n", "TE0715 Ethernet DMA peer", "-d", "boot.cmd", "boot.scr"],
            output, log, environment)
    bootgen = next((ROOT / "build/boot/work/bootgen").glob("*/bootgen"))
    execute([bootgen, "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin",
             "-w", "on"], output, log, environment)
    root_record = install_root(dma, link, output, timeout)
    key, fingerprint = normalize_authorized_key(output / "authorized_key.pub")
    if key != (output / "authorized_key.pub").read_bytes():
        raise ValueError("published key is not normalized")
    boot_partitions = check_directory(output)
    programs = ["check_dma_peer", "probe_clock"]
    files = {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)}
             for path in output.iterdir() if path.is_file() and path.name != "manifest.json"}
    manifest = {
        "profile": "ethernet-dma-peer",
        "purpose": "Transparent PS PL330 mailbox/CDC/1000BASE-X/CDC/mailbox integration fixture",
        "production_topology": False,
        "module": dma_manifest["module"], "carrier": dma_manifest["carrier"],
        "part": dma_manifest["part"], "kernel_release": dma_manifest["kernel_release"],
        "fclk0_hz": link_manifest["fclk0_hz"],
        "fsbl_programs_si5338": True,
        "reference_clock_hz_required": 125_000_000,
        "dma_device": "/dev/hls-dma0",
        "hardware_validated": False,
        "timing_qualified": False,
        "route": route_record,
        "assembly": assembly_record,
        "rootfs_uncompressed": root_record,
        "dma_base_manifest_sha256": digest(dma / "manifest.json"),
        "link_base_manifest_sha256": digest(link / "manifest.json"),
        "authorized_key": {"path": "/root/.ssh/authorized_keys",
                           "sha256": digest(output / "authorized_key.pub"),
                           "fingerprint": fingerprint,
                           "host_key_store": "/etc/dropbear",
                           "service": "/etc/local.d/dropbear.start",
                           "runlevel": "default"},
        "programs": programs,
        "sd_files": ["BOOT.bin", "boot.scr", "image.ub", *programs],
        "root_partition": {"number": 2, "filesystem": "ext4",
                           "gzip_source": "rootfs.ext4.gz"},
        "boot_partitions": boot_partitions,
        "inputs": {str(path.relative_to(ROOT)): digest(path) for path in
                   (Path(__file__), ROOT / "initramfs.py", ROOT / "packaging_commands.py", INSTALLER, DROPBEAR_START, RUNTIME_ITS, BOOT_COMMAND,
                    ROOT / "ethernet/check_dma_peer.c", ROOT / "ethernet/dma_endpoint.v",
                    ROOT / "ethernet/te0715_ethernet_dma_top.v")},
        "files": files,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    check_output(output)
    return output


def main() -> None:
    """Select retained software, route/assembly evidence and one new output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("dma", "link", "route", "database", "assembly-a", "assembly-b", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    print(build(args.dma.resolve(), args.link.resolve(), args.route.resolve(),
                args.database.resolve(), args.assembly_a.resolve(), args.assembly_b.resolve(),
                args.output.resolve(), args.timeout))


if __name__ == "__main__":
    main()
