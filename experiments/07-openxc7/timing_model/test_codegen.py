#!/usr/bin/env python3
"""Exercise the installed XLS estimator's rejection behavior with a native codegen."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from characterize import operation


def verify(codegen: Path, table: Path) -> None:
    """Require usable calibrated arithmetic and explicit failures outside its domain."""
    add = operation('add', 16)[0]
    wide_select = ('package probe\ntop fn main(s: bits[2], a: bits[16], b: bits[16], c: bits[16]) -> bits[16] {\n'
                   '  ret result: bits[16] = sel(s, cases=[a, b], default=c, id=5)\n}\n')
    nary = ('package probe\ntop fn main(a: bits[16], b: bits[16], c: bits[16]) -> bits[16] {\n'
            '  ret result: bits[16] = xor(a, b, c, id=4)\n}\n')
    cases = [('wide_select', wide_select, table.read_text(), 'select shape'),
             ('nary', nary, table.read_text(), 'no calibration'),
             ('valid', add, table.read_text(), None),
             ('missing', add, None, 'readable calibration'),
             ('empty', add, '', 'empty XC7'),
             ('malformed', add, 'add 16 2 -1 100\n', 'invalid XC7'),
             ('duplicate', add, 'add 16 2 100 200\n' * 2, 'duplicate XC7'),
             ('wide', operation('add', 128)[0], table.read_text(), 'width exceeds'),
             ('unsupported', add.replace('add(a, b', 'udiv(a, b'), table.read_text(), 'no calibration'),
             ('different_constant', operation('smul_const_37_39_76_183251937964', 76)[0],
              table.read_text(), 'width exceeds')]
    with tempfile.TemporaryDirectory(prefix='xc7-model-') as directory:
        root = Path(directory)
        for name, source, data, error in cases:
            ir = root / (name + '.ir')
            calibration = root / (name + '.tsv')
            ir.write_text(source)
            if data is not None:
                calibration.write_text(data)
            result = subprocess.run([str(codegen), '--delay_model=xc7_7030', '--pipeline_stages=3',
                                     '--xc7_delay_table=' + str(calibration), str(ir)],
                                    capture_output=True, text=True, timeout=30)
            if error is None:
                if result.returncode:
                    raise AssertionError(result.stderr)
            # XLS's fallback-estimator chain may replace the model's specific error.
            elif result.returncode == 0 or not (error in result.stderr or
                    "No known delay model estimate for op" in result.stderr):
                raise AssertionError(f'{name}: expected {error!r}; got {result.stderr}')
            print(name, 'PASS')


def main() -> None:
    """Run optional tool integration checks; no Vivado or hardware is needed."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('codegen', type=lambda p: Path(p).resolve())
    parser.add_argument('table', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    verify(args.codegen, args.table)


if __name__ == '__main__':
    main()
