#!/usr/bin/env python3
"""Extract conservative primitive arcs from a Vivado SDF in picoseconds."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import re
from typing import Any, Iterator


def parse(text: str) -> list[Any]:
    """Parse balanced S-expressions, preserving quoted strings and escaped pin names."""
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text)
    stack: list[list[Any]] = [[]]
    for token in tokens:
        if token == '(':
            child: list[Any] = []
            stack[-1].append(child)
            stack.append(child)
        elif token == ')':
            if len(stack) == 1:
                raise ValueError('unmatched SDF closing parenthesis')
            stack.pop()
        else:
            stack[-1].append(token.strip('"'))
    if len(stack) != 1 or len(stack[0]) != 1 or not stack[0][0] or stack[0][0][0] != 'DELAYFILE':
        raise ValueError('incomplete SDF delay file')
    return stack[0][0]


def walk(tree: list[Any], tag: str) -> Iterator[list[Any]]:
    """Yield tagged subexpressions in document order."""
    if tree and tree[0] == tag:
        yield tree
    for value in tree:
        if isinstance(value, list):
            yield from walk(value, tag)


def pin(value: str | list[Any]) -> str:
    """Name the terminal of a plain, edge-qualified or conditional timing port."""
    if isinstance(value, list):
        return pin(value[1] if value[0] in ('posedge', 'negedge') else value[-1])
    return re.sub(r'\\(.)', r'\1', value)


def maximum(value: list[Any]) -> float:
    """Take the slowest finite member of an SDF rise/fall min:typ:max tuple."""
    numbers = [float(n) for entry in value for n in str(entry).split(':') if n]
    if not numbers or not all(math.isfinite(number) for number in numbers):
        raise ValueError('empty delay tuple')
    return max(numbers)


def extract(path: Path) -> list[dict[str, Any]]:
    """Retain separate instance/mode arcs; do not treat missing timing as zero."""
    tree = parse(path.read_text())
    timescale = next(walk(tree, 'TIMESCALE'))[1:]
    scale = ''.join(timescale)
    if scale != '1ps':
        raise ValueError(f'expected picosecond SDF, got {scale}')
    rows = []
    for cell in walk(tree, 'CELL'):
        kind = next(walk(cell, 'CELLTYPE'))[1]
        instance = next(walk(cell, 'INSTANCE'))
        name = pin(instance[1]) if len(instance) > 1 else '@top'
        arcs = []
        for arc in walk(cell, 'IOPATH'):
            arcs.append({'kind': 'propagation', 'from': pin(arc[1]), 'to': pin(arc[2]),
                         'ps': max(maximum(v) for v in arc[3:] if isinstance(v, list))})
        for tag in ('SETUPHOLD', 'SETUP', 'HOLD', 'RECREM', 'RECOVERY', 'REMOVAL'):
            for arc in walk(cell, tag):
                labels = {'SETUPHOLD': ('setup', 'hold'), 'RECREM': ('recovery', 'removal')}.get(tag, (tag.lower(),))
                for label, delay in zip(labels, arc[3:]):
                    arcs.append({'kind': label, 'from': pin(arc[1]), 'to': pin(arc[2]), 'ps': maximum(delay)})
        rows.append({'cell': kind, 'instance': name, 'arcs': arcs})
    return rows


def main() -> None:
    """Write all cell arcs as JSON, leaving interpretation of modes to the consumer."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(extract(args.input), indent=2) + '\n')


if __name__ == '__main__':
    main()
