#!/usr/bin/env python3
"""Exercise bounded Ethernet frames through pinned LiteEth MAC and 1000BASE-X PCS."""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from ethernet.prepare import digest, environment
from ethernet.reference import check_capture, write_vectors
from prepare_te0715_boot import fetch

EXPECTED = [(14, 1), (59, 2), (60, 3), (61, 4), (1514, 5),
            (100, 8), (101, 9), (102, 10), (103, 11), (67, 24)]


def yosys_data(yosys: Path) -> Path:
    """Locate native or distro Yosys primitive simulation models."""
    config = yosys.with_name("yosys-config")
    return (Path(subprocess.check_output([str(config), "--datdir"], text=True).strip())
            if config.is_file() else yosys.parent.parent / "share/yosys")


def check_store(stage: Path) -> None:
    """Exercise admission races and long malformed frames in the handwritten RTL."""
    source = Path(__file__).resolve().parent / "ethernet"
    executable = stage / "frame-store.vvp"
    subprocess.run(["iverilog", "-g2012", "-s", "frame_store_tb", "-o", str(executable),
                    str(source / "frame_store.v"), str(source / "frame_store_tb.sv")], check=True)
    subprocess.run(["vvp", str(executable)], check=True, timeout=10)


def synthesize(yosys: Path, stage: Path, sources: list[Path], mapped: bool,
               top: str = "ethernet_packet_endpoint") -> Path:
    """Lower processes, optionally map XC7 cells, and reject undriven nets/loops."""
    output = stage / ("mapped.v" if mapped else "lowered.v")
    commands = ["read_verilog " + " ".join(f'"{path}"' for path in sources)]
    commands += ([f"synth_xilinx -family xc7 -top {top} -noiopad -flatten"]
                 if mapped else [f"hierarchy -top {top}", "proc", "opt"])
    commands += ["check -assert", "scc -expect 0", f'write_verilog -noattr "{output}"']
    if mapped:
        # Older distro Yosys treats quotes in tee's filename literally. The
        # process already runs in stage, so a plain basename is portable.
        commands += ["tee -o stat.json stat -json"]
    subprocess.run([str(yosys), "-Q", "-q", "-l", str(output.with_suffix(".log")),
                    "-p", "; ".join(commands)], check=True, cwd=stage, timeout=180)
    return output


def simulate(stage: Path, rtl: Path, models: Path | None, cache: Path,
             gearbox: tuple[int, int] | None = None, alignment_only: bool = False) -> str:
    """Check frame contents and wire coding, optionally through the ideal GTX model.

    Gearbox selects (initial bit offset, half-clock phase). Alignment-only runs
    negotiate and transfer one checked frame; normal runs exercise all faults.
    """
    root = Path(__file__).resolve().parent
    write_vectors(stage)
    sources = [root / "ethernet/packet_tb.sv", rtl]
    flags = []
    if gearbox is not None:
        sources.append(root / "ethernet/gearbox_packet_fixture.sv")
        flags.append("-DPACKET_ENDPOINT=gearbox_packet_fixture")
    if models:
        # cells_sim declares BRAM only as a black box. Exercise the actual mapped
        # ports/modes with AMD's functional model, as the DMA regression does.
        cells, count = re.subn(r"\bmodule RAMB36E1\b.*?\bendmodule\b", "",
                               models.read_text(), flags=re.S)
        if count != 1:
            raise ValueError("expected one RAMB36E1 black box")
        (stage / "cells.v").write_text(cells)
        sources.append(stage / "cells.v")
        cache.mkdir(parents=True, exist_ok=True)
        lock = json.loads((root / "ethernet/models.lock.json").read_text())
        sources += [fetch(pin, cache) for pin in lock.values()]
        flags += ["-s", "glbl"]
    executable = stage / "packet.vvp"
    subprocess.run(["iverilog", "-g2012", *flags, "-s", "packet_tb", "-o", str(executable),
                    *map(str, sources)], cwd=stage, check=True, timeout=60)
    options = ([] if gearbox is None else
               [f"+bit_offset={gearbox[0]}", f"+half_phase={gearbox[1]}"])
    if alignment_only:
        options.append("+alignment_only")
    process = subprocess.run(["vvp", str(executable), *options], cwd=stage, text=True, timeout=60,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    result = process.stdout
    (stage / "simulation.log").write_text(result)
    print(result.strip(), flush=True)
    process.check_returncode()
    check_capture(stage / "wire.hex", [(60, 3)] if alignment_only else EXPECTED)
    print("PASS: independent 8b/10b disparity, preamble, padding, FCS and inter-frame gap")
    return result


def run(yosys: Path, output: Path) -> dict:
    """Regenerate, simulate before/after mapping and measure production-timer logic."""
    started = time.monotonic()
    root = Path(__file__).resolve().parent
    source = root / "ethernet"
    output.mkdir(parents=True, exist_ok=True)
    # Every build has fresh outputs; downloaded source archives remain cached.
    with tempfile.TemporaryDirectory(prefix="packet-", dir=output) as directory:
        stage = Path(directory)
        check_store(stage)
        env = environment(output / "sources", stage / "sources")
        upstream_test, = (stage / "sources/liteeth").glob("*/test/test_pcs_1000basex.py")
        subprocess.run([sys.executable, "-S", str(upstream_test)], env=env, check=True, timeout=30)
        for name in ("simulation", "production"):
            destination = stage / name
            command = [sys.executable, "-S", str(source / "generate.py"), str(destination)]
            if name == "simulation":
                command.append("--simulation")
            subprocess.run(command, env=env, check=True, timeout=30)
            sources = [destination / "liteeth_packet_core.v", source / "frame_store.v", source / "packet_endpoint.v"]
            if name == "simulation":
                # Generated FSM blocks couple ready/valid sensitivity even where
                # the Boolean network is acyclic. Icarus can spin at zero time;
                # proc/opt eliminates this scheduling artifact before simulation.
                lowered = synthesize(yosys, destination, sources, False)
                simulate(destination, lowered, None, output / "sources")
                shutil.copyfile(destination / "simulation.log", destination / "lowered-simulation.log")
            mapped = synthesize(yosys, destination, sources, True)
            if name == "simulation":
                simulate(destination, mapped, yosys_data(yosys) / "xilinx/cells_sim.v", output / "sources")
        cells = json.loads((stage / "production/stat.json").read_text())["modules"]["\\ethernet_packet_endpoint"]["num_cells_by_type"]
        if cells.get("RAMB36E1") != 2:
            raise AssertionError(f"expected one BRAM per direction: {cells}")
        report = {
            "scope": "One full-duplex 1000BASE-X packet endpoint; no GTX, PS, host CDC, pins or timing qualification",
            "sources": json.loads((source / "sources.lock.json").read_text()),
            "inputs": {str(path.relative_to(root)): digest(path) for path in sorted(source.iterdir()) if path.is_file()},
            "runner_sha256": digest(Path(__file__)),
            "generated": {str(path.relative_to(stage)): digest(path) for path in sorted(stage.rglob("*"))
                          if path.is_file() and (path.name == "liteeth_packet_core.v" or path.suffix == ".init")},
            "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
            "production_cells": cells,
            "checks": ["19 pinned upstream PCS tests", "independent wire encoding/disparity/FCS/IFG", "consumer backpressure and two-slot overflow",
                       "TX/RX frame bounds", "bad preamble/FCS rejection", "full-duplex traffic with 100-ppm peer clock offset",
                       "link loss during traffic, committed RX preservation, renegotiation", "no undriven nets or combinational SCCs",
                       "identical frame scenarios before and after XC7 mapping with AMD BRAM model",
                       "admission/release races, 5000-byte overflow, sticky error, partial abort, flush",
                       "two RAMB36E1 retained with production negotiation timers"],
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "hardware_qualified": False,
        }
        (stage / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        candidate = output / "candidate"
        if candidate.exists():
            shutil.rmtree(candidate)
        stage.rename(candidate)
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    """Choose local tools and an ignored artifact/cache directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path, default=Path(shutil.which("yosys") or "yosys"))
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "build/ethernet")
    args = parser.parse_args()
    run(args.yosys.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
