#!/usr/bin/env python3
"""Measure the complete eighteen-board phi torus through four independent links per board."""
import argparse
import json
import os
from pathlib import Path
from backend_paths import PUBLIC
import re
import shutil
import subprocess
import time

from test_actor_rtl import digest, erl_command, execute
from test_phi_bridge import ROOT
from test_phi_mesh import artifacts
from phi_mesh_metrics import layout, analyze
from phi_capture import compressed_capture, prune_simulation
from phi_cycle_trace import executor_requests, plan as cycle_plan, read as read_cycles, verify_queries


def connections(devices: list[dict], link_stages: int = 1) -> str:
    """Wire each directed stream to the reciprocal peer port through its own bounded CDC FIFO."""
    if link_stages < 0:
        raise ValueError("link stages must be nonnegative")
    lines = ["// Generated from the deployment; no geometry-based forwarding or shared link arbiter."]
    count = len(devices)
    by_id = {d["id"]: d for d in devices}
    widths = {d.get("link_width", 33) for d in devices}
    if len(widths) != 1:
        raise ValueError("mesh profile requires one uniform transfer width")
    width, = widths
    if sorted(by_id) != list(range(count)):
        raise ValueError("mesh fixture requires dense integer device IDs")
    lines += [f"wire clk{d} = device_clk[{d}], reset{d} = device_reset[{d}];" for d in range(count)]
    for device in devices:
        d = device["id"]
        ports = [f".clk(clk{d})", f".reset(reset{d})"]
        for link in device["links"]:
            i, peer = link["index"], link["peer"]
            reverse, = [r for r in by_id[peer]["links"] if r["peer"] == d]
            if device.get("transport", "serial") != by_id[peer].get("transport", "serial"):
                raise ValueError("reciprocal transport configurations differ")
            if link["tx_lanes"] != reverse["rx_lanes"] or link["rx_lanes"] != reverse["tx_lanes"]:
                raise ValueError("reciprocal lane counts differ")
            j = reverse["index"]
            for direction, bus in (("in", "rx"), ("out", "tx")):
                port = f"_link_{i}_{direction}"
                ports += [f".{port}({bus}[{d}][{i}])", f".{port}_vld({bus}_valid[{d}][{i}])",
                          f".{port}_rdy({bus}_ready[{d}][{i}])"]
            ports += [f"._fault_{i}_out(faults[{d}][{i}])",
                      f"._fault_{i}_out_vld(fault_valid[{d}][{i}])", f"._fault_{i}_out_rdy(1'b1)"]
            stem = f"link_{d}_{peer}"
            lines += [f"wire [{width-1}:0] {stem}_data [0:{link_stages}];",
                      f"wire [{link_stages}:0] {stem}_valid, {stem}_ready;",
                      f"assign {stem}_data[0] = tx[{d}][{i}];",
                      f"assign {stem}_valid[0] = tx_valid[{d}][{i}];",
                      f"assign tx_ready[{d}][{i}] = {stem}_ready[0];",
                      f"reg {stem}_admit = 0;",
                      f"always @(negedge clk{d}) {stem}_admit = !stalls || (cycles[{d}]+{i}) % 17 >= 5;"]
            for stage in range(link_stages):
                admit = f"{stem}_admit" if stage == 0 else "1'b1"
                lines += [f"phi_bridge_delay #(.WIDTH({width})) {stem}_gate_{stage}(.clk(clk{d}), .reset(reset{d}), .admit({admit}),",
                          f"    .in_data({stem}_data[{stage}]), .in_valid({stem}_valid[{stage}]), .in_ready({stem}_ready[{stage}]),",
                          f"    .out_data({stem}_data[{stage+1}]), .out_valid({stem}_valid[{stage+1}]), .out_ready({stem}_ready[{stage+1}]));"]
            lines += [f"hls_async_fifo #(.WIDTH({width})) {stem}_crossing(.reset(reset), .wr_clk(clk{d}), .rd_clk(clk{peer}),",
                      f"    .in_data({stem}_data[{link_stages}]), .in_valid({stem}_valid[{link_stages}]), .in_ready({stem}_ready[{link_stages}]),",
                      f"    .out_data(rx[{peer}][{j}]), .out_valid(rx_valid[{peer}][{j}]), .out_ready(rx_ready[{peer}][{j}]));"]
        ports += [f"._app_in(request_data[{d}])", f"._app_in_vld(request_valid[{d}])", f"._app_in_rdy(request_ready[{d}])",
                  f"._app_out(response_data[{d}])", f"._app_out_vld(response_valid[{d}])", f"._app_out_rdy(response_ready[{d}])"]
        s = d+count
        ports += [f".s_dbg_tdata(request_data[{s}][31:0])", ".s_dbg_tkeep(4'hf)", f".s_dbg_tlast(request_data[{s}][32])",
                  f".s_dbg_tvalid(request_valid[{s}])", f".s_dbg_tready(request_ready[{s}])",
                  f".m_dbg_tdata(response_data[{s}][31:0])", f".m_dbg_tkeep(debug_keep[{d}])", f".m_dbg_tlast(response_data[{s}][32])",
                  f".m_dbg_tvalid(response_valid[{s}])", f".m_dbg_tready(response_ready[{s}])"]
        lines += [f"hls_phi_debug_{d} device_{d} (\n    " + ",\n    ".join(ports) + "\n);"]
    return "\n".join(lines)+"\n"


def prepare(args: argparse.Namespace) -> list[dict]:
    """Check immutable RTL, retain public manifests, and compile a mesh-only testbench."""
    source = args.build / "source"
    if json.loads((args.build / "source-hashes.json").read_text()) != artifacts(source):
        raise ValueError("generated device source changed")
    devices = json.loads((source / "bridge.json").read_text())["devices"]
    for device in devices:
        directory = args.build / f"device{device['id']}"
        if json.loads((directory / "complete.json").read_text()) != artifacts(directory):
            raise ValueError(f"device {device['id']} changed after its checked build")
    args.stage.mkdir(parents=True, exist_ok=False)
    for name in ("config.term", "deployment.term", "bridge.json"):
        shutil.copy(source / name, args.stage)
    execute(erl_command(args.erl_hls,
        "[Stage] = init:get_plain_arguments(), ok = hls_phi_memory_fixture:oracle(Stage), "
        "ok = hls_phi_memory_profile:describe(Stage), "
        "ok = hls_phi_board_geometry:write(filename:join(Stage, \"geometry.json\")), halt().", args.stage),
        args.stage, "oracle", timeout=120)
    catalog = json.loads((args.stage / "lane-catalog.json").read_text())
    probes = {}
    for device in devices:
        d = device["id"]
        manifest = args.build / f"device{d}/debug/manifest.json"
        shutil.copy(manifest, args.stage / f"device{d}-manifest.json")
        selected, families = [], set()
        field_lanes = {link["index"]: min(r["lane"] for r in catalog
            if r["device"] == d and r["peer"] == link["peer"] and any(s["name"] == "phi" for s in r["schemas"]))
            for link in device["links"]}
        for resource in json.loads(manifest.read_text())["resources"]:
            actor = re.search(r"\{actor,\{family,([^,]+),", resource["name"])
            if resource["kind"] == "actor" and actor:
                families.add(actor[1])
                selected.append(resource["id"])
            elif resource["kind"] == "fifo":
                queue = re.search(r"fifo__outgoing_(\d+)__(\d+)_$", resource["name"])
                if queue and field_lanes.get(int(queue[1])) == int(queue[2]):
                    selected.append(resource["id"])
        if len(families) != 6 or len(selected) != 16:
            raise ValueError(f"expected twelve actors and four outgoing field-lane probes on D{d}: {selected}")
        if args.transport:
            # Independently query one packetizer input per peer to check tap decoding.
            resources = json.loads(manifest.read_text())["resources"]
            selected += [r["pop"] for r in resources if r["kind"] == "fifo"
                         and re.search(r"fifo__outgoing_\d+__0_$", r["name"])]
        if args.actors and (args.actor_devices is None or d in args.actor_devices):
            selected += [r['accept'] for r in executor_requests(json.loads(manifest.read_text())['resources'])]
        probes[str(d)] = selected
    (args.stage / "probes.json").write_text(json.dumps(probes, indent=2)+"\n")
    (args.stage / "phi_mesh_config.vh").write_text(f"`define MESH_DEVICES {len(devices)}\n"
        f"`define MESH_LINK_WIDTH {devices[0].get('link_width', 33)}\n")
    (args.stage / "phi_mesh_devices.vh").write_text(connections(devices, args.link_stages))
    sources = [ROOT / "test/rtl/phi_mesh_tb.sv", ROOT / "rtl/hls_async_fifo.v"]
    sources += [args.build / f"device{d['id']}/debug" / name for d in devices for name in ("debug_top.v", "instrumented.v")]
    sources += [args.erl_hls / "priv/rtl/debug" / name for name in
                ("hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v")]
    if getattr(args, "messages", False):
        from phi_message_trace import plan as message_plan
        sources.append(message_plan(args.build, args.stage, tuple(d["id"] for d in devices), args.erl_hls))
        replacements = {args.build/f'device{d["id"]}/debug/instrumented.v':
            args.stage/f'message-rtl/device{d["id"]}/instrumented.v' for d in devices}
        sources = [replacements.get(source, source) for source in sources]
    hardware = sources + [ROOT / "test/rtl/phi_link_delay.svh", args.stage / "phi_mesh_config.vh", args.stage / "phi_mesh_devices.vh"]
    hashes = {str(p): digest(p) for p in hardware}
    execute(["iverilog", "-g2012", "-s", "phi_bridge_tb", "-I", str(args.stage), "-I", str(ROOT / "test/rtl"),
             "-o", str(args.stage / "profile.vvp"), *(["-s", "phi_message_observer"] if getattr(args, "messages", False) else []), *map(str, sources)], args.stage, "iverilog", timeout=900)
    if hashes != {str(p): digest(p) for p in hardware}:
        raise ValueError("hardware changed during compilation")
    cycle_plan(args.build, args.stage, tuple(d["id"] for d in devices), channels=args.transport,
               all_channels=args.actors, actor_devices=None if args.actor_devices is None else set(args.actor_devices))
    execute(["iverilog-vpi", str(ROOT / "test/rtl/phi_service_trace.c")], args.stage, "cycle-vpi", timeout=60)
    host_sources = [Path(__file__), ROOT / "tools/phi_capture.py", ROOT / "tools/phi_cycle_trace.py", ROOT / "test/rtl/phi_service_trace.c",
                    ROOT / "test/hls_phi_memory_profile.erl", ROOT / "test/hls_phi_profile_debug.erl",
                    ROOT / "test/hls_phi_memory_metrics.erl", ROOT / "test/hls_phi_memory_fixture.erl", args.stage / "probes.json",
                    ROOT / "tools/phi_packed_metrics.py", ROOT / "tools/phi_link_packet.py",
                    ROOT / "tools/phi_mesh_metrics.py", ROOT / "tools/phi_service_metrics.py"]
    if getattr(args, "messages", False):
        host_sources += [ROOT / "tools/phi_message_trace.py", ROOT / "tools/phi_mailbox_trace.py", args.stage / "message-bindings.json"]
    record = {**layout(args.stage), "distance": 6, "build": str(args.build), "build_inputs_sha256": digest(args.build / "inputs.json"),
              "placement": "coalesced", "device_periods_ns": [2*args.clock_half]*len(devices), "host_period_ns": 10,
              "reductions": json.loads((source / "bridge.json").read_text()).get("reductions", "ordinary"),
              "transport": devices[0].get("transport", "serial"),
              "scheduler_groups": {str(d['id']): [{k: b[k] for k in ('index', 'module', 'slots')}
                  for b in json.loads((args.stage / f"device{d['id']}-manifest.json").read_text())['actor_projection']['banks']]
                  for d in devices},
              "link_stages": args.link_stages,
              "compressed_capture": getattr(args, "compress_capture", False),
              "message_payloads": getattr(args, "messages", False), "periodic_stalls": args.stalls, "transport_channels": args.transport, "actor_channels": args.actors, "host_model": "zero-simulated-time ordinary Erlang reducer",
              "actor_devices": args.actor_devices if args.actor_devices is not None else [d['id'] for d in devices] if args.actors else [],
              "hardware_sources": hashes, "host_sources": {str(p): digest(p) for p in host_sources},
              "vvp_sha256": digest(args.stage / "profile.vvp"), "cycle_plan_sha256": digest(args.stage / "cycle-probes.txt"),
              "vpi_sha256": digest(args.stage / "phi_service_trace.vpi")}
    (args.stage / "profile-inputs.json").write_text(json.dumps(record, indent=2)+"\n")
    observer = args.stage / "observer-source"
    observer.mkdir()
    for source in host_sources:
        if digest(source) != record["host_sources"][str(source)]:
            raise ValueError("observer source changed during preparation")
        shutil.copy(source, observer / source.name)
    return devices


def simulate(args: argparse.Namespace) -> None:
    """Require both the complete BEAM witness and all public-port/credit assertions to pass."""
    for name in ("host_requests", "host_responses"):
        os.mkfifo(args.stage / name)
    started = time.monotonic()
    with compressed_capture(args.stage / "cycle-trace.csv", getattr(args, "compress_capture", False)), \
            (args.stage / "host.log").open("w") as host_log, (args.stage / "simulation.log").open("w") as sim_log:
        host = subprocess.Popen(erl_command(args.erl_hls,
            "ok = hls_phi_memory_profile:run(hd(init:get_plain_arguments())), halt().", args.stage),
            cwd=ROOT, stdout=host_log, stderr=subprocess.STDOUT)
        sim = subprocess.Popen(["vvp", "-M", str(args.stage), "-m", "phi_service_trace", str(args.stage / "profile.vvp"),
            f"+HALF={args.clock_half}", f"+STALLS={int(args.stalls)}"], cwd=args.stage, stdout=sim_log, stderr=subprocess.STDOUT)
        try:
            while host.poll() is None or sim.poll() is None:
                if host.poll() not in (None, 0) or sim.poll() not in (None, 0):
                    raise RuntimeError(f"mesh profile failed; see {args.stage}")
                if time.monotonic()-started > args.timeout:
                    raise TimeoutError(f"mesh profile exceeded {args.timeout}s")
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
    queried = {(d["device"], sample["id"]) for d in json.loads((args.stage / "occupancy.json").read_text())
               for sample in d["samples"]}
    _, histories = read_cycles(args.stage, selected=queried)
    verify_queries(args.stage, histories)
    analyze(args.stage)
    if args.transport:
        inputs = json.loads((args.stage / "profile-inputs.json").read_text())
        if inputs.get("transport", "serial") == "serial":
            from phi_transport_metrics import analyze as analyze_transport
        else:
            from phi_packed_metrics import analyze as analyze_transport
        analyze_transport(args.stage)
    print(f"Profile completed in {time.monotonic()-started:.1f}s: {args.stage}")


def main() -> None:
    """Profile cached devices, optionally retaining payload aliases for complete observation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--erl-hls", type=Path, default=PUBLIC)
    parser.add_argument("--clock-half", type=int, default=4)
    parser.add_argument("--stalls", action="store_true")
    parser.add_argument("--link-stages", type=int, default=1,
                        help="elastic source-clock stages before each unchanged CDC FIFO; latency experiment, not Ethernet emulation")
    parser.add_argument("--compress-capture", action="store_true", help="stream cycle observations to gzip during simulation")
    parser.add_argument("--keep-simulation", action="store_true", help="retain the simulation executable and generated payload-observer RTL after success")
    parser.add_argument("--messages", action="store_true", help="capture accepted message values without changing RTL")
    parser.add_argument("--actors", action="store_true", help="capture every channel for actor work reconstruction")
    parser.add_argument("--actor-devices", type=int, nargs='+', help="restrict detailed actor channels; all eighteen boards still run and retain FIFO/actor observations")
    parser.add_argument("--transport", action="store_true", help="observe transport FIFO boundary handshakes")
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args()
    if args.messages and (not args.actors or not args.transport or args.actor_devices is not None):
        parser.error("--messages requires --actors --transport across all devices")
    if args.transport and args.stalls:
        parser.error("transport cause accounting currently requires an unstalled run")
    if args.actor_devices is not None and (not args.actors or not set(args.actor_devices) <= set(range(18))):
        parser.error('--actor-devices requires --actors and IDs from 0 through 17')
    if args.link_stages < 0 or (args.stalls and args.link_stages == 0):
        parser.error("link stages must be nonnegative; periodic stalls need at least one stage")
    if args.clock_half < 1 or args.timeout < 1:
        parser.error("period and timeout must be positive")
    for name in ("build", "stage", "erl_hls"):
        setattr(args, name, getattr(args, name).resolve())
    prepare(args)
    simulate(args)
    if not args.keep_simulation:
        prune_simulation(args.stage)


if __name__ == "__main__":
    main()
