"""Follow accepted ordinary frames through physical FIFO, mux and routing boundaries."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import defaultdict
import json
from pathlib import Path
import re

from phi_link_packet import packets
from phi_message_profile import packet_frame

FRAME_MASK = (1 << 128)-1


def instances(manifest: dict) -> dict[tuple[str, ...], dict]:
    """Group public handshake endpoints by their generated instance, retaining physical aliases."""
    groups = {}
    for probe in manifest['probes']:
        for endpoint in probe['endpoints']:
            key = tuple(endpoint['path'])
            group = groups.setdefault(key, {'module': endpoint['module'], 'ports': {}})
            previous = group['ports'].setdefault(endpoint['port'], probe['id'])
            if previous != probe['id']:
                raise ValueError('an instance port has multiple physical observations')
    return groups


def frame(value: int, width: int) -> int:
    """Project a checked Frame, Egress, ScheduledRequest or SpatialFrame to its complete frame bits."""
    if width == 161:
        return (value >> 1) & FRAME_MASK
    if width in (128, 136, 194):
        return value & FRAME_MASK
    raise ValueError(f'unsupported ordinary frame envelope: {width}')


def control_select(value: int, binding: dict, targets: list[dict]) -> bool:
    """Apply the checked deployment's inclusive rectangle and target/schema selection."""
    selector = (value >> 128) & 3
    x0, y0, x1, y1 = [(value >> offset) & 65535 for offset in (178, 162, 146, 130)]
    x, y = binding['point']
    if not x0 <= x <= x1 or not y0 <= y <= y1:
        return False
    op, words = (value >> 96) & 255, (value >> 120) & 255
    return any(t['id'] in binding['targets'] and t['selector'] == selector and
        {'op': op, 'words': words} in t['encodings'] for t in targets)


def boundary_name(channel: dict) -> str:
    """Name an observed boundary without a long generated hierarchy in the track title."""
    name,role=channel['channel'],channel['role']
    if 'fifo__outgoing_' in role:
        return 'packetizer accepts frame'
    if 'fifo__received_' in role:
        return 'receive queue accepts frame'
    if '__FrameMux2_' in name:
        match=re.search(r'__FrameMux2_0_next_inst(?:_(\d+))?/',name)
        index=(match[1] or '0') if match else '?'
        port=name.rsplit('/',1)[-1]
        return f'mux {index} '+{'_left_in':'left input','_right_in':'right input','_frame_out':'output'}[port]
    if '__Router' in name:
        return 'actor egress' if name.endswith('/_egress_in') else 'route '+name.rsplit('/',1)[-1].strip('_').replace('_',' ')
    if '__SchedulerIngress' in name:
        return 'scheduler ingress '+('output' if name.endswith('/_request_out') else name.rsplit('/',1)[-1].strip('_'))
    if '__SchedulerInput' in name:
        return 'request wrapper '+('input' if name.endswith('/_frame_in') else 'output')
    if 'SharedService' in name:
        return 'scheduler accepts request'
    return name.rsplit('/',1)[-1]


class Streams:
    """Resolve message ancestry by accepted stream ordinal; payload equality only checks the result."""

    def __init__(self, graph: dict, stage: Path, route: dict, channels: dict, messages: dict) -> None:
        """Bind the captured topology and seed actor effects, host ingress and startup boundaries."""
        self.graph, self.stage, self.route = graph, stage, route
        self.channels, self.messages = channels, messages
        self.parents, self.memo, self.roots, self.remote = {}, {}, {}, {}
        self.checked = set()
        self.tail_roots = {}
        self.events = {e['id']: e for e in graph['events']}
        self.relations = {(e['source'],e['target']): e for e in graph['edges']}
        self.tracks = {t['id'] for t in graph['tracks']}
        self.inputs = json.loads((stage/'profile-inputs.json').read_text())
        self.manifests = {d: json.loads((stage/f'device{d}-manifest.json').read_text())
                          for d in range(len(self.inputs['device_periods_ns']))}
        self.instances = {d: instances(m) for d, m in self.manifests.items()}
        self.capture_end = max(p['ts'] for values in messages.values() for p in values)
        self.effects = {(int(e['track'].split('/')[0][1:]), e['args']['channel'], e['ts']): e
            for e in graph['events'] if e['track'].endswith('/effect')}
        for device in self.manifests:
            self.bind_device(device)
        self.bind_remote()

    def values(self, device: int, channel: int) -> list[dict]:
        """Return a captured stream; an empty selected stream has no transactions."""
        if (device, channel) not in self.channels:
            raise ValueError(f'ordinary routing boundary was not captured: {device}/{channel}')
        records = self.messages.get((device, channel), [])
        width = self.channels[device, channel]['width']
        if (device,channel) not in self.checked and any(p['mask'] != (1 << width)-1 for p in records):
            raise ValueError('ordinary routing needs complete observed payload bits')
        self.checked.add((device,channel))
        return records

    def bind(self, device: int, target: int, sources: list[tuple[int, int]], kind: str) -> None:
        """Require a conserved ordered stream and checked frame bits across one transformation."""
        output = self.values(device, target)
        for index in range(len(sources),len(output)):
            if output[index]['ts'] != self.capture_end:
                raise ValueError(f'{kind} produced more messages than it accepted: D{device}/{target}')
            self.tail_roots[device,target,index]='producer observation missing on final simulation edge'
        for i, (source, ordinal) in enumerate(sources[:len(output)]):
            prior = self.values(device, source)[ordinal]
            a,b=self.channels[device,source]['width'],self.channels[device,target]['width']
            mismatch=prior['value']!=output[i]['value'] if a==b else frame(prior['value'],a)!=frame(output[i]['value'],b)
            if prior['ts'] > output[i]['ts'] or mismatch:
                raise ValueError(f'{kind} changed frame identity or order: D{device}/{source}/{ordinal} -> {target}/{i}')
        key = device, target
        if key in self.parents:
            raise ValueError('two transformations claim one ordinary stream')
        self.parents[key] = (sources[:len(output)], kind)

    def bind_device(self, device: int) -> None:
        """Connect FIFO order, observed mux selection and compiler-declared actor/control routing."""
        for resource in self.manifests[device]['resources']:
            if resource['kind'] == 'fifo' and all((device,resource[side]) in self.channels for side in ('push','pop')):
                if self.channels[device,resource['push']]['width'] not in (128,136,161,194):
                    continue
                self.bind(device, resource['pop'], [(resource['push'], i)
                    for i in range(len(self.values(device, resource['push'])))], 'FIFO delivery')
        for _, instance in self.instances[device].items():
            module, ports = instance['module'], instance['ports']
            if '__FrameMux2_' in module:
                sources = [(p, i) for p in (ports['_left_in'], ports['_right_in'])
                           for i in range(len(self.values(device,p)))]
                sources.sort(key=lambda item: self.values(device,item[0])[item[1]]['ts'])
                times = [self.values(device,p)[i]['ts'] for p,i in sources]
                if len(times) != len(set(times)):
                    raise ValueError('FrameMux2 accepted two inputs in one clock')
                self.bind(device, ports['_frame_out'], sources, 'mux forwarding')
            elif re.search(r'__SchedulerIngress\d+_', module):
                producers = [p for name,p in ports.items() if name.startswith('_frame_')]
                sources = [(p,i) for p in producers for i in range(len(self.values(device,p)))]
                sources.sort(key=lambda item: self.values(device,item[0])[item[1]]['ts'])
                times = [self.values(device,p)[i]['ts'] for p,i in sources]
                if len(times) != len(set(times)):
                    raise ValueError('scheduler ingress accepted two inputs in one clock')
                self.bind(device, ports['_request_out'], sources, 'ingress arbitration and envelope')
            elif re.search(r'__SchedulerInput\d+_', module):
                self.bind(device, ports['_request_out'], [(ports['_frame_in'], i)
                    for i in range(len(self.values(device,ports['_frame_in'])))], 'scheduler envelope')
            elif match := re.search(r'__Router(\d+)_', module):
                actor = next(a for a in self.route['actors'] if a['device'] == device and a['index'] == int(match[1]))
                ingress=ports['_egress_in']
                # XLS can implement the actor egress boundary with port registers,
                # which are not independent FIFO resources in the public manifest.
                if (device,ingress) not in self.parents and self.values(device,ingress):
                    sources={channel for (d,channel,_),event in self.effects.items()
                             if d==device and event['args']['actor']==actor['name']
                             and self.channels[d,channel]['channel'].endswith('/_effects')}
                    if len(sources)!=1:
                        raise ValueError('actor router lacks one identified effect source')
                    source,=sources
                    if source!=ingress:
                        self.bind(device,ingress,[(source,i) for i in range(len(self.values(device,source)))], 'actor egress delivery')
                # Proved reduction lanes have independent producers and bypass this router.
                for lane in [l for l in self.route['lanes'] if l['source'] == actor['name']
                             and f'_lane_{l.get("rtl_id", l["id"])}_out' in ports]:
                    source = ports['_egress_in']
                    eligible = [(source, i) for i,p in enumerate(self.values(device,source))
                                if p['value'] >> 128 in lane['ports']]
                    self.bind(device, ports[f'_lane_{lane.get("rtl_id", lane["id"])}_out'], eligible, 'actor routing')
            elif '__ControlRouter_' in module:
                ingress, = self.route['ingresses']
                source = ports['_spatial_in']
                self.parents.pop((device,source), None)
                self.roots[device,source] = 'external control ingress'
                for binding in ingress['bindings']:
                    if binding['device'] != device:
                        continue
                    self.bind(device, ports[f'_actor_{binding["index"]}_control_out'], [(source,i)
                        for i,p in enumerate(self.values(device,source))
                        if control_select(p['value'],binding,ingress['targets'])], 'rectangle control routing')
            elif re.search(r'__SchedulerStartup\d+_', module):
                self.roots[device,ports['_request_out']] = 'deployment startup'

    def bind_remote(self) -> None:
        """Pair directed peer streams exactly, retaining lane ordinals across packetization."""
        topology = json.loads((self.stage/'bridge.json').read_text())['devices']
        tx = packets(self.stage/'traffic.log', self.inputs['transport'])
        rx = packets(self.stage/'received-traffic.log', self.inputs['transport'])
        streams = defaultdict(list)
        for device in topology:
            d = device['id']
            for link in device['links']:
                peer = link['peer']
                reverse, = [p['index'] for p in topology[peer]['links'] if p['peer']==d]
                sent, received = tx.get((d,link['index']),[]), rx.get((peer,reverse),[])
                if len(received)>len(sent):
                    raise ValueError('peer received an unrecorded packet')
                for a,b in zip(sent,received):
                    if b['words'] != a['words'][:len(b['words'])]:
                        raise ValueError('peer wire changed packet identity')
                    if not a['credit'] and b['complete']:
                        streams[d,peer,a['lane']].append((a,b))
        for lane in self.route['lanes']:
            if lane['kind'] != 'remote':
                continue
            source, target, ident = lane['source_device'], lane['destination_device'], lane['wire_id']
            port, = [p['index'] for p in topology[source]['links'] if p['peer']==target]
            reverse, = [p['index'] for p in topology[target]['links'] if p['peer']==source]
            out, = [r for r in self.manifests[source]['resources'] if r['kind']=='fifo' and
                    r['name'].endswith(f'fifo__outgoing_{port}__{ident}_')]
            inc, = [r for r in self.manifests[target]['resources'] if r['kind']=='fifo' and
                    r['name'].endswith(f'fifo__received_{reverse}__{ident}_')]
            self.remote[target,inc['push']] = (source,out['pop'],lane,streams[source,target,ident])

    def add(self, ident: str, device: int, track: str, name: str, ts: int, args: dict, dur: int = 0) -> dict:
        """Add a unique observed event; clock bins do not become logical service time."""
        if ident in self.events:
            return self.events[ident]
        if track not in self.tracks:
            actor=args.get('actor')
            label=re.sub(r'^\{actor,\{family,([^,]+),(\[[^\]]+\])\}\}$',r'\1\2',actor) if actor else None
            self.graph['tracks'].append({'id':track,'name':f'{label} / {name}' if actor else f'D{device} {name}',
                'group':f'D{device} {actor}' if actor else f'D{device} ordinary transport'})
            self.tracks.add(track)
        event = {'id':ident,'track':track,'name':name,'ts':ts,'dur':dur,'args':args,
                 'category':'handshake' if not dur else 'service'}
        if not dur:
            event['display_duration_ns'] = self.inputs['device_periods_ns'][device]
        self.graph['events'].append(event)
        self.events[ident]=event
        return event

    def edge(self, source: dict, target: dict, kind: str, evidence: str, *, resource: str | None = None) -> None:
        """Record a supported prerequisite, separating observed resource constraints."""
        if source['ts']+source['dur'] > target['ts']:
            raise ValueError(f'ordinary-message time inversion: {source["id"]} -> {target["id"]}')
        pair=source['id'],target['id']
        if not resource and pair in self.relations:
            self.relations[pair].setdefault('additional_evidence', []).append({'kind':kind,'evidence':evidence})
            return
        edge={'source':source['id'],'target':target['id'],'kind':kind,'evidence':evidence}
        if resource:
            self.graph['resource_dependencies'].append({**edge,'resource':resource})
        else:
            self.graph['edges'].append(edge)
            self.relations[pair]=edge

    def node(self, device: int, channel: int, ordinal: int) -> dict:
        """Materialize one identity's ancestry; unexplained interior roots are errors."""
        key=device,channel,ordinal
        if key in self.memo:
            return self.memo[key]
        record=self.values(device,channel)[ordinal]
        if self.channels[device,channel]['role']=='effect':
            if (device,channel,record['ts']) not in self.effects:
                raise ValueError(f'ordinary effect lacks a producing activation: {key}')
            result=self.effects[device,channel,record['ts']]
            self.memo[key]=result
            return result
        label=boundary_name(self.channels[device,channel])
        result=self.add(f'mail/D{device}/ch{channel}/{ordinal}',device,f'D{device}/mail/ch{channel}',label,
            record['ts'],{'channel':channel,'ordinal':ordinal,'frame':hex(frame(record['value'],self.channels[device,channel]['width']))})
        self.memo[key]=result
        if key in self.tail_roots:
            result['args'].update(incomplete_at_capture_end=True, capture_boundary=self.tail_roots[key])
        elif (device,channel) in self.remote:
            sd,sc,lane,wire=self.remote[device,channel]
            sent,received=wire[ordinal]
            producer=self.node(sd,sc,ordinal)
            source=self.values(sd,sc)[ordinal]
            if packet_frame(sent)['value'] != frame(source['value'],self.channels[sd,sc]['width']) or packet_frame(received)['value'] != frame(record['value'],self.channels[device,channel]['width']):
                raise ValueError('ordinary remote frame differs from its directed wire packet')
            stem=f'mail/lane{lane["id"]}/{ordinal}'
            args={'lane':lane['id'],'ordinal':ordinal,'destination':lane['destination']}
            a=self.add(stem+'/tx',sd,f'D{sd}/mail/lane{lane["id"]}/tx','ordinary frame transmit',sent['start_ns'],args,sent['end_ns']-sent['start_ns'])
            b=self.add(stem+'/rx',device,f'D{device}/mail/lane{lane["id"]}/rx','ordinary peer frame complete',received['end_ns'],args)
            for left,right,kind in ((producer,a,'packetization'),(a,b,'wire delivery'),(b,result,'receive admission')):
                self.edge(left,right,kind,'directed peer stream, lane ordinal and complete frame bits agree')
        elif (device,channel) in self.parents:
            references,kind=self.parents[device,channel]
            parent,index=references[ordinal]
            self.edge(self.node(device,parent,index),result,kind,'accepted stream ordinal and complete frame bits agree')
        elif (device,channel) in self.roots:
            result['args']['external_root']=self.roots[device,channel]
            result['name']=self.roots[device,channel]
        else:
            raise ValueError(f'unexplained ordinary stream root: D{device}/{channel}: {self.channels[device,channel]["channel"]}')
        return result
