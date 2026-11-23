#!/usr/bin/env python3
"""Exercise two virtual FPGA nodes hosted in one BEAM against routed RTL.

Run rebar3 eunit first. RTL_DIR must contain the pinned public regression's
regsvc.v, hls_debug_observer.v and hls_debug_server.v. No XLS build is repeated.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from backend_paths import erlang_paths, erlang_environment

ROOT = Path(__file__).resolve().parents[1]


def run(public: Path, rtl: Path, stage: Path, carrier: str) -> None:
    """Check retained RTL hashes and exercise two nodes with the supplied compiler's test beams."""
    manifest = dict((name, digest) for digest, name in
                    (line.split() for line in (public / 'test/golden/xls_verilog.sha256').read_text().splitlines()))
    generated = [rtl / name for name in ('regsvc.v', 'hls_debug_observer.v', 'hls_debug_server.v')]
    hashes = {source.name: hashlib.sha256(source.read_bytes()).hexdigest() for source in generated}
    if hashes['regsvc.v'] != manifest['regsvc.v']:
        raise RuntimeError('regsvc RTL does not match the pinned public golden')
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'rtl-sha256.json').write_text(json.dumps(hashes, sort_keys=True, indent=2) + '\n')
    sources = [ROOT / 'test/rtl/device_services_tb.sv', ROOT / 'test/rtl/hls_device_services.sv',
               ROOT / 'apps/hls_lowering/priv/rtl/hls_return_routes.v',
               public / 'src/examples/regsvc/regsvc_core_adapter.v',
               public / 'src/examples/regsvc/regsvc_debug_top.v',
               *sorted((public / 'priv/rtl/fabric').glob('*.v')),
               *[public / 'priv/rtl/debug' / name for name in
                 ('hls_debug_monitor.v', 'hls_debug_tap.v', 'hls_trace_store.v')], *generated]
    for name in ('xls_sim_bridge.c', 'xls_sim_axis.h'):
        shutil.copy(public / 'test/rtl' / name, stage)
    with (stage / 'compile.log').open('w') as log:
        subprocess.run(['iverilog', '-g2012', '-s', 'fabric_services_tb', '-o', str(stage / 'device.vvp'),
                        *map(str, sources)], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        subprocess.run(['iverilog-vpi', 'xls_sim_bridge.c'], cwd=stage, stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=60)
    simulations, logs = [], []
    try:
        for name in ('a', 'b'):
            board = stage / name
            board.mkdir()
            if name == 'b':
                (board / 'release_app').touch()
            log = (board / 'simulation.log').open('w')
            logs.append(log)
            env = {key: value for key, value in os.environ.items() if not key.startswith('ERL_HLS_SIM_')}
            env.update(ERL_HLS_SIM_DIR=str(board), ERL_HLS_SIM_TOP='fabric_services_tb')
            simulations.append(subprocess.Popen(['vvp', '-M', str(stage), '-m', 'xls_sim_bridge',
                                                  str(stage / 'device.vvp')], cwd=board, env=env,
                                                 stdout=log, stderr=subprocess.STDOUT))
        deadline = time.monotonic() + 15
        while not all((stage / board / name).exists() for board in ('a', 'b')
                      for name in ('app_tx', 'app_rx', 'debug_tx', 'debug_rx')):
            if any(p.poll() is not None for p in simulations) or time.monotonic() > deadline:
                raise RuntimeError(f'simulator startup failed; see {stage}')
            time.sleep(0.02)
        paths = erlang_paths('test', compiler=public)
        with (stage / 'host.log').open('w') as log:
            subprocess.run(['erl', '+S', '2:2', '-noshell', '-proto_dist', carrier, '-pa', *map(str, paths), '-eval',
                            '[A,B] = init:get_plain_arguments(), ok = hls_device_rtl:run(A,B), halt().',
                            '-extra', str(stage / 'a'), str(stage / 'b')], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90,
                           env=erlang_environment('test', compiler=public))
        for process in simulations:
            if process.wait(timeout=10):
                raise RuntimeError(f'simulator failed; see {stage}')
    finally:
        for process in simulations:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for log in logs:
            log.close()
    print((stage / 'host.log').read_text(), end='')
    print(f'Public debug observations saved in {stage}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', type=Path)
    parser.add_argument('--erl-hls', type=Path, required=True)
    parser.add_argument('--carrier', choices=['inet_tcp', 'hls_local'], default='inet_tcp')
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/rtl-devices')
    args = parser.parse_args()
    run(args.erl_hls.resolve(), args.rtl.resolve(), args.stage.resolve(), args.carrier)
