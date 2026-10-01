"""Decode link traffic and time-weighted debug projections in the same status window."""
from collections import Counter
from bisect import bisect_right
import json
from pathlib import Path

from phi_cycle_trace import read
from phi_service_metrics import cycles, PORTS


def traffic(stage: Path, start: int, stop: int) -> list[dict]:
    """Classify each accepted wire word; count packet names at their frame-header edge."""
    catalog = {(r['device'], r['lane']): r for r in json.loads((stage / 'lane-catalog.json').read_text())}
    words = [Counter(), Counter()]
    messages = [Counter(), Counter()]
    lanes = [Counter(), Counter()]
    packets: list[list[int]] = [[], []]
    for line in (stage / 'traffic.log').read_text().splitlines():
        timestamp, device, raw = line.split()
        time, d, beat = int(timestamp), int(device), int(raw, 16)
        value, last = beat & 0xffffffff, bool(beat >> 32)
        packet = packets[d]
        if not packet:
            lane, credit = value & 0x7fff, bool(value & 0x8000)
            if value >> 16 != 0x4850 or credit != last or (d, lane) not in catalog:
                raise ValueError('invalid link header')
            kind = 'credit' if credit else 'lane_header'
            if not credit:
                packet.append(value)
        else:
            index = len(packet)
            if last != (index == 4):
                raise ValueError('invalid link TLAST')
            if index == 1:
                schemas = catalog[d, packet[0] & 0x7fff]['schemas']
                schema, = [s for s in schemas if s['tag'] == value >> 24]
                if value & 255 != (schema['bits']+31)//32 or value & 0x00ffff00:
                    raise ValueError('unexpected application frame header')
                kind = 'frame_header'
                if start <= time < stop:
                    messages[d][schema['name']] += 1
                    lanes[d][packet[0] & 0x7fff] += 1
            else:
                kind = 'payload' if index-1 <= (packet[1] & 255) else 'padding'
                if kind == 'padding' and value:
                    raise ValueError('nonzero padding word')
            packet.append(value)
            if last:
                packet.clear()
        if start <= time < stop:
            words[d][kind] += 1
    return [{'device': d, 'words': dict(words[d]), 'frames': dict(messages[d]),
             'lanes': [{**catalog[d, lane], 'frames': count} for lane, count in sorted(lanes[d].items())]}
            for d in (0, 1)]


def occupancy(stage: Path, start: int, stop: int) -> list[dict]:
    """Weight published state by device clock edges; actor values describe committed metadata."""
    resources, histories = read(stage, kinds={"S", "M", "F"})
    periods = json.loads((stage / 'profile-inputs.json').read_text())['device_periods_ns']
    result = []
    for (device, ident), resource in resources.items():
        if resource['kind'] not in ('actor', 'fifo'):
            continue
        history = histories.get((device, ident), [])
        if not history or history[0]['time_ns'] > start:
            raise ValueError(f'missing initial observation D{device} resource {ident}')
        total = Counter()
        maximum = 0
        for sample, following in zip(history, [*history[1:], {'time_ns': stop}]):
            n = cycles(start, stop, sample['time_ns'], following['time_ns'], periods[device])
            if not n:
                continue
            total['cycles'] += n
            if resource['kind'] == 'fifo':
                depth, capacity = sample['occupancy'], resource['capacity']
            else:
                depth, capacity = sample['message_queue_len'], resource['mailbox_capacity']
                if depth is None:
                    raise ValueError('uninitialized actor mailbox in measurement window')
                total['egress_wait_cycles'] += n*sample['waiting_for_egress']
                total['in_flight_cycles'] += n*sample['in_flight']
            maximum = max(maximum, depth)
            total['depth_cycles'] += n*depth
            total['full_cycles'] += n*(depth == capacity)
        observation = {'device': device, 'id': ident, 'kind': resource['kind'], 'name': resource['name'],
            'capacity': capacity, 'max_depth': maximum, 'mean_depth': total['depth_cycles']/total['cycles'],
            'full_fraction': total['full_cycles']/total['cycles']}
        if resource['kind'] == 'actor':
            observation.update(egress_wait_fraction=total['egress_wait_cycles']/total['cycles'],
                in_flight_fraction=total['in_flight_cycles']/total['cycles'],
                state_writes=sum(start <= s['time_ns'] < stop and s['state_write'] for s in history))
        result.append(observation)
    return result


def idle_returns(stage: Path, start: int, stop: int) -> list[dict]:
    """Count ready-but-idle link cycles with at least one credit return awaiting transmission."""
    resources, histories = read(stage, kinds={"S", "M", "F"})
    periods = json.loads((stage / 'profile-inputs.json').read_text())['device_periods_ns']
    activity: list[list[tuple[int, int]]] = [[], []]
    for line in (stage / 'activity.log').read_text().splitlines():
        time, device, _, bits = line.split()
        activity[int(device)].append((int(time), int(bits, 16)))
    result = []
    for device, period in enumerate(periods):
        changes = activity[device]
        times = [t for t, _ in changes]
        queues = [histories[key] for key, resource in resources.items()
                  if key[0] == device and resource['kind'] == 'fifo'
                  and 'fifo__link_returned__' in resource['name']]
        queue_times = [[s['time_ns'] for s in queue] for queue in queues]
        if not times or any(not ts or ts[0] > start for ts in [times, *queue_times]):
            raise ValueError('missing initial return/port observation')
        first = times[0]+max(0, (start-times[0]+period-1)//period)*period
        idle = pending = 0
        for time in range(first, stop, period):
            bits = changes[bisect_right(times, time)-1][1]
            if (bits >> PORTS['link_out']) & 3 == 1:
                idle += 1
                pending += any(queue[bisect_right(ts, time)-1]['occupancy']
                               for queue, ts in zip(queues, queue_times))
        result.append({'device': device, 'idle_ready_cycles': idle,
            'pending_return_cycles': pending, 'pending_fraction': pending/idle if idle else 0.0})
    return result


def analyze(stage: Path) -> dict:
    """Write link composition and every FIFO/actor's occupancy, cross-checking public word totals."""
    service = json.loads((stage / 'service.json').read_text())
    start, stop = service['window_ns']
    links = traffic(stage, start, stop)
    for link, device in zip(links, service['devices']):
        if sum(link['words'].values()) != device['ports']['link_out']['accepted']:
            raise ValueError('wire log and handshake counts disagree')
    waiting = idle_returns(stage, start, stop)
    for row, device in zip(waiting, service['devices']):
        if row['idle_ready_cycles'] != device['ports']['link_out']['idle_ready']:
            raise ValueError('return-wait and handshake idle counts disagree')
    report = {'window_ns': [start, stop], 'link_traffic': links, 'idle_returns': waiting,
              'occupancy': occupancy(stage, start, stop)}
    (stage / 'analysis.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    analyze(parser.parse_args().stage)
