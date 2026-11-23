#!/usr/bin/env python3
"""Measure an XLS arithmetic function between explicit fabric registers."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phi_timing import critical_paths, tool_files
from timing_coverage.check import check


def digest(path: Path) -> str:
    """Fingerprint a file without loading large device databases into memory."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def command(argv: list[str | Path], root: Path, label: str,
            output: Path | None = None) -> None:
    """Run a bounded phase with durable diagnostics and optional captured stdout."""
    with (root / (label + '.log')).open('w') as log:
        if output is None:
            subprocess.run(list(map(str, argv)), cwd=root, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=180)
        else:
            with output.open('w') as out:
                subprocess.run(list(map(str, argv)), cwd=root, stdout=out,
                               stderr=log, check=True, timeout=180)


def harness(rtl: str) -> str:
    """Preserve registered input stimulus and capture every result bit.

    The function must have vector inputs totaling at least three bits, one
    vector output named out, and optionally a pipeline clock named clk.
    Numerical correctness is checked separately; this is a timing harness.
    """
    ports = re.findall(r'  input wire \[(\d+):0\] (\w+)', rtl)
    result = re.search(r'  output wire \[(\d+):0\] out', rtl)
    width = sum(int(high) + 1 for high, _ in ports)
    if width < 3 or result is None:
        raise ValueError('unexpected function interface')
    all_inputs = set(re.findall(r'  input wire(?: \[\d+:0\])? (\w+)', rtl))
    if all_inputs - {name for _, name in ports} - {'clk'}:
        raise ValueError('scalar inputs other than clk are unsupported')
    output_width = int(result[1]) + 1
    lines = ['module timing_chain(input wire clock, output wire activity);',
             f'  (* keep = "true" *) reg [{width-1}:0] stimulus = 1;',
             f'  wire [{output_width-1}:0] value;',
             f'  (* keep = "true" *) reg [{output_width-1}:0] captured = 0;',
             '  reg activity_reg = 0;',
             '  always @(posedge clock) begin',
             f'    stimulus <= {{stimulus[{width-2}:0], stimulus[{width-1}] ^ stimulus[{width-3}] ^ stimulus[1] ^ stimulus[0]}};',
             '    captured <= value;', '    activity_reg <= ^captured;',
             '  end', '  assign activity = activity_reg;']
    offset, connects = 0, []
    if 'input wire clk' in rtl:
        connects.append('.clk(clock)')
    for high, port in ports:
        size = int(high) + 1
        connects.append(f'.{port}(stimulus[{offset+size-1}:{offset}])')
        offset += size
    lines += ['  arithmetic arithmetic(' + ', '.join(connects) + ', .out(value));',
              'endmodule']
    return '\n'.join(lines) + '\n'


def inputs(args: argparse.Namespace) -> dict[str, str]:
    """Fingerprint sources, standard library, harness driver, tools and device data."""
    paths = list(args.source.parent.glob('*.x'))
    paths += list((args.xls / 'xls/dslx/stdlib').rglob('*.x'))
    paths += [Path(__file__), args.chipdb,
              Path(__file__).resolve().parents[1] / 'xc7z030sbg485.xdc']
    paths += [args.xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')]
    for tool in (args.yosys, args.nextpnr):
        paths += tool_files(tool)
    return {str(path): digest(path) for path in sorted(set(paths))}


def run(args: argparse.Namespace) -> None:
    """Compile and route, rejecting omitted register boundaries and changing inputs."""
    args.stage.mkdir(parents=True, exist_ok=False)
    original = inputs(args)
    root = args.stage
    command([args.xls / 'ir_converter_main', '--top=main',
             f'--dslx_path={args.source.parent}',
             f'--dslx_stdlib_path={args.xls / "xls/dslx/stdlib"}', args.source],
            root, 'convert', root / 'design.ir')
    command([args.xls / 'opt_main', root / 'design.ir'],
            root, 'optimize', root / 'design.opt.ir')
    schedule = ['--generator=combinational'] if not args.stages else [
        f'--pipeline_stages={args.stages}', f'--delay_model={args.delay_model}',
        '--flop_inputs=false', '--flop_outputs=true']
    command([args.xls / 'codegen_main', *schedule, '--use_system_verilog=false',
             '--module_name=arithmetic', root / 'design.opt.ir'],
            root, 'codegen', root / 'arithmetic.v')
    (root / 'harness.v').write_text(harness((root / 'arithmetic.v').read_text()))
    (root / 'map.ys').write_text(
        'read_verilog -sv arithmetic.v harness.v\n'
        'synth_xilinx -flatten -abc9 -family xc7 -top timing_chain' +
        (' -nodsp' if args.no_dsp else '') +
        '\ncheck -assert\nscc -expect 0\nwrite_json mapped.json\n')
    command([args.yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map')
    cells = json.loads((root / 'mapped.json').read_text())['modules']['timing_chain']['cells']
    counts = Counter(cell['type'] for cell in cells.values())
    xdc = Path(__file__).resolve().parents[1] / 'xc7z030sbg485.xdc'
    (root / 'timing.xdc').write_text(
        xdc.read_text() + f'create_clock -period {1000/args.frequency} [get_ports clock]\n')
    start = time.monotonic()
    command([args.nextpnr, '--chipdb', args.chipdb, '--json', 'mapped.json',
             '--xdc', 'timing.xdc', '--seed', str(args.seed), '--freq', str(args.frequency),
             '--timing-allow-fail', '--report', 'timing.json', '--log', 'route.log',
             '--timing-coverage', 'coverage.json'], root, 'route')
    elapsed = time.monotonic() - start
    requirements = [{'type': 'SLICE_FFX', 'port': 'D', 'class': 'register_input'},
                    {'type': 'SLICE_FFX', 'port': 'Q', 'class': 'register_output'}]
    if counts['DSP48E1']:
        requirements += [{'type': 'DSP48E1_DSP48E1', 'port': 'P[0-9]+', 'class': 'comb_output'},
                         {'type': 'DSP48E1_DSP48E1', 'port': '[AB][0-9]+', 'class': 'comb_input'}]
    audit = check(json.loads((root / 'coverage.json').read_text()), requirements)
    if not audit['endpoint_requirements_met'] or any(key.startswith(('RAM', 'SRL')) for key in counts):
        raise ValueError('unmodeled timing boundaries in arithmetic probe')
    if original != inputs(args):
        raise ValueError('inputs changed during measurement')
    raw = json.loads((root / 'timing.json').read_text())
    if len(raw['fmax']) != 1:
        raise ValueError('expected one measured clock')
    report = {'inputs': original, 'cell_counts': dict(counts), 'coverage': audit,
              'fmax': raw['fmax'], 'critical_paths': critical_paths((root / 'route.log').read_text()),
              'route_seconds': elapsed, 'seed': args.seed, 'stages': args.stages,
              'delay_model': args.delay_model, 'no_dsp': args.no_dsp,
              'target_mhz': args.frequency, 'design_wide_clock_validated': False,
              'outputs': {path.name: digest(path) for path in root.iterdir() if path.is_file()}}
    (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'case': args.source.stem, 'fmax': raw['fmax'],
                      'LUT': sum(value for key, value in counts.items() if re.fullmatch('LUT[1-6]', key)),
                      'FF': sum(value for key, value in counts.items() if key.startswith('FD')),
                      'DSP': counts['DSP48E1'], 'carry': counts['CARRY4']}), flush=True)


def main() -> None:
    """Require pinned tools and a fresh output directory for each candidate/seed."""
    parser = argparse.ArgumentParser(description=__doc__)
    paths = ('source', 'stage', 'xls', 'yosys', 'nextpnr', 'chipdb')
    for name in paths:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--stages', type=int, default=0, help='zero selects combinational codegen')
    parser.add_argument('--delay-model', choices=('unit', 'asap7', 'sky130'), default='unit')
    parser.add_argument('--no-dsp', action='store_true')
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--frequency', type=float, default=100)
    args = parser.parse_args()
    if args.stages < 0 or args.seed < 1 or not math.isfinite(args.frequency) or args.frequency <= 0:
        parser.error('stages must be nonnegative; seed/frequency must be positive')
    for name in paths:
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == '__main__':
    main()
