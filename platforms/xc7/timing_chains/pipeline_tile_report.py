#!/usr/bin/env python3
"""Compare complete-mesh boundary experiments and retain portable profile evidence."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'workloads/hls_phi/tools'))
from phi_cycle_trace import executor_requests, read
from phi_transport_metrics import dense, distribution


def banks(profile: Path) -> list[dict]:
    """Count transfers and independent public reservation flags without attributing source-actor causality."""
    resources, histories = read(profile, {0}, profile/'device0-trace.csv.gz')
    config = json.loads((profile/'profile-inputs.json').read_text())
    start, stop = json.loads((profile/'service.json').read_text())['window_ns']
    period = config['device_periods_ns'][0]
    results = []
    for bank in config['scheduler_groups']['0']:
        request, = executor_requests(resources.values(), bank['module'])
        history = histories[0, request['accept']]
        origin = history[0]['time_ns']
        count = (stop-origin+period-1)//period
        values = dense(history, count)
        selected = [v for i, v in enumerate(values) if start <= origin+i*period < stop]
        totals = dict.fromkeys(('in_flight_ns', 'outbox_reserved_ns', 'both_ns', 'neither_ns'), 0)
        actors = [r for r in resources.values() if r['kind'] == 'actor' and r['bank'] == bank['index']]
        if len(actors) != bank['slots']:
            raise ValueError('actor reservation population differs from bank catalog')
        for actor in actors:
            history = histories[0, actor['id']]
            for value, following in zip(history, [*history[1:], {'time_ns': stop}]):
                duration = max(0, min(stop, following['time_ns'])-max(start, value['time_ns']))
                flight, outbox = value['in_flight'], value['waiting_for_egress']
                for key, active in (('in_flight_ns', flight), ('outbox_reserved_ns', outbox),
                                    ('both_ns', flight and outbox), ('neither_ns', not (flight or outbox))):
                    totals[key] += duration*int(active)
        results.append({**bank, 'cycles': len(selected), 'executor_requests': selected.count(3),
                        'request_blocked_cycles': selected.count(1), 'actor_time_ns': totals})
    return results


def package(root: Path, output: Path) -> dict:
    """Require matching workload/tool inputs and successful full-mesh witnesses before comparing."""
    output.mkdir(parents=True, exist_ok=True)
    entries, runs, identities, controls, transforms, windows = {}, {}, [], [], [], []
    def keep(path: Path, member: str) -> None:
        """Preserve an exact compact artifact in the indexed archive."""
        entries[member] = path.read_bytes()
    for name, profile_name in (('full-tile', 'full-tile-profile-v2'), ('no-loader-tile', 'no-loader-tile-profile')):
        build, profile = root/name, root/profile_name
        identity = json.loads((build/'inputs.json').read_text())
        experiment = identity.pop('experiment')
        if experiment.pop('remove') != ([] if name == 'full-tile' else ['loader']):
            raise ValueError('unexpected tile transformation')
        transforms.append(experiment)
        identities.append(identity)
        config = json.loads((profile/'profile-inputs.json').read_text())
        controls.append({k: config[k] for k in ('device_periods_ns', 'link_stages', 'periodic_stalls',
                                              'transport', 'reductions', 'actor_devices')})
        for log in ('host.log', 'simulation.log'):
            if 'PASS:' not in (profile/log).read_text():
                raise ValueError('incomplete mesh witness: '+name)
        progress = json.loads((profile/'progress.json').read_text())
        graph = json.loads((profile/'actor0.profile.json').read_text())
        actor = json.loads((profile/'actor0.summary.json').read_text())
        start, stop = actor['window_ns']
        records = [r for r in actor['progress_handoffs']['records'] if start <= r['request_ns'] < stop]
        by_key = {(r['actor'], r['site'], r['key']): r for r in records}
        if len(by_key) != len(records):
            raise ValueError('ambiguous actor/site/key handoff identity')
        windows.append(by_key)
        report = {'progress': progress, 'mean_cycles_per_step': progress['mean_ns']/config['device_periods_ns'][0],
                  'controls': controls[-1], 'groups': config['scheduler_groups']['0'],
                  'banks': banks(profile),
                  'actor_time_ns': actor['observed_actor_time_ns'],
                  'handoffs_ns': actor['progress_handoffs']['durations_ns'],
                  'actor_durations_ns': actor['durations_ns'],
                  'analysis_tools_sha256': graph['metadata']['analysis_sha256'],
                  'checked_publication_cycles': graph['metadata']['checked_publication_cycles'],
                  'events': json.loads((profile/'memory-result.json').read_text())['events'],
                  'full_capture_sha256': hashlib.sha256((profile/'cycle-trace.csv.gz').read_bytes()).hexdigest()}
        runs[name] = report
        for leaf in ('inputs.json', 'source-hashes.json', 'source/ablation.json', 'device0/build.json'):
            keep(build/leaf, name+'/build/'+leaf)
        for path in (build/'source').glob('*.x'):
            keep(path, name+'/source/'+path.name)
        for path in profile.iterdir():
            if path.suffix == '.json' or path.name in (
                    'activity.log', 'host.log', 'simulation.log', 'device0-trace.csv.gz',
                    'config.term', 'deployment.term', 'oracle.term', 'actor0.svg'):
                keep(path, name+'/profile/'+path.name)
    if identities[0] != identities[1] or controls[0] != controls[1] or transforms[0] != transforms[1]:
        raise ValueError('mesh tools/workload/profile controls differ beyond the requested transformation')
    if runs['full-tile']['analysis_tools_sha256'] != runs['no-loader-tile']['analysis_tools_sha256']:
        raise ValueError('actor analysis tools differ between captures')
    keep(root/'replay/verification.json', 'replay-verification.json')
    full, candidate = (runs[k]['progress']['mean_ns'] for k in ('full-tile', 'no-loader-tile'))
    result = {'runs': runs, 'mean_step_change_percent': 100*(candidate/full-1),
              'break_even_period_ratio': full/candidate,
              'scope': 'Complete D6 mesh simulation at fixed clock; no complete-tile physical timing comparison.'}
    keys = windows[0].keys() & windows[1].keys()
    result['matched_handoffs'] = {'samples': len(keys), 'identity': 'actor/site/key; request inside both measurement windows',
        'runs': {name: {field: distribution([rows[k][field] for k in keys])
                       for field in ('mux_queue_ns', 'scheduler_pending_ns', 'state_read_ns')}
                 for name, rows in zip(runs, windows)}}
    with tarfile.open(output/'tile-evidence.tar.gz', 'w:gz') as archive:
        for member, data in entries.items():
            info = tarfile.TarInfo(member)
            info.size, info.mtime = len(data), 0
            archive.addfile(info, io.BytesIO(data))
    (output/'tile-evidence-index.json').write_text(json.dumps({n: {'bytes': len(b),
        'sha256': hashlib.sha256(b).hexdigest()} for n, b in entries.items()}, indent=2)+'\n')
    (output/'tile-summary.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main() -> None:
    """Package the two completed mesh runs without repeating compilation or simulation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = package(args.root, args.output)
    print({k: v for k, v in result.items() if k != 'runs'})


if __name__ == '__main__':
    main()
