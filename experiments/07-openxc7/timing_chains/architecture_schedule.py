#!/usr/bin/env python3
"""Extract stage-delay estimates while verifying unchanged generated application RTL."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(path: Path) -> str:
    """Fingerprint the scheduled RTL before discarding the duplicate output."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def measure(stage: Path) -> None:
    """Replay one successful codegen command with schedule reporting enabled."""
    records = json.loads((stage / 'commands.json').read_text())
    previous = next(row for row in records if row['label'] == 'codegen')
    if previous['exit'] != 0 or previous['output_sha256'] != sha(stage / 'phi_decoder_profile.v'):
        raise ValueError('the candidate lacks a verified successful build')
    report = stage / 'schedule.textproto'
    command = previous['command'][:-1] + ['--output_schedule_path=' + str(report), previous['command'][-1]]
    temporary = stage / 'schedule-replay.v'
    with temporary.open('w') as out, (stage / 'schedule-replay.log').open('w') as err:
        subprocess.run(command, cwd=stage, stdout=out, stderr=err, check=True, timeout=1200)
    if sha(temporary) != previous['output_sha256']:
        raise AssertionError('schedule-report replay changed the RTL')
    rows = []
    for entry in re.split(r'^schedules \{\s*$', report.read_text(), flags=re.M)[1:]:
        name = re.search(r'^    function: "([^"]+)"$', entry, re.M)
        delays = list(map(int, re.findall(r'path_delay_ps: ([0-9]+)', entry)))
        if name is None:
            raise ValueError('incomplete schedule report')
        rows.append({'function': name[1], 'max_stage_path_ps': max(delays, default=0)})
    if not rows:
        raise ValueError('empty schedule report')
    (stage / 'schedule-summary.json').write_text(json.dumps({
        'command': command, 'rtl_sha256': sha(temporary), 'report_sha256': sha(report),
        'delay_units': 'ps', 'schedules': sorted(rows, key=lambda r: -r['max_stage_path_ps'])}, indent=2) + '\n')
    temporary.unlink()
    print(stage.name, max(r['max_stage_path_ps'] for r in rows), 'ps', flush=True)


def main() -> None:
    """Analyze completed candidates without changing their sources or build outputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stages', type=lambda p: Path(p).resolve(), nargs='+')
    for stage in parser.parse_args().stages:
        measure(stage)


if __name__ == '__main__':
    main()
