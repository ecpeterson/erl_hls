#!/usr/bin/env python3
"""Summarize limiting reduction inputs and export one comparable causal handoff per recording."""
import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path
import sys

from phi_transport_metrics import distribution
from backend_commands import digest


def input_chain(target: dict, events: dict, incoming: dict) -> list[dict]:
    """Follow one delivery back to its producer; stop where evidence branches or ends."""
    chain = [target]
    while not chain[-1]['track'].endswith('/work') and len(incoming[chain[-1]['id']]) == 1:
        chain.append(events[incoming[chain[-1]['id']][0]['source']])
    return list(reversed(chain))


def intervals(chain: list[dict]) -> dict[str, int]:
    """Partition one local or remote delivery between independently recorded boundaries."""
    if len(chain) not in (3, 7) or not chain[0]['track'].endswith('/work'):
        raise ValueError('incomplete message chain')
    producer, effect, *_, fragment = chain
    values = {'producer_execution_and_publication': producer['dur'],
              'commit_to_effect_acceptance': effect['ts']-producer['ts']-producer['dur']}
    if len(chain) == 3:
        values['effect_to_fragment_queue'] = fragment['ts']-effect['ts']
    else:
        _, _, capture, tx, rx, delivery, _ = chain
        values.update({'effect_to_packetizer_admission': capture['ts']-effect['ts'],
              'admission_to_first_wire_word': tx['ts']-capture['ts'],
              'first_to_last_wire_word': tx['dur'],
              'last_wire_word_to_peer_complete': rx['ts']-tx['ts']-tx['dur'],
              'peer_complete_to_receive_queue': delivery['ts']-rx['ts'],
              'receive_queue_to_fragment_queue': fragment['ts']-delivery['ts']})
    if min(values.values()) < 0 or sum(values.values()) != fragment['ts']-producer['ts']:
        raise ValueError('message boundary intervals do not partition elapsed time')
    return values


def handoff_selection(fold: dict, events: dict, incoming: dict, outgoing: dict) -> tuple[set[str], list[str], list[list[dict]]]:
    """Retain every immediate contributor's complete producer chain and publication batch."""
    prerequisites = [events[e['source']] for e in incoming[fold['id']]]
    chains = [input_chain(item, events, incoming) for item in prerequisites]
    for item, chain in zip(prerequisites, chains):
        if not item['id'].endswith('/open'):
            intervals(chain)  # Missing producer ancestry must not become a plausible empty row.
    ordered = [e for chain in chains for e in chain]
    for chain in chains:
        if len(chain) in (3, 7):
            batch = chain[1]['args']['batch']
            ordered += [events[batch], *[e for e in events.values() if e.get('args', {}).get('batch') == batch]]
    ordered += [fold, *[events[e['target']] for e in outgoing[fold['id']]]]
    return {e['id'] for e in ordered}, list(dict.fromkeys(e['track'] for e in ordered)), chains


def report(stage: Path, destination: Path, name: str, profile_tools: Path) -> dict:
    """Compare all latest prerequisites in the original measurement window; retain tied inputs."""
    sys.path.insert(0, str(profile_tools))
    import hls_profile
    graph = json.loads(gzip.decompress((stage/'messages.profile.json.gz').read_bytes()))
    events = {event['id']: event for event in graph['events']}
    incoming, outgoing = defaultdict(list), defaultdict(list)
    for edge in graph['edges']:
        incoming[edge['target']].append(edge)
        outgoing[edge['source']].append(edge)
    start, stop = json.loads((stage/'service.json').read_text())['window_ns']
    counts, samples = Counter(), defaultdict(list)
    for fold in graph['events']:
        if not fold['id'].endswith('/fold') or not start <= fold['ts'] < stop:
            continue
        prerequisites = [events[e['source']] for e in incoming[fold['id']]]
        latest = max(event['ts']+event['dur'] for event in prerequisites)
        limiting = [event for event in prerequisites if event['ts']+event['dur'] == latest]
        counts['windows'] += 1
        counts['tied_windows'] += len(limiting) > 1
        for item in limiting:
            if item['id'].endswith('/open'):
                counts['limiting_openings'] += 1
                continue
            chain = input_chain(item, events, incoming)
            if len(chain) == 7:
                counts['limiting_remote_inputs'] += 1
                timing = intervals(chain)
                for key, value in timing.items():
                    samples[key].append(value)
                samples['commit_to_fragment_queue'].append(sum(timing.values())-timing['producer_execution_and_publication'])
            elif len(chain) == 3:
                counts['limiting_local_inputs'] += 1
            else:
                raise ValueError('latest reduction input lacks a complete local or remote chain')
    # Compare a fixed semantic window, not whichever picture happens to look best.
    fold, = [e for e in graph['events'] if e['id'].startswith('D0/') and e['id'].endswith('/fold')
             and e['args']['actor'] == '{actor,{family,phi_x,[0,0]}}'
             and e['args']['site'] == 0 and e['args']['key'] == 145]
    prerequisites = [events[e['source']] for e in incoming[fold['id']]]
    fragments = [e for e in prerequisites if not e['id'].endswith('/open')]
    last = max(fragments, key=lambda event: (event['ts']+event['dur'], event['id']))
    chain = input_chain(last, events, incoming)
    selection, track_order, chains = handoff_selection(fold, events, incoming, outgoing)
    selected = [e for e in graph['events'] if e['id'] in selection]
    tracks = {t['id']: t for t in graph['tracks']}
    focus = {**graph, 'events': selected, 'tracks': [tracks[t] for t in track_order], 'counters': [],
             'edges': [e for e in graph['edges'] if e['source'] in selection and e['target'] in selection],
             'resource_dependencies': [e for e in graph.get('resource_dependencies', []) if e['source'] in selection and e['target'] in selection],
             'metadata': {'dependency_scope': 'all immediate contributors to one reduction handoff; earlier producer-state ancestry and ordinary mail omitted',
                          'source_profile': str(stage/'messages.profile.json.gz'),
                          'source_profile_sha256': digest(stage/'messages.profile.json.gz'), 'selected_window': {'site': 0, 'key': 145}}}
    left = min(e['ts'] for e in selected)-8
    right = max(e['ts']+hls_profile.display_duration(e) for e in selected)+8
    # Annotation spans partition elapsed time; they are not causal work and get no edges.
    timing = intervals(chain)
    focus['tracks'].insert(0, {'id': 'elapsed', 'name': 'Latest fragment: elapsed service + wait', 'group': 'Boundary accounting'})
    cursor = chain[0]['ts']
    for index, (label, duration) in enumerate(timing.items()):
        if duration:
            focus['events'].append({'id': f'elapsed/{index}', 'track': 'elapsed', 'name': f'{duration} ns',
                'ts': cursor, 'dur': duration, 'category': 'unknown',
                'args': {'interval': label, 'evidence': 'elapsed between recorded boundaries; not an occupation or causality claim'}})
        cursor += duration
    for item in selected:
        if item['dur'] == 0:
            item['category'] = 'handshake'
    # Detailed transport names remain in event arguments; label the rows by their boundaries.
    for track in focus['tracks']:
        if 'message transport' in track.get('group', ''):
            track['name'] = {suffix: track['id'].split('/')[0]+' '+label for suffix, label in
                [('capture', 'packetizer accepts'), ('tx', 'first-to-last wire word'),
                 ('rx', 'peer frame complete'), ('delivery', 'receive queue accepts')]}[track['id'].rsplit('/', 1)[1]]
    overlay = hls_profile.observed_overlay(focus, fold['id'])
    for suffix, value in (('profile.json', overlay), ('perfetto.json', hls_profile.perfetto(overlay))):
        (destination/f'{name}-handoff.{suffix}').write_text(json.dumps(value, separators=(',', ':'))+'\n')
    (destination/f'{name}-handoff.svg').write_text(hls_profile.svg(focus, left, right, observed_target=fold['id']))
    result = {'source_profile_sha256': focus['metadata']['source_profile_sha256'], 'window_ns': [start, stop], 'counts': dict(counts),
              'latest_remote_input_intervals_ns': {key: distribution(values) for key, values in samples.items()},
              'example': {'target': fold['id'], 'kind': 'remote' if len(chain) == 7 else 'local', 'chain': [{'id': e['id'], 'name': e['name'], 'ts': e['ts'], 'dur': e['dur']} for e in chain],
                          'intervals_ns': intervals(chain),
                          'contributors': [[e['id'] for e in c] for c in chains]},
              'correlation': graph['metadata']['report'],
              'scope': 'Each latest required remote input is a sample; ties are retained. Boundary intervals include service and waiting. These are local handoffs, not a whole-step critical path.'}
    (destination/f'{name}-summary.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main() -> None:
    """Render a matched pair of saved captures without new simulation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', nargs=2, action='append', metavar=('NAME', 'STAGE'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--profile-tools', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, path in args.run:
        summary = report(Path(path), args.output, name, args.profile_tools)
        print(name, json.dumps(summary['counts']), flush=True)


if __name__ == '__main__':
    main()
