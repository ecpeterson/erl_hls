#!/usr/bin/env python3
"""Assemble a pinned ARMv7 Alpine/OTP SD root in QEMU using the checked Trenz kernel."""

import argparse
import gzip
import json
import os
import shutil
import stat
import subprocess
import tarfile
import time
from pathlib import Path

from check_zynq_boot import check_directory
from prepare_te0715_boot import digest, fetch, fdt
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime"
BUILD = ROOT / "build/runtime"
SUCCESS = b"PASS: ARM runtime image assembled"
CHECK_SUCCESS = b"PASS: SD-root ARM runtime boot"


def validate_candidate(candidate: Path) -> dict:
    """Require the exact board profile and every boot input's recorded digest."""
    manifest = json.loads((candidate / "manifest.json").read_text())
    if manifest.get("module") != "TE0715-05-71C33-A" or manifest.get("part") != "xc7z030sbg485-1" or manifest.get("carrier") != "TEF1002-03-A":
        raise ValueError("runtime requires the checked TE0715 boot profile")
    for name in ("zImage", "rootfs.cpio.gz", "system.dtb", "BOOT.bin", "fsbl.elf", "probe.bit", "u-boot.elf", "probe_zynq_ps"):
        expected = manifest["files"][name]
        path = candidate / name
        if path.stat().st_size != expected["bytes"] or digest(path) != expected["sha256"]:
            raise ValueError(f"boot payload differs from manifest: {name}")
    check_directory(candidate)
    return manifest


def tar_entries(archive: Path) -> list[tuple[str, bytes, int]]:
    """Convert the pinned base tar to newc entries without extracting onto the host."""
    entries = []
    with tarfile.open(archive) as source:
        members = {member.name.removeprefix("./"): member for member in source.getmembers()}
        for name, member in members.items():
            if not name or name == ".":
                continue
            if name.startswith("/") or ".." in Path(name).parts:
                raise ValueError(f"unsafe archive path: {name}")
            if member.isdir():
                entries.append((name, b"", stat.S_IFDIR | member.mode))
            elif member.issym():
                entries.append((name, member.linkname.encode(), stat.S_IFLNK | member.mode))
            elif member.isfile() or member.islnk():
                payload = source.extractfile(member)
                if payload is None:
                    raise ValueError(f"missing archive data: {name}")
                entries.append((name, payload.read(), stat.S_IFREG | member.mode))
            else:
                raise ValueError(f"unsupported archive member: {name}")
    return entries


def cpio_entries(data: bytes) -> list[tuple[str, bytes, int]]:
    """Read regular files, directories and symlinks from one newc initramfs."""
    entries = []
    offset = 0
    while data[offset:offset + 6] == b"070701":
        if len(data) < offset + 110:
            raise ValueError("truncated newc header")
        fields = [int(data[offset + 6 + i * 8:offset + 14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        start = offset + 110
        if namesize < 1 or start + namesize > len(data) or data[start + namesize - 1] != 0:
            raise ValueError("invalid newc name")
        name = data[start:start + namesize - 1].decode()
        if name.startswith("/") or ".." in Path(name).parts:
            raise ValueError(f"unsafe initramfs path: {name}")
        start = (start + namesize + 3) & ~3
        end = start + size
        if end > len(data):
            raise ValueError("truncated initramfs")
        if name == "TRAILER!!!":
            return entries
        entries.append((name.removeprefix("./"), data[start:end], fields[1]))
        offset = (end + 3) & ~3
    raise ValueError("invalid or unterminated newc initramfs")


def tree_entries(source: Path, prefix: str) -> list[tuple[str, bytes, int]]:
    """Package ordinary project files under a fixed target path."""
    entries = [(prefix, b"", stat.S_IFDIR | 0o755)]
    for path in sorted(source.rglob("*")):
        name = f"{prefix}/{path.relative_to(source)}"
        if path.is_dir():
            entries.append((name, b"", stat.S_IFDIR | 0o755))
        elif path.is_file() and not path.is_symlink():
            entries.append((name, path.read_bytes(), stat.S_IFREG | (path.stat().st_mode & 0o777)))
        else:
            raise ValueError(f"unsupported project file: {path}")
    return entries


def guest(candidate: Path, image: Path, log: Path, timeout: int, initrd: Path | None) -> None:
    """Run an isolated one-CPU Zynq guest; require success and a clean shutdown."""
    command = ["qemu-system-arm", "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(candidate / "zImage"), "-dtb", str(candidate / "system.dtb"),
               "-drive", f"file={image},if=sd,format=raw"]
    if initrd:
        command += ["-initrd", str(initrd), "-append", "console=ttyPS0,115200 rdinit=/build-init panic=-1"]
    else:
        command += ["-snapshot", "-append", "console=ttyPS0,115200 root=/dev/mmcblk0 rw rootwait hls.runtime_check=1 panic=-1"]
    with log.open("wb") as output:
        try:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"QEMU timed out; see {log}") from error
    marker = SUCCESS if initrd else CHECK_SUCCESS
    if result.returncode or marker not in log.read_bytes().splitlines():
        raise RuntimeError(f"QEMU image check failed; see {log}")


def boot_files(candidate: Path, stage: Path, epoch: int) -> None:
    """Package and independently extract the kernel/DT FIT and SD boot script."""
    for name in ("BOOT.bin", "zImage", "system.dtb"):
        shutil.copyfile(candidate / name, stage / name)
    shutil.copyfile(RUNTIME / "runtime.its", stage / "runtime.its")
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(epoch))
    with (BUILD / "images.log").open("w") as log:
        subprocess.run(["mkimage", "-f", "runtime.its", "image.ub"], cwd=stage, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["mkimage", "-A", "arm", "-T", "script", "-C", "none", "-n", "TE0715 OTP SD root",
                        "-d", str(RUNTIME / "boot.cmd"), str(stage / "boot.scr")], env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        fit = stage / "image.ub"
        if fdt(fit, "/configurations", "default") != "runtime":
            raise ValueError("unexpected runtime FIT configuration")
        for index, (name, filename) in enumerate((("kernel", "zImage"), ("fdt", "system.dtb"))):
            if fdt(fit, "/configurations/runtime", name) != name:
                raise ValueError(f"FIT does not select {name}")
            extracted = stage / f"verify-{name}"
            subprocess.run(["dumpimage", "-T", "flat_dt", "-p", str(index), "-o", str(extracted), str(fit)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            actual = bytes(int(b, 16) for b in fdt(fit, f"/images/{name}/hash", "value", "bx").split())
            if digest(extracted) != digest(stage / filename) or actual != bytes.fromhex(digest(extracted)):
                raise ValueError(f"runtime FIT data/hash mismatch: {name}")
            extracted.unlink()


def build(candidate: Path, timeout: int) -> Path:
    """Produce a separate SD-root candidate without altering the register-probe image."""
    lock = json.loads((RUNTIME / "packages.lock.json").read_text())
    if timeout < 1:
        raise ValueError("timeout must be positive")
    for tool in ("qemu-system-arm", "rebar3", "mkimage", "dumpimage", "fdtget"):
        if shutil.which(tool) is None:
            raise ValueError(f"required tool: {tool}")
    manifest = validate_candidate(candidate)
    downloads = BUILD / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    base = fetch(lock["rootfs"], downloads)
    packages = [fetch(package, downloads) for package in lock["packages"]]
    subprocess.run(["rebar3", "compile"], cwd=ROOT.parent.parent, check=True)
    entries = tar_entries(base)
    entries += [("packages", b"", stat.S_IFDIR | 0o755)]
    entries += [(f"packages/{p.name}", p.read_bytes(), stat.S_IFREG | 0o644) for p in packages]
    entries += [(name, content, mode) for name, content, mode in
                cpio_entries(gzip.decompress((candidate / "rootfs.cpio.gz").read_bytes()))
                if name == "lib/modules" or name.startswith("lib/modules/")]
    entries += tree_entries(ROOT.parent.parent / "_build/default/lib/erl_hls/ebin", "opt/erl-hls/lib/erl_hls/ebin")
    entries += tree_entries(RUNTIME / "bin", "opt/erl-hls/bin")
    entries.append(("opt/erl-hls/bin/probe_zynq_ps", (candidate / "probe_zynq_ps").read_bytes(), stat.S_IFREG | 0o755))
    for name in ("hls_fabric_tests.erl", "hls_fabric_client_tests.erl", "phi_memory_fabric_fixture.erl", "hls_reply_fixture.erl", "hls_logical_fixture.erl"):
        entries.append((f"opt/erl-hls/tests/{name}", (ROOT.parent.parent / "test" / name).read_bytes(), stat.S_IFREG | 0o644))
    versions = {p["name"]: p["version"] for p in lock["packages"]}
    world = "".join(f"{name}={versions[name]}\n" for name in lock["roots"]).encode()
    entries += [("runtime-world", world, stat.S_IFREG | 0o644),
                ("build-init", (RUNTIME / "build-init.sh").read_bytes(), stat.S_IFREG | 0o755),
                ("etc/local.d/runtime-check.start", (RUNTIME / "check.start").read_bytes(), stat.S_IFREG | 0o755),
                ("opt/erl-hls/check-init", (RUNTIME / "check-init.sh").read_bytes(), stat.S_IFREG | 0o755)]
    # newc extraction needs parent directories before their children.
    existing = {name for name, _, _ in entries}
    parents = {str(p) for name in existing for p in Path(name).parents if str(p) != "."} - existing
    entries = [(name, b"", stat.S_IFDIR | 0o755) for name in sorted(parents, key=lambda n: (n.count('/'), n))] + entries
    initrd = BUILD / "assembly.cpio.gz"
    entries.sort(key=lambda e: (e[0].count("/"), not stat.S_ISDIR(e[2]), e[0]))
    initrd.write_bytes(gzip.compress(cpio(entries), mtime=0))
    stage = BUILD / "stage"
    if stage.is_symlink():
        raise ValueError("refusing symlinked staging directory")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    image = stage / "rootfs.ext4"
    with image.open("wb") as output:
        output.truncate(512 * 1024 * 1024)
    print("Assembling and testing ARM Linux/OTP in offline QEMU...", flush=True)
    started = time.monotonic()
    guest(candidate, image, BUILD / "assembly-uart.log", timeout, initrd)
    print("Booting the resulting ext4 root filesystem...", flush=True)
    guest(candidate, image, BUILD / "sd-root-uart.log", timeout, None)
    boot_files(candidate, stage, manifest["source_date_epoch"])
    rootfs = {"sha256": digest(image), "bytes": image.stat().st_size}
    with image.open("rb") as source, (stage / "rootfs.ext4.gz").open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    image.unlink()
    result = {"base_boot_manifest_sha256": digest(candidate / "manifest.json"),
              "package_lock_sha256": digest(RUNTIME / "packages.lock.json"),
              "hardware_validated": False, "dma_hardware_exercised": False,
              "qemu_seconds": round(time.monotonic() - started, 2),
              "rootfs_uncompressed": rootfs,
              "project_commit": subprocess.check_output(
                  ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "erl_hls_beams": {p.name: digest(p) for p in sorted(
                  (ROOT.parent.parent / "_build/default/lib/erl_hls/ebin").glob("*.beam"))},
              "build_inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                               [Path(__file__), *sorted(RUNTIME.rglob("*"))] if p.is_file()},
              "files": {p.name: {"sha256": digest(p), "bytes": p.stat().st_size}
                        for p in stage.iterdir() if p.is_file()}}
    (stage / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    output = BUILD / "candidate"
    if output.is_symlink():
        raise ValueError("refusing symlinked candidate directory")
    if output.exists():
        shutil.rmtree(output)
    stage.rename(output)
    initrd.unlink()
    return output


def main() -> None:
    """Build from an explicit verified boot candidate with bounded QEMU runs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    print(build(args.candidate.resolve(), args.timeout))


if __name__ == "__main__":
    main()
