#!/usr/bin/env python3
"""Reconstruct shared phi actor work from public state projections and FIFO handshakes."""
import argparse
from collections import Counter, defaultdict
from bisect import bisect_left, bisect_right
import gzip
import json
from pathlib import Path
import re
import sys

from phi_cycle_trace import capture_path, read, trace_digest
from phi_transport_metrics import dense, distribution
from test_actor_rtl import digest


def reduction(resource: dict, value: int) -> dict:
    """Decode a manifest-described reduction without relying on machine RAM layout."""
    if 'reduction' not in resource:
        return dict.fromkeys(('status', 'site', 'key', 'remaining', 'failure'), 0)
    return {name: (value >> field['observation_offset']) & ((1 << field['width'])-1)
            for name, field in resource['reduction']['fields'].items()}


def classify(before: dict, after: dict, old_phase: str, phase: str) -> str:
    """Name only transitions justified by the reduction status/count and emitted phase."""
    if before['status'] == 2:
        return 'completion + entry' if after['status'] == 1 else 'completion'
    if before['status'] == 1 and before['key'] == after['key'] and before['site'] == after['site'] and after['remaining'] == before['remaining']-1:
        return 'contribution'
    if before['status'] == 1 and (after['status'] == 0 or before['key'] != after['key'] or before['site'] != after['site']):
        return 'aggregate completion + entry' if after['status'] == 1 else 'aggregate completion'
    if old_phase != phase:
        return 'phase transition + entry'
    return 'other / postponed'


def final_effect(credit: int, effects: list[int], credit_port: list[int]) -> int:
    """Locate the last effect at a credited registered output, including either port's held tail."""
    if effects[credit] == 3:
        return credit
    if effects[credit] == 1:
        # The effect register retains the final word after the independent credit
        # register drains. Its next acceptance still belongs to this batch.
        for cycle in range(credit+1, len(effects)):
            if effects[cycle] == 3:
                return cycle
            if effects[cycle] != 1:
                break
    else:
        # Conversely, a held credit can outlive the already accepted effect.
        for cycle in range(credit-1, -1, -1):
            if credit_port[cycle] != 1:
                break
            if effects[cycle] == 3:
                return cycle
    raise ValueError('outbox credit cannot be paired with its final accepted effect')


def extract(stage: Path, device: int) -> Path:
    """Retain one device's public observations once, with digests tying it to the complete recording."""
    source = capture_path(stage)
    output = stage/f'device{device}-trace.csv.gz'
    record = stage/f'device{device}-trace-source.json'
    if record.exists():
        metadata = json.loads(record.read_text())
        if metadata['source_sha256'] == trace_digest(source) and metadata['trace_sha256'] == digest(output):
            return output
        raise ValueError('cached per-device capture changed')
    before = trace_digest(source)
    with (gzip.open(source, 'rt') if source.suffix == '.gz' else source.open()) as incoming, \
            gzip.open(output, 'wt', compresslevel=6) as outgoing:
        outgoing.write(next(incoming))
        for line in incoming:
            if int(line.split(',', 2)[1]) == device:
                outgoing.write(line)
    if trace_digest(source) != before:
        raise ValueError('recording changed during extraction')
    record.write_text(json.dumps({'source_sha256': before, 'trace_sha256': digest(output)}, indent=2)+'\n')
    return output


def reconstruct(stage: Path, device: int, trace: Path, *, all_actors: bool = False,
                publication_cycles: int = 1) -> tuple[dict, dict]:
    """Emit local work and flows, requiring one execution clock and publication_cycles to each state write."""
    if publication_cycles < 1:
        raise ValueError('publication latency must be at least one clock')
    resources, histories = read(stage, {device}, trace)
    banks = sorted({(r.get('bank', 0), r['module']) for r in resources.values()
                    if r['kind'] == 'actor' and (all_actors or r.get('module') == 'phi_halo_cell')})
    if not banks:
        raise ValueError('no phi actors in the recording')
    groups = [reconstruct_group(stage, device, trace, resources, histories, bank,
              sum(m == module for _, m in banks[:index]), module, publication_cycles)
              for index, (bank, module) in enumerate(banks)]
    if len(groups) == 1:
        if json.loads((stage/'profile-inputs.json').read_text()).get('reductions') == 'source_fragments':
            from phi_reduction_profile import extend
            extend(*groups[0], stage, device, resources, histories)
        return groups[0]
    profile, report = groups[0]
    profile = {**profile, **{key: [] for key in ('tracks', 'events', 'edges', 'counters')}}
    for (bank, _), (graph, _) in zip(banks, groups):
        prefix = f'bank{bank}/'
        for track in graph['tracks']:
            profile['tracks'].append({**track, 'id': prefix+track['id']})
        for event in graph['events']:
            args = {k: prefix+v if k in ('producer', 'batch') else v for k, v in event['args'].items()}
            profile['events'].append({**event, 'id': prefix+event['id'], 'track': prefix+event['track'], 'args': args})
        profile['edges'] += [{**edge, 'source': prefix+edge['source'], 'target': prefix+edge['target']} for edge in graph['edges']]
        profile['counters'] += [{**counter, 'track': prefix+counter['track']} for counter in graph['counters']]
    reports = [r for _, r in groups]
    kinds, waits, durations = Counter(), Counter(), defaultdict(list)
    for r in reports:
        for entry in r['window_activations']:
            kinds[entry['kind'], entry['phase_before'], entry['reduction_site']] += entry['count']
        waits.update(r['observed_actor_time_ns'])
        for name, stats in r['durations_ns'].items():
            durations[name] += [int(value) for value, count in stats['histogram'].items() for _ in range(count)]
    report = {**report, 'scheduler_groups': reports, 'slots': sum(r['slots'] for r in reports),
        **{key: sum(r[key] for r in reports) for key in ('state_writes', 'executor_requests', 'executor_results', 'reserved_with_candidate_ns')},
        'window_activations': [{'kind': k[0], 'phase_before': k[1], 'reduction_site': k[2], 'count': n} for k,n in sorted(kinds.items())],
        'observed_actor_time_ns': dict(waits), 'durations_ns': {key: distribution(values) for key, values in durations.items()}}
    report.pop('bank')
    if json.loads((stage/'profile-inputs.json').read_text()).get('reductions') == 'source_fragments':
        from phi_reduction_profile import extend
        extend(profile, report, stage, device, resources, histories)
    return profile, report


def reconstruct_group(stage: Path, device: int, trace: Path, resources: dict, histories: dict,
                      bank: int, ordinal: int, module: str = 'phi_halo_cell',
                      publication_cycles: int = 1) -> tuple[dict, dict]:
    """Match one normalized bank to its generated module-instance ordinal; retain local slot identity."""
    actors = [r for r in resources.values() if r['kind'] == 'actor' and r.get('module') == module]
    actors = [r for r in actors if r.get('bank', 0) == bank]
    ids = {r['id']: r for r in actors}
    queues = [r for r in resources.values() if r['kind'] == 'fifo' and module in r['name']]
    requests_by_instance = sorted((r for r in queues if r['name'].endswith('fifo__executor_request_')), key=lambda r: r['name'])
    request = requests_by_instance[ordinal]
    instance = request['name'].rsplit('/', 1)[0]
    result, = [r for r in queues if r['name'].endswith('fifo__executor_result_') and r['name'].rsplit('/', 1)[0] == instance]
    count = 1+max(int(fields[2]) for line in (stage/'activity.log').read_text().splitlines()
                  if (fields := line.split())[1] == str(device))
    inputs = json.loads((stage/'profile-inputs.json').read_text())
    period = inputs['device_periods_ns'][device]
    origin = histories[device, request['pop']][0]['time_ns']
    start, stop = json.loads((stage/'service.json').read_text())['window_ns']
    if origin+count*period < stop:
        raise ValueError('recording ends before the analysis window')
    def transfers(ident: int) -> list[int]:
        """Enumerate accepted pre-edge transactions, including adjacent-cycle transfers."""
        return [i for i, value in enumerate(dense(histories[device, ident], count)) if value == 3]
    requests, results = transfers(request['pop']), transfers(result['push'])
    if requests != transfers(request['push']) or results != transfers(result['pop']):
        raise ValueError('executor FIFO added buffering; adapt the phase model before attributing work')
    writes = sorted((s['cycle'], r['id'], s) for r in actors for s in histories[device, r['id']] if s['state_write'] and s['cycle'] < count)
    initialized = writes[:len(actors)]
    if {a for _, a, _ in initialized} != set(ids) or any(s['phase'] != 'configuring' for _, _, s in initialized):
        raise ValueError('expected one initialization write per actor')
    writes = writes[len(actors):]
    if not len(writes) <= len(results) <= len(requests) <= len(writes)+len(actors):
        raise ValueError('unmatched executor work exceeds the bounded capture tail')
    profile = {'schema': 1, 'unit': 'ns', 'tracks': [], 'events': [], 'edges': [], 'counters': [],
               'metadata': {'device': device, 'clock_period_ns': period, 'reset_release_ns': origin,
                            'checked_publication_cycles': publication_cycles,
                            'capture_cycles': count,
                            'dependency_scope': 'local actor/executor/outbox chains; incoming messages are not paired',
                            'trace_sha256': digest(trace), 'manifest_sha256': digest(stage/f'device{device}-manifest.json')}}
    events, edges = profile['events'], profile['edges']
    by_commit, previous = {}, {a: s for _, a, s in initialized}
    last_work, summaries = {}, defaultdict(list)
    last_diffusion = {}
    kinds, waits = Counter(), Counter()
    pairs = set()
    def edge(source: dict, target: dict, kind: str, evidence: str) -> None:
        """Connect two identified pieces of work, rejecting negative or duplicate causal steps."""
        if source['ts']+source['dur'] > target['ts']:
            raise ValueError(f'causal time inversion: {source["id"]} -> {target["id"]}')
        pair = source['id'], target['id']
        if pair not in pairs:
            edges.append({'source': pair[0], 'target': pair[1], 'kind': kind, 'evidence': evidence})
            pairs.add(pair)
    for resource in actors:
        slot = resource['slot']
        label = re.sub(r'^\{actor,\{family,([^,]+),(\[[^\]]+\])\}\}$', r'\1\2', resource['name'])
        for suffix in ('work', 'outbox', 'effect'):
            profile['tracks'].append({'id': f'{slot}/{suffix}', 'name': f'{label} / {suffix}', 'group': f'D{device} {resource["name"]}'})
        for sample in histories[device, resource['id']]:
            if start <= sample['time_ns'] < stop:
                for name, value in (('mailbox', sample['message_queue_len']), ('outbox reserved', int(sample['waiting_for_egress']))):
                    if value is not None:
                        profile['counters'].append({'track': f'{slot}/work', 'name': name, 'ts': sample['time_ns'], 'value': value})
    for index, ((cycle, actor, state), issued, returned) in enumerate(zip(writes, requests, results)):
        if returned-issued != 1 or cycle-returned != publication_cycles:
            raise ValueError('executor timing differs from the checked one-cycle execution and publication latency')
        resource, old = ids[actor], previous[actor]
        before, after = reduction(resource, old['value']), reduction(resource, state['value'])
        if before['failure'] or after['failure'] or (state['value'] >> 8) & 0xffff:
            raise ValueError('failed reduction in the healthy-workload profile')
        kind = classify(before, after, old['phase'], state['phase'])
        slot = resource['slot']
        event = {'id': f'D{device}/phi{slot}/{index}', 'track': f'{slot}/work', 'name': kind,
                 'ts': origin+issued*period, 'dur': (cycle-issued)*period,
                 'args': {'actor': resource['name'], 'slot': slot, 'module': module, 'phase_before': old['phase'], 'phase_after': state['phase'],
                          'reduction_before': before, 'reduction_after': after, 'request_cycle': issued,
                          'result_cycle': returned, 'committed_observation_cycle': cycle,
                          'evidence': 'FIFO-ordered executor handshakes matched to public state writes; execution and publication latencies checked for every retirement'}}
        events.append(event)
        by_commit[cycle] = event
        if actor in last_work:
            edge(last_work[actor], event, 'actor state', 'same actor; committed state feeds the next accepted request')
        if start <= state['time_ns'] < stop:
            kinds[(kind, old['phase'], before['site'])] += 1
            if actor in last_work:
                summaries['commit_interval_ns'].append(state['time_ns']-last_work[actor]['ts']-last_work[actor]['dur'])
            if before['status'] == 2:
                summaries['last_contribution_to_completion_commit_ns'].append(state['time_ns']-old['time_ns'])
            if kind == 'completion + entry' and before['site'] == 0:
                summaries['diffusion_last_contribution_to_completion_commit_ns'].append(state['time_ns']-old['time_ns'])
            if kind in ('completion + entry', 'aggregate completion + entry') and before['site'] == 0:
                prior = last_diffusion.get(actor)
                if prior and prior['args']['phase_after'] == 'gathering':
                    summaries['diffusion_round_commit_interval_ns'].append(event['ts']-prior['ts'])
        if kind in ('completion + entry', 'aggregate completion + entry') and before['site'] == 0:
            last_diffusion[actor] = event
        last_work[actor], previous[actor] = event, state
    for resource in actors:
        slot = resource['slot']
        parallel_name = f'{module}_ParallelActorOutboxDrainB{bank}S{slot}_0_next_inst/'
        channels = {r['name'].rsplit('/', 1)[-1]: r['id'] for r in resources.values()
                    if r['kind'] == 'channel' and parallel_name in r['name']}
        parallel = bool(channels)
        if not parallel:
            drains = [r for r in resources.values() if r['kind'] == 'channel' and f'{module}_ActorOutboxDrain' in r['name']]
            parents = sorted({r['name'].rsplit('/', 2)[0] for r in drains})
            parent = parents[ordinal] if len(requests_by_instance) > 1 else None
            channels = {r['name'].rsplit('/', 1)[-1]: r['id'] for r in drains
                        if f'{module}_ActorOutboxDrain_0__{slot}_next_inst/' in r['name']
                        and (parent is None or r['name'].rsplit('/', 2)[0] == parent)}
        work = [e for e in events if e['track'] == f'{slot}/work']
        work_times = [e['ts'] for e in work]
        commit_cycles = [e['args']['committed_observation_cycle'] for e in work]
        clears = [sample for sample in histories[device, resource['id']] if not sample['waiting_for_egress']]
        clear_cycles = [sample['cycle'] for sample in clears]
        batches, credits = (transfers(channels[name]) for name in ('_batches', '_credits'))
        effects = sorted((cycle, ident) for name, ident in channels.items()
                         if name == '_effects' or name.startswith('_fragment_') for cycle in transfers(ident))
        effect_tracks = {ident: (f'{slot}/effect' if name == '_effects' else f'{slot}/{name}/effect')
                         for name, ident in channels.items() if name == '_effects' or name.startswith('_fragment_')}
        base_track = next(t for t in profile['tracks'] if t['id'] == f'{slot}/effect')
        for name, ident in channels.items():
            if name.startswith('_fragment_'):
                profile['tracks'].append({**base_track, 'id': effect_tracks[ident],
                                          'name': base_track['name']+' / '+name.lstrip('_')})
        effect_port = dense(histories[device, channels['_effects']], count)
        credit_port = dense(histories[device, channels['_credits']], count)
        if not len(credits) <= len(batches) <= len(credits)+1:
            raise ValueError('outbox has more than one unfinished batch')
        used_effects = set()
        for index, (batch, credit) in enumerate(zip(batches, credits)):
            last_effect = (max((c for c, _ in effects if batch <= c <= credit), default=batch) if parallel
                           else final_effect(credit, effect_port, credit_port))
            members = [(c, port) for c, port in effects if batch <= c <= last_effect and (c, port) not in used_effects]
            used_effects.update(members)
            if index+1 < len(batches) and credit >= batches[index+1]:
                raise ValueError('outbox batches overlap')
            if not parallel and (not members or members[-1][0] != last_effect):
                raise ValueError('credited outbox has no newly accepted final effect')
            # In this checked schedule dispatch and slot FIFO each introduce one edge after retirement.
            producer = by_commit.get(batch)
            if inputs.get('reductions') == 'source_fragments':
                producer_index = bisect_right(commit_cycles, batch)-1
                producer = work[producer_index] if producer_index >= 0 else None
            if producer is None or producer['args']['slot'] != slot:
                raise ValueError('outbox batch cannot be identified from the corresponding state write')
            event = {'id': f'D{device}/outbox{slot}/{index}', 'track': f'{slot}/outbox', 'name': 'outbox reservation',
                     'ts': origin+batch*period, 'dur': (credit-batch)*period,
                     'args': {'effect_cycles': [c for c, _ in members], 'batch_cycle': batch, 'credit_cycle': credit,
                              'last_effect_cycle': last_effect, 'producer': producer['id'], 'count': len(members)}}
            events.append(event)
            edge(producer, event, 'effects', 'public per-slot batch acceptance follows the latest committed result; its actor remains reserved until the final credit')
            next_index = bisect_right(work_times, producer['ts'])
            if next_index < len(work) and work_times[next_index] < origin+credit*period:
                raise ValueError('actor issued another request before its outbox credit')
            next_index = bisect_left(work_times, origin+credit*period)
            successors = work[next_index:next_index+1]
            if successors:
                following = min(successors, key=lambda e: e['ts'])
                edge(event, following, 'outbox credit', 'the actor cannot issue another request until its batch credit returns; a final effect may still occupy the registered output')
            for position, (cycle, port) in enumerate(members):
                events.append({'id': f'{event["id"]}/effect{position}', 'track': effect_tracks[port], 'name': f'effect {position}',
                               'ts': origin+cycle*period, 'dur': 0, 'args': {'batch': event['id'], 'producer': producer['id'], 'actor': resource['name'],
                                                                                  'channel': port, 'position': position, 'parallel_publication': parallel, 'cycle': cycle}})
            history = histories[device, resource['id']]
            clear_index = bisect_right(clear_cycles, credit)
            release = clears[clear_index] if clear_index < len(clears) else None
            if start <= event['ts'] < stop:
                if release:
                    summaries['credit_to_observed_reservation_clear_ns'].append(release['time_ns']-(origin+credit*period))
                summaries['outbox_drain_ns'].append(event['dur'])
                summaries['last_effect_after_credit_ns'].append((last_effect-credit)*period)
                if producer['name'] in ('completion + entry', 'aggregate completion + entry') and producer['args']['reduction_before']['site'] == 0:
                    summaries['diffusion_outbox_drain_ns'].append(event['dur'])
                    summaries['diffusion_effect_span_ns'].append((members[-1][0]-members[0][0])*period)
                    if producer['name'] == 'completion + entry':
                        final_contribution = work[bisect_left(work_times, producer['ts'])-1]
                        if final_contribution['name'] != 'contribution' or final_contribution['args']['reduction_after']['status'] != 2:
                            raise ValueError('completion lacks its final contribution')
                        summaries['diffusion_last_contribution_to_last_effect_ns'].append(origin+last_effect*period-final_contribution['ts']-final_contribution['dur'])
                if successors:
                    summaries['credit_to_next_request_ns'].append(following['ts']-(origin+credit*period))
        tail_start = batches[-1] if len(batches) > len(credits) else count
        if any((c, p) not in used_effects and c < tail_start for c, p in effects):
            raise ValueError('accepted effect is outside any outbox batch')
        if tail_start < count:
            producer_index = bisect_right(commit_cycles, tail_start)-1
            if producer_index < 0:
                raise ValueError('unfinished outbox lacks its producing activation')
            producer = work[producer_index]
            batch_id = f'D{device}/outbox{slot}/{len(credits)}'
            members = [(c, p) for c, p in effects if c >= tail_start and (c, p) not in used_effects]
            events.append({'id': batch_id, 'track': f'{slot}/outbox', 'name': 'unfinished outbox reservation',
                'ts': origin+tail_start*period, 'dur': max(0, (count-1-tail_start)*period),
                'args': {'producer': producer['id'], 'batch_cycle': tail_start, 'effect_cycles': [c for c, _ in members],
                         'incomplete_at_capture_end': True}})
            edge(producer, events[-1], 'effects', 'accepted batch belongs to latest committed actor result; credit lies beyond capture')
            for position, (cycle, port) in enumerate(members):
                events.append({'id': f'{batch_id}/effect{position}', 'track': effect_tracks[port], 'name': f'effect {position}',
                    'ts': origin+cycle*period, 'dur': 0,
                    'args': {'batch': batch_id, 'producer': producer['id'], 'actor': resource['name'],
                             'channel': port, 'position': position, 'parallel_publication': parallel, 'cycle': cycle}})
        history = histories[device, resource['id']]
        for sample, following in zip(history, [*history[1:], {'time_ns': origin+count*period}]):
            duration = max(0, min(stop, following['time_ns'])-max(start, sample['time_ns']))
            if not duration:
                continue
            value = sample['value']
            category = ('in_flight' if sample['in_flight'] else 'outbox_reserved' if sample['waiting_for_egress'] else
                        'candidate_pending' if value & ((1 << 49) | (1 << 50)) or reduction(resource, value)['status'] == 2 else
                        'no_observed_candidate')
            waits[category] += duration
            if category == 'outbox_reserved' and value & ((1 << 49) | (1 << 50)):
                summaries['reserved_with_candidate_intervals_ns'].append(duration)
    report = {'device': device, 'bank': bank, 'slots': len(actors), 'window_ns': [start, stop], 'state_writes': len(writes),
              'executor_requests': len(requests), 'executor_results': len(results),
              'window_activations': [{'kind': k[0], 'phase_before': k[1], 'reduction_site': k[2], 'count': n} for k,n in sorted(kinds.items())],
              'durations_ns': {key: distribution(values) for key, values in summaries.items()},
              'observed_actor_time_ns': dict(waits),
              'reserved_with_candidate_ns': sum(summaries['reserved_with_candidate_intervals_ns']), 'scope': profile['metadata']['dependency_scope']}
    return profile, report


def main() -> None:
    """Export one recorded board through the public profiler; no hardware regeneration is needed."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--device', type=int, default=0)
    parser.add_argument('--profile-tools', type=Path, required=True, help='erl_hls tools directory')
    parser.add_argument('--trace', type=Path)
    parser.add_argument('--output', type=Path, help='output stem; preserve the original analysis when rereading a capture')
    parser.add_argument('--publication-cycles', type=int, default=1,
                        help='required result-to-state-write latency; reject any retirement that differs')
    args = parser.parse_args()
    sys.path.insert(0, str(args.profile_tools))
    import hls_profile
    trace = args.trace or extract(args.stage, args.device)
    if not hasattr(hls_profile, 'display_duration'):
        raise ValueError('use the common profiler with clock-width boundary support (erl_hls PR #165)')
    profile, report = reconstruct(args.stage, args.device, trace, publication_cycles=args.publication_cycles)
    from phi_profile_phases import extend as explain
    explain(profile, report, args.stage, args.device, trace)
    profile['metadata']['analysis_sha256'] = {Path(__file__).name: digest(Path(__file__)),
                                               'phi_reduction_profile.py': digest(Path(__file__).with_name('phi_reduction_profile.py')),
                                               'phi_profile_phases.py': digest(Path(__file__).with_name('phi_profile_phases.py')),
                                               'hls_profile.py': digest(Path(hls_profile.__file__))}
    hls_profile.validate(profile)
    stem = args.output or args.stage/f'actor{args.device}'
    stem.parent.mkdir(parents=True, exist_ok=True)
    stem.with_suffix('.profile.json').write_text(json.dumps(profile, separators=(',', ':'))+'\n')
    stem.with_suffix('.perfetto.json').write_text(json.dumps(hls_profile.perfetto(profile), separators=(',', ':'))+'\n')
    stem.with_suffix('.summary.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
