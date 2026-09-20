#!/usr/bin/env python3
"""Record GTX routing evidence separately from assembly and hardware qualification."""

import argparse
import json
from pathlib import Path

from prepare import audit_database, digest


def report(database: Path, build: Path) -> dict:
    """Require the lane/reference sites in the routed design and retain its audit."""
    fasm = build / "probe.fasm"
    features = fasm.read_text()
    if "GTX_CHANNEL_1_X186Y17.GTXE2_CHANNEL.IN_USE" not in features:
        raise ValueError("routed FASM does not contain the expected GTX lane")
    if "GTX_COMMON_X186Y23.IBUFDS_GTE2_Y1.IN_USE" not in features:
        raise ValueError("routed FASM does not contain the expected reference-clock tile")
    timing = json.loads((build / "report.json").read_text())
    root = Path(__file__).resolve().parent.parent
    sources = [root / "zynq_ps_probe.v", root / "zynq_ps_probe_top.v",
               *sorted((root / "gtx").glob("*.v")), root / "gtx/te0715_gtx.xdc"]
    result = {"part": "xc7z030sbg485-1", "seed": 1, "synthesis_and_route": "passed",
              "bitstream_generated": False, "hardware_qualified": False,
              "toolchain_identity": (build / "chipdb.identity").read_text().strip(),
              "source_sha256": {str(path.relative_to(root)): digest(path.read_bytes())
                                for path in sources},
              "configuration": {"refclk_mhz": 125, "line_rate_gbps": 1.25,
                                "control_clock_mhz": 25, "user_clock_mhz": 62.5,
                                "loopback": "near-end PMA", "prbs": 7},
              "fmax_partial_only": timing["fmax"],
              "resources": {key: value["used"] for key, value in timing["utilization"].items()
                            if value["used"]},
              "sha256": {name: digest((build / name).read_bytes())
                         for name in ("probe.fasm", "netlist.json", "preparation.json")},
              "database_audit": audit_database(database, fasm)}
    (build / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Write a machine-readable result and a brief, qualified completion message."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("build", type=Path)
    args = parser.parse_args()
    result = report(args.database, args.build)
    print("GTX synthesis/route passed; no bitstream produced or hardware qualified.")
    audit = result["database_audit"]
    print(f"Missing frame mappings: {len(audit['missing_frame_mapping'])} used GTX tiles; "
          f"missing segbits: {', '.join(audit['missing_segbits_types'])}.")
    print(f"Full evidence: {args.build / 'result.json'}")


if __name__ == "__main__":
    main()
