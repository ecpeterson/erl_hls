"""Account for transport service using public channel and FIFO debug projections."""
from collections import Counter
import json
from pathlib import Path
import re
import statistics

from phi_cycle_trace import read, capture_path
from phi_mesh_metrics import layout
from backend_commands import digest


def transport_plan(resources: list[dict], links: list[dict]) -> list[dict]:
    """Resolve per-peer queues and their endpoints from the checked debug manifest."""
    by_id = {r['id']: r for r in resources}
    by_name = {r['name']: r for r in resources}
    result = []
    for link in links:
        i, tx, rx = link['index'], link['tx_lanes'], link['rx_lanes']
        queues = {int(m[1]): r for r in resources if r['kind'] == 'fifo'
                  and (m := re.search(rf'fifo__outgoing_{i}__(\d+)_$', r['name']))}
        if sorted(queues) != list(range(tx)):
            raise ValueError('outgoing lane layout differs from deployment')
        packetizer = by_id[queues[0]['pop']]['name'].rsplit('/', 1)[0]
        bridge = packetizer.split('/__hls_credit_link__Transmit_')[0]
        def endpoint(suffix: str) -> int:
            """Require a channel endpoint within this peer's packetizer."""
            r = by_name[f'{packetizer}/{suffix}']
            if r['kind'] != 'channel' or r['width'] != 2:
                raise ValueError('invalid transport channel projection')
            return r['id']
        def lane_queues(name: str, count: int) -> list[int]:
            """Require every independent lane queue under this bridge."""
            return [by_name[f'{bridge}/materialized_fifo_fifo__{name}__{lane}_']['id']
                    for lane in range(count)]
        result.append({**link, 'frames': [endpoint(f'_frames_in__{lane}') for lane in range(tx)],
            'credits': [endpoint(f'_credits_in__{lane}') for lane in range(tx)],
            'returns': [endpoint(f'_returned_in__{lane}') for lane in range(rx)],
            'outgoing': [queues[lane]['id'] for lane in range(tx)],
            'credit_queues': lane_queues('link_credit', tx),
            'return_queues': lane_queues('link_returned', rx),
            'received': lane_queues('link_received', rx),
            'words': endpoint('_link_out'), 'wire': by_name[f'_link_{i}_out']['id']})
    return result


def dense(history: list[dict], count: int) -> list[int]:
    """Expand a change-only projection to pre-edge values, requiring an initial sample."""
    if not history or history[0]['cycle'] != 0:
        raise ValueError('transport accounting requires observation from reset release')
    result = [0]*count
    for sample, following in zip(history, [*history[1:], {'cycle': count}]):
        begin, end = sample['cycle'], min(count, following['cycle'])
        result[begin:end] = [sample['value']] * (end-begin)
    return result


def inspect_link(plan: dict, histories: dict, device: int, start: int, stop: int, period: int) -> dict:
    """Reconstruct credit ownership and validate packetizer choices against observed transfers."""
    initial = histories[device, plan['wire']][0]
    count = (stop-initial['time_ns']+period-1)//period
    ids = set(sum([plan[k] for k in ('frames', 'credits', 'returns', 'outgoing', 'return_queues')], []))
    ids.update((plan['words'], plan['wire']))
    values = {i: dense(histories[device, i], count) for i in ids}
    credits, served, returned = [True]*len(plan['frames']), set(), set()
    stage, prefer = 0, False
    totals = Counter()
    first = max(0, (start-initial['time_ns']+period-1)//period)
    generated, output = [], []
    ledger = []
    credit_start = [None]*len(credits)
    data_start, return_start = [None]*len(credits), [None]*len(plan['returns'])
    latencies = {name: [] for name in ('frame_wait', 'return_wait', 'credit_roundtrip')}
    wire_values = []
    for cycle in range(count):
        frame = [values[i][cycle] for i in plan['frames']]
        credit = [values[i][cycle] for i in plan['credits']]
        returns = [values[i][cycle] for i in plan['returns']]
        offered = {i for i, value in enumerate(frame) if value & 1}
        granted = {i for i, value in enumerate(frame) if value == 3}
        credited = {i for i, value in enumerate(credit) if value == 3}
        return_offered = {i for i, value in enumerate(returns) if value & 1}
        return_granted = {i for i, value in enumerate(returns) if value == 3}
        if any(credits[i] for i in credited):
            raise ValueError(f'duplicate credit D{device} L{plan["index"]} cycle {cycle}')
        for i in credited:
            if credit_start[i] is None:
                raise ValueError('credit without an outstanding frame')
            if credit_start[i] >= first:
                latencies['credit_roundtrip'].append(cycle-credit_start[i])
            credit_start[i] = None
            credits[i] = True
        eligible = {i for i in offered if credits[i]}
        for states, starts, transfers, name in (
                (frame, data_start, granted, 'frame_wait'),
                (returns, return_start, return_granted, 'return_wait')):
            for i, value in enumerate(states):
                if value & 1 and starts[i] is None:
                    starts[i] = cycle
                if not value & 1 and starts[i] is not None:
                    raise ValueError('an offered item was withdrawn before acceptance')
                if i in transfers:
                    if starts[i] >= first:
                        latencies[name].append(cycle-starts[i])
                    starts[i] = None
        # Unconditional nonblocking credit receives share the iteration enable.
        enabled = bool(credit[0] & 2)
        if any(bool(v & 2) != enabled for v in credit):
            raise ValueError('credit inputs disagree on iteration enable')
        take_return = min(return_offered-returned, default=None) if prefer and stage == 0 and enabled else None
        take_data = min(eligible-served, default=None) if take_return is None and stage == 0 and enabled else None
        if granted != ({take_data} if take_data is not None else set()) or return_granted != ({take_return} if take_return is not None else set()):
            raise ValueError(f'choice reconstruction differs D{device} L{plan["index"]} cycle {cycle}: '
                             f'stage={stage} enabled={enabled} data {granted}/{take_data} return {return_granted}/{take_return}')
        emitting = enabled and bool(stage or granted or return_granted)
        generated.append(emitting)
        output.append(values[plan['words']][cycle] == 3)
        wire_values.append(values[plan['wire']][cycle] == 3)
        if not enabled:
            reason = 'iteration_stalled'
        elif stage:
            reason = 'payload'
        elif granted:
            reason = 'data_header'
        elif return_granted:
            reason = 'credit_header'
        elif eligible or return_offered:
            reason = 'arbitration_idle'
        elif offered:
            reason = 'credit_idle'
        else:
            reason = 'no_offer_idle'
        if cycle >= first:
            totals[reason] += 1
            if reason == 'arbitration_idle':
                subtype = 'data_round' if eligible else ('return_turn' if not prefer else 'return_round')
                totals['arbitration_'+subtype+'_idle'] += 1
            wire = values[plan['wire']][cycle]
            totals['wire_accepted'] += wire == 3
            totals['wire_blocked'] += wire == 1
            totals['wire_idle'] += not (wire & 1)
            totals['wire_idle_offered'] += not (wire & 1) and bool(offered)
            totals['wire_idle_queued'] += not (wire & 1) and any(values[i][cycle] for i in plan['outgoing'])
            ledger.append([cycle, reason, len(offered), len(eligible), len(return_offered), wire])
        for i in granted:
            if not credits[i]:
                raise ValueError('uncredited frame')
            credits[i] = False
            credit_start[i] = cycle
        if enabled:
            if stage == 0:
                if granted:
                    served |= granted
                elif not return_granted:
                    served.clear()
                if return_granted:
                    returned |= return_granted
                elif prefer:
                    returned.clear()
                if len(served) == len(credits): served.clear()
                if len(returned) == len(returns): returned.clear()
                prefer = True if granted else not prefer
            stage = 1 if granted else (stage+1 if 0 < stage < 4 else 0)
    delays = [lag for lag in range(8) if generated[:count-lag] == output[lag:]]
    if len(delays) != 1:
        raise ValueError(f'word production is not a fixed checked delay: {delays}')
    wire_delays = [lag for lag in range(8) if output[:count-lag] == wire_values[lag:]]
    if len(wire_delays) != 1 or totals['iteration_stalled'] or totals['wire_blocked']:
        raise ValueError('this accounting requires unstalled fixed-delay word delivery')
    summaries = {name+'_cycles': distribution(samples) for name, samples in latencies.items()}
    return {'device': device, 'link': plan['index'], 'peer': plan['peer'], 'cycles': count-first,
            'packetizer_output_delay_cycles': delays[0], 'wire_delay_cycles': wire_delays[0],
            'reset_release_ns': initial['time_ns'], 'counts': dict(totals), 'latencies': summaries, 'timeline': ledger}


def distribution(samples: list[int]) -> dict:
    """Summarize completed observations, using population variance and retaining the histogram."""
    if not samples:
        return {'samples': 0}
    return {'samples': len(samples), 'best': min(samples), 'mean': statistics.mean(samples),
            'variance': statistics.pvariance(samples), 'worst': max(samples),
            'histogram': dict(sorted(Counter(samples).items()))}


def analyze(stage: Path) -> dict:
    """Write a fail-closed transport accounting report for every peer in the D6 run."""
    devices = json.loads((stage/'bridge.json').read_text())['devices']
    selected = set()
    for device in devices:
        d = device['id']
        manifest = json.loads((stage/f'device{d}-manifest.json').read_text())
        for plan in transport_plan(manifest['resources'], device['links']):
            for key in ('frames', 'credits', 'returns', 'outgoing', 'return_queues'):
                selected.update((d, ident) for ident in plan[key])
            selected.update((d, plan[key]) for key in ('words', 'wire'))
    resources, histories = read(stage, selected=selected)
    inputs = json.loads((stage/'profile-inputs.json').read_text())
    start, stop = json.loads((stage/'service.json').read_text())['window_ns']
    result, timelines = [], []
    for device in json.loads((stage/'bridge.json').read_text())['devices']:
        d = device['id']
        plans = transport_plan([r for (owner, _), r in resources.items() if owner == d], device['links'])
        for plan in plans:
            row = inspect_link(plan, histories, d, start, stop, inputs['device_periods_ns'][d])
            timeline = row.pop('timeline')
            if d == 0:
                timelines += [[d, plan['index'], *r] for r in timeline]
            row['direction'] = layout(stage)['port_labels'][str(d)][f"link_{plan['index']}_out"].split()[0]
            result.append(row)
    import csv
    with (stage/'transport-timeline.csv').open('w') as f:
        writer = csv.writer(f)
        writer.writerow(('device', 'link', 'cycle', 'reason', 'offered', 'eligible', 'returns', 'wire'))
        writer.writerows(timelines)
    evidence = [Path(__file__), Path(__file__).with_name('phi_cycle_trace.py'),
                capture_path(stage), stage/'profile-inputs.json', stage/'service.json',
                stage/'bridge.json', *sorted(stage.glob('device*-manifest.json'))]
    report = {'window_ns': [start, stop], 'links': result,
              'input_sha256': {str(p): digest(p) for p in evidence}}
    (stage/'transport.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    import sys
    analyze(Path(sys.argv[1]))
