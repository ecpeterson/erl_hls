#!/usr/bin/env python3
"""Validate routed measurements and fit a bounded XLS operation-delay table."""
from __future__ import annotations
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import statistics
from typing import Any
from connectivity import check


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


def analyze(corpora: list[Path], output: Path) -> None:
    """Fit only training cases, report held-out errors, and preserve every measurement."""
    manifests = [json.loads((corpus / 'manifest.json').read_text()) for corpus in corpora]
    if len({manifest['part'] for manifest in manifests}) != 1:
        raise ValueError('cannot mix target parts')
    rows = [dict(row, **measurement(corpus / row['name']))
            for corpus, manifest in zip(corpora, manifests) for row in manifest['probes']]
    keys = [(row['op'], row['width'], row['count']) for row in rows]
    if len(keys) != len(set(keys)):
        raise ValueError('duplicate measurement shape')
    training: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        if row['split'] == 'training' and row['op'] != 'reverse':
            training[row['op'], row['count']].append(row)
    validation = []
    for row in rows:
        if row['split'] == 'validation' and row['op'] != 'reverse':
            prediction = {field: estimate(training[row['op'], row['count']], row['width'], field)
                          for field in ('cell_ps', 'routed_ps')}
            validation.append({'name': row['name'], 'predicted': prediction,
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
    args = parser.parse_args()
    analyze([args.corpus] + args.extra_corpus, args.output)


if __name__ == '__main__':
    main()
