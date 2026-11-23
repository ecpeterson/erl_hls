"""Check explicit timing-endpoint requirements against a live nextpnr export."""

import argparse
import json
from pathlib import Path
import re
from typing import Any


def check(data: dict[str, Any], requirements: list[dict[str, str]]) -> dict[str, Any]:
    """Report absent/ignored endpoints; passing checks do not prove arc completeness.

    Each requirement selects full cell-type and port-name regexes and requires
    one timing class. Register endpoints must also resolve a connected clock.
    A selector matching no placed ports is a failed requirement, not a pass.
    """
    if data.get("schema") != 1 or not isinstance(data.get("cells"), dict):
        raise ValueError("unsupported timing coverage export")
    if not requirements:
        raise ValueError("at least one endpoint requirement is required")
    rows = []
    for requirement in requirements:
        expected = requirement["class"]
        if expected not in {"register_input", "register_output", "clock_input", "comb_input", "comb_output"}:
            raise ValueError(f"unsupported required class: {expected}")
        matched, failures = 0, []
        for name, cell in sorted(data["cells"].items()):
            if not re.fullmatch(requirement["type"], cell["type"]):
                continue
            for port, info in sorted(cell["ports"].items()):
                if not re.fullmatch(requirement["port"], port):
                    continue
                matched += 1
                reason = None
                if not cell["placed"]:
                    reason = "unplaced cell"
                elif info["class"] != expected:
                    reason = "class=" + info["class"]
                elif expected.startswith("register_"):
                    clocks = info["clocks"]
                    if not clocks or any(clock["port"] not in cell["ports"] or
                                         cell["ports"][clock["port"]]["class"] != "clock_input"
                                         for clock in clocks):
                        reason = "missing or unclassified clock"
                if reason:
                    failures.append({"cell": name, "port": port, "reason": reason})
        rows.append({"requirement": requirement, "matched": matched, "failed": len(failures),
                     "passed": matched > 0 and not failures, "failures": failures})
    return {"endpoint_requirements_met": all(row["passed"] for row in rows),
            "design_wide_clock_validated": False, "checks": rows}


def requirements(mode: str) -> list[dict[str, str]]:
    """Return necessary endpoint checks for the selected single-clock fixture."""
    rows = [{"type": "SLICE_FFX", "port": "Q", "class": "register_output"},
            {"type": "SLICE_FFX", "port": "D", "class": "register_input"}]
    if mode in {"ram", "ram_registered", "ram_dsp"}:
        rows += [{"type": "RAMB(?:18|36)E1_RAMB(?:18|36)E1", "port": "DO(?:ADO|BDO)[0-9]+",
                  "class": "register_output"},
                 {"type": "RAMB(?:18|36)E1_RAMB(?:18|36)E1", "port": "(?:DIADI|DIBDI)[0-9]+",
                  "class": "register_input"}]
    if mode in {"dsp", "ram_dsp", "dsp_registered"}:
        registered = mode == "dsp_registered"
        rows += [{"type": "DSP48E1_DSP48E1", "port": "P[0-9]+",
                  "class": "register_output" if registered else "comb_output"},
                 {"type": "DSP48E1_DSP48E1", "port": "[AB][0-9]+",
                  "class": "register_input" if registered else "comb_input"}]
    return rows


def main() -> None:
    """Write the explicit endpoint audit and fail if any requirement is unmet."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coverage", type=Path)
    parser.add_argument("requirements", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() in {args.coverage.resolve(), args.requirements.resolve()}:
        parser.error("output must not replace an input")
    result = check(json.loads(args.coverage.read_text()), json.loads(args.requirements.read_text()))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    raise SystemExit(0 if result["endpoint_requirements_met"] else 1)


if __name__ == "__main__":
    main()
