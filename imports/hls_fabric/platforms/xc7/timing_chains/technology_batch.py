#!/usr/bin/env python3
"""Run a bounded, resumable device comparison from immutable portable RTL."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def digest(path: Path) -> str:
    """Identify an input without loading a large RTL file into memory."""
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def execute(root: Path, job: dict, timeout: int) -> dict:
    """Run immutable jobs with bounded threads; reject changed evidence or RTL pins."""
    max_threads = job.get('max_threads', 2)
    if type(max_threads) is not int or not 1 <= max_threads <= 8:
        raise ValueError('max_threads must be an integer from 1 through 8')
    job = {**job, 'max_threads': max_threads}
    name = job['name']
    stop_after = job.get('stop_after', 'route')
    if stop_after not in ('synthesis', 'route'):
        raise ValueError('stop_after must be synthesis or route')
    if Path(name).name != name:
        raise ValueError('job name must be a directory basename')
    if Path(job['fixture']).name != job['fixture']:
        raise ValueError('fixture must be a directory basename')
    stage = root / 'results' / name
    source = root / 'inputs' / job['fixture']
    inputs = {str(path.relative_to(root)): digest(path)
              for path in sorted(source.glob('*.v'))}
    if not inputs:
        raise ValueError(f'no RTL for {name}')
    expected = job.get('rtl_sha256')
    actual = {Path(path).name: value for path, value in inputs.items()}
    if expected is not None and expected != actual:
        raise ValueError(f'RTL bundle differs from the declared validated release for {name}')
    inputs['technology_compare.tcl'] = digest(root / 'technology_compare.tcl')
    version = subprocess.check_output(['vivado', '-version'], text=True)
    identity = {'job': job, 'inputs': inputs, 'version': version}
    status = root / f'{name}-status.json'
    if status.exists():
        previous = json.loads(status.read_text())
        if previous['identity'] != identity:
            raise ValueError(f'changed inputs: use a new job name for {name}')
        if previous.get('complete'):
            outputs = previous.get('outputs', {})
            if not outputs or any(not (root / path).is_file() or digest(root / path) != expected
                                  for path, expected in outputs.items()):
                raise ValueError(f'missing or changed reports: use a new job name for {name}')
            return previous
        raise ValueError(f'incomplete run: preserve it and use a new job name for {name}')
    command = ['vivado', '-mode', 'batch', '-source', str(root / 'technology_compare.tcl'),
               '-log', str(root / f'{name}.log'), '-journal', str(root / f'{name}.jou'),
               '-tclargs', str(source), job['top'], job['clock'], job['part'],
               str(stage), str(job.get('period_ns', 5.0)), stop_after, str(max_threads)]
    result = {'identity': identity, 'command': command, 'timeout_seconds': timeout, 'complete': False}
    status.write_text(json.dumps(result, indent=2) + '\n')
    start = time.monotonic()
    console = root / f'{name}-console.log'
    with console.open('w') as stream:
        process = subprocess.Popen(command, cwd=root, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result['exit'] = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            result['exit'] = None
    result['seconds'] = time.monotonic() - start
    marker = 'TECHNOLOGY_SYNTHESIS_COMPLETE' if stop_after == 'synthesis' else 'TECHNOLOGY_COMPARE_COMPLETE'
    result['complete'] = result['exit'] == 0 and marker in console.read_text()
    result['outputs'] = {str(path.relative_to(root)): digest(path)
                         for path in sorted(stage.glob('*.rpt'))}
    required = {'timing.rpt', 'synthesis-timing.rpt', 'paths.rpt', 'utilization.rpt',
                'route.rpt', 'coverage.rpt', 'drc.rpt'}
    if stop_after == 'synthesis':
        required = {'synthesis-timing.rpt', 'synthesis-utilization.rpt', 'synthesis-paths.rpt'}
    result['complete'] = result['complete'] and required <= {Path(p).name for p in result['outputs']}
    if inputs != {name: digest(root / name) for name in inputs}:
        raise RuntimeError(f'inputs changed during {name}')
    status.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'name': name, 'complete': result['complete'],
                      'seconds': result['seconds'], 'exit': result['exit']}), flush=True)
    return result


def main() -> None:
    """Select explicitly named jobs and cap parallelism rather than launching a sweep."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan', type=Path)
    parser.add_argument('--jobs', type=int, default=1, choices=(1, 2))
    parser.add_argument('--timeout', type=int, default=86400,
                        help='Wall-clock seconds per target, including synthesis and routing (default:24 hours).')
    parser.add_argument('--only', nargs='+')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('timeout must be positive')
    root = args.plan.resolve().parent
    jobs = json.loads(args.plan.read_text())['jobs']
    if len({job['name'] for job in jobs}) != len(jobs):
        parser.error('job names must be unique: each owns one status, log and report directory')
    if args.only:
        unknown = set(args.only) - {job['name'] for job in jobs}
        if unknown:
            parser.error(f'unknown jobs: {sorted(unknown)}')
        jobs = [job for job in jobs if job['name'] in args.only]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda job: execute(root, job, args.timeout), jobs))
    if not all(result['complete'] for result in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
