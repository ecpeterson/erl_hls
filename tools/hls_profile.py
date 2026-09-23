#!/usr/bin/env python3
"""Validated timing graphs with reusable SVG and Perfetto (Chrome JSON) exports."""
from __future__ import annotations

import argparse
from collections import defaultdict, deque
import html
import json
import math
from pathlib import Path


def validate(profile: dict) -> list[str]:
    """Check nanosecond timestamps, nonoverlapping tracks and acyclic finish/start dependencies."""
    if profile.get('schema') != 1 or profile.get('unit') != 'ns':
        raise ValueError('expected profile schema 1 with integer nanosecond time')
    tracks = profile['tracks']
    if len({t['id'] for t in tracks}) != len(tracks):
        raise ValueError('duplicate track ID')
    track_ids = {t['id'] for t in tracks}
    events = {e['id']: e for e in profile['events']}
    if len(events) != len(profile['events']):
        raise ValueError('duplicate event ID')
    lanes = defaultdict(list)
    for event in events.values():
        if {'event_id', 'duration_ns', 'display_duration_ns', 'profile_dependencies'} & event.get('args', {}).keys():
            raise ValueError('event arguments use reserved export fields')
        if event['track'] not in track_ids:
            raise ValueError('unknown event track')
        for field in ('ts', 'dur'):
            if type(event[field]) is not int or event[field] < 0:
                raise ValueError(f'{field} must be a nonnegative integer')
        display = event.get('display_duration_ns', event['dur'])
        if type(display) is not int or display < event['dur'] or (display != event['dur'] and event['dur'] != 0):
            raise ValueError('display duration may only expand an instant into an observed cycle')
        if event['ts']+display > 2**52:
            raise ValueError('use a trace-relative origin for times beyond 2**52 ns')
        lanes[event['track']].append(event)
    for lane in lanes.values():
        lane.sort(key=lambda e: e['ts'])
        if any(a['ts']+display_duration(a) > b['ts'] or a['ts'] == b['ts'] for a, b in zip(lane, lane[1:])):
            raise ValueError('overlapping slices require separate tracks')
    for counter in profile.get('counters', []):
        if counter['track'] not in track_ids or type(counter['ts']) is not int or not 0 <= counter['ts'] <= 2**52:
            raise ValueError('invalid counter track or time')
        if not math.isfinite(counter['value']) or float(counter['value']) != counter['value']:
            raise ValueError('counter must be exactly representable as a finite double')
    incoming, outgoing = dict.fromkeys(events, 0), defaultdict(list)
    pairs = set()
    for edge in profile['edges']:
        source, target = edge['source'], edge['target']
        if source not in events or target not in events or (source, target) in pairs:
            raise ValueError('unknown or duplicate dependency')
        pairs.add((source, target))
        a, b = events[source], events[target]
        delay = edge.get('delay_ns', 0)
        if type(delay) is not int or delay < 0 or a['ts']+a['dur']+delay > b['ts']:
            raise ValueError('dependency finishes after its consumer starts')
        if not edge.get('evidence'):
            raise ValueError('dependencies require evidence')
        incoming[target] += 1
        outgoing[source].append(target)
    ready = deque(sorted(key for key, n in incoming.items() if not n))
    order = []
    while ready:
        source = ready.popleft()
        order.append(source)
        for target in outgoing[source]:
            incoming[target] -= 1
            if incoming[target] == 0:
                ready.append(target)
    if len(order) != len(events):
        raise ValueError('cyclic dependencies')
    return order


def longest_path(profile: dict, target: str) -> dict:
    """Find the longest declared work/delay chain; unassigned gaps are not claimed as work."""
    order = validate(profile)
    events = {e['id']: e for e in profile['events']}
    if target not in events:
        raise ValueError(f'unknown path target: {target}')
    incoming = defaultdict(list)
    for edge in profile['edges']:
        incoming[edge['target']].append(edge)
    scores, previous = {}, {}
    for ident in order:
        candidates = incoming[ident]
        edge = max(candidates, key=lambda e: (scores[e['source']]+e.get('delay_ns', 0), e['source']), default=None)
        previous[ident] = edge
        scores[ident] = events[ident]['dur'] + (scores[edge['source']]+edge.get('delay_ns', 0) if edge else 0)
    path, edge_list = [], []
    node = target
    while True:
        path.append(node)
        edge = previous[node]
        if edge is None:
            break
        edge_list.append(edge)
        node = edge['source']
    elapsed = events[target]['ts']+events[target]['dur']-events[node]['ts']
    return {'target': target, 'events': path[::-1], 'edges': edge_list[::-1],
            'accounted_ns': scores[target], 'elapsed_ns': elapsed,
            'unassigned_ns': elapsed-scores[target],
            'scope': profile.get('metadata', {}).get('dependency_scope', 'recorded dependencies only')}



def display_duration(event: dict) -> int:
    """Return a declared observation-cycle width without adding work to causal accounting."""
    return event.get('display_duration_ns', event['dur'])


def counter_name(counter: dict) -> str:
    """Give process-scoped Chrome counters a reversible identity including their logical track."""
    return json.dumps([counter['track'], counter['name']], separators=(',', ':'), ensure_ascii=False)

def perfetto(profile: dict) -> dict:
    """Export slices, counters, argument metadata and causal flows without external dependencies."""
    validate(profile)
    processes = {name: i+1 for i, name in enumerate(dict.fromkeys(t.get('group', 'HLS') for t in profile['tracks']))}
    tracks = {t['id']: (processes[t.get('group', 'HLS')], i+1) for i, t in enumerate(profile['tracks'])}
    result = []
    for name, pid in processes.items():
        result.append({'ph': 'M', 'name': 'process_name', 'pid': pid, 'args': {'name': name}})
    for track in profile['tracks']:
        pid, tid = tracks[track['id']]
        result.append({'ph': 'M', 'name': 'thread_name', 'pid': pid, 'tid': tid, 'args': {'name': track['name']}})
    events = {e['id']: e for e in profile['events']}
    incoming = defaultdict(list)
    for edge in profile['edges']:
        incoming[edge['target']].append(edge)
    timed = []
    # Chrome flow args are not imported by Perfetto; retain their evidence on the consumer slice.
    for event in events.values():
        pid, tid = tracks[event['track']]
        timed.append({'ph': 'X', 'name': event['name'], 'cat': event.get('category', 'work'),
                      'pid': pid, 'tid': tid, 'ts': event['ts']/1000, 'dur': display_duration(event)/1000,
                      'args': {**event.get('args', {}), 'event_id': event['id'], 'duration_ns': event['dur'],
                               'display_duration_ns': display_duration(event),
                               'profile_dependencies': json.dumps(incoming[event['id']], separators=(',', ':'))}})
    for index, edge in enumerate(profile['edges'], 1):
        # Anchor each flow to the source/target slice start, not an ambiguous shared end boundary.
        for phase, endpoint in (('s', 'source'), ('f', 'target')):
            event = events[edge[endpoint]]
            pid, tid = tracks[event['track']]
            timed.append({'ph': phase, 'name': edge['kind'], 'cat': 'dependency', 'id': index,
                          'pid': pid, 'tid': tid, 'ts': event['ts']/1000,
                          **({'bp': 'e'} if phase == 'f' else {}), 'args': edge})
    for counter in profile.get('counters', []):
        pid, tid = tracks[counter['track']]
        timed.append({'ph': 'C', 'name': counter_name(counter), 'pid': pid, 'tid': tid,
                      'ts': counter['ts']/1000, 'args': {'value': counter['value']}})
    result += sorted(timed, key=lambda e: (e['ts'], {'X': 0, 's': 1, 'f': 2, 'C': 3}[e['ph']]))
    return {'traceEvents': result, 'displayTimeUnit': 'ns', 'metadata': profile.get('metadata', {})}



def window(profile: dict, start: int, end: int) -> dict:
    """Keep complete events in a window, recording omitted dependencies and boundary counter values."""
    validate(profile)
    if end <= start:
        raise ValueError('empty profile window')
    events = [e for e in profile['events'] if start <= e['ts'] and e['ts']+display_duration(e) < end]
    ids = {e['id'] for e in events}
    edges = [e for e in profile['edges'] if e['source'] in ids and e['target'] in ids]
    boundary = sum((e['source'] in ids) != (e['target'] in ids) for e in profile['edges'])
    counters, prior = [], {}
    for sample in profile.get('counters', []):
        if start <= sample['ts'] < end:
            counters.append(sample)
        elif sample['ts'] < start:
            key = sample['track'], sample['name']
            if key not in prior or prior[key]['ts'] < sample['ts']:
                prior[key] = sample
    counters += [{**s, 'ts': start, 'original_ts': s['ts']} for s in prior.values()
                 if not any(c['track'] == s['track'] and c['name'] == s['name'] and c['ts'] == start for c in counters)]
    metadata = {**profile.get('metadata', {}), 'window_ns': [start, end], 'omitted_boundary_edges': boundary}
    metadata['dependency_scope'] = f"window ({boundary} boundary dependencies omitted); " + metadata.get('dependency_scope', 'recorded dependencies only')
    return {**profile, 'events': events, 'edges': edges, 'counters': counters, 'metadata': metadata}

def svg(profile: dict, start: int, end: int, target: str | None = None) -> str:
    """Draw a time window with native hover details and an optional longest recorded chain."""
    validate(profile)
    if end <= start:
        raise ValueError('empty timeline window')
    visible = [e for e in profile['events'] if e['ts'] < end and e['ts']+display_duration(e) >= start]
    tracks = [t for t in profile['tracks'] if any(e['track'] == t['id'] for e in visible)]
    series = defaultdict(list)
    for counter in profile.get('counters', []):
        series[counter['track'], counter['name']].append(counter)
    series = {key: samples for key, samples in series.items() if any(c['ts'] < end for c in samples)}
    lanes = {t['id']: 90+52*i for i, t in enumerate(tracks)}
    positions = {e['id']: e for e in visible}
    path = longest_path(profile, target) if target else None
    bold = {(e['source'], e['target']) for e in path['edges']} if path else set()
    marked = set(path['events']) if path else set()
    width, height = 1450, 140+52*(len(tracks)+len(series))
    esc = html.escape
    colors = {'wait': '#d7a84b', 'service': '#2878b5', 'unknown': '#c5cbd3', 'handshake': '#8661b5'}
    def x(time: int) -> float:
        """Map nanoseconds into the visible plot area."""
        return 230+(time-start)*1190/(end-start)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<style>text{font:12px sans-serif;fill:#17212b}.edge{fill:none;stroke:#9ca9ba;stroke-width:1}.bold{stroke:#17212b;stroke-width:3} .event:hover{stroke:#d65f00;stroke-width:3}</style>',
           '<rect width="100%" height="100%" fill="#fff"/>',
           '<defs><marker id="arrow" viewBox="0 0 8 8" refX="8" refY="4" markerWidth="4" markerHeight="4" orient="auto"><path d="M0 0 L8 4 L0 8Z" fill="context-stroke"/></marker></defs>',
           '<text x="15" y="23">Timing graph — hover blocks and dependencies for evidence</text>',
           '<text x="700" y="23">Blue: service · amber: wait · gray: unknown · purple: boundary clock bin</text>']
    if path:
        out.append(f'<text x="15" y="43">Longest recorded chain (full selected graph): {path["accounted_ns"]} ns accounted; {path["unassigned_ns"]} ns unassigned. {esc(path["scope"])}</text>')
    for i in range(11):
        time = start+(end-start)*i//10
        anchor = 'end' if i == 10 else 'start'
        out += [f'<path d="M{x(time):.2f} 65 V{height-30}" stroke="#edf0f3"/>',
                f'<text x="{x(time):.2f}" y="64" text-anchor="{anchor}">{time} ns</text>']
    def label(text: str, y: int) -> str:
        """Keep lane names out of the plot; retain the complete name on hover."""
        shortened = text if len(text) <= 31 else text[:30]+'…'
        return f'<text x="12" y="{y+4}"><title>{esc(text)}</title>{esc(shortened)}</text>'
    for track in tracks:
        y = lanes[track['id']]
        out += [label(track['name'], y),
                f'<path d="M230 {y} H1420" stroke="#dde3e9"/>']
    for index, ((track, name), samples) in enumerate(series.items()):
        samples.sort(key=lambda c: c['ts'])
        points = [c for c in samples if start <= c['ts'] < end]
        preceding = [c for c in samples if c['ts'] < start]
        if preceding:
            points.insert(0, {**preceding[-1], 'ts': start})
        if not points:
            continue
        y = 90+52*(len(tracks)+index)
        scale = max(1, max(abs(c['value']) for c in points))
        out.append(label(f'{track} / {name} [0…{scale}]', y))
        previous_y = y-18*points[0]['value']/scale
        for current, following in zip(points, [*points[1:], {'ts': end}]):
            xp, xq = x(current['ts']), x(following['ts'])
            yp = y-18*current['value']/scale
            out.append(f'<path d="M{xp:.2f} {previous_y:.2f} V{yp:.2f} H{xq:.2f}" fill="none" stroke="#378447" data-tooltip="{esc(json.dumps(current))}"><title>{esc(json.dumps(current))}</title></path>')
            previous_y = yp
    for edge in profile['edges']:
        if edge['source'] not in positions or edge['target'] not in positions:
            continue
        a, b = positions[edge['source']], positions[edge['target']]
        ax, bx = x(min(end, a['ts']+a['dur'])), x(max(start, b['ts']))
        ay, by = lanes[a['track']], lanes[b['track']]
        mid = (ax+bx)/2
        cls = 'edge bold' if (a['id'], b['id']) in bold else 'edge'
        out.append(f'<path class="{cls}" marker-end="url(#arrow)" data-tooltip="{esc(json.dumps(edge))}" d="M{ax:.2f} {ay} Q{mid:.2f} {min(ay,by)-20} {bx:.2f} {by}"><title>{esc(json.dumps(edge, indent=2))}</title></path>')
    for event in visible:
        y, xp = lanes[event['track']], x(max(start, event['ts']))
        duration = max(3, x(min(end, event['ts']+display_duration(event)))-xp)
        color = '#c45b17' if event['id'] in marked else colors.get(event.get('category'), '#2878b5')
        tip = esc(json.dumps(event, indent=2))
        out.append(f'<rect class="event" x="{xp:.2f}" y="{y-8}" width="{duration:.2f}" height="16" rx="2" fill="{color}" data-tooltip="{tip}"><title>{tip}</title></rect>')
        if duration >= 45:
            # Conservative character budget keeps labels inside their own clock interval.
            budget = int((duration-8)/7)
            event_label = event['name'] if len(event['name']) <= budget else event['name'][:max(0, budget-1)]+'…'
            out.append(f'<text x="{xp+4:.2f}" y="{y+4}" style="fill:#111;pointer-events:none">{esc(event_label)}</text>')
    return '\n'.join([*out, '</svg>'])+'\n'


def main() -> None:
    """Render a saved profile without rereading RTL or rerunning simulation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', type=Path)
    parser.add_argument('--perfetto', type=Path)
    parser.add_argument('--svg', type=Path)
    parser.add_argument('--start', type=int)
    parser.add_argument('--end', type=int)
    parser.add_argument('--target')
    parser.add_argument('--window', action='store_true', help='export only complete events in --start/--end')
    args = parser.parse_args()
    profile = json.loads(args.profile.read_text())
    validate(profile)
    if args.window:
        if args.start is None or args.end is None:
            parser.error('--window requires --start and --end')
        profile = window(profile, args.start, args.end)
    if args.perfetto:
        args.perfetto.write_text(json.dumps(perfetto(profile), separators=(',', ':'))+'\n')
    if args.svg:
        if args.start is None or args.end is None:
            parser.error('--svg requires --start and --end in ns')
        args.svg.write_text(svg(profile, args.start, args.end, args.target))
    if args.target:
        print(json.dumps(longest_path(profile, args.target), indent=2))


if __name__ == '__main__':
    main()
