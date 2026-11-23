#!/usr/bin/env python3
"""Package matched role-A/role-B repetition-link images over the checked SSH root."""

import argparse
import gzip
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

from check_zynq_boot import check_directory
from dma.debug_device_tree import add_debug_mailbox, check_pair_tree
from ethernet.prepare import digest
from packaging_commands import execute
from prepare_te0715_runtime import guest, selected_beam_entries, tree_entries
from initramfs import cpio

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
INSTALLER = ROOT / "application/install_repetition_link.sh"
CHECK = ROOT / "application/check_repetition_link.escript"
RELOAD = ROOT / "application/reload_repetition_pl.sh"
DMA_START = ROOT / "application/hls-dma.start"
NETWORK_START = ROOT / "application/repetition-network.start"
DEFAULT_APPLICATION = ROOT / "build/repetition-link/rtl"
RUNTIME_ITS = ROOT / "runtime/runtime.its"
BOOT_COMMAND = ROOT / "runtime/boot.cmd"


def checked_file(path: Path, record: dict) -> Path:
    """Require one retained file's size and digest before reuse."""
    if path.stat().st_size != record["bytes"] or digest(path) != record["sha256"]:
        raise ValueError(f"retained file differs: {path}")
    return path


def clock_input(peer: Path, clock: Path | None) -> tuple[Path, dict, Path]:
    """Select either the peer kit's FSBL or a standalone checked clock-FSBL build."""
    directory = peer if clock is None else clock
    manifest_path = directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    fsbl = directory / "fsbl.elf"
    if "files" in manifest:
        checked_file(fsbl, manifest["files"]["fsbl.elf"])
    elif fsbl.stat().st_size == 0 or digest(fsbl) != manifest["fsbl_sha256"]:
        raise ValueError("clock FSBL differs from its manifest")
    if manifest.get("fsbl_programs_si5338") is not True or \
            not isinstance(manifest.get("fclk0_hz"), int) or manifest["fclk0_hz"] <= 0:
        raise ValueError("clock FSBL lacks the required Si5338/FCLK0 contract")
    return fsbl, manifest, manifest_path


def application_inputs(application: Path) -> dict:
    """Require generated role/deployment outputs to match their application manifest."""
    manifest = json.loads((application / "manifest.json").read_text())
    for name, expected in manifest["inputs"].items():
        if digest(PROJECT / name) != expected:
            raise ValueError(f"partition application input changed: {name}")
    for name, expected in manifest["outputs"].items():
        directory = "dslx" if name.endswith(".etf") or name == "fixture.json" else \
            "ebin" if name.endswith(".beam") else ""
        path = application / directory / name
        if digest(path) != expected:
            raise ValueError(f"generated application output differs: {name}")
    return manifest


def role_bitstream(assembly: Path, route: Path, role: str) -> tuple[Path, dict]:
    """Check a role's routed FASM and round-tripped assembled bitstream."""
    route_manifest = json.loads((route / "result.json").read_text())
    assembly_manifest = json.loads((assembly / "result.json").read_text())
    if route_manifest["profile"]["role"] != role or \
            digest(route / "probe.fasm") != route_manifest["fasm_sha256"] or \
            digest(assembly / "input.fasm") != route_manifest["fasm_sha256"] or \
            digest(assembly / "candidate.bit") != assembly_manifest["bitstream_sha256"]:
        raise ValueError(f"role-{role} physical artifacts differ")
    return assembly / "candidate.bit", {
        "route_manifest_sha256": digest(route / "result.json"),
        "assembly_manifest_sha256": digest(assembly / "result.json"),
        "bitstream_sha256": assembly_manifest["bitstream_sha256"],
        "modeled_targets_met": route_manifest["modeled_targets_met"],
        "partial_timing": route_manifest["partial_timing"]["fmax"],
    }


def boot_files(dma: Path, fsbl: Path, bitstream: Path, role: str, output: Path) -> None:
    """Create and validate one role-specific FAT boot payload."""
    dma_manifest = json.loads((dma / "manifest.json").read_text())
    output.mkdir(parents=True)
    shutil.copyfile(fsbl, output / "fsbl.elf")
    for source, name, record in (
            (dma / "u-boot.elf", "u-boot.elf", dma_manifest["files"]["u-boot.elf"]),
            (dma / "zImage", "zImage", dma_manifest["files"]["zImage"])):
        shutil.copyfile(checked_file(source, record), output / name)
    shutil.copyfile(bitstream, output / "probe.bit")
    (output / "repetition-role").write_text(role + "\n")
    try:
        check_pair_tree(dma / "system.dtb")
    except (ValueError, subprocess.CalledProcessError):
        add_debug_mailbox(dma / "system.dtb", output / "system.dtb")
    else:
        shutil.copyfile(dma / "system.dtb", output / "system.dtb")
    check_pair_tree(output / "system.dtb")
    shutil.copyfile(RUNTIME_ITS, output / "runtime.its")
    shutil.copyfile(BOOT_COMMAND, output / "boot.cmd")
    (output / "boot.bif").write_text(
        "the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n u-boot.elf\n"
        " [load=0x00100000] system.dtb\n}\n")
    environment = dict(os.environ, SOURCE_DATE_EPOCH="1729850430")
    log = output / "build.log"
    execute(["mkimage", "-f", "runtime.its", "image.ub"], output, log, environment)
    execute(["mkimage", "-A", "arm", "-T", "script", "-C", "none",
             "-n", "TE0715 partition link", "-d", "boot.cmd", "boot.scr"],
            output, log, environment)
    bootgen = next((ROOT / "build/boot/work/bootgen").glob("*/bootgen"))
    execute([bootgen, "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin",
             "-w", "on"], output, log, environment)
    execute([bootgen, "-arch", "zynq", "-image", "boot.bif",
             "-process_bitstream", "bin", "-w", "on"], output, log, environment)
    check_fpga_manager_bin(output / "probe.bit.bin")
    check_directory(output)


def check_fpga_manager_bin(path: Path) -> None:
    """Require the byte-swapped, aligned sync word expected by Zynq FPGA Manager."""
    data = path.read_bytes()
    if len(data) % 4 or data[:128].find(b"\x66\x55\x99\xaa") < 0:
        raise ValueError(f"invalid Zynq FPGA-manager bitstream: {path}")


def install_root(base: Path, boot_base: Path, candidate: Path,
                 application: Path, role_bins: dict[str, Path], timeout: int, *,
                 runtime_beams: Path, fabric_beams: Path, examples: dict[str, Path]) -> dict:
    """Install current BEAM/application files once and QEMU-check the copied root."""
    base_manifest = json.loads((base / "manifest.json").read_text())
    raw = candidate / "rootfs.ext4"
    with gzip.open(base / "rootfs.ext4.gz", "rb") as source, raw.open("wb") as output:
        shutil.copyfileobj(source, output)
    if digest(raw) != base_manifest["rootfs_uncompressed"]["sha256"]:
        raise ValueError("SSH root filesystem differs after decompression")
    entries = [
        ("repetition-link-init", INSTALLER.read_bytes(), stat.S_IFREG | 0o755),
        ("check_repetition_link.escript", CHECK.read_bytes(), stat.S_IFREG | 0o755),
        ("reload_repetition_pl.sh", RELOAD.read_bytes(), stat.S_IFREG | 0o755),
        ("hls-dma.start", DMA_START.read_bytes(), stat.S_IFREG | 0o755),
        ("repetition-network.start", NETWORK_START.read_bytes(), stat.S_IFREG | 0o755),
        ("hls-runtime", b"", stat.S_IFDIR | 0o755),
        ("examples", b"", stat.S_IFDIR | 0o755),
        ("hls-fabric", b"", stat.S_IFDIR | 0o755),
        ("deployment-a.etf", (application / "dslx/deployment-a.etf").read_bytes(),
         stat.S_IFREG | 0o644),
        ("deployment-b.etf", (application / "dslx/deployment-b.etf").read_bytes(),
         stat.S_IFREG | 0o644),
        ("fixture.json", (application / "dslx/fixture.json").read_bytes(),
         stat.S_IFREG | 0o644),
        *[(f"repetition-link-{role}.bit.bin", path.read_bytes(), stat.S_IFREG | 0o644)
          for role, path in sorted(role_bins.items())],
        *[(f"repetition-link-{role}.bit.bin.sha256",
           f"{digest(path)}  repetition-link-{role}.bit.bin\n".encode(),
           stat.S_IFREG | 0o644)
          for role, path in sorted(role_bins.items())],
        *tree_entries(runtime_beams, "hls-runtime/ebin"),
        *selected_beam_entries(examples, "examples/ebin"),
        *tree_entries(fabric_beams, "hls-fabric/ebin"),
    ]
    initrd = candidate / "install.cpio.gz"
    initrd.write_bytes((boot_base / "rootfs.cpio.gz").read_bytes() +
                       gzip.compress(cpio(entries), mtime=0))
    command = ["qemu-system-arm", "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", candidate / "zImage", "-dtb", candidate / "system.dtb",
               "-initrd", initrd,
               "-append", "console=ttyPS0,115200 rdinit=/repetition-link-init panic=-1",
               "-drive", f"file={raw},if=sd,format=raw"]
    log = candidate / "install-uart.log"
    with log.open("wb") as output:
        try:
            result = subprocess.run([str(value) for value in command], stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"QEMU installer timed out; see {log}") from error
    installed = b"PASS: repetition-link application files installed"
    if result.returncode or installed not in log.read_bytes().splitlines():
        raise RuntimeError(f"QEMU installation failed; see {log}")
    guest(candidate, raw, candidate / "sd-root-uart.log", timeout, None)
    record = {"bytes": raw.stat().st_size, "sha256": digest(raw),
              "runtime_beams": {
                  "hls_runtime": {path.name: digest(path) for path in runtime_beams.glob("*.beam")},
                  "hls_fabric": {path.name: digest(path) for path in fabric_beams.glob("*.beam")}},
              "example_beams": {name: digest(path) for name, path in examples.items()}}
    with raw.open("rb") as source, (candidate / "rootfs.ext4.gz").open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    raw.unlink()
    initrd.unlink()
    return record


def manifest(candidate: Path, role: str, dma: Path, clock_manifest: Path, base: Path,
             application_dir: Path, application: dict, physical: dict, root: dict) -> None:
    """Write one role manifest after all boot and root artifacts are final."""
    dma_manifest = json.loads((dma / "manifest.json").read_text())
    clock = json.loads(clock_manifest.read_text())
    base_manifest = json.loads((base / "manifest.json").read_text())
    files = {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)}
             for path in candidate.iterdir() if path.is_file() and path.name != "manifest.json"}
    record = {
        "profile": "repetition-link-" + role,
        "purpose": ("Role-specific half of the N=6 repetition application over "
                    "a private 1000BASE-X link"),
        "role": role,
        "module": dma_manifest["module"],
        "carrier": dma_manifest["carrier"],
        "part": dma_manifest["part"],
        "kernel_release": dma_manifest["kernel_release"],
        "fclk0_hz": clock["fclk0_hz"],
        "reference_clock_hz_required": 125_000_000,
        "hardware_validated": False,
        "timing_qualified": False,
        "dma_devices": ["/dev/hls-dma0", "/dev/hls-dma1"],
        "application_manifest_sha256": digest(application_dir / "manifest.json"),
        "application_outputs": application["outputs"],
        "compiler_root": application["compiler_root"],
        "rebar_profile": application["rebar_profile"],
        "physical": physical,
        "rootfs_uncompressed": root,
        "ssh_root_manifest_sha256": digest(base / "manifest.json"),
        "authorized_key": base_manifest["authorized_key"],
        "si5338_fsbl_manifest_sha256": digest(clock_manifest),
        "sd_files": ["BOOT.bin", "boot.scr", "image.ub", "repetition-role"],
        "root_partition": {"number": 2, "filesystem": "ext4",
                           "gzip_source": "rootfs.ext4.gz"},
        "boot_partitions": check_directory(candidate),
        "inputs": {str(path.relative_to(ROOT)): digest(path) for path in
                    (Path(__file__), ROOT / "initramfs.py", ROOT / "packaging_commands.py", INSTALLER, CHECK, RELOAD, DMA_START, NETWORK_START,
                    ROOT / "dma/debug_device_tree.py", ROOT / "prepare_ps_probe.py",
                    RUNTIME_ITS, BOOT_COMMAND)},
        "files": files,
    }
    (candidate / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")


def build(dma: Path, peer: Path, clock: Path | None, base: Path, boot_base: Path,
          application_dir: Path,
          route_a: Path, assembly_a: Path, route_b: Path, assembly_b: Path,
          output: Path, timeout: int) -> Path:
    """Create and QEMU-check two fresh role candidates with one identical SSH root."""
    if timeout < 1:
        raise ValueError("timeout must be positive")
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    application = application_inputs(application_dir)
    sys.path.insert(0, str(PROJECT / "tools/hls_fabric"))
    from backend_paths import application_directory, compiler_runtime_ebin
    from compiler_paths import compiler_root
    profile = application["rebar_profile"]
    public = compiler_root(profile, Path(application["compiler_root"]), PROJECT)
    runtime_beams = compiler_runtime_ebin(public, profile)
    memory = application_directory("hls_phi", profile, PROJECT) / "ebin/phi_repetition_memory.beam"
    if not memory.is_file():
        raise FileNotFoundError(f"missing runtime example: {memory}")
    examples = {"phi_repetition_memory": memory}
    fabric_beams = application_directory("hls_fabric", profile, PROJECT) / "ebin"
    output.mkdir(parents=True)
    fsbl, _clock, clock_manifest = clock_input(peer, clock)
    role_data = {}
    for role, route, assembly in (("a", route_a, assembly_a), ("b", route_b, assembly_b)):
        bitstream, physical = role_bitstream(assembly, route, role)
        candidate = output / role
        boot_files(dma, fsbl, bitstream, role, candidate)
        role_data[role] = (candidate, physical)
    role_bins = {role: candidate / "probe.bit.bin"
                 for role, (candidate, _physical) in role_data.items()}
    root = install_root(base, boot_base, role_data["a"][0],
                        application_dir, role_bins, timeout,
                        runtime_beams=runtime_beams, fabric_beams=fabric_beams, examples=examples)
    shutil.copyfile(role_data["a"][0] / "rootfs.ext4.gz",
                    role_data["b"][0] / "rootfs.ext4.gz")
    for role, (candidate, physical) in role_data.items():
        manifest(candidate, role, dma, clock_manifest, base, application_dir,
                 application, physical, root)
    return output


def main() -> None:
    """Select retained software/physical inputs and one fresh pair directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("dma", "peer", "base", "boot-base", "route-a", "assembly-a",
                 "route-b", "assembly-b", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--clock", type=Path)
    parser.add_argument("--application", type=Path, default=DEFAULT_APPLICATION)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    clock = args.clock.resolve() if args.clock else None
    print(build(args.dma.resolve(), args.peer.resolve(), clock, args.base.resolve(),
                args.boot_base.resolve(), args.application.resolve(),
                args.route_a.resolve(), args.assembly_a.resolve(),
                args.route_b.resolve(), args.assembly_b.resolve(), args.output.resolve(),
                args.timeout))


if __name__ == "__main__":
    main()
