#!/usr/bin/env python3
"""Record source, tool and artifact identity for the carrier-status bitstream."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    """Hash a build input or artifact without loading large files into memory."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def record(build: Path, apio: Path) -> dict:
    """Describe a completed round-trip-checked build; hardware remains unqualified."""
    root = Path(__file__).resolve().parent.parent
    inputs = [root / n for n in ("zynq_ps_probe.v", "zynq_ps_probe_top.v", "run_sfp_probe.sh",
                                 "openxc7_common.sh", "prepare_zynq7030.py", "check_zynq7030_bitstream.py",
                                 "test_sfp_probe.py", "test_te0715_qemu.py")]
    inputs += [p for p in (root / "sfp").rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    prefix = "xc7z030sbg485-1"
    artifacts = [f"{prefix}.{suffix}" for suffix in ("bit", "frames", "fasm", "bits")]
    artifacts += ["netlist.json", "stat.json", "yosys.log", f"{prefix}-nextpnr.log", f"{prefix}-report.json"]
    return {"part": prefix, "module": "TE0715-05-71C33-A", "carrier": "TEF1002-03-A",
        "fclk0_hz": 25000000, "rgpio_hz": 250000, "carrier_controls_activated": False,
        "hardware_validated": False,
        "chipdb_sha256": digest(build.parent / "chipdb/xc7z030sbg485.bin"),
        "chipdb_identity": (build.parent / "chipdb/xc7z030sbg485.bin.toolchain").read_text().strip(),
        "inputs": {str(p.relative_to(root)): digest(p) for p in sorted(inputs)},
        "files": {name: digest(build / name) for name in artifacts},
        "tools": {name: json.loads((apio / "packages" / name / "BUILD-INFO.json").read_text())
                  for name in ("openxc7", "oss-cad-suite")},
        "route": json.loads((build / f"{prefix}-report.json").read_text())}


def main() -> None:
    """Write the manifest after the shell runner verifies bitstream round-tripping."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("apio", type=Path)
    args = parser.parse_args()
    (args.build / "manifest.json").write_text(json.dumps(record(args.build, args.apio), indent=2) + "\n")


if __name__ == "__main__":
    main()
