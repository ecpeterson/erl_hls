#!/usr/bin/env python3
"""Check memory mapping and behavior, including both former export failures."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

import check_debug_memories as memories
from topology_debug import instrument, quote, yosys_run

ROOT = Path(__file__).resolve().parents[1]


def test(yosys, stage):
    stage = stage.resolve()
    instrument(argparse.Namespace(
        top="memory_export_fixture", output_top="observed", clock="clk", reset="reset",
        reset_active_low=False, stage=stage, yosys=yosys,
        rtl=[ROOT / "test/rtl/debug/memory_export_fixture.sv", ROOT / "priv/rtl/hls_1r1w_ram.v"]))
    report = memories.check(stage, yosys, map_xc7=True)
    counts = report["mapping"]["verilog"]["primitives"]
    assert counts.get("RAMB18E1", 0) == 3, counts
    assert any(name.startswith("RAM") and not name.startswith("RAMB") for name in counts), counts
    exe = stage / "memory.vvp"
    subprocess.run(["iverilog", "-g2012", "-s", "memory_export_tb", "-o", str(exe),
                    str(ROOT / "test/rtl/debug/memory_export_tb.sv"),
                    str(ROOT / "test/rtl/debug/memory_export_fixture.sv"),
                    str(ROOT / "priv/rtl/hls_1r1w_ram.v"), str(stage / "instrumented.v")], check=True)
    subprocess.run(["vvp", str(exe)], check=True, timeout=30)
    # Removing only -noattr is insufficient: without opt_reduce, identical
    # word-enable bits become separate writes and fragment the mapped RAMs.
    controls = {}
    for name, flag, mapping in (("stripped", "-noattr", False), ("unreduced", "", True)):
        control = stage / name
        control.mkdir(exist_ok=True)
        for source in ("flat.json", "instrumented.json", "manifest.json"):
            shutil.copy2(stage / source, control / source)
        yosys_run(yosys, f"read_json {quote(stage / 'instrumented.json')}\nopt_clean -purge\n" +
                  f"write_verilog {flag} {quote(control / 'instrumented.v')}\n", control, "export")
        expected = "mapped memory configurations" if mapping else "memory declarations"
        try:
            memories.check(control, yosys, map_xc7=mapping)
        except ValueError as error:
            assert f"RTL export changed {expected}" in str(error), error
        else:
            raise AssertionError(f"{name} export escaped the audit")
        if mapping:
            controls[name] = json.loads((control / "memory-check/report.json").read_text())["mapping"]["verilog"]
        else:
            controls[name] = memories.map_memories(yosys, f"read_verilog -sv {quote(control / 'instrumented.v')}",
                                                   "observed", control, "mapped")
            assert not any(kind.startswith("RAMB") for kind in controls[name]["primitives"]), controls[name]
    (stage / "negative-controls.json").write_text(json.dumps(controls, indent=2) + "\n")
    stripped = stage / "stripped"
    # A corrupted instrumented JSON must fail before inspecting its RTL.
    broken = json.loads((stripped / "instrumented.json").read_text())
    del broken["modules"]["observed"]["memories"]["first_ram.memory"]["attributes"]["ram_style"]
    (stripped / "instrumented.json").write_text(json.dumps(broken))
    try:
        memories.check(stripped, yosys, output=stripped / "broken-json")
    except ValueError as error:
        assert "instrumentation changed application memory declarations" in str(error), error
    else:
        raise AssertionError("changed instrumented memory escaped the audit")
    print("PASS: the audit rejects stripped attributes, fragmented RAM writes, and changed instrumented memories")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--stage", type=Path, default=Path("_build/debug-memories"))
    args = parser.parse_args()
    test(args.yosys, args.stage)
