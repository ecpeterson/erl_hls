"""Build independently compiled Phi devices and their public-port simulation harness."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import shutil
import subprocess

from compiler_paths import compiler_application, compiler_resource, compiler_tool, compiler_tools_root
from backend_build_profile import emit as emit_build_profile, read as read_build_profile
from transport_codegen import specialize
from backend_commands import digest, execute
from backend_paths import ROOT, erl_command, debug_rtl
from phi_build_artifacts import bridge_outputs, read_bridge_build


def inputs(args: argparse.Namespace) -> dict:
    """Fingerprint compiler inputs, including the selected full-application fixture."""
    files = {}
    applications = {name: compiler_application(args.erl_hls, name)
                    for name in ("erl_hls", "hls_compile", "hls_fabric", "hls_target")}
    sources = (
        ("private", ROOT, ("apps/hls_fabric/src/**/*.erl", "apps/hls_target/src/**/*.erl", "apps/hls_phi/src/**/*.erl",
                           "apps/hls_phi/src/*.x", "apps/hls_phi/include/**/*.hrl", "apps/hls_phi/tools/phi_tool_paths.py", "apps/hls_phi/test/hls_bridge_phi_fixture.erl",
                           "apps/hls_phi/test/rtl/phi_bridge_tb.sv", "apps/hls_phi/test/rtl/phi_link_delay.svh", "apps/hls_phi/test/rtl/phi_memory_transport.svh",
                           "apps/hls_fabric/test/rtl/partition_sim_bridge.c",
                           "apps/hls_phi/test/hls_phi_memory_fixture.erl", "apps/hls_phi/test/hls_phi_board_geometry.erl", "apps/hls_phi/tools/test_phi_memory.py",
                           "apps/hls_target/priv/rtl/hls_async_fifo.v", "apps/hls_target/priv/xls/**/*.x", "tools/hls_fabric/scheduler_ram_configurations.sh",
                           "apps/hls_phi/tools/test_phi_bridge.py", "apps/hls_phi/tools/phi_device_build.py", "apps/hls_phi/tools/phi_build_artifacts.py",
                           "tools/hls_fabric/test_actor_rtl.py", "tools/hls_fabric/backend_commands.py",
                           "tools/hls_fabric/backend_paths.py", "tools/hls_fabric/compiler_paths.py", "tools/hls_fabric/transport_codegen.py",
                           "tools/hls_fabric/backend_build_profile.py",
                           "rebar.config", "rebar.lock")),
        ("public/erl_hls", applications["erl_hls"],
         ("src/**/*.erl", "test/rtl/xls_sim_bridge.c", "test/rtl/xls_sim_axis.h")),
        ("public/hls_compile", applications["hls_compile"],
         ("src/**/*.erl", "include/**/*.hrl", "priv/xls/**/*.x")),
        ("public/hls_fabric", applications["hls_fabric"],
         ("src/**/*.erl", "include/**/*.hrl", "priv/xls/**/*.x")),
        ("public/hls_target", applications["hls_target"],
         ("src/**/*.erl", "priv/xls/**/*.x", "priv/rtl/debug/*.v", "priv/rtl/hls_1r1w_ram.v")),
        ("public-tools", compiler_tools_root(args.erl_hls), ("tools/erl_hls_tools/*.py",)),
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


def validate_build(args: argparse.Namespace) -> None:
    """Reject reuse when selected inputs, device files or required simulation artifacts differ."""
    if read_bridge_build(args.stage)["inputs"] != inputs(args):
        raise ValueError("RTL build inputs changed; use a fresh --stage without --reuse-build")


def external_ports(device: dict) -> Iterator[tuple[int, str]]:
    """Yield checked numbered public output ports; reject unrecognized port names."""
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
    """Compile one device and check passive debug instrumentation preserves its netlist."""
    ident = device["id"]
    source = args.stage / "source"
    stage = args.stage / f"device{ident}"
    policy = read_build_profile(source / "build-profile.json")
    if policy["profile"]["postprocess"]["completion_storage"] != "registers":
        raise ValueError("Phi device builds support only registers completion storage")
    if policy["profile"]["schedules"]["channel"]["delay_model"] != "unit":
        raise ValueError("Phi device builds support only the unit delay model; use tiles for custom timing")
    stage.mkdir()
    name = f"phi_device_{ident}"
    if not device.get("application"):
        (source / f"{name}.x").write_text(device_wrapper(device))
    ram_options = []
    if device.get("scheduler_count", 0):
        configurations = subprocess.check_output([
            "bash", "-c", 'source "$1"; scheduler_ram_configurations "$2"',
            "partition-ram-config", str(ROOT / "tools/hls_fabric/scheduler_ram_configurations.sh"),
            str(device["scheduler_count"])], text=True).strip()
        ram_options = [f"--ram_configurations={configurations}"]
    commands = [
        ("convert", [str(args.xls / "ir_converter_main"), "--top=Top", "--warnings_as_errors=false",
                     f"--dslx_path={source}", f"--dslx_stdlib_path={args.xls / 'xls/dslx/stdlib'}",
                     str(source / f"{name}.x")], stage / f"{name}.ir"),
        ("optimize", [str(args.xls / "opt_main"), str(stage / f"{name}.ir")], stage / f"{name}.opt.ir"),
        ("codegen", [str(args.xls / "codegen_main"), *policy["codegen_flags"],
                     f"--module_name={name}", *ram_options,
                     str(stage / f"{name}.opt.ir")], stage / f"{name}.v")]
    for label, command, output in commands:
        execute(command, stage, label, timeout=getattr(args, "compiler_timeout", 1200), output=output)
    specialize(args.xls/'codegen_main', stage/f'{name}.opt.ir', stage/f'{name}.v', stage/'adapters')
    (stage / "build.json").write_text(json.dumps({
        "build_profile": policy,
        "commands": [command for _, command, _ in commands],
        "outputs": {path.name: digest(path) for _, _, path in commands}}, indent=2) + "\n")
    instrument_device(args, device)


def instrument_device(args: argparse.Namespace, device: dict) -> None:
    """Check a completed RTL device's passive projections and combinational acyclicity."""
    ident = device['id']
    name = f"phi_device_{ident}"
    source, stage = args.stage/'source', args.stage/f'device{ident}'
    topology = compiler_tool(args.erl_hls, "topology_debug")
    ram = bool(device.get("scheduler_count", 0))
    top = name + "_ram" if ram else name
    rtl = [stage / f"{name}.v"]
    if ram:
        rtl += [source / f"{name}_ram.v",
                compiler_resource(args.erl_hls, "hls_target", "priv/rtl/hls_1r1w_ram.v")]
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
    emit_build_profile(source / "build-profile.json", profile="test", public=args.erl_hls,
                       initiation_interval=None)
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
    for path in compiler_resource(args.erl_hls, "hls_compile", "priv/xls/lib").glob("*.x"):
        shutil.copy(path, source)
    for path in compiler_resource(args.erl_hls, "hls_fabric", "priv/xls/fabric").glob("*.x"):
        shutil.copy(path, source)
    for path in (ROOT / "apps/hls_target/priv/xls").rglob("*.x"):
        shutil.copy(path, source)
    shutil.copy(ROOT / "apps/hls_phi/src/phi_field.x", source)
    devices = json.loads((source / "bridge.json").read_text())["devices"]
    if [device["id"] for device in devices] != [0, 1]:
        raise ValueError("the link witness requires device IDs 0 and 1 in order")
    with ThreadPoolExecutor(max_workers=1 if getattr(args, "memory", False) else 2) as workers:
        list(workers.map(lambda device: build_device(args, device), devices))
    (args.stage / "phi_devices.vh").write_text(testbench_connections(devices))
    if not getattr(args, "devices_only", False):
        compile_simulation(args, devices)
    if provenance != inputs(args):
        raise RuntimeError("RTL build inputs changed while generation was running")
    (args.stage / "provenance.json").write_text(json.dumps({
        "inputs": provenance, "outputs": bridge_outputs(args.stage, devices_only=getattr(args, "devices_only", False))}, indent=2, sort_keys=True) + "\n")


def compile_simulation(args: argparse.Namespace, devices: list[dict]) -> None:
    """Compile the verified devices and public-port bridge without changing clocks or witness coverage."""
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(args.erl_hls / "test/rtl" / name, args.stage)
    adapter = "partition_sim_bridge" if getattr(args, "memory", False) else "xls_sim_bridge"
    if getattr(args, "memory", False):
        shutil.copy(ROOT / "apps/hls_fabric/test/rtl/partition_sim_bridge.c", args.stage)
    execute(["iverilog-vpi", f"{adapter}.c"], args.stage, "vpi", timeout=60)
    device_rtl = [path for device in devices for path in (
        args.stage / f"device{device['id']}/debug/debug_top.v",
        simulation_netlist(args, device['id']))]
    execute(["iverilog", "-g2012", "-s", "phi_bridge_tb", "-I", str(args.stage),
             *( ["-DPHI_MEMORY"] if getattr(args, "memory", False) else []),
             "-I", str(ROOT / "apps/hls_fabric/test/rtl"), "-I", str(ROOT / "apps/hls_phi/test/rtl"), "-o", str(args.stage / "phi_bridge.vvp"), str(ROOT / "apps/hls_phi/test/rtl/phi_bridge_tb.sv"), str(ROOT / "apps/hls_target/priv/rtl/hls_async_fifo.v"),
             *map(str, device_rtl + debug_rtl(args.erl_hls))], args.stage, "iverilog", timeout=300)
