#!/usr/bin/env python3
"""Prepare four inert reference-clock bit comparisons at the board's bonded site."""

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from gtx.prepare import digest, fetch


def prepare(output: Path) -> dict:
    """Create one baseline and three single-attribute IBUFDS_GTE2 variants."""
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    pin = json.loads((ROOT / "gtx/reference.lock.json").read_text())["common"]
    tcl = fetch(pin, output.parent / "reference-sources").decode()
    tcl = tcl.replace('source "$::env(XRAY_DIR)/utils/utils.tcl"\n', "")
    marker = "    synth_design -top top\n"
    if tcl.count(marker) != 1:
        raise ValueError("upstream reference procedure changed")
    tcl = tcl.replace(marker, marker +
                      "    set_property PACKAGE_PIN U5 [get_ports ref_p]\n"
                      "    set_property PACKAGE_PIN V5 [get_ports ref_n]\n"
                      "    if {[llength [get_cells -hier -filter {REF_NAME == IBUFDS_GTE2}]] != 1} {error {reference buffer lost}}\n")
    output.mkdir(parents=True)
    shutil.copy2(ROOT / "gtx/LICENSE.prjxray", output / "LICENSE")
    cases = {"base": ('"TRUE"', '"TRUE"', "2'b11"),
             "swing": ('"TRUE"', '"TRUE"', "2'b00"),
             "cm": ('"FALSE"', '"TRUE"', "2'b11"),
             "trst": ('"TRUE"', '"FALSE"', "2'b11")}
    for name, (cm, trst, swing) in cases.items():
        stage = output / name
        stage.mkdir()
        (stage / "generate.tcl").write_text(tcl)
        (stage / "top.v").write_text(
            "// Inert configuration reference. DO NOT PROGRAM.\n"
            "module top(input wire ref_p, ref_n);\n"
            '(* KEEP, DONT_TOUCH, LOC="IBUFDS_GTE2_X0Y1" *)\n'
            f"IBUFDS_GTE2 #(.CLKCM_CFG({cm}), .CLKRCV_TRST({trst}), .CLKSWING_CFG({swing}))\n"
            "specimen(.I(ref_p), .IB(ref_n), .CEB(1'b0), .O(), .ODIV2());\nendmodule\n")
    (output / "run.tcl").write_text(
        "set root [file dirname [file normalize [info script]]]\n"
        "set ::env(XRAY_PART) xc7z030sbg485-1\n"
        "set_param general.maxThreads 2\n"
        "foreach name {base swing cm trst} {\n"
        "  cd [file join $root $name]\n  source generate.tcl\n  close_project\n}\n")
    report = {"part": "xc7z030sbg485-1", "site": "IBUFDS_GTE2_X0Y1", "upstream": pin,
              "cases": cases, "hardware_qualified": False,
              "inputs": {str(p.relative_to(output)): digest(p.read_bytes())
                         for p in sorted(output.rglob("*")) if p.is_file()}}
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    """Select a new directory for the portable reference task."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.output.resolve()), indent=2))


if __name__ == "__main__":
    main()
