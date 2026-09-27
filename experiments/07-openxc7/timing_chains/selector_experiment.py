#!/usr/bin/env python3
"""Prove and map balanced indexed selections with an explicit out-of-range default."""
import argparse
from collections import Counter
from functools import lru_cache
import json
from pathlib import Path
import re
import subprocess

from architecture import sha
from probe import harness, tool_files


def source(count: int, width: int, index_bits: int, balanced: bool) -> str:
    """Emit identical interfaces for flat/default and bit-indexed tree selections."""
    if not 2 <= count < 2**index_bits or width <= 0:
        raise ValueError('require positive width and a nonempty out-of-range domain')
    ports = [('index', index_bits), *[(f'v{i}', width) for i in range(count)], ('otherwise', width)]
    rows = ['package selector', '', 'top fn main(' + ', '.join(
        f'{name}: bits[{bits}]' for name, bits in ports) + f') -> bits[{width}] {{']
    next_id = len(ports) + 1

    def node(name: str, bits: int, expression: str, final: bool = False) -> str:
        """Assign unique IR ids to each explicit tree level."""
        nonlocal next_id
        rows.append(f'  {"ret " if final else ""}{name}: bits[{bits}] = {expression[:-1]}, id={next_id})')
        next_id += 1
        return name

    values = [f'v{i}' for i in range(count)]
    if not balanced:
        node('result', width, 'sel(index, cases=[' + ', '.join(values) + '], default=otherwise)', True)
    else:
        levels = (count - 1).bit_length()
        values += ['otherwise'] * ((1 << levels) - count)
        for level in range(levels):
            bit = node(f'bit{level}', 1, f'bit_slice(index, start={level}, width=1)')
            values = [node(f'level{level}_{i//2}', width,
                           f'sel({bit}, cases=[{values[i]}, {values[i+1]}])')
                      for i in range(0, len(values), 2)]
        if levels < index_bits:
            high = node('high', index_bits - levels, f'bit_slice(index, start={levels}, width={index_bits-levels})')
            outside = node('outside', 1, f'or_reduce({high})')
            node('result', width, f'sel({outside}, cases=[{values[0]}, otherwise])', True)
        else:
            node('result', width, f'identity({values[0]})', True)
    return '\n'.join(rows + ['}', ''])


def run(argv: list[str | Path], stage: Path, label: str, output: str | None = None) -> None:
    """Record commands and preserve bounded proof/compiler diagnostics."""
    argv = list(map(str, argv))
    (stage / (label + '.command.json')).write_text(json.dumps(argv) + '\n')
    with (stage / (output or label + '.log')).open('w') as out, (stage / (label + '.stderr')).open('w') as err:
        subprocess.run(argv, cwd=stage, stdout=out, stderr=err, timeout=240, check=True)


def structural_depth(mapped: dict) -> dict:
    """Measure conservative cell-level combinational depth between sequential boundaries.

    This is topology, not a delay estimator. All combinational inputs may affect
    each output; multi-bit hard arithmetic is rejected rather than inventing arcs.
    """
    top = next(iter(mapped['modules'].values()))
    drivers, endpoints = {}, []
    supported = {'INV', 'MUXF7', 'MUXF8', 'CARRY4', 'IBUF', 'OBUF', 'BUFG'}
    for name, cell in top['cells'].items():
        kind = cell['type']
        sequential = kind.startswith('FD')
        if kind not in supported and not sequential and not re.fullmatch(r'LUT[1-6]', kind):
            raise ValueError(f'unsupported structural primitive: {kind}')
        if sequential:
            endpoints += [b for b in cell['connections']['D'] if isinstance(b, int)]
        inputs = [] if sequential else [b for port, bits in cell['connections'].items()
                    if cell['port_directions'][port] == 'input' for b in bits if isinstance(b, int)]
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    if isinstance(bit, int):
                        if bit in drivers:
                            raise ValueError('multiple drivers')
                        drivers[bit] = (name, kind, inputs)

    @lru_cache(None)
    def depth(bit: int, mux_only: bool) -> int:
        """Compute a DAG longest path, stopping at launch flip-flops or inputs."""
        if bit not in drivers:
            return 0
        _, kind, inputs = drivers[bit]
        if not inputs:
            return 0
        cost = int(kind == 'MUXF8') if mux_only else int(kind not in ('IBUF', 'OBUF', 'BUFG'))
        return cost + max((depth(i, mux_only) for i in inputs), default=0)

    return {'max_cells': max(depth(b, False) for b in endpoints),
            'max_muxf8': max(depth(b, True) for b in endpoints),
            'scope': 'structural upper bound, not timing or a sensitizable-path proof'}


def prepare(args: argparse.Namespace) -> None:
    """Prove every arbitrary payload/index combination before mapping each pair."""
    inputs = {str(p): sha(p) for p in [args.codegen, *tool_files(args.yosys),
                                     Path(__file__), Path(__file__).with_name('probe.py')]}
    args.stage.mkdir(parents=True, exist_ok=False)
    results = []
    for count in args.counts:
        root = args.stage / str(count)
        root.mkdir()
        for label in ('flat', 'tree'):
            stage = root / label
            stage.mkdir()
            (stage / 'selector.ir').write_text(source(count, args.width, args.index_bits, label == 'tree'))
            run([args.codegen, '--generator=combinational', '--use_system_verilog=false',
                 '--module_name=arithmetic', 'selector.ir'], stage, 'codegen', 'arithmetic.v')
        (root / 'proof.ys').write_text(
            'read_verilog flat/arithmetic.v\nrename arithmetic reference\n'
            'read_verilog tree/arithmetic.v\nrename arithmetic candidate\n'
            'miter -equiv -flatten reference candidate miter\n'
            'prep -top miter\nsat -verify -prove trigger 0 -set-def-inputs\n')
        run([args.yosys, '-Q', '-T', '-s', 'proof.ys'], root, 'proof')
        pair = {'count': count, 'width': args.width, 'index_bits': args.index_bits,
                'proof': {'verdict': 'equivalent', 'log_sha256': sha(root / 'proof.log')}, 'variants': {}}
        for label in ('flat', 'tree'):
            stage = root / label
            (stage / 'harness.v').write_text(harness((stage / 'arithmetic.v').read_text()))
            (stage / 'map.ys').write_text('read_verilog arithmetic.v harness.v\n'
                'synth_xilinx -flatten -abc9 -family xc7 -top timing_chain\n'
                'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
            run([args.yosys, '-Q', '-T', '-s', 'map.ys'], stage, 'map')
            mapped = json.loads((stage / 'mapped.json').read_text())
            mapped['modules'] = {'timing_chain': mapped['modules']['timing_chain']}
            (stage / 'mapped.json').write_text(json.dumps(mapped, separators=(',', ':')) + '\n')
            counts = Counter(c['type'] for c in mapped['modules']['timing_chain']['cells'].values())
            pair['variants'][label] = {'counts': dict(counts), 'depth': structural_depth(mapped),
                                      'files': {p.name: sha(p) for p in stage.iterdir() if p.is_file()}}
        results.append(pair)
        if inputs != {p: sha(Path(p)) for p in inputs}:
            raise ValueError('selector tools or runner changed during measurement')
        evidence = {'schema': 1, 'measurements': results, 'inputs': inputs}
        (args.stage / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps({label: row['depth'] for label, row in pair['variants'].items()}), flush=True)


def main() -> None:
    """Require explicit tools and a fresh stage for the selector screen."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'codegen', 'yosys'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--counts', nargs='+', type=int, default=[63, 65, 127])
    parser.add_argument('--width', type=int, default=24)
    parser.add_argument('--index-bits', type=int, default=8)
    args = parser.parse_args()
    if not 1 <= args.index_bits <= 12 or not 1 <= args.width <= 1024 or any(not 2 <= c < 2**args.index_bits for c in args.counts):
        parser.error('unsupported probe dimensions')
    prepare(args)


if __name__ == '__main__':
    main()
