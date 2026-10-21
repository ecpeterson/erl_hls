#!/usr/bin/env python3
"""Prove finite-width control cancellation, preserving other uses of the arithmetic result."""
import argparse
from pathlib import Path

from ir_rewrite_check import compile_passes, equivalent, finish, rewrite


def fixture(width: int, op: str) -> str:
    """Expose both comparison orders, equality senses, and the unchanged full arithmetic result."""
    return f'''package cancellation

top fn test(a: bits[{width}] id=1, b: bits[{width}] id=2) -> bits[{width + 4}] {{
  changed: bits[{width}] = {op}(a, b, id=3)
  e0: bits[1] = eq(changed, a, id=4)
  e1: bits[1] = eq(a, changed, id=5)
  n0: bits[1] = ne(changed, a, id=6)
  n1: bits[1] = ne(a, changed, id=7)
  ret result: bits[{width + 4}] = concat(changed, e0, e1, n0, n1, id=8)
}}
'''


def main() -> None:
    """Require a fresh stage and prove all listed instances, then reject a wrong equality sense."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage, xls = args.stage.resolve(), args.xls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    ebin = compile_passes(stage, ['xls_ir_control'])
    rows = []
    for width in [1, 2, 8, 12, 32, 64, 699]:
        for op in ['add', 'sub', 'xor']:
            case = stage / f'{op}-{width}'
            case.mkdir()
            (case / 'input.ir').write_text(fixture(width, op))
            audit = rewrite(case, ebin, 'xls_ir_control')
            assert len(audit['changes']) == 4
            equivalent(case, xls, args.yosys)
            rows.append({'width': width, 'operation': op, 'comparisons': 4, 'passed': True})
    case = stage / 'negative'
    case.mkdir()
    (case / 'input.ir').write_text(fixture(32, 'add'))
    correct = (stage / 'add-32/candidate.ir').read_text()
    broken = correct.replace('e0: bits[1] = eq(', 'e0: bits[1] = ne(')
    assert correct != broken
    (case / 'broken.ir').write_text(broken)
    equivalent(case, xls, args.yosys, 'broken.ir', reject=True)
    rows.append({'wrong_comparison_rejected': True})
    finish(stage, ebin, xls, args.yosys, rows,
           'All a/b binary valuations at each width, both eq/ne orders; complete arithmetic and comparison outputs.')
    print('21 finite circuits pass; wrong comparison rejected.')


if __name__ == '__main__':
    main()
