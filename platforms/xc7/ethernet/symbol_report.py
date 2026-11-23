#!/usr/bin/env python3
"""Record qualified scope for the routed external raw-symbol diagnostic."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from gtx.prepare import audit_database, digest


def report(database: Path, build: Path) -> dict:
    """Require the selected GTX sites and retain modeled timing/resource evidence."""
    features = (build / "probe.fasm").read_text()
    for required in ("GTX_CHANNEL_1_X186Y17.GTXE2_CHANNEL.IN_USE",
                     "GTX_COMMON_X186Y23.IBUFDS_GTE2_Y1.IN_USE"):
        if required not in features:
            raise ValueError(f"routed FASM lacks selected GTX resource: {required}")
    timing = json.loads((build / "report.json").read_text())
    for name, clock in timing["fmax"].items():
        if clock["achieved"] < clock["constraint"]:
            raise ValueError(f"modeled timing failed for {name}: {clock}")
    sources = [ROOT / "zynq_ps_probe.v", ROOT / "zynq_ps_probe_top.v",
               ROOT / "gtx/gtx_probe_control.v", ROOT / "gtx/gtx_probe_sample.v",
               ROOT / "gtx/te0715_gtx_channel.v", ROOT / "gtx/te0715_gtx.xdc",
               ROOT / "ethernet/symbol_probe_sample.v", ROOT / "ethernet/te0715_symbol_top.v"]
    result = {
        "part": "xc7z030sbg485-1", "seed": 1,
        "profile": "symbol-external", "synthesis_and_route": "passed",
        "bitstream_generated": False, "hardware_validated": False,
        "configuration": {"refclk_mhz": 125, "line_rate_gbps": 1.25,
                          "control_clock_mhz": 25, "user_clock_mhz": 62.5,
                          "loopback": "none", "rx_polarity": 1, "tx_polarity": 1,
                          "pattern": "{K28.5-,K28.5+}", "hard_8b10b": False},
        "fmax_partial_only": timing["fmax"],
        "resources": {key: value["used"] for key, value in timing["utilization"].items()
                      if value["used"]},
        "source_sha256": {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in sources},
        "artifacts_sha256": {name: digest((build / name).read_bytes())
                             for name in ("probe.fasm", "netlist.json", "preparation.json")},
        "database_audit": audit_database(database, build / "probe.fasm"),
        "limits": "Modeled routed paths pass; PS/GTX timing and analog behavior remain outside the native timing model.",
    }
    (build / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Write one machine-readable route report for an explicit database/build pair."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("build", type=Path)
    args = parser.parse_args()
    result = report(args.database.resolve(), args.build.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
