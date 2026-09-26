#!/usr/bin/env python3
"""Audit and compare whole-package XLS schedules without a unit-delay fallback."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
from characterize import sha


def schedule_summary(path: Path) -> list[dict]:
    """Read per-proc bounds from XLS's emitted PackageScheduleProto text format."""
    result = []
    for entry in re.split(r'^schedules \{\s*$', path.read_text(), flags=re.MULTILINE)[1:]:
        name = re.search(r'^    function: "([^"]+)"$', entry, re.MULTILINE)
        if name is None:
            raise ValueError('schedule lacks its function name')
        row = {'function': name[1]}
        for field in ('min_clock_period_ps', 'target_clock_period_ps', 'length'):
            match = re.search(rf'^    {field}: ([0-9]+)$', entry, re.MULTILINE)
            if match is not None:
                row[field] = int(match[1])
        delays = [int(n) for n in re.findall(r'path_delay_ps: ([0-9]+)', entry)]
        row['max_stage_path_ps'] = max(delays, default=0)
        result.append(row)
    if not result:
        raise ValueError('no scheduled functions/procs')
    return sorted(result, key=lambda row: (-row['max_stage_path_ps'], row['function']))


def measure(args: argparse.Namespace) -> None:
    """Save input fingerprints, coverage, and equal-option schedules for both models."""
    args.stage.mkdir(parents=True, exist_ok=False)
    for source, name in [(args.ir, 'input.ir'), (args.table, 'table.tsv')]:
        shutil.copyfile(source, args.stage/name)
    options = json.loads(args.options.read_text())
    if not isinstance(options, list) or any(not isinstance(option, str) or not option.startswith('--') for option in options):
        raise ValueError('options must be a JSON array of --flag=value strings')
    if any(option.startswith(('--delay_model=', '--xc7_', '--output_')) for option in options):
        raise ValueError('model and output flags are controlled by the comparison')
    inputs = {'ir': sha(args.stage/'input.ir'), 'table': sha(args.stage/'table.tsv'), 'codegen': sha(args.codegen),
              'auditor': sha(args.audit), 'options': options}
    (args.stage/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
    with (args.stage/'coverage.tsv').open('w') as out, (args.stage/'coverage.log').open('w') as err:
        subprocess.run([str(args.audit), '--xc7_delay_table='+str(args.stage/'table.tsv'),
                        str(args.stage/'input.ir')], stdout=out, stderr=err, check=True, timeout=120)
    summary = {}
    for model in args.models:
        root = args.stage/model
        root.mkdir()
        flags = [f'--delay_model={model}', '--output_schedule_path=schedule.textproto',
                 '--output_block_ir_path=block.ir']
        if model == 'xc7_7030':
            flags.append('--xc7_delay_table='+str(args.stage/'table.tsv'))
        command = [str(args.codegen), *options, *flags, str(args.stage/'input.ir')]
        (root/'command.json').write_text(json.dumps(command, indent=2)+'\n')
        start = time.monotonic()
        with (root/'application.v').open('w') as out, (root/'codegen.log').open('w') as err:
            subprocess.run(command, cwd=root, stdout=out, stderr=err, check=True, timeout=args.timeout)
        rows = schedule_summary(root/'schedule.textproto')
        summary[model] = {'delay_units': 'ps' if model == 'xc7_7030' else 'unit_cost', 'seconds': round(time.monotonic()-start, 3), 'schedules': rows,
                          'rtl_sha256': sha(root/'application.v')}
        (args.stage/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
        print(model, 'scheduled', len(rows), 'procs/functions; largest modeled stage',
              rows[0]['max_stage_path_ps'], summary[model]['delay_units'], flush=True)


def main() -> None:
    """Require explicit tools, measured calibration, and the application's codegen flags."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('ir', 'table', 'codegen', 'audit', 'options', 'stage'):
        parser.add_argument('--'+name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--models', nargs='+', choices=('unit', 'xc7_7030'), default=['unit', 'xc7_7030'])
    parser.add_argument('--timeout', type=int, default=3600)
    measure(parser.parse_args())


if __name__ == '__main__':
    main()
