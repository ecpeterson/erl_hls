#!/usr/bin/env python3
"""Reject the Yosys SDP72 parity-pin typo and its mapped-netlist signature."""

import argparse
import json
import re
from pathlib import Path


CORRECT = r"PORT_W_WIDTH\s*==\s*72\s*\?\s*DIP\[7:4\]\s*:\s*DIP\[3:0\]"
BROKEN = r"PORT_W_WIDTH\s*==\s*71\s*\?\s*DIP\[7:4\]\s*:\s*DIP\[3:0\]"


def parameter_int(value: object) -> int:
    """Decode a Yosys integer parameter represented as bits or a number."""
    if isinstance(value, int):
        return value
    text = str(value)
    return int(text, 2) if text and set(text) <= {"0", "1"} else int(text, 0)


def audit_library(text: str) -> dict:
    """Require the Series-7 RAMB36 map to select upper parity at width 72."""
    if re.search(BROKEN, text):
        raise ValueError("Yosys SDP72 parity typo: PORT_W_WIDTH compares with 71")
    if not re.search(CORRECT, text):
        raise ValueError("Yosys SDP72 upper-parity mapping was not recognized")
    return {"sdp72_upper_parity_select": 72, "passed": True}


def audit_probe_netlist(netlist: dict) -> dict:
    """Require every SDP72 cell in the lane-distinct probe to use distinct parity nets."""
    checked = []
    copied = []
    for module in netlist.get("modules", {}).values():
        for name, cell in module.get("cells", {}).items():
            params = cell.get("parameters", {})
            if (cell.get("type") != "RAMB36E1" or params.get("RAM_MODE") != "SDP" or
                    parameter_int(params.get("READ_WIDTH_A", 0)) != 72 or
                    parameter_int(params.get("WRITE_WIDTH_B", 0)) != 72):
                continue
            checked.append(name)
            ports = cell.get("connections", {})
            if ports.get("DIPADIP") == ports.get("DIPBDIP"):
                copied.append(name)
    if not checked:
        raise ValueError("no synthesized SDP72 RAMB36E1 cells")
    if copied:
        raise ValueError(f"SDP72 upper parity copies lower parity: {copied}")
    return {"cells": len(checked), "distinct_parity_cells": len(checked), "passed": True}


def main() -> None:
    """Audit one Yosys mapping library and, optionally, a lane-distinct probe netlist."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--probe-netlist", type=Path)
    args = parser.parse_args()
    result = {"library": audit_library(args.library.read_text())}
    if args.probe_netlist:
        result["probe_netlist"] = audit_probe_netlist(
            json.loads(args.probe_netlist.read_text()))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
