"""One small Snowflake source-protocol integration witness against ordinary BEAM/reference frames."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment, application_directory


def bench(build: Path, stage: Path, vectors: dict) -> Path:
    """Wire only manifest public pins and score round order and correction order per logical sender."""
    manifest = json.loads((build / 'boundary/manifest.json').read_text())
    endpoints = {e['id']: e['index'] for e in manifest['externals']}
    assert set(endpoints) == {'rounds', 'corrections', 'unexpected'}
    rounds = [s['round_frame'] for s in vectors['sheets']]
    owners = sorted({c['source'] for s in vectors['sheets'] for c in s['corrections']})
    corrections = [[c['frame'] for s in vectors['sheets'] for c in s['corrections'] if c['source'] == owner]
                   for owner in owners]
    assert owners and all(len(fs) == 6 for fs in corrections)
    inputs = [s['input_frame'] for s in vectors['sheets']]
    declarations, connections, faults, diagnostics = [], ['.clk(clk)'], [], []
    for p in manifest['inputs'] + manifest['outputs']:
        name, width = p['name'], p['width']
        connections.append(f'.{name}({name})')
        if name not in {'reset', 'start_valid', 'ingress_valid', 'ingress_data'}:
            declarations.append(f'wire [{width-1}:0] {name};')
        if name.endswith(('_fault', '_failure')):
            faults.append('(|' + name + ')')
            diagnostics.append(f'if ({name}!=0) $display("{name}=%h",{name});')
    for e in manifest['externals']:
        i = e['index']
        declarations += [f'assign external_{i}_ready=ready[{i}];',
                         f'assign valid[{i}]=external_{i}_valid;', f'assign data[{i}]=external_{i}_data;']
    declarations += ['wire fault=' + ' | '.join(faults) + ';',
                     'protocol_boundary dut(' + ','.join(connections) + ');']
    tables = []
    for name, frames in [('input_frame', inputs), ('round_frame', rounds),
                         ('correction_frame', [f for fs in corrections for f in fs])]:
        tables += [f'function [127:0] {name}(input integer index);', 'case(index)']
        tables += [f"{i}: {name}=128'h{f};" for i, f in enumerate(frames)]
        tables += [f"default: {name}=128'bx;", 'endcase', 'endfunction']
    text = (ROOT / 'apps/hls_fabric/test/rtl/protocol_snowflake_tb.sv').read_text()
    replacements = {'@@FAULTS@@': '\n'.join(diagnostics), '@@WIRING@@': '\n'.join(declarations), '@@TABLES@@': '\n'.join(tables),
                    '@@OWNERS@@': str(len(owners)), '@@ROUNDS@@': str(endpoints['rounds']),
                    '@@CORRECTIONS@@': str(endpoints['corrections']), '@@UNEXPECTED@@': str(endpoints['unexpected'])}
    for token, value in replacements.items():
        text = text.replace(token, value)
    source = stage / 'bench.sv'
    source.write_text(text)
    return source


def qualify(build: Path, stage: Path, vectors: dict) -> None:
    """Compile the exact circuit once, then run its finite witness and a rejecting scoreboard control."""
    source = bench(build, stage, vectors)
    rtl = [build / p for p in (build / 'files.f').read_text().splitlines()]
    tracked = [source, *rtl, stage / 'vectors.json']
    hashes = {str(p): digest(p) for p in tracked}
    run(['verilator', '--binary', '--timing', '--top-module', 'tb', '--Mdir', stage / 'obj_dir',
         '-j', '1', '-Wno-fatal', '-o', 'simulation', source, *rtl], stage, 'verilator', timeout=300)
    simulation = stage / 'obj_dir/simulation'
    run([simulation], stage, 'simulation', timeout=60)
    log = (stage / 'simulation.log').read_text()
    assert 'SNOWFLAKE_PASS' in log and '%Fatal:' not in log
    with (stage / 'negative.log').open('x') as log:
        result = subprocess.run([simulation, '+corrupt'], stdout=log, stderr=subprocess.STDOUT, timeout=60)
    assert result.returncode != 0 and 'wrong round frame/order' in (stage / 'negative.log').read_text()
    assert hashes == {str(p): digest(p) for p in tracked}
    (stage / 'result.json').write_text(json.dumps({'passed': True, 'distance': 2, 'height': 2,
        'sheets': 8, 'input_hashes': hashes, 'negative_scoreboard_rejected': True,
        'evidence': 'Finite BEAM/reference/public-RTL witness with stalls and reset; no general equivalence, QEC or native performance claim.'}, indent=2) + '\n')


def main() -> None:
    """Emit one fresh small graph, calculate its independent reference and compile through the public tool boundary."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.stage.mkdir(parents=True)
    build = args.stage / 'build'
    env = erlang_environment('test')
    expression = '[Build, Vectors]=init:get_plain_arguments(),ok=hls_ci_snowflake:write(Build),ok=hls_ci_snowflake:oracle(Vectors),halt().'
    run(['erl', '-noshell', '-eval', expression, '-extra', build, args.stage / 'vectors.json'],
        args.stage, 'emit-reference', env=env)
    target = application_directory('hls_target', 'test')
    run([sys.executable, target / 'priv/tools/compile_source_build.py', args.xls, build],
        args.stage, 'xls', timeout=600)
    qualify((build / 'compiled').resolve(), args.stage, json.loads((args.stage / 'vectors.json').read_text()))


if __name__ == '__main__':
    main()
