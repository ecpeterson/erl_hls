#!/usr/bin/env python3
"""Generate two independent XLS devices and compare linked RTL with a BEAM oracle.

Run rebar3 as test compile first. Each device has its own public debug stream;
VPI carries public debug and, for the memory experiment, application streams.
The ready/valid link is RTL; no hierarchical state inspection is performed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib
import json
import os
from pathlib import Path
from compiler_paths import PUBLIC
import re
import shutil
import subprocess
import sys
import time

from transport_codegen import specialize
from backend_commands import digest, execute
from backend_paths import erl_command

ROOT = Path(__file__).resolve().parents[1]


def inputs(args: argparse.Namespace) -> dict:
    """Fingerprint compiler inputs, including the selected full-application fixture."""
    files = {}
    sources = (
        ("private", ROOT, ("src/**/*.erl", "test/hls_bridge_phi_fixture.erl",
                           "test/rtl/phi_bridge_tb.sv", "test/rtl/phi_link_delay.svh", "test/rtl/phi_memory_transport.svh",
                           "test/rtl/partition_sim_bridge.c",
                           "test/hls_phi_memory_fixture.erl", "test/hls_phi_board_geometry.erl", "tools/test_phi_memory.py",
                           "rtl/hls_async_fifo.v", "priv/xls/**/*.x", "tools/phi_scheduler_rams.sh",
                           "tools/test_phi_bridge.py", "tools/test_actor_rtl.py", "tools/backend_commands.py",
                           "tools/backend_paths.py", "tools/compiler_paths.py", "tools/transport_codegen.py",
                           "rebar.config", "rebar.lock")),
        ("public", args.erl_hls, ("src/**/*.erl", "src/examples/phi_decoder/phi_field.x",
                                  "include/**/*.hrl", "priv/xls/**/*.x",
                                  "priv/rtl/debug/*.v", "tools/topology_debug*.py",
                                  "priv/rtl/hls_1r1w_ram.v",
                                  "test/rtl/xls_sim_bridge.c", "test/rtl/xls_sim_axis.h")),
        ("stdlib", args.xls / "xls/dslx/stdlib", ("**/*.x",)),
    )
    for label, root, patterns in sources:
        for pattern in patterns:
            for path in root.glob(pattern):
                files[f"{label}/{path.relative_to(root)}"] = digest(path)
    tools = {name: digest(args.xls / name)
             for name in ("ir_converter_main", "opt_main", "codegen_main")}
    for name, executable in (("yosys", args.yosys), ("iverilog", "iverilog"),
                             ("iverilog-vpi", "iverilog-vpi")):
        path = Path(shutil.which(executable) or executable).resolve()
        tools[name] = {"path": str(path), "sha256": digest(path)}
    return {"files": files, "tools": tools, "config": {"shape": args.shape, "planes": args.planes,
        "memory": getattr(args, "memory", False), "memory_case": getattr(args, "memory_case", "d3"),
        "placement": getattr(args, "placement", "direct"), "reductions": getattr(args, "reductions", "ordinary"),
        "devices_only": getattr(args, "devices_only", False)}}


def outputs(stage: Path, *, devices_only: bool = False) -> dict:
    """Hash generated devices; require the bridge adapter unless the build explicitly omits it."""
    paths = [path for directory in ("source", "device0", "device1")
             for path in (stage / directory).rglob("*")
             if path.is_file() and path.suffix in (".x", ".v", ".vh", ".json", ".ir", ".term")]
    paths += [stage / "phi_devices.vh", *stage.glob("*.vpi")]
    if not devices_only:
        paths.append(stage / "phi_bridge.vvp")
    return {str(path.relative_to(stage)): digest(path) for path in sorted(paths)}


def read_build(stage: Path) -> dict:
    """Return the build record only when all selected device/harness artifact hashes still match."""
    saved = json.loads((stage / "provenance.json").read_text())
    devices_only = saved["inputs"]["config"].get("devices_only", False)
    if saved["outputs"] != outputs(stage, devices_only=devices_only):
        raise ValueError("generated RTL or instrumentation changed; rebuild before simulation")
    return saved


def validate_build(args: argparse.Namespace) -> None:
    """Reject reuse when selected inputs, device files or required simulation artifacts differ."""
    if read_build(args.stage)["inputs"] != inputs(args):
        raise ValueError("RTL build inputs changed; use a fresh --stage without --reuse-build")


def external_ports(device):
    for entry in device["externals"]:
        port = entry["port"]
        match = re.fullmatch(r"external_(\d+)_out", port)
        if not match:
            raise ValueError(f"unsupported external port {port!r}")
        yield int(match[1]), port


def device_wrapper(device: dict) -> str:
    """Only connectivity is generated; all link behavior lives in static DSLX."""
    rx, tx = device["rx_lanes"], device["tx_lanes"]
    if not (0 < rx <= 32768 and 0 < tx <= 32768):
        raise ValueError("the two-device witness requires 1..32768 lanes in both directions")
    graph = device["graph"]
    ports = ["link_0_in: chan<axis::Beat> in", "link_0_out: chan<axis::Beat> out",
             "fault_0_out: chan<u32> out"]
    ports += [f"{port}: chan<axis::Frame> out" for _, port in external_ports(device)]
    ports += [f"{entry['port']}: chan<hls_spatial_router::SpatialFrame> in"
              for entry in device.get("ingresses", [])]
    names = [declaration.split(":")[0] for declaration in ports]
    graph_args = ["received_c", "outgoing_p", *names[3:]]
    lines = ["// Generated connectivity for one independently compiled device.",
             "import axis;", "import hls_credit_link;", "import hls_spatial_router;", f"import {graph};", "", "pub proc Top {"]
    lines += [f"    {port};" for port in ports]
    lines += [f"    config({', '.join(ports)}) {{",
              f'        let (received_p, received_c) = chan<axis::Frame, u32:1>[{rx}]("received");',
              f'        let (outgoing_p, outgoing_c) = chan<axis::Frame, u32:1>[{tx}]("outgoing");',
              f"        spawn {graph}::Top({', '.join(graph_args)});",
              f"        spawn hls_credit_link::Bridge<u32:{tx}, u32:{rx}, u16:18512>(",
              "            link_0_in, link_0_out, outgoing_c, received_p, fault_0_out);",
              f"        ({', '.join(names)})", "    }", "    init { () }",
              "    next(state: ()) { state }", "}", ""]
    return "\n".join(lines)


def testbench_connections(devices: list[dict]) -> str:
    """Bind public ports; memory controls and sinks obey the same device clock."""
    lines = ["// Generated only from the checked deployment's public ports."]
    for device in devices:
        ident = device["id"]
        prefix = f"device{ident}"
        ports = [f".clk(clk{ident})", f".reset(reset{ident})",
                 f"._link_0_in(link{1-ident}{ident}_data)",
                 f"._link_0_in_vld(link{1-ident}{ident}_valid)",
                 f"._link_0_in_rdy(link{1-ident}{ident}_ready)",
                 f"._link_0_out(tx{ident}_data)", f"._link_0_out_vld(tx{ident}_valid)",
                 f"._link_0_out_rdy(tx{ident}_ready)",
                 f"._fault_0_out(fault{ident})", f"._fault_0_out_vld(fault{ident}_valid)",
                 "._fault_0_out_rdy(1'b1)"]
        ports += [f".{direction}_dbg_{signal}({direction}_{prefix}_{signal})"
                  for direction, signals in (("s", ("tdata", "tkeep", "tlast", "tvalid", "tready")),
                                             ("m", ("tdata", "tkeep", "tlast", "tvalid", "tready")))
                  for signal in signals]
        if device.get("application"):
            ports += [f"._app_in({{app{ident}_request_last, app{ident}_request_data}})",
                      f"._app_in_vld(app{ident}_request_valid)",
                      f"._app_in_rdy(app{ident}_request_ready)",
                      f"._app_out({{app{ident}_response_last, app{ident}_response_data}})",
                      f"._app_out_vld(app{ident}_response_valid)",
                      f"._app_out_rdy(app{ident}_response_ready)"]
            lines += [f"hls_phi_debug_{ident} device_{ident} (", "    " + ",\n    ".join(ports), ");", ""]
            continue
        for index, port in external_ports(device):
            stem = f"event_{ident}_{index}"
            lines += [f"wire [127:0] {stem};", f"wire {stem}_valid;",
                      f"wire {stem}_ready = event_ready{ident};",
                      f"always @(posedge clk{ident}) if (resetn && !reset{ident} && {stem}_valid && {stem}_ready) begin",
                      f'    $fdisplay(reports, "{ident} {index} %032h", {stem});',
                      "    $fflush(reports);", "end"]
            ports += [f"._{port}({stem})", f"._{port}_vld({stem}_valid)", f"._{port}_rdy({stem}_ready)"]
        for entry in device.get("ingresses", []):
            port = entry["port"]
            ports += [f"._{port}(control{ident}_data)",
                      f"._{port}_vld(control{ident}_valid)", f"._{port}_rdy(control{ident}_ready)"]
        lines += [f"hls_phi_debug_{ident} device_{ident} (", "    " + ",\n    ".join(ports), ");", ""]
    return "\n".join(lines)


def build_device(args: argparse.Namespace, device: dict) -> None:
    """Compile one device and prove passive debug instrumentation leaves its logic intact."""
    ident = device["id"]
    source = args.stage / "source"
    stage = args.stage / f"device{ident}"
    stage.mkdir()
    name = f"phi_device_{ident}"
    if not device.get("application"):
        (source / f"{name}.x").write_text(device_wrapper(device))
    ram_options = []
    if device.get("scheduler_count", 0):
        configurations = subprocess.check_output([
            "bash", "-c", 'source "$1"; phi_scheduler_ram_configurations "$2"',
            "partition-ram-config", str(ROOT / "tools/phi_scheduler_rams.sh"),
            str(device["scheduler_count"])], text=True).strip()
        ram_options = [f"--ram_configurations={configurations}"]
    commands = [
        ("convert", [str(args.xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
                     f"--dslx_path={source}", f"--dslx_stdlib_path={args.xls / 'xls/dslx/stdlib'}",
                     str(source / f"{name}.x")], stage / f"{name}.ir"),
        ("optimize", [str(args.xls / "opt_main"), str(stage / f"{name}.ir")], stage / f"{name}.opt.ir"),
        ("codegen", [str(args.xls / "codegen_main"), "--pipeline_stages=2", "--delay_model=unit",
                     "--flop_inputs=false", "--flop_outputs=true", "--use_system_verilog=false",
                     "--reset=reset", "--fifo_module=", f"--module_name={name}", *ram_options,
                     str(stage / f"{name}.opt.ir")], stage / f"{name}.v")]
    for label, command, output in commands:
        execute(command, stage, label, timeout=getattr(args, "compiler_timeout", 1200), output=output)
    specialize(args.xls/'codegen_main', stage/f'{name}.opt.ir', stage/f'{name}.v', stage/'adapters')
    (stage / "build.json").write_text(json.dumps({
        "commands": [command for _, command, _ in commands],
        "outputs": {path.name: digest(path) for _, _, path in commands}}, indent=2) + "\n")
    instrument_device(args, device)


def instrument_device(args: argparse.Namespace, device: dict) -> None:
    """Check a completed RTL device's passive projections and combinational acyclicity."""
    ident = device['id']
    name = f"phi_device_{ident}"
    source, stage = args.stage/'source', args.stage/f'device{ident}'
    topology = importlib.import_module("topology_debug")
    ram = bool(device.get("scheduler_count", 0))
    top = name + "_ram" if ram else name
    rtl = [stage / f"{name}.v"]
    if ram:
        rtl += [source / f"{name}_ram.v", args.erl_hls / "priv/rtl/hls_1r1w_ram.v"]
    topology.instrument(argparse.Namespace(
        rtl=rtl, top=top, clock="clk", reset="reset", reset_active_low=False,
        output_top=f"hls_phi_device_{ident}", stage=stage / "debug", yosys=args.yosys,
        actor_projection=source / f"{name}_actors.json" if ram else None, actor_root=""))
    original = json.loads((stage / "debug/flat.json").read_text())["modules"][top]
    observed = json.loads((stage / "debug/instrumented.json").read_text())["modules"][f"hls_phi_device_{ident}"]
    for section in ("ports", "netnames"):
        for port in ("hls_probe_values", "hls_actor_writes"):
            observed[section].pop(port, None)
    if original != observed:
        raise RuntimeError(f"debug instrumentation changed device {ident}'s application")
    execute([args.yosys, "-Q", "-T", "-p",
             f"read_json {json.dumps(str(stage / 'debug/flat.json'))}; scc -expect 0"], stage, "scc")
    debug_wrapper_path = stage / "debug/debug_top.v"
    wrapper = debug_wrapper_path.read_text()
    if wrapper.count("module hls_debug_application (") != 1:
        raise ValueError("public debug wrapper has an unexpected module declaration")
    debug_wrapper_path.write_text(wrapper.replace("module hls_debug_application (",
                                                f"module hls_phi_debug_{ident} ("))
    print(f"Built and instrumented independent device {ident}", flush=True)


def simulation_netlist(args: argparse.Namespace, ident: int) -> Path:
    """Remove redundant combinational cells for simulation while retaining probe ports and uninitialized registers."""
    stage = args.stage / f"device{ident}/debug"
    output = stage / "simulation.v"
    # Start from the already checked passive netlist. Keep the original export
    # for diagnosis; these standard Yosys passes change only the simulator input.
    script = (f"read_json {json.dumps(str(stage / 'instrumented.json'))}\n"
              "opt_reduce\nopt_clean -purge\n"
              "opt_expr -keepdc\nopt_merge -keepdc\nopt_clean -purge\n"
              "splitnets -driver\n"
              "attrmap -remove src -remove hdlname\n"
              "attrmap -modattr -remove src -remove hdlname\n"
              f"stat\nwrite_verilog {json.dumps(str(output))}\n")
    path = stage / "simulation.ys"
    path.write_text(script)
    execute([args.yosys, "-Q", "-T", "-s", str(path)], stage, "simulation-netlist")
    return output


def build(args: argparse.Namespace) -> None:
    """Compile and verify each device; optionally omit the bridge harness when another driver supplies it."""
    provenance = inputs(args)
    args.stage.mkdir(parents=True, exist_ok=False)
    source = args.stage / "source"
    source.mkdir()
    width, height = args.shape
    (source / "config.term").write_text(
        f"#{{shape => [{width}, {height}], planes => [{', '.join(args.planes)}]}}.\n")
    fixture = "hls_phi_memory_fixture" if getattr(args, "memory", False) else "hls_bridge_phi_fixture"
    command = erl_command(args.erl_hls,
        f"ok = {fixture}:write(hd(init:get_plain_arguments())" +
        (f", {args.placement}, {args.memory_case}, #{{}}, {getattr(args, 'reductions', 'ordinary')}"
         if getattr(args, "memory", False) else "") + "), halt().", source, profile="test")
    with (args.stage / "generation.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=300)
    for library in ("lib", "fabric"):
        for path in (args.erl_hls / "priv/xls" / library).glob("*.x"):
            shutil.copy(path, source)
    for path in (ROOT / "priv/xls").rglob("*.x"):
        shutil.copy(path, source)
    shutil.copy(args.erl_hls / "src/examples/phi_decoder/phi_field.x", source)
    devices = json.loads((source / "bridge.json").read_text())["devices"]
    if [device["id"] for device in devices] != [0, 1]:
        raise ValueError("the link witness requires device IDs 0 and 1 in order")
    sys.path.insert(0, str(args.erl_hls / "tools"))
    with ThreadPoolExecutor(max_workers=1 if getattr(args, "memory", False) else 2) as workers:
        list(workers.map(lambda device: build_device(args, device), devices))
    (args.stage / "phi_devices.vh").write_text(testbench_connections(devices))
    if not getattr(args, "devices_only", False):
        compile_simulation(args, devices)
    if provenance != inputs(args):
        raise RuntimeError("RTL build inputs changed while generation was running")
    (args.stage / "provenance.json").write_text(json.dumps({
        "inputs": provenance, "outputs": outputs(args.stage, devices_only=getattr(args, "devices_only", False))}, indent=2, sort_keys=True) + "\n")


def compile_simulation(args: argparse.Namespace, devices: list[dict]) -> None:
    """Compile the verified devices and public-port bridge without changing clocks or witness coverage."""
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(args.erl_hls / "test/rtl" / name, args.stage)
    adapter = "partition_sim_bridge" if getattr(args, "memory", False) else "xls_sim_bridge"
    if getattr(args, "memory", False):
        shutil.copy(ROOT / "test/rtl/partition_sim_bridge.c", args.stage)
    execute(["iverilog-vpi", f"{adapter}.c"], args.stage, "vpi", timeout=60)
    device_rtl = [path for device in devices for path in (
        args.stage / f"device{device['id']}/debug/debug_top.v",
        simulation_netlist(args, device['id']))]
    debug_rtl = [args.erl_hls / "priv/rtl/debug" / name for name in
                 ("hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v")]
    execute(["iverilog", "-g2012", "-s", "phi_bridge_tb", "-I", str(args.stage),
             *( ["-DPHI_MEMORY"] if getattr(args, "memory", False) else []),
             "-I", str(ROOT / "test/rtl"), "-o", str(args.stage / "phi_bridge.vvp"), str(ROOT / "test/rtl/phi_bridge_tb.sv"), str(ROOT / "rtl/hls_async_fifo.v"),
             *map(str, device_rtl + debug_rtl)], args.stage, "iverilog", timeout=300)


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
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
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
