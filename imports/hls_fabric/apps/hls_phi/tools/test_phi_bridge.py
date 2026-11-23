#!/usr/bin/env python3
"""Generate two independent XLS devices and compare linked RTL with a BEAM oracle.

Run rebar3 as test compile first. Each device has its own public debug stream;
VPI carries public debug and, for the memory experiment, application streams.
The ready/valid link is RTL; no hierarchical state inspection is performed.
"""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
import json
import os
from pathlib import Path
from compiler_paths import compiler_root
import shutil
import subprocess
import time

from backend_commands import execute
from phi_device_build import build, validate_build
from backend_paths import erl_command

ROOT = Path(__file__).resolve().parents[3]


def simulate(args: argparse.Namespace) -> None:
    """Run the independent oracle, then the host against ready/valid RTL boundaries."""
    stage = args.stage / "simulation"
    attempt = 1
    while True:
        try:
            stage.mkdir()
            break
        except FileExistsError:
            attempt += 1
            stage = args.stage / f"simulation-{attempt}"
    for ident in (0, 1):
        shutil.copy(args.stage / f"device{ident}/debug/manifest.json", stage / f"device{ident}-manifest.json")
    for name in ("config.term", "bridge.json", "deployment.term"):
        shutil.copy(args.stage / "source" / name, stage)
    for path in (args.stage / "source").glob("phi_device_*_schedule.term"):
        shutil.copy(path, stage)
    for path in (args.stage / "source").glob("phi_device_*_actors.json"):
        shutil.copy(path, stage)
    (stage / "clocks.json").write_text(json.dumps({"host_period_ns": 10,
        "device_periods_ns": [2 * half for half in args.clock_halves],
        "device1_phase_ns": 1, "fifo_depth": 8}) + "\n")
    env = {key: value for key, value in os.environ.items() if not key.startswith("ERL_HLS_SIM_")}
    env.update(ERL_HLS_SIM_DIR=str(stage), ERL_HLS_SIM_TOP="phi_bridge_tb")
    fixture = "hls_phi_memory_fixture" if getattr(args, "memory", False) else "hls_bridge_phi_fixture"
    command = erl_command(args.erl_hls,
        f"ok = {fixture}:oracle(hd(init:get_plain_arguments())), halt().", stage, profile="test")
    with (stage / "oracle.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=300)
    with (stage / "simulation.log").open("w") as log:
        adapter = "partition_sim_bridge" if getattr(args, "memory", False) else "xls_sim_bridge"
        sim = subprocess.Popen(["vvp", "-M", str(args.stage), "-m", adapter,
                                str(args.stage / "phi_bridge.vvp"),
                                f"+HALF0={args.clock_halves[0]}", f"+HALF1={args.clock_halves[1]}"], cwd=stage, env=env,
                               stdout=log, stderr=subprocess.STDOUT)
        try:
            # FIFO creation precedes warmup and coordinated restart. Do not spend
            # the first debug RPC's deadline waiting for application activation.
            deadline = time.monotonic() + 60
            required = ["app_tx", "app_rx", "debug_tx", "debug_rx", "activated"]
            if getattr(args, "memory", False):
                required += [f"data{device}_{direction}" for device in (0, 1) for direction in ("tx", "rx")]
            while not all((stage / name).exists() for name in required):
                if sim.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f"simulator startup failed; see {stage / 'simulation.log'}")
                time.sleep(0.02)
            runner = "hls_phi_memory_live" if getattr(args, "memory", False) else "hls_bridge_phi_live"
            execute(erl_command(args.erl_hls,
                f"ok = {runner}:run(hd(init:get_plain_arguments())), halt().", stage, profile="test"),
                stage, "host", timeout=getattr(args, "simulation_timeout", 720))
            if sim.wait(timeout=15):
                raise RuntimeError(f"simulator failed; see {stage / 'simulation.log'}")
        finally:
            if sim.poll() is None:
                sim.terminate()
                try:
                    sim.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    sim.kill()
                    sim.wait()
    print((stage / "host.log").read_text(), end="")
    if "PASS: two-device phi bridge" not in (stage / "simulation.log").read_text():
        raise RuntimeError(f"simulator did not finish its assertions; see {stage}")
    print(f"PASS: two-device phi simulation; public observations saved in {stage}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/phi-bridge")
    parser.add_argument("--shape", type=int, nargs=2, default=[4, 2], metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--planes", choices=("x", "z"), nargs="+", default=["x"])
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--clock-halves", type=int, nargs=2, default=[3, 7],
                        metavar=("DEVICE0_NS", "DEVICE1_NS"))
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--reuse-build", action="store_true",
                        help="validate and reuse generated RTL; host runner changes need rebar compilation")
    args = parser.parse_args()
    args.erl_hls = compiler_root("test", args.erl_hls)
    if min(args.clock_halves) < 1:
        parser.error("clock half periods must be positive integer nanoseconds")
    for name in ("xls", "erl_hls", "stage"):
        setattr(args, name, getattr(args, name).resolve())
    if args.reuse_build:
        validate_build(args)
    else:
        build(args)
    if not args.build_only:
        simulate(args)
