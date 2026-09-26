#!/usr/bin/env python3
"""Compare the installed C++ estimator with the validation predictor on every probe."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import subprocess
from analyze import composed_estimate, operation_estimate
from characterize import sha
from expand import probe


def verify(auditor: Path, table: Path, plan: Path, stage: Path) -> None:
    """Require identical cell/routed predictions across the saved measurement grid."""
    rows = json.loads(plan.read_text())
    if not isinstance(rows, list):
        rows = rows['probes']
    training = defaultdict(list)
    for line in table.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        op, width, count, cell, routed = line.split()
        training[op, int(count)].append(dict(width=int(width), cell_ps=int(cell), routed_ps=int(routed)))
    source = ['package coverage']
    for index, row in enumerate(rows):
        ir = probe(row['op'], row['width'], row['count'])[0]
        ir = re.sub(r', id=[0-9]+', '', ir)
        source.append(f'fn shape_{index}' + ir.split('top fn main', 1)[1])
    stage.mkdir(parents=True, exist_ok=False)
    ir_path = stage/'coverage.ir'
    ir_path.write_text('\n'.join(source))
    result = {'inputs': {str(p): sha(p) for p in (auditor, table, plan)}, 'shapes': len(rows)}
    for field, routed in [('cell_ps', 'false'), ('routed_ps', 'true')]:
        command = [str(auditor), '--xc7_delay_table='+str(table),
                   '--xc7_routed_delays='+routed, str(ir_path)]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (stage/(field+'.tsv')).write_text(completed.stdout)
        (stage/(field+'.log')).write_text(completed.stderr)
        completed.check_returncode()
        actual = {int(parts[0].removeprefix('shape_')): int(parts[2])
                  for line in completed.stdout.splitlines()
                  if len(parts := line.split('\t')) >= 3 and parts[1] == 'result'}
        if len(actual) != len(rows):
            raise AssertionError('auditor omitted a probe result')
        for index, row in enumerate(rows):
            estimate = composed_estimate if row['op'].startswith('array2_') else operation_estimate
            expected = 0 if row['op'] == 'reverse' else estimate(training, row, field)
            if actual[index] != expected:
                raise AssertionError(f'{row}: {field}: C++ {actual[index]} != validation {expected}')
        result[field] = 'equal'
    (stage/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS: {len(rows)} shapes, cell and routed estimates agree')


def main() -> None:
    """Check a frozen campaign using the installed auditor, without running Vivado."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('auditor', 'table', 'plan', 'stage'):
        parser.add_argument('--'+name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    verify(args.auditor, args.table, args.plan, args.stage)


if __name__ == '__main__':
    main()
