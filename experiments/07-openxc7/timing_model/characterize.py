#!/usr/bin/env python3
"""Prepare XLS operations mapped by native Yosys for exact-part Vivado timing."""
import argparse
from collections import Counter
import hashlib
import json
import math
import re
from pathlib import Path
import subprocess

BINARY = ('add', 'sub', 'umul', 'smul', 'eq', 'ult', 'slt', 'sgt', 'and', 'or', 'xor', 'shll', 'shrl', 'shra')
UNARY = ('neg', 'not', 'and_reduce', 'or_reduce', 'xor_reduce', 'reverse')


def operation(op: str, width: int, count: int = 2) -> tuple[str, list[tuple[str, int]], int]:
    """Return a single-node IR function, its input ports, and result width."""
    specialized = re.fullmatch(r'smul_const_(\d+)_(\d+)_(\d+)_(\d+)', op)
    if specialized:
        lhs, rhs, result, value = map(int, specialized.groups())
        if width != result or not (0 < lhs <= 128 and 0 < rhs <= 64 and 0 <= value < (1 << rhs)):
            raise ValueError('invalid constant-multiply shape')
        ir = (f'package probe\n\ntop fn main(a: bits[{lhs}]) -> bits[{result}] {{\n'
              f'  constant: bits[{rhs}] = literal(value={value}, id=2)\n'
              f'  ret result: bits[{result}] = smul(a, constant, id=3)\n}}\n')
        return ir, [('a', lhs)], result
    ports = [('a', width)]
    result = 1 if op in ('eq', 'ult', 'slt', 'sgt', 'and_reduce', 'or_reduce', 'xor_reduce') else width
    operands = 'a'
    if op in BINARY:
        ports.append(('b', width))
        operands = 'a, b'
    elif op in ('sel', 'one_hot_sel', 'priority_sel'):
        selector_width = count if op != 'sel' else math.ceil(math.log2(count))
        ports = [('selector', selector_width)] + [(f'v{i}', width) for i in range(count)]
        operands = 'selector, cases=[' + ', '.join(n for n, _ in ports[1:]) + ']'
        if op == 'priority_sel':
            ports.append(('otherwise', width))
            operands += ', default=otherwise'
    elif op not in UNARY:
        raise ValueError(op)
    args = ', '.join(f'{name}: bits[{bits}]' for name, bits in ports)
    ir = f'package probe\n\ntop fn main({args}) -> bits[{result}] {{\n'
    ir += f'  ret result: bits[{result}] = {op}({operands}, id={len(ports) + 1})\n}}\n'
    return ir, ports, result


def harness(name: str, ports: list[tuple[str, int]], result: int) -> str:
    """Wrap an operation in preserved fabric launch/capture registers."""
    decl = ', '.join(f'input wire [{bits-1}:0] {port}' for port, bits in ports)
    rows = [f'module probe_top(input wire clock, {decl}, output wire [{result-1}:0] out);']
    for port, bits in ports:
        rows.append(f'wire [{bits-1}:0] launch_{port};')
        for index in range(bits):
            rows.append(f'(* keep = 1, dont_touch = "yes" *) FDRE launch_{port}_{index} '
                        f'(.C(clock), .CE(1\'b1), .R(1\'b0), .D({port}[{index}]), .Q(launch_{port}[{index}]));')
    rows += [f'wire [{result-1}:0] value;',
             f'{name} dut(' + ', '.join(f'.{p}(launch_{p})' for p, _ in ports) + ', .out(value));']
    for index in range(result):
        rows.append(f'(* keep = 1, dont_touch = "yes" *) FDRE capture_{index} '
                    f'(.C(clock), .CE(1\'b1), .R(1\'b0), .D(value[{index}]), .Q(out[{index}]));')
    rows.append('endmodule\n')
    return '\n'.join(rows)


def sha(path: Path) -> str:
    """Hash a tool or input without retaining its contents in memory."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(argv: list[str | Path], directory: Path, label: str, output: Path | None = None) -> None:
    """Execute one bounded phase, preserving failure diagnostics."""
    with (directory / (label + '.log')).open('w') as log:
        if output:
            with output.open('w') as result:
                subprocess.run(list(map(str, argv)), cwd=directory, stdout=result, stderr=log,
                               check=True, timeout=180)
        else:
            subprocess.run(list(map(str, argv)), cwd=directory, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=180)


def prepare(args: argparse.Namespace) -> None:
    """Emit independent mapped probes and a manifest; do not overwrite old evidence."""
    args.stage.mkdir(parents=True, exist_ok=False)
    rows = []
    for op in args.ops:
        for width in args.widths:
            counts = (2, 4, 8) if op in ('sel', 'one_hot_sel', 'priority_sel') else (2,)
            for count in counts:
                name = f'{op}_{width}' + (f'_{count}' if op in ('sel', 'one_hot_sel', 'priority_sel') else '')
                root = args.stage / name
                root.mkdir()
                ir, ports, result = operation(op, width, count)
                (root / 'probe.ir').write_text(ir)
                run([args.codegen, '--generator=combinational', '--use_system_verilog=false',
                     '--module_name=operation', 'probe.ir'], root, 'codegen', root / 'operation.v')
                (root / 'harness.v').write_text(harness('operation', ports, result))
                (root / 'map.ys').write_text(
                    'read_verilog operation.v harness.v\n'
                    'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
                    'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
                run([args.yosys, '-Q', '-q', '-s', 'map.ys'], root, 'map')
                data = json.loads((root / 'mapped.json').read_text())
                top = data['modules']['probe_top']
                top['cells'] = {n: c for n, c in top['cells'].items() if c['type'] != '$scopeinfo'}
                data['modules'] = {'probe_top': top}
                (root / 'mapped.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
                run([args.yosys, '-Q', '-q', '-p',
                     'read_verilog -lib +/xilinx/cells_sim.v; read_json mapped.json; write_edif -pvector bra mapped.edf'], root, 'edif')
                cells = json.loads((root / 'mapped.json').read_text())['modules']['probe_top']['cells']
                if sum(c['type'] == 'FDRE' for c in cells.values()) != sum(w for _, w in ports) + result:
                    raise ValueError(f'{name}: fabric register boundary changed')
                for cell in cells.values():
                    if cell['type'] == 'DSP48E1' and any(int(v, 2) for k, v in cell['parameters'].items() if k.endswith('REG')):
                        raise ValueError(f'{name}: a register was absorbed into a DSP')
                rows.append({'name': name, 'op': op, 'width': width, 'count': count,
                             'split': 'validation' if width in (12, 24, 48) else 'training',
                             'counts': dict(Counter(c['type'] for c in cells.values())),
                             'files': {p.name: sha(p) for p in root.iterdir() if p.is_file()}})
                print(name, flush=True)
    manifest = {'schema': 1, 'part': 'xc7z030sbg485-1', 'flow': 'synth_xilinx -abc9',
                'tools': {str(p): sha(p) for p in (args.codegen, args.yosys)}, 'probes': rows}
    (args.stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


def main() -> None:
    """Require explicit tools; held-out widths remain labeled in every manifest."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('codegen', 'yosys', 'stage'):
        parser.add_argument('--' + name, type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument('--ops', nargs='+', default=list(BINARY + UNARY) + ['sel', 'one_hot_sel', 'priority_sel'])
    parser.add_argument('--widths', nargs='+', type=int, default=[4, 8, 16, 32, 64, 24])
    args = parser.parse_args()
    if any(w <= 0 for w in args.widths):
        parser.error('widths must be positive')
    prepare(args)


if __name__ == '__main__':
    main()
