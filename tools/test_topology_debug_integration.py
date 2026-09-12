#!/usr/bin/env python3
"""Query a generated application via the real Erlang/FIFO/VPI debug transport.

Takes the same RTL/top/clock/reset arguments as topology_debug.py. The test
compares original and instrumented application outputs every cycle, blocks the
first external sink, then releases it after the host has inspected its wait chain.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import topology_debug as topology

ROOT = Path(__file__).resolve().parents[1]
DEBUG_RTL = [ROOT / "priv/rtl/debug" / name for name in
             ("hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v")]


def testbench(args, ports, manifest):
    lines = ["`timescale 1ns/1ps", "module topology_live_tb;", "reg clk=0, resetn=0;",
             "always #5 clk=~clk;", "reg released=0; integer fd, cycles=0;",
             "reg [31:0] s_dbg_tdata=0; reg [3:0] s_dbg_tkeep=15;",
             "reg s_dbg_tlast=0, s_dbg_tvalid=0; wire s_dbg_tready;",
             "wire [31:0] m_dbg_tdata; wire [3:0] m_dbg_tkeep;",
             "wire m_dbg_tlast, m_dbg_tvalid; reg m_dbg_tready=0;"]
    originals, instrumented, checks = [], [], []
    sinks = [ready for _, _, ready, direction in topology.channel_ports({"ports": ports}) if direction == "output"]
    if not sinks:
        raise ValueError("test requires an external sink")
    valid_for_data = {stem: valid for stem, valid, _, _ in topology.channel_ports({"ports": ports})}
    for index, (name, port) in enumerate(ports.items()):
        width = len(port["bits"])
        if port["direction"] == "input":
            if name == args.clock:
                signal = "clk"
            elif name == args.reset:
                signal = "resetn" if args.reset_active_low else "!resetn"
            elif name in sinks:
                signal = "released" if name == sinks[0] else "1'b1"
            else:
                raise ValueError(f"test has no driver for input {name}")
            originals.append(f".\\{name} ({signal})")
            instrumented.append(f".\\{name} ({signal})")
        else:
            for suffix in ("ref", "dut"):
                lines.append(f"wire [{width-1}:0] port_{index}_{suffix};")
            originals.append(f".\\{name} (port_{index}_ref)")
            instrumented.append(f".\\{name} (port_{index}_dut)")
            valid_name = valid_for_data.get(name)
            condition = "1" if valid_name is None else f"port_{list(ports).index(valid_name)}_ref"
            checks.append(f"if ({condition} && port_{index}_ref !== port_{index}_dut) $fatal(1, \"changed application output {name}\");")
    debug_ports = [f".{side}_dbg_{suffix}({side}_dbg_{suffix})" for side in ("s", "m")
                   for suffix in ("tdata", "tkeep", "tlast", "tvalid", "tready")]
    queues = [q for q in manifest["resources"] if q["kind"] == "fifo"]
    for q in queues:
        lines.append(f"integer occupancy_{q['id']}=0;")
        base, push, pop = (32*q[k] for k in ("id", "push", "pop"))
        checks.append(f"if(dut.probe_values[{base}+:32] !== occupancy_{q['id']}) "
                      f"$fatal(1, \"FIFO occupancy conservation failed: {q['id']}\");")
        checks.append(f"occupancy_{q['id']} = occupancy_{q['id']} + "
                      f"((dut.probe_values[{push}+:2] == 3) ? 1 : 0) - "
                      f"((dut.probe_values[{pop}+:2] == 3) ? 1 : 0);")
    lines += [f"{args.top} reference ({', '.join(originals)});",
              f"hls_debug_application dut ({', '.join(instrumented+debug_ports)});",
              "initial begin repeat(5) @(negedge clk); resetn=1; end",
              "always @(posedge clk) if(resetn) begin", *checks,
              "cycles=cycles+1; if(cycles>5000000) $fatal(1, \"host query timeout\");",
              "end", "always @(negedge clk) if(resetn && cycles%100==0) begin",
              'fd=$fopen("release","r"); if(fd) begin released=1; $fclose(fd); fd=$fopen("released","w"); $fclose(fd); end',
              'fd=$fopen("done","r"); if(fd) begin $fclose(fd);',
              '$display("PASS: original/instrumented application equivalence for %0d cycles",cycles); $finish; end',
              "end", "endmodule"]
    return "\n".join(lines)+"\n"


def run(args):
    topology.instrument(args)
    stage = args.stage.resolve()
    manifest = json.loads((stage / "manifest.json").read_text())
    flat = json.loads((stage / "flat.json").read_text())
    ports = flat["modules"][args.top]["ports"]
    (stage / "tb.sv").write_text(testbench(args, ports, manifest))
    # Check structural noninterference before subsequent Yosys cleanup.
    instrumented = json.loads((stage / "instrumented.json").read_text())["modules"][args.output_top]
    instrumented["ports"].pop("hls_probe_values")
    instrumented["netnames"].pop("hls_probe_values")
    assert instrumented == flat["modules"][args.top], "instrumentation modified application cells/ports"
    del flat, instrumented
    for name in ("release", "released", "done", "debug_tx", "debug_rx"):
        (stage / name).unlink(missing_ok=True)
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(ROOT / "test/rtl" / name, stage)
    commands = [["iverilog-vpi", "xls_sim_bridge.c"],
        ["iverilog", "-g2012", "-s", "topology_live_tb", "-o", "test.vvp", "tb.sv", "debug_top.v", "instrumented.v",
         *map(str, DEBUG_RTL), *[str(p.resolve()) for p in args.rtl]]]
    with (stage / "compile.log").open("w") as log:
        for command in commands:
            subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    env = dict(os.environ, ERL_HLS_SIM_DIR=str(stage), ERL_HLS_SIM_TOP="topology_live_tb", ERL_HLS_SIM_DEBUG_ONLY="1")
    for name in ("ERL_HLS_SIM_APP_ONLY", "ERL_HLS_SIM_PROFILE_ONLY", "ERL_HLS_SIM_SCHEDULER_PROFILE"):
        env.pop(name, None)
    with (stage / "simulation.log").open("w") as log:
        sim = subprocess.Popen(["vvp", "-M", str(stage), "-m", "xls_sim_bridge", "test.vvp"], cwd=stage,
                               env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while not all((stage / name).exists() for name in ("debug_tx", "debug_rx")):
                if sim.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("VPI did not create its transport FIFOs")
                time.sleep(0.01)
            # Paths are passed as arguments, never interpolated into Erlang code.
            host = ["erl", "-noshell", "-pa", str(ROOT / "_build/test/lib/erl_hls/ebin"),
                    str(ROOT / "_build/test/lib/erl_hls/test"), "-eval",
                    'case hls_topology_debug_live:run(hd(init:get_plain_arguments())) of ok -> halt(0); Error -> io:format("~p~n",[Error]), halt(1) end.',
                    "-extra", str(stage)]
            with (stage / "host.log").open("w") as host_log:
                client = subprocess.Popen(host, cwd=ROOT, stdout=host_log, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 180
                    while client.poll() is None:
                        if (sim.poll() is not None and not (sim.returncode == 0 and (stage / "done").exists())) or time.monotonic() > deadline:
                            raise RuntimeError("simulation exited or host queries timed out")
                        time.sleep(0.02)
                    if client.returncode:
                        raise RuntimeError(f"host failed: {(stage / 'host.log').read_text()}")
                finally:
                    if client.poll() is None:
                        client.terminate()
                        client.wait(timeout=10)
            assert sim.wait(timeout=30) == 0, (stage / "simulation.log").read_text()
            print((stage / "host.log").read_text(), end="")
        finally:
            if sim.poll() is None:
                sim.terminate()
                sim.wait(timeout=10)
    assert "PASS: original/instrumented" in (stage / "simulation.log").read_text()
    print(f"PASS: {manifest['top']} structural and cycle-by-cycle noninterference")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, nargs="+")
    parser.add_argument("--top", required=True)
    parser.add_argument("--clock", default="clk")
    parser.add_argument("--reset", default="reset")
    parser.add_argument("--reset-active-low", action="store_true")
    parser.add_argument("--output-top", default="hls_instrumented_application")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--yosys", default="yosys")
    run(parser.parse_args())
