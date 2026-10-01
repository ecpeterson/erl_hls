"""Connect recorded fragment arrivals and complete aggregates to their owning actor windows."""
from collections import defaultdict
from collections.abc import Callable
from functools import cache
import json
from pathlib import Path
import re
import subprocess

from phi_transport_metrics import dense, distribution
from test_actor_rtl import digest


def bindings(stage: Path, device: int) -> dict:
    """Retain collector identities from checked scheduling metadata for portable Python-only replay."""
    saved = stage/f'device{device}-reduction-bindings.json'
    manifest = digest(stage/f'device{device}-manifest.json')
    if saved.exists():
        record = json.loads(saved.read_text())
        if record['manifest_sha256'] != manifest:
            raise ValueError('collector bindings belong to another recording')
        return record
    build = Path(json.loads((stage/'profile-inputs.json').read_text())['build'])
    source = build/f'source/phi_device_{device}_schedule.term'
    before = digest(source)
    expression = '''[File] = init:get_plain_arguments(),
      {ok, [{#{actors := Actors}, _}]} = file:consult(File),
      Bindings = [#{index => I, name => unicode:characters_to_binary(io_lib:format("~w", [{actor, maps:get(logical_identity, A, Id)}]))}
        || A = #{index := I, id := Id, module := phi_halo_cell} <- Actors],
      io:put_chars(json:encode(Bindings)), halt().'''
    result = subprocess.check_output(['erl', '+S', '2:2', '-noshell', '-eval', expression,
        '-extra', str(source)], text=True)
    if before != digest(source):
        raise ValueError('collector identity metadata changed during analysis')
    record = {'source_sha256': before, 'manifest_sha256': manifest, 'actors': json.loads(result)}
    saved.write_text(json.dumps(record, indent=2)+'\n')
    return record


def aggregate_handoffs(resources: dict, transfers: Callable[[int], list[int]]) -> dict:
    """Match collector outputs to mux selection, forwarding and scheduler capture by FIFO ordinals."""
    channels = {r['id']: r for r in resources.values() if r['kind'] == 'channel'}
    fifos = [r for r in resources.values() if r['kind'] == 'fifo']
    handoffs = {}
    for output in channels.values():
        if '_ReductionMux_' not in output['name'] or not output['name'].endswith('/_outgoing'):
            continue
        parent = output['name'].rsplit('/', 1)[0]
        inputs = [r for r in channels.values() if r['name'].rsplit('/', 1)[0] == parent
                  and r['name'].rsplit('/', 1)[1].startswith('_incoming__')]
        output_queue, = [q for q in fifos if q['push'] == output['id']]
        selected = sorted((cycle, r['id'], ordinal) for r in inputs
                          for ordinal, cycle in enumerate(transfers(r['id'])))
        if len({c for c, _, _ in selected}) != len(selected):
            raise ValueError('aggregate mux accepted multiple inputs in one clock')
        emitted, captured = transfers(output['id']), transfers(output_queue['pop'])
        if not len(captured) <= len(emitted) <= len(selected) <= len(emitted)+1:
            raise ValueError('aggregate mux transaction counts disagree')
        for (selection, channel, ordinal), forwarding, capture in zip(selected, emitted, captured):
            source_queue, = [q for q in fifos if q['pop'] == channel]
            enqueued = transfers(source_queue['push'])
            if ordinal >= len(enqueued) or not enqueued[ordinal] <= selection <= forwarding <= capture:
                raise ValueError('aggregate mux bypassed accepted FIFO order')
            key = source_queue['push'], ordinal
            if key in handoffs:
                raise ValueError('collector output has multiple aggregate routes')
            handoffs[key] = [(selection, channel), (forwarding, output['id']), (capture, output_queue['pop'])]
    return handoffs


def extend(profile: dict, report: dict, stage: Path, device: int,
           resources: dict, histories: dict) -> None:
    """Add only ordinally matched, fully observed reduction windows; reject ambiguous handoffs."""
    record = bindings(stage, device)
    metadata = profile['metadata']
    period, origin, count = (metadata[k] for k in ('clock_period_ns', 'reset_release_ns', 'capture_cycles'))
    start, stop = report['window_ns']
    summaries, completed = defaultdict(list), 0
    events, edges = profile['events'], profile['edges']
    owners = {r['name']: r for r in resources.values()
              if r['kind'] == 'actor' and r.get('module') == 'phi_halo_cell'}
    if set(owners) != {a['name'] for a in record['actors']}:
        raise ValueError('collector identities differ from the recorded actor catalog')

    @cache
    def transfers(ident: int) -> list[int]:
        """Count adjacent accepted transactions at a manifest-described boundary."""
        return [i for i, value in enumerate(dense(histories[device, ident], count)) if value == 3]

    def connect(source: dict, target: dict, kind: str, evidence: str) -> None:
        """Require every recorded causal edge to advance in time."""
        if source['ts']+source['dur'] > target['ts']:
            raise ValueError(f'reduction causal time inversion: {source["id"]} -> {target["id"]}')
        edges.append({'source': source['id'], 'target': target['id'], 'kind': kind, 'evidence': evidence})

    handoffs = aggregate_handoffs(resources, transfers)
    for actor in record['actors']:
        name, index = actor['name'], actor['index']
        ports = {r['name'].rsplit('/', 1)[1]: r['id'] for r in resources.values()
                 if r['kind'] == 'channel' and re.search(rf'__ReductionCollector{index}_\d+__\d+_next_inst/', r['name'])}
        frame_ports = sorted(key for key in ports if key.startswith('_frame_'))
        if set(ports) != {'_aggregate', '_opened', *frame_ports} or not frame_ports:
            raise ValueError(f'incomplete collector capture for {name}')
        emitted, opened = transfers(ports['_aggregate']), transfers(ports['_opened'])
        opening_queue, = [r for r in resources.values() if r['kind'] == 'fifo' and r['pop'] == ports['_opened']]
        announced = transfers(opening_queue['push'])
        arrivals, collected, fragment_queues = [], [], []
        for port in frame_ports:
            queue, = [r for r in resources.values() if r['kind'] == 'fifo' and r['pop'] == ports[port]]
            fragment_queues.append(queue)
            arrivals.append(transfers(queue['push']))
            collected.append(transfers(queue['pop']))
        work = [e for e in events if e['track'].endswith('/work') and e['args']['actor'] == name]
        openers = [e for e in work if e['args']['reduction_after']['status'] == 1 and
                   any(e['args']['reduction_before'][k] != e['args']['reduction_after'][k] for k in ('status', 'site', 'key'))]
        finishers = [e for e in work if e['name'].startswith('aggregate completion')]
        n = len(finishers)
        if not n <= len(emitted) <= len(opened) <= len(announced) <= len(openers) <= n+1 or any(len(v) < n for v in arrivals+collected):
            raise ValueError(f'reduction handoff counts disagree for {name}')
        track = work[0]['track'].removesuffix('/work')
        label = re.sub(r'^\{actor,\{family,([^,]+),(\[[^\]]+\])\}\}$', r'\1\2', name)
        for suffix in ('opening', 'reduction', 'aggregate_select', 'aggregate_forward', 'aggregate_capture', *(f'fragment{i}' for i in range(len(frame_ports)))):
            profile['tracks'].append({'id': f'{track}/{suffix}', 'name': f'{label} / {suffix}', 'group': f'D{device} {name}'})
        for position, queue in enumerate(fragment_queues):
            profile['counters'] += [{'track': f'{track}/fragment{position}',
                'name': f'FIFO depth / {queue["capacity"]}', 'ts': sample['time_ns'], 'value': sample['occupancy']}
                for sample in histories[device, queue['id']]]
        for ordinal, (opener, finisher) in enumerate(zip(openers, finishers)):
            opened_state, completed_state = opener['args']['reduction_after'], finisher['args']['reduction_before']
            if any(opened_state[k] != completed_state[k] for k in ('site', 'key')):
                raise ValueError('aggregate completion does not match its opening window')
            pushed = [v[ordinal] for v in arrivals]
            popped = [v[ordinal] for v in collected]
            opening, aggregate = opened[ordinal], emitted[ordinal]
            announcement = announced[ordinal]
            if announcement > opening:
                raise ValueError('opening token bypassed its bounded queue')
            barrier = max(opening, *popped)
            prefix = f'D{device}/collector{index}/{ordinal}'
            common = {'actor': name, 'site': opened_state['site'], 'key': opened_state['key'],
                      'fragment_arrivals': pushed, 'fragment_receives': popped,
                      'opening_arrival_cycle': announcement, 'opening_receive_cycle': opening, 'aggregate_cycle': aggregate}
            fold = {'id': prefix+'/fold', 'track': track+'/reduction', 'name': 'complete aggregate',
                    'ts': origin+barrier*period, 'dur': (aggregate-barrier)*period, 'args': common}
            opening_event = {'id': prefix+'/open', 'track': track+'/opening', 'name': 'opening token',
                             'ts': origin+announcement*period, 'dur': 0, 'args': common}
            events.extend([opening_event, fold])
            connect(opener, opening_event, 'window opening', 'committed actor opening matched to its next per-actor opening token')
            connect(opening_event, fold, 'opening fence', 'collector cannot emit before accepting this opening token')
            for position, (push, pop) in enumerate(zip(pushed, popped)):
                if push > pop or pop > aggregate:
                    raise ValueError('fragment bypassed its bounded queue')
                arrival = {'id': prefix+f'/fragment{position}', 'track': track+f'/fragment{position}', 'name': f'fragment {position}',
                           'ts': origin+push*period, 'dur': 0, 'args': {**common, 'position': position, 'receive_cycle': pop}}
                events.append(arrival)
                connect(arrival, fold, 'contribution', 'the nth frame of each proved ordered fragment belongs to the nth complete window')
            route = handoffs.get((ports['_aggregate'], ordinal))
            if route is None:
                raise ValueError('completed window lacks an observed aggregate route')
            prior = fold
            for (cycle, channel), suffix, label, kind in zip(route,
                    ('aggregate_select', 'aggregate_forward', 'aggregate_capture'),
                    ('mux selects aggregate', 'mux forwards aggregate', 'scheduler captures aggregate'),
                    ('aggregate queue', 'aggregate mux', 'aggregate capture')):
                boundary = {'id': prefix+'/'+suffix, 'track': track+'/'+suffix, 'name': label,
                            'ts': origin+cycle*period, 'dur': 0, 'args': {**common, 'channel': channel}}
                events.append(boundary)
                connect(prior, boundary, kind, 'per-actor FIFO ordinal and accepted mux order preserve this aggregate identity')
                prior = boundary
            connect(prior, finisher, 'aggregate', 'scheduler capture matched to the same committed actor site/key window')
            if start <= finisher['ts'] < stop:
                completed += 1
                for key, value in {
                    'fragment_arrival_span_ns': (max(pushed)-min(pushed))*period,
                    'last_fragment_to_aggregate_ns': (aggregate-max(pushed))*period,
                    'ready_inputs_to_aggregate_ns': (aggregate-barrier)*period,
                    'aggregate_to_executor_request_ns': finisher['ts']-(origin+aggregate*period),
                    'aggregate_queue_to_mux_ns': (route[0][0]-aggregate)*period,
                    'aggregate_mux_forward_ns': (route[1][0]-route[0][0])*period,
                    'aggregate_mux_to_scheduler_ns': (route[2][0]-route[1][0])*period,
                    'aggregate_scheduler_to_executor_ns': finisher['ts']-(origin+route[2][0]*period),
                    'last_fragment_to_commit_ns': finisher['ts']+finisher['dur']-(origin+max(pushed)*period),
                    'opening_commit_to_token_arrival_ns': origin+announcement*period-opener['ts']-opener['dur'],
                    'opening_token_wait_ns': (opening-announcement)*period,
                }.items():
                    summaries[key].append(value)
    report['reduction_handoffs'] = {'completed_windows': completed,
        'durations_ns': {key: distribution(values) for key, values in summaries.items()}}
    groups = {name: i for i, name in enumerate(dict.fromkeys(t['group'] for t in profile['tracks']))}
    order = {'work': 0, 'opening': 1, **{f'fragment{i}': 2+i for i in range(4)}, 'reduction': 6, 'aggregate_select': 7, 'aggregate_forward': 8, 'aggregate_capture': 9, 'outbox': 10, 'effect': 11}
    profile['tracks'].sort(key=lambda t: (groups[t['group']], order.get(t['id'].rsplit('/', 1)[1], 2)))
    metadata['reduction_bindings_sha256'] = digest(stage/f'device{device}-reduction-bindings.json')
    metadata['dependency_scope'] = 'local actor/fragment/aggregate/outbox chains; remote producers and ordinary-mail consumers are not paired'
    report['scope'] = metadata['dependency_scope']
