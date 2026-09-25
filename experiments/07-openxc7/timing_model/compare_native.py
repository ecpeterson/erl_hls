#!/usr/bin/env python3
"""Compare native timing before/after adding measured BRAM endpoint arcs."""
import argparse
import json
import re
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from timing_coverage.run import command, mapped_primitives, validate_modes, digest
from timing_coverage.check import check, requirements


def ram_harness(source: Path) -> str:
    """Exercise an isolated RAM mode with internal traffic and two physical I/O pins."""
    text = source.read_text()
    declarations = re.findall(r'(input|output) wire \[(\d+):0\] (\w+)', text.split(');', 1)[0])
    rows = ['module timing_coverage_fixture(input wire clock, output wire activity);',
            "reg [31:0] traffic = 32'h12345678;",
            "always @(posedge clock) traffic <= {traffic[30:0], traffic[31]^traffic[21]^traffic[1]^traffic[0]};"]
    bindings = ['.clock(clock)']
    outputs = []
    for number, (direction, upper, name) in enumerate(declarations):
        width = int(upper) + 1
        if direction == 'input':
            value = '{' + ','.join(f'traffic[{(bit + number) % 32}]' for bit in range(width)) + '}'
        else:
            rows.append(f'wire [{width-1}:0] {name};')
            outputs.append(name)
            value = name
        bindings.append(f'.{name}({value})')
    rows += ['ram_probe memory(' + ','.join(bindings) + ');',
             'assign activity = ^{' + ','.join(outputs) + '};', 'endmodule']
    return text.replace('module probe_top(', 'module ram_probe(', 1) + '\n'.join(rows) + '\n'


def compare(args: argparse.Namespace) -> None:
    """Route identical fixtures with both tools; preserve known coverage failures."""
    parent = Path(__file__).resolve().parents[1]
    args.stage.mkdir(parents=True, exist_ok=False)
    rows = []
    modes = ['logic', 'ram', 'ram_registered', 'dsp', 'dsp_registered', 'ram_dsp']
    application = sorted(args.application_ram.glob('*/fixture.v')) if args.application_ram else []
    modes += ['app_' + source.parent.name for source in application]
    for index, mode in enumerate(modes):
        root = args.stage / mode
        root.mkdir()
        if index < 6:
            source = parent / 'timing_coverage/fixture.v'
            read = f'read_verilog "{source}"\nchparam -set MODE {index} timing_coverage_fixture\n'
        else:
            (root / 'fixture.v').write_text(ram_harness(application[index - 6]))
            read = 'read_verilog fixture.v\n'
        (root / 'map.ys').write_text(read +
            'synth_xilinx -family xc7 -top timing_coverage_fixture\ncheck -assert\nscc -expect 0\nwrite_json mapped.json\n')
        command([args.yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map', 120)
        primitives = mapped_primitives(root / 'mapped.json')
        if index < 6:
            validate_modes(mode, primitives)
        (root / 'timing.xdc').write_text((parent / 'xc7z030sbg485.xdc').read_text() +
                                       'create_clock -period 10 [get_ports clock]\n')
        variants = {}
        for variant in ('baseline', 'calibrated'):
            command([getattr(args, variant), '--chipdb', args.chipdb, '--json', 'mapped.json',
                     '--xdc', 'timing.xdc', '--seed', '1', '--freq', '100', '--timing-allow-fail',
                     '--report', f'{variant}.json', '--timing-coverage', f'{variant}-coverage.json',
                     '--log', f'{variant}.log'], root, variant, 180)
            result = json.loads((root / f'{variant}.json').read_text())
            coverage = check(json.loads((root / f'{variant}-coverage.json').read_text()), requirements('ram' if mode.startswith('app_') else mode))
            variants[variant] = {'fmax': result['fmax'], 'coverage': coverage}
        if mode in ('logic', 'dsp', 'dsp_registered') and variants['baseline'] != variants['calibrated']:
            raise ValueError(f'{mode}: unrelated timing behavior changed')
        if (mode in ('ram', 'ram_registered', 'ram_dsp') or mode.startswith('app_')) and not variants['calibrated']['coverage']['endpoint_requirements_met']:
            raise ValueError(f'{mode}: measured RAM endpoints still absent')
        rows.append({'mode': mode, 'mapped': primitives, 'variants': variants})
        result = {'schema': 1, 'part': 'xc7z030sbg485-1', 'seed': 1, 'design_wide_clock_validated': False,
                  'tools': {name: digest(getattr(args, name)) for name in ('baseline', 'calibrated', 'yosys')}, 'runs': rows}
        (args.stage / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(mode, {k: v['fmax'] for k, v in variants.items()}, flush=True)


def main() -> None:
    """Require explicit baseline/calibrated tools and a fresh measurement directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'yosys', 'chipdb', 'baseline', 'calibrated'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--application-ram', type=Path)
    compare(parser.parse_args())


if __name__ == '__main__':
    main()
