#!/usr/bin/env python3
"""Record qualified scope for the routed 1000BASE-X PCS-boundary probe."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from gtx.prepare import audit_database, digest


def report(database: Path, build: Path, seed: int = 1) -> dict:
    """Require hard resources, modeled clock targets and a complete source closure."""
    features = (build / "probe.fasm").read_text()
    for required in ("GTX_CHANNEL_1_X186Y17.GTXE2_CHANNEL.IN_USE",
                     "GTX_COMMON_X186Y23.IBUFDS_GTE2_Y1.IN_USE"):
        if required not in features:
            raise ValueError(f"routed FASM lacks selected GTX resource: {required}")
    timing = json.loads((build / "report.json").read_text())
    for name, clock in timing["fmax"].items():
        if clock["achieved"] < clock["constraint"]:
            raise ValueError(f"modeled timing failed for {name}: {clock}")
    generated = build / "generated"
    sources = [ROOT / "zynq_ps_probe.v", ROOT / "zynq_ps_probe_top.v",
               ROOT / "gtx/gtx_probe_control.v", ROOT / "gtx/te0715_gtx_channel.v",
               ROOT / "ethernet/clock_pair.v", ROOT / "ethernet/gtx_clocks.v",
               ROOT / "ethernet/snapshot.v", ROOT / "ethernet/pcs_probe_sample.v",
               ROOT / "ethernet/te0715_pcs_probe_top.v", ROOT / "ethernet/generate_pcs_probe.py",
               ROOT / "ethernet/generate_gearbox.py", ROOT / "ethernet/prepare_pcs_probe.py",
               ROOT / "ethernet/prepare.py", ROOT / "ethernet/te0715_ethernet.xdc"]
    generated_sources = [generated / "liteeth_pcs_probe.v",
                         generated / "liteeth_pcs_probe_mem_6b5b.init",
                         generated / "liteeth_pcs_gearbox.v"]
    result = {
        "part": "xc7z030sbg485-1", "seed": seed,
        "profile": "pcs-external", "synthesis_and_route": "passed",
        "bitstream_generated": False, "hardware_validated": False,
        "configuration": {"refclk_mhz": 125, "line_rate_gbps": 1.25,
                          "full_clock_mhz": 125, "half_clock_mhz": 62.5,
                          "loopback": "none", "rx_polarity": 1, "tx_polarity": 1,
                          "hard_8b10b": False, "pcs": "LiteEth 1000BASE-X"},
        "fmax_partial_only": timing["fmax"],
        "resources": {key: value["used"] for key, value in timing["utilization"].items()
                      if value["used"]},
        "source_sha256": {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in sources},
        "generated_sha256": {path.name: digest(path.read_bytes()) for path in generated_sources},
        "artifacts_sha256": {name: digest((build / name).read_bytes())
                             for name in ("probe.fasm", "netlist.json", "preparation.json")},
        "database_audit": audit_database(database, build / "probe.fasm"),
        "limits": ("Native modeled paths pass their stated constraints. PS/GTX timing, hard-GTX "
                   "analog behavior, CDC settling, link operation and BER require hardware evidence."),
    }
    (build / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Write one machine-readable report for an explicit database/build pair."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("build", type=Path)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    print(json.dumps(report(args.database.resolve(), args.build.resolve(), args.seed), indent=2))


if __name__ == "__main__":
    main()
