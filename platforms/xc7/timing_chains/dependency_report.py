#!/usr/bin/env python3
"""Compare proposed source changes using overlapping families of routed paths."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Iterable

from shared_subchains import arc_keys, endpoint_bus, fingerprint, read_paths, service


def selectors(plan: dict) -> dict[str, list[dict]]:
    """Compile explicit, scoped path-family labels; these are reviewed hypotheses."""
    if plan.get('schema') != 1:
        raise ValueError('dependency plan schema must be 1')
    groups = {}
    for group in plan['dependencies']:
        name = group['id']
        if name in groups or not name or not group.get('reason'):
            raise ValueError('dependencies need unique ids and a reason')
        rules = []
        for rule in group['selectors']:
            if set(rule) - {'scope', 'source', 'destination', 'through'} or not rule.get('scope'):
                raise ValueError('selector needs an explicit scope and known fields')
            if not any(rule.get(k) for k in ('source', 'destination', 'through')):
                raise ValueError('scope alone does not identify a dependency')
            rules.append({k: re.compile(v) for k, v in rule.items()})
        if not rules:
            raise ValueError('empty selector set')
        groups[name] = rules
    names = set()
    for bundle in plan['changes']:
        if bundle['id'] in names or not bundle.get('dependencies'):
            raise ValueError('changes need unique ids and nonempty dependency sets')
        names.add(bundle['id'])
        members = bundle['dependencies']
        if len(set(members)) != len(members) or set(members) - groups.keys():
            raise ValueError('unknown or repeated dependency in change')
    return groups


def matches(path: dict, rule: dict) -> bool:
    """Match source, destination and optional traversed arc within a source scope."""
    return (bool(rule['scope'].search(service(path['source']))) and
            all(key not in rule or rule[key].search(path[key]) for key in ('source', 'destination')) and
            ('through' not in rule or any(rule['through'].search(a['resource']) for a in path['arcs'])))


def summarize(endpoints: Iterable[dict], alternatives: Iterable[dict], metadata: dict,
              plan: dict, savings: tuple[float, ...] = (.25, .5, 1.)) -> dict:
    """Union proposed dependencies once per path and expose uncovered competitors.

    Savings apply once to each covered path, not once per matching label. They
    are conditional scenarios, not inferred arc savings or rerouting forecasts.
    """
    if not savings or any(not math.isfinite(x) or x <= 0 for x in savings):
        raise ValueError('savings must be positive finite numbers')
    rules = selectors(plan)
    rows, seen, destinations = [], set(), set()
    counts, worst = {}, metadata['requirement_ns'] - metadata['worst_slack_ns']
    for kind, paths in [('endpoint_paths', endpoints), ('alternative_paths', alternatives)]:
        count = 0
        for p in paths:
            count += 1
            if p['clock'] != metadata['clock']:
                raise ValueError('mixed clock groups')
            if kind == 'endpoint_paths':
                if p['destination'] in destinations:
                    raise ValueError('repeated endpoint in census')
                destinations.add(p['destination'])
            key = hashlib.sha256(repr((p['source'], p['destination'], p['period_ns'], arc_keys(p))).encode()).digest()
            if key in seen:
                continue
            seen.add(key)
            labels = {name for name, rs in rules.items() if any(matches(p, r) for r in rs)}
            rows.append({'source': p['source'], 'destination': p['destination'],
                         'period_ns': p['period_ns'], 'labels': labels,
                         'census': kind == 'endpoint_paths'})
        counts[kind] = count
        if count != metadata[kind] or count == 0:
            raise ValueError(f'{kind}: parsed {count}, expected {metadata[kind]}')
    if abs(max(r['period_ns'] for r in rows if r['census']) - worst) > .002:
        raise ValueError('worst period differs from extraction metadata')
    band_edge = worst - metadata['band_ns']
    changes = []
    for change in plan['changes']:
        members = set(change['dependencies'])
        covered = [r for r in rows if r['labels'] & members]
        untouched = [r for r in rows if not r['labels'] & members]
        census = [r for r in covered if r['census']]
        residual = sorted(untouched, key=lambda r: -r['period_ns'])
        examples, example_buses = [], set()
        for r in residual:
            key = (endpoint_bus(r['source']), endpoint_bus(r['destination']))
            if key not in example_buses:
                examples.append({k: r[k] for k in ('source', 'destination', 'period_ns')})
                example_buses.add(key)
            if len(examples) == 5:
                break
        scenarios = []
        for delta in savings:
            period = max(r['period_ns'] - (min(delta, r['period_ns']) if r['labels'] & members else 0) for r in rows)
            scenarios.append({'saving_per_covered_path_ns': delta, 'sample_period_ns': period,
                              'band_limited_period_ns': max(period, band_edge),
                              'reaches_band_edge': period <= band_edge})
        changes.append({'id': change['id'], 'dependencies': sorted(members),
                        'census_endpoints': len(census), 'sample_paths': len(covered),
                        'overlap_endpoints': sum(len(r['labels'] & members) > 1 for r in census),
                        'instances': sorted({service(r['source']) for r in covered}),
                        'covered_worst_ns': max((r['period_ns'] for r in covered), default=None),
                        'untouched_worst_ns': residual[0]['period_ns'] if residual else None,
                        'unmatched_dependencies': sorted(members - set().union(*(r['labels'] for r in covered))),
                        'scenarios': scenarios, 'remaining_examples': examples})
    label_counts = Counter(label for r in rows if r['census'] for label in r['labels'])
    return {'schema': 1, 'extraction': metadata, 'worst_period_ns': worst,
            'census_endpoints': len(destinations), 'distinct_sample_paths': len(rows),
            'band_edge_ns': band_edge, 'endpoint_cap_reached': counts['endpoint_paths'] >= metadata['limit'],
            'alternative_cap_reached': counts['alternative_paths'] >= metadata.get('alternative_limit', metadata['limit']),
            'dependencies': [{**g, 'census_endpoints': label_counts[g['id']]} for g in plan['dependencies']],
            'changes': changes,
            'interpretation': 'Reviewed path-family attribution, not automatic source equivalence. Each scenario removes its stated time once per covered path across all named instances, with unchanged layout and other paths. Bounded alternatives and uncensused paths can limit any gain.'}


def markdown(report: dict) -> str:
    """Show combined coverage, conditional timing and concrete remaining competitors."""
    lines = ['# Source-dependency targeting', '', report['interpretation'], '',
             f"{report['census_endpoints']} endpoint-worst paths; baseline {report['worst_period_ns']:.3f} ns. Census band ends at {report['band_edge_ns']:.3f} ns.",
             f"Endpoint cap reached: {report['endpoint_cap_reached']}; alternative cap reached: {report['alternative_cap_reached']}.", '',
             '| Proposed change | Covered endpoints | Instances | Overlapping endpoints | Covered worst ns | Untouched worst ns | Conditional periods ns |',
             '|---|---:|---:|---:|---:|---:|---|']
    for c in report['changes']:
        covered = 'none sampled' if c['covered_worst_ns'] is None else f"{c['covered_worst_ns']:.3f}"
        untouched = 'none sampled' if c['untouched_worst_ns'] is None else f"{c['untouched_worst_ns']:.3f}"
        effects = '; '.join(f"−{s['saving_per_covered_path_ns']:g} → {s['band_limited_period_ns']:.3f}" + (' (band edge)' if s['reaches_band_edge'] else '') for s in c['scenarios'])
        lines.append(f"| {c['id']} | {c['census_endpoints']} | {len(c['instances'])} | {c['overlap_endpoints']} | {covered} | {untouched} | {effects} |")
    for c in report['changes']:
        lines += ['', f"## {c['id']}: remaining paths", '']
        if c['unmatched_dependencies']:
            lines += ['Unmatched labels: ' + ', '.join(c['unmatched_dependencies']) + '.', '']
        lines += [f"- {r['period_ns']:.3f} ns: `{r['source']}` → `{r['destination']}`." for r in c['remaining_examples']] or ['No untouched sampled paths; absence outside the sample is unknown.']
    return '\n'.join(lines)+'\n'


def build(root: Path, manifest: Path) -> dict:
    """Check extraction/source identities and stream one plan over the retained census."""
    plan = json.loads(manifest.read_text())
    files = {name: root/file for name, file in [('metadata', 'extraction.json'), ('endpoints', 'endpoints.rpt.gz'), ('alternatives', 'alternatives.rpt.gz')]}
    files['plan'] = manifest
    before = {k: fingerprint(p) for k, p in files.items()}
    if before['metadata'] != plan['extraction_sha256']:
        raise ValueError('dependency labels belong to another extraction')
    sources = []
    for source in plan.get('source_evidence', []):
        p = (manifest.parent/source['path']).resolve()
        if fingerprint(p) != source['sha256']:
            raise ValueError(f'source evidence changed: {p}')
        files[f'source:{p}'] = p
        before[f'source:{p}'] = source['sha256']
        sources.append({'path': str(p), 'sha256': source['sha256']})
    report = summarize(read_paths(files['endpoints']), read_paths(files['alternatives']),
                       json.loads(files['metadata'].read_text()), plan)
    if before != {k: fingerprint(p) for k, p in files.items()}:
        raise ValueError('input changed during analysis')
    report['inputs'] = before
    report['source_evidence'] = sources
    report['analyzer_sha256'] = fingerprint(Path(__file__))
    report['shared_helpers_sha256'] = fingerprint(Path(__file__).with_name('shared_subchains.py'))
    report['parser_sha256'] = fingerprint(Path(__file__).with_name('path_report.py'))
    return report


def main() -> None:
    """Write a reproducible combined-dependency report beside other timing diagnostics."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = build(args.input, args.plan)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'dependencies.json').write_text(json.dumps(report, indent=2)+'\n')
    (args.output/'dependencies.md').write_text(markdown(report))


if __name__ == '__main__':
    main()
