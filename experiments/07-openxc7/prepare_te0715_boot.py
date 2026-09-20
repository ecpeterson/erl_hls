#!/usr/bin/env python3
"""Build an SD register-probe candidate for TE0715-05-71C33-A on Apple Silicon."""

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

from boot.board import PART, PROFILE, SKU, prepare_fsbl, replace_once
from check_zynq_boot import bit_payload, check_directory, check_linux_elf

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/boot"
BOOT = ROOT / "boot"
LINUX = "prebuilt/os/petalinux/1GB"


def digest(path: Path) -> str:
    """Hash a file without retaining a toolchain archive in memory."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(args: list[str | Path], cwd: Path, log: Path, env: dict[str, str]) -> None:
    """Run a bounded build step, retaining its output and naming the log on failure."""
    with log.open("a") as stream:
        stream.write(f"\n$ {' '.join(map(str, args))}\n")
        stream.flush()
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, stdout=stream, stderr=stream)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}); see {log}")


def fetch(source: dict[str, str], downloads: Path) -> Path:
    """Reuse a verified archive or download to a temporary file before publishing it."""
    path = downloads / source["file"]
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".partial")
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--output", str(temporary),
                        source["url"]], check=True)
        if digest(temporary) != source["sha256"]:
            temporary.unlink()
            raise ValueError(f"download checksum mismatch: {path.name}")
        temporary.replace(path)
    if digest(path) != source["sha256"]:
        raise ValueError(f"cached archive checksum mismatch: {path}")
    return path


def fresh(directory: Path) -> Path:
    """Replace a generated build subdirectory; never accept an external deletion target."""
    directory.resolve().relative_to(BUILD.resolve())
    if directory.resolve() == BUILD.resolve():
        raise ValueError("refusing to remove the build root")
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    return directory


def unpack_tar(archive: Path, directory: Path) -> Path:
    """Extract one pinned source tree with Python's safe data filter."""
    fresh(directory)
    with tarfile.open(archive) as tar:
        tar.extractall(directory, filter="data")
    children = list(directory.iterdir())
    if len(children) != 1 or not children[0].is_dir():
        raise ValueError(f"expected one archive root: {archive}")
    return children[0]


def unpack_vendor(archive: Path, directory: Path) -> tuple[Path, Path]:
    """Extract only this module's PS source, hooks and retained boot components."""
    fresh(directory)
    prefixes = ("test_board/board_files/", "test_board/sw_lib/",
                f"test_board/prebuilt/hardware/{PROFILE}/", f"test_board/{LINUX}/")
    with zipfile.ZipFile(archive) as zipped:
        for name in zipped.namelist():
            if name.startswith(prefixes) and not name.endswith("/"):
                target = directory / name
                target.resolve().relative_to(directory.resolve())
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(zipped.read(name))
    vendor = directory / "test_board"
    xsa = directory / "xsa"
    xsa.mkdir()
    with zipfile.ZipFile(vendor / f"prebuilt/hardware/{PROFILE}/test_board_{PROFILE}.xsa") as zipped:
        for name in ("ps7_init.c", "ps7_init.h", "zsys.hwh"):
            (xsa / name).write_bytes(zipped.read(name))
    return vendor, xsa


def patch(tree: Path, name: str, log: Path, env: dict[str, str]) -> None:
    """Apply a checked-in portability patch to a freshly extracted upstream tree."""
    run(["patch", "--batch", "-p1", "-i", BOOT / f"patches/{name}.patch"], tree, log, env)


def build_musl(source: Path, compiler: Path, work: Path, log: Path, env: dict[str, str]) -> tuple[Path, Path]:
    """Build static ARM Linux libc and linker settings for this plain-C diagnostic."""
    build = fresh(work / "musl-build")
    sysroot = work / "musl-sysroot"
    gcc = compiler / "bin/arm-none-eabi-gcc"
    settings = dict(env, CC=str(gcc), AR=str(compiler / "bin/arm-none-eabi-ar"),
                    RANLIB=str(compiler / "bin/arm-none-eabi-ranlib"),
                    CFLAGS="-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard")
    run([source / "configure", "--target=arm-linux-gnueabihf", "--disable-shared",
         "--enable-gcc-wrapper", f"--prefix={sysroot}"], build, log, settings)
    run(["make", "-j4"], build, log, settings)
    run(["make", "install"], build, log, settings)
    # Bare-metal GCC supplies non-PIC crtbegin/crtend. Use those only with -static.
    specs = (sysroot / "lib/musl-gcc.specs").read_text()
    for old, new in (("/Scrt1.o", "/crt1.o"), ("crtbeginS.o", "crtbegin.o"), ("crtendS.o", "crtend.o")):
        specs = replace_once(specs, old, new)
    result = build / "static-musl.specs"
    result.write_text(specs)
    script = subprocess.check_output([compiler / "bin/arm-none-eabi-ld", "--verbose"], text=True)
    script = script.split("==================================================")[1]
    # Linux supplies AT_PHDR from mapped ELF headers; bare-metal ld omits them.
    # Keep the compiler's complete section rules, adjusting only this placement.
    script = script.replace('SEGMENT_START("text-segment", 0x8000)',
                            'SEGMENT_START("text-segment", 0x10000)')
    script = replace_once(script, '. = SEGMENT_START("text-segment", 0x10000);',
                          '. = SEGMENT_START("text-segment", 0x10000) + SIZEOF_HEADERS;')
    linker = build / "linux-static.ld"
    linker.write_text(script)
    return result, linker


def fdt(tree: Path, node: str, prop: str, kind: str = "s") -> str:
    """Read a required device-tree property using the native libfdt utility."""
    return subprocess.check_output(["fdtget", "-t", kind, str(tree), node, prop], text=True).strip()


def prepare_device_tree(source: Path, output: Path, log: Path, env: dict[str, str]) -> None:
    """Replace the vendor PL register bank with the probe's single, polling UIO page."""
    old = "/amba_pl/axi_reg32@43c00000"
    clock = "/axi/slcr@f8000000/clkc@100"
    expected = [(old, "compatible", "s", "xlnx,axi-reg32-1.0"),
                (old, "reg", "x", "43c00000 10000"), (old, "clocks", "x", "1 f"),
                (clock, "phandle", "x", "1"), (clock, "fclk-enable", "x", "1"),
                ("/memory@0", "reg", "x", "0 40000000")]
    for node, prop, kind, value in expected:
        if fdt(source, node, prop, kind) != value:
            raise ValueError(f"unexpected device-tree property: {node}/{prop}")
    children = subprocess.check_output(["fdtget", "-l", str(source), "/amba_pl"], text=True).split()
    if children != ["axi_reg32@43c00000"]:
        raise ValueError("unrecognized vendor PL devices")
    shutil.copyfile(source, output)
    run(["fdtput", "-r", output, old], output.parent, log, env)
    run(["fdtput", "-d", output, "/__symbols__", "axi_reg32_0"], output.parent, log, env)
    node = "/amba_pl/probe@40000000"
    run(["fdtput", "-c", output, node], output.parent, log, env)
    for prop, kind, values in [
        ("compatible", "s", ["generic-uio"]), ("linux,uio-name", "s", ["erl-hls-probe"]),
        ("reg", "x", ["40000000", "1000"]), ("clocks", "x", ["1", "f"]),
        ("clock-names", "s", ["s_axi_aclk"]),
    ]:
        run(["fdtput", "-t", kind, output, node, prop, *values], output.parent, log, env)


def check_fit(image: Path, stage: Path, log: Path, env: dict[str, str]) -> None:
    """Require the FIT to reference and hash exactly the three selected payloads."""
    if fdt(image, "/configurations", "default") != "probe":
        raise ValueError("unexpected FIT default configuration")
    for index, (name, filename) in enumerate((('kernel', 'zImage'), ('fdt', 'system.dtb'),
                                             ('ramdisk', 'rootfs.cpio.gz'))):
        if fdt(image, "/configurations/probe", name) != name:
            raise ValueError(f"FIT does not select {name}")
        extracted = stage / f"verify-{name}"
        run(["dumpimage", "-T", "flat_dt", "-p", str(index), "-o", extracted, image], stage, log, env)
        if extracted.read_bytes() != (stage / filename).read_bytes():
            raise ValueError(f"FIT payload differs: {name}")
        expected = bytes.fromhex(digest(extracted))
        actual = bytes(int(b, 16) for b in fdt(image, f"/images/{name}/hash", "value", "bx").split())
        if fdt(image, f"/images/{name}/hash", "algo") != "sha256" or actual != expected:
            raise ValueError(f"FIT digest differs: {name}")
        extracted.unlink()


def build(bitstream: Path, openssl: Path) -> Path:
    """Build, inspect and publish a candidate under build/boot, preserving download caches."""
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise ValueError("this experiment pins the native Darwin ARM64 compiler")
    if any(c.isspace() for c in str(BUILD)):
        raise ValueError("upstream FSBL makefiles require a checkout path without whitespace")
    bit_payload(bitstream.read_bytes())
    for tool in ("curl", "make", "clang", "clang++", "patch", "dtc", "fdtget", "fdtput", "mkimage", "dumpimage"):
        if not shutil.which(tool):
            raise ValueError(f"missing native tool: {tool}")
    if not (openssl / "include/openssl/ssl.h").is_file():
        raise ValueError(f"missing OpenSSL headers: {openssl}")
    lock = json.loads((BOOT / "sources.json").read_text())
    downloads = BUILD / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    archives = {name: fetch(source, downloads) for name, source in lock["sources"].items()}
    work = fresh(BUILD / "work")
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(lock["source_date_epoch"]), LC_ALL="C")
    # Cache only the unmodified compiler; fresh source/build trees avoid stale BSPs.
    compiler_cache = BUILD / "compiler"
    stamp = compiler_cache / ".archive-sha256"
    compiler_hash = lock["sources"]["arm"]["sha256"]
    if not stamp.exists() or stamp.read_text() != compiler_hash:
        compiler = unpack_tar(archives["arm"], compiler_cache)
        stamp.write_text(compiler_hash)
    else:
        compiler = next(p for p in compiler_cache.iterdir() if p.is_dir())
    env["PATH"] = f"{compiler / 'bin'}:{env['PATH']}"
    trees = {name: unpack_tar(archives[name], work / name) for name in ("embeddedsw", "bootgen", "musl")}
    vendor, xsa = unpack_vendor(archives["trenz"], work / "trenz")
    for name in ("embeddedsw", "bootgen"):
        patch(trees[name], name, work / f"{name}.log", env)
    fsbl = prepare_fsbl(trees["embeddedsw"], vendor, xsa)
    print("Building FSBL, Bootgen and ARM Linux diagnostic natively...", flush=True)
    run(["make", "BOARD=te0715", "CFLAGS=-Wall -Os -g -c -DFSBL_DEBUG_INFO",
         "LDFLAGS=-Wl,--start-group,-lxilffs,-lxil,-lgcc,-lc,--end-group", "SHELL=/bin/bash"],
        fsbl, work / "embeddedsw.log", env)
    run(["make", "-j4", "CXX=clang++", "CC=clang", f"INCLUDE_USER=-I{openssl / 'include'}",
         f"LIBS=-L{openssl / 'lib'} -lssl -lcrypto"], trees["bootgen"], work / "bootgen.log", env)
    specs, linker = build_musl(trees["musl"], compiler, work, work / "musl.log", env)
    stage = work / "candidate"
    stage.mkdir()
    for source, name in ((fsbl / "fsbl.elf", "fsbl.elf"), (bitstream, "probe.bit"),
                         (vendor / LINUX / "u-boot.elf", "u-boot.elf")):
        shutil.copyfile(source, stage / name)
    for source, name in (("probe_zynq_ps.c", "probe_zynq_ps"), ("test_probe_zynq_ps.c", "test_probe_zynq_ps")):
        run([compiler / "bin/arm-none-eabi-gcc", f"-specs={specs}", "-std=c11", "-Wall", "-Wextra", "-Werror",
             "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack",
             f"-Wl,-T,{linker}",
             ROOT / source, "-o", stage / name], stage, work / "probe.log", env)
        check_linux_elf((stage / name).read_bytes())
    log = work / "images.log"
    prepare_device_tree(vendor / LINUX / "system.dtb", stage / "system.dtb", log, env)
    for index, name in ((0, "zImage"), (2, "rootfs.cpio.gz")):
        run(["dumpimage", "-T", "flat_dt", "-p", str(index), "-o", stage / name,
             vendor / LINUX / "image.ub"], stage, log, env)
    shutil.copyfile(BOOT / "probe.its", stage / "probe.its")
    run(["mkimage", "-f", "probe.its", "image.ub"], stage, log, env)
    run(["mkimage", "-A", "arm", "-T", "script", "-C", "none", "-n", "TE0715 probe SD boot",
         "-d", BOOT / "boot.cmd", "boot.scr"], stage, log, env)
    (stage / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n u-boot.elf\n"
                                    " [load=0x00100000] system.dtb\n}\n")
    run([trees["bootgen"] / "bootgen", "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"],
        stage, log, env)
    partitions = check_directory(stage)
    check_fit(stage / "image.ub", stage, log, env)
    files = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted(stage.iterdir()) if p.is_file()}
    inputs = [ROOT / name for name in ("prepare_te0715_boot.py", "check_zynq_boot.py",
                                       "probe_zynq_ps.c", "test_probe_zynq_ps.c")]
    inputs += [p for p in BOOT.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    report = {"module": SKU, "carrier": "TEF1002-03-A", "part": PART, "vendor_profile": PROFILE,
              "hardware_validated": False, "source_date_epoch": lock["source_date_epoch"],
              "sources": lock["sources"], "files": files, "boot_partitions": partitions,
              "sd_files": ["BOOT.bin", "boot.scr", "image.ub", "probe_zynq_ps"],
              "retained_vendor_binaries": ["u-boot.elf", "zImage", "rootfs.cpio.gz"],
              "ps_init_sha256": digest(xsa / "ps7_init.c"),
              "build_inputs": {str(p.relative_to(ROOT)): digest(p) for p in sorted(inputs)},
              "compiler": subprocess.check_output([compiler / "bin/arm-none-eabi-gcc", "--version"], text=True).splitlines()[0]}
    (stage / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    published = BUILD / "candidate"
    fresh(published).rmdir()
    stage.rename(published)
    return published


def main() -> None:
    """Build an explicitly supplied register-probe bitstream into a checked SD candidate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bitstream", required=True, type=Path,
                        help="output of run_zynq_ps_probe.sh; no arbitrary PL design")
    parser.add_argument("--openssl-prefix", type=Path, default=Path("/opt/homebrew/opt/openssl@3"))
    args = parser.parse_args()
    print(f"PASS: candidate assembled and inspected at {build(args.bitstream.resolve(), args.openssl_prefix.resolve())}")


if __name__ == "__main__":
    main()
