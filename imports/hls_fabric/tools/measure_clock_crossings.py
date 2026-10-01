#!/usr/bin/env python3
"""Map the two link and four debug clock crossings to XC7 primitives."""
import argparse
import importlib
import json
from pathlib import Path
from backend_paths import PUBLIC
import statistics
import subprocess
import sys
from test_actor_rtl import digest, execute

ROOT = Path(__file__).resolve().parents[1]


def wrapper():
    ports = ["input wire reset, host_clk, clk0, clk1"]
    instances = []
    crossings = [("link01", 33, "clk0", "clk1"), ("link10", 33, "clk1", "clk0")]
    crossings += [(f"debug{i}_{name}", 37, write, read) for i in (0, 1)
                  for name, write, read in (("request", "host_clk", f"clk{i}"),
                                            ("response", f"clk{i}", "host_clk"))]
    for name, width, write, read in crossings:
        ports += [f"input wire [{width-1}:0] {name}_in", f"input wire {name}_valid",
                  f"output wire {name}_ready", f"output wire [{width-1}:0] {name}_out",
                  f"output wire {name}_out_valid", f"input wire {name}_out_ready"]
        instances.append(f"""hls_async_fifo #(.WIDTH({width})) {name}(
    .reset(reset), .wr_clk({write}), .rd_clk({read}),
    .in_data({name}_in), .in_valid({name}_valid), .in_ready({name}_ready),
    .out_data({name}_out), .out_valid({name}_out_valid), .out_ready({name}_out_ready));""")
    return "module crossings(\n    " + ",\n    ".join(ports) + ");\n" + "\n".join(instances) + "\nendmodule\n"


def measure(args):
    args.stage.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(args.erl_hls / "tools"))
    accounting = importlib.import_module("measure_topology_debug")
    rtl = ROOT / "rtl/hls_async_fifo.v"
    (args.stage / "crossings.v").write_text(wrapper())
    samples = []
    for seed in (1, 2):
        script = args.stage / f"seed-{seed}.ys"
        script.write_text(f'''read_verilog {json.dumps(str(rtl))} crossings.v
hierarchy -check -top crossings
proc
flatten
opt
rename -scramble-name -seed {seed}
synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf -top crossings
check -assert
scc -expect 0
tee -o seed-{seed}.json stat -json -tech xilinx
write_json mapped-{seed}.json
''')
        execute([args.yosys, "-Q", "-T", "-s", str(script)], args.stage, f"seed-{seed}", timeout=300)
        cells = json.loads((args.stage / f"seed-{seed}.json").read_text())["design"]["num_cells_by_type"]
        samples.append({"seed": seed, **accounting.cell_counts(cells), "primitives": cells})
    summary = {key: {"best": min(values), "mean": statistics.mean(values),
                     "variance": statistics.pvariance(values), "worst": max(values)}
               for key in ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36")
               for values in [[sample[key] for sample in samples]]}
    report = {"scope": "six depth-8 clock crossings: two 33-bit links and four 37-bit debug paths",
              "excludes": "actor cores, credit endpoints, debug services, test-only admission stages, PHY, I/O and placement",
              "target": "xc7 ABC9, no I/O pads or clock buffers",
              "prediction": "300-660 LUTs, about 228 FF before shared reset logic, no BRAM",
              "yosys": subprocess.check_output([args.yosys, "-V"], text=True).strip(),
              "sources": {str(path.relative_to(ROOT)): digest(path) for path in (rtl, Path(__file__))},
              "wrapper_sha256": digest(args.stage / "crossings.v"), "samples": samples, "summary": summary}
    (args.stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/clock-crossing-area")
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    args.stage = args.stage.resolve()
    measure(args)
