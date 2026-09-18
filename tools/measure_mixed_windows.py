#!/usr/bin/env python3
"""Check reset/recovery and measure the two-component mixed-topology fixture.

First run test_mixed_topology.sh with components_global components_weak.
The simulation uses only application ports and fixed cycle-based backpressure;
its cycles are independent of the separate live debug regression's host timing.
Optional area mapping includes the complete application and topology/actor
query service, but no boundary counter/trace monitor or board transport.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from measure_topology_debug import cell_counts, distribution
from topology_debug import quote, yosys_run
from test_topology_debug_integration import DEBUG_RTL

ROOT = Path(__file__).resolve().parents[1]
MODES = ("components_global", "components_weak")


def simulate(build, stage, stages):
    samples = []
    for mode in MODES:
        source = build / mode
        for depth in stages:
            output = stage / f"{mode}-p{depth}"
            output.mkdir(parents=True, exist_ok=True)
            tb = ROOT / "test/rtl/mixed_effect_windows_tb.sv"
            shutil.copy(source / "expected.hex", output / "expected.hex")
            rtl = [source / f"topology_{depth}.v", source / "mixed_topology_wrapper.v",
                   ROOT / "priv/rtl/hls_1r1w_ram.v"]
            with (output / "compile.log").open("w") as log:
                subprocess.run(["iverilog", "-g2012", "-s", "window_tb", "-o", str(output / "test.vvp"),
                                str(tb), *map(str, rtl)], stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=120)
            result = subprocess.run(["vvp", str(output / "test.vvp")], capture_output=True,
                                    text=True, timeout=60, cwd=output)
            (output / "simulation.log").write_text(result.stdout + result.stderr)
            result.check_returncode()
            match = re.search(r"METRICS (\d+) (\d+) (\d+) (\d+)", result.stdout)
            if not match:
                raise RuntimeError(f"missing completion metrics: {output}")
            first, last, peer_first, peer_last = map(int, match.groups())
            row = {"mode": mode, "pipeline_stages": depth, "first": first, "last": last,
                   "peer_first": peer_first, "peer_last": peer_last,
                   "report_interval_mean": (last-first)/31,
                   "peer_report_interval_mean": (peer_last-peer_first)/31}
            samples.append(row)
            print(json.dumps(row), flush=True)
    (stage / "cycles.json").write_text(json.dumps(samples, indent=2) + "\n")


def measure(build, stage, yosys, seeds):
    area = stage / "area"
    area.mkdir(exist_ok=True)
    rows, sources = [], {}
    for mode in MODES:
        source = build / mode / "p2"
        files = [source / "instrumented.json", source / "debug_top.v", *DEBUG_RTL]
        sources[mode] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        for seed in range(1, seeds+1):
            name = f"{mode}-{seed}"
            report = area / f"{name}.json"
            script = f"read_json {quote(files[0])}\nread_verilog -sv " + " ".join(map(quote, files[1:])) + "\n"
            script += "hierarchy -check -top hls_debug_application\nproc\nflatten\nopt\nmemory_collect\n"
            script += f"rename -scramble-name -seed {seed}\n"
            script += "synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top hls_debug_application\ncheck -assert\nscc -expect 0\n"
            script += f"tee -o {quote(report)} stat -json -tech xilinx\n"
            yosys_run(yosys, script, area, name)
            cells = json.loads(report.read_text())["design"]["num_cells_by_type"]
            row = {"mode": mode, "seed": seed, **cell_counts(cells)}
            rows.append(row)
            print(json.dumps(row), flush=True)
            (area / "samples.json").write_text(json.dumps(rows, indent=2) + "\n")
    summary = {mode: {metric: distribution([r[metric] for r in rows if r["mode"] == mode])
                      for metric in rows[0] if metric not in ("mode", "seed")} for mode in MODES}
    provenance = {"sources": sources, "yosys": subprocess.check_output([yosys, "-V"], text=True).strip(),
                  "pipeline_stages": 2, "seeds": seeds, "samples": rows, "summary": summary}
    (area / "results.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("_build/mixed-windows"))
    parser.add_argument("--stages", type=int, nargs="+", default=[2, 3], choices=[2, 3])
    parser.add_argument("--area", action="store_true")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--seeds", type=int, default=2)
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error("seeds must be positive")
    args.stage.mkdir(parents=True, exist_ok=True)
    simulate(args.build.resolve(), args.stage.resolve(), args.stages)
    if args.area:
        measure(args.build.resolve(), args.stage.resolve(), args.yosys, args.seeds)
