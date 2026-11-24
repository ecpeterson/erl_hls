"""Explain recorded actor progress with clock bins and independently checked handoff intervals."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import defaultdict
from pathlib import Path
import json

from phi_cycle_trace import executor_requests, read
from phi_transport_metrics import dense, distribution
from phi_reduction_profile import bindings


def handoffs(profile: dict, resources: dict, histories: dict, stage: Path, device: int) -> tuple[dict, dict]:
    """Pair mux inputs with scheduler captures and RAM reads using conserved FIFO order."""
    count = profile['metadata']['capture_cycles']
    actors = {r['name']: r for r in resources.values()
              if r['kind'] == 'actor' and r.get('module') == 'phi_halo_cell'}
    groups = defaultdict(list)

    def transfers(ident: int) -> list[int]:
        """Retain every accepted clock, including adjacent handshakes."""
        return [cycle for cycle, value in enumerate(dense(histories[device, ident], count)) if value == 3]

    for actor in bindings(stage, device)['actors']:
        name, index = actor['name'], actor['index']
        port, = [r for r in resources.values() if r['kind'] == 'channel'
                 and f'__ReductionCollector{index}_' in r['name'] and r['name'].endswith('/_aggregate')]
        queue, = [r for r in resources.values() if r['kind'] == 'fifo' and r['push'] == port['id']]
        emitted, popped = transfers(queue['push']), transfers(queue['pop'])
        if not len(popped) <= len(emitted) <= len(popped)+queue['capacity']:
            raise ValueError('aggregate input queue does not conserve frames')
        groups[actors[name]['bank']] += [(cycle, name, ordinal, emitted[ordinal])
                                        for ordinal, cycle in enumerate(popped)]
    requests = executor_requests(resources.values(), 'phi_halo_cell')
    if len(requests) != len(groups):
        raise ValueError('scheduler/aggregate bank population differs')
    captures, reads = {}, {}
    for (bank, popped), request in zip(sorted(groups.items()), requests):
        parent = request['owner']
        ports = {r['name'].rsplit('/', 1)[1]: r['id'] for r in resources.values()
                 if r['kind'] == 'channel' and r['name'].rsplit('/', 1)[0] == parent}
        captured = transfers(ports['_aggregate_in'])
        if '_ram_read_req_out' in ports:
            state_reads = transfers(ports['_ram_read_req_out'])
        else:
            # Bind the RAM owner inside this scheduler, then follow its ticket
            # input. Ticket staging may precede the loader; FIFO names are not roles.
            read_port, = [r for r in resources.values() if r['kind'] == 'channel'
                          and r['name'].startswith(parent+'/')
                          and r['name'].endswith('/_ram_read_req_out')]
            owner = read_port['name'].rsplit('/', 1)[0]
            ticket_input, = [r for r in resources.values() if r['kind'] == 'channel'
                             and r['name'] == owner+'/_tickets']
            ticket, = [r for r in resources.values() if r['kind'] == 'fifo'
                       and r['pop'] == ticket_input['id']]
            state_reads = transfers(read_port['id'])
            issued, loaded = transfers(ticket['push']), transfers(ticket['pop'])
            if not len(state_reads) <= len(loaded) <= len(state_reads)+1 or not len(loaded) <= len(issued) <= len(loaded)+ticket['capacity']:
                raise ValueError('loader ticket/RAM handoff does not conserve requests')
            if any(push > pop or pop > read for push, pop, read in zip(issued, loaded, state_reads)):
                raise ValueError('loader ticket/RAM handoff goes backwards')
        accepted = transfers(request['accept'])
        # The mux emits one ordered stream. A bounded capture tail can retain its last word.
        if not len(captured) <= len(popped) <= len(captured)+1:
            raise ValueError('aggregate mux does not conserve frames')
        popped.sort()
        if len({p[0] for p in popped}) != len(popped):
            raise ValueError('aggregate mux accepted several inputs on one clock')
        for (pop, actor, ordinal, emitted), capture in zip(popped, captured):
            if not emitted <= pop <= capture:
                raise ValueError('aggregate handoff goes backwards')
            captures[actor, ordinal] = (emitted, pop, capture)
        bank_actors = {name for name, r in actors.items() if r['bank'] == bank}
        work = sorted((e for e in profile['events'] if e['track'].endswith('/work')
                       and e['args']['actor'] in bank_actors), key=lambda e: e['ts'])
        # At capture end each actor may own one uncommitted request anywhere
        # between RAM issue and publication, regardless of the number of stages.
        if not len(work) <= len(accepted) <= len(state_reads) <= len(work)+len(bank_actors):
            raise ValueError('RAM/executor handoff has an unexplained capture tail')
        for event, cycle, accepted_cycle in zip(work, state_reads, accepted):
            if accepted_cycle != event['args']['request_cycle'] or cycle > accepted_cycle:
                raise ValueError('RAM read cannot be paired with its executor request')
            reads[event['id']] = cycle
    return captures, reads


def intervals(profile: dict, captures: dict, reads: dict, observations: dict | None = None) -> tuple[list[dict], dict]:
    """Partition completed actor windows into measured waits and service; leave unknown gaps explicit."""
    metadata = profile['metadata']
    period, origin = metadata['clock_period_ns'], metadata['reset_release_ns']
    source = {e['id']: e for e in profile['events']}
    incoming, outgoing = defaultdict(list), defaultdict(list)
    for edge in profile['edges']:
        incoming[edge['target']].append(source[edge['source']])
        outgoing[edge['source']].append(source[edge['target']])
    segments, samples = [], []
    observations = observations or {}

    def add(track: str, start: int, end: int, name: str, args: dict) -> None:
        """Keep positive observed intervals only; never manufacture a negative or zero-width wait."""
        if end < start:
            raise ValueError(f'negative progress interval: {name}')
        if end > start:
            segments.append({'id': f'{track}/progress/{len(segments)}', 'track': track+'/progress',
                             'ts': start, 'dur': end-start, 'name': name,
                             'category': ('wait' if name.startswith(('wait ', 'aggregate queued', 'scheduler pending', 'observed empty', 'collector inputs ready'))
                                          else 'unknown' if name in ('unattributed gap', 'mailbox handoff / unclassified')
                                          else 'service'), 'args': args})

    for event in profile['events']:
        if event['track'].endswith('/work'):
            args, start, end = event['args'], event['ts'], event['ts']+event['dur']
            result = origin+args['result_cycle']*period
            track = event['track'].removesuffix('/work')
            detail = {**args, 'work_id': event['id']}
            add(track, start, result, 'execute', detail)
            add(track, result, end, 'commit publication', detail)
        if not event['track'].endswith('/reduction'):
            continue
        args = event['args']
        track = event['track'].removesuffix('/reduction')
        ordinal = int(event['id'].split('/')[-2])
        emitted, popped, captured = captures[args['actor'], ordinal]
        previous = event
        for suffix in ('aggregate_select', 'aggregate_forward', 'aggregate_capture'):
            boundary, = outgoing[previous['id']]
            if not boundary['track'].endswith('/'+suffix):
                raise ValueError('aggregate progress lacks its identified handoff chain')
            previous = boundary
        finisher, = outgoing[previous['id']]
        if not finisher['track'].endswith('/work') or finisher['args']['actor'] != args['actor']:
            raise ValueError('aggregate handoff does not reach its owning actor')
        opening, = [e for e in incoming[event['id']] if e['track'].endswith('/opening')]
        opener, = incoming[opening['id']]
        state_read = reads[finisher['id']]
        if emitted != args['aggregate_cycle'] or captured > state_read:
            raise ValueError('aggregate or RAM identity differs from the completed window')
        start = opener['ts']+opener['dur']
        arrivals = [origin+c*period for c in args['fragment_arrivals']]
        opened = opening['ts']
        ready = max(start, opened, *arrivals)
        detail = {**args, 'opener': opener['id'], 'finisher': finisher['id'],
                  'aggregate_pop_cycle': popped, 'scheduler_capture_cycle': captured,
                  'state_read_cycle': state_read,
                  'last_fragments': [i for i, t in enumerate(arrivals) if t == max(arrivals)],
                  'evidence': 'Ordered per-actor queues, mux output, RAM and executor handshakes; no remote producer attribution'}
        boundaries = sorted({start, ready, *[t for t in [opened, *arrivals] if start < t < ready]})
        for a, b in zip(boundaries, boundaries[1:]):
            missing = [i for i, t in enumerate(arrivals) if t > a]
            name = 'wait fragments '+','.join(map(str, missing)) if missing else 'wait opening token'
            add(track, a, b, name, {**detail, 'missing_fragments': missing, 'opening_pending': opened > a})
        add(track, ready, event['ts'], 'collector inputs ready', detail)
        add(track, event['ts'], origin+emitted*period, 'collect / fold', detail)
        add(track, origin+emitted*period, origin+popped*period, 'aggregate queued for mux', detail)
        add(track, origin+popped*period, origin+captured*period, 'mux transfer', detail)
        add(track, origin+captured*period, origin+state_read*period, 'scheduler pending', detail)
        add(track, origin+state_read*period, finisher['ts'], 'state RAM read', detail)
        samples.append({'actor': args['actor'], 'site': args['site'], 'key': args['key'],
                        'request_ns': finisher['ts'], 'mux_queue_ns': (popped-emitted)*period,
                        'mux_transfer_ns': (captured-popped)*period,
                        'scheduler_pending_ns': (state_read-captured)*period,
                        'state_read_ns': finisher['ts']-origin-state_read*period})
    by_track = defaultdict(list)
    for event in segments:
        by_track[event['track']].append(event)
    for track, events in by_track.items():
        events.sort(key=lambda e: e['ts'])
        for previous, following in zip(events, events[1:]):
            end = previous['ts']+previous['dur']
            if end > following['ts']:
                raise ValueError('overlapping actor progress attribution')
            if end == following['ts']:
                continue
            base = track.removesuffix('/progress')
            work = source.get(following['args'].get('work_id'))
            actor = work['args']['actor'] if work else None
            read_at = origin+reads[work['id']]*period if work else following['ts']
            # The final ordinary activation has the same checked RAM/executor stream as reductions.
            if not end <= read_at <= following['ts']:
                raise ValueError('ordinary RAM read overlaps previous actor service')
            history = observations.get(actor, [])
            boundaries = sorted({end, read_at, *[s['time_ns'] for s in history if end < s['time_ns'] < read_at]})
            for a, b in zip(boundaries, boundaries[1:]):
                state = next((s for s in reversed(history) if s['time_ns'] <= a), None)
                if state is None:
                    name, detail = 'unattributed gap', {'evidence': 'No actor observation covers this interval'}
                else:
                    empty = state['message_queue_len'] == 0
                    name = 'observed empty mailbox' if empty else 'mailbox handoff / unclassified'
                    detail = {'actor': actor, 'phase': state['phase'], 'message_queue_len': state['message_queue_len'],
                              'outbox_reserved': state['waiting_for_egress'], 'observation_ns': state['time_ns'],
                              'evidence': 'Published actor projection, one clock after sampling; empty mailbox is not proof the input network is idle'}
                add(base, a, b, name, detail)
            if work:
                add(base, read_at, following['ts'], 'state RAM read', {'actor': actor, 'work_id': work['id'],
                    'evidence': 'FIFO-ordered RAM reads paired with executor request acceptance'})
    return segments, {'handoffs': samples}


def boundary_bins(profile: dict) -> None:
    """Draw accepted clock bins and label the latest required input at each local reduction join."""
    period = profile['metadata']['clock_period_ns']
    source = {e['id']: e for e in profile['events']}
    joins = defaultdict(list)
    for edge in profile['edges']:
        if source[edge['target']]['track'].endswith('/reduction'):
            joins[edge['target']].append(source[edge['source']])
    for inputs in joins.values():
        latest = max(e['ts']+e['dur'] for e in inputs)
        for event in inputs:
            if event['ts']+event['dur'] == latest:
                event['name'] += ' / last required'
                event.setdefault('args', {})['dependency_role'] = 'Latest required input at this local join; ties retained'
    for event in profile['events']:
        if event['dur'] == 0:
            event['display_duration_ns'] = period
            event['category'] = 'handshake'
            event.setdefault('args', {})['display_evidence'] = (
                'One observed clock bin, beginning at acceptance; not additional compute latency')


def extend(profile: dict, report: dict, stage: Path, device: int, trace: Path) -> None:
    """Add cycle-width boundary bins and local progress lanes without changing causal timestamps."""
    boundary_bins(profile)
    if json.loads((stage/'profile-inputs.json').read_text()).get('reductions') != 'source_fragments':
        return
    resources, histories = read(stage, {device}, trace)
    captures, reads = handoffs(profile, resources, histories, stage, device)
    observations = {r['name']: histories.get((device, r['id']), []) for r in resources.values() if r['kind'] == 'actor'}
    segments, details = intervals(profile, captures, reads, observations)
    tracks = []
    for track in profile['tracks']:
        if track['id'].endswith('/work'):
            tracks.append({**track, 'id': track['id'].removesuffix('/work')+'/progress',
                           'name': track['name'].removesuffix(' / work')+' / local progress'})
        tracks.append(track)
    profile['tracks'] = tracks
    profile['events'] += segments
    start, stop = report['window_ns']
    selected = [s for s in details['handoffs'] if start <= s['request_ns'] < stop]
    report['progress_handoffs'] = {'samples': len(selected), 'durations_ns': {
        key: distribution([s[key] for s in selected])
        for key in ('mux_queue_ns', 'mux_transfer_ns', 'scheduler_pending_ns', 'state_read_ns')}}
    report['progress_handoffs']['records'] = details['handoffs']
    profile['metadata']['progress_scope'] = (
        'Local progress partitions completed reduction windows. Wait spans are not compute occupancy; '
        'unattributed gaps remain explicit. Independent outbox drainage may overlap input waits. '
        'Clock-width boundary bins do not add causal work. Remote producers remain unpaired.')
