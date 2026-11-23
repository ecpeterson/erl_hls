#!/usr/bin/env python3
"""Package owned bring-up RTL and pinned generated IP for an offline Vivado host."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from ethernet.board import board_sources
from ethernet.prepare import environment


def prepare(output: Path, phi: Path | None = None) -> dict:
    """Create a new portable source bundle; optionally include an existing phi build.

    The bundle contains no tool installation, credentials or device programming
    commands. The phi directory must contain the three generated RTL files.
    """
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    output.mkdir(parents=True)
    generated = output / "inputs/generated"
    with tempfile.TemporaryDirectory(dir=output) as directory:
        env = environment(ROOT / "build/ethernet-board/sources", Path(directory))
        for name in ("generate.py", "generate_gearbox.py"):
            subprocess.run([sys.executable, "-S", str(ROOT / "ethernet" / name), str(generated)],
                           env=env, check=True, timeout=60)
        simulated = output / "inputs/generated-sim"
        subprocess.run([sys.executable, "-S", str(ROOT / "ethernet/generate.py"),
                        str(simulated), "--simulation"], env=env, check=True, timeout=60)
        shutil.copy2(generated / "liteeth_pcs_gearbox.v", simulated)
    files = set(board_sources(ROOT, generated))
    files.update(ROOT / "gtx" / name for name in
                 ("te0715_gtx_top.v", "te0715_gtx_lane.v", "gtx_probe_sample.v"))
    files.update(ROOT / "dma" / name for name in ("zynq_dma_top.v", "zynq_dma_mailbox.v"))
    for source in sorted(files):
        if source.is_relative_to(generated):
            continue
        destination = output / "inputs" / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    for source in Path(__file__).parent.glob("*.tcl"):
        shutil.copy2(source, output / source.name)
    for source in Path(__file__).parent.glob("*.v"):
        shutil.copy2(source, output / "inputs" / source.name)
    for source in Path(__file__).parent.glob("*.sv"):
        shutil.copy2(source, output / "inputs" / source.name)
    for source in ROOT.glob("ethernet/LICENSE.*"):
        shutil.copy2(source, generated / source.name)
        shutil.copy2(source, simulated / source.name)
    shutil.copy2(ROOT / "gtx/LICENSE.liteiclink", output / "inputs/gtx/LICENSE.liteiclink")
    if phi is not None:
        target = output / "inputs/phi"
        target.mkdir()
        for name in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v"):
            shutil.copy2(phi / name, target / name)
        shutil.copy2(ROOT / "phi_timing_harness.v", target)
    report = {"part": "xc7z030sbg485-1", "hardware_validated": False,
              "files": {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in sorted(output.rglob("*")) if p.is_file()}}
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    """Select a fresh bundle directory and optional previously validated phi RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--phi", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.output.resolve(), args.phi.resolve() if args.phi else None), indent=2))


if __name__ == "__main__":
    main()
