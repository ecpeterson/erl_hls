#!/usr/bin/env python3
"""Measure differently sized decoder populations with the same XC7 mapping recipe.

This is an out-of-context capacity probe, excluding physical board links and
the external debug gateway. It does not establish a board fit or clock limit.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sys

from measure_phi_mapping import measure_mapping
from phi_timing import HERE, load_profile, save, sha, tool_files


def main() -> None:
    """Compare matched decoder builds with one explicitly selected accounting implementation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profiles", type=Path, nargs="+", help="prepared profile directories containing compiled/")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--seeds", nargs="+", type=int, default=[1, 2])
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--erl-hls", type=Path)
    parser.add_argument("--profile", default="default")
    args = parser.parse_args()
    sys.path.insert(0, str(HERE.parents[1] / "tools/hls_fabric"))
    from compiler_paths import compiler_root, compiler_tool
    public = compiler_root(args.profile, args.erl_hls, HERE.parents[1])
    accounting = compiler_tool(public, "measure_topology_debug")
    if args.jobs < 1 or min(args.seeds) < 1 or len(set(args.seeds)) != len(args.seeds):
        parser.error("jobs and unique seeds must be positive")
    sources = {path.name: (path / "compiled").resolve() for path in args.profiles}
    if len(sources) != len(args.profiles):
        parser.error("profile directory names must be unique")
    builds = {name: load_profile(path, require_d3=False) for name, path in sources.items()}
    reference = next(iter(builds.values()))
    for build in builds.values():
        if any(build[k] != reference[k] for k in ("tools", "stdlib", "ram_configuration")):
            parser.error("profiles must use the same tools, standard library, and RAM recipe")
        if build["build_profile"] != reference["build_profile"]:
            parser.error("profiles must use the same emitted hardware policy")
    stage = args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    apio = Path(os.environ.get("ERL_HLS_APIO_HOME", HERE / ".apio")).resolve()
    yosys = apio / "packages/oss-cad-suite/bin/yosys"
    save(stage / "inputs.json", {"builds": builds,
         "tool_files": {str(p): sha(p) for p in tool_files(yosys)},
         "measurement_script": sha(Path(__file__)),
         "mapping_recipe": sha(HERE / "measure_phi_mapping.py"), "seeds": args.seeds})

    def measure(pair: tuple[str, int]) -> dict:
        """Map one profile/seed with the shared accounting context."""
        name, seed = pair
        return measure_mapping(stage / f"{name}-{seed}", name, seed,
            [sources[name] / file for file in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")], yosys, accounting)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(measure, [(name, seed) for seed in args.seeds for name in sources]))
    keys = ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36", "DSP", "CARRY4", "mapping_delay_ps")
    summary = {name: {key: accounting.distribution([r[key] for r in rows if r["variant"] == name])
                      for key in keys} for name in sources}
    save(stage / "results.json", {"seeds": args.seeds, "samples": rows, "summary": summary})
    print(json.dumps(summary, indent=2))
    print("Descriptive signal-name seed statistics; mapping delay is not routed timing.")


if __name__ == "__main__":
    main()
