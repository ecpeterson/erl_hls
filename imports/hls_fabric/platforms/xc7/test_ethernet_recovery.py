#!/usr/bin/env python3
"""Check supervised packet recovery with physically stopped user clocks."""

import argparse
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from ethernet.prepare import digest, environment
from ethernet.board import map_board
from test_ethernet import simulation_models, synthesize, yosys_data

# Bound startup rejection cheaply; retain the real 1,024-cycle clock watchdog.
SIMULATION_PARAMETERS = {"TIMEOUT_CYCLES": 2000}


def check_driver(stage: Path) -> None:
    """Check identity-before-write and bounded success/fault paths over fake MMIO."""
    source = Path(__file__).resolve().parent / "ethernet/probe_ethernet.c"
    executable = stage / "probe-ethernet"
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(executable)], check=True)
    device = stage / "fake-uio"
    for identity, status, sent, received, bad, run, expected in (
        (0, 0, 0, 0, 0, True, 1),
        (0x45544837, 0x30006, 5, 5, 0, False, 0),
        (0x45544837, 0x30006, 5, 5, 0, True, 0),
        (0x45544837, 0x2007, 0, 0, 0, True, 1),
        (0x45544837, 0x30006, 5, 5, 1, True, 1),
    ):
        device.write_bytes(struct.pack("=9I", identity, 1, 0x55, 0, 0, status, sent, received, bad).ljust(4096, b"\0"))
        result = subprocess.run([str(executable), str(device), *(["--run"] if run else [])], capture_output=True, text=True, timeout=1)
        assert result.returncode == expected, result.stdout + result.stderr
        control, = struct.unpack_from("=I", device.read_bytes(), 8)
        assert control == (0 if run and identity else 0x55)


def check_probe(yosys: Path, stage: Path) -> None:
    """Check diagnostic frames and coherent status before and after mapping."""
    root = Path(__file__).resolve().parent
    source = root / "ethernet"
    bench = source / "probe_tb.sv"
    original = [source / "probe_traffic.v", source / "snapshot.v", root / "zynq_ps_probe.v"]
    for mapped in (False, True):
        sources = original
        if mapped:
            sources = []
            for module, parameters in (("ethernet_probe_traffic", {"GAP_CYCLES": 40}), ("ethernet_snapshot", {"WIDTH": 64})):
                target = stage / module
                target.mkdir()
                sources.append(synthesize(yosys, target, original, True, module, parameters))
            sources.append(yosys_data(yosys) / "xilinx/cells_sim.v")
        executable = stage / "probe.vvp"
        subprocess.run(["iverilog", "-g2012", *(["-DMAPPED_PROBE"] if mapped else []),
                        "-s", "ethernet_probe_tb", "-o", str(executable), str(bench), *map(str, sources)],
                       check=True, timeout=30)
        subprocess.run(["vvp", str(executable)], check=True, timeout=15)


def simulate(stage: Path, rtl: Path, models: Path | None, cache: Path, phase: int) -> dict:
    """Exercise both clock pairs, lock/done faults and complete frame restart."""
    source = Path(__file__).resolve().parent / "ethernet"
    sources = [rtl, source / "gearbox_packet_fixture.sv", source / "recovery_tb.sv",
               *simulation_models(stage, models, cache)]
    executable = stage / "recovery.vvp"
    subprocess.run(["iverilog", "-g2012", "-DSUPERVISED", "-s", "recovery_tb",
                    "-Precovery_tb.STARTUP_TIMEOUT=2000",
                    *(["-s", "glbl"] if models else []), "-o", str(executable),
                    *map(str, sources)], cwd=stage, check=True, timeout=60)
    log = stage / f"{'mapped' if models else 'lowered'}-phase-{phase}.log"
    with log.open("w") as output:
        process = subprocess.run(["vvp", str(executable), f"+half_phase={phase}", "+bit_offset=7"],
                                 cwd=stage, stdout=output, stderr=subprocess.STDOUT, timeout=120)
    text = log.read_text()
    print(text.strip(), flush=True)
    process.check_returncode()
    if "PASS:" not in text:
        raise AssertionError(text)
    return {"mapped": models is not None, "half_phase": phase, "log_sha256": digest(log)}


def run(yosys: Path, output: Path) -> dict:
    """Map the complete supervisor and compare its area with the same packet core."""
    started = time.monotonic()
    root = Path(__file__).resolve().parent
    source = root / "ethernet"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="recovery-", dir=output) as directory:
        stage = Path(directory)
        check_driver(stage)
        check_probe(yosys, stage)
        env = environment(output / "sources", stage / "sources")
        checks = []
        cells = {}
        board_profiles = []
        for name in ("simulation", "production"):
            destination = stage / name
            subprocess.run([sys.executable, "-S", str(source / "generate.py"), str(destination),
                            *(["--simulation"] if name == "simulation" else [])], env=env, check=True, timeout=30)
            subprocess.run([sys.executable, "-S", str(source / "generate_gearbox.py"), str(destination)],
                           env=env, check=True, timeout=30)
            base = [destination / "liteeth_packet_core.v", destination / "liteeth_pcs_gearbox.v",
                    source / "frame_store.v", source / "packet_endpoint.v", source / "gtx_packet_endpoint.v"]
            sources = [*base, source / "clock_pair.v", source / "supervised_endpoint.v",
                       root / "gtx/gtx_probe_control.v", root / "zynq_ps_probe.v"]
            if name == "simulation":
                lowered = synthesize(yosys, destination, sources, False, "ethernet_supervised_endpoint", SIMULATION_PARAMETERS)
                for phase in (0, 1):
                    checks.append(simulate(destination, lowered, None, output / "sources", phase))
            else:
                synthesize(yosys, destination, base, True, "ethernet_gtx_packet_endpoint")
                cells["baseline"] = json.loads((destination / "stat.json").read_text())["modules"]["\\ethernet_gtx_packet_endpoint"]["num_cells_by_type"]
            mapped = synthesize(yosys, destination, sources, True, "ethernet_supervised_endpoint",
                                SIMULATION_PARAMETERS if name == "simulation" else None)
            if name == "simulation":
                for phase in (0, 1):
                    checks.append(simulate(destination, mapped, yosys_data(yosys) / "xilinx/cells_sim.v", output / "sources", phase))
            else:
                cells["candidate"] = json.loads((destination / "stat.json").read_text())["modules"]["\\ethernet_supervised_endpoint"]["num_cells_by_type"]
                for external in (False, True):
                    board_profiles.append(map_board(yosys, root, destination, stage / f"board-{int(external)}", external))
        if any(value.get("RAMB36E1") != 2 for value in cells.values()):
            raise AssertionError(f"frame-store BRAM retention changed: {cells}")
        report = {
            "scope": "Control-supervised raw GTX packet endpoint; modeled status and ideal related clocks; no MMCM, hard GTX, physical timing or board qualification",
            "sources": json.loads((source / "sources.lock.json").read_text()),
            "inputs": {str(path.relative_to(root)): digest(path) for path in
                       [*sorted(p for p in source.iterdir() if p.is_file()), root / "gtx/gtx_probe_control.v", root / "zynq_ps_probe.v"]},
            "runner_sha256": digest(Path(__file__)), "packet_runner_sha256": digest(root / "test_ethernet.py"),
            "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
            "production_cells": cells, "packet_runs": checks,
            "board_profiles": board_profiles,
            "simulation_parameter_overrides": SIMULATION_PARAMETERS,
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
    """Select native tools and an ignored directory for reproducible artifacts."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path, default=Path(shutil.which("yosys") or "yosys"))
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "build/ethernet-recovery")
    args = parser.parse_args()
    run(args.yosys.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
