#!/usr/bin/env python3
"""Compile and route the transparent TE0715 PS-DMA/Ethernet peer fixture."""

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

ROOT = Path(__file__).resolve().parent.parent
TOP = "te0715_ethernet_dma_top"


def sources(generated: Path) -> list[Path]:
    """Return the complete physical fixture source closure."""
    return [generated / "liteeth_packet_core.v", generated / "liteeth_pcs_gearbox.v",
            ROOT / "zynq_ps_probe.v", ROOT / "dma/zynq_dma_mailbox.v",
            ROOT / "gtx/te0715_gtx_channel.v", ROOT / "gtx/gtx_probe_control.v",
            *[ROOT / "ethernet" / (name + ".v") for name in
              ("frame_store", "clock_pair", "gtx_clocks", "dma_endpoint", "cdc_slot", "dma_packets",
               "te0715_ethernet_dma_top")]]


def inspect(path: Path) -> dict:
    """Require one PS, the proven external lane and all six packet/mailbox BRAMs."""
    module = json.loads(path.read_text())["modules"][TOP]
    cells = module["cells"]

    def by_type(kind: str) -> list[dict]:
        """Select preserved hard primitives from the flattened netlist."""
        return [cell for cell in cells.values() if cell["type"] == kind]

    def number(cell: dict, key: str) -> int:
        """Decode a binary Yosys primitive parameter."""
        return int(cell["parameters"][key], 2)

    lane, = by_type("GTXE2_CHANNEL")
    assert len(by_type("PS7")) == len(by_type("IBUFDS_GTE2")) == 1
    assert len(by_type("MMCME2_BASE")) == 2
    assert len(by_type("RAMB36E1")) == 2
    assert len(by_type("RAMB18E1")) == 4
    assert number(lane, "TX_DATA_WIDTH") == number(lane, "RX_DATA_WIDTH") == 20
    assert number(lane, "CPLL_FBDIV") == 5 and number(lane, "CPLL_FBDIV_45") == 4
    assert number(lane, "TXOUT_DIV") == number(lane, "RXOUT_DIV") == 4
    conn = lane["connections"]
    assert conn["LOOPBACK"] == ["0", "0", "0"]
    assert conn["TXPOLARITY"] == conn["RXPOLARITY"] == ["1"]
    for port in ("TX8B10BEN", "RX8B10BEN", "TXPRBSSEL", "RXPRBSSEL", "TXCHARISK"):
        assert set(conn[port]) == {"0"}, port
    return {"top": TOP, "external": True, "mailbox_identity": "0x484c454d",
            "mailbox_words": 380, "ps7": 1, "gtx_channels": 1, "mmcm": 2,
            "mac_ramb36": 2, "mailbox_and_cdc_ramb18": 4,
            "refclk_mhz": 125, "line_rate_gbps": 1.25,
            "control_clock_mhz": 25, "tx_clock_mhz": 125, "rx_clock_mhz": 125}


def build(yosys: Path, backend: Path, chipdb: Path, database: Path,
          output: Path, seed: int, source_cache: Path | None = None) -> dict:
    """Generate, map, route and independently check one fresh fixture candidate."""
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    started = time.monotonic()
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="sources-", dir=output) as directory:
        cache = source_cache or output / "sources"
        env = environment(cache, Path(directory))
        generated = output / "generated"
        for script in ("generate.py", "generate_gearbox.py"):
            subprocess.run([sys.executable, "-S", str(ROOT / "ethernet" / script), str(generated)],
                           env=env, check=True, timeout=30)
    closure = sources(generated)
    netlist = output / "netlist.json"
    commands = ["read_verilog " + " ".join(f'"{path}"' for path in closure),
                f"synth_xilinx -flatten -abc9 -family xc7 -top {TOP}",
                "check -assert", "scc -expect 0", f'write_json "{netlist}"',
                f'tee -o "{output / "stat.json"}" stat -json']
    subprocess.run([str(yosys), "-Q", "-q", "-l", str(output / "yosys.log"),
                    "-p", "; ".join(commands)], cwd=generated, check=True, timeout=240)
    profile = inspect(netlist)
    constraints = ROOT / "ethernet/te0715_ethernet.xdc"
    packed = output / "packed.json"
    with (output / "pack.log").open("w") as log:
        subprocess.run([str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
                        "--xdc", str(constraints), "--pack-only", "--write", str(packed)],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    fasm = output / "probe.fasm"
    routed = output / "routed.json"
    timing = output / "timing.json"
    with (output / "console.log").open("w") as log:
        subprocess.run([str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
                        "--xdc", str(constraints), "--fasm", str(fasm), "--report", str(timing),
                        "--write", str(routed), "--log", str(output / "nextpnr.log"),
                        "--freq", "125", "--seed", str(seed), "--router", "router2",
                        "--timing-allow-fail"], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=1200)
    log_text = (output / "nextpnr.log").read_text()
    if "failed to find a route using dedicated resources" in log_text:
        raise ValueError("clock routing fell back to fabric")
    lut_check = check_luts(packed, routed, fasm, database / "xc7z030/tilegrid.json")
    partial_timing = json.loads(timing.read_text())
    report = {"profile": profile, "seed": seed, "router": "router2",
              "synthesis_and_route": "passed", "hardware_qualified": False,
              "timing_qualified": False,
              "timing_limits": "Partial native model; no BRAM sequential or CDC settling signoff.",
              "modeled_targets_met": all(value["achieved"] >= value["constraint"]
                                         for value in partial_timing["fmax"].values()),
              "partial_timing": partial_timing, "lut_check": lut_check,
              "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
              "backend_sha256": digest(backend), "chipdb_sha256": digest(chipdb),
              "database_audit": audit_database(database, fasm),
              "inputs": {str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else path.name: digest(path)
                         for path in [Path(__file__), *closure,
                                     generated / "liteeth_packet_core_mem_6b5b.init", constraints]},
              "netlist_sha256": digest(netlist), "fasm_sha256": digest(fasm),
              "synthesis_cells": json.loads((output / "stat.json").read_text())["modules"]["\\"+TOP]["num_cells_by_type"],
              "elapsed_seconds": round(time.monotonic()-started,2)}
    (output / "result.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))
    return report


def main() -> None:
    """Select explicit, retained native tools and a new output directory."""
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("yosys","nextpnr","chipdb","database","output"):
        parser.add_argument("--"+name,type=Path,required=True)
    parser.add_argument("--seed",type=int,default=1)
    parser.add_argument("--source-cache",type=Path,
                        help="existing pinned LiteEth/LiteX/Migen archive directory")
    args=parser.parse_args()
    if args.seed<1:
        parser.error("seed must be positive")
    build(args.yosys.resolve(),args.nextpnr.resolve(),args.chipdb.resolve(),
          args.database.resolve(),args.output.resolve(),args.seed,
          args.source_cache.resolve() if args.source_cache else None)


if __name__ == "__main__":
    main()
