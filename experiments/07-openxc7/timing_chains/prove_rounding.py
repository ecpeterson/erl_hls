#!/usr/bin/env python3
"""Prove exact reciprocal rounding for all inputs at selected widths/divisors."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

WIDTHS = (1, 2, 8, 16, 31, 32, 33, 36, 37, 64, 129)
DIVISORS = (3, 5, 7, 10, 12, 13, 255, 1000, 2147483647, 4294967295)


def problem(width: int, divisor: int, *, round_up: bool = True) -> str:
    """Ask for an input whose reciprocal result differs from magnitude rounding.

    This proves the integer identity, not synthesis equivalence. The production
    DSLX separately widens its product to prevent overflow and has JIT tests.
    """
    shift = width + (divisor - 1).bit_length()
    reciprocal = ((1 << shift) + (divisor - 1 if round_up else 0)) // divisor
    return f'''(set-logic QF_LIA)
(set-option :timeout 5000)
(declare-const n Int)
(assert (and (>= n {-(1 << (width - 1))}) (<= n {(1 << (width - 1)) - 1})))
(define-fun reference () Int
  (ite (< n 0) (- (div (+ (- n) {divisor // 2}) {divisor}))
                 (div (+ n {divisor // 2}) {divisor})))
(define-fun candidate () Int
  (div (+ (* n {reciprocal}) {1 << (shift - 1)}) {1 << shift}))
(assert (not (= reference candidate)))
(check-sat)
'''


def solve(z3: Path, source: str) -> str:
    """Return the solver verdict; errors and timeouts cannot count as a proof."""
    result = subprocess.run([str(z3), '-in'], input=source, text=True,
                            capture_output=True, check=True, timeout=6)
    return result.stdout.strip()


def bulk_bound(neighbors: int = 4) -> str:
    """Ask whether bounded scalar inputs can overflow the rounded bulk average."""
    low, high = -(1 << 31), (1 << 31) - 1
    return f"""(set-logic QF_LIA)
(set-option :timeout 5000)
(declare-const a Int)
(declare-const b Int)
(declare-const neighbors Int)
(assert (and (>= a {low}) (<= a {high}) (>= b {low}) (<= b {high})
             (>= neighbors {neighbors * low}) (<= neighbors {neighbors * high})))
(define-fun n () Int (+ a (* 7 b) neighbors))
(define-fun rounded () Int
  (ite (< n 0) (- (div (+ (- n) 6) 12)) (div (+ n 6) 12)))
(assert (or (< rounded {low}) (> rounded {high})))
(check-sat)
"""


def main() -> None:
    """Retain each proof input and require detection of a wrong reciprocal."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--z3', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    proofs = []
    for width in WIDTHS:
        for divisor in DIVISORS:
            source = problem(width, divisor)
            verdict = solve(args.z3, source)
            if verdict != 'unsat':
                raise AssertionError((width, divisor, verdict))
            proofs.append({'width': width, 'divisor': divisor,
                           'verdict': verdict, 'smtlib': source})
    mutation = problem(37, 12, round_up=False)
    if solve(args.z3, mutation) != 'sat':
        raise AssertionError('failed to reject a downward-rounded reciprocal')
    bounds = bulk_bound()
    extra_neighbor = bulk_bound(5)
    if solve(args.z3, bounds) != 'unsat' or solve(args.z3, extra_neighbor) != 'sat':
        raise AssertionError('bulk range proof or fifth-neighbor mutation failed')
    result = {'bulk_bounds': bounds, 'rejected_fifth_neighbor': extra_neighbor,
              'scope': 'integer identities; not compiled RTL equivalence',
              'solver': subprocess.check_output([str(args.z3), '-version'], text=True).strip(),
              'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'proofs': proofs, 'rejected_mutation': mutation}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS: {len(proofs)} all-input proofs + bulk range; both mutations rejected')


if __name__ == '__main__':
    main()
