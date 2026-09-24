#!/usr/bin/env python3
"""Map and route tiny timing probes, checking endpoint coverage and observer neutrality."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phi_timing import critical_paths, tool_files
from timing_coverage.check import check, requirements

MODES = ("logic", "ram", "ram_registered", "dsp", "dsp_registered", "ram_dsp")


def digest(path: Path) -> str:
    """Hash an input or completed artifact without loading a large chip database."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def feature_digest(path: Path) -> str:
    """Hash all FASM features in order, excluding only whole-line comments."""
    content = "\n".join(line for line in path.read_text().splitlines() if not line.startswith("#"))
    return hashlib.sha256(content.encode()).hexdigest()


def command(args: list[str | Path], stage: Path, label: str, timeout: int) -> float:
    """Run one bounded phase, retaining stdout/stderr even when the tool fails."""
    start = time.monotonic()
    with (stage / f"{label}.console").open("w") as log:
        subprocess.run(list(map(str, args)), cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                       timeout=timeout, check=True)
    return round(time.monotonic() - start, 3)


def save(path: Path, value: Any) -> None:
    """Publish a structured report with a trailing newline."""
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def mapped_primitives(path: Path) -> dict[str, Any]:
    """Record hard-block modes so register absorption cannot hide in a MHz change."""
    cells = json.loads(path.read_text())["modules"]["timing_coverage_fixture"]["cells"]
    hard = {}
    for name, cell in cells.items():
        if cell["type"].startswith(("RAMB", "DSP")):
            params = {key: value for key, value in cell["parameters"].items()
                      if "REG" in key or "WIDTH" in key or key == "RAM_MODE"}
            hard[name] = {"type": cell["type"], "parameters": params}
    return {"counts": dict(Counter(cell["type"] for cell in cells.values())), "hard_blocks": hard}


def validate_modes(mode: str, primitives: dict[str, Any]) -> None:
    """Reject probes whose mapped hard blocks no longer exercise the requested modes."""
    blocks = list(primitives["hard_blocks"].values())
    rams = [block for block in blocks if block["type"] == "RAMB36E1"]
    dsps = [block for block in blocks if block["type"] == "DSP48E1"]
    want_ram = mode in {"ram", "ram_registered", "ram_dsp"}
    want_dsp = mode in {"dsp", "dsp_registered", "ram_dsp"}
    if len(rams) != int(want_ram) or len(dsps) != int(want_dsp):
        raise ValueError(f"{mode}: mapped hard-block population changed")
    if rams and int(rams[0]["parameters"]["DOB_REG"], 2) != int(mode == "ram_registered"):
        raise ValueError(f"{mode}: BRAM output-register mode changed")
    for dsp in dsps:
        for parameter in ("MREG", "PREG"):
            if int(dsp["parameters"][parameter], 2) != int(mode == "dsp_registered"):
                raise ValueError(f"{mode}: DSP register mode changed")


def run(args: argparse.Namespace) -> dict[str, Any]:
    """Compare identical maps/routes; retain omitted endpoints as measurement failures.

    Completed probes can pass their observer-neutrality check while failing
    endpoint coverage. Neither result qualifies a design-wide clock frequency.
    """
    root = Path(__file__).resolve().parent
    identity = {name: {str(path): digest(path) for path in tool_files(getattr(args, name))}
                for name in ("nextpnr", "baseline", "yosys")}
    inputs = {str(path): digest(path) for path in (args.chipdb, root / "fixture.v", Path(__file__),
                                                  root / "check.py", root / "nextpnr-coverage.patch")}
    report: dict[str, Any] = {"schema": 1, "status": "running", "tools": identity, "inputs": inputs,
                              "seed": 1, "requested_mhz": 100, "part": "xc7z030sbg485-1",
                              "design_wide_clock_validated": False, "runs": []}
    save(args.stage / "result.json", report)
    for mode in args.modes:
        stage = args.stage / mode
        stage.mkdir(exist_ok=False)
        source = root / "fixture.v"
        script = (f'read_verilog "{source}"\nchparam -set MODE {MODES.index(mode)} timing_coverage_fixture\n'
                  'synth_xilinx -family xc7 -top timing_coverage_fixture\n'
                  'check -assert\nscc -expect 0\nwrite_json mapped.json\n')
        (stage / "map.ys").write_text(script)
        command([args.yosys, "-Q", "-q", "-s", "map.ys"], stage, "map", args.timeout)
        primitives = mapped_primitives(stage / "mapped.json")
        validate_modes(mode, primitives)
        (stage / "timing.xdc").write_text((root.parent / "xc7z030sbg485.xdc").read_text() +
                                         "create_clock -period 10 [get_ports clock]\n")
        variants = {}
        for label in ("baseline", "nextpnr"):
            extra = ["--timing-coverage", "coverage.json"] if label == "nextpnr" else []
            elapsed = command([getattr(args, label), "--chipdb", args.chipdb, "--json", "mapped.json",
                               "--xdc", "timing.xdc", "--seed", "1", "--freq", "100", "--timing-allow-fail",
                               "--report", f"{label}.report.json", "--log", f"{label}.log",
                               "--fasm", f"{label}.fasm", *extra], stage, label, args.timeout)
            timing = json.loads((stage / f"{label}.report.json").read_text())
            paths = critical_paths((stage / f"{label}.log").read_text())
            if len(timing["fmax"]) != 1 or len(paths) != 1:
                raise ValueError(f"{mode}: missing or ambiguous completed timing report")
            variants[label] = {"seconds": elapsed, "fmax": timing["fmax"], "paths": paths,
                               "fasm_features_sha256": feature_digest(stage / f"{label}.fasm")}
        neutral = all(variants["baseline"][key] == variants["nextpnr"][key]
                      for key in ("fmax", "paths", "fasm_features_sha256"))
        if not neutral:
            raise ValueError(f"{mode}: coverage observer changed the measured route")
        coverage = check(json.loads((stage / "coverage.json").read_text()), requirements(mode))
        if any(row["matched"] == 0 for row in coverage["checks"]):
            raise ValueError(f"{mode}: endpoint selector matched no ports")
        if not all(row["passed"] for row in coverage["checks"][:2]):
            raise ValueError(f"{mode}: fixture flip-flop control endpoints are not modeled")
        row = {"mode": mode, "mapped": primitives, "observer_neutral": neutral, "variants": variants,
               "coverage": coverage, "artifacts": {path.name: digest(path) for path in stage.iterdir()
                                                    if path.is_file()}}
        report["runs"].append(row)
        save(args.stage / "result.json", report)
        print(f"{mode}: identical route; endpoint coverage={coverage['endpoint_requirements_met']}", flush=True)
    report["status"] = "complete"
    save(args.stage / "result.json", report)
    return report


def main() -> None:
    """Require explicit native tools and a new output directory; never overwrite evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("nextpnr", "baseline", "yosys", "chipdb", "stage"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--modes", choices=MODES, nargs="+", default=MODES)
    parser.add_argument("--timeout", type=int, default=120, help="seconds per mapping/routing phase")
    args = parser.parse_args()
    if args.timeout <= 0 or len(set(args.modes)) != len(args.modes):
        parser.error("positive timeout and distinct modes required")
    for name in ("nextpnr", "baseline", "yosys", "chipdb", "stage"):
        setattr(args, name, getattr(args, name).resolve())
    args.stage.mkdir(parents=True, exist_ok=False)
    try:
        run(args)
    except Exception as error:
        target = args.stage / "result.json"
        report = json.loads(target.read_text()) if target.exists() else {}
        report.update(status="failed", error=str(error))
        save(target, report)
        raise


if __name__ == "__main__":
    main()
