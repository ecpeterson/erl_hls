#!/usr/bin/env python3
"""Inventory selection dimensions in canonical XLS IR against measured table bounds."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Any

SCOPES = re.compile(r'^(?:top )?(?:fn|proc|block) ([\w.]+)', re.M)
NODE = re.compile(r'\s*(?:ret )?([\w.]+): (.+?) = (sel|one_hot_sel|priority_sel)\((.*)\)\s*')
SELECTION = re.compile(r'^(?:sel|one_hot_sel|priority_sel)\(')
SCALARS = re.compile(r'\b([\w.]+):\s*bits\[(\d+)\](?!\[)')
DECLARATIONS = re.compile(r'^\s*(?:ret )?([\w.]+): bits\[(\d+)\] =', re.M)


def flat_width(text: str) -> int:
    """Count data bits in bits/token/tuple/array types; reject unsupported syntax."""
    tokens = re.findall(r'bits|token|[0-9]+|[][(),]', text)
    if ''.join(tokens) != re.sub(r'\s+', '', text):
        raise ValueError(f'unsupported IR type: {text}')
    position = 0

    def take(expected: str | None = None) -> str:
        """Consume one token and check punctuation when requested."""
        nonlocal position
        value = tokens[position]
        position += 1
        if expected is not None and value != expected:
            raise ValueError('unexpected type token')
        return value

    def parse() -> int:
        """Read one type and its array dimensions."""
        kind = take()
        if kind == 'bits':
            take('[')
            width = int(take())
            take(']')
        elif kind == 'token':
            width = 0
        elif kind == '(':
            width = 0
            if tokens[position] != ')':
                width = parse()
                while tokens[position] == ',':
                    take(',')
                    width += parse()
            take(')')
        else:
            raise ValueError('unexpected type')
        while position < len(tokens) and tokens[position] == '[':
            take('[')
            width *= int(take())
            take(']')
        return width

    try:
        width = parse()
        if position != len(tokens):
            raise ValueError('trailing type tokens')
        return width
    except (IndexError, ValueError) as error:
        raise ValueError(f'unsupported IR type: {text}') from error


def table_bounds(text: str) -> dict[tuple[str, int], int]:
    """Read maximum measured widths from validated five-column calibration rows."""
    bounds, seen = {}, set()
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        fields = line.split()
        if len(fields) != 5:
            raise ValueError(f'invalid calibration row: {line}')
        op = fields[0]
        width, count, cell, routed = map(int, fields[1:])
        if min(width, count) <= 0 or cell < 0 or routed < cell or (op, count, width) in seen:
            raise ValueError(f'invalid calibration row: {line}')
        seen.add((op, count, width))
        bounds[op, count] = max(width, bounds.get((op, count), 0))
    if not bounds:
        raise ValueError('empty calibration table')
    return bounds


def inventory(source: str, bounds: dict[tuple[str, int], int]) -> list[dict[str, Any]]:
    """Group selections by data width, case count and selector width, within scopes.

    This inventories dimensions, not IR validity or complete estimator coverage.
    Non-selection operations, operand properties and physical wiring need separate checks.
    """
    source = '\n'.join('' if line.lstrip().startswith('//') else line
                       for line in source.split('\n'))
    starts = list(SCOPES.finditer(source))
    if not starts:
        raise ValueError('no function/proc/block scopes in IR')
    groups = {}
    for index, start in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(source)
        body = source[start.start():end]
        symbols = {name: int(width) for name, width in SCALARS.findall(body.splitlines()[0])}
        symbols.update({name: int(width) for name, width in DECLARATIONS.findall(body)})
        first_line = source.count('\n', 0, start.start()) + 1
        for line_number, line in enumerate(body.splitlines(), first_line):
            if not SELECTION.match(line.partition(' = ')[2]):
                continue
            match = NODE.fullmatch(line)
            if match is None:
                raise ValueError(f'noncanonical selection at line {line_number}')
            name, kind, op, arguments = match.groups()
            cases = re.search(r'\bcases=\[([^\]]*)\]', arguments)
            selector = arguments.split(',', 1)[0].strip()
            if cases is None or selector not in symbols:
                raise ValueError(f'unresolved selection dimensions at line {line_number}')
            count = len(cases[1].split(',')) if cases[1].strip() else 0
            width, selector_width = flat_width(kind), symbols[selector]
            key = op, width, count, selector_width
            if key not in groups:
                maximum = bounds.get((op, count))
                reasons = []
                if width == 0:
                    reasons.append('zero_data_width')
                if maximum is None:
                    reasons.append('unmeasured_case_count')
                elif width > maximum:
                    reasons.append('wider_than_table')
                if op == 'sel' and (count not in (2, 4, 8) or selector_width != count.bit_length() - 1):
                    reasons.append('unmeasured_selector_width')
                groups[key] = dict(op=op, result_bits=width, case_count=count,
                                   selector_bits=selector_width, max_measured_bits=maximum,
                                   review_reasons=reasons, occurrences=0, examples=[])
            row = groups[key]
            row['occurrences'] += 1
            if len(row['examples']) < 3:
                row['examples'].append(dict(scope=start[1], node=name, line=line_number))
    return [groups[key] for key in sorted(groups)]


def main() -> None:
    """Write a fingerprinted dimension inventory without estimating or extending delays."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ir', type=Path)
    parser.add_argument('--table', type=Path, default=Path(__file__).with_name('xc7_7030.tsv'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() in {args.ir.resolve(), args.table.resolve()}:
        parser.error('output must not replace IR or calibration table')
    source, table = args.ir.read_bytes(), args.table.read_bytes()
    rows = inventory(source.decode(), table_bounds(table.decode()))
    result = dict(schema=1, scope='selection dimensions only; not a coverage or timing qualification',
                  ir_sha256=hashlib.sha256(source).hexdigest(), table_sha256=hashlib.sha256(table).hexdigest(),
                  selections=sum(row['occurrences'] for row in rows), shapes=rows)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{result["selections"]} selections; {len(rows)} distinct dimension sets; '
          f'{sum(row["occurrences"] for row in rows if row["review_reasons"])} require dimension review')


if __name__ == '__main__':
    main()
