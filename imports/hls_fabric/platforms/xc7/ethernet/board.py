#!/usr/bin/env python3
"""Compile, inspect and optionally route a TE0715 Ethernet diagnostic candidate."""

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from ethernet.prepare import digest, environment
from gtx.prepare import audit_database
from lut_legality.check import check as check_luts


def board_sources(root: Path, generated: Path) -> list[Path]:
    """Return the complete probe source closure, excluding testbench models."""
    return [generated / "liteeth_packet_core.v", generated / "liteeth_pcs_gearbox.v",
            root / "zynq_ps_probe.v", root / "zynq_ps_probe_top.v",
            root / "gtx/te0715_gtx_channel.v", root / "gtx/gtx_probe_control.v",
            *[root / "ethernet" / (name + ".v") for name in
              ("frame_store", "packet_endpoint", "gtx_packet_endpoint", "clock_pair",
               "supervised_endpoint", "gtx_clocks", "snapshot", "probe_traffic", "te0715_ethernet_top")]]


def inspect_netlist(path: Path, external: bool) -> dict:
    """Require the lane profile, MMCM ratios and user-clock/data connections."""
    module = json.loads(path.read_text())["modules"]["te0715_ethernet_top"]
    cells = module["cells"]
    def by_type(kind: str) -> list[dict]:
        """Select preserved hard primitives from the flattened netlist."""
        return [cell for cell in cells.values() if cell["type"] == kind]
    def number(cell: dict, key: str) -> int:
        """Decode a Yosys numeric parameter without mistaking binary for decimal."""
        return int(cell["parameters"][key], 2)
    lane, = by_type("GTXE2_CHANNEL")
    assert len(by_type("PS7")) == len(by_type("IBUFDS_GTE2")) == 1
    assert len(by_type("RAMB36E1")) == 2
    assert number(lane, "TX_DATA_WIDTH") == number(lane, "RX_DATA_WIDTH") == 20
    assert number(lane, "CPLL_FBDIV") == 5 and number(lane, "CPLL_FBDIV_45") == 4
    assert number(lane, "TXOUT_DIV") == number(lane, "RXOUT_DIV") == 4
    conn = lane["connections"]
    for port in ("TX8B10BEN", "RX8B10BEN", "TXPRBSSEL", "RXPRBSSEL", "TXCHARISK"):
        assert set(conn[port]) == {"0"}, port
    assert conn["LOOPBACK"] == (["0", "0", "0"] if external else ["0", "1", "0"])
    assert conn["TXPOLARITY"] == conn["RXPOLARITY"] == ["1" if external else "0"]
    for port in ("TXDATA", "TXCHARDISPVAL", "TXCHARDISPMODE"):
        width = 16 if port == "TXDATA" else 2
        assert all(isinstance(bit, int) for bit in conn[port][:width]), port
        assert set(conn[port][width:]) == {"0"}, port
    clocks = by_type("MMCME2_BASE")
    assert len(clocks) == 2, [c["type"] for c in cells.values() if "MMCM" in c["type"]]
    # Yosys represents real-valued primitive parameters as decimal text.
    for cell in clocks:
        p = cell["parameters"]
        assert float(p["CLKFBOUT_MULT_F"]) == 16.0
        assert float(p["CLKOUT0_DIVIDE_F"]) == 8.0
        assert number(cell, "CLKOUT1_DIVIDE") == 16 and number(cell, "DIVCLK_DIVIDE") == 1
    for direction in ("tx", "rx"):
        full = module["netnames"][direction + "_clock"]["bits"]
        half = module["netnames"][direction + "_half_clock"]["bits"]
        assert full != half and conn[direction.upper()+"USRCLK"] == half
        assert conn[direction.upper()+"USRCLK2"] == half
        buffers = {tuple(c["connections"]["O"]): c["connections"]["I"] for c in by_type("BUFG")}
        generator, = [c["connections"] for c in clocks if c["connections"]["CLKOUT0"] == buffers[tuple(full)]]
        assert generator["CLKOUT1"] == buffers[tuple(half)]
        assert buffers[tuple(generator["CLKIN1"])] == conn[direction.upper()+"OUTCLK"]
        assert buffers[tuple(generator["CLKFBIN"])] == generator["CLKFBOUT"]
    return {"external": external, "lane": "GTXE2_CHANNEL_X0Y1", "mmcm_count": 2,
            "frame_store_ramb36": 2, "refclk_mhz": 125, "line_rate_gbps": 1.25,
            "full_clock_mhz": 125, "half_clock_mhz": 62.5}


def map_board(yosys: Path, root: Path, generated: Path, stage: Path, external: bool) -> dict:
    """Map and structurally check one complete lane profile without native routing."""
    stage.mkdir(parents=True, exist_ok=True)
    sources = board_sources(root, generated)
    netlist = stage / "netlist.json"
    commands = ["read_verilog " + " ".join(f'"{p}"' for p in sources),
                f"chparam -set EXTERNAL {int(external)} te0715_ethernet_top",
                "synth_xilinx -flatten -abc9 -family xc7 -top te0715_ethernet_top", "check -assert", "scc -expect 0",
                f'write_json "{netlist}"', "tee -o stat.json stat -json"]
    subprocess.run([str(yosys), "-Q", "-q", "-l", str(stage / "yosys.log"), "-p", "; ".join(commands)],
                   cwd=stage, check=True, timeout=180)
    profile = inspect_netlist(netlist, external)
    return profile


def build(yosys: Path, backend: Path, chipdb: Path, database: Path, output: Path,
          external: bool, route: bool) -> dict:
    """Retain native compilation evidence without ever assembling a bitstream."""
    root = Path(__file__).resolve().parent.parent
    started = time.monotonic()
    output.mkdir(parents=True, exist_ok=True)
    # Separate immutable archive cache from fresh source extraction.
    with tempfile.TemporaryDirectory(prefix="sources-", dir=output) as directory:
        env = environment(output / "sources", Path(directory))
        generated = output / "generated"
        for script in ("generate.py", "generate_gearbox.py"):
            subprocess.run([sys.executable, "-S", str(root / "ethernet" / script), str(generated)],
                           env=env, check=True, timeout=30)
    stage = output / ("external" if external else "loopback")
    stage.mkdir(exist_ok=True)
    sources = board_sources(root, generated)
    netlist = stage / "netlist.json"
    profile = map_board(yosys, root, generated, stage, external)
    fasm = stage / "probe.fasm"
    for name in ("probe.fasm", "timing.json", "result.json"):
        (stage / name).unlink(missing_ok=True)
    constraints = root / "ethernet/te0715_ethernet.xdc"
    lut_check = None
    if route:
        with (stage / "pack.log").open("w") as log:
            subprocess.run([str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
                            "--xdc", str(constraints), "--pack-only", "--write", str(stage / "packed.json")],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
        with (stage / "console.log").open("w") as log:
            subprocess.run([str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
                            "--xdc", str(constraints), "--fasm", str(fasm), "--report", str(stage / "timing.json"),
                            "--write", str(stage / "routed.json"), "--log", str(stage / "nextpnr.log"),
                            "--freq", "125", "--seed", "1", "--router", "router2", "--timing-allow-fail"],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
        # A completed general route can conceal a failed dedicated clock route.
        # Refuse that candidate instead of interpreting its MHz as useful evidence.
        log_text = (stage / "nextpnr.log").read_text()
        if "failed to find a route using dedicated resources" in log_text:
            raise ValueError("clock routing fell back to fabric; inspect nextpnr.log")
        lut_check = check_luts(stage / "packed.json", stage / "routed.json", fasm,
                              database / "xc7z030/tilegrid.json")
    report = {"profile": profile, "routed": route, "bitstream_generated": False, "hardware_qualified": False,
              "runner_sha256": digest(Path(__file__)), "lut_checker_sha256": digest(root / "lut_legality/check.py"),
              "lut_check": lut_check, "seed": 1, "router": "router2",
              "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
              "backend_sha256": digest(backend), "chipdb_sha256": digest(chipdb),
              "inputs": {str(p.relative_to(root)) if p.is_relative_to(root) else p.name: digest(p)
                         for p in [*sources, constraints]},
              "netlist_sha256": digest(netlist), "database_audit": audit_database(database, fasm if route else None),
              "synthesis_cells": json.loads((stage / "stat.json").read_text())["modules"]["\\te0715_ethernet_top"]["num_cells_by_type"]}
    if route:
        report["fasm_sha256"] = digest(fasm)
        report["partial_timing"] = json.loads((stage / "timing.json").read_text())
        report["modeled_targets_met"] = all(v["achieved"] >= v["constraint"] for v in report["partial_timing"]["fmax"].values())
        report["timing_coverage"] = "Partial only: missing BRAM sequential timing, calibrated FF delays and generated-clock/CDC constraints; not a safe-clock estimate"
    report["elapsed_seconds"] = round(time.monotonic() - started, 2)
    (stage / "result.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    """Choose an explicit tool/database cache and internal or external lane profile."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("yosys", "nextpnr", "chipdb", "database", "output"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--external", action="store_true")
    parser.add_argument("--no-route", action="store_true")
    args = parser.parse_args()
    build(args.yosys.resolve(), args.nextpnr.resolve(), args.chipdb.resolve(), args.database.resolve(),
          args.output.resolve(), args.external, not args.no_route)


if __name__ == "__main__":
    main()
