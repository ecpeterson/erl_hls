"""Measure opaque packed traffic and wire-visible credit ownership without reconstructing DUT internals."""
from collections import Counter, defaultdict, deque
import json
from pathlib import Path
import re

from phi_link_packet import packets
from phi_transport_metrics import dense, distribution
from phi_cycle_trace import read


def ledger(outgoing: list[dict], incoming: list[dict], lanes: int, credits: int,
           start: int, stop: int) -> dict:
    """Bound outstanding wire frames per lane and time each header-to-return round trip."""
    pending = [deque() for _ in range(lanes)]
    maxima, area, previous = [0]*lanes, [0]*lanes, [start]*lanes
    rtt, samples, counts = [], [], [0]*lanes
    events = [(p['start_ns'], 1, p) for p in outgoing if not p['credit']]
    events += [(p['end_ns'], 0, p) for p in incoming if p['credit'] and p['complete']]
    for time, action, packet in sorted(events, key=lambda event: event[:2]):
        lane = packet['lane']
        if lane >= lanes:
            raise ValueError('wire lane exceeds deployment')
        until = max(start, min(stop, time))
        if until > previous[lane]:
            maxima[lane] = max(maxima[lane], len(pending[lane]))
        area[lane] += len(pending[lane])*(until-previous[lane])
        previous[lane] = until
        if action:
            pending[lane].append(time)
            if len(pending[lane]) > credits:
                raise ValueError('wire sender exceeded its independently reserved window')
            if start <= time < stop:
                maxima[lane] = max(maxima[lane], len(pending[lane]))
                counts[lane] += 1
        else:
            if not pending[lane]:
                raise ValueError('wire credit without an outstanding frame')
            sent = pending[lane].popleft()
            if start <= sent < stop:
                rtt.append(time-sent)
        if start <= time < stop:
            samples.append([time, lane, len(pending[lane])])
    for lane in range(lanes):
        if stop > previous[lane]:
            maxima[lane] = max(maxima[lane], len(pending[lane]))
        area[lane] += len(pending[lane])*(stop-previous[lane])
    return {'roundtrip_ns': distribution(rtt),
            'lanes': [{'lane': lane, 'frames': counts[lane], 'max_outstanding': maxima[lane],
                       'mean_outstanding': area[lane]/(stop-start), 'tail_outstanding': len(pending[lane])}
                      for lane in range(lanes)], 'outstanding_events': samples}


def source_waits(stage: Path, devices: list[dict], tx: dict, start: int, stop: int) -> dict:
    """Track captured frames until their wire header and count idle edges with visible source work."""
    plans, selected = {}, set()
    for device in devices:
        d = device['id']
        resources = json.loads((stage/f'device{d}-manifest.json').read_text())['resources']
        for link in device['links']:
            i = link['index']
            frames = {int(m[1]): r['pop'] for r in resources if r['kind'] == 'fifo'
                      and (m := re.search(rf'fifo__outgoing_{i}__(\d+)_$', r['name']))}
            wire, = [r['id'] for r in resources if r['kind'] == 'channel' and r['name'] == f'_link_{i}_out']
            if sorted(frames) != list(range(link['tx_lanes'])):
                raise ValueError('frame-capture lanes differ from deployment')
            plans[d, i] = ([frames[lane] for lane in sorted(frames)], wire)
            selected.update((d, ident) for ident in [*frames.values(), wire])
    _, histories = read(stage, kinds={'C'}, selected=selected)
    periods = json.loads((stage/'profile-inputs.json').read_text())['device_periods_ns']
    result = {}
    for (d, i), (frames, wire) in plans.items():
        period, initial = periods[d], histories[d, wire][0]['time_ns']
        # Read through the last recorded header so completed waits are uncensored.
        end = max([stop, *[p['start_ns']+period for p in tx.get((d, i), [])]])
        count = (end-initial+period-1)//period
        values = {ident: dense(histories[d, ident], count) for ident in [*frames, wire]}
        headers = defaultdict(list)
        for packet in tx.get((d, i), []):
            if not packet['credit']:
                cycle, remainder = divmod(packet['start_ns']-initial, period)
                if remainder or cycle < 0:
                    raise ValueError('wire header is not on the observed device edge')
                headers[cycle].append(packet['lane'])
        pending = [deque() for _ in frames]
        totals, waits = Counter(), []
        for cycle in range(count):
            time = initial+cycle*period
            states = [values[ident][cycle] for ident in frames]
            for lane, state in enumerate(states):
                if state == 3:
                    pending[lane].append(time)
            for lane in headers[cycle]:
                if not pending[lane]:
                    raise ValueError('wire header without a captured frame')
                arrival = pending[lane].popleft()
                if start <= arrival < stop:
                    waits.append(time-arrival)
            if start <= time < stop:
                wire_state = values[wire][cycle]
                if wire_state == 3:
                    totals['accepted'] += 1
                elif wire_state == 1:
                    totals['blocked'] += 1
                elif any(pending):
                    totals['idle_with_captured_frame'] += 1
                elif any(state & 1 for state in states):
                    totals['idle_with_offered_frame'] += 1
                else:
                    totals['idle_without_visible_frame'] += 1
        result[d, i] = {'wire_cycles': dict(totals), 'capture_to_wire_header_ns': distribution(waits)}
    return result


def analyze(stage: Path) -> dict:
    """Verify end-to-end packet conservation and report actual receive-side credit arrival times."""
    inputs = json.loads((stage/'profile-inputs.json').read_text())
    transport = inputs['transport']
    devices = json.loads((stage/'bridge.json').read_text())['devices']
    start, stop = json.loads((stage/'service.json').read_text())['window_ns']
    tx = packets(stage/'traffic.log', transport)
    rx = packets(stage/'received-traffic.log', transport)
    by_id = {d['id']: d for d in devices}
    waits = source_waits(stage, devices, tx, start, stop)
    result = []
    for device in devices:
        d = device['id']
        for link in device['links']:
            i, peer = link['index'], link['peer']
            reverse, = [p['index'] for p in by_id[peer]['links'] if p['peer'] == d]
            source, destination = tx.get((d, i), []), rx.get((peer, reverse), [])
            if len(destination) > len(source):
                raise ValueError('received packet without an offered peer packet')
            latency = []
            for sent, received in zip(source, destination):
                if received['words'] != sent['words'][:len(received['words'])] or received['start_ns'] < sent['start_ns']:
                    raise ValueError('physical crossing changed packet order, contents or causality')
                if received['complete'] and not sent['complete']:
                    raise ValueError('receiver completed an unfinished sender packet')
                if received['complete'] and start <= sent['start_ns'] < stop:
                    latency.append(received['end_ns']-sent['start_ns'])
            stats = ledger(source, rx.get((d, i), []), link['tx_lanes'], transport['credits'], start, stop)
            result.append({'device': d, 'link': i, 'peer': peer, **stats, 'source': waits[d, i],
                           'header_to_peer_complete_ns': distribution(latency),
                           'sent_packets': len(source), 'received_packets': len(destination)})
    report = {'scope': 'Accepted public wire transfers. Outstanding begins at a data header and ends at its reverse credit arriving at the sender; staged unsent frames and receiver/packetizer latency after that credit are excluded. Source waits separately pair public frame-input acceptances with wire headers. Idle categories show observed work, not inferred arbiter or credit causes.',
              'window_ns': [start, stop], 'transport': transport, 'links': result}
    (stage/'packed-transport.json').write_text(json.dumps(report, indent=2)+'\n')
    return report
