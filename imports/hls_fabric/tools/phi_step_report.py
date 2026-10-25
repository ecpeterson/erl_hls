#!/usr/bin/env python3
"""Account for complete status intervals along observed latest causal prerequisites."""
from collections import Counter, defaultdict
import argparse
import gzip
import json
from pathlib import Path
import re

from phi_transport_metrics import distribution
from backend_commands import digest
from compiler_paths import compiler_root, compiler_tool


def attach_status(graph: dict, statuses: list[dict], routes: dict) -> list[dict]:
    """Join public status packets to unique actor effects by identity and complete frame bytes."""
    actors = {(a['device'], a['name']): a for a in routes['actors']}
    external = {(lane['source_device'], lane['source'], port): lane['destination']
                for lane in routes['lanes'] if lane['kind'] == 'external' for port in lane['ports']}
    sources = defaultdict(list)
    for event in graph['events']:
        if not event['track'].endswith('/effect') or 'payload' not in event.get('args', {}):
            continue
        device = int(event['track'].split('/')[0][1:])
        actor = event['args']['actor']
        description = actors[device, actor]
        port = int(event['args']['payload'], 16) >> 128
        if description['module'] != 'phi_halo_cell' or description['outputs'][port] != 'status':
            continue
        value = int(event['args']['payload'], 16) & ((1 << 128)-1)
        if int(event['args']['known_mask'], 16) & ((1 << 128)-1) != (1 << 128)-1:
            raise ValueError('status effect contains unknown bits')
        stream = external[device, actor, port].removeprefix('{external,').removesuffix('}')
        sources[device, stream, value].append(event)
    targets = []
    for ordinal, status in enumerate(statuses):
        payload = bytes.fromhex(status['payload_hex'])
        expected = b''.join(status[key].to_bytes(width, 'little') for key, width in
                            [('step', 4), ('x', 2), ('y', 2), ('flags', 4)])
        if payload != expected:
            raise ValueError('decoded status fields disagree with the complete 96-bit record')
        # Use the exact accepted header word, as in packet_frame; do not reinterpret API tuple fields.
        header = int.from_bytes(status['header_word'].to_bytes(4, 'big'), 'little')
        value = (header << 96) | int.from_bytes(payload, 'little')
        key = status['device'], status['stream'], value
        candidates = sources.pop(key, [])
        if len(candidates) != 1:
            raise ValueError(f'public status does not identify one complete producer frame: {key}')
        source, = candidates
        if source['ts'] > status['time_ns']:
            raise ValueError('public status precedes its producer')
        coords = re.search(r'\[(\d+),(\d+)\]', source['args']['actor'])
        if not coords or list(map(int, coords.groups())) != [status['x'], status['y']]:
            raise ValueError('status coordinates disagree with producer identity')
        event = {'id': f'host/status/{ordinal}', 'track': f"host/D{status['device']}/status", 'name': f"step {status['step']} / {source['args']['actor']}",
                 'ts': status['time_ns'], 'dur': 0, 'display_duration_ns': source['display_duration_ns'],
                 'args': {**status, 'producer_effect': source['id'], 'actor': source['args']['actor']}}
        graph['edges'].append({'source': source['id'], 'target': event['id'], 'kind': 'public status delivery',
                              'evidence': 'independent Erlang wire decode; unique actor stream and complete header/payload match'})
        targets.append(event)
    graph['events'].extend(targets)
    graph['tracks'].extend({'id': f'host/D{d}/status', 'name': f'D{d} complete public status', 'group': 'Round completion'}
                           for d in sorted({s['device'] for s in statuses}))
    return targets


def duration_kind(event: dict) -> str:
    """Label recorded execution spans separately from time between acceptances."""
    if event['id'].endswith('/tx'):
        return 'first-to-last wire transfer'
    if event['id'].endswith('/fold'):
        return 'collect/fold'
    if event['track'].endswith('/work'):
        return 'execution/publication'
    if event['name'] == 'mailbox RAM read':
        return 'mailbox RAM read'
    return 'other recorded service'


def gap_kind(edge: dict) -> str:
    """Name elapsed boundaries without claiming that a wait is necessary or reducible."""
    return {'produces effect': 'commit to effect acceptance',
            'ordered lane': 'effect to packetizer', 'packetization': 'packetizer to wire',
            'wire delivery': 'last wire transfer to peer complete',
            'receive admission': 'peer complete to receive queue',
            'aggregate queue': 'aggregate queue to mux', 'aggregate mux': 'aggregate mux forwarding',
            'aggregate capture': 'aggregate mux to scheduler', 'aggregate': 'aggregate to executor', 'contribution': 'input to collect',
            'public status delivery': 'status effect to public output'}.get(edge['kind'], 'ordinary/state/other waits')


class Accounting:
    """Index once; retain tied latest prerequisites and clip only at a disclosed time frontier."""

    def __init__(self, graph: dict) -> None:
        """Build causal adjacency without importing resource-order edges."""
        self.events = {e['id']: e for e in graph['events']}
        self.incoming = defaultdict(list)
        for edge in graph['edges']:
            if edge.get('delay_ns', 0):
                raise ValueError('explicit edge delays require separate accounting')
            self.incoming[edge['target']].append(edge)

    def latest(self, ident: str) -> list[dict]:
        """Return every prerequisite with the latest recorded completion, retaining ties."""
        edges = self.incoming[ident]
        if not edges:
            return []
        time = max(self.events[e['source']]['ts'] + self.events[e['source']]['dur'] for e in edges)
        return sorted([e for e in edges if self.events[e['source']]['ts'] + self.events[e['source']]['dur'] == time],
                      key=lambda e: e['source'])

    def budget(self, target: str, start: int) -> dict:
        """Partition one deterministic path; also bound each category over every tied alternative."""
        memo = {}
        selected, representative, segments, frontiers = set(), [], [], set()

        pending, active = [(target, False)], set()
        while pending:
            ident, expanded = pending.pop()
            if ident in memo:
                continue
            event = self.events[ident]
            end = event['ts'] + event['dur']
            if end <= start:
                frontiers.add(ident)
                memo[ident] = Counter(), Counter()
                continue
            edges = self.latest(ident)
            if not expanded:
                if ident in active:
                    raise ValueError('cycle in latest causal ancestry')
                active.add(ident)
                pending.append((ident, True))
                pending.extend((e['source'], False) for e in edges if e['source'] not in memo)
                continue
            active.remove(ident)
            selected.add(ident)
            own = Counter({duration_kind(event): end-max(start, event['ts'])})
            choices = []
            for edge in edges:
                source = self.events[edge['source']]
                ready = source['ts']+source['dur']
                if ready > event['ts']:
                    raise ValueError('causal predecessor overlaps its consumer')
                low, high = memo[source['id']]
                wait = max(0, event['ts']-max(start, ready))
                extra = Counter({gap_kind(edge): wait}) + own
                choices.append((low+extra, high+extra))
            if not choices:
                own['unobserved root'] += max(0, event['ts']-start)
                choices = [(own, own)]
                frontiers.add(ident)
            labels = set().union(*(set(lo) | set(hi) for lo, hi in choices))
            memo[ident] = (Counter({k: min(lo[k] for lo, _ in choices) for k in labels}),
                           Counter({k: max(hi[k] for _, hi in choices) for k in labels}))
        low, high = memo[target]
        ident = target
        while self.events[ident]['ts'] + self.events[ident]['dur'] > start:
            event = self.events[ident]
            representative.append(ident)
            finish = event['ts'] + event['dur']
            if finish > max(start, event['ts']):
                segments.append({'start': max(start, event['ts']), 'end': finish,
                                 'kind': duration_kind(event), 'event': ident})
            edges = self.latest(ident)
            ready = self.events[edges[0]['source']]['ts'] + self.events[edges[0]['source']]['dur'] if edges else start
            if event['ts'] > max(start, ready):
                segments.append({'start': max(start, ready), 'end': event['ts'],
                                 'kind': gap_kind(edges[0]) if edges else 'unobserved root',
                                 'source': edges[0]['source'] if edges else None, 'target': ident})
            if not edges:
                break
            ident = edges[0]['source']
        segments.sort(key=lambda s: s['start'])
        if any(a['end'] != b['start'] for a, b in zip(segments, segments[1:])):
            raise ValueError('latest-path elapsed spans do not meet')
        stop = self.events[target]['ts'] + self.events[target]['dur']
        totals = Counter()
        for segment in segments:
            totals[segment['kind']] += segment['end']-segment['start']
        if sum(totals.values()) != stop-start:
            raise ValueError('latest-path budget does not partition the status interval')
        return {'target': target, 'window_ns': [start, stop], 'representative_ns': dict(totals),
                'tied_path_min_ns': dict(low), 'tied_path_max_ns': dict(high), 'segments': segments,
                'representative': representative, 'latest_ancestry': sorted(selected), 'frontiers': sorted(frontiers)}

    def ancestors(self, target: str, start: int) -> set[str]:
        """Retain every causal branch until its first event crossing the time frontier."""
        pending, selected = [target], set()
        while pending:
            ident = pending.pop()
            if ident in selected:
                continue
            selected.add(ident)
            if self.events[ident]['ts'] + self.events[ident]['dur'] > start:
                pending.extend(e['source'] for e in self.incoming[ident])
        return selected


def compact_tracks(profile: dict) -> dict:
    """Group boundary roles, allocating separate tracks whenever tied branches overlap."""
    role_order = ['actor work', 'effect acceptance', 'packetizer admission', 'wire transfers',
                  'peer frame complete', 'receive queue', 'fragment arrival', 'collect/fold', 'aggregate selection', 'aggregate forwarding', 'scheduler capture', 'public status', 'other']
    def role(event: dict) -> str:
        """Group real observation nodes by boundary without joining their causal identities."""
        ident = event['id']
        if event['track'].endswith('/work'):
            return 'actor work'
        if event['track'].endswith('/effect'):
            return 'effect acceptance'
        for suffix, label in [('/capture', 'packetizer admission'), ('/tx', 'wire transfers'),
                              ('/rx', 'peer frame complete'), ('/delivery', 'receive queue'), ('/fold', 'collect/fold'),
                              ('/aggregate_select', 'aggregate selection'), ('/aggregate_forward', 'aggregate forwarding'),
                              ('/aggregate_capture', 'scheduler capture')]:
            if ident.endswith(suffix):
                return label
        if '/fragment' in ident:
            return 'fragment arrival'
        return 'public status' if ident.startswith('host/') else 'other'
    events, ends, labels = [], defaultdict(list), {}
    for event in sorted(profile['events'], key=lambda e: (e['ts'], e['id'])):
        if event['track'] == 'elapsed':
            events.append(event)
            continue
        name = role(event)
        duration = event.get('display_duration_ns', max(1, event['dur']))
        lane = next((i for i, end in enumerate(ends[name]) if end <= event['ts']), len(ends[name]))
        if lane == len(ends[name]):
            ends[name].append(0)
        ends[name][lane] = event['ts']+duration
        ident = f'{name}/{lane}'
        labels[ident] = name if lane == 0 else f'{name} / tied branch {lane+1}'
        events.append({**event, 'track': ident, 'args': {**event.get('args', {}), 'original_track': event['track']}})
    tracks = [t for t in profile['tracks'] if t['id'] == 'elapsed']
    tracks += [{'id': ident, 'name': label, 'group': 'Latest causal chain (ties retained)'}
               for ident, label in sorted(labels.items(), key=lambda pair: (role_order.index(pair[0].rsplit('/', 1)[0]), pair[0]))]
    return {**profile, 'events': events, 'tracks': tracks}


def publication_spacing(budget: dict, events: list[dict]) -> dict:
    """Separate initial publication latency from observed spacing within the same result batch."""
    by_id = {e['id']: e for e in events}
    batches = defaultdict(list)
    for event in events:
        if event['track'].endswith('/effect'):
            batches[event['args']['batch']].append(event)
    positions, initial, spacing, irregular = Counter(), 0, 0, 0
    for segment in budget['segments']:
        if segment['kind'] != 'commit to effect acceptance':
            continue
        event = by_id[segment['target']]
        first = min(e['ts'] for e in batches[event['args']['batch']])
        split = max(segment['start'], min(segment['end'], first))
        initial += split-segment['start']
        spacing += segment['end']-split
        positions[event['args']['position']] += 1
        irregular += not event['args'].get('parallel_publication', False) and event['ts']-first != event['args']['position']*event['display_duration_ns']
    return {'publication_positions': dict(positions), 'commit_to_first_acceptance_ns': initial,
            'within_batch_spacing_ns': spacing, 'non_clock_spaced_effects': irregular,
            'scope': 'Observed acceptance spacing, not predicted throughput gain. Positions number observed publications; concurrent lanes have no causal ordering.'}


def analyze(stage: Path, destination: Path, public: Path, focus_step: int) -> dict:
    """Check all public round boundaries and export one full contributor cone and elapsed overlay."""
    hls_profile = compiler_tool(public, "hls_profile")
    graph = json.loads(gzip.decompress((stage/'messages.profile.json.gz').read_bytes()))
    routes = json.loads((stage/'message-routes.json').read_text())
    targets = attach_status(graph, json.loads((stage/'status-events.json').read_text()), routes)
    index = Accounting(graph)
    progress = json.loads((stage/'progress.json').read_text())
    count = sum(a['module'] == 'phi_halo_cell' for a in routes['actors'])
    results = []
    for previous, current in zip(progress['complete_rounds'], progress['complete_rounds'][1:]):
        status = [e for e in targets if e['args']['step'] == current['step']]
        if len({(e['args']['stream'], e['args']['x'], e['args']['y']) for e in status}) != count:
            raise ValueError('incomplete public status round')
        latest = max(e['ts'] for e in status)
        if latest != current['time_ns']:
            raise ValueError('reconstructed status boundary disagrees with independently saved metrics')
        for event in status:
            if event['ts'] == latest:
                results.append({'step': current['step'], **index.budget(event['id'], previous['time_ns'])})
    continuous = index.budget(results[-1]['target'], progress['complete_rounds'][0]['time_ns'])
    focus = next(r for r in results if r['step'] == focus_step)
    selected = index.ancestors(focus['target'], focus['window_ns'][0])
    events = [e for e in graph['events'] if e['id'] in selected]
    tracks = {e['track'] for e in events}
    selection = {**graph, 'events': events, 'tracks': [t for t in graph['tracks'] if t['id'] in tracks], 'counters': [],
                 'edges': [e for e in graph['edges'] if e['source'] in selected and e['target'] in selected],
                 'resource_dependencies': [e for e in graph['resource_dependencies'] if e['source'] in selected and e['target'] in selected],
                 'metadata': {'scope': 'all causal contributors to the last public status in one interval; explicit carry-in frontier',
                              'source_profile_sha256': digest(stage/'messages.profile.json.gz'),
                              'window_ns': focus['window_ns'], 'target': focus['target']}}
    # The boundary carries existing state; it is not a synchronization barrier or new causal edge.
    included_targets = {e['target'] for e in selection['edges']}
    selection['metadata']['frontiers'] = [e['id'] for e in events if e['id'] not in included_targets]
    hls_profile.validate(selection)
    (destination/'step-contributors.profile.json.gz').write_bytes(gzip.compress(json.dumps(selection, separators=(',', ':')).encode()))
    (destination/'step-contributors.perfetto.json.gz').write_bytes(gzip.compress(json.dumps(hls_profile.perfetto(selection), separators=(',', ':')).encode()))
    # Small readable view: real latest-chain nodes/edges plus classified elapsed-time slices.
    latest = set(focus['latest_ancestry']) | set(focus['frontiers'])
    view = {**selection, 'events': [e for e in events if e['id'] in latest], 'resource_dependencies': [],
            'edges': [e for e in selection['edges'] if e['source'] in latest and e['target'] in latest],
            'tracks': [t for t in selection['tracks'] if t['id'] in {e['track'] for e in events if e['id'] in latest}]}
    view['metadata'] = {**selection['metadata'], 'scope': 'all tied latest causal predecessors; earlier required inputs are in step-contributors',
                        'frontiers': focus['frontiers']}
    view['tracks'].insert(0, {'id': 'elapsed', 'name': 'Elapsed time on one representative latest chain', 'group': 'Boundary accounting'})
    for ordinal, segment in enumerate(focus['segments']):
        view['events'].append({'id': f'elapsed/{ordinal}', 'track': 'elapsed', 'name': segment['kind'],
                               'ts': segment['start'], 'dur': segment['end']-segment['start'], 'category': 'unknown',
                               'args': {**segment, 'scope': 'elapsed between observations; no new causal edge, no rescheduling prediction'}})
    view = compact_tracks(view)
    (destination/'step-latest.profile.json').write_text(json.dumps(view, separators=(',', ':'))+'\n')
    (destination/'step-latest.perfetto.json').write_text(json.dumps(hls_profile.perfetto(view), separators=(',', ':'))+'\n')
    labels = sorted(set().union(*(set(r['representative_ns']) for r in results)))
    report = {'source_profile_sha256': digest(stage/'messages.profile.json.gz'),
              'status_events_sha256': digest(stage/'status-events.json'),
              'input_sha256': {name: digest(stage/name) for name in ('progress.log', 'progress.json', 'message-routes.json')},
              'public_status_frames': len(targets),
              'publication_spacing': publication_spacing(continuous, graph['events']),
              'continuous_window': continuous, 'rounds': results, 'representative_distributions_ns': {k: distribution([r['representative_ns'].get(k, 0) for r in results]) for k in labels},
              'focus': {'step': focus_step, 'all_contributor_events': len(events), 'latest_events': len(latest)},
              'scope': 'Observed latest prerequisites, not a rescheduling model. Resource ordering excluded. Each representative path partitions a complete public interval; tied-path componentwise bounds need not add to one path. A time frontier carries prior work and is not a causal barrier.'}
    (destination/'step-budget.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main() -> None:
    """Analyze an existing payload recording without another hardware run."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--erl-hls', type=Path, help='explicit compiler root')
    parser.add_argument('--profile', default='default', help='rebar dependency profile')
    parser.add_argument('--step', type=int, default=12)
    args = parser.parse_args()
    public = compiler_root(args.profile, args.erl_hls)
    args.output.mkdir(parents=True, exist_ok=True)
    result = analyze(args.stage, args.output, public, args.step)
    print(json.dumps(result['representative_distributions_ns'], indent=2))


if __name__ == '__main__':
    main()
