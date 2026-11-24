#!/usr/bin/env python3
"""Build and exercise scheduled actor PIDs through real RTL and debug FIFOs.

Run rebar3 as test compile first. XLS_ROOT contains ir_converter_main, opt_main,
codegen_main and xls/dslx/stdlib. The same generated RTL exercises both carriers.
"""
import argparse
import json
import os
from pathlib import Path
from compiler_paths import compiler_resource, compiler_root, compiler_tool
from backend_paths import erl_command, debug_rtl
from backend_commands import digest, execute
from actor_build_artifacts import inputs, outputs, validate_build
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def build(args: argparse.Namespace) -> None:
    """Generate and instrument one fresh actor RTL build, rejecting changed inputs or interfaces."""
    stage, public, xls = args.stage, args.erl_hls, args.xls
    provenance = inputs(args)
    stage.mkdir(parents=True, exist_ok=False)
    source = stage / "source"
    source.mkdir()
    command = erl_command(public,
        "ok = hls_actor_pid_dslx:write(hd(init:get_plain_arguments())), halt().", source, profile="test")
    with (stage / "generation.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    for library in ("lib", "fabric"):
        for path in (public / "priv/xls" / library).glob("*.x"):
            shutil.copy(path, source)
    for path in (ROOT / "apps/hls_target/priv/xls").rglob("*.x"):
        shutil.copy(path, source)
    shutil.copy(compiler_resource(public, "hls_target", "priv/rtl/hls_1r1w_ram.v"), source)
    banks = len(json.loads((source / "actors.json").read_text())["banks"])
    configurations = subprocess.check_output([
        "bash", "-c", 'source "$1"; scheduler_ram_configurations "$2"',
        "actor-ram-config", str(ROOT / "tools/hls_fabric/scheduler_ram_configurations.sh"), str(banks)], text=True).strip()
    commands = [
        ("convert", [str(xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
                     "--dslx_path=.", f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}",
                     "actor_pid.x"], source / "actor_pid.ir"),
        ("optimize", [str(xls / "opt_main"), "actor_pid.ir"], source / "actor_pid.opt.ir"),
        ("codegen", [str(xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit",
                     "--flop_inputs=false", "--flop_outputs=true", "--use_system_verilog=false",
                     "--reset=reset", "--fifo_module=", "--module_name=actor_pid",
                     f"--ram_configurations={configurations}", "actor_pid.opt.ir"], source / "actor_pid.v")]
    for name, command, output in commands:
        execute(command, source, name, timeout=600, output=output)
    metadata = {
        "commands": [command for _, command, _ in commands],
        "tools": {name: digest(xls / name) for name in ("ir_converter_main", "opt_main", "codegen_main")},
        "sources": {path.name: digest(path) for path in sorted(source.glob("*.x"))},
        "outputs": {path.name: digest(path) for _, _, path in commands}}
    (source / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")

    # Use the public instrumentation generator and wire ABI without copying its
    # observation logic into this private project.
    topology = compiler_tool(args.erl_hls, "topology_debug")
    topology.instrument(argparse.Namespace(
        rtl=[source / "actor_pid.v", source / "actor_pid_wrapper.v", source / "hls_1r1w_ram.v"],
        top="actor_pid_wrapper", clock="clk", reset="reset", reset_active_low=False,
        output_top="hls_instrumented_application", stage=stage / "debug", yosys=args.yosys,
        actor_projection=source / "actors.json", actor_root=""))
    original = json.loads((stage / "debug/flat.json").read_text())["modules"]["actor_pid_wrapper"]
    observed = json.loads((stage / "debug/instrumented.json").read_text())["modules"]["hls_instrumented_application"]
    for section in ("ports", "netnames"):
        for name in ("hls_probe_values", "hls_actor_writes"):
            observed[section].pop(name, None)
    if original != observed:
        raise RuntimeError("debug instrumentation modified application cells or ports")
    del original, observed
    execute([args.yosys, "-Q", "-T", "-p",
             f"read_json {json.dumps(str(stage / 'debug/flat.json'))}; scc -expect 0"],
            stage, "scc")
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(public / "test/rtl" / name, stage)
    execute(["iverilog-vpi", "xls_sim_bridge.c"], stage, "vpi", timeout=60)
    execute(["iverilog", "-g2012", "-s", "actor_device_tb", "-o", str(stage / "actor.vvp"),
             str(ROOT / "apps/hls_fabric/test/rtl/actor_device_tb.sv"), str(stage / "debug/debug_top.v"),
             str(stage / "debug/instrumented.v"), *map(str, debug_rtl(public))], stage, "iverilog")
    if provenance != inputs(args):
        raise RuntimeError("RTL build inputs changed while the build was running")
    (stage / "provenance.json").write_text(json.dumps({
        "inputs": provenance, "outputs": outputs(stage)}, indent=2, sort_keys=True) + "\n")


def simulate(args: argparse.Namespace, carrier: str) -> None:
    """Run the host fixture through one carrier and retain public observations; terminate on failure."""
    board = args.stage / carrier
    board.mkdir()
    shutil.copy(args.stage / "debug/manifest.json", board)
    shutil.copy(args.stage / "source/actors.json", board)
    env = {key: value for key, value in os.environ.items() if not key.startswith("ERL_HLS_SIM_")}
    env.update(ERL_HLS_SIM_DIR=str(board), ERL_HLS_SIM_TOP="actor_device_tb")
    with (board / "simulation.log").open("w") as log:
        sim = subprocess.Popen(["vvp", "-M", str(args.stage), "-m", "xls_sim_bridge",
                                str(args.stage / "actor.vvp")], cwd=board, env=env,
                               stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while not all((board / name).exists() for name in ("app_tx", "app_rx", "debug_tx", "debug_rx")):
                if sim.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f"simulator startup failed; see {board / 'simulation.log'}")
                time.sleep(0.02)
            command = erl_command(args.erl_hls,
                "ok = hls_actor_pid_live:run(hd(init:get_plain_arguments())), halt().", board, profile="test")
            command[1:1] = ["-proto_dist", carrier]
            execute(command, board, "host", timeout=180)
            if sim.wait(timeout=10):
                raise RuntimeError(f"simulator failed; see {board / 'simulation.log'}")
        finally:
            if sim.poll() is None:
                sim.terminate()
                try:
                    sim.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    sim.kill()
                    sim.wait()
    print((board / "host.log").read_text(), end="")
    if "PASS: actor PID casts and public debug queries" not in (board / "simulation.log").read_text():
        raise RuntimeError(f"simulator did not finish its assertions; see {board}")
    print(f"PASS: {carrier} actor simulation; public observations saved in {board}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", type=Path)
    parser.add_argument("--erl-hls", type=Path, help="Compiler override; defaults to the built test profile.")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/actor-pids")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--carriers", choices=("inet_tcp", "hls_local"), nargs="+", default=["inet_tcp", "hls_local"])
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--reuse-build", action="store_true", help="reuse this invocation's generated RTL for host-test iteration")
    arguments = parser.parse_args()
    arguments.erl_hls = compiler_root("test", arguments.erl_hls)
    for name in ("xls", "erl_hls", "stage"):
        setattr(arguments, name, getattr(arguments, name).resolve())
    if not arguments.reuse_build:
        build(arguments)
    else:
        validate_build(arguments)
    if not arguments.build_only:
        for selected_carrier in arguments.carriers:
            simulate(arguments, selected_carrier)
