#!/usr/bin/env python3
"""Join routed placement and sampled timing nets to explicit resource owners."""
import argparse
from collections import Counter, defaultdict
import csv
import gzip
import hashlib
import json
from pathlib import Path
import re
from typing import Iterator, TextIO

from path_report import parse_vivado
from technology_report import capacity, hierarchy


def digest(path: Path, *, decompress: bool = False) -> str:
    """Fingerprint file bytes, optionally decompressed, without retaining them in memory."""
    h = hashlib.sha256()
    opener = gzip.open if decompress and path.suffix == '.gz' else open
    with opener(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def text_open(path: Path) -> TextIO:
    """Open raw or gzip text reports with the same streaming interface."""
    return gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()


def timing_paths(path: Path) -> Iterator[dict]:
    """Parse one reported setup path at a time, retaining the shared parser's checks."""
    block = []
    with text_open(path) as stream:
        for line in stream:
            if line.startswith('Slack ('):
                if block:
                    yield from parse_vivado(''.join(block))
                block = [line]
            elif block:
                block.append(line)
    if block:
        yield from parse_vivado(''.join(block))


def select_nets(path: Path, limit: int) -> dict:
    """Select a bounded union by worst branch delay, endpoint count and reported fanout."""
    if limit <= 0:
        raise ValueError('net rank limit must be positive')
    nets, count, worst = {}, 0, 0.0
    for p in timing_paths(path):
        count += 1
        worst = max(worst, p['period_ns'])
        seen = set()
        for arc in p['arcs']:
            if arc['kind'] != 'net':
                continue
            name = arc['resource']
            n = nets.setdefault(name, {'name': name, 'endpoints': 0, 'max_branch_ns': 0.0, 'reported_fanout': 0})
            n['max_branch_ns'] = max(n['max_branch_ns'], arc['delay_ns'])
            n['reported_fanout'] = max(n['reported_fanout'], arc['fanout'] or 0)
            if name not in seen:
                n['endpoints'] += 1
                seen.add(name)
    if not count:
        raise ValueError('no sampled timing paths')
    selected = set()
    for key in ('max_branch_ns', 'endpoints', 'reported_fanout'):
        selected.update(n['name'] for n in sorted(nets.values(), key=lambda n: (-n[key], n['name']))[:limit])
    return {'schema': 1, 'paths_sha256': digest(path, decompress=True), 'path_count': count, 'worst_period_ns': worst,
            'unique_nets': len(nets), 'rank_limit': limit,
            'nets': [nets[n] for n in sorted(selected)]}


class Owners:
    """Classify resource paths by ordered, explicit regex rules; retain unmatched objects."""

    def __init__(self, config: dict) -> None:
        """Compile first-match rules with named captures usable in domain and role labels."""
        self.rules = [(re.compile(r['pattern']), r['domain'], r['role']) for r in config['rules']]

    def classify(self, name: str) -> tuple[str, str]:
        """Return the first matching domain/role, or an explicit unclassified bucket."""
        for pattern, domain, role in self.rules:
            if match := pattern.search(name):
                return domain.format(**match.groupdict()), role.format(**match.groupdict())
        return 'unclassified', 'unclassified'


def extent(points: list[tuple[int, int]]) -> dict:
    """Report tile-grid bounds and central 90% marginals; neither is routed wire length."""
    if not points:
        return {'count': 0}
    xs, ys = sorted(p[0] for p in points), sorted(p[1] for p in points)
    low, high = int((len(points) - 1) * .05), int((len(points) - 1) * .95)
    return {'count': len(points), 'bounds': [xs[0], ys[0], xs[-1], ys[-1]],
            'central90': [xs[low], ys[low], xs[high], ys[high]],
            'median': [xs[len(xs)//2], ys[len(ys)//2]],
            'manhattan_span': xs[-1] - xs[0] + ys[-1] - ys[0]}


def read_rows(root: Path, name: str) -> Iterator[dict]:
    """Stream a TSV export, accepting a compressed retained copy."""
    path = root / name
    if not path.exists():
        path = root / (name + '.gz')
    with text_open(path) as stream:
        yield from csv.DictReader(stream, delimiter='\t')


def census(root: Path, config: dict) -> dict:
    """Reconcile exclusive area, owner placement and sampled net loads without double counting parents."""
    owners = Owners(config)
    def classify_rows(rows: list[dict]) -> str:
        """Use report lineage after removing the synthetic top and parent self rows."""
        name = '/'.join(row['instance'] for row in rows[1:] if not row['instance'].startswith('('))
        return ' / '.join(owners.classify(name))
    area = hierarchy((root / 'utilization.rpt').read_text(), classify_rows)
    cells, groups = {}, defaultdict(lambda: {'primitives': Counter(), 'points': [], 'clock_regions': Counter(), 'unplaced': 0})
    for row in read_rows(root, 'cells.tsv'):
        if row['name'] in cells:
            raise ValueError('duplicate cell in export')
        label = owners.classify(row['name'])
        point = (int(row['x']), int(row['y'])) if row['x'] and row['y'] else None
        cells[row['name']] = (label, point)
        group = groups[' / '.join(label)]
        group['primitives'][row['ref']] += 1
        if point is None:
            group['unplaced'] += 1
        else:
            group['points'].append(point)
            group['clock_regions'][row['clock_region']] += 1
    placement = {name: {**{k: v for k, v in group.items() if k != 'points'}, 'extent': extent(group['points'])}
                 for name, group in sorted(groups.items())}
    selected = json.loads((root / 'selection.json').read_text())
    extraction = json.loads((root / 'extraction.json').read_text())
    if extraction['endpoint_count'] != selected['path_count']:
        raise ValueError('timing selection does not match extraction path count')
    if extraction['missing_nets'] != sum(row['status'] == 'missing' for row in read_rows(root, 'nets.tsv')):
        raise ValueError('net lookup coverage does not match extraction')
    timing = {n['name']: n for n in selected['nets']}
    nets = {}
    for row in read_rows(root, 'nets.tsv'):
        n = nets.setdefault(row['canonical'], {'name': row['canonical'], 'aliases': [], 'timing': None,
                                              'domains': Counter(), 'roles': Counter(), 'points': [],
                                              'drivers': [], 'loads': 0, 'missing_cells': 0})
        sample = timing.get(row['name'])
        n['aliases'].append({**row, 'timing': sample})
        if sample:
            if n['timing'] is None:
                n['timing'] = {'max_branch_ns': 0.0, 'max_alias_endpoints': 0}
            n['timing']['max_branch_ns'] = max(n['timing']['max_branch_ns'], sample['max_branch_ns'])
            n['timing']['max_alias_endpoints'] = max(n['timing']['max_alias_endpoints'], sample['endpoints'])
    for row in read_rows(root, 'pins.tsv'):
        n = nets[row['net']]
        if row['cell'] not in cells:
            n['missing_cells'] += 1
            continue
        (domain, role), point = cells[row['cell']]
        n['domains'][domain] += 1
        n['roles'][role] += 1
        if point is not None:
            n['points'].append(point)
        if row['direction'] == 'OUT':
            n['drivers'].append(row['cell'])
        else:
            n['loads'] += 1
    for n in nets.values():
        n['extent'] = extent(n.pop('points'))
    # Endpoints partition the sample; intermediate owner crossings are separate.
    path_groups = defaultdict(lambda: {'paths': 0, 'worst_period_ns': 0.0, 'logic_sum_ns': 0.0,
                                      'route_sum_ns': 0.0, 'cross_domain_paths': 0,
                                      'cross_role_paths': 0, 'missing_cell_references': 0})
    path_file = root / 'endpoints.rpt'
    if not path_file.exists():
        path_file = root / 'endpoints.rpt.gz'
    if not path_file.exists():
        raise ValueError('missing endpoint timing report')
    if digest(path_file, decompress=True) != selected['paths_sha256']:
        raise ValueError('endpoint report bytes changed after net selection')
    for path in timing_paths(path_file):
        destination = path['destination'].rsplit('/', 1)[0]
        label = ' / '.join(cells.get(destination, (('unclassified', 'unclassified'), None))[0])
        group = path_groups[label]
        group['paths'] += 1
        group['worst_period_ns'] = max(group['worst_period_ns'], path['period_ns'])
        group['logic_sum_ns'] += path['logic_ns']
        group['route_sum_ns'] += path['route_ns']
        names = {path['source'].rsplit('/', 1)[0], destination}
        names.update(a['resource'].rsplit('/', 1)[0] for a in path['arcs'] if a['kind'] == 'cell')
        labels = {cells[n][0] for n in names if n in cells}
        group['missing_cell_references'] += sum(name not in cells for name in names)
        group['cross_domain_paths'] += len({label[0] for label in labels}) > 1
        group['cross_role_paths'] += len(labels) > 1
    if sum(g['paths'] for g in path_groups.values()) != selected['path_count']:
        raise ValueError('endpoint report count does not match selection')
    inputs = {p.name: digest(p) for p in sorted(root.iterdir())
              if p.name in ('extraction.json', 'selection.json', 'utilization.rpt', 'capacity.rpt',
                            'congestion.rpt', 'cells.tsv', 'nets.tsv', 'pins.tsv', 'endpoints.rpt', 'endpoints.rpt.gz') or p.name in
              ('cells.tsv.gz', 'nets.tsv.gz', 'pins.tsv.gz')}
    return {'schema': 1, 'extraction': extraction,
            'reporter_sha256': digest(Path(__file__)),
            'input_hashes': inputs, 'owner_config': config, 'area': area,
            'capacity': capacity((root / 'capacity.rpt').read_text()), 'placement': placement, 'path_groups': dict(path_groups),
            'net_selection': {k: v for k, v in selected.items() if k != 'nets'},
            'nets': sorted(nets.values(), key=lambda n: -(n['timing'] or {}).get('max_branch_ns', 0)),
            'scope': 'One retained routed checkpoint, no netlist or constraint change. Owner rules label generated boundaries, not removable area. Primitive counts are not physical LUT-site counts. Tile-grid extent is not routed wire length; central90 uses marginal quantiles over placed primitives. Hierarchy aliases share one physical-net load census. Timing is the worst sampled branch; max-alias endpoint incidence is a lower bound on distinct physical-net endpoints, not their sum. Neither measures total fanout delay. Endpoint sampling is capped; alternative paths are not enumerated. Congestion is the native report, not inferred from bounds.'}


def markdown(report: dict) -> str:
    """Summarize area and physical spans while retaining attribution and sampling limits."""
    area = report['area']
    lines = ['# Physical ownership census', '', report['scope'], '',
             f"Checkpoint SHA-256: `{report['extraction']['checkpoint_sha256']}`.", '',
             f"Total: {area['total']['Total LUTs']:,} LUTs / {area['total']['FFs']:,} FFs / {area['total']['RAMB36']} BRAM36.",
             f"Top minus exclusive row sums: `{area['reconciliation']}`. Do not assign this difference to owners.", '',
             '| Owner / role | LUTs (hierarchy) | FF | BRAM36 | Tile-grid bounds | Central 90% |',
             '| --- | ---: | ---: | ---: | --- | --- |']
    for name, res in sorted(area['groups'].items(), key=lambda kv: -kv[1]['Total LUTs']):
        e = report['placement'].get(name, {}).get('extent', {})
        lines.append(f"| {name} | {res['Total LUTs']:,} | {res['FFs']:,} | {res['RAMB36']} | {e.get('bounds', 'unplaced/none')} | {e.get('central90', 'none')} |")
    lines += ['', '## Near-critical endpoint ownership', '',
              '| Endpoint owner | Paths | Worst period (ns) | Cross domain | Cross role | Missing cell references |',
              '| --- | ---: | ---: | ---: | ---: | ---: |']
    for name, group in sorted(report['path_groups'].items(), key=lambda kv: -kv[1]['paths']):
        lines.append(f"| {name} | {group['paths']} | {group['worst_period_ns']:.3f} | {group['cross_domain_paths']} | {group['cross_role_paths']} | {group['missing_cell_references']} |")
    lines += ['', '## Sampled nets', '',
              f"{report['net_selection']['path_count']:,} endpoint paths; {report['extraction']['endpoint_limit']} endpoint cap; "
              f"{len(report['nets'])} physical nets ({report['extraction']['selected_nets']} selected aliases) selected by delay, endpoint incidence, fanout or global high fanout. Full names and load identities are in the JSON/TSV.", '',
              '| Net | Worst sampled branch (ns) | Max-alias endpoints | Leaf loads | Domains | Grid span |',
              '| --- | ---: | ---: | ---: | --- | ---: |']
    for n in report['nets'][:24]:
        t = n['timing'] or {}
        lines.append(f"| `{n['name']}` | {t.get('max_branch_ns', '')} | {t.get('max_alias_endpoints', '')} | {n['loads']} | {dict(n['domains'])} | {n['extent'].get('manhattan_span', '')} |")
    return '\n'.join(lines) + '\n'


def main() -> None:
    """Select net probes or render a completed extraction using explicit owner rules."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    select = sub.add_parser('select')
    select.add_argument('paths', type=Path)
    select.add_argument('output', type=Path)
    select.add_argument('--limit', type=int, default=128)
    report = sub.add_parser('report')
    report.add_argument('directory', type=Path)
    report.add_argument('owners', type=Path)
    args = parser.parse_args()
    if args.command == 'select':
        result = select_nets(args.paths, args.limit)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        args.output.with_suffix('.txt').write_text(''.join(n['name'] + '\n' for n in result['nets']))
    else:
        result = census(args.directory, json.loads(args.owners.read_text()))
        (args.directory / 'physical-census.json').write_text(json.dumps(result, indent=2) + '\n')
        (args.directory / 'physical-census.md').write_text(markdown(result))


if __name__ == '__main__':
    main()
