#!/usr/bin/env python3
"""Measure isolated mailbox-selector area as actor count changes; no timing claim."""
import argparse
import json
from pathlib import Path
import subprocess

from architecture import sha

ROOT = Path(__file__).resolve().parents[3]


def measure(args: argparse.Namespace, actors: int, variant: str) -> dict:
    """Compare the former sequential selector with parallel row choices."""
    stage = args.stage / f'{variant}-{actors}-{args.depth}'
    stage.mkdir(parents=True, exist_ok=False)
    expression = {
        'sequential': 'mailbox_refinement::reference(order[actor], occupied[actor], postponed[actor])',
        'parallel': 'mailbox::select_actor(order, occupied, postponed, actor)',
        'parallel-positions': 'mailbox::select(order[actor], occupied[actor], postponed[actor])',
    }[variant]
    source = stage / 'selector.x'
    source.write_text(f'''import mailbox;
import mailbox_refinement;
pub fn selector(order: u8[{args.depth}][{actors}], occupied: u8[{actors}],
    postponed: bool[{args.depth}][{actors}], actor: u32) -> (bool, u8, u8) {{
  {expression}
}}
''')
    commands = []
    for output, argv in (
            ('selector.ir', [str(args.xls / 'ir_converter_main'), '--top=selector',
                '--warnings_as_errors=false', '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'),
                '--dslx_path=' + str(ROOT / 'priv/xls/lib') + ':' + str(ROOT / 'test_data'), str(source)]),
            ('selector.opt.ir', [str(args.xls / 'opt_main'), str(stage / 'selector.ir')]),
            ('selector.v', [str(args.xls / 'codegen_main'), '--generator=combinational',
                '--module_name=selector', '--use_system_verilog=false', str(stage / 'selector.opt.ir')])):
        commands.append(argv)
        with (stage / output).open('w') as out, (stage / (output + '.stderr')).open('w') as err:
            subprocess.run(argv, stdout=out, stderr=err, check=True, timeout=120)
    script = stage / 'map.ys'
    script.write_text('read_verilog -sv selector.v\n'
                      'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top selector\n'
                      'check -assert\nscc -expect 0\ntee -o stat.json stat -json\n')
    argv = [str(args.yosys), '-Q', '-T', '-s', str(script)]
    commands.append(argv)
    with (stage / 'map.log').open('w') as log:
        subprocess.run(argv, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    (stage / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    stats = json.loads((stage / 'stat.json').read_text())['modules']['\\selector']['num_cells_by_type']
    return {'actors': actors, 'depth': args.depth, 'variant': variant, 'cells': stats,
            'luts': sum(n for kind, n in stats.items() if kind.startswith('LUT')),
            'artifacts': {p.name: sha(p) for p in stage.iterdir() if p.is_file()}}


def main() -> None:
    """Retain matched combinational area screens and exact input/tool identities."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('xls', 'yosys', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--actors', type=int, nargs='+', default=[2, 8, 16])
    parser.add_argument('--depth', type=int, default=5)
    parser.add_argument('--variants', nargs='+', choices=['sequential', 'parallel', 'parallel-positions'],
                        default=['sequential', 'parallel', 'parallel-positions'])
    args = parser.parse_args()
    if not 1 <= args.depth <= 255 or any(n < 1 for n in args.actors):
        raise ValueError('require positive actor counts and depth 1..255')
    inputs = [Path(__file__), ROOT / 'priv/xls/lib/mailbox.x', ROOT / 'test_data/mailbox_refinement.x',
              args.yosys, *[args.xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')]]
    identities = {str(p): sha(p) for p in inputs}
    results = []
    for actors in args.actors:
        for variant in args.variants:
            row = measure(args, actors, variant)
            results.append(row)
            print(actors, variant, row['luts'], flush=True)
    if identities != {str(p): sha(p) for p in inputs}:
        raise ValueError('measurement inputs changed')
    (args.stage / 'summary.json').write_text(json.dumps({'inputs': identities,
        'results': results, 'scope': 'isolated combinational area, not whole-core cost or timing'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
