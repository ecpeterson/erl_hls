#!/usr/bin/env python3
"""Place and route one mapped architecture with bounded phases and retained provenance."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time


def sha(path: Path) -> str:
    """Fingerprint each physical input and completed output."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(args: argparse.Namespace) -> None:
    """Retain timeouts as failures, never as measurements of completed routing."""
    if (args.stage / 'route-run.json').exists():
        raise ValueError('use a fresh physical stage; existing measurements must be retained')
    if min(args.seed, args.place_seconds, args.route_seconds) <= 0:
        raise ValueError('seed and phase budgets must be positive')
    pins = Path(__file__).resolve().parents[1] / 'xc7z030sbg485.xdc'
    (args.stage / 'timing.xdc').write_text(pins.read_text() + 'create_clock -period 40 [get_ports clock]\n')
    evidence = {'seed': args.seed, 'frequency': 25, 'inputs': {
        str(p): sha(p) for p in (args.nextpnr, args.chipdb,
                                args.stage / 'mapped.json', args.stage / 'timing.xdc')}, 'phases': {}}
    common = [str(args.nextpnr), '--chipdb', str(args.chipdb), '--seed', str(args.seed), '--freq', '25']
    for name, command, budget in (
        ('place', common + ['--json', 'mapped.json', '--xdc', 'timing.xdc', '--no-route',
                           '--write', 'placed.json', '--log', 'place.log'], args.place_seconds),
        ('route', common + ['--json', 'placed.json', '--no-pack', '--no-place', '--router', 'router2',
                           '--timing-allow-fail', '--report', 'timing.json', '--timing-coverage',
                           'coverage.json', '--log', 'route.log'], args.route_seconds)):
        start = time.monotonic()
        code = None
        with (args.stage / (name + '.console')).open('w') as log:
            try:
                code = subprocess.run(command, cwd=args.stage, stdout=log,
                                      stderr=subprocess.STDOUT, timeout=budget).returncode
            except subprocess.TimeoutExpired:
                pass
        evidence['phases'][name] = {'command': command, 'seconds': time.monotonic() - start,
                                   'exit': code, 'budget_seconds': budget}
        (args.stage / 'route-run.json').write_text(json.dumps(evidence, indent=2) + '\n')
        if code != 0:
            raise RuntimeError(f'{name} failed or timed out: {args.stage}')
        print(name, 'complete', flush=True)
    checker = Path(__file__).resolve().parents[1] / 'timing_coverage/check.py'
    spec = importlib.util.spec_from_file_location('coverage_check', checker)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads((args.stage / 'coverage.json').read_text())
    has_ram = any(cell['type'].startswith('RAMB') for cell in data['cells'].values())
    has_dsp = any(cell['type'].startswith('DSP48') for cell in data['cells'].values())
    mode = ('ram_dsp' if has_dsp else 'ram') if has_ram else ('dsp' if has_dsp else 'logic')
    audit = module.check(data, module.requirements(mode))
    (args.stage / 'endpoint-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    if any(sha(Path(path)) != value for path, value in evidence['inputs'].items()):
        raise RuntimeError('physical inputs changed during measurement')
    evidence['outputs'] = {n: sha(args.stage / n) for n in
                           ('timing.json', 'coverage.json', 'route.log', 'endpoint-audit.json')}
    (args.stage / 'route-run.json').write_text(json.dumps(evidence, indent=2) + '\n')
    if not audit['endpoint_requirements_met']:
        raise RuntimeError('required timing endpoints are absent or unclassified')


def main() -> None:
    """Require the calibrated native binary, exact device database and mapped input."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'nextpnr', 'chipdb'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--place-seconds', type=int, default=1800)
    parser.add_argument('--route-seconds', type=int, default=2700)
    args = parser.parse_args()
    run(args)


if __name__ == '__main__':
    main()
