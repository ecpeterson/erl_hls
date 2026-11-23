"""Connect ordinary message identities to their observed mailbox attempts and outcomes."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import Counter, defaultdict, deque
import json
import hashlib
from pathlib import Path
import re

from phi_mailbox_model import Mailbox, decode, frame_from_ram, packed_layout
from phi_mailbox_routes import FRAME_MASK, Streams


def mailbox_stride(text: str, capacity: int, slots: int) -> int:
    """Decode the generated bank layout, preserving packed addresses in older saved profiles."""
    if 'mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH)' not in text:
        return capacity
    padded = 1 << (capacity - 1).bit_length()
    return padded if (slots * padded - 1).bit_length() == (slots * capacity - 1).bit_length() else capacity


def bank_layout(stage: Path, streams: Streams, device: int, bank: int, actors: list[dict]) -> dict:
    """Bind a public actor bank to its exact executor and generated packed type declarations."""
    module = actors[0]['module']
    banks = sorted({r['bank'] for r in streams.manifests[device]['resources']
                    if r['kind']=='actor' and r['module']==module})
    services = sorted((path, value) for path,value in streams.instances[device].items()
                      if value['module'].startswith(f'__{module}__SharedService_'))
    path, service = services[banks.index(bank)]
    executor, = [value for p,value in streams.instances[device].items()
                 if p[:-1]==path and '__SharedExecutor_' in value['module']]
    source = Path(streams.inputs['build'])/'source'/f'{module}.x'
    text = source.read_text()
    layouts = {name:packed_layout(text, 'SharedExecutor'+name.title()) for name in ('request','result')}
    for name,port in (('request','_request_in'),('result','_result_out')):
        if layouts[name]['width'] != streams.channels[device,executor['ports'][port]]['width']:
            raise ValueError('generated executor type differs from captured width')
    capacity = int(re.search(r'const MAILBOX_DEPTH = u32:(\d+);',text)[1])
    if {a['mailbox_capacity'] for a in actors} != {capacity}:
        raise ValueError('actor manifest and generated mailbox capacities disagree')
    return {'service':service['ports'],'executor':executor['ports'],'layouts':layouts,
            'capacity':capacity,'stride':mailbox_stride(text, capacity, len(actors)),'source':str(source),'source_sha256':hashlib.sha256(text.encode()).hexdigest()}


def extend_bank(streams: Streams, device: int, bank: int, actors: list[dict], layout: dict) -> dict:
    """Replay one bank's ordered storage transactions; reject lost, reordered or invented messages."""
    service, executor = layout['service'], layout['executor']
    capacity = layout['capacity']
    stride = layout.get('stride', capacity)
    if stride < capacity:
        raise ValueError('mailbox stride overlaps logical rows')
    actor_by_slot = {a['slot']:a for a in actors}
    boxes = {slot:Mailbox(capacity) for slot in actor_by_slot}
    report = Counter()
    queues, producers = defaultdict(deque), defaultdict(set)
    for name,channel in service.items():
        if name=='_startup_in' or name.startswith('_request_in__'):
            for ordinal,record in enumerate(streams.values(device,channel)):
                value=record['value']
                if value & 1:
                    continue
                slot=value >> 129
                if slot not in boxes:
                    raise ValueError('scheduler admitted an unknown actor slot')
                queues[slot].append((record['ts'],channel,ordinal,(value >> 1)&FRAME_MASK))
                if name!='_startup_in':
                    producers[slot].add(channel)
    if any(len(ports)>1 for ports in producers.values()):
        raise ValueError('multiple ordinary producer ports need an observed admission selector')
    for slot,items in queues.items():
        queues[slot]=deque(sorted(items))
    requests = [dict(record, fields=decode(record['value'],layout['layouts']['request']))
                for record in streams.values(device,executor['_request_in'])]
    results = [dict(record, fields=decode(record['value'],layout['layouts']['result']))
               for record in streams.values(device,executor['_result_out'])]
    reads = streams.values(device,service['_mailbox_read_req_out'])
    responses = streams.values(device,service['_mailbox_read_resp_in'])
    writes = streams.values(device,service['_mailbox_write_req_out'])
    works = {e['ts']:e for e in streams.graph['events'] if e['track'].startswith(f'D{device}/bank{bank}/') and e['track'].endswith('/work')}
    selected_requests = [i for i,r in enumerate(requests) if r['fields']['received']]
    if len(responses)!=len(selected_requests):
        raise ValueError('mailbox response and received executor request counts differ')
    if not len(selected_requests)<=len(reads)<=len(selected_requests)+1 or not len(results)<=len(requests)<=len(results)+1:
        raise ValueError('mailbox/executor transaction counts disagree beyond the capture frontier')
    period = streams.inputs['device_periods_ns'][device]
    end = streams.capture_end
    operations=[]
    selected={}
    for read,response,index in zip(reads,responses,selected_requests):
        request=requests[index]
        fields=request['fields']
        if read['ts']+period != request['ts'] or read['value'] != fields['slot']*stride+fields['mailbox_index']:
            raise ValueError('mailbox read address/timing disagrees with executor selection')
        if response['ts'] != request['ts'] or frame_from_ram(response['value']) != fields['frame']:
            raise ValueError('mailbox RAM response differs from executor frame/timing')
        operations.append((read['ts'],0,index,'read',read))
    for index,result in enumerate(results):
        request=requests[index]
        if result['ts'] != request['ts']+period or any(result['fields'][k]!=request['fields'][k] for k in ('slot','received','mailbox_index','order_index')):
            raise ValueError('executor result does not retire its ordered request')
        operations.append((result['ts'],1,index,'retire',result))
    for index,write in enumerate(writes):
        operations.append((write['ts'],2,index,'write',write))
    for index,request in enumerate(requests):
        operations.append((request['ts'],3,index,'attempt',request))
    for time,_,index,kind,record in sorted(operations):
        if kind=='write':
            address,frame=record['value'] >> 128,frame_from_ram(record['value'] & FRAME_MASK)
            slot,physical=divmod(address,stride)
            if slot not in boxes or not queues[slot]:
                raise ValueError('mailbox write lacks an accepted actor input')
            accepted,channel,ordinal,expected=queues[slot].popleft()
            if accepted>time or expected!=frame:
                raise ValueError('mailbox admission changed per-actor input order or payload')
            source=streams.node(device,channel,ordinal)
            ident=f'mail/D{device}/bank{bank}/write{index}'
            args={'actor':actor_by_slot[slot]['name'],'bank':bank,'slot':slot,'physical_row':physical,
                  'frame':hex(frame),'op':(frame >> 96)&255,'payload_words':frame >> 120,'admission_channel':channel,'admission_ordinal':ordinal}
            admission=streams.add(ident,device,f'D{device}/bank{bank}/{slot}/mailbox_admission','mailbox admission',time,args)
            streams.edge(source,admission,'mailbox admission','one ordinary input stream per actor; RAM address, ordinal and complete frame agree')
            boxes[slot].admit(physical,{'event':admission,'frame':frame,'attempts':0})
        elif kind=='read':
            fields=requests[index]['fields']
            box=boxes[fields['slot']]
            message=box.select(fields['mailbox_index'],fields['order_index'])
            if message['frame'] != fields['frame']:
                raise ValueError('executor frame differs from the selected mailbox row identity')
            args={**message['event']['args'],'message':message['event']['id'],
                  'logical_position':fields['order_index'],'executor_request_ns':requests[index]['ts']}
            read=streams.add(f'mail/D{device}/bank{bank}/read{index}',device,
                f'D{device}/bank{bank}/{fields["slot"]}/mailbox_read','mailbox RAM read',time,args,period)
            streams.edge(message['event'],read,'stored message','selected physical row retains this admission identity; request and RAM response agree')
            selected[index]=(message,box.released.get(fields['mailbox_index']),read)
        elif kind=='attempt':
            fields=record['fields']
            work=works.get(time)
            if work is None:
                if time<end-2*period:
                    raise ValueError('interior executor request lacks an observed activation')
                report['unpublished_tail_activations']+=1
                continue
            if work['args']['slot'] != fields['slot']:
                raise ValueError('executor payload slot differs from public state-write identity')
            if not fields['received']:
                continue
            message,released,read=selected[index]
            if index>=len(results):
                report['unretired_tail_attempts']+=1
                continue
            dispatched=results[index]['fields']['dispatched']
            args={'message':message['event']['id'],'physical_row':fields['mailbox_index'],
                  'logical_position':fields['order_index'],'dispatched':bool(dispatched)}
            work['args']['mailbox']=args
            if not dispatched:
                report['unused_speculative_reads']+=1
                continue
            streams.edge(read,work,'ordinary message','executor dispatched this physical row and admission identity; full frame agrees')
            if released:
                args['postponed_release']=released
                streams.edge(streams.events[released],work,'postponed message released','observed phase boundary made this same postponed row eligible again')
            message['attempts']+=1
            args['attempt']=message['attempts']
            args['outcome']='consume' if results[index]['fields']['directive']==0 else 'postpone'
            if args['outcome']=='postpone':
                work['args']['state_transition_classification']=work['name']
                work['name']=f'postpone message (attempt {message["attempts"]})'
            if message['attempts']>1:
                report['retried']+=1
        else:
            fields=record['fields']
            request=requests[index]
            work=works.get(request['ts'])
            box=boxes[fields['slot']]
            # Public state writes are visible one clock after this accepted result.
            # Keep the actual retirement time as evidence, while placing outcome
            # markers at publication so their work edge never points backwards.
            if work:
                label='phase boundary' if fields['phase_boundary'] else 'actor result'
                if fields['received'] and fields['dispatched']:
                    label='message consumed' if fields['directive']==0 else 'message postponed'
                args={'actor':actor_by_slot[fields['slot']]['name'],'accepted_result_ns':time,
                      'phase_boundary':bool(fields['phase_boundary']),'directive':fields['directive']}
                if fields['received']:
                    args['message']=selected[index][0]['event']['id']
                outcome=streams.add(work['id']+'/outcome',device,work['track'].removesuffix('/work')+'/mailbox_outcome',label,
                    work['ts']+work['dur'],args)
                streams.edge(work,outcome,'actor result','checked result payload; marker is at public state publication')
            box.retire(fields['mailbox_index'],received=fields['received'],dispatched=fields['dispatched'],
                       directive=fields['directive'],phase_boundary=fields['phase_boundary'],event=work['id'] if work else '')
    for box in boxes.values():
        report.update(box.counts)
        report['pending_mailbox_tail']+=len(box.order)
        report['pending_postponed_tail']+=len(box.postponed)
    report['pending_input_tail']=sum(map(len,queues.values()))
    report['unissued_read_tail']=len(reads)-len(selected_requests)
    return dict(report)


def extend(graph: dict, stage: Path, route: dict, channels: dict, messages: dict) -> dict:
    """Connect all captured ordinary mailboxes, retaining explicit host/startup and capture boundaries."""
    streams=Streams(graph,stage,route,channels,messages)
    report,schemas=Counter(),{}
    for device,manifest in streams.manifests.items():
        banks=defaultdict(list)
        for actor in manifest['resources']:
            if actor['kind']=='actor':
                banks[actor['bank']].append(actor)
        for bank,actors in sorted(banks.items()):
            layout=bank_layout(stage,streams,device,bank,actors)
            schemas[f'D{device}/bank{bank}']=layout
            report.update(extend_bank(streams,device,bank,actors,layout))
    report['unobserved_final_edge_sources']=len(streams.tail_roots)
    (stage/'mailbox-schemas.json').write_text(json.dumps(schemas,indent=2)+'\n')
    return dict(report)
