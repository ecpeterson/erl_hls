#!/usr/bin/env python3
"""Diagnose routed observation loss through hls_debug and the public debug stream.

Requires rebar3 eunit and the generated hls_debug_{observer,server}.v files from
prepare_xls_sim.sh / remote_xls_sim.sh. VPI transports only debug AXI packets;
the testbench injects sampling faults without inspecting private hardware state.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def run(rtl, stage):
    stage.mkdir(parents=True, exist_ok=True)
    for pattern in ("phase_*", "done_*", "trace_*.term", "debug_tx", "debug_rx"):
        for path in stage.glob(pattern):
            path.unlink()
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(ROOT / "test/rtl" / name, stage)
    support = [ROOT / "priv/rtl/debug" / name for name in (
        "hls_debug_tap.v", "hls_debug_monitor.v", "hls_trace_store.v", "hls_debug_route.v")]
    generated = [rtl / f"hls_debug_{name}.v" for name in ("observer", "server")]
    with (stage / "compile.log").open("w") as log:
        for command in (["iverilog-vpi", "xls_sim_bridge.c"],
                        ["iverilog", "-g2012", "-s", "hls_debug_trace_live_tb", "-o", "test.vvp",
                         str(ROOT / "test/rtl/debug/hls_debug_trace_live_tb.sv"),
                         *map(str, support + generated)]):
            subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    env = dict(os.environ, ERL_HLS_SIM_DIR=str(stage),
               ERL_HLS_SIM_TOP="hls_debug_trace_live_tb", ERL_HLS_SIM_DEBUG_ONLY="1")
    for name in ("ERL_HLS_SIM_APP_ONLY", "ERL_HLS_SIM_PROFILE_ONLY", "ERL_HLS_SIM_SCHEDULER_PROFILE"):
        env.pop(name, None)
    with (stage / "simulation.log").open("w") as log:
        sim = subprocess.Popen(["vvp", "-M", str(stage), "-m", "xls_sim_bridge", "test.vvp"],
                               cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while not all((stage / name).exists() for name in ("debug_tx", "debug_rx")):
                if sim.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f"No debug transport; see {stage / 'simulation.log'}")
                time.sleep(0.01)
            command = ["erl", "-noshell", "-pa", str(ROOT / "_build/test/lib/erl_hls/ebin"),
                       str(ROOT / "_build/test/lib/erl_hls/test"), "-eval",
                       'ok = hls_debug_trace_live:run(hd(init:get_plain_arguments())), halt(0).',
                       "-extra", str(stage)]
            with (stage / "host.log").open("w") as host_log:
                result = subprocess.run(command, cwd=stage, stdout=host_log,
                                        stderr=subprocess.STDOUT, timeout=120)
            if result.returncode:
                raise RuntimeError((stage / "host.log").read_text())
            if sim.wait(timeout=15):
                raise RuntimeError((stage / "simulation.log").read_text())
        finally:
            if sim.poll() is None:
                sim.terminate()
                sim.wait(timeout=10)
    print((stage / "host.log").read_text(), end="")
    print(f"Saved decoded traces and transport diagnostics in {stage}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, help="directory containing the generated debug RTL")
    parser.add_argument("--stage", type=Path, default=Path("_build/debug-trace-integration"))
    args = parser.parse_args()
    run(args.rtl.resolve(), args.stage.resolve())
