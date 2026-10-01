#!/usr/bin/env python3
"""Compare packed samples with BEAM and diagnose failures through public AXI APIs."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def run(rtl, stage):
    stage.mkdir(parents=True, exist_ok=True)
    for name in ('app_tx', 'app_rx', 'debug_tx', 'debug_rx', 'release_app', 'done'):
        (stage / name).unlink(missing_ok=True)
    for name in ('xls_sim_bridge.c', 'xls_sim_axis.h'):
        shutil.copy(ROOT / 'test/rtl' / name, stage)
    sources = [ROOT / 'test/rtl/packed_samples_tb.sv', rtl / 'packed_samples.v',
               *[rtl / f'hls_debug_{name}.v' for name in ('observer', 'server')],
               *[ROOT / 'priv/rtl/debug' / name for name in (
                   'hls_debug_route.v', 'hls_debug_monitor.v', 'hls_debug_tap.v', 'hls_trace_store.v')]]
    with (stage / 'compile.log').open('w') as log:
        subprocess.run(['iverilog-vpi', 'xls_sim_bridge.c'], cwd=stage,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
        subprocess.run(['iverilog', '-g2012', '-s', 'packed_samples_tb', '-o', 'test.vvp',
                        *map(str, sources)], cwd=stage,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    env = dict(os.environ, ERL_HLS_SIM_DIR=str(stage), ERL_HLS_SIM_TOP='packed_samples_tb')
    for name in ('ERL_HLS_SIM_APP_ONLY', 'ERL_HLS_SIM_DEBUG_ONLY', 'ERL_HLS_SIM_PROFILE_ONLY',
                 'ERL_HLS_SIM_SCHEDULER_PROFILE'):
        env.pop(name, None)
    with (stage / 'simulation.log').open('w') as log:
        sim = subprocess.Popen(['vvp', '-M', str(stage), '-m', 'xls_sim_bridge', 'test.vvp'],
                               cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while not all((stage / name).exists() for name in ('app_tx', 'app_rx', 'debug_tx', 'debug_rx')):
                if sim.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError((stage / 'simulation.log').read_text())
                time.sleep(0.02)
            with (stage / 'host.log').open('w') as host:
                result = subprocess.run(['erl', '-noshell', '-pa',
                    str(ROOT / '_build/test/lib/erl_hls/ebin'), str(ROOT / '_build/test/lib/erl_hls/test'),
                    '-eval', 'ok = packed_samples_live:run(hd(init:get_plain_arguments())), halt().',
                    '-extra', str(stage)], cwd=stage, stdout=host, stderr=subprocess.STDOUT, timeout=120)
            if result.returncode:
                raise RuntimeError((stage / 'host.log').read_text())
            if sim.wait(timeout=10):
                raise RuntimeError((stage / 'simulation.log').read_text())
        finally:
            if sim.poll() is None:
                sim.terminate()
                sim.wait(timeout=10)
    print((stage / 'host.log').read_text(), end='')
    print(f'Saved public counter and trace observations in {stage}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=Path)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/binary/live')
    args = parser.parse_args()
    run(args.rtl.resolve(), args.stage.resolve())
