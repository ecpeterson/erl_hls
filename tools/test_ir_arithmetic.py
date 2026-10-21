#!/usr/bin/env python3
"""Prove finite increment/comparison rewrites and reject broken prefix carries."""
import argparse
from pathlib import Path
import re

from ir_rewrite_check import compile_passes, equivalent, finish, rewrite

MODULES = ['xls_ir_increment_compare', 'xls_ir_conditional_increment', 'xls_ir_small_add']


def fixture(width: int, small: int, comparison: bool) -> str:
    """Expose both operand orders and all recognized increment encodings in complete results."""
    if comparison:
        return f'''package comparison

top fn test(x: bits[{width}] id=1, y: bits[{width}] id=2) -> bits[{2*width+4}] {{
  one: bits[{width}] = literal(value=1, id=3)
  a: bits[{width}] = add(y, one, id=4)
  b: bits[{width}] = add(one, y, id=5)
  e0: bits[1] = eq(x, a, id=6)
  e1: bits[1] = eq(b, x, id=7)
  n0: bits[1] = ne(a, x, id=8)
  n1: bits[1] = ne(x, b, id=9)
  ret result: bits[{2*width+4}] = concat(a, b, e0, e1, n0, n1, id=10)
}}
'''
    return f'''package addition

top fn test(x: bits[{width}] id=1, y: bits[{small}] id=2) -> bits[{6*width}] {{
  one: bits[{width}] = literal(value=1, id=3)
  zero: bits[{width-small}] = literal(value=0, id=4)
  ext: bits[{width}] = zero_ext(y, new_bit_count={width}, id=5)
  packed: bits[{width}] = concat(zero, y, id=6)
  s0: bits[{width}] = add(x, one, id=7)
  s1: bits[{width}] = add(ext, x, id=8)
  s2: bits[{width}] = add(x, packed, id=9)
  s3: bits[{width}] = add(one, x, id=10)
  s4: bits[{width}] = add(x, ext, id=11)
  s5: bits[{width}] = add(packed, x, id=12)
  ret result: bits[{6*width}] = concat(s0, s1, s2, s3, s4, s5, id=13)
}}
'''


def main() -> None:
    """Compile checkout passes and check all concrete domains plus one rejecting case per pass."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage, xls = args.stage.resolve(), args.xls.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    ebin = compile_passes(stage, ['xls_ir_rewrite', *MODULES])
    rows = []
    for module in MODULES:
        comparison = module == 'xls_ir_increment_compare'
        widths = [1, 8, 9, 16, 31, 32, 33, 65] if comparison else [8, 9, 16, 31, 32, 33, 65]
        smalls = [2, 3, 4] if module == 'xls_ir_small_add' else [1]
        for width in widths:
            for small in smalls:
                case = stage / f'{module}-{width}-{small}'
                case.mkdir()
                (case / 'input.ir').write_text(fixture(width, small, comparison))
                audit = rewrite(case, ebin, module)
                count = 4 if comparison or small > 1 else 6
                assert len(audit['changes']) == (count if width > 8 else 0)
                equivalent(case, xls, args.yosys)
                rows.append({'pass': module, 'width': width, 'small_width': small, 'passed': True})
        original = stage / f'{module}-32-{smalls[0]}'
        negative = stage / f'{module}-negative'
        negative.mkdir()
        (negative / 'input.ir').write_bytes((original / 'input.ir').read_bytes())
        broken, count = re.subn(r'and_reduce\([^\n]+?, id=', 'literal(value=0, id=',
                                (original / 'candidate.ir').read_text(), count=1)
        assert count == 1
        (negative / 'broken.ir').write_text(broken)
        equivalent(negative, xls, args.yosys, 'broken.ir', reject=True)
        rows.append({'pass': module, 'broken_prefix_rejected': True})
    finish(stage, ebin, xls, args.yosys, rows,
           'All binary operand valuations at each listed width, including overflow; both operand orders, complete outputs, literal/zero-extended/zero-concatenated increments.')
    print('36 finite circuits pass; all three broken prefix carries rejected.')


if __name__ == '__main__':
    main()
