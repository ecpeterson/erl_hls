#!/usr/bin/env python3
"""Render an ordinary-message retry and summarize measured admission-to-selection intervals."""
from collections import defaultdict
import gzip
import json
from pathlib import Path
from types import ModuleType

from phi_transport_metrics import distribution
from backend_commands import digest
from compiler_paths import compiler_root, compiler_tool


def remote_intervals(message: dict, read: dict, events: dict, incoming: dict) -> dict[str, int] | None:
    """Partition a remote ordinary delivery from peer completion through first mailbox selection."""
    chain = [message]
    while not chain[-1]['track'].endswith('/work') and len(incoming[chain[-1]['id']]) == 1:
        chain.append(events[incoming[chain[-1]['id']][0]['source']])
    chain.reverse()
    received = [i for i,e in enumerate(chain) if e['name'] == 'ordinary peer frame complete']
    if not received:
        return None
    index, = received
    peer, queued = chain[index:index+2]
    accepted = chain[-2]
    values = {'peer_complete_to_receive_queue': queued['ts']-peer['ts'],
              'receive_queue_to_scheduler': accepted['ts']-queued['ts'],
              'scheduler_to_admission': message['ts']-accepted['ts'],
              'admission_to_first_selection': read['ts']-message['ts']}
    if min(values.values()) < 0 or sum(values.values()) != read['ts']-peer['ts']:
        raise ValueError('ordinary boundary intervals do not partition elapsed time')
    return values


def render(graph: dict, target: dict, destination: Path, name: str, renderer: ModuleType) -> dict:
    """Show one admitted identity through its attempts; clip other actors' upstream histories explicitly."""
    hls_profile=renderer
    events={e['id']:e for e in graph['events']}
    incoming=defaultdict(list)
    for edge in graph['edges']:
        incoming[edge['target']].append(edge)
    message=target['args']['mailbox']['message']
    related=[e for e in graph['events'] if e.get('args',{}).get('message')==message or e.get('args',{}).get('mailbox',{}).get('message')==message]
    related=[e for e in related if e['ts']<=target['ts']+target['dur']]
    pending=[e['id'] for e in related]+[target['id'],message]
    selected,visited=set(),set()
    while pending:
        ident=pending.pop()
        if ident in visited:
            continue
        visited.add(ident)
        selected.add(ident)
        for edge in incoming[ident]:
            prior=events[edge['source']]
            selected.add(prior['id'])
            if not prior['track'].endswith('/work'):
                pending.append(prior['id'])
    chosen=sorted((events[i] for i in selected),key=lambda e:(e['ts'],e['id']))
    tracks={t['id']:t for t in graph['tracks']}
    track_order=list(dict.fromkeys(e['track'] for e in chosen))
    focus={'schema':1,'unit':'ns','tracks':[tracks[t] for t in track_order],'events':chosen,
           'edges':[e for e in graph['edges'] if e['source'] in selected and e['target'] in selected],
           'resource_dependencies':[e for e in graph['resource_dependencies'] if e['source'] in selected and e['target'] in selected],
           'counters':[], 'metadata':{'source_profile_sha256':graph['metadata']['source_profile_sha256'],'message':message,
             'dependency_scope':'one ordinary message through admission and any retries; producer and intervening actor ancestry clipped'}}
    left=max(0,min(e['ts'] for e in chosen)-8)
    right=max(e['ts']+hls_profile.display_duration(e) for e in chosen)+8
    overlay=hls_profile.observed_overlay(focus,target['id'])
    for suffix,value in [('profile.json',overlay),('perfetto.json',hls_profile.perfetto(overlay))]:
        (destination/f'{name}.{suffix}').write_text(json.dumps(value,separators=(',',':'))+'\n')
    (destination/f'{name}.svg').write_text(hls_profile.svg(focus,left,right,observed_target=target['id']))
    return {'target':target['id'],'message':message,'window_ns':[left,right]}


def report(stage: Path, destination: Path, name: str, public: Path) -> dict:
    """Retain an identity-preserving retry example without labelling queue waits as arbiter delay."""
    hls_profile = compiler_tool(public, "hls_profile")
    source=stage/'messages.profile.json.gz'
    graph=json.loads(gzip.decompress(source.read_bytes()))
    events={e['id']:e for e in graph['events']}
    incoming=defaultdict(list)
    for edge in graph['edges']:
        incoming[edge['target']].append(edge)
    start,stop=json.loads((stage/'service.json').read_text())['window_ns']
    attempts=[e for e in graph['events'] if e['track'].endswith('/work') and e.get('args',{}).get('mailbox',{}).get('dispatched')]
    samples=defaultdict(list)
    remote_samples=defaultdict(list)
    for work in attempts:
        if not start<=work['ts']<stop:
            continue
        message=events[work['args']['mailbox']['message']]
        read,=[events[e['source']] for e in incoming[work['id']] if e['kind']=='ordinary message']
        kind='first_selection' if work['args']['mailbox']['attempt']==1 else 'retry_selection'
        samples[kind+'_since_admission_ns'].append(read['ts']-message['ts'])
        if work['args']['mailbox']['attempt']==1:
            for key,value in (remote_intervals(message,read,events,incoming) or {}).items():
                remote_samples[key].append(value)
            parent,=[events[e['source']] for e in incoming[message['id']]]
            samples['scheduler_acceptance_to_admission_ns'].append(message['ts']-parent['ts'])
            node=message
            while len(incoming[node['id']])==1 and not node['track'].endswith('/work'):
                node=events[incoming[node['id']][0]['source']]
            if node['track'].endswith('/work'):
                samples['producer_commit_to_admission_ns'].append(message['ts']-node['ts']-node['dur'])

    graph['metadata']['source_profile_sha256']=digest(source)
    steady=[e for e in attempts if e['track'].startswith('D0/bank0/') and start<=e['ts']<stop]
    retries=[e for e in attempts if e['track'].startswith('D0/') and e['args']['mailbox']['attempt']>1]
    if not steady:
        raise ValueError('capture needs a steady-state ordinary delivery')
    examples={label:render(graph,min(candidates,key=lambda e:(e['ts'],e['id'])),destination,
                          name+'-'+label,hls_profile)
              for label,candidates in [('mailbox',steady),('retry',retries)] if candidates}
    result={'counts':graph['metadata']['report']['ordinary_mailboxes'],
            'remote_ordinary_intervals_ns':{key:distribution(values) for key,values in remote_samples.items()},
            'selection_intervals':{key:distribution(values) for key,values in samples.items()},
            'examples':examples,
            'measurement_window_ns':[start,stop],
            'postponed_attempts_in_window':sum(start<=e['ts']<stop and e['args']['mailbox']['outcome']=='postpone' for e in attempts),
            'source_profile_sha256':digest(source),
            'scope':'Selection intervals include postponement and resource waiting, not isolated arbitration overhead.'}
    (destination/f'{name}-mailbox-summary.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main() -> None:
    """Export a saved mailbox capture with the shared canonical and Perfetto renderers."""
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',nargs=2,action='append',required=True,metavar=('NAME','STAGE'))
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--erl-hls', type=Path, help='explicit compiler root')
    parser.add_argument('--profile', default='default', help='rebar dependency profile')
    args=parser.parse_args()
    public = compiler_root(args.profile, args.erl_hls)
    args.output.mkdir(parents=True,exist_ok=True)
    for name,path in args.run:
        print(name,json.dumps(report(Path(path),args.output,name,public)),flush=True)


if __name__=='__main__':
    main()
