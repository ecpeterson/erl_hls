#!/usr/bin/env python3
"""Isolate actual mapped BRAM modes behind explicit fabric measurement registers."""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Any
from characterize import run, sha


def literal(value: str) -> str:
    """Express a Yosys parameter without changing its width or string value."""
    return f"{len(value)}'b{value}" if set(value) <= set('01xz') else json.dumps(value)


def fixture(cell: dict[str, Any], registered: bool) -> str:
    """Exercise the mapped constant/control configuration and every data output."""
    # Uninitialized memory contents are irrelevant to timing; choose defined probe data.
    parameters = {k: v.replace('x', '0') if k.startswith(('INIT', 'SRVAL')) else v
                  for k, v in cell['parameters'].items()}
    parameters.update(DOA_REG=str(int(registered)), DOB_REG=str(int(registered)))
    declarations, body, bindings = [], [], []
    for port, bits in cell['connections'].items():
        width = len(bits)
        direction = cell['port_directions'][port]
        if port in ('CLKARDCLK', 'CLKBWRCLK'):
            bindings.append(f'.{port}(clock)')
        elif direction == 'input':
            declarations.append(f'input wire [{width-1}:0] in_{port}')
            body.append(f'wire [{width-1}:0] r_{port};')
            for index, bit in enumerate(bits):
                if isinstance(bit, str):
                    body.append(f"assign r_{port}[{index}] = 1'b{bit};")
                else:
                    body.append(f'(* keep = 1 *) FDRE launch_{port}_{index} '
                                f"(.C(clock), .CE(1'b1), .R(1'b0), .D(in_{port}[{index}]), .Q(r_{port}[{index}]));")
            bindings.append(f'.{port}(r_{port})')
        elif port.startswith(('DO', 'DOP')):
            declarations.append(f'output wire [{width-1}:0] out_{port}')
            body.append(f'wire [{width-1}:0] r_{port};')
            for index in range(width):
                body.append(f'(* keep = 1 *) FDRE capture_{port}_{index} '
                            f"(.C(clock), .CE(1'b1), .R(1'b0), .D(r_{port}[{index}]), .Q(out_{port}[{index}]));")
            bindings.append(f'.{port}(r_{port})')
    body.append(cell['type'] + ' #(\n' + ',\n'.join(f'.{k}({literal(v)})' for k, v in parameters.items()) +
                '\n) memory(\n' + ',\n'.join(bindings) + '\n);')
    return 'module probe_top(input wire clock,\n' + ',\n'.join(declarations) + ');\n' + '\n'.join(body) + '\nendmodule\n'


def prepare(mapped: Path, stage: Path, yosys: Path) -> None:
    """Map each distinct application RAM mode, with and without its output register."""
    modes = {}
    for module in json.loads(mapped.read_text())['modules'].values():
        for cell in module.get('cells', {}).values():
            if cell['type'] in ('RAMB18E1', 'RAMB36E1'):
                key = cell['type'], json.dumps(cell['parameters'], sort_keys=True)
                modes[key] = cell
    if not modes:
        raise ValueError('no RAMB18E1/RAMB36E1 modes found')
    stage.mkdir(parents=True, exist_ok=False)
    rows = []
    for index, cell in enumerate(modes.values()):
        for registered in (False, True):
            name = f"ram_{index}_{cell['type']}_reg{int(registered)}"
            root = stage / name
            root.mkdir()
            (root / 'fixture.v').write_text(fixture(cell, registered))
            (root / 'map.ys').write_text('read_verilog fixture.v\n'
                'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
                'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n'
                'write_edif -pvector bra mapped.edf\n')
            run([yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map')
            data = json.loads((root / 'mapped.json').read_text())
            data['modules'] = {'probe_top': data['modules']['probe_top']}
            (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
            cells = data['modules']['probe_top']['cells']
            blocks = [c for c in cells.values() if c['type'].startswith('RAMB')]
            if len(blocks) != 1 or blocks[0]['type'] != cell['type']:
                raise ValueError(f'{name}: RAM boundary changed')
            rows.append({'name': name, 'split': 'primitive', 'registered': registered,
                         'counts': dict(Counter(c['type'] for c in cells.values())),
                         'parameters': blocks[0]['parameters'],
                         'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
            print(name, flush=True)
    (stage / 'manifest.json').write_text(json.dumps({'schema': 1, 'part': 'xc7z030sbg485-1',
        'source_sha256': sha(mapped), 'yosys_sha256': sha(yosys), 'probes': rows}, indent=2) + '\n')


def main() -> None:
    """Require the application map, an explicit mapper, and a fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mapped', 'stage', 'yosys'):
        parser.add_argument(name, type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    prepare(args.mapped, args.stage, args.yosys)


if __name__ == '__main__':
    main()
