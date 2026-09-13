#!/usr/bin/env python3
"""Exercise every debug service on a complete D3 topology through public APIs.

First run build_phi_debug.py. The VPI plugin transports external stream words;
it never reads application internals. The RTL also compares the application
against its independently compiled production variant on every clock.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
from topology_debug_services import rtl_files
from build_phi_debug import validate


def run(build, stage):
    validate(build)
    stage.mkdir(parents=True, exist_ok=True)
    for name in ("block", "blocked", "hold_debug", "debug_held", "reply_held", "debug_released", "done",
                 "application_complete", "app_tx", "app_rx", "debug_tx", "debug_rx",
                 "debug.term", "actors-blocked.term", "blocked.json", "recovered.json", "application.json"):
        (stage / name).unlink(missing_ok=True)
    shutil.copy(build / "debug/manifest.json", stage)
    shutil.copy(build / "fixture.json", stage)
    for name in ("xls_sim_bridge.c", "xls_sim_axis.h"):
        shutil.copy(ROOT / "test/rtl" / name, stage)
    # Alias-only instrumentation must not alter the observed application's cells.
    raw = json.loads((build / "debug/flat.json").read_text())["modules"]["phi_memory_top"]
    instrumented = json.loads((build / "debug/instrumented.json").read_text())["modules"]["hls_instrumented_application"]
    for section in ("ports", "netnames"):
        for name in ("hls_probe_values", "hls_actor_writes"):
            instrumented[section].pop(name)
    assert raw == instrumented, "instrumentation changed application logic"
    del raw, instrumented
    sources = [ROOT / "test/rtl/debug/hls_phi_debug_live_tb.sv", build / "debug/debug_top.v",
               build / "debug/instrumented.v", build / "production/phi_memory_top.v",
               build / "production/phi_memory_gateway.v", build / "production/hls_1r1w_ram.v",
               *[build / "support" / f"{name}.v" for name in (
                   "hls_fabric_router", "hls_debug_observer", "hls_debug_server")], *rtl_files(monitor=True)]
    with (stage / "compile.log").open("w") as log:
        for command in (["iverilog-vpi", "xls_sim_bridge.c"],
                        ["iverilog", "-g2012", "-s", "hls_phi_debug_live_tb", "-o", "test.vvp", *map(str, sources)]):
            subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    env = dict(os.environ, ERL_HLS_SIM_DIR=str(stage), ERL_HLS_SIM_TOP="hls_phi_debug_live_tb")
    for name in ("ERL_HLS_SIM_APP_ONLY", "ERL_HLS_SIM_DEBUG_ONLY", "ERL_HLS_SIM_PROFILE_ONLY", "ERL_HLS_SIM_SCHEDULER_PROFILE"):
        env.pop(name, None)
    with (stage / "simulation.log").open("w") as log:
        sim = subprocess.Popen(["vvp", "-M", str(stage), "-m", "xls_sim_bridge", "test.vvp"],
                               cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 30
            while not all((stage / name).exists() for name in ("app_tx", "app_rx", "debug_tx", "debug_rx")):
                if sim.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError((stage / "simulation.log").read_text())
                time.sleep(0.05)
            with (stage / "host.log").open("w") as host_log:
                client = subprocess.run(["erl", "-noshell", "-pa", str(ROOT / "_build/test/lib/erl_hls/ebin"),
                    str(ROOT / "_build/test/lib/erl_hls/test"), "-eval",
                    'ok = hls_phi_debug_live:run(hd(init:get_plain_arguments())), halt().', "-extra", str(stage)],
                    cwd=ROOT, stdout=host_log, stderr=subprocess.STDOUT, timeout=600)
            if client.returncode:
                raise RuntimeError((stage / "host.log").read_text())
            if sim.wait(timeout=30):
                raise RuntimeError((stage / "simulation.log").read_text())
        finally:
            if sim.poll() is None:
                sim.terminate()
                sim.wait(timeout=10)
    print((stage / "host.log").read_text(), end="")
    for line in (stage / "simulation.log").read_text().splitlines():
        if line.startswith("PASS:"):
            print(line)
    print(f"Saved public observations and simulator diagnostics in {stage}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("_build/phi-debug/live"))
    args = parser.parse_args()
    run(args.build.resolve(), args.stage.resolve())
