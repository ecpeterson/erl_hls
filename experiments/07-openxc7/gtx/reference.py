#!/usr/bin/env python3
"""Prepare inert Z7030 GTX bit-location references for a separate Vivado host."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from gtx.prepare import digest, fetch

# Two independent changes per tile allow a proposed frame origin to be checked.
# Consult the pinned donor for hypothesized relative positions, not Zynq facts.
CASES = {
    "channel": {"primitive": "GTXE2_CHANNEL", "site": "GTXE2_CHANNEL_X0Y1",
                "tile": "GTX_CHANNEL_1_X186Y17",
                "base": {"ALIGN_MCOMMA_DET": '"FALSE"', "CPLL_LOCK_CFG": "9'h1e8"},
                "changes": {"align": {"ALIGN_MCOMMA_DET": '"TRUE"'},
                            "lock": {"CPLL_LOCK_CFG": "9'h1e9"}}},
    "common": {"primitive": "GTXE2_COMMON", "site": "GTXE2_COMMON_X0Y0",
               "tile": "GTX_COMMON_X186Y23",
               "base": {"QPLL_FBDIV": "10'h005", "BIAS_CFG": "64'h0000040000001000"},
               "changes": {"divider": {"QPLL_FBDIV": "10'h004"},
                           "bias": {"BIAS_CFG": "64'h0000040000001001"}}},
}


def source(case: dict, change: dict[str, str]) -> str:
    """Emit one fixed, unconnected primitive; this is not an operational design."""
    params = {**case["base"], **change}
    attributes = ",\n        ".join(f".{name}({value})" for name, value in params.items())
    return ("// Inert configuration reference. DO NOT PROGRAM hardware with this design.\n"
            "module top();\n"
            f'    (* KEEP, DONT_TOUCH, LOC="{case["site"]}" *)\n'
            f'    {case["primitive"]} #(\n        {attributes}\n    ) specimen ();\nendmodule\n')


def prepare(output: Path) -> dict:
    """Write a portable six-run reference bundle using pinned X-Ray Tcl scripts.

    Existing output is rejected so a new bundle cannot mix with old evidence.
    No Vivado executable, database overlay or hardware programming is invoked.
    """
    if output.exists():
        raise ValueError(f"reference directory already exists: {output}")
    lock = json.loads(Path(__file__).with_name("reference.lock.json").read_text())
    scripts = {kind: fetch(pin, output.parent / "reference-sources").decode() for kind, pin in lock.items()}
    # These two upstream scripts source utils.tcl but call no procedures from it.
    unused_import = 'source "$::env(XRAY_DIR)/utils/utils.tcl"\n'
    for kind, script in scripts.items():
        if script.count(unused_import) != 1:
            raise ValueError(f"upstream Tcl import changed: {kind}")
    output.mkdir(parents=True)
    runs = []
    for kind, case in CASES.items():
        for variant, change in {"base": {}, **case["changes"]}.items():
            name = kind + "-" + variant
            stage = output / name
            stage.mkdir()
            (stage / "top.v").write_text(source(case, change))
            (stage / "generate.tcl").write_text(scripts[kind].replace(unused_import, ""))
            runs.append(name)
    # Each run retains the original upstream DRC exemptions for an unconnected
    # primitive. They must never be reused by the operational board build.
    runner = '''# Configuration evidence only: no hardware manager/programming commands.
set root [file dirname [file normalize [info script]]]
set ::env(XRAY_PART) xc7z030sbg485-1
set version_file [open [file join $root vivado-version.txt] w]
puts $version_file [version]
close $version_file
foreach name {RUNS} {
    cd [file join $root $name]
    source generate.tcl
    close_project
}
'''.replace("RUNS", " ".join(runs))
    (output / "run.tcl").write_text(runner)
    (output / "DO_NOT_PROGRAM.txt").write_text(
        "These unconnected primitive designs measure configuration locations only.\n"
        "They deliberately use upstream X-Ray DRC exemptions; they are not board images.\n"
        "Run: vivado -mode batch -source run.tcl\n"
        "Return the complete directory, including version, logs, checkpoints and bitstreams.\n")
    report = {"part": "xc7z030sbg485-1", "cases": CASES, "runs": runs, "upstream": lock,
              "vivado_executed": False, "hardware_qualified": False,
              "files": {str(path.relative_to(output)): digest(path.read_bytes())
                        for path in sorted(output.rglob("*")) if path.is_file()}}
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    """Choose a new directory for a portable, reference-only Vivado task."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.output.resolve()), indent=2))


if __name__ == "__main__":
    main()
