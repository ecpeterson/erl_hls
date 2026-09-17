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
import topology_debug_report as reporting

ROOT = Path(__file__).resolve().parents[1]
DEBUG_RTL = [ROOT / "priv/rtl/debug" / name for name in
             ("hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v")]


def testbench(args, ports, manifest):
    lines = ["`timescale 1ns/1ps", "module topology_live_tb;", "reg clk=0, resetn=0;",
             "always #5 clk=~clk;", "reg released=0, contributions=0; integer fd, cycles=0;",
             "reg [31:0] s_dbg_tdata=0; reg [3:0] s_dbg_tkeep=15;",
             "reg s_dbg_tlast=0, s_dbg_tvalid=0; wire s_dbg_tready;",
             "wire [31:0] m_dbg_tdata; wire [3:0] m_dbg_tkeep;",
             "wire m_dbg_tlast, m_dbg_tvalid; reg m_dbg_tready=0;"]
    originals, instrumented, production, checks, final_checks = [], [], [], [], []
    ingress = bool(args.actor_test and args.actor_test.startswith("ingress_"))
    packets = json.loads((args.stage.parent / "commands.json").read_text()) if ingress else []
    compare_production = bool(getattr(args, "reference_rtl", None))
    sinks = [ready for _, _, ready, direction in topology.channel_ports({"ports": ports}) if direction == "output"]
    if not sinks:
        raise ValueError("test requires an external sink")
    if ingress:
        # The report sink is held while acknowledgments drain independently.
        sinks.remove("_reports_out_rdy")
        sinks.insert(0, "_reports_out_rdy")
        lines += [f"reg [193:0] commands [0:{len(packets)-1}];",
                  f"integer command_round [0:{len(packets)-1}];",
                  "integer sent=0, acks=0, input_stalls=0; reg application_complete=0;", "initial begin"]
        lines += [f"commands[{i}]=194'h{p['bits']}; command_round[{i}]={p['round']};"
                  for i, p in enumerate(packets)]
        lines += ["end", f"wire command_valid = sent < {len(packets)} && command_round[sent] <= acks;",
                  "wire [193:0] command_data = command_valid ? commands[sent] : 194'b0;"]
    valid_for_data = {stem: valid for stem, valid, _, _ in topology.channel_ports({"ports": ports})}
    for index, (name, port) in enumerate(ports.items()):
        width = len(port["bits"])
        if port["direction"] == "input":
            if name == args.clock:
                signal = "clk"
            elif name == args.reset:
                signal = "resetn" if args.reset_active_low else "!resetn"
            elif ingress and name == "_commands_in":
                signal = "command_data"
            elif ingress and name == "_commands_in_vld":
                signal = "command_valid"
            elif name in sinks:
                signal = "released" if name == sinks[0] else "1'b1"
            elif name == "release_contributions" and args.actor_test in ("reduction", "aggregate", "direct_reduction"):
                signal = "contributions" if args.actor_test == "direct_reduction" else "released"
            else:
                raise ValueError(f"test has no driver for input {name}")
            originals.append(f".\\{name} ({signal})")
            instrumented.append(f".\\{name} ({signal})")
            production.append(f".\\{name} ({signal})")
        else:
            for suffix in (("ref", "dut", "production") if compare_production else ("ref", "dut")):
                lines.append(f"wire [{width-1}:0] port_{index}_{suffix};")
            originals.append(f".\\{name} (port_{index}_ref)")
            instrumented.append(f".\\{name} (port_{index}_dut)")
            production.append(f".\\{name} (port_{index}_production)")
            valid_name = valid_for_data.get(name)
            condition = "1" if valid_name is None else f"port_{list(ports).index(valid_name)}_ref"
            checks.append(f"if ({condition} && port_{index}_ref !== port_{index}_dut) $fatal(1, \"changed application output {name}\");")
    if compare_production:
        if args.actor_test != "direct_reduction":
            raise ValueError("production comparison currently uses the direct reduction fixture")
        report_index = list(ports).index("_reports_out")
        valid_index = list(ports).index("_reports_out_vld")
        for suffix in ("dut", "production"):
            lines.append(f"integer reports_{suffix}=0;")
            checks += [
                f"if(port_{valid_index}_{suffix} && !contributions) $fatal(1, \"{suffix}: completed before missing contributors\");",
                f"if(port_{valid_index}_{suffix} && port_{report_index}_{suffix}[95:0] !== 96'd3) $fatal(1, \"{suffix}: wrong healthy reduction result\");",
                f"if(port_{valid_index}_{suffix} && released) reports_{suffix}=reports_{suffix}+1;",
            ]
            final_checks.append(f"if(reports_{suffix} != 1) $fatal(1, \"{suffix}: expected exactly one healthy report, got %0d\",reports_{suffix});")
        # This fixture's complete application transcript is one report. Check
        # the whole frame as well as its value, independently of cycle timing.
        lines += [f"reg [{len(ports['_reports_out']['bits'])-1}:0] report_dut, report_production;"]
        for suffix in ("dut", "production"):
            checks.append(f"if(port_{valid_index}_{suffix} && released) report_{suffix}=port_{report_index}_{suffix};")
        final_checks.append('if(report_dut !== report_production) $fatal(1, "production/debug application frame differs");')
        final_checks.append('$display("PASS: production/debug application transcripts match (one healthy report, payload 3)");')
    debug_ports = [f".{side}_dbg_{suffix}({side}_dbg_{suffix})" for side in ("s", "m")
                   for suffix in ("tdata", "tkeep", "tlast", "tvalid", "tready")]
    if args.actor_test and args.actor_test.startswith(("mixed_", "ingress_")):
        report_index = list(ports).index("_reports_out")
        valid_index = list(ports).index("_reports_out_vld")
        lines += ["reg [127:0] expected_reports [0:31]; integer reports=0;",
                  'initial $readmemh("expected.hex", expected_reports);']
        checks += [f"if(port_{valid_index}_dut && released) begin",
                   '  if(reports >= 32) $fatal(1, "duplicate mixed report");',
                   f'  if(port_{report_index}_dut !== expected_reports[reports]) $fatal(1, "mixed report %0d: got %032h expected %032h", reports, port_{report_index}_dut, expected_reports[reports]);',
                   '  $display("mixed report %0d accepted at cycle %0d", reports, cycles);',
                   "  reports=reports+1; end"]
        final_checks += ['if(reports != 32) $fatal(1, "missing mixed reports: %0d", reports);',
                         '$display("PASS: mixed RTL matches all 32 CPU reports (320 work items, 640 result items)");']
    if ingress:
        ready = list(ports).index("_commands_in_rdy")
        ack_valid = list(ports).index("_acks_out_vld")
        ack_data = list(ports).index("_acks_out")
        checks += [f"if(command_valid && port_{ready}_dut) sent <= sent+1;",
                   f"if(command_valid && !port_{ready}_dut) input_stalls=input_stalls+1;",
                   f"if(port_{ack_valid}_dut) begin",
                   f'  if(port_{ack_data}_dut[95:0] !== acks+1) $fatal(1, "wrong command acknowledgment");',
                   "  acks=acks+1; end",
                   f"if(reports == 32 && acks == 32 && sent == {len(packets)} && !application_complete) begin",
                   '  application_complete=1; fd=$fopen("application_complete","w"); $fclose(fd); end']
        final_checks += [f'if(sent != {len(packets)} || acks != 32) $fatal(1, "incomplete command stream");',
                         'if(input_stalls == 0) $fatal(1, "command input never experienced backpressure");',
                         '$display("PASS: %0d external packets, %0d input stall cycles", sent, input_stalls);']
    queues = [q for q in manifest["resources"] if q["kind"] == "fifo"]
    for q in queues:
        lines.append(f"integer occupancy_{q['id']}=0;")
        base, push, pop = (64*q[k] for k in ("id", "push", "pop"))
        checks.append(f"if(dut.probe_values[{base}+:32] !== occupancy_{q['id']}) "
                      f"$fatal(1, \"FIFO occupancy conservation failed: {q['id']}\");")
        checks.append(f"occupancy_{q['id']} = occupancy_{q['id']} + "
                      f"((dut.probe_values[{push}+:2] == 3) ? 1 : 0) - "
                      f"((dut.probe_values[{pop}+:2] == 3) ? 1 : 0);")
    if compare_production:
        lines.append(f"{args.reference_top} production ({', '.join(production)});")
    lines += [f"{args.top} reference ({', '.join(originals)});",
              f"hls_debug_application dut ({', '.join(instrumented+debug_ports)});",
              "initial begin repeat(5) @(negedge clk); resetn=1; end",
              "always @(posedge clk) if(resetn) begin", *checks,
              "cycles=cycles+1; if(cycles>5000000) $fatal(1, \"host query timeout\");",
              "end", "always @(negedge clk) if(resetn && cycles%100==0) begin",
              'fd=$fopen("contributions","r"); if(fd) begin contributions=1; $fclose(fd); fd=$fopen("contributions_released","w"); $fclose(fd); end',
              'fd=$fopen("release","r"); if(fd) begin released=1; $fclose(fd); fd=$fopen("released","w"); $fclose(fd); end',
              'fd=$fopen("done","r"); if(fd) begin $fclose(fd);',
              *final_checks,
              '$display("PASS: original/instrumented application equivalence for %0d cycles",cycles); $finish; end',
              "end", "endmodule"]
    return "\n".join(lines)+"\n"


def run(args):
    topology.instrument(args)
    stage = args.stage.resolve()
    manifest = json.loads((stage / "manifest.json").read_text())
    flat = json.loads((stage / "flat.json").read_text())
    ports = flat["modules"][args.top]["ports"]
    # A cycle can stop simulation before even the independent debug endpoint
    # answers. Diagnose the application structurally before starting the host.
    with (stage / "scc.log").open("w") as log:
        subprocess.run([args.yosys, "-Q", "-T", "-p",
                        f"read_json {json.dumps(str(stage / 'flat.json'))}; scc -expect 0"],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
    (stage / "tb.sv").write_text(testbench(args, ports, manifest))
    # Check structural noninterference before subsequent Yosys cleanup.
    instrumented = json.loads((stage / "instrumented.json").read_text())["modules"][args.output_top]
    instrumented["ports"].pop("hls_probe_values")
    instrumented["netnames"].pop("hls_probe_values")
    for section in ("ports", "netnames"):
        instrumented[section].pop("hls_actor_writes", None)
    assert instrumented == flat["modules"][args.top], "instrumentation modified application cells/ports"
    del flat, instrumented
    if getattr(args, "actor_test", None):
        (stage / "actor-test").write_text(args.actor_test)
        if args.actor_test.startswith(("mixed_", "ingress_")):
            shutil.copy(stage.parent / "expected.hex", stage / "expected.hex")
    else:
        (stage / "actor-test").unlink(missing_ok=True)
    for name in ("release", "released", "contributions", "contributions_released", "application_complete", "done", "debug_tx", "debug_rx"):
        (stage / name).unlink(missing_ok=True)
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(ROOT / "test/rtl" / name, stage)
    reference_rtl = getattr(args, "reference_rtl", None) or []
    if reference_rtl:
        # Independent XLS builds reuse internal proc/FIFO module names. Flatten
        # the production copy under its own top before compiling both designs
        # into one simulation; never rename individual generated signal text.
        reference_flat = stage / "production.v"
        script = "\n".join([
            "read_verilog -sv " + " ".join(json.dumps(str(path.resolve())) for path in reference_rtl),
            f"hierarchy -check -top {args.reference_top}",
            "proc", "flatten", f"hierarchy -top {args.reference_top}",
            "write_verilog " + json.dumps(str(reference_flat)),
        ])
        (stage / "production.ys").write_text(script + "\n")
        with (stage / "production.log").open("w") as log:
            subprocess.run([args.yosys, "-Q", "-T", "-s", str(stage / "production.ys")],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
        reference_rtl = [reference_flat]
    commands = [["iverilog-vpi", "xls_sim_bridge.c"],
        ["iverilog", "-g2012", "-s", "topology_live_tb", "-o", "test.vvp", "tb.sv", "debug_top.v", "instrumented.v",
         *map(str, DEBUG_RTL), *[str(p.resolve()) for p in args.rtl],
         *[str(p.resolve()) for p in reference_rtl]]]
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
    for name in (("blocked", "completed", "recovered") if args.actor_test == "direct_reduction" else ("blocked", "recovered")):
        report = json.loads((stage / f"{name}.json").read_text())
        (stage / f"{name}.txt").write_text(reporting.text_report(manifest, report))
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
    parser.add_argument("--actor-projection", type=Path)
    parser.add_argument("--actor-root", default="")
    parser.add_argument("--actor-test", choices=("small", "phi", "mailbox", "reduction", "aggregate", "direct_reduction",
                                                "mixed_direct", "mixed_one", "mixed_two", "mixed_coalesced",
                                                "ingress_direct", "ingress_one", "ingress_two", "ingress_coalesced"))
    parser.add_argument("--reference-rtl", type=Path, action="append", help="diagnostics-disabled application RTL for transfer comparison")
    parser.add_argument("--reference-top", default="actor_debug_production_wrapper")
    run(parser.parse_args())
