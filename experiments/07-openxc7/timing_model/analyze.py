#!/usr/bin/env python3
"""Validate routed measurements and fit a bounded XLS operation-delay table."""
from __future__ import annotations
import argparse
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
import json
import math
from pathlib import Path
import re
import statistics
from typing import Any
from connectivity import check
from characterize import sha


def properties(path: Path) -> dict[str, str]:
    """Read Vivado's scalar timing-path properties without depending on spacing."""
    result = {}
    for line in path.read_text().splitlines()[1:]:
        fields = line.split(None, 3)
        if len(fields) == 4:
            result[fields[0]] = fields[3]
    return result


def checked_path(root: Path) -> tuple[dict[str, str], dict[str, int]]:
    """Require an unchanged imported circuit, full internal timing coverage and routing."""
    report = root / 'vivado'
    audit = check(root / 'mapped.json', report / 'connectivity.tsv', report / 'parameters.tsv')
    routed_audit = check(root / 'mapped.json', report / 'routed-connectivity.tsv', report / 'routed-parameters.tsv')
    if routed_audit != audit:
        raise ValueError(f'{root}: logical circuit changed during placement/routing')
    if 'CHARACTERIZATION_COMPLETE' not in (report / 'console.log').read_text():
        raise ValueError(f'{root}: incomplete Vivado run')
    coverage = {name: int(count) for name, count in re.findall(
        r'checking ([a-z_]+) \((\d+)\)', (report / 'coverage.rpt').read_text())}
    for name in ('no_clock', 'constant_clock', 'unconstrained_internal_endpoints',
                 'multiple_clock', 'loops', 'latch_loops'):
        if coverage.get(name) != 0:
            raise ValueError(f'{root}: timing coverage {name}={coverage.get(name)}')
    route = (report / 'route.rpt').read_text()
    errors = re.search(r'nets with routing errors\.+\s*:\s*(\d+)', route)
    routed = re.search(r'fully routed nets\.+\s*:\s*(\d+)', route)
    routable = re.search(r'routable nets\.+\s*:\s*(\d+)', route)
    if not errors or int(errors[1]) or not routed or not routable or routed[1] != routable[1]:
        raise ValueError(f'{root}: incomplete routing')
    return properties(report / 'path-properties.rpt'), audit


def measurement(root: Path) -> dict[str, Any]:
    """Return operation costs in picoseconds, excluding the fabric launch register."""
    path, audit = checked_path(root)
    report = root / 'vivado'
    # These measurements are FF-to-FF; hard-block fixtures use a separate collector.
    clocks = re.findall(r'FDRE \(Prop_fdre_C_Q\)\s+([\d.]+)', (report / 'paths.rpt').read_text())
    if not clocks or not path['STARTPOINT_PIN'].startswith('launch_'):
        raise ValueError(f'{root}: unexpected measurement boundary')
    launch_ps = round(float(clocks[0]) * 1000)
    def ps(key: str) -> int:
        """Convert a required, finite Vivado scalar from nanoseconds to picoseconds."""
        value = float(path[key])
        if not math.isfinite(value):
            raise ValueError(f'{root}: non-finite {key}')
        return round(value * 1000)
    return {'cell_ps': ps('DATAPATH_LOGIC_DELAY') - launch_ps,
            'routed_ps': ps('DATAPATH_DELAY') - launch_ps,
            'wire_ps': ps('DATAPATH_NET_DELAY'), 'launch_ps': launch_ps,
            'period_ps': ps('REQUIREMENT') - ps('SLACK'),
            'start': path['STARTPOINT_PIN'], 'end': path['ENDPOINT_PIN'], 'audit': audit}


def estimate(samples: list[dict[str, Any]], width: int, field: str) -> int:
    """Interpolate a monotone envelope inside measured widths, rejecting extrapolation."""
    previous_width = previous_delay = 0
    for row in sorted(samples, key=lambda r: r['width']):
        delay = max(previous_delay, row[field])
        if width <= row['width']:
            if previous_width == 0:
                return delay
            return math.ceil(previous_delay + (delay - previous_delay) *
                             (width - previous_width) / (row['width'] - previous_width))
        previous_width, previous_delay = row['width'], delay
    raise ValueError(f'width {width} exceeds measured support')


def shape_estimate(training: dict, op: str, width: int, count: int, field: str) -> int:
    """Interpolate monotone width/fan-in samples within the measured domain."""
    previous_count = previous_delay = 0
    for n in sorted(n for key, n in training if key == op):
        delay = max(previous_delay, estimate(training[op, n], width, field))
        if count <= n:
            if previous_count == 0:
                return delay
            return math.ceil(previous_delay + (delay - previous_delay) *
                             (count - previous_count) / (n - previous_count))
        previous_count, previous_delay = n, delay
    raise ValueError(f'{op}: fan-in {count} exceeds measured support')


def index_family(training: dict, prefix: str, bits: int) -> str:
    """Choose the smallest measured index width retaining all overflow decoding."""
    widths = {int(op[len(prefix):]) for op, _ in training if op.startswith(prefix)
              and op[len(prefix):].isdigit() and int(op[len(prefix):]) >= bits}
    if not widths:
        raise ValueError(f'{prefix}: index width {bits} exceeds measured support')
    return prefix + str(min(widths))


def operation_estimate(training: dict, row: dict, field: str) -> int:
    """Estimate a held-out shape, rounding only independently sampled index widths."""
    op = row['op']
    indexed = re.fullmatch(r'(sel_d|array_index_s|array_update_s|shll_s|shrl_s|shra_s)([0-9]+)', op)
    if indexed:
        if indexed[1] in ('shll_s', 'shrl_s', 'shra_s') and int(indexed[2]) == row['width']:
            op = indexed[1][:-2]
        else:
            op = index_family(training, indexed[1], int(indexed[2]))
    return shape_estimate(training, op, row['width'], row['count'], field)


def composed_estimate(training: dict, row: dict, field: str) -> int:
    """Estimate nested reads as measured mux layers, omitting constant dimensions."""
    match = re.fullmatch(r'array2_(s[0-9]+|c0)_(s[0-9]+|c0)_n([0-9]+)_n([0-9]+)', row['op'])
    if match is None:
        raise ValueError(f'unknown composition {row["op"]}')
    width, delay = row['width'], 0
    for mode, size in reversed(list(zip(match.groups()[:2], map(int, match.groups()[2:])))):
        if mode == 'c0':
            continue
        bits = int(mode[1:])
        count = min(size, 2**bits)
        delay += shape_estimate(training, index_family(training, 'array_index_s', bits), width, count, field)
        width *= count
    return delay


def summarize(values: list[int]) -> dict[str, Any]:
    """Keep optimistic errors visible instead of cancelling them with pessimism."""
    if not values:
        raise ValueError('empty error sample')
    result = {'count': len(values), 'mean_ps': round(statistics.mean(values), 2),
              'variance_ps2': round(statistics.pvariance(values), 2),
              'min_error_ps': min(values), 'max_error_ps': max(values),
              'mean_absolute_ps': round(statistics.mean(abs(v) for v in values), 2),
              'exact_count': values.count(0)}
    for name, errors in (('underestimation', [-v for v in values if v < 0]),
                         ('overestimation', [v for v in values if v > 0])):
        result[name] = {'count': len(errors),
                        'mean_ps': round(statistics.mean(errors), 2) if errors else 0,
                        'worst_ps': max(errors, default=0)}
    return result


def measured_row(item: tuple[Path, dict]) -> dict:
    """Check one independent circuit and retain its declared probe shape."""
    corpus, row = item
    root = corpus / row['name']
    if sha(root / 'mapped.json') != row['files']['mapped.json']:
        raise ValueError(f'{root}: mapped circuit differs from its prepared manifest')
    return dict(row, **measurement(root))


def analyze(corpora: list[Path], output: Path, jobs: int = 1) -> None:
    """Fit only training cases, report held-out errors, and preserve every measurement."""
    manifests = [json.loads((corpus / 'manifest.json').read_text()) for corpus in corpora]
    if len({manifest['part'] for manifest in manifests}) != 1:
        raise ValueError('cannot mix target parts')
    items = [(corpus, row) for corpus, manifest in zip(corpora, manifests) for row in manifest['probes']]
    if jobs == 1:
        rows = list(map(measured_row, items))
    else:
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            rows = list(pool.map(measured_row, items))
    keys = [(row['op'], row['width'], row['count']) for row in rows]
    if len(keys) != len(set(keys)):
        raise ValueError('duplicate measurement shape')
    training: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        if row['split'] == 'training' and row['op'] != 'reverse':
            training[row['op'], row['count']].append(row)
    validation = []
    for row in rows:
        if row['split'] in ('validation', 'composed_validation') and row['op'] != 'reverse':
            prediction = {field: (composed_estimate(training, row, field) if row['split'] == 'composed_validation'
                                  else operation_estimate(training, row, field))
                          for field in ('cell_ps', 'routed_ps')}
            validation.append({'name': row['name'], 'kind': row['split'], 'predicted': prediction,
                               'error': {field: prediction[field] - row[field] for field in prediction}})
    output.mkdir(parents=True, exist_ok=True)
    table = ['# xc7z030sbg485-1; native synth_xilinx -abc9; ps excluding launch FF clock-to-Q',
             '# op width cases cell_ps routed_ps; held-out widths excluded']
    for key, samples in sorted(training.items()):
        for row in sorted(samples, key=lambda r: r['width']):
            table.append(f"{key[0]} {row['width']} {key[1]} {row['cell_ps']} {row['routed_ps']}")
    (output / 'xc7_7030.tsv').write_text('\n'.join(table) + '\n')
    result = {'schema': 2, 'part': manifests[0]['part'],
              'tools': [manifest.get('tools', {}) for manifest in manifests],
              'measurements': rows, 'validation': validation,
              'errors': {field: summarize([r['error'][field] for r in validation])
                         for field in ('cell_ps', 'routed_ps')} if validation else {}}
    (output / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result['errors'], indent=2))


def main() -> None:
    """Analyze a complete, audited corpus into a reusable local calibration."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--extra-corpus', type=Path, action='append', default=[])
    parser.add_argument('--jobs', type=int, choices=range(1, 9), default=1)
    args = parser.parse_args()
    analyze([args.corpus] + args.extra_corpus, args.output, args.jobs)


if __name__ == '__main__':
    main()
