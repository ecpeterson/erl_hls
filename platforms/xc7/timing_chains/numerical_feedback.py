#!/usr/bin/env python3
"""Account for the observed diffusion feedback path before proposing a hot-state bypass."""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path
import statistics

from architecture import sha


def distribution(values: list[float]) -> dict:
    """Report the complete population's spread, without treating it as a confidence interval."""
    return {'samples': len(values), 'best': min(values), 'mean': statistics.mean(values),
            'variance': statistics.pvariance(values), 'worst': max(values)}


def small_fixture(trace: Path) -> dict:
    """Report only uniquely bracketed actor-local transactions in the older sparse trace."""
    actors = defaultdict(list)
    with trace.open() as stream:
        for row in csv.DictReader(stream):
            if row['component'].startswith('phi_') and row['slot'] != '-1':
                row['cycle'] = int(row['cycle'])
                actors[row['component'], row['slot']].append(row)
    samples, skipped = [], 0
    for events in actors.values():
        aggregates = [e for e in events if e['event'] == 'aggregate_receive']
        for first, following in zip(aggregates, aggregates[1:]):
            if not first['detail'].startswith('site=gathering;'):
                continue
            middle = [e for e in events if first['cycle'] <= e['cycle'] < following['cycle']]
            reads = [e for e in middle if e['event'] == 'state_read']
            writes = [e for e in middle if e['event'] == 'state_write']
            if len(reads) != 1 or len(writes) != 1 or reads[0]['cycle'] > writes[0]['cycle']:
                skipped += 1
                continue
            samples.append({'aggregate_to_ram': reads[0]['cycle']-first['cycle'],
                            'ram_to_commit': writes[0]['cycle']-reads[0]['cycle']})
    if not samples:
        raise ValueError('no unambiguous small-fixture transactions')
    return {'trace_sha256': sha(trace), 'matched': len(samples), 'ambiguous_skipped': skipped,
            'cycle_intervals': {k:distribution([s[k] for s in samples]) for k in samples[0]},
            'missing': ['Operand values', 'Executor acceptance and arithmetic substages',
                        'Actor identity on publication port'],
            'scope': 'Small replay fixture, complete recorded run; sparse observations, not the D6 application.'}


def analyze(profile: Path, summary: Path) -> dict:
    """Join existing actor/site/epoch identities; never pair merely adjacent activity."""
    graph = json.loads(profile.read_text())
    report = json.loads(summary.read_text())
    start, stop = report['window_ns']
    metadata = graph['metadata']
    period = metadata['clock_period_ns']
    origin = metadata['reset_release_ns']
    by_id = {e['id']: e for e in graph['events']}
    groups, publications = defaultdict(dict), defaultdict(list)
    for event in graph['events']:
        args = event['args']
        if 'producer' in args and event['name'].startswith('effect '):
            publications[args['producer']].append(event['ts'])
        if event['name'] in ('complete aggregate', 'scheduler captures aggregate', 'state RAM read') and args.get('site') == 0:
            key = args['actor'], args['key']
            if event['name'] in groups[key]:
                raise ValueError(f'ambiguous epoch identity: {key}')
            groups[key][event['name']] = event
    rows = []
    for (actor, epoch), events in groups.items():
        read = events.get('state RAM read')
        if read is None or not start <= read['ts'] < stop:
            continue
        fold, capture = events['complete aggregate'], events['scheduler captures aggregate']
        work = by_id[read['args']['finisher']]
        args = work['args']
        if args['reduction_before']['key'] != epoch or args['phase_before'] != 'gathering':
            raise ValueError('reduction identity disagrees with the accepted callback')
        boundaries = {
            'inputs_ready': origin + max(*fold['args']['fragment_arrivals'], fold['args']['opening_arrival_cycle'])*period,
            # The displayed fold block begins at input acceptance; its width
            # is not a substitute for the separately observed output transfer.
            'aggregate': origin + fold['args']['aggregate_cycle']*period,
            'capture': capture['ts'], 'ram': read['ts'],
            'execute': work['ts'], 'result': origin + args['result_cycle']*period,
            'commit': work['ts'] + work['dur'],
            'publication': min(publications[work['id']])}
        stages = ('inputs_ready', 'aggregate', 'capture', 'ram', 'execute', 'result', 'commit', 'publication')
        deltas = {a+'_to_'+b: (boundaries[b]-boundaries[a])/period for a,b in zip(stages, stages[1:])}
        # Publication may overlap the observed RAM write. Preserve a negative
        # displacement; it is not evidence of a negative-latency computation.
        if any(v < 0 for k,v in deltas.items() if k != 'commit_to_publication'):
            raise ValueError('causal timestamp inversion')
        rows.append({'actor': actor, 'epoch': epoch, 'round': epoch % 12,
                     'boundaries_ns': boundaries, 'cycles': deltas})
    if not rows:
        raise ValueError('no matched diffusion windows')
    metrics = {key: distribution([r['cycles'][key] for r in rows]) for key in rows[0]['cycles']}
    capture_to_publication = [(r['boundaries_ns']['publication']-r['boundaries_ns']['capture'])/period for r in rows]
    return {'inputs': {str(p): sha(p) for p in (profile, summary, Path(__file__))},
        'clock_period_ns': period, 'window_ns': [start, stop], 'cycle_intervals': metrics,
        'capture_to_publication_cycles': distribution(capture_to_publication),
        'round_coverage': {str(i): sum(r['round'] == i for r in rows) for i in range(12)},
        'rows': rows, 'scope': 'Recorded local diffusion transactions; not a whole-mesh counterfactual.',
        'missing': ['Internal arithmetic substage timestamps',
                    'Network and cold/hot-owner handoff cost of a future integrated numerical engine']}


def main() -> None:
    """Read a retained complete-tile actor profile and write a reproducible feedback ledger."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'summary', 'output'):
        parser.add_argument('--'+name, required=True, type=lambda p: Path(p).resolve())
    parser.add_argument('--small-trace', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    result = analyze(args.profile, args.summary)
    if args.small_trace:
        result['small_fixture'] = small_fixture(args.small_trace)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('inputs', 'rows')}, indent=2))


if __name__ == '__main__':
    main()
