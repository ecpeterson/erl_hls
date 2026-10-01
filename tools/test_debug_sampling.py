#!/usr/bin/env python3
"""Prove continuous debug sampling and replay overlapping public queries.

Use the production generated Observer (2 stages, II=1) and DebugServer
(3 stages, II=2), as built by remote_xls_sim.sh or build_phi_debug.py. The
unbounded safety proof uses Yosys and its bundled ABC PDR engine. All inputs
are unconstrained after a shared sampled reset, including later resets and
indefinitely stalled replies. This is not a liveness or physical timing proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from topology_debug import quote

ROOT = Path(__file__).resolve().parents[1]


def run(command, log, cwd=None):
    with log.open("w") as output:
        subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                       check=True, timeout=120)


def prove(args, sources, name, failure=False):
    stage = args.stage / name
    stage.mkdir(exist_ok=True)
    script = "read_verilog -formal -sv " + " ".join(map(quote, [
        ROOT / "test/rtl/debug/hls_debug_sampling_formal.sv", *sources])) + "\n"
    script += ("prep -top hls_debug_sampling_formal -flatten\n"
               "memory_map\nopt\ncheck -assert\nscc -expect 0\n"
               "formalff -clk2ff -ff2anyinit\nsetundef -undriven -anyseq\n"
               "techmap\nopt -fast\ndffunmap\naigmap\nopt_clean\n"
               "write_aiger -miter -zinit -map design.aim design.aig\n")
    (stage / "proof.ys").write_text(script)
    run([args.yosys, "-Q", "-T", "-s", "proof.ys"], stage / "yosys.log", stage)
    command = "read_aiger design.aig; fold; strash; pdr; write_cex -a counterexample.aiw"
    (stage / "proof.abc").write_text(command + "\n")
    run([args.abc, "-c", command], stage / "abc.log", stage)
    log = (stage / "abc.log").read_text()
    # ABC can exit successfully after a command error. Require the solver's
    # conclusive result, never just a zero exit code or absence of a trace.
    if failure:
        if "asserted in frame" not in log or not (stage / "counterexample.aiw").exists():
            raise RuntimeError(f"mutation did not produce a counterexample: {stage}")
        print(f"PASS: sampling proof rejects {name}", flush=True)
    elif "Property proved." not in log:
        raise RuntimeError(f"sampling proof did not complete: {stage}")
    else:
        print("PASS: unbounded sampling safety under arbitrary query traffic, reply stalls and resets", flush=True)


def simulate(stage, monitor, support, failure=False):
    exe = stage / "sampling.vvp"
    run(["iverilog", "-g2012", "-s", "hls_debug_sampling_tb", "-o", str(exe),
         str(ROOT / "test/rtl/debug/hls_debug_sampling_tb.sv"),
         str(ROOT / "priv/rtl/debug/hls_debug_tap.v"), str(monitor), *map(str, support)],
        stage / "compile.log")
    log = stage / "simulation.log"
    try:
        run(["vvp", str(exe)], log)
    except subprocess.CalledProcessError:
        if not failure or "query backpressure lost observations" not in log.read_text():
            raise
        print("PASS: public counter reply diagnoses missed observations without the fence", flush=True)
    else:
        if failure:
            raise RuntimeError("unfenced requests escaped the public-port regression")
        print(log.read_text(), end="", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, help="directory with generated hls_debug_{observer,server}.v")
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/debug-sampling")
    parser.add_argument("--yosys", default=os.environ.get("ERL_HLS_YOSYS") or shutil.which("yosys"))
    parser.add_argument("--abc", help="defaults to yosys-abc beside Yosys or on PATH")
    args = parser.parse_args()
    if not args.yosys:
        parser.error("Yosys required; set --yosys or ERL_HLS_YOSYS")
    args.yosys = str(Path(shutil.which(args.yosys) or args.yosys).resolve())
    args.abc = args.abc or str(Path(args.yosys).with_name("yosys-abc"))
    args.abc = str(Path(shutil.which(args.abc) or args.abc).resolve())
    args.stage = args.stage.resolve()
    args.stage.mkdir(parents=True, exist_ok=True)
    args.rtl = args.rtl.resolve()
    generated = [args.rtl / f"hls_debug_{name}.v" for name in ("observer", "server")]
    monitor = ROOT / "priv/rtl/debug/hls_debug_monitor.v"
    support = [ROOT / "priv/rtl/debug/hls_trace_store.v", *generated]
    inputs = [monitor, ROOT / "priv/rtl/debug/hls_debug_tap.v", *support,
              ROOT / "test/rtl/debug/hls_debug_sampling_formal.sv",
              ROOT / "test/rtl/debug/hls_debug_sampling_tb.sv", Path(__file__).resolve()]
    started = time.monotonic()
    prove(args, [monitor, *support], "production")
    mutations = {
        "unfenced-requests": [
            ("!reply_pending && server_request_ready", "server_request_ready"),
            ("s_dbg_tvalid && !reply_pending", "s_dbg_tvalid")],
        "blocked-trace-writes": [
            ("._trace_write_out_rdy(trace_write_ready)",
             "._trace_write_out_rdy(trace_write_ready && m_dbg_tready)")],
    }
    original = monitor.read_text()
    for name, replacements in mutations.items():
        changed = original
        for before, after in replacements:
            if changed.count(before) != 1:
                raise ValueError(f"mutation target changed: {before}")
            changed = changed.replace(before, after)
        path = args.stage / f"{name}.v"
        path.write_text(changed)
        prove(args, [path, *support], name, failure=True)
    simulate(args.stage, monitor, support)
    simulate(args.stage / "unfenced-requests", args.stage / "unfenced-requests.v", support, failure=True)
    report = {"result": "pass", "seconds": time.monotonic() - started,
              "proof": "ABC PDR, unbounded safety after a sampled shared reset; no input/fairness constraints",
              "negative_controls": list(mutations),
              "yosys": subprocess.check_output([args.yosys, "-V"], text=True).strip(),
              "inputs": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
              "tools": {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in map(Path, (args.yosys, args.abc))}}
    (args.stage / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
