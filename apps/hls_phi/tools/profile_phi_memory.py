#!/usr/bin/env python3
"""Measure cached phi devices with a zero-simulated-time Erlang host and public port observations."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
import json
import os
import re
from pathlib import Path
from compiler_paths import compiler_root
import shutil
import subprocess
import time

from backend_commands import digest, execute
from backend_paths import ROOT, debug_rtl, erl_command
from phi_build_artifacts import read_bridge_build
from phi_service_metrics import summarize
from phi_service_analysis import analyze
from phi_cycle_trace import plan as cycle_plan, read as read_cycles, verify_queries


def profile(args: argparse.Namespace) -> None:
    """Validate immutable device artifacts, compile only the testbench, and check the selected oracle."""
    provenance_path = args.build / "provenance.json"
    provenance = read_bridge_build(args.build)
    args.stage.mkdir(parents=True, exist_ok=False)
    for name in ("config.term", "deployment.term", "bridge.json"):
        shutil.copy(args.build / "source" / name, args.stage)
    execute(erl_command(args.erl_hls,
        "[Stage] = init:get_plain_arguments(), ok = hls_phi_memory_fixture:oracle(Stage), "
        "ok = hls_phi_memory_profile:describe(Stage), halt().", args.stage, profile="test"),
        args.stage, "oracle", timeout=60)
    catalog = json.loads((args.stage / "lane-catalog.json").read_text())
    plan = {}
    for device in (0, 1):
        manifest = args.build / f"device{device}/debug/manifest.json"
        shutil.copy(manifest, args.stage / f"device{device}-manifest.json")
        resources = json.loads(manifest.read_text())["resources"]
        families = set()
        # One lane per payload-schema set keeps data, field and query traffic visible
        # when placement changes their wire IDs.
        lane_groups = {}
        for lane in catalog:
            if lane["device"] == device:
                schemas = tuple(sorted(s["name"] for s in lane["schemas"]))
                lane_groups.setdefault(schemas, lane["lane"])
        selected = []
        for resource in resources:
            name, kind = resource["name"], resource["kind"]
            actor = re.search(r"\{actor,\{family,([^,]+),", name)
            fifo = re.search(r"fifo__(outgoing(?:_\d+)?|received(?:_\d+)?|link_returned|link_credit)__(\d+)_$", name)
            if kind == "actor" and actor and actor[1] not in families:
                families.add(actor[1])
                selected.append(resource["id"])
            elif kind == "fifo" and fifo and int(fifo[2]) in lane_groups.values():
                selected.append(resource["id"])
            elif kind == "fifo" and name.endswith("fifo__transmit_words_"):
                selected.append(resource["id"])
        plan[str(device)] = [] if args.no_debug else selected
    if args.probe_plan:
        plan = json.loads(args.probe_plan.read_text())
    (args.stage / "probes.json").write_text(json.dumps(plan, indent=2)+"\n")
    for name in ("host_requests", "host_responses"):
        os.mkfifo(args.stage / name)
    sources = [ROOT / "apps/hls_phi/test/rtl/phi_bridge_tb.sv", ROOT / "apps/hls_target/priv/rtl/hls_async_fifo.v"]
    sources += [args.build / f"device{d}/debug" / name for d in (0, 1)
                for name in ("debug_top.v", "instrumented.v")]
    sources += debug_rtl(args.erl_hls)
    hardware = [*sources, ROOT / "apps/hls_phi/test/rtl/phi_memory_profile.svh",
                ROOT / "apps/hls_phi/test/rtl/phi_memory_transport.svh", ROOT / "apps/hls_phi/test/rtl/phi_link_delay.svh", args.build / "phi_devices.vh"]
    hardware_hashes = {str(p): digest(p) for p in hardware}
    simulator = subprocess.check_output(["iverilog", "-V"], stderr=subprocess.DEVNULL, text=True).splitlines()[0]
    if args.reuse_testbench:
        previous = json.loads((args.reuse_testbench / "profile-inputs.json").read_text())
        cached = args.reuse_testbench / "profile.vvp"
        if (previous["hardware_sources"] != hardware_hashes or previous["simulator"] != simulator
                or previous["vvp_sha256"] != digest(cached)):
            raise ValueError("cached testbench differs from current hardware sources/tools")
        (args.stage / "profile.vvp").symlink_to(cached.resolve())
    else:
        execute(["iverilog", "-g2012", "-s", "phi_bridge_tb", "-DPHI_MEMORY", "-DPHI_PROFILE",
                 "-I", str(args.build), "-I", str(ROOT / "apps/hls_fabric/test/rtl"), "-I", str(ROOT / "apps/hls_phi/test/rtl"), "-o", str(args.stage / "profile.vvp"),
                 *map(str, sources)], args.stage, "iverilog", timeout=300)
    if hardware_hashes != {str(p): digest(p) for p in hardware}:
        raise ValueError("hardware sources changed during testbench compilation")
    harness = [Path(__file__), ROOT / "apps/hls_phi/tools/phi_service_metrics.py", ROOT / "apps/hls_phi/tools/phi_cycle_trace.py",
               ROOT / "apps/hls_phi/tools/phi_service_analysis.py",
               ROOT / "apps/hls_phi/test/rtl/phi_service_trace.c",
               ROOT / "apps/hls_phi/test/hls_phi_memory_profile.erl", ROOT / "apps/hls_phi/test/hls_phi_profile_debug.erl",
               ROOT / "apps/hls_phi/test/hls_phi_memory_metrics.erl", ROOT / "apps/hls_phi/test/hls_phi_memory_fixture.erl", args.stage / "probes.json"]
    record = {"distance": provenance["inputs"]["config"]["shape"][0], "build": str(args.build), "build_provenance_sha256": digest(provenance_path),
              "placement": provenance["inputs"]["config"].get("placement", "direct"),
              "reductions": provenance["inputs"]["config"].get("reductions", "ordinary"),
              "device_periods_ns": [2*n for n in args.clock_halves], "host_period_ns": 10,
              "periodic_stalls": args.stalls, "host_model": "zero-simulated-time ordinary Erlang reducer",
              "actor_channels": args.actors,
              "hardware_sources": hardware_hashes,
              "host_sources": {str(p): digest(p) for p in harness},
              "simulator": simulator,
              "vvp_sha256": digest(args.stage / "profile.vvp")}
    cycle_plan(args.build, args.stage, all_channels=args.actors)
    execute(["iverilog-vpi", str(ROOT / "apps/hls_phi/test/rtl/phi_service_trace.c")], args.stage, "cycle-vpi", timeout=60)
    record["cycle_plan_sha256"] = digest(args.stage / "cycle-probes.txt")
    record["vpi_sha256"] = digest(args.stage / "phi_service_trace.vpi")
    (args.stage / "profile-inputs.json").write_text(json.dumps(record, indent=2) + "\n")
    started = time.monotonic()
    with (args.stage / "host.log").open("w") as host_log, (args.stage / "simulation.log").open("w") as sim_log:
        host = subprocess.Popen(erl_command(args.erl_hls,
            "ok = hls_phi_memory_profile:run(hd(init:get_plain_arguments())), halt().", args.stage, profile="test"),
            cwd=ROOT, stdout=host_log, stderr=subprocess.STDOUT)
        sim = subprocess.Popen(["vvp", "-M", str(args.stage), "-m", "phi_service_trace", str(args.stage / "profile.vvp"),
            f"+HALF0={args.clock_halves[0]}", f"+HALF1={args.clock_halves[1]}", f"+STALLS={int(args.stalls)}"],
            cwd=args.stage, stdout=sim_log, stderr=subprocess.STDOUT)
        try:
            while host.poll() is None or sim.poll() is None:
                if host.poll() not in (None, 0) or sim.poll() not in (None, 0):
                    raise RuntimeError(f"profile failed; see {args.stage}")
                if time.monotonic()-started > args.timeout:
                    raise TimeoutError(f"profile exceeded {args.timeout}s; see {args.stage}")
                time.sleep(0.1)
        finally:
            for process in (host, sim):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    for name in ("host", "simulation"):
        contents = (args.stage / f"{name}.log").read_text()
        if "PASS:" not in contents:
            raise RuntimeError(f"{name} did not complete its checks")
        print(contents, end="")
    summarize(args.stage, [2*n for n in args.clock_halves])
    _, histories = read_cycles(args.stage)
    verify_queries(args.stage, histories)
    analyze(args.stage)
    print(f"Profile finished in {time.monotonic()-started:.1f}s: {args.stage}")


def main() -> None:
    """Select an already validated device build and a fresh experiment directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--clock-halves", type=int, nargs=2, default=[3, 7])
    parser.add_argument("--stalls", action="store_true")
    parser.add_argument("--actors", action="store_true", help="capture every channel for actor work reconstruction")
    parser.add_argument("--no-debug", action="store_true", help="disable otherwise passive periodic occupancy queries")
    parser.add_argument("--probe-plan", type=Path, help="explicit per-device resource ID lists as JSON")
    parser.add_argument("--reuse-testbench", type=Path, help="reuse a verified prior profile compilation")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    if min(args.clock_halves) < 1 or args.timeout < 1:
        parser.error("clock half periods and timeout must be positive")
    for name in ("build", "stage", "erl_hls"):
        setattr(args, name, getattr(args, name).resolve())
    profile(args)


if __name__ == "__main__":
    main()
