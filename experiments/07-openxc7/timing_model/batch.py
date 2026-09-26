#!/usr/bin/env python3
"""Run bounded, independent Vivado measurements and retain per-probe failures."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import hashlib
import os
import signal
from pathlib import Path
import subprocess
import time


def measure(root: Path, script: Path, name: str, timeout: int = 180) -> dict[str, str | float]:
    """Route one mapped circuit; a failed case remains a failed measurement."""
    inputs = [root / name / 'mapped.edf', root / name / 'mapped.json', script,
              script.with_name('connectivity.py'), script.with_name('circuit_audit.tcl')]
    fingerprint = [hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs]
    output = root / name / 'vivado'
    if output.exists():
        log = output / 'console.log'
        if ((output / 'inputs.json').is_file() and
                json.loads((output / 'inputs.json').read_text()) == fingerprint and
                (output / 'path-properties.rpt').is_file() and log.is_file() and
                'CHARACTERIZATION_COMPLETE' in log.read_text()):
            return {'name': name, 'status': 'complete', 'seconds': 0.0}
        raise ValueError(f'{output}: incomplete or changed prior measurement; use a fresh corpus')
    output.mkdir()
    (output / 'inputs.json').write_text(json.dumps(fingerprint) + '\n')
    start = time.monotonic()
    with (output / 'console.log').open('w') as log:
        process = subprocess.Popen(
            ['vivado', '-mode', 'batch', '-nojournal', '-nolog', '-source', str(script),
             '-tclargs', str(root / name / 'mapped.edf'), str(output)], cwd=output,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            complete = ('CHARACTERIZATION_COMPLETE' in (output / 'console.log').read_text()
                        and (output / 'path-properties.rpt').is_file())
            status = 'complete' if code == 0 and complete else f'failed (exit {code})'
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            status = 'timeout'
    return {'name': name, 'status': status, 'seconds': round(time.monotonic() - start, 3)}


def main() -> None:
    """Use at most two processes by default; never overwrite earlier measurements."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', type=lambda p: Path(p).resolve())
    parser.add_argument('script', type=lambda p: Path(p).resolve())
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--names', nargs='+')
    parser.add_argument('--status', default='status.json')
    args = parser.parse_args()
    manifest = json.loads((args.corpus / 'manifest.json').read_text())
    names = [r['name'] for r in manifest['probes']]
    if args.names is not None:
        if set(args.names) - set(names):
            parser.error('unknown probe name')
        names = [name for name in names if name in args.names]
    if Path(args.status).name != args.status:
        parser.error('status must be a filename')
    if len(names) != len(set(names)) or not 1 <= args.jobs <= 8 or args.timeout <= 0:
        parser.error('distinct probes, 1..8 workers and a positive timeout required')
    results = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(measure, args.corpus, args.script, name, args.timeout) for name in names]
        for future in as_completed(futures):
            row = future.result()
            results.append(row)
            (args.corpus / args.status).write_text(json.dumps(sorted(results, key=lambda result: result['name']), indent=2) + '\n')
            print(row, flush=True)
    if any(row['status'] != 'complete' for row in results):
        raise SystemExit('one or more measurements failed')


if __name__ == '__main__':
    main()
