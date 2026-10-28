#!/usr/bin/env python3
"""Rank shared physical timing segments and bounded, fixed-layout sensitivities."""
import argparse
from array import array
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
from typing import Iterator

from path_report import parse_vivado


def read_paths(path: Path) -> Iterator[dict]:
    """Stream complete setup paths from plain or compressed Vivado reports."""
    opener = gzip.open if path.suffix == '.gz' else open
    block = []
    with opener(path, 'rt') as stream:
        for line in stream:
            if line.startswith('Slack ('):
                if block:
                    yield parse_vivado(''.join(block))[0]
                block = [line]
            elif block:
                block.append(line)
        if block:
            yield parse_vivado(''.join(block))[0]


def fingerprint(path: Path) -> str:
    """Hash consumed bytes without loading a potentially large report into memory."""
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def arc_keys(path: dict) -> list[tuple]:
    """Identify cell timing arcs and individual net branches, never whole fanout nets."""
    arcs = path['arcs']
    keys = []
    for i, arc in enumerate(arcs):
        if arc['kind'] == 'cell':
            keys.append(('cell', arc['resource'], arc['timing_arc']))
        else:
            before = arcs[i-1]['resource'] if i else path['source']
            after = arcs[i+1] if i+1 < len(arcs) else None
            sink = (after['resource'], after['timing_arc']) if after else (path['destination'], '')
            keys.append(('net', arc['resource'], before, *sink))
    return keys


def segments(keys: list, maximum: int) -> Iterator[tuple[int, tuple]]:
    """Enumerate contiguous multi-arc segments up to the requested bound."""
    for i in range(len(keys)-1):
        for length in range(2, min(maximum, len(keys)-i)+1):
            yield i, tuple(keys[i:i+length])


def service(resource: str) -> str:
    """Retain the physical instance name rather than infer source-level equivalence."""
    instance = re.match(r'^(.*?_inst)(?:/|$)', resource)
    if instance:
        return instance[1]
    return resource.split('/memory', 1)[0] if '/memory' in resource else resource.rsplit('/', 2)[0]


def endpoint_bus(resource: str) -> str:
    """Group bit endpoints for presentation only; do not merge their timing paths."""
    return re.sub(r'\[\d+\]', '[*]', resource)


def sensitivity(paths: list[dict], affected: dict[int, float], reduction: float) -> dict:
    """Shorten only sampled occurrences, capped by their actual segment delay."""
    untouched = [p['period_ns'] for i, p in enumerate(paths) if i not in affected]
    return {'reduction_ns': reduction,
            'sample_period_ns': max(p['period_ns']-min(reduction, affected.get(i, 0.0))
                                    for i, p in enumerate(paths)),
            'untouched_sample_period_ns': max(untouched) if untouched else None}


def summarize(endpoints: list[dict], alternatives: list[dict], metadata: dict,
              maximum: int = 12, keep: int = 40) -> dict:
    """Count endpoint coverage and evaluate recurring segments against sampled alternatives."""
    if not endpoints or not alternatives:
        raise ValueError('both endpoint and alternative paths are required')
    for name, paths in [('endpoint_paths', endpoints), ('alternative_paths', alternatives)]:
        if len(paths) != metadata[name]:
            raise ValueError(f'{name}: parsed {len(paths)} but extraction recorded {metadata[name]}')
    if len({p['destination'] for p in endpoints}) != len(endpoints):
        raise ValueError('endpoint census contains repeated endpoints')
    worst = metadata['requirement_ns']-metadata['worst_slack_ns']
    if abs(max(p['period_ns'] for p in endpoints)-worst) > .002:
        raise ValueError('worst period differs from extraction metadata')
    if any(p['clock'] != metadata['clock'] for p in endpoints+alternatives):
        raise ValueError('mixed clock groups')
    # Intern the arc identities: sequence dictionaries otherwise repeat long names.
    ids, identities, delays = {}, [], []
    encoded = []
    for path in endpoints:
        row = []
        for key, arc in zip(arc_keys(path), path['arcs']):
            if key not in ids:
                ids[key] = len(ids)
                identities.append(key)
                delays.append(arc['delay_ns'])
            row.append(ids[key])
        encoded.append(row)
    support = {}
    for i, row in enumerate(encoded):
        for _, segment in segments(row, maximum):
            old = support.get(segment)
            if old is None:
                support[segment] = i
            elif isinstance(old, int):
                if old != i:
                    support[segment] = array('I', [old, i])
            elif old[-1] != i:
                old.append(i)
    # Keep the longest-delay representative for each identical endpoint support set.
    representatives = {}
    for segment, members in support.items():
        if isinstance(members, int):
            continue
        delay = sum(delays[k] for k in segment)
        signature = members.tobytes()
        old = representatives.get(signature)
        if old is None or delay > old[0]:
            representatives[signature] = (delay, segment)
    del support
    candidates = sorted(((len(signature)//4*delay, signature, delay, seg)
                         for signature, (delay, seg) in representatives.items()), reverse=True)
    # A broad-coverage ranking is separate from the worst-path ranking.
    chosen = {seg: (mask, delay) for _, mask, delay, seg in candidates[:keep*4]}
    worst_index = max(range(len(endpoints)), key=lambda i: endpoints[i]['period_ns'])
    for _, mask, delay, seg in [c for c in candidates if worst_index in array('I', c[1])][:keep]:
        chosen[seg] = (mask, delay)
    paths, seen = [], set()
    for path in endpoints+alternatives:
        key = (path['source'], path['destination'], tuple(arc_keys(path)), path['period_ns'])
        if key not in seen:
            seen.add(key)
            paths.append(path)
    hits = {seg: {} for seg in chosen}
    for i, path in enumerate(paths):
        row = [ids.get(key, -1) for key in arc_keys(path)]
        for start, seg in segments(row, maximum):
            if seg in hits:
                delay = sum(a['delay_ns'] for a in path['arcs'][start:start+len(seg)])
                hits[seg][i] = max(delay, hits[seg].get(i, 0.0))
    rows = []
    for seg, (mask, delay) in chosen.items():
        matched = [endpoints[i] for i in array('I', mask)]
        effects = [sensitivity(paths, hits[seg], delta) for delta in (.25, .5, 1.0)]
        rows.append({'endpoints': len(matched), 'endpoint_buses': len({endpoint_bus(p['destination']) for p in matched}),
                     'services': sorted({service(p['destination']) for p in matched}),
                     'census_delay_ns': delay, 'arcs': [identities[k] for k in seg],
                     'source_examples': sorted({p['source'] for p in matched})[:4],
                     'destination_examples': sorted({endpoint_bus(p['destination']) for p in matched})[:6],
                     'sample_paths': len(hits[seg]), 'sensitivity': effects,
                     'affected_worst_ns': max(p['period_ns'] for p in matched)})
    coverage = sorted(rows, key=lambda r: (r['endpoints']*r['census_delay_ns'], r['endpoints']), reverse=True)[:keep]
    leverage = sorted(rows, key=lambda r: (r['sensitivity'][-1]['sample_period_ns'], -r['endpoints']))[:keep]
    groups = defaultdict(list)
    for p in endpoints:
        groups[service(p['destination'])].append(p)
    return {'schema': 1, 'extraction': metadata, 'worst_period_ns': worst,
            'census_limit_reached': len(endpoints) >= metadata['limit'],
            'alternatives_limit_reached': len(alternatives) >= metadata.get('alternative_limit', metadata['limit']),
            'distinct_sample_paths': len(paths), 'maximum_segment_arcs': maximum,
            'interpretation': 'Fixed-layout sensitivity of sampled paths only; bounded alternatives are not a global timing guarantee. Physical identities do not establish source-level equivalence.',
            'endpoint_services': [{'instance': name, 'endpoints': len(ps),
                                   'worst_period_ns': max(p['period_ns'] for p in ps)}
                                  for name, ps in sorted(groups.items(), key=lambda pair: -max(p['period_ns'] for p in pair[1]))],
            'shared_segments_by_coverage': coverage, 'shared_segments_by_sample_leverage': leverage}


def markdown(report: dict) -> str:
    """Render instance aliases and a small, diverse set of approximate targets."""
    meta = report['extraction']
    aliases = {row['instance']: f'S{i}' for i, row in enumerate(report['endpoint_services'])}

    def label(resource: str) -> tuple[str, str]:
        """Abbreviate only a known physical instance prefix; retain the cell identity."""
        for name in sorted(aliases, key=len, reverse=True):
            if resource.startswith(name+'/'):
                return aliases[name], resource[len(name)+1:]
        return '—', resource

    lines = ['# Shared timing subchains', '',
             f"Clock `{meta['clock']}`: {meta['endpoint_paths']} endpoints within {meta['band_ns']} ns of {report['worst_period_ns']:.3f} ns; {meta['alternative_paths']} alternative paths, at most {meta['alternatives_per_endpoint']} per endpoint.", '',
             'Coverage identifies recurring structures worth investigating. The hypothetical period changes hold the existing layout fixed; they help expose competing paths, not predict the next implementation.', '',
             f"Endpoint cap reached: {report['census_limit_reached']}. Alternative cap reached: {report['alternatives_limit_reached']}.", '',
             '| ID | Endpoint instance | Endpoints | Worst ns |', '|---|---|---:|---:|']
    for row in report['endpoint_services']:
        lines.append(f"| {aliases[row['instance']]} | `{row['instance']}` | {row['endpoints']} | {row['worst_period_ns']:.3f} |")
    for title, key in [('Broad physical sharing', 'shared_segments_by_coverage'), ('Best sampled period sensitivity', 'shared_segments_by_sample_leverage')]:
        lines += ['', f'## {title}', '', 'Up to two representatives per physical instance; JSON retains the full ranking.', '',
                  '| Instance | First → last arc | Endpoints / buses | Segment ns | Sample period after −0.5 / −1 ns | Untouched sample ns |', '|---|---|---:|---:|---:|---:|']
        counts = defaultdict(int)
        shown = 0
        for row in report[key]:
            instance, first = label(row['arcs'][0][1])
            last_instance, last = label(row['arcs'][-1][1])
            group = (service(row['arcs'][0][1]), service(row['arcs'][-1][1]))
            if counts[group] >= 2:
                continue
            counts[group] += 1
            effects = row['sensitivity']
            floor = effects[0]['untouched_sample_period_ns']
            scope = instance if instance == last_instance else f'{instance} → {last_instance}'
            lines.append(f"| {scope} | `{first}` → `{last}` | {row['endpoints']} / {row['endpoint_buses']} | {row['census_delay_ns']:.3f} | {effects[1]['sample_period_ns']:.3f} / {effects[2]['sample_period_ns']:.3f} | {floor if floor is not None else 'none sampled'} |")
            shown += 1
            if shown == 15:
                break
    return '\n'.join(lines)+'\n'


def main() -> None:
    """Analyze one fingerprinted extraction directory and write JSON plus Markdown."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-arcs', type=int, default=12)
    args = parser.parse_args()
    if not 2 <= args.max_arcs <= 32:
        parser.error('--max-arcs must be between 2 and 32')
    files = {key: args.input/name for key, name in [('metadata', 'extraction.json'), ('endpoints', 'endpoints.rpt.gz'), ('alternatives', 'alternatives.rpt.gz')]}
    before = {key: fingerprint(path) for key, path in files.items()}
    report = summarize(list(read_paths(files['endpoints'])), list(read_paths(files['alternatives'])), json.loads(files['metadata'].read_text()), args.max_arcs)
    after = {key: fingerprint(path) for key, path in files.items()}
    if before != after:
        raise ValueError('input changed during analysis')
    report['inputs'] = {key: {'path': str(path), 'sha256': before[key]} for key, path in files.items()}
    report['analyzer_sha256'] = fingerprint(Path(__file__))
    report['parser_sha256'] = fingerprint(Path(__file__).with_name('path_report.py'))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'shared-subchains.json').write_text(json.dumps(report, indent=2)+'\n')
    (args.output/'shared-subchains.md').write_text(markdown(report))


if __name__ == '__main__':
    main()
