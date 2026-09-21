#!/usr/bin/env python3
"""Compare native nextpnr builds on small XC7 placement and LUT-truth fixtures."""

import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path
from typing import Any

from lut_legality.check import check
from phi_timing import tool_files

# Stable fixture modes also permit rerunning one failed case in isolation.
FIXTURES = ("lut5", "lut6", "dual", "carry", "ram", "srl", "fixed", "tied")


def digest(path: Path) -> str:
    """Fingerprint a source, tool or measurement artifact."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args: list[str | Path], stage: Path, label: str, timeout: int = 60) -> float:
    """Run a bounded phase, retaining its combined output and returning seconds."""
    started = time.monotonic()
    with (stage / f"{label}.console").open("w") as log:
        subprocess.run(list(map(str, args)), cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout)
    return time.monotonic() - started


def run(args: argparse.Namespace) -> dict[str, Any]:
    """Map once per fixture, then compare placement, routes and programmed LUTs."""
    root = Path(__file__).resolve().parent
    args.stage.mkdir(parents=True, exist_ok=True)
    identity = {name: digest(getattr(args, name))
                for name in ("baseline", "candidate", "yosys", "chipdb", "tilegrid")}
    report: dict[str, Any] = {"status": "running", "inputs": identity, "fixtures": {}, "runs": [],
                              "tool_files": {name: {str(p): digest(p) for p in tool_files(getattr(args, name))}
                                             for name in ("baseline", "candidate", "yosys")},
                              "checker_sha256": digest(root / "lut_legality/check.py"),
                              "runner_sha256": digest(Path(__file__)),
                              "patches": {p.name: digest(p) for p in sorted((root / "lut_legality").glob("*.patch"))}}
    for name in args.fixtures:
        mode = FIXTURES.index(name)
        source = root / "lut_legality" / ("fixed_fixture.v" if mode >= 6 else "fixture.v")
        report["fixtures"][source.name] = digest(source)
        stage = args.stage / name
        stage.mkdir(exist_ok=True)
        script = (f'read_verilog "{source}"; chparam -set MODE {mode} lut_legality_fixture; '
                  'synth_xilinx -family xc7 -top lut_legality_fixture; check -assert; scc -expect 0; '
                  'write_json mapped.json')
        command([args.yosys, "-Q", "-q", "-p", script], stage, "map")
        (stage / "timing.xdc").write_text((root / "xc7z030sbg485.xdc").read_text() +
                                         "create_clock -period 10 [get_ports clock]\n")
        for variant in ("baseline", "candidate"):
            tool = getattr(args, variant)
            command([tool, "--chipdb", args.chipdb, "--json", "mapped.json", "--xdc", "timing.xdc", "--pack-only",
                     "--write", variant + "-packed.json"], stage, variant + "-pack")
            elapsed = command([tool, "--chipdb", args.chipdb, "--json", "mapped.json", "--xdc", "timing.xdc",
                               "--seed", "1", "--freq", "100", "--timing-allow-fail",
                               "--write", variant + ".json", "--fasm", variant + ".fasm",
                               "--log", variant + ".log"], stage, variant)
            log = (stage / f"{variant}.log").read_text()
            repairs = sum(map(int, re.findall(r"post-place repair: relocated (\d+)", log)))
            inputs = (stage / f"{variant}-packed.json", stage / f"{variant}.json",
                      stage / f"{variant}.fasm", args.tilegrid)
            validation: dict[str, Any]
            if variant == "baseline" and name == "tied":
                # The unchanged backend must demonstrate the known wrong
                # function, independently of its malformed origin metadata.
                try:
                    check(*inputs, require_origins=False)
                except ValueError as error:
                    if "wrong programmed truth table" not in str(error):
                        raise
                    validation = {"expected_failure": str(error)}
                else:
                    raise ValueError("unchanged backend no longer reproduces the tied-input bug")
            else:
                validation = check(*inputs)
            result = {"fixture": name, "variant": variant, "seconds": round(elapsed, 3),
                      "repairs": repairs, **validation,
                      "artifacts": {suffix: digest(stage / f"{variant}.{suffix}")
                                    for suffix in ("json", "fasm", "log")}}
            report["runs"].append(result)
            print(json.dumps(result), flush=True)
            (args.stage / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    report["status"] = "complete"
    (args.stage / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    """Require explicit tools and the already prepared exact-part database."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "yosys", "chipdb", "tilegrid", "stage"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--fixtures", nargs="+", choices=FIXTURES, default=FIXTURES)
    args = parser.parse_args()
    for name, value in vars(args).items():
        if isinstance(value, Path):
            setattr(args, name, value.resolve())
    args.stage.mkdir(parents=True, exist_ok=True)
    result = args.stage / "result.json"
    result.write_text(json.dumps({"status": "running", "fixtures_requested": args.fixtures}) + "\n")
    try:
        run(args)
    except Exception as error:
        report = json.loads(result.read_text())
        report.update(status="failed", error=str(error))
        result.write_text(json.dumps(report, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
