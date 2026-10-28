#!/usr/bin/env python3
"""Measure DSP/resource thresholds for narrower exact-rounded phi bulk recurrences."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path: Path) -> str:
    """Fingerprint the compiler and arithmetic sources used by the width screen."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def measure(args: argparse.Namespace, width: int) -> dict:
    """Synthesize one recurrence; this measures neither numerical adequacy nor clock timing."""
    stage = args.stage / str(width)
    stage.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(args.library, stage / 'hls_fixed.x')
    if (dependency := args.library.with_name('hls_multiply.x')).exists():
        shutil.copyfile(dependency, stage / dependency.name)
    (stage / 'bulk.x').write_text(f'''import hls_fixed;
// Four width-{width} neighbors fit in the signed {width+2}-bit sum.
pub fn main(a: sN[{width}], b: sN[{width}], sum: sN[{width+2}]) -> sN[{width}] {{
  let numerator = (a as sN[{width+5}]) + sN[{width+5}]:7 * (b as sN[{width+5}]) +
    (sum as sN[{width+5}]);
  hls_fixed::saturate<u32:{width}>(hls_fixed::round_ratio<u32:12>(numerator))
}}
''')
    commands = [
        ([str(args.xls / 'ir_converter_main'), '--top=main', '--dslx_path=.',
          '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), 'bulk.x'], 'design.ir'),
        ([str(args.xls / 'opt_main'), 'design.ir'], 'design.opt.ir'),
        ([str(args.xls / 'codegen_main'), '--generator=combinational', '--use_system_verilog=false',
          '--module_name=arithmetic', 'design.opt.ir'], 'arithmetic.v')]
    for command, output in commands:
        with (stage / output).open('w') as out, (stage / (output + '.log')).open('w') as err:
            subprocess.run(command, cwd=stage, stdout=out, stderr=err, check=True, timeout=180)
    (stage / 'map.ys').write_text('read_verilog arithmetic.v\nsynth_xilinx -flatten -abc9 -family xc7 '
        '-top arithmetic -noiopad -noclkbuf\ncheck -assert\nscc -expect 0\ntee -o stat.json stat -json\n')
    with (stage / 'map.log').open('w') as log:
        subprocess.run([str(args.yosys), '-Q', '-T', '-s', 'map.ys'], cwd=stage,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    data = json.loads((stage / 'stat.json').read_text())
    counts = next(iter(data['modules'].values()))['num_cells_by_type']
    return {'width': width, 'counts': counts, 'commands': commands,
            'sources': {name: sha(stage / name) for name in ('bulk.x', 'hls_fixed.x', 'hls_multiply.x', 'arithmetic.v') if (stage / name).exists()}}


def main() -> None:
    """Require explicit compiler, native Yosys and unchanged rounding library."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'xls', 'yosys', 'library'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--widths', type=int, nargs='+', default=[32, 24, 20, 16, 12])
    args = parser.parse_args()
    if any(w < 2 or w > 32 for w in args.widths):
        parser.error('widths must be between 2 and 32')
    results = []
    for width in args.widths:
        result = measure(args, width)
        results.append(result)
        (args.stage / 'results.json').write_text(json.dumps({'measurements': results,
            'tools': {str(p): sha(p) for p in [args.yosys,
                *[args.xls / n for n in ('ir_converter_main', 'opt_main', 'codegen_main')]]}}, indent=2) + '\n')
        print(width, result['counts'], flush=True)


if __name__ == '__main__':
    main()
