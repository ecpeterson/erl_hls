#!/usr/bin/env python3
"""Check application memory preservation through passive debug RTL export.

Compare original, instrumented, and reparsed memory declarations. With
--map-xc7, also compare the preserved JSON and emitted Verilog after Xilinx
memory mapping, before expensive LUT mapping or placement. This is a storage
implementation check, not a whole-design area/timing or equivalence proof.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from topology_debug import quote, yosys_run


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def inventory(module):
    # Source locations change when Verilog is reparsed; hdlname is provenance
    # added by flattening. Every other memory attribute must survive literally.
    return {name: {key: memory[key] for key in ("width", "size", "start_offset")} |
            {"attributes": {key: value for key, value in memory.get("attributes", {}).items()
                            if key not in ("src", "hdlname")}}
            for name, memory in module.get("memories", {}).items()}


def mapped_memories(module):
    # Internal instance names and signal numbers can change on round-trip.
    # Compare the full primitive parameter sets (including INIT and collision
    # modes) as a multiset; keep the report compact by hashing those sets.
    configurations, counts = Counter(), Counter()
    unmapped_bits = 0
    for cell in module.get("cells", {}).values():
        kind = cell["type"]
        if not (kind.startswith("RAM") or kind == "$mem_v2"):
            continue
        parameters = {k: v for k, v in cell["parameters"].items() if k != "MEMID"}
        counts[kind] += 1
        configurations[kind, digest(parameters)] += 1
        if kind == "$mem_v2":
            unmapped_bits += int(parameters["WIDTH"], 2) * int(parameters["SIZE"], 2)
    return {"primitives": dict(sorted(counts.items())), "unmapped_bits": unmapped_bits,
            "configurations": [{"type": kind, "parameters_sha256": key, "count": count}
                               for (kind, key), count in sorted(configurations.items())]}


def map_memories(yosys, read, top, stage, name):
    target = stage / f"{name}.json"
    yosys_run(yosys, read + f"\nhierarchy -check -top {top}\n" +
              f"synth_xilinx -family xc7 -flatten -noiopad -noclkbuf -top {top} -run begin:map_ffram\n" +
              f"select {top}\nwrite_json -selected {quote(target)}\n", stage, name)
    design = json.loads(target.read_text())
    return mapped_memories(design["modules"][top])


def check(stage, yosys, output=None, map_xc7=False):
    stage = stage.resolve()
    output = (output or stage / "memory-check").resolve()
    output.mkdir(parents=True, exist_ok=True)
    paths = {name: stage / name for name in ("flat.json", "instrumented.json", "instrumented.v")}
    original = json.loads(paths["flat.json"].read_text())
    exported = json.loads(paths["instrumented.json"].read_text())
    top, = exported["modules"]
    original_top = json.loads((stage / "manifest.json").read_text())["top"]
    expected = inventory(original["modules"][original_top])
    if not expected:
        raise ValueError("memory check requires an application with memories")
    if inventory(exported["modules"][top]) != expected:
        raise ValueError("instrumentation changed application memory declarations")
    # The full D3 netlists are large; retain only their memory inventories
    # while Yosys elaborates and maps the other representation.
    del original, exported
    reread = output / "roundtrip.json"
    yosys_run(yosys, f"read_verilog -sv {quote(paths['instrumented.v'])}\n" +
              f"hierarchy -check -top {top}\nproc\n" +
              f"write_json {quote(reread)}\n", output, "roundtrip")
    actual = inventory(json.loads(reread.read_text())["modules"][top])
    report = {"yosys": subprocess.check_output([yosys, "-V"], text=True).strip(),
              "inputs": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in paths.items()},
              "original": expected, "roundtrip": actual}
    report_file = output / "report.json"
    report_file.write_text(json.dumps(report, indent=2) + "\n")
    if actual != expected:
        changed = sorted(name for name in expected.keys() | actual.keys() if expected.get(name) != actual.get(name))
        raise ValueError(f"RTL export changed memory declarations: {changed}")
    if map_xc7:
        mappings = {}
        for name, read in (("preserved", f"read_json {quote(paths['instrumented.json'])}"),
                           ("verilog", f"read_verilog -sv {quote(paths['instrumented.v'])}")):
            mappings[name] = map_memories(yosys, read, top, output, name)
        report["mapping"] = mappings
        report_file.write_text(json.dumps(report, indent=2) + "\n")
        if mappings["preserved"] != mappings["verilog"]:
            raise ValueError("RTL export changed mapped memory configurations")
    print(f"PASS: {len(expected)} application memories preserve geometry and attributes" +
          (" and XC7 primitive configurations" if map_xc7 else ""), flush=True)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="instrumentation directory")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--map-xc7", action="store_true")
    args = parser.parse_args()
    check(args.stage, args.yosys, args.output, args.map_xc7)
