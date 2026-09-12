#!/usr/bin/env python3
"""Compare receive-path area with a git baseline using one native XLS/Yosys build.

Maps three-word receivers and the checked regsvc DSLX artifact to Xilinx 7-series
cells. This is a deterministic synthesis estimate, without placement or routing.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {'axis.x': 'priv/xls/lib/axis.x',
           'regsvc.x': 'src/examples/regsvc/regsvc.erl.x'}
RECEIVERS = '''import axis;
pub proc Raw { config(input: chan<axis::Beat> in, output: chan<axis::Frame> out) {
  spawn axis::Rx(input, output); } init { () } next(s: ()) { s } }
pub proc Reserved { config(input: chan<axis::Beat> in, output: chan<axis::Frame> out, credit: chan<u1> in) {
  spawn axis::ReservedRx(input, output, credit); } init { () } next(s: ()) { s } }
pub proc Checked { config(input: chan<axis::Beat> in, output: chan<axis::Frame> out) {
  spawn axis::RxN<u32:3>(input, output); } init { () } next(s: ()) { s } }
'''


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def measure(args):
    args.stage.mkdir(parents=True, exist_ok=True)
    baseline = git('rev-parse', '--verify', args.baseline + '^{commit}').decode().strip()
    report = {'baseline': baseline, 'head': git('rev-parse', 'HEAD').decode().strip(),
              'xls_root': str(args.xls_root), 'yosys': str(args.yosys),
              'yosys_version': subprocess.check_output([str(args.yosys), '-V']).decode().strip(),
              'tool_sha256': {name: digest(args.xls_root / name) for name in
                             ('ir_converter_main', 'opt_main', 'codegen_main')},
              'codegen': 'p1, unit delay, no input flops, output flops',
              'mapping': 'synth_xilinx -flatten -abc9 -arch xc7 -noiopad', 'results': []}
    for version in ('baseline', 'branch'):
        directory = args.stage / version
        directory.mkdir(exist_ok=True)
        (directory / 'receivers.x').write_text(RECEIVERS)
        hashes = {}
        for name, path in SOURCES.items():
            data = git('show', f'{baseline}:{path}') if version == 'baseline' else (ROOT / path).read_bytes()
            (directory / name).write_bytes(data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        for name in ('Raw', 'Reserved', 'Checked', 'regsvc'):
            prefix = directory / name
            source = directory / ('regsvc.x' if name == 'regsvc' else 'receivers.x')
            top = 'Top' if name == 'regsvc' else name
            with prefix.with_suffix('.log').open('w') as log:
                def run(command, output):
                    with output.open('w') as dest:
                        subprocess.run(list(map(str, command)), cwd=ROOT, stdout=dest,
                                       stderr=log, check=True)
                run([args.xls_root / 'ir_converter_main', '--warnings_as_errors=false', f'--top={top}',
                     f'--dslx_path={directory}:{ROOT / "priv/xls/lib"}',
                     f'--dslx_stdlib_path={args.xls_root / "xls/dslx/stdlib"}', source],
                    prefix.with_suffix('.ir'))
                run([args.xls_root / 'opt_main', prefix.with_suffix('.ir')], prefix.with_suffix('.opt.ir'))
                run([args.xls_root / 'codegen_main', '--pipeline_stages=1', '--delay_model=unit',
                     '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
                     '--module_name=measured', '--reset=reset', '--fifo_module=',
                     prefix.with_suffix('.opt.ir')], prefix.with_suffix('.v'))
                # JSON quoting also quotes these path strings for Yosys's script parser.
                rtl = json.dumps(str(prefix.with_suffix('.v')))
                stats = json.dumps(str(prefix.with_suffix('.json')))
                prefix.with_suffix('.ys').write_text(f'''read_verilog -sv {rtl}
hierarchy -check -top measured
proc
flatten
opt
check -assert
scc -expect 0
synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top measured
tee -o {stats} stat -json -tech xilinx
''')
                subprocess.run([str(args.yosys), '-Q', '-l', str(prefix.with_suffix('.yosys.log')),
                                '-s', str(prefix.with_suffix('.ys'))], stdout=log, stderr=log, check=True)
            cells = json.loads(prefix.with_suffix('.json').read_text())['design']['num_cells_by_type']
            row = {'version': version, 'case': name, 'source_sha256': hashes,
                   'LUT': sum(n for kind, n in cells.items() if kind.startswith('LUT')),
                   'FF': sum(n for kind, n in cells.items() if kind.startswith('FD')), 'cells': cells}
            report['results'].append(row)
            print(f"{version:8} {name:8} LUT={row['LUT']:5} FF={row['FF']:5}", flush=True)
            (args.stage / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls_root', type=Path)
    parser.add_argument('--baseline', default='origin/main')
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/application_frames_area')
    parser.add_argument('--yosys', type=Path, default=os.environ.get('ERL_HLS_YOSYS') or
                        shutil.which('yosys') or
                        ROOT / 'experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys')
    args = parser.parse_args()
    args.xls_root, args.stage, args.yosys = args.xls_root.resolve(), args.stage.resolve(), args.yosys.resolve()
    measure(args)
