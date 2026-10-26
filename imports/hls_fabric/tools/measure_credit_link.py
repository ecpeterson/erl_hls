#!/usr/bin/env python3
"""Measure an isolated symmetric credit-link endpoint with two XC7 ABC9 seeds."""
import argparse
import json
from pathlib import Path
from compiler_paths import compiler_root, compiler_tool
import shutil
import statistics
import subprocess

from backend_paths import ROOT
from backend_commands import digest, execute


def wrapper(lanes: int) -> str:
    """Bind the symmetric fixture to the requested number of lanes in each direction."""
    source = (ROOT / "test/xls/credit_link.x").read_text()
    return source.replace("[2]", f"[{lanes}]").replace(
        "Bridge<u32:2, u32:2,", f"Bridge<u32:{lanes}, u32:{lanes},")


def measure(args: argparse.Namespace) -> None:
    """Compile endpoints and retain matched two-seed resource measurements for each lane count."""
    args.stage.mkdir(parents=True, exist_ok=False)
    accounting = compiler_tool(args.erl_hls, "measure_topology_debug")
    report = {"scope": "isolated credit-link endpoint, no actor graph, debug, PHY or placement",
              "target": "xc7", "mapping": "ABC9, no I/O pads or clock buffers",
              "yosys": subprocess.check_output([args.yosys, "-V"], text=True).strip(),
              "prediction": "500-1500 LUTs at four lanes per direction, no BRAM",
              "tools": {name: digest(args.xls / name)
                        for name in ("ir_converter_main", "opt_main", "codegen_main")},
              "sources": {str(path.relative_to(ROOT)): digest(path) for path in
                          (ROOT / "priv/xls/hls_credit_link.x", ROOT / "tools/backend_commands.py", Path(__file__))},
              "compiler_sources": {name: digest(args.erl_hls / "priv/xls/lib" / name)
                                   for name in ("axis.x", "frame_config.x")},
              "configurations": []}
    for lanes in args.lanes:
        stage = args.stage / f"lanes-{lanes}"
        stage.mkdir()
        for path in (ROOT / "priv/xls/hls_credit_link.x", args.erl_hls / "priv/xls/lib/axis.x",
                     args.erl_hls / "priv/xls/lib/frame_config.x"):
            shutil.copyfile(path, stage / path.name)
        (stage / "endpoint.x").write_text(wrapper(lanes))
        commands = [
            ([str(args.xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
              "--dslx_path=.", f"--dslx_stdlib_path={args.xls / 'xls/dslx/stdlib'}", "endpoint.x"], "convert", "endpoint.ir"),
            ([str(args.xls / "opt_main"), "endpoint.ir"], "optimize", "endpoint.opt.ir"),
            ([str(args.xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit", "--flop_inputs=false",
              "--flop_outputs=true", "--use_system_verilog=false", "--reset=reset", "--fifo_module=",
              "--module_name=endpoint", "endpoint.opt.ir"], "codegen", "endpoint.v")]
        for command, name, output in commands:
            execute(command, stage, name, timeout=600, output=stage / output)
        samples = []
        for seed in (1, 2):
            script = stage / f"seed-{seed}.ys"
            script.write_text(f'''read_verilog -sv endpoint.v
hierarchy -check -top endpoint
proc
flatten
opt
rename -scramble-name -seed {seed}
synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf -top endpoint
check -assert
scc -expect 0
tee -o seed-{seed}.json stat -json -tech xilinx
''')
            execute([args.yosys, "-Q", "-T", "-s", str(script)], stage, f"seed-{seed}", timeout=600)
            cells = json.loads((stage / f"seed-{seed}.json").read_text())["design"]["num_cells_by_type"]
            samples.append({"seed": seed, **accounting.cell_counts(cells), "primitives": cells})
        summary = {key: {"best": min(values), "mean": statistics.mean(values),
                         "variance": statistics.pvariance(values), "worst": max(values)}
                   for key in ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36")
                   for values in [[sample[key] for sample in samples]]}
        report["configurations"].append({"lanes_per_direction": lanes,
            "commands": [command for command, _, _ in commands],
            "inputs": {path.name: digest(path) for path in stage.glob("*.x")},
            "rtl_sha256": digest(stage / "endpoint.v"), "samples": samples, "summary": summary})
        (args.stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"lanes": lanes, "summary": summary}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/credit-link-area")
    parser.add_argument("--lanes", nargs="+", type=int, default=[4, 6])
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    for name in ("xls", "erl_hls", "stage"):
        setattr(args, name, getattr(args, name).resolve())
    if not all(0 < lanes <= 32768 for lanes in args.lanes):
        parser.error("lane counts must be between 1 and 32768")
    measure(args)
