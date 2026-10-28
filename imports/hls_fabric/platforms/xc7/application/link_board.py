#!/usr/bin/env python3
"""Map and route one role of the TE0715 application-link fixture."""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from backend_paths import application_directory

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from ethernet.prepare import digest
from gtx.prepare import audit_database
from lut_legality.check import check as check_luts

ROOT = Path(__file__).resolve().parent.parent
TOP = "te0715_partition_link_top"


def sources(generated: Path, application: Path, ram_wrapper: Path | None = None) -> list[Path]:
    """Return the complete role-specific physical source closure."""
    public = application_directory("erl_hls", "default")
    debug = public / "priv/rtl/debug"
    fabric = public / "priv/rtl/fabric"
    routed = ROOT / "build/routed-dma/rtl"
    return [
        generated / "liteeth_packet_core.v",
        generated / "liteeth_pcs_gearbox.v",
        application,
        *([ram_wrapper] if ram_wrapper else []),
        *([public / "priv/rtl/hls_1r1w_ram.v"] if ram_wrapper else []),
        routed / "hls_debug_observer.v",
        routed / "hls_debug_server.v",
        debug / "hls_debug_tap.v",
        debug / "hls_debug_monitor.v",
        debug / "hls_trace_store.v",
        fabric / "hls_fabric_ingress.v",
        fabric / "hls_fabric_egress.v",
        ROOT / "zynq_ps_probe.v",
        ROOT / "dma/zynq_dma_mailbox.v",
        ROOT / "dma/zynq_dma_pair.v",
        ROOT / "gtx/te0715_gtx_channel.v",
        ROOT / "gtx/gtx_probe_control.v",
        *[ROOT / "ethernet" / f"{name}.v" for name in (
            "frame_store", "clock_pair", "gtx_clocks", "dma_endpoint", "cdc_slot",
            "dma_packets")],
        ROOT / "application/partition_link_packets.v",
        ROOT / "application/partition_packet_probe.v",
        ROOT / "application/te0715_partition_link_top.v",
    ]


def inspect(path: Path, role: str, private_link_debug: bool, stage_debug: bool,
            packet_debug: bool) -> dict:
    """Require the expected hard physical boundary in the flattened netlist."""
    module = json.loads(path.read_text())["modules"][TOP]
    cells = module["cells"]

    def by_type(kind: str) -> list[dict]:
        """Select preserved hard primitives from the flattened netlist."""
        return [cell for cell in cells.values() if cell["type"] == kind]

    def number(cell: dict, key: str) -> int:
        """Decode one binary Yosys primitive parameter."""
        return int(cell["parameters"][key], 2)

    lane, = by_type("GTXE2_CHANNEL")
    assert len(by_type("PS7")) == len(by_type("IBUFDS_GTE2")) == 1
    assert len(by_type("MMCME2_BASE")) == 2
    assert number(lane, "TX_DATA_WIDTH") == number(lane, "RX_DATA_WIDTH") == 20
    assert number(lane, "CPLL_FBDIV") == 5 and number(lane, "CPLL_FBDIV_45") == 4
    assert number(lane, "TXOUT_DIV") == number(lane, "RXOUT_DIV") == 4
    connection = lane["connections"]
    assert connection["LOOPBACK"] == ["0", "0", "0"]
    assert connection["TXPOLARITY"] == connection["RXPOLARITY"] == ["1"]
    for port in ("TX8B10BEN", "RX8B10BEN", "TXPRBSSEL", "RXPRBSSEL", "TXCHARISK"):
        assert set(connection[port]) == {"0"}, port
    return {
        "top": TOP,
        "role": role,
        "ps7": 1,
        "gtx_channels": 1,
        "mmcm": 2,
        "ramb36": len(by_type("RAMB36E1")),
        "ramb18": len(by_type("RAMB18E1")),
        "refclk_mhz": 125,
        "line_rate_gbps": 1.25,
        "application_clock_mhz": 25,
        "tx_clock_mhz": 125,
        "rx_clock_mhz": 125,
        "debug_observation": [
            "private-link" if private_link_debug else "host-application",
            *(["scheduler-memory-and-graph-output"] if stage_debug else []),
            *(["private-packet-boundaries"] if packet_debug else []),
        ],
    }


def build(yosys: Path, backend: Path, chipdb: Path, database: Path, generated: Path,
          application: Path, role: str, output: Path, seed: int,
          application_stem: str | None = None, ram_wrapper: Path | None = None,
          synthesis_only: bool = False, private_link_debug: bool = False,
          stage_debug: bool = False, packet_debug: bool = False,
          normalize_buffers: bool = False) -> dict:
    """Synthesize and pack one role; unless requested otherwise, route and audit it."""
    if role not in ("a", "b"):
        raise ValueError("role must be a or b")
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    output.mkdir(parents=True)
    started = time.monotonic()
    if (application_stem is None) != (ram_wrapper is None):
        raise ValueError("application stem and RAM wrapper must be supplied together")
    if stage_debug and ram_wrapper is None:
        raise ValueError("stage debug requires an external scheduler RAM wrapper")
    if packet_debug and ram_wrapper is None:
        raise ValueError("packet debug requires the qualified external scheduler RAM wrapper")
    if stage_debug and packet_debug:
        raise ValueError("stage and packet debug use the same endpoint")
    closure = sources(generated, application, ram_wrapper)
    stem = application_stem or f"link_application_{role}"
    role_top = f"__{stem}__Top_0_next"
    netlist = output / "netlist.json"
    renames = [f"rename {role_top} {stem}"]
    if ram_wrapper:
        renames.append(f"rename {stem}_ram link_application")
    else:
        renames.append(f"rename {stem} link_application")
    commands = [
        "read_verilog -sv " + ("-DHLS_SCHEDULER_PROBE " if stage_debug else
                               "-DHLS_PACKET_PROBE " if packet_debug else "") +
            " ".join(f'"{path}"' for path in closure),
        *renames,
        f"chparam -set ROLE {1 if role == 'a' else 2} {TOP}",
        f"chparam -set DEBUG_PRIVATE_LINK {int(private_link_debug)} {TOP}",
        f"synth_xilinx -flatten -abc9 -family xc7 -top {TOP}",
        *(["bufnorm -conn"] if normalize_buffers else []),
        "check -assert",
        "scc -expect 0",
        f'write_json "{netlist}"',
        f'tee -o "{output / "stat.json"}" stat -json',
    ]
    subprocess.run(
        [str(yosys), "-Q", "-q", "-l", str(output / "yosys.log"),
         "-p", "; ".join(commands)],
        cwd=generated, check=True, timeout=600,
    )
    profile = inspect(netlist, role, private_link_debug, stage_debug, packet_debug)
    constraints = ROOT / "ethernet/te0715_ethernet.xdc"
    packed = output / "packed.json"
    with (output / "pack.log").open("w") as log:
        subprocess.run(
            [str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
             "--xdc", str(constraints), "--pack-only", "--write", str(packed)],
            stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300,
        )
    common = {
        "profile": profile | {"application_stem": stem,
                              "external_application_ram": bool(ram_wrapper)},
        "seed": seed,
        "router": "router2",
        "hardware_qualified": False,
        "timing_qualified": False,
        "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
        "backend_sha256": digest(backend),
        "chipdb_sha256": digest(chipdb),
        "inputs": {
            str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): digest(path)
            for path in [Path(__file__), *closure,
                         generated / "liteeth_packet_core_mem_6b5b.init", constraints]
        },
        "netlist_sha256": digest(netlist),
        "packed_sha256": digest(packed),
        "synthesis_cells": json.loads((output / "stat.json").read_text())[
            "modules"]["\\" + TOP]["num_cells_by_type"],
    }
    if synthesis_only:
        report = common | {
            "synthesis_and_pack": "passed",
            "route_attempted": False,
            "timing_limits": "No placement, routing or timing analysis was requested.",
            "elapsed_seconds": round(time.monotonic() - started, 2),
        }
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return report
    fasm = output / "probe.fasm"
    routed = output / "routed.json"
    timing = output / "timing.json"
    with (output / "console.log").open("w") as log:
        subprocess.run(
            [str(backend), "--chipdb", str(chipdb), "--json", str(netlist),
             "--xdc", str(constraints), "--fasm", str(fasm), "--report", str(timing),
             "--write", str(routed), "--log", str(output / "nextpnr.log"),
             "--freq", "125", "--seed", str(seed), "--router", "router2",
             "--timing-allow-fail"],
            stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800,
        )
    log_text = (output / "nextpnr.log").read_text()
    if "failed to find a route using dedicated resources" in log_text:
        raise ValueError("clock routing fell back to fabric")
    lut_check = check_luts(packed, routed, fasm, database / "xc7z030/tilegrid.json")
    partial_timing = json.loads(timing.read_text())
    report = common | {
        "synthesis_and_route": "passed",
        "timing_limits": "Partial native model; no BRAM sequential or CDC settling signoff.",
        "modeled_targets_met": all(value["achieved"] >= value["constraint"]
                                     for value in partial_timing["fmax"].values()),
        "partial_timing": partial_timing,
        "lut_check": lut_check,
        "database_audit": audit_database(database, fasm),
        "fasm_sha256": digest(fasm),
        "elapsed_seconds": round(time.monotonic() - started, 2),
    }
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    """Select retained tools, a generated role and a fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("yosys", "nextpnr", "chipdb", "database", "generated",
                 "application", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--role", choices=("a", "b"), required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--application-stem")
    parser.add_argument("--ram-wrapper", type=Path)
    parser.add_argument("--synthesis-only", action="store_true")
    parser.add_argument("--private-link-debug", action="store_true")
    parser.add_argument("--stage-debug", action="store_true")
    parser.add_argument("--packet-debug", action="store_true")
    parser.add_argument("--normalize-buffers", action="store_true",
                        help="remove explicit $buf cells emitted by newer Yosys builds")
    args = parser.parse_args()
    if args.seed < 1:
        parser.error("seed must be positive")
    build(args.yosys.resolve(), args.nextpnr.resolve(), args.chipdb.resolve(),
          args.database.resolve(), args.generated.resolve(), args.application.resolve(),
          args.role, args.output.resolve(), args.seed, args.application_stem,
          args.ram_wrapper.resolve() if args.ram_wrapper else None,
          args.synthesis_only, args.private_link_debug, args.stage_debug,
          args.packet_debug,
          args.normalize_buffers)


if __name__ == "__main__":
    main()
