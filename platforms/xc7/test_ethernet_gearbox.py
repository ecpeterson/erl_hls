#!/usr/bin/env python3
"""Qualify the pinned PCS gearbox and GTX raw-pin adapter with whole frames."""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from ethernet.prepare import digest, environment
from test_ethernet import simulate, synthesize, yosys_data


def run(yosys: Path, output: Path) -> dict:
    """Check word alignment and phase choices, then map production-timer hardware."""
    started = time.monotonic()
    root = Path(__file__).resolve().parent
    source = root / "ethernet"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="gearbox-", dir=output) as directory:
        stage = Path(directory)
        env = environment(output / "sources", stage / "sources")
        checks = []
        for name in ("simulation", "production"):
            destination = stage / name
            command = [sys.executable, "-S", str(source / "generate.py"), str(destination)]
            if name == "simulation":
                command.append("--simulation")
            subprocess.run(command, env=env, check=True, timeout=30)
            subprocess.run([sys.executable, "-S", str(source / "generate_gearbox.py"), str(destination)],
                           env=env, check=True, timeout=30)
            sources = [destination / "liteeth_packet_core.v", destination / "liteeth_pcs_gearbox.v",
                       source / "frame_store.v", source / "packet_endpoint.v", source / "gtx_packet_endpoint.v"]
            if name == "simulation":
                lowered = synthesize(yosys, destination, sources, False, "ethernet_gtx_packet_endpoint")
                # Every initial serial bit position; both possible /2 phases.
                for offset in range(20):
                    phase = offset % 2
                    simulate(destination, lowered, None, output / "sources", (offset, phase), alignment_only=True)
                    log = f"lowered-offset-{offset}-phase-{phase}.log"
                    shutil.copyfile(destination / "simulation.log", destination / log)
                    checks.append({"mapped": False, "alignment_only": True, "bit_offset": offset, "half_phase": phase,
                                   "log_sha256": digest(destination / log)})
                for offset, phase in ((7, 0), (13, 1)):
                    simulate(destination, lowered, None, output / "sources", (offset, phase))
                    log = f"lowered-full-offset-{offset}-phase-{phase}.log"
                    shutil.copyfile(destination / "simulation.log", destination / log)
                    checks.append({"mapped": False, "alignment_only": False, "bit_offset": offset,
                                   "half_phase": phase, "log_sha256": digest(destination / log)})
            mapped = synthesize(yosys, destination, sources, True, "ethernet_gtx_packet_endpoint")
            if name == "simulation":
                for offset, phase in ((7, 0), (13, 1)):
                    simulate(destination, mapped, yosys_data(yosys) / "xilinx/cells_sim.v",
                             output / "sources", (offset, phase))
                    log = f"mapped-offset-{offset}-phase-{phase}.log"
                    shutil.copyfile(destination / "simulation.log", destination / log)
                    checks.append({"mapped": True, "alignment_only": False, "bit_offset": offset, "half_phase": phase,
                                   "log_sha256": digest(destination / log)})
        cells = json.loads((stage / "production/stat.json").read_text())["modules"]["\\ethernet_gtx_packet_endpoint"]["num_cells_by_type"]
        if cells.get("RAMB36E1") != 2:
            raise AssertionError(f"expected the two frame-store BRAMs: {cells}")
        report = {
            "scope": "One packet endpoint through LiteEth PCSGearbox and GTX raw data pins; ideal related clocks/serial alignment model; no hard GTX/MMCM, pins, route or board qualification",
            "sources": json.loads((source / "sources.lock.json").read_text()),
            "inputs": {str(path.relative_to(root)): digest(path) for path in sorted(source.iterdir()) if path.is_file()},
            "runner_sha256": digest(Path(__file__)),
            "packet_runner_sha256": digest(root / "test_ethernet.py"),
            "generated": {str(path.relative_to(stage)): digest(path) for path in sorted(stage.rglob("*"))
                          if path.is_file() and path.name in ("liteeth_packet_core.v", "liteeth_pcs_gearbox.v")},
            "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
            "production_cells": cells, "packet_runs": checks,
            "elapsed_seconds": round(time.monotonic() - started, 2), "hardware_qualified": False,
        }
        (stage / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        candidate = output / "candidate"
        if candidate.exists():
            shutil.rmtree(candidate)
        stage.rename(candidate)
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    """Select local tools and an ignored directory for reproducible evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path, default=Path(shutil.which("yosys") or "yosys"))
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "build/ethernet-gearbox")
    args = parser.parse_args()
    run(args.yosys.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
