#!/usr/bin/env python3
"""Measure the deployed cost of all hooks against matched production D3 RTL.

Run build_phi_debug.py first. This maps the entire design, including the shared
debug transport, compiler-generated samples and one boundary monitor. LUT RAM
is included in LUT totals. No placement/routing or power estimate is implied.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from measure_topology_debug import cell_counts, distribution
from topology_debug import quote, yosys_run
from topology_debug_services import rtl_files
from build_phi_debug import validate


def measure(args):
    build, stage = args.build.resolve(), args.stage.resolve()
    validate(build)
    stage.mkdir(parents=True, exist_ok=True)
    snapshot = stage / "sources"
    snapshot.mkdir(exist_ok=True)
    # Snapshot once: every seed consumes identical inputs, even during local work.
    support = rtl_files(monitor=True)
    files = [build / "debug/instrumented.json", build / "debug/debug_top.v",
             build / "debug/manifest.json", *support,
             *[build / "production" / name for name in ("phi_memory_top.v", "phi_memory_gateway.v", "hls_1r1w_ram.v")],
             *[build / "support" / f"{name}.v" for name in ("hls_fabric_router", "hls_debug_observer", "hls_debug_server")]]
    for source in files:
        shutil.copy(source, snapshot)
    production = [snapshot / name for name in ("phi_memory_top.v", "phi_memory_gateway.v", "hls_1r1w_ram.v", "hls_fabric_router.v")]
    yosys_run(args.yosys, "read_verilog -sv " + " ".join(map(quote, production)) +
              "\nhierarchy -check -top phi_memory_top\nproc\nflatten\n" +
              f"write_json {quote(snapshot / 'production.json')}\n", stage, "production")
    sources = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in snapshot.iterdir()}
    (stage / "provenance.json").write_text(json.dumps({"sources": sources,
        "yosys": subprocess.check_output([args.yosys, "-V"], text=True).strip(),
        "seeds": args.seeds, "flow": "opt; memory_collect; scramble; synth_xilinx -abc9 -arch xc7 -noiopad -noclkbuf; check; scc"
    }, indent=2) + "\n")

    def run(job):
        mode, seed = job
        prefix = stage / f"{mode}-{seed}"
        if mode == "production":
            script = f"read_json {quote(snapshot / 'production.json')}\n"
            top = "phi_memory_top"
        else:
            script = f"read_json {quote(snapshot / 'instrumented.json')}\n"
            services = [snapshot / "debug_top.v", *[snapshot / p.name for p in support],
                        snapshot / "hls_debug_observer.v", snapshot / "hls_debug_server.v"]
            script += "read_verilog -sv " + " ".join(map(quote, services)) + "\n"
            top = "hls_debug_application"
        script += f"hierarchy -check -top {top}\nproc\nflatten\nopt\nmemory_collect\nrename -scramble-name -seed {seed}\n"
        script += f"synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf -top {top}\ncheck -assert\nscc -expect 0\n"
        script += f"tee -o {quote(prefix.with_suffix('.json'))} stat -json -tech xilinx\n"
        yosys_run(args.yosys, script, stage, prefix.name)
        cells = json.loads(prefix.with_suffix(".json").read_text())["design"]["num_cells_by_type"]
        row = {"mode": mode, "seed": seed, **cell_counts(cells), "DSP": cells.get("DSP48E1", 0)}
        row["BRAM18_equivalent"] = row["RAMB18"] + 2*row["RAMB36"]
        print(json.dumps(row), flush=True)
        return row

    jobs = [(mode, seed) for seed in range(1, args.seeds+1) for mode in ("production", "all")]
    rows = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for row in pool.map(run, jobs):
            rows.append(row)
            (stage / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    summary = {mode: {key: distribution([row[key] for row in rows if row["mode"] == mode])
                     for key in rows[0] if key not in ("mode", "seed")} for mode in ("production", "all")}
    (stage / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("_build/phi-debug/area"))
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--seeds", type=int, default=5)
    parser.add_argument("--jobs", type=int, default=1, help="concurrent full designs; 2 fits a 16 GiB host")
    args = parser.parse_args()
    if args.seeds < 1 or args.jobs < 1:
        parser.error("seeds and jobs must be positive")
    measure(args)
