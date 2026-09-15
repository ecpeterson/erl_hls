#!/usr/bin/env python3
"""Run generated services behind the configurable router, using public debug APIs.

RTL must contain regsvc.v and hls_debug_{observer,server}.v from the current
prepare_xls_sim/remote_xls_sim run. Requires compiled test BEAM modules.
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
    for name in ('app_tx', 'app_rx', 'debug_tx', 'debug_rx', 'app_held', 'release_app', 'done'):
        (stage / name).unlink(missing_ok=True)
    sources = [ROOT / 'test/rtl/regsvc_fabric_fixture.sv',
               ROOT / 'src/examples/regsvc/regsvc_core_adapter.v',
               ROOT / 'src/examples/regsvc/regsvc_debug_top.v',
               *sorted((ROOT / 'priv/rtl/fabric').glob('*.v')),
               *[ROOT / 'priv/rtl/debug' / name for name in (
                   'hls_debug_monitor.v', 'hls_debug_tap.v', 'hls_trace_store.v')],
               *[rtl / name for name in ('regsvc.v', 'hls_debug_observer.v', 'hls_debug_server.v')]]
    for name in ('xls_sim_bridge.c', 'xls_sim_axis.h'):
        shutil.copy(ROOT / 'test/rtl' / name, stage)
    with (stage / 'compile.log').open('w') as log:
        for top in ('regsvc_pair_tb', 'fabric_services_tb', 'regsvc_pair_harness_tb'):
            test_sources = ([ROOT / 'experiments/07-openxc7/regsvc_pair_harness_tb.sv',
                             ROOT / 'experiments/07-openxc7/regsvc_pair_harness.v']
                            if top == 'regsvc_pair_harness_tb' else [ROOT / f'test/rtl/{top}.sv'])
            subprocess.run(['iverilog', '-g2012', '-s', top, '-o', str(stage / f'{top}.vvp'),
                            *map(str, test_sources + sources)],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        subprocess.run(['iverilog-vpi', 'xls_sim_bridge.c'], cwd=stage,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
    for top in ('regsvc_pair_tb', 'regsvc_pair_harness_tb'):
        with (stage / f'{top}.log').open('w') as log:
            subprocess.run(['vvp', str(stage / f'{top}.vvp')],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
    env = dict(os.environ, ERL_HLS_SIM_DIR=str(stage), ERL_HLS_SIM_TOP='fabric_services_tb')
    for name in ('ERL_HLS_SIM_APP_ONLY', 'ERL_HLS_SIM_DEBUG_ONLY', 'ERL_HLS_SIM_PROFILE_ONLY', 'ERL_HLS_SIM_SCHEDULER_PROFILE'):
        env.pop(name, None)
    with (stage / 'simulation.log').open('w') as log:
        sim = subprocess.Popen(['vvp', '-M', str(stage), '-m', 'xls_sim_bridge', 'fabric_services_tb.vvp'],
                               cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while not all((stage / name).exists() for name in ('app_tx', 'app_rx', 'debug_tx', 'debug_rx')):
                if sim.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError((stage / 'simulation.log').read_text())
                time.sleep(0.02)
            with (stage / 'host.log').open('w') as host:
                subprocess.run(['erl', '-noshell', '-pa', str(ROOT / '_build/test/lib/erl_hls/ebin'),
                                str(ROOT / '_build/test/lib/erl_hls/test'), '-eval',
                                'ok = hls_fabric_services_live:run(hd(init:get_plain_arguments())), halt().',
                                '-extra', str(stage)], cwd=stage, stdout=host,
                               stderr=subprocess.STDOUT, check=True, timeout=120)
            if sim.wait(timeout=10):
                raise RuntimeError((stage / 'simulation.log').read_text())
        finally:
            if sim.poll() is None:
                sim.terminate()
                sim.wait(timeout=10)
    print((stage / 'regsvc_pair_tb.log').read_text(), end='')
    print((stage / 'regsvc_pair_harness_tb.log').read_text(), end='')
    print((stage / 'host.log').read_text(), end='')
    print(f'Saved public stall and recovery observations in {stage}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=Path)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/fabric-services')
    args = parser.parse_args()
    run(args.rtl.resolve(), args.stage.resolve())
