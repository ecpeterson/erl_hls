#!/usr/bin/env python3
"""Compare the four-actor fixture with direct and addressed ingress using XC7.

Both variants include identical scheduler configuration and public debug hooks.
The direct baseline accepts an arbitrary SpatialFrame, so the integrated delta
includes downstream optimization enabled by the addressed protocol's constants.
This is a small-fixture synthesis measurement, not placed-and-routed timing.
"""
import argparse
import importlib
import json
from pathlib import Path
from backend_paths import PUBLIC
import shutil
import statistics
import subprocess
import sys

import test_actor_rtl as fixture


def measure(args):
    fixture.validate_build(args)
    area = args.stage / "area"
    area.mkdir()
    source = area / "baseline"
    source.mkdir()
    for path in (args.stage / "source").iterdir():
        if path.suffix in (".x", ".v", ".json"):
            shutil.copy(path, source)
    original = json.loads((source / "build.json").read_text())
    commands = [[part.replace("actor_pid", "actor_pid_baseline") for part in command]
                for command in original["commands"]]
    for suffix, command in zip((".ir", ".opt.ir", ".v"), commands):
        fixture.execute(command, source, "baseline" + suffix, timeout=600,
                        output=source / ("actor_pid_baseline" + suffix))
    sys.path.insert(0, str(args.erl_hls / "tools"))
    topology = importlib.import_module("topology_debug")
    topology.instrument(argparse.Namespace(
        rtl=[source / "actor_pid_baseline.v", source / "actor_pid_baseline_wrapper.v",
             source / "hls_1r1w_ram.v"], top="actor_pid_baseline_wrapper", clock="clk",
        reset="reset", reset_active_low=False, output_top="hls_instrumented_application",
        stage=area / "baseline-debug", yosys=args.yosys,
        actor_projection=source / "actors.json", actor_root=""))
    map_variants(args, area, commands)


def map_variants(args, area, commands):
    sys.path.insert(0, str(args.erl_hls / "tools"))
    topology = importlib.import_module("topology_debug")
    accounting = importlib.import_module("measure_topology_debug")
    debug_sources = [args.erl_hls / "priv/rtl/debug" / name for name in (
        "hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v")]
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()
    results, provenance = [], {"yosys": version, "script": fixture.digest(Path(__file__)),
                              "baseline_commands": commands, "variants": {}}
    for label, directory in (("direct", area / "baseline-debug"), ("addressed", args.stage / "debug")):
        rtl = [directory / "debug_top.v", *debug_sources]
        application = directory / "instrumented.json"
        provenance["variants"][label] = {str(path): fixture.digest(path) for path in [application, *rtl]}
        for seed in (1, 2):
            name = f"{label}-{seed}"
            # The simulation Verilog is exported with -noattr. Reading that
            # would discard ram_style and silently change memory inference.
            script = "read_json " + topology.quote(application) + "\n"
            script += "read_verilog -sv " + " ".join(map(topology.quote, rtl)) + "\n"
            script += "hierarchy -check -top hls_debug_application\nproc\nflatten\nopt\n"
            script += f"rename -scramble-name -seed {seed}\n"
            script += "synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf -top hls_debug_application\n"
            script += "check -assert\nscc -expect 0\n"
            script += f"tee -o {topology.quote(area / (name + '.json'))} stat -json -tech xilinx\n"
            path = area / (name + ".ys")
            path.write_text(script)
            fixture.execute([args.yosys, "-Q", "-T", "-s", str(path)], area, name, timeout=600)
            cells = json.loads((area / (name + ".json")).read_text())["design"]["num_cells_by_type"]
            result = {"variant": label, "seed": seed, **accounting.cell_counts(cells)}
            results.append(result)
            print(result, flush=True)
            (area / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    summary = {label: {key: {"best": min(values), "mean": statistics.mean(values),
                            "variance": statistics.pvariance(values), "worst": max(values)}
                       for key in ("LUT", "LUT_logic", "LUT_RAM", "FF", "RAMB18", "RAMB36")
                       for values in [[result[key] for result in results if result["variant"] == label]]}
               for label in ("direct", "addressed")}
    (area / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (area / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--yosys", default="yosys")
    arguments = parser.parse_args()
    for name in ("xls", "stage", "erl_hls"):
        setattr(arguments, name, getattr(arguments, name).resolve())
    measure(arguments)
