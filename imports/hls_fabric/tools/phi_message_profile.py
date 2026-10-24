#!/usr/bin/env python3
"""Connect reduction and ordinary messages across actor, transport and mailbox observations."""
from collections import defaultdict
import csv
import gzip
import json
from pathlib import Path
import re
import subprocess
import sys

from phi_actor_profile import reconstruct
from phi_cycle_trace import capture_path, trace_digest
from phi_reduction_profile import bindings as reduction_bindings
from phi_link_packet import packets
from backend_commands import digest
from backend_paths import erl_command


def routes(stage: Path, public: Path) -> dict:
    """Retain source ports and fragment multiplicities from the checked deployment."""
    expression = '''[Stage] = init:get_plain_arguments(),
    {ok,[P]} = file:consult(filename:join(Stage,"deployment.term")),
    Fmt = fun(T) -> iolist_to_binary(io_lib:format("~w",[T])) end,
    Actors = maps:get(actors,P), Index = maps:from_list([{maps:get(identity,A),A} || A <- Actors]),
    LA = [maps:merge(maps:with([index,device,module,outputs], A),
      #{name => Fmt({actor,maps:get(identity,A)}), fragments =>
        [maps:with([id,multiplicity],L) || L <- hls_partition_reduction:inputs(A,P)]}) || A <- Actors],
    LL = [begin #{source := Src, destination := Dest, ports := Ports} = L,
      #{outputs := Outputs} = maps:get(Src,Index),
      maps:merge(maps:with([id,rtl_id,wire_id,kind,source_device,destination_device],L),
        #{source => Fmt({actor,Src}),destination => Fmt(Dest),
          ports => [I || {I,V} <- lists:enumerate(0,Outputs), lists:member(V,Ports)]})
      end || L <- maps:get(lanes,P)],
    LI = [#{bindings => [maps:with([index,device,targets,point], A) || A <- maps:get(bindings,I)],
       targets => [#{id=>maps:get(id,T), selector=>maps:get(selector,T),
         encodings=>[#{op=>Op,words=>(lists:sum([hls_type:width(maps:get(type,F))||F<-Fields])+31) div 32}
                     || {_,Op,Fields} <- maps:get(encodings,T)]} || T <- maps:get(targets,I)]}
       || I <- maps:get(ingresses,P)],
    io:put_chars(json:encode(#{actors=>LA,lanes=>LL,ingresses=>LI})), halt().'''
    before = digest(stage/'deployment.term')
    result = json.loads(subprocess.check_output(erl_command(public, expression, stage, profile="test"), text=True))
    if before != digest(stage/'deployment.term'):
        raise ValueError('deployment changed during route binding')
    result['deployment_sha256'] = before
    (stage/'message-routes.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def split_cycles(stage: Path, devices: list[int]) -> None:
    """Split one full recording in a single pass, preserving each board's observation order."""
    source = capture_path(stage)
    record = stage/'message-cycle-extraction.json'
    paths = [stage/f'device{d}-trace.csv.gz' for d in devices]
    source_digest = trace_digest(source)
    if record.exists():
        expected = {'source_sha256': source_digest,
                    'traces': {str(d): digest(path) for d, path in zip(devices, paths)}}
        if json.loads(record.read_text()) != expected:
            raise ValueError('cached message cycle extraction changed')
        return
    if any(path.exists() for path in paths):
        raise ValueError('unverified per-device extraction; use a fresh analysis directory')
    outputs = {d: gzip.open(path, 'wt') for d, path in zip(devices, paths)}
    try:
        with (gzip.open(source,'rt') if source.suffix=='.gz' else source.open()) as incoming:
            header = next(incoming)
            for output in outputs.values():
                output.write(header)
            for line in incoming:
                outputs[int(line.split(',', 2)[1])].write(line)
    finally:
        for output in outputs.values():
            output.close()
    if trace_digest(source) != source_digest:
        raise ValueError('recording changed during message cycle extraction')
    record.write_text(json.dumps({'source_sha256': source_digest,
        'traces': {str(d): digest(path) for d, path in zip(devices, paths)}}, indent=2)+'\n')


def payloads(stage: Path) -> tuple[dict, dict]:
    """Read every accepted payload, retaining duplicate words and rejecting mixed reset epochs."""
    bindings = json.loads((stage/'message-bindings.json').read_text())
    channels = {(b['device'], b['id']): b for b in bindings['channels']}
    result = defaultdict(list)
    with (stage/'message-trace.csv').open() as source:
        for row in csv.DictReader(source):
            device, ident, epoch, time = [int(row[k]) for k in ('device', 'id', 'epoch', 'time_ns')]
            if epoch != 0:
                raise ValueError('actor-window reconstruction currently requires one reset epoch')
            channel = channels[device, ident]
            value, mask = int(row['value'], 16), int(channel['known_mask'], 16)
            if value >> channel['width'] or value & ~mask:
                raise ValueError('accepted payload exceeds its retained known bits')
            previous = result[device, ident]
            if previous and previous[-1]['ts'] >= time:
                raise ValueError('nonmonotonic or duplicate channel acceptance')
            previous.append({'ts': time, 'value': value, 'mask': mask})
    return channels, dict(result)


def same_payload(left: dict, right: dict) -> None:
    """Check shared known bits; transaction identity must already follow an ordered lane."""
    if (left['value'] ^ right['value']) & left['mask'] & right['mask']:
        raise ValueError(f'ordered payload mismatch: {left} != {right}')


def packet_frame(packet: dict) -> dict:
    """Reconstruct a complete full-format frame, including padding, from its accepted wire words."""
    if packet['credit'] or packet['compact'] or not packet['complete'] or len(packet['words']) != 5:
        raise ValueError('message reconstruction requires complete full-format data packets')
    words = [word & 0xffffffff for word in packet['words'][1:]]
    header = int.from_bytes(words[0].to_bytes(4, 'little'), 'big')
    return {'value': (header << 96) | sum(word << (32*i) for i, word in enumerate(words[1:])),
            'mask': (1 << 128)-1, 'ts': packet['end_ns']}



def observed_effect(item: dict, accepted: dict, device: int, capture_end: int) -> dict | None:
    """Require a payload for each effect, except an explicitly unobserved final simulation edge."""
    key = device, item['args']['channel'], item['ts']
    payload = accepted.get(key)
    if payload is None and item['ts'] != capture_end:
        raise ValueError(f'effect handshake/payload observations disagree: {key}: {item["id"]}')
    return payload


def analyze(stage: Path, public: Path, profile_tools: Path) -> tuple[dict, dict]:
    """Build a checked message graph with explicit external roots and capture frontiers."""
    sys.path.insert(0, str(profile_tools))
    import hls_profile
    inputs = json.loads((stage/'profile-inputs.json').read_text())
    if inputs['reductions'] != 'source_fragments':
        raise ValueError('message correlation requires the fixed source-fragment proof')
    devices = list(range(len(inputs['device_periods_ns'])))
    split_cycles(stage, devices)
    route = routes(stage, public)
    channels, messages = payloads(stage)
    graph = {'schema': 1, 'unit': 'ns', 'tracks': [], 'events': [], 'edges': [], 'counters': [],
             'resource_dependencies': [], 'metadata': {}}
    origins = {}
    cache = stage/'message-actors.json.gz'
    for device in devices:
        reduction_bindings(stage, device)
    provenance = {str(path): digest(path) for path in [
        Path(__file__).with_name('phi_actor_profile.py'), Path(__file__).with_name('phi_reduction_profile.py'),
        Path(__file__).with_name('phi_cycle_trace.py'), Path(__file__).with_name('phi_transport_metrics.py'),
        stage/'profile-inputs.json', stage/'service.json', stage/'activity.log',
        *[stage/f'device{d}-manifest.json' for d in devices],
        *[stage/f'device{d}-reduction-bindings.json' for d in devices], *[stage/f'device{d}-trace.csv.gz' for d in devices]]}
    cached = json.loads(gzip.decompress(cache.read_bytes())) if cache.exists() else None
    if cached is not None and cached['provenance'] == provenance:
        graph, origins = cached['graph'], {int(d): value for d, value in cached['origins'].items()}
        pending_devices = []
    else:
        pending_devices = devices
    for device in pending_devices:
        print(f'Replaying actor observations: device {device}', file=sys.stderr, flush=True)
        profile, _ = reconstruct(stage, device, stage/f'device{device}-trace.csv.gz', all_actors=True)
        origins[device] = profile['metadata']['reset_release_ns']
        # Event IDs already include device identity; local tracks do not.
        for track in profile['tracks']:
            track['id'] = f'D{device}/'+track['id']
        for event in profile['events']:
            event['track'] = f'D{device}/'+event['track']
            if event['dur'] == 0:
                event['display_duration_ns'] = inputs['device_periods_ns'][device]
        for counter in profile['counters']:
            counter['track'] = f'D{device}/'+counter['track']
        for edge in profile['edges']:
            if edge['kind'] == 'outbox credit':
                graph['resource_dependencies'].append({**edge, 'resource': 'actor outbox reservation'})
            else:
                graph['edges'].append(edge)
        for key in ('tracks', 'events', 'counters'):
            graph[key] += profile[key]
    if pending_devices:
        temporary = cache.with_suffix('.tmp')
        with gzip.open(temporary, 'wt', compresslevel=1) as output:
            json.dump({'graph': graph, 'origins': origins, 'provenance': provenance}, output, separators=(',', ':'))
        temporary.replace(cache)
    capture_end = max(int(line.split()[0]) for line in (stage/'activity.log').read_text().splitlines())
    by_id = {e['id']: e for e in graph['events']}
    tracks = {t['id'] for t in graph['tracks']}
    report = {'matched_reduction_deliveries': 0, 'remote_reduction_deliveries': 0,
              'unconnected_effects': 0, 'unobserved_final_edge_effects': 0}

    def edge(source: dict, target: dict, kind: str, evidence: str) -> None:
        """Connect actual prerequisites; source completion cannot follow consumer readiness."""
        if source['ts']+source['dur'] > target['ts']:
            raise ValueError(f'message dependency time inversion: {source["id"]} -> {target["id"]}')
        graph['edges'].append({'source': source['id'], 'target': target['id'], 'kind': kind, 'evidence': evidence})

    def event(ident: str, track: str, name: str, ts: int, device: int, args: dict, dur: int = 0) -> dict:
        """Publish one transfer boundary or measured packet span, retaining its independent identity."""
        if track not in tracks:
            graph['tracks'].append({'id': track, 'name': track, 'group': f'D{device} message transport'})
            tracks.add(track)
        result = {'id': ident, 'track': track, 'name': name, 'ts': ts, 'dur': dur,
                  'category': 'handshake' if dur == 0 else 'service', 'args': args}
        if not dur:
            result['display_duration_ns'] = inputs['device_periods_ns'][device]
        graph['events'].append(result)
        by_id[ident] = result
        return result

    # An effect's ordinal survives independently of its payload value. Only
    # fully observed source ports can select a lane; do not guess optimized bits.
    effects = defaultdict(list)
    seen_effects = set()
    accepted = {(d, c, p['ts']): p for (d, c), values in messages.items() for p in values}
    routes_by_port = defaultdict(list)
    for lane in route['lanes']:
        for port in lane['ports']:
            routes_by_port[lane['source'], port].append(lane)
    for item in list(graph['events']):
        if not item['track'].endswith('/effect'):
            continue
        device = int(item['track'].split('/')[0][1:])
        args = item['args']
        seen_effects.add((device, args['channel'], item['ts']))
        payload = observed_effect(item, accepted, device, capture_end)
        if payload is None:
            item['args']['payload_unobserved_at_capture_end'] = True
            report['unobserved_final_edge_effects'] += 1
            continue
        item['display_duration_ns'] = inputs['device_periods_ns'][device]
        edge(by_id[args['producer']], item, 'produces effect', 'retired actor result owns this independently drained effect ordinal')
        item['args'].update(payload=hex(payload['value']), known_mask=hex(payload['mask']))
        if (payload['mask'] >> 128) & 255 != 255:
            report['unconnected_effects'] += 1
            continue
        port = payload['value'] >> 128
        for lane in routes_by_port[args['actor'], port]:
            effects[lane['id']].append((item, {**payload, 'value': payload['value'] & ((1 << 128)-1), 'mask': payload['mask'] & ((1 << 128)-1)}))
    frontier={(d,c,p['ts']) for (d,c),values in messages.items() if channels[d,c]['role']=='effect' for p in values}-seen_effects
    if any(ts<capture_end-inputs['device_periods_ns'][d] for d,c,ts in frontier):
        raise ValueError('source effect lacks an activation away from the capture frontier')
    report['source_effect_tail']=len(frontier)
    report['unpaired_source_frontier']=[{'device':d,'channel':c,'time_ns':ts} for d,c,ts in sorted(frontier)]
    for lane in effects.values():
        lane.sort(key=lambda pair: pair[0]['ts'])

    topology = json.loads((stage/'bridge.json').read_text())['devices']
    tx = packets(stage/'traffic.log', inputs['transport'])
    rx = packets(stage/'received-traffic.log', inputs['transport'])
    wire_lanes = defaultdict(list)
    for device in topology:
        d = device['id']
        for link in device['links']:
            port, peer = link['index'], link['peer']
            reverse, = [r['index'] for r in topology[peer]['links'] if r['peer'] == d]
            sent, received = tx.get((d, port), []), rx.get((peer, reverse), [])
            if len(received) > len(sent):
                raise ValueError('receiver has more packets than its sender')
            for ordinal, (a, b) in enumerate(zip(sent, received)):
                if b['words'] != a['words'][:len(b['words'])] or b['start_ns'] < a['start_ns']:
                    raise ValueError('wire packet changed identity or order')
                if a['credit'] or not b['complete']:
                    continue
                wire_lanes[d, peer, a['lane']].append((ordinal, a, b))

    # Each reduction position is assigned by the compiler's source-fragment
    # proof. Aliased ports occupy consecutive positions on their shared lane.
    for actor in route['actors']:
        d, position = actor['device'], 0
        for fragment in actor['fragments']:
            lane, = [l for l in route['lanes'] if l['id'] == fragment['id']]
            producers = effects[lane['id']]
            multiplicity = fragment['multiplicity']
            for offset in range(multiplicity):
                channel, = [b for b in channels.values() if b['device'] == d and b['role'] == 'fragment'
                    and re.search(rf'__ReductionCollector{actor["index"]}_', b['channel'])
                    and b['channel'].endswith(f'/_frame_{position}')]
                received = messages.get((d, channel['id']), [])
                for window, payload in enumerate(received):
                    ident = f'D{d}/collector{actor["index"]}/{window}/fragment{position}'
                    target = by_id.get(ident)
                    if target is None:
                        continue  # An incomplete final window has no claimed consumer yet.
                    expected_time = origins[d]+target['args']['receive_cycle']*inputs['device_periods_ns'][d]
                    if payload['ts'] != expected_time:
                        raise ValueError('collector value/handshake ordinals disagree')
                    ordinal = window*multiplicity+offset
                    if ordinal >= len(producers):
                        raise ValueError('completed collector lacks a recorded producer effect')
                    source, value = producers[ordinal]
                    same_payload(value, payload)
                    previous = source
                    if lane['kind'] == 'remote':
                        sd = lane['source_device']
                        sequence, sent, landed = wire_lanes[sd, d, lane['wire_id']][ordinal]
                        same_payload(value, packet_frame(sent))
                        same_payload(payload, packet_frame(landed))
                        port, = [link['index'] for link in topology[sd]['links'] if link['peer'] == d]
                        reverse, = [link['index'] for link in topology[d]['links'] if link['peer'] == sd]
                        outgoing, = [b for b in channels.values() if b['device'] == sd and
                            b['role'].startswith('pop ') and b['role'].endswith(f'fifo__outgoing_{port}__{lane["wire_id"]}_')]
                        incoming, = [b for b in channels.values() if b['device'] == d and
                            b['role'].startswith('push ') and b['role'].endswith(f'fifo__received_{reverse}__{lane["wire_id"]}_')]
                        capture = messages[sd, outgoing['id']][ordinal]
                        delivery = messages[d, incoming['id']][ordinal]
                        same_payload(value, capture)
                        same_payload(payload, delivery)
                        common = {'lane': lane['id'], 'wire_lane': lane['wire_id'], 'ordinal': ordinal,
                                  'producer_effect': source['id'], 'destination_actor': actor['name']}
                        stem = f'lane{lane["id"]}/{ordinal}'
                        admitted = event(stem+'/capture', f'D{sd}/to{d}/lane{lane["wire_id"]}/capture', 'packetizer accepts frame',
                            capture['ts'], sd, common)
                        delivered = event(stem+'/delivery', f'D{d}/from{sd}/lane{lane["wire_id"]}/delivery', 'receive queue accepts frame',
                            delivery['ts'], d, common)
                        transmit = event(stem+'/tx', f'D{sd}/to{d}/lane{lane["wire_id"]}/tx', 'transmit frame',
                            sent['start_ns'], sd, common, sent['end_ns']-sent['start_ns'])
                        receive = event(stem+'/rx', f'D{d}/from{sd}/lane{lane["wire_id"]}/rx', 'received complete frame',
                            landed['end_ns'], d, common)
                        edge(source, admitted, 'ordered lane', 'source port and per-lane FIFO ordinal; accepted frame payload checked on every known bit')
                        edge(admitted, transmit, 'packetization', 'accepted frame and data packet share their per-lane ordinal and checked payload')
                        edge(transmit, receive, 'wire delivery', 'directed peer stream preserves exact packet words and packet ordinal')
                        edge(receive, delivered, 'receive admission', 'complete wire packet and accepted received frame share their lane ordinal and payload')
                        previous = delivered
                        report['remote_reduction_deliveries'] += 1
                    edge(previous, target, 'reduction fragment', 'proved source lane, split multiplicity and window ordinal; captured collector payload agrees')
                    report['matched_reduction_deliveries'] += 1
                position += 1
    print('Replaying ordinary mailbox identities', file=sys.stderr, flush=True)
    from phi_mailbox_profile import extend
    report['ordinary_mailboxes'] = extend(graph, stage, route, channels, messages)
    graph['metadata'] = {'dependency_scope': 'observed reduction and ordinary message ancestry; external host/startup roots and capture frontier remain explicit',
        'message_bindings_sha256': digest(stage/'message-bindings.json'), 'message_trace_sha256': digest(stage/'message-trace.csv'),
        'deployment_sha256': route['deployment_sha256'], 'capture_end_ns': capture_end, 'report': report,
        'actor_provenance': provenance, 'analysis_sha256': {str(path): digest(path) for path in
            [Path(__file__), Path(hls_profile.__file__), *[Path(__file__).with_name(f'phi_mailbox_{name}.py') for name in ('model','profile','routes')]]}}
    hls_profile.validate(graph)
    return graph, report


def main() -> None:
    """Write reproducible causal and Perfetto profiles without rerunning hardware synthesis."""
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--erl-hls', type=Path, required=True)
    parser.add_argument('--profile-tools', type=Path, required=True)
    args = parser.parse_args()
    graph, report = analyze(args.stage.resolve(), args.erl_hls.resolve(), args.profile_tools.resolve())
    import hls_profile
    for suffix in ('profile.json','perfetto.json','summary.json'):
        value=hls_profile.perfetto(graph) if suffix=='perfetto.json' else graph if suffix=='profile.json' else report
        with gzip.open(args.stage/f'messages.{suffix}.gz', 'wt', compresslevel=1) as output:
            json.dump(value, output, separators=(',', ':'))
        del value
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
