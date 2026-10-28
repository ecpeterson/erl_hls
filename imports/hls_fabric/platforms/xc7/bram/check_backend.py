#!/usr/bin/env python3
"""Audit native FASM width configuration for 72-bit SDP RAMB36E1 cells."""

import argparse
import json
from pathlib import Path


def parameter_int(value: object) -> int:
    """Decode a nextpnr/Yosys integer parameter represented as bits or a number."""
    if isinstance(value, int):
        return value
    text = str(value)
    return int(text, 2) if text and set(text) <= {"0", "1"} else int(text, 0)


def sdp72_cells(routed: dict, tilegrid: dict) -> dict[str, str]:
    """Map every routed 72-bit SDP RAMB36 cell name to its configuration tile."""
    site_tiles = {site: tile for tile, record in tilegrid.items()
                  for site in record.get("sites", {})}
    result = {}
    for module in routed.get("modules", {}).values():
        for name, cell in module.get("cells", {}).items():
            params = cell.get("parameters", {})
            if (cell.get("type") != "RAMB36E1_RAMB36E1" or
                    params.get("RAM_MODE") != "SDP" or
                    parameter_int(params.get("READ_WIDTH_A", 0)) != 72 or
                    parameter_int(params.get("WRITE_WIDTH_B", 0)) != 72):
                continue
            site = cell.get("attributes", {}).get("NEXTPNR_BEL", "").split("/", 1)[0]
            if site not in site_tiles:
                raise ValueError(f"missing tile for {name}: {site}")
            result[name] = site_tiles[site]
    if not result:
        raise ValueError("no routed 72-bit SDP RAMB36E1 cells")
    return result


def enabled_features(text: str) -> set[str]:
    """Return the enabled scalar feature names from canonical or ordinary FASM."""
    return {line.split()[0] for raw in text.splitlines()
            if (line := raw.split("#", 1)[0].strip()) and "=" not in line}


def audit(routed: dict, tilegrid: dict, fasm: str) -> dict:
    """Require the vendor-matched width markers for every routed SDP72 RAMB36."""
    cells = sdp72_cells(routed, tilegrid)
    features = enabled_features(fasm)
    suffixes = {
        f"RAMB18_Y{half}.{feature}"
        for half in (0, 1)
        for feature in (
            "IN_USE", "READ_WIDTH_A_18", "READ_WIDTH_B_18",
            "SDP_READ_WIDTH_36", "SDP_WRITE_WIDTH_36",
            "WRITE_WIDTH_A_18", "WRITE_WIDTH_B_18")
    }
    missing = sorted(f"{tile}.{suffix}" for tile in set(cells.values())
                     for suffix in suffixes if f"{tile}.{suffix}" not in features)
    if missing:
        raise ValueError(f"incomplete SDP72 width configuration: {missing}")
    return {"cells": len(cells), "tiles": sorted(set(cells.values())),
            "required_features_per_tile": len(suffixes), "passed": True,
            "hardware_qualified": False}


def main() -> None:
    """Load a routed design, tile grid and FASM, then print the audit result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--routed", required=True, type=Path)
    parser.add_argument("--tilegrid", required=True, type=Path)
    parser.add_argument("--fasm", required=True, type=Path)
    args = parser.parse_args()
    result = audit(json.loads(args.routed.read_text()),
                   json.loads(args.tilegrid.read_text()), args.fasm.read_text())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
