#!/usr/bin/env python3
"""Bounded snapshot equivalence for arbitrary writes, queries and later resets.

Proves eight clock steps against a register-array reference, starting with reset.
This is exhaustive within the bound, not an unbounded liveness/timing proof.
"""
import argparse
from pathlib import Path
import subprocess

from topology_debug import quote

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/actor-snapshot-formal')
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=True)
    # Larger banks also run in the 4096-cycle RTL test. Keep the exhaustive
    # arbitrary-history check small enough for the regular CI memory budget.
    for slots, mailbox, reduction in ((1, 0, 0), (1, 1, 66), (3, 0, 53), (9, 1, 59), (32, 0, 0)):
        prefix = args.stage / f'slots-{slots}-mailbox-{mailbox}-reduction-{reduction}'
        sources = [ROOT / 'test/rtl/debug/hls_actor_snapshot_formal.sv',
                   ROOT / 'priv/rtl/debug/hls_actor_snapshot.v']
        script = 'read_verilog -sv ' + ' '.join(map(quote, sources)) + '\n'
        script += f'chparam -set SLOTS {slots} -set MAILBOX {mailbox} -set REDUCTION_WIDTH {reduction} hls_actor_snapshot_formal\n'
        script += 'prep -top hls_actor_snapshot_formal -flatten\nmemory_map\nopt\n'
        script += 'sat -verify -prove match 1 -set-at 1 reset 1 -set-def-inputs -seq 8\n'
        prefix.with_suffix('.ys').write_text(script)
        with prefix.with_suffix('.log').open('w') as log:
            subprocess.run([args.yosys, '-Q', '-T', '-s', str(prefix.with_suffix('.ys'))],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        print(f'PASS: eight-step snapshot equivalence, {slots} slots, mailbox={mailbox}', flush=True)


if __name__ == '__main__':
    main()
