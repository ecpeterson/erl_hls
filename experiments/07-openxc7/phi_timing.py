#!/usr/bin/env python3
"""Map and route the generated D3 decoder profile on the pinned native openXC7 flow."""
import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
PART = "xc7z100ffg900-2"
TOP = "phi_timing_harness"
CORE = "phi_decoder_profile_top"
TIMING_MODEL = ("Partial-path estimate from pinned openXC7: BRAM and registered DSP timing are excluded; "
                "flip-flop setup/hold/clock-to-Q use fixed 0.1 ns values; shared zynq7 tables do not select "
                "a speed grade. This is not a design-wide maximum clock or vendor signoff.")


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def tool_files(binary):
    # Apio bin/ commands are shell launchers; fingerprint their real executable
    # and package identity as well. A normal system binary needs no such wrapper.
    paths = [binary]
    package = binary.parent.parent
    if (package / "BUILD-INFO.json").exists():
        paths += [package / "BUILD-INFO.json", package / "libexec" / binary.name]
    if binary.name == "yosys":
        abc = package / "libexec/yosys-abc" if (package / "BUILD-INFO.json").exists() else binary.with_name("yosys-abc")
        if abc.exists():
            paths.append(abc)
    return paths


def command(argv, stage, label, env=None):
    print(label, flush=True)
    with (stage / f"{label}.console").open("w") as log:
        subprocess.run(list(map(str, argv)), cwd=stage, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)


def yosys(script, stage, label, binary):
    path = stage / f"{label}.ys"
    path.write_text(script)
    command([binary, "-T", "-Q", "-l", stage / f"{label}.log", "-s", path], stage, label)


def quote(path):
    return json.dumps(str(path))


def simulate(args):
    command(["iverilog", "-g2012", "-s", "phi_timing_tb", "-o", args.stage / "harness.vvp",
             HERE / "phi_timing_tb.sv", HERE / "phi_timing_harness.v",
             *[args.rtl / name for name in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")]],
            args.stage, "simulate-compile")
    command(["vvp", args.stage / "harness.vvp"], args.stage, "simulate")
    print((args.stage / "simulate.console").read_text(), end="")


def load_profile(rtl):
    build = json.loads((rtl / "phi_decoder_profile.build.json").read_text())
    expected = {"width": 3, "height": 3, "shards_per_plane": 3,
                "pipeline_stages": 2, "initiation_interval": 1, "delay_model": "unit",
                "flop_inputs": False, "flop_outputs": True}
    if build["schema"] != 1 or build["profile"] != expected:
        raise ValueError("expected the D3, three-shard, two-stage, II=1 decoder profile")
    for name in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v"):
        if build["rtl"].get(name) != sha(rtl / name):
            raise ValueError(f"profile RTL changed since compilation: {name}")
    return build


def signatures(cells):
    return Counter((cell["type"], json.dumps(cell["parameters"], sort_keys=True))
                   for cell in cells if cell["type"] != "$scopeinfo")


def timing_coverage(cells):
    """Scope of nextpnr-xilinx 68aeeb3's getPortTimingClass/getPortClockingInfo.

    These counts make its omissions visible; they do not prove arc completeness
    within the primitives it does model. See phi-timing.md for the source audit.
    """
    omitted = Counter()
    combinational_dsps = 0
    for cell in cells:
        kind = cell["type"]
        if kind == "DSP48E1":
            registers = ("AREG", "BREG", "CREG", "DREG", "ADREG", "MREG", "PREG", "ACASCREG", "BCASCREG")
            if any(int(cell["parameters"].get(p, "0"), 2) for p in registers):
                omitted["registered_DSP48E1"] += 1
            else:
                combinational_dsps += 1
        elif kind.startswith(("RAM", "SRL")):
            omitted[kind] += 1
    return {"omitted_sequential_primitives": dict(omitted),
            "combinational_dsps_with_coarse_delay": combinational_dsps,
            "design_wide_clock_validated": False}


def check_assembly(stage):
    core = json.loads((stage / "core.json").read_text())["modules"][CORE]
    original = signatures(core["cells"].values())
    core_types = Counter(c["type"] for c in core["cells"].values() if c["type"] != "$scopeinfo")
    del core
    design = json.loads((stage / "mapped.json").read_text())["modules"][TOP]
    retained = signatures(c for name, c in design["cells"].items()
                          if name.startswith(("decoder.", "$flatten\\decoder.")))
    if retained != original:
        raise ValueError("mapped decoder cells changed during harness assembly")
    buffers = [c for c in design["cells"].values() if c["type"] == "BUFG"]
    if len(buffers) != 1:
        raise ValueError("expected one global clock buffer")
    clock = buffers[0]["connections"]["O"]
    clock_ports = {"FDRE": ["C"], "FDSE": ["C"], "DSP48E1": ["CLK"],
                   "RAMB18E1": ["CLKARDCLK", "CLKBWRCLK"], "RAMB36E1": ["CLKARDCLK", "CLKBWRCLK"],
                   "RAM32M": ["WCLK"], "RAM64M": ["WCLK"], "SRL16E": ["CLK"], "SRLC32E": ["CLK"]}
    for cell in design["cells"].values():
        for port in clock_ports.get(cell["type"], []):
            bits = cell["connections"][port]
            if any(isinstance(bit, int) for bit in bits) and bits != clock:
                raise ValueError(f"clock bypasses BUFG: {cell['type']}.{port}")
    return {"retained_decoder_cells": sum(original.values()), "decoder_cells": dict(core_types),
            "assembled_cells": dict(Counter(c["type"] for c in design["cells"].values()
                                         if c["type"] != "$scopeinfo")), "single_global_clock": True,
            "timing_coverage": timing_coverage(design["cells"].values())}


def mapped_stage(stage, label, script, inputs, outputs, binary):
    files = [*inputs, *tool_files(binary)]
    key = {"files": {str(p): sha(p) for p in files}, "script": script}
    stamp = stage / f"{label}-completed.json"
    if stamp.exists():
        old = json.loads(stamp.read_text())
        if old["inputs"] == key and all((stage / p).exists() and sha(stage / p) == old["outputs"].get(p)
                                         for p in outputs):
            print(f"Using verified {label}", flush=True)
            return old
    stamp.unlink(missing_ok=True)
    yosys(script, stage, label, binary)
    if key["files"] != {str(p): sha(p) for p in files}:
        raise ValueError(f"{label}: inputs changed while mapping")
    result = {"inputs": key, "outputs": {p: sha(stage / p) for p in outputs}}
    save(stamp, result)
    return result


def map_design(args, binaries):
    stage, rtl = args.stage, args.rtl
    inputs = [rtl / name for name in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")]
    core = mapped_stage(stage, "map-core",
        "read_verilog -sv " + " ".join(map(quote, inputs)) + "\n"
        f"hierarchy -check -top {CORE}\n"
        f"synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top {CORE}\n"
        "check -assert\nscc -expect 0\ntee -o core-stat.json stat -json\nwrite_json core.json\n",
        inputs, ["core.json", "core-stat.json"], binaries["yosys"])
    mapped_stage(stage, "core-interface",
        f"read_json core.json\nblackbox {CORE}\nsetattr -set clkbuf_sink 1 ={CORE}/aclk\n"
        f"select -clear\nselect ={CORE}\nwrite_verilog -selected -blackboxes core-stub.v\n",
        [stage / "core.json"], ["core-stub.v"], binaries["yosys"])
    # Only the small harness is mapped here. The already mapped core is restored
    # afterwards, preventing constants or observability changes at the boundary
    # from silently resynthesizing a smaller application.
    assembly = mapped_stage(stage, "map-harness",
        f"read_verilog -lib core-stub.v\nread_verilog {quote(HERE / 'phi_timing_harness.v')}\n"
        f"synth_xilinx -flatten -abc9 -nosrl -family xc7 -top {TOP}\n"
        "design -stash harness\nread_json core.json\n"
        "read_verilog -lib -nowb -overwrite +/xilinx/cells_sim.v +/xilinx/cells_xtra.v\n"
        f"design -copy-from harness {TOP}\n"
        f"hierarchy -check -top {TOP}\n"
        "flatten\nopt_clean\ncheck -assert\nscc -expect 0\n"
        "tee -o mapped-stat.json stat -json\nwrite_json mapped.json\n",
        [stage / "core-stub.v", stage / "core.json", HERE / "phi_timing_harness.v"],
        ["mapped.json", "mapped-stat.json"], binaries["yosys"])
    result = {"core": core, "assembly": assembly,
              "netlist_sha256": sha(stage / "mapped.json"), **check_assembly(stage)}
    save(stage / "mapping.json", result)
    return result


def critical_paths(log):
    # This pinned nextpnr writes an empty JSON critical_paths array. Its log has
    # the detailed paths; keep the last (post-route) report for each clock.
    paths = {}
    pattern = r"Info: Critical path report for clock '([^']+)'[^\n]*:\n.*?Info: ([0-9.]+) ns logic, ([0-9.]+) ns routing"
    for match in re.finditer(pattern, log, re.S):
        paths[match[1]] = {"logic_ns": float(match[2]), "routing_ns": float(match[3]), "text": match[0]}
    return paths


def warning_summary(log):
    groups = {}
    for line in log.splitlines():
        if not line.startswith("Warning:"):
            continue
        unused = re.fullmatch(r"Warning: Port (\S+) connected to net .* on cell .* has no connections", line)
        kind = ("Unconnected port " + re.sub(r"\d+$", "", unused[1])) if unused else line[9:].strip()
        group = groups.setdefault(kind, {"count": 0, "example": line})
        group["count"] += 1
    return groups


def summarize(reports):
    if not reports:
        raise ValueError("no completed routes")
    frequencies = [r["achieved_mhz"] for r in reports]
    if not all(math.isfinite(f) and f > 0 for f in frequencies):
        raise ValueError("invalid achieved frequency")
    return {"samples": len(frequencies), "mean_mhz": statistics.mean(frequencies),
            "variance_mhz_squared": statistics.pvariance(frequencies),
            "best_mhz": max(frequencies), "worst_mhz": min(frequencies)}


def completion_valid(run, expected):
    stamp = run / "completed.json"
    if not stamp.exists():
        return False
    completed = json.loads(stamp.read_text())
    return completed.get("inputs") == expected and all(
        (run / name).exists() and sha(run / name) == completed.get("outputs", {}).get(name)
        for name in ("nextpnr.json", "nextpnr.log"))


def route_key(args, binaries, mapping):
    return {"netlist": mapping["netlist_sha256"],
            "chipdb": sha(args.stage / "device/chipdb/xc7z100ffg900.bin"),
            "xdc": sha(args.stage / "timing.xdc"),
            "nextpnr": {str(p): sha(p) for p in tool_files(binaries["nextpnr"])},
            "part": PART, "frequency": args.frequency, "router": "router2"}


def timed_path(data, log):
    if len(data["fmax"]) != 1:
        raise ValueError("expected exactly one timed clock")
    clock, timing = next(iter(data["fmax"].items()))
    paths = critical_paths(log)
    if clock in paths:
        path_clock = clock
    elif len(paths) == 1:
        # This nextpnr can use the internal clock name in JSON and its aliased
        # net name in the log. Accept only an unambiguous single-clock report.
        path_clock = next(iter(paths))
    else:
        raise ValueError("missing or ambiguous detailed critical path")
    return {"clock": clock, "critical_path_clock": path_clock,
            "achieved_mhz": timing["achieved"], "target_mhz": timing["constraint"],
            "critical_path": paths[path_clock], "utilization": data["utilization"],
            "warnings": warning_summary(log)}


def report(args, binaries, mapping):
    runs = []
    key = route_key(args, binaries, mapping)
    for seed in args.seeds:
        run = args.stage / f"seed-{seed}"
        if not completion_valid(run, {**key, "seed": seed}):
            raise ValueError(f"seed {seed}: incomplete, modified, or stale route")
        data = json.loads((run / "nextpnr.json").read_text())
        timing = timed_path(data, (run / "nextpnr.log").read_text())
        if not math.isclose(timing["target_mhz"], args.frequency):
            raise ValueError(f"seed {seed}: wrong clock constraint")
        runs.append({"seed": seed, **timing})
    summary = {"part": PART, "target_mhz": args.frequency, "mapping": mapping,
               "profile_build": load_profile(args.rtl),
               "statistics": summarize(runs), "runs": runs, "route_inputs": key,
               "timing_model": TIMING_MODEL}
    save(args.stage / "report.json", summary)
    lines = ["# D3 decoder physical timing", "", summary["timing_model"], "",
             f"Target: `{PART}`, {args.frequency:g} MHz. Decoder-only D3, three shards per phi plane.", "",
             "| Seed | Partial-path MHz | Logic ns | Routing ns |", "| --- | ---: | ---: | ---: |"]
    lines += [f"| {r['seed']} | {r['achieved_mhz']:.2f} | {r['critical_path']['logic_ns']:.2f} | {r['critical_path']['routing_ns']:.2f} |" for r in runs]
    s = summary["statistics"]
    lines += ["", f"Mean {s['mean_mhz']:.2f} MHz; population variance {s['variance_mhz_squared']:.4f} MHz²; best {s['best_mhz']:.2f} MHz; worst {s['worst_mhz']:.2f} MHz.", "",
              f"All {mapping['retained_decoder_cells']:,} mapped decoder cells survive harness assembly; sequential cells use one BUFG.", "",
              "Excluded sequential primitive timing: `" + json.dumps(mapping["timing_coverage"]["omitted_sequential_primitives"], sort_keys=True) + "`.", "",
              "Physical utilization is in `report.json`. nextpnr's SLICE_LUTX denominator counts O5/O6 BELs, not physical LUT packages."]
    for r in runs:
        lines += ["", f"## Seed {r['seed']} critical path", "", "```text", r["critical_path"]["text"], "```",
                  "", "Warnings (full text in the route log):", ""]
        lines += [f"- {kind}: {group['count']}" for kind, group in r["warnings"].items()] or ["None."]
    (args.stage / "report.md").write_text("\n".join(lines) + "\n")
    print(TIMING_MODEL)
    print(json.dumps(summary["statistics"], indent=2))


def route(args, binaries, mapping):
    env = dict(os.environ, ERL_HLS_OPENXC7_BUILD_ROOT=str(args.stage / "device"))
    command(["bash", "-c", 'set -euo pipefail; source "$1"; prepare_openxc7; make_chipdb "$2"',
             "bash", HERE / "openxc7_common.sh", PART], args.stage, "device", env)
    chipdb = args.stage / "device/chipdb/xc7z100ffg900.bin"
    xdc = args.stage / "timing.xdc"
    xdc.write_text("# Compile-harness pins, not a board assignment.\n"
                   "set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS18} [get_ports clock]\n"
                   "set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS18} [get_ports activity]\n"
                   f"create_clock -period {1000/args.frequency:.9f} [get_ports clock]\n")
    key = route_key(args, binaries, mapping)
    for seed in args.seeds:
        run = args.stage / f"seed-{seed}"
        run.mkdir(exist_ok=True)
        stamp = run / "completed.json"
        expected = {**key, "seed": seed}
        if completion_valid(run, expected):
            print(f"Using verified seed {seed}", flush=True)
            continue
        stamp.unlink(missing_ok=True)
        command([binaries["nextpnr"], "--chipdb", chipdb, "--json", args.stage / "mapped.json",
                 "--xdc", xdc, "--freq", args.frequency, "--seed", seed, "--router", "router2",
                 "--timing-allow-fail", "--report", run / "nextpnr.json", "--log", run / "nextpnr.log"],
                run, "route")
        save(stamp, {"inputs": expected,
                     "outputs": {name: sha(run / name) for name in ("nextpnr.json", "nextpnr.log")}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, help="prepared, compiled decoder-profile RTL directory")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3])
    parser.add_argument("--frequency", type=float, default=100)
    parser.add_argument("--phase", choices=("all", "simulate", "map", "route", "report"), default="all")
    args = parser.parse_args()
    if args.frequency <= 0 or not math.isfinite(args.frequency) or len(set(args.seeds)) != len(args.seeds) or min(args.seeds) < 1:
        parser.error("frequency must be positive and seeds must be unique positive integers")
    args.rtl, args.stage = args.rtl.resolve(), args.stage.resolve()
    args.stage.mkdir(parents=True, exist_ok=True)
    apio = Path(os.environ.get("ERL_HLS_APIO_HOME", HERE / ".apio"))
    binaries = {"yosys": apio / "packages/oss-cad-suite/bin/yosys", "nextpnr": apio / "packages/openxc7/bin/nextpnr-xilinx"}
    load_profile(args.rtl)
    if args.phase in ("all", "simulate"):
        simulate(args)
    if args.phase == "simulate":
        return
    mapping = map_design(args, binaries)
    if args.phase in ("all", "route"):
        route(args, binaries, mapping)
    if args.phase in ("all", "route", "report"):
        report(args, binaries, mapping)


if __name__ == "__main__":
    main()
