#!/usr/bin/env python3
"""Compare matched D3 decoder mappings over controlled signal-name seeds.

These are out-of-context mapped resources and ABC9 delay estimates. Routing,
clock feasibility, and debug instrumentation are separate measurements.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import sys

from phi_timing import CORE, HERE, load_profile, mapped_stage, quote, save, sha, tool_files

sys.path.insert(0, str(HERE.parents[1] / "tools"))
from measure_topology_debug import cell_counts, distribution


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3, 4, 5])
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.jobs < 1 or min(args.seeds) < 1 or len(set(args.seeds)) != len(args.seeds):
        parser.error("jobs and unique seeds must be positive")
    stages = {name: getattr(args, name).resolve() for name in ("baseline", "candidate")}
    builds = {name: load_profile(path) for name, path in stages.items()}
    for key in ("profile", "tools", "stdlib", "ram_configuration"):
        if builds["baseline"][key] != builds["candidate"][key]:
            parser.error(f"unmatched {key}")
    stage = args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    apio = Path(os.environ.get("ERL_HLS_APIO_HOME", HERE / ".apio")).resolve()
    yosys = apio / "packages/oss-cad-suite/bin/yosys"
    sources = {name: [path / file for file in
                     ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")]
               for name, path in stages.items()}
    save(stage / "inputs.json", {"builds": builds,
         "tool_files": {str(p): sha(p) for p in tool_files(yosys)},
         "measurement_script": sha(Path(__file__)), "seeds": args.seeds})

    def measure(pair):
        name, seed = pair
        run = stage / f"{name}-{seed}"
        run.mkdir(exist_ok=True)
        script = "read_verilog -sv " + " ".join(map(quote, sources[name])) + "\n"
        script += f"hierarchy -check -top {CORE}\nproc\nflatten\nopt\nmemory_collect\n"
        script += f"rename -scramble-name -seed {seed}\n"
        script += f"synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top {CORE}\n"
        script += "check -assert\nscc -expect 0\ntee -o stat.json stat -json -tech xilinx\n"
        completion = mapped_stage(run, "map", script, sources[name], ["stat.json", "map.log"], yosys)
        cells = json.loads((run / "stat.json").read_text())["design"]["num_cells_by_type"]
        delays = re.findall(r"ABC: A: +Del = ([0-9]+(?:\.[0-9]+)?)", (run / "map.log").read_text())
        if not delays:
            raise ValueError(f"{name}/{seed}: missing ABC9 mapping-stage delay")
        result = {"variant": name, "seed": seed, **cell_counts(cells),
                  "DSP": cells.get("DSP48E1", 0), "CARRY4": cells.get("CARRY4", 0),
                  "mapping_delay_ps": float(delays[-1]), "completion": completion}
        print(json.dumps({k: v for k, v in result.items() if k != "completion"}), flush=True)
        return result

    pairs = [(name, seed) for seed in args.seeds for name in stages]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(measure, pairs))
    keys = ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36", "DSP", "CARRY4", "mapping_delay_ps")
    summary = {name: {key: distribution([r[key] for r in rows if r["variant"] == name])
                      for key in keys} for name in stages}
    save(stage / "results.json", {"samples": rows, "summary": summary})
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
