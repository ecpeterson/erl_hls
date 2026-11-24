#!/usr/bin/env python3
"""Exercise message identity, postponed retries and checked generated layouts."""
import phi_tool_paths  # Resolve shared tooling for this application.
import unittest

from phi_mailbox_model import Mailbox, decode, frame_from_ram, packed_layout
from phi_mailbox_routes import Streams, control_select, frame
from phi_mailbox_profile import extend_bank, mailbox_stride
from phi_mailbox_report import remote_intervals
from collections import defaultdict


class MailboxTests(unittest.TestCase):
    """Reject ambiguous/reordered histories, including equal-valued messages and reused rows."""

    def test_equal_payloads_keep_distinct_identities(self) -> None:
        """Consuming an equal-valued predecessor cannot consume its successor."""
        box=Mailbox(2)
        a,b={'id':'a','frame':42},{'id':'b','frame':42}
        box.admit(0,a); box.admit(1,b)
        self.assertIs(box.select(0,0),a)
        box.retire(0,received=True,dispatched=True,directive=0,phase_boundary=False,event='a')
        box.admit(0,{'id':'c','frame':42})
        self.assertIs(box.select(1,0),b)
        with self.assertRaises(ValueError): box.select(0,1)
        self.assertEqual(box.order,[1,0])

    def test_postpone_phase_release_and_retry(self) -> None:
        """A phase boundary releases a postponed identity without allocating a new message."""
        box=Mailbox(2)
        a,b={'id':'a'},{'id':'b'}
        box.admit(1,a); box.admit(0,b)
        box.retire(1,received=True,dispatched=True,directive=1,phase_boundary=False,event='postpone')
        self.assertIs(box.select(0,1),b)
        box.retire(0,received=True,dispatched=True,directive=0,phase_boundary=True,event='transition')
        self.assertIs(box.select(1,0),a)
        self.assertEqual(box.released,{1:'transition'})
        box.retire(1,received=True,dispatched=True,directive=0,phase_boundary=False,event='consume')
        box.admit(1,{'id':'c'})
        self.assertNotIn(1,box.released)

    def test_unused_read_and_same_result_release(self) -> None:
        """Speculative reads do not consume; a postponing phase change releases its own message."""
        box=Mailbox(1); message={'id':'same'}; box.admit(0,message)
        box.retire(0,received=True,dispatched=False,directive=0,phase_boundary=False,event='entry')
        self.assertIs(box.select(0,0),message)
        box.retire(0,received=True,dispatched=True,directive=1,phase_boundary=True,event='transition')
        self.assertIs(box.select(0,0),message)
        self.assertEqual(box.released[0],'transition')

    def test_invalid_storage_and_selection_fail(self) -> None:
        """Do not silently repair overwrite, missing identity, or out-of-order selection."""
        box=Mailbox(2); box.admit(1,{'id':'a'})
        for action in (lambda:box.admit(1,{}), lambda:box.admit(2,{}), lambda:box.select(1,1),
                       lambda:box.retire(0,received=True,dispatched=True,directive=0,phase_boundary=False,event='bad')):
            with self.assertRaises(ValueError): action()
        box.retire(1,received=True,dispatched=True,directive=1,phase_boundary=False,event='postpone')
        with self.assertRaises(ValueError): box.select(1,0)

    def test_generated_layout_and_envelopes(self) -> None:
        """Offsets follow declared packed order; unsupported syntax and overflow are rejected."""
        layout=packed_layout('type Flags = bits[3]; enum Mode : u2 { A = 0 } pub struct Request { slot: u32, mode: Mode, flags: Flags, frame: axis::Frame, }','Request')
        self.assertEqual(layout['width'],165)
        self.assertEqual(decode((7<<133)|(2<<131)|(5<<128)|123,layout),{'slot':7,'mode':2,'flags':5,'frame':123})
        with self.assertRaises(ValueError): decode(1<<165,layout)
        with self.assertRaises(ValueError): packed_layout('','Unknown<4>')
        self.assertEqual(frame((9<<129)|(123<<1),161),123)
        self.assertEqual(frame_from_ram((123<<32)|0x78563412),(0x12345678<<96)|123)
        with self.assertRaises(ValueError): frame_from_ram(1<<128)
        with self.assertRaises(ValueError): frame(123,33)

    def test_physical_stride_preserves_old_profiles(self) -> None:
        """Logical capacity does not silently change the physical addresses of saved traces."""
        generated = 'mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH)'
        self.assertEqual(mailbox_stride('', 24, 6), 24)
        self.assertEqual(mailbox_stride(generated, 24, 6), 32)
        self.assertEqual(mailbox_stride(generated, 24, 5), 24)
        self.assertEqual(mailbox_stride(generated, 1, 1), 1)

    def replay_fixture(self) -> tuple[Streams, dict]:
        """Construct two equal messages and three independently observed executor transactions."""
        request=packed_layout('struct R { slot:u32, frame:axis::Frame, received:u1, mailbox_index:u8, order_index:u8, }','R')
        result=packed_layout('struct R { slot:u32, dispatched:u1, directive:u2, phase_boundary:u1, received:u1, mailbox_index:u8, order_index:u8, }','R')
        def value(layout: dict, **fields: int) -> int:
            """Pack independently supplied fixture fields using the declared field offsets."""
            return sum(v << layout['fields'][k]['offset'] for k,v in fields.items())
        payloads={0:[(0,111<<1),(8,111<<1)],1:[(8,111<<32),(16,(1<<128)|(111<<32))],
                  2:[(24,0),(48,1),(72,0)],
                  3:[(32,value(request,frame=111,received=1)),
                     (56,value(request,frame=111,received=1,mailbox_index=1,order_index=1)),
                     (80,value(request,frame=111,received=1))],
                  5:[(32,111<<32),(56,111<<32),(80,111<<32)],
                  4:[(40,value(result,received=1,dispatched=1,directive=1)),
                     (64,value(result,received=1,dispatched=1,mailbox_index=1,order_index=1,phase_boundary=1)),
                     (88,value(result,received=1,dispatched=1))]}
        streams=Streams.__new__(Streams)
        streams.inputs={'device_periods_ns':[8]}; streams.capture_end=96
        streams.channels={(0,c):{'width':w,'role':'mailbox','channel':str(c)}
                          for c,w in enumerate([161,160,32,request['width'],result['width'],128])}
        streams.messages={(0,c):[{'ts':t,'value':v,'mask':(1<<streams.channels[0,c]['width'])-1} for t,v in values]
                          for c,values in payloads.items()}
        works=[{'id':f'work{i}','track':'D0/bank0/0/work','name':'work','ts':t,'dur':16,'args':{'slot':0}}
               for i,t in enumerate([32,56,80])]
        streams.graph={'tracks':[],'events':works,'edges':[],'resource_dependencies':[]}
        streams.events={e['id']:e for e in works}; streams.tracks=set(); streams.checked=set(); streams.relations={}
        streams.parents={}; streams.memo={}; streams.tail_roots={}; streams.roots={(0,0):'startup'}; streams.remote={}
        layout={'capacity':2,'service':{'_startup_in':0,'_mailbox_write_req_out':1,'_mailbox_read_req_out':2,'_mailbox_read_resp_in':5},
                'executor':{'_request_in':3,'_result_out':4},'layouts':{'request':request,'result':result}}
        return streams,layout

    def test_replay_connects_retried_identity_and_phase_release(self) -> None:
        """A complete bank replay connects two equal messages to the right three dispatches."""
        streams,layout=self.replay_fixture()
        counts=extend_bank(streams,0,0,[{'slot':0,'name':'actor'}],layout)
        self.assertEqual({k:counts[k] for k in ('admitted','consumed','postponed','retried','pending_mailbox_tail')},
                         {'admitted':2,'consumed':2,'postponed':1,'retried':1,'pending_mailbox_tail':0})
        mail=[e for e in streams.graph['edges'] if e['kind']=='ordinary message']
        self.assertEqual([(e['source'],e['target']) for e in mail],
            [('mail/D0/bank0/read0','work0'),('mail/D0/bank0/read1','work1'),('mail/D0/bank0/read2','work2')])
        self.assertEqual([streams.events[f'mail/D0/bank0/read{i}']['args']['message'] for i in range(3)],
                         ['mail/D0/bank0/write0','mail/D0/bank0/write1','mail/D0/bank0/write0'])
        self.assertTrue(any(e['source']=='work1' and e['target']=='work2' and e['kind']=='postponed message released'
                            for e in streams.graph['edges']))

    def test_replay_uses_physical_stride_between_actors(self) -> None:
        """RAM padding changes addresses, not logical capacity or per-actor message identity."""
        streams, layout = self.replay_fixture()
        layout.update(capacity=3, stride=4)
        for record in streams.messages[0, 0]:
            record['value'] |= 1 << 129
        for record in streams.messages[0, 1]:
            record['value'] += 4 << 128
        for record in streams.messages[0, 2]:
            record['value'] += 4
        for port, kind in ((3, 'request'), (4, 'result')):
            for record in streams.messages[0, port]:
                record['value'] |= 1 << layout['layouts'][kind]['fields']['slot']['offset']
        for event in streams.graph['events']:
            event['args']['slot'] = 1
            event['track'] = 'D0/bank0/1/work'
        counts = extend_bank(streams, 0, 0, [{'slot': 1, 'name': 'actor'}], layout)
        self.assertEqual(counts['admitted'], 2)
        self.assertEqual(counts['consumed'], 2)
        self.assertEqual(streams.events['mail/D0/bank0/write0']['args']['slot'], 1)

    def test_ignored_frame_does_not_cause_actor_work(self) -> None:
        """Speculative reading leaves storage intact and adds no message-to-activation edge."""
        streams,layout=self.replay_fixture()
        def packed(kind: str, **fields: int) -> int:
            """Encode the fixture's independently selected outcomes and row addresses."""
            return sum(v << layout['layouts'][kind]['fields'][k]['offset'] for k,v in fields.items())
        streams.messages[0,2][1]['value']=0
        streams.messages[0,2][2]['value']=1
        streams.messages[0,3][1]['value']=packed('request',frame=111,received=1)
        streams.messages[0,3][2]['value']=packed('request',frame=111,received=1,mailbox_index=1)
        streams.messages[0,4][0]['value']=packed('result',received=1,dispatched=0)
        streams.messages[0,4][1]['value']=packed('result',received=1,dispatched=1,phase_boundary=1)
        streams.messages[0,4][2]['value']=packed('result',received=1,dispatched=1,mailbox_index=1)
        counts=extend_bank(streams,0,0,[{'slot':0,'name':'actor'}],layout)
        self.assertEqual(counts['unused_speculative_reads'],1)
        self.assertEqual(counts['consumed'],2)
        self.assertEqual([e['target'] for e in streams.graph['edges'] if e['kind']=='ordinary message'],['work1','work2'])
        self.assertEqual(streams.events['work1']['args']['mailbox']['attempt'],1)

    def test_phase_release_merges_existing_state_dependency(self) -> None:
        """Extra causal evidence must not duplicate the same pair of event endpoints."""
        streams=Streams.__new__(Streams)
        source={'id':'a','ts':0,'dur':8}; target={'id':'b','ts':16,'dur':8}
        existing={'source':'a','target':'b','kind':'actor state','evidence':'same actor'}
        streams.graph={'edges':[existing],'resource_dependencies':[]}
        streams.relations={('a','b'):existing}
        streams.edge(source,target,'postponed message released','phase changed')
        self.assertEqual(len(streams.graph['edges']),1)
        self.assertEqual(existing['additional_evidence'],[{'kind':'postponed message released','evidence':'phase changed'}])

    def test_stream_ordinals_and_corruption(self) -> None:
        """Equal payloads preserve observed source ordinals; changed words or reversed time fail."""
        streams=Streams.__new__(Streams)
        streams.channels={(0,c):{'width':128} for c in (1,2,3)}
        streams.messages={(0,1):[{'ts':1,'value':7,'mask':(1<<128)-1}],
                          (0,2):[{'ts':2,'value':7,'mask':(1<<128)-1}],
                          (0,3):[{'ts':3,'value':7,'mask':(1<<128)-1},{'ts':4,'value':7,'mask':(1<<128)-1}]}
        streams.parents={}; streams.checked=set()
        streams.bind(0,3,[(2,0),(1,0)],'mux')
        self.assertEqual(streams.parents[0,3][0],[(2,0),(1,0)])
        streams.parents={}; streams.messages[0,3][1]['value']=9
        with self.assertRaises(ValueError): streams.bind(0,3,[(2,0),(1,0)],'mux')
        streams.messages[0,3][1]['value']=7; streams.messages[0,1][0]['ts']=5
        with self.assertRaises(ValueError): streams.bind(0,3,[(2,0),(1,0)],'mux')

    def test_remote_ordinary_boundary_accounting(self) -> None:
        """Separate upstream forwarding from admission and selection with one shared population."""
        chain = [{'id':str(i),'ts':t,'track':'boundary','name':name}
                 for i,(t,name) in enumerate([(0,'ordinary peer frame complete'),
                    (16,'receive queue accepts frame'),(48,'scheduler accepts request'),(56,'admitted')])]
        events={e['id']:e for e in chain}
        incoming=defaultdict(list,{str(i):[{'source':str(i-1)}] for i in range(1,4)})
        values=remote_intervals(chain[-1],{'ts':64},events,incoming)
        self.assertEqual(values,{'peer_complete_to_receive_queue':16,'receive_queue_to_scheduler':32,
                                'scheduler_to_admission':8,'admission_to_first_selection':8})
        with self.assertRaisesRegex(ValueError,'partition elapsed'):
            remote_intervals(chain[-1],{'ts':55},events,incoming)
        chain[0]['name']='local effect'
        self.assertIsNone(remote_intervals(chain[-1],{'ts':64},events,incoming))

    def test_ingress_ordinals_and_wrapping(self) -> None:
        """Reconstruct duplicate frames through the fused root by accepted ordinals, not values."""
        streams=Streams.__new__(Streams)
        streams.channels={(0,c):{'width':128 if c<3 else 161} for c in (1,2,3)}
        streams.messages={(0,1):[{'ts':8,'value':7,'mask':(1<<128)-1}],
                          (0,2):[{'ts':0,'value':7,'mask':(1<<128)-1}],
                          (0,3):[{'ts':t,'value':(3<<129)|(7<<1),'mask':(1<<161)-1} for t in (16,24)]}
        streams.parents={}; streams.checked=set(); streams.tail_roots={}; streams.capture_end=32
        streams.manifests={0:{'resources':[]}}
        streams.instances={0:{():{'module':'__device__SchedulerIngress7_3_next',
            'ports':{'_frame_0':1,'_frame_1':2,'_request_out':3}}}}
        streams.bind_device(0)
        self.assertEqual(streams.parents[0,3][0],[(2,0),(1,0)])
        streams.parents={}; streams.messages[0,3][1]['value'] ^= 2
        with self.assertRaisesRegex(ValueError,'changed frame identity'):
            streams.bind_device(0)
        streams.messages[0,1][0]['ts']=0
        with self.assertRaisesRegex(ValueError,'two inputs in one clock'):
            streams.bind_device(0)

    def test_parallel_effects_bypass_ordinary_router(self) -> None:
        """Concurrent reduction publications cannot become the ordinary tail's stream ancestor."""
        streams=Streams.__new__(Streams)
        streams.channels={(0,c):{'width':136 if c<4 else 128,'channel':name} for c,name in
            [(1,'drain/_effects'),(2,'drain/_fragment_10'),(3,'router/_egress_in'),(4,'router/_lane_11_out')]}
        values={1:[(8,(5<<128)|7)],2:[(0,9)],3:[(16,(5<<128)|7)],4:[(24,7)]}
        streams.messages={(0,c):[{'ts':t,'value':v,'mask':(1<<streams.channels[0,c]['width'])-1}
            for t,v in records] for c,records in values.items()}
        streams.effects={(0,c,t):{'args':{'actor':'actor'}} for c,t in [(1,8),(2,0)]}
        streams.parents={}; streams.checked=set(); streams.tail_roots={}; streams.capture_end=32
        streams.manifests={0:{'resources':[]}}
        streams.instances={0:{():{'module':'__device__Router7_0_next',
            'ports':{'_egress_in':3,'_lane_11_out':4}}}}
        streams.route={'actors':[{'device':0,'index':7,'name':'actor'}],
            'lanes':[{'source':'actor','id':10,'ports':[0]}, {'source':'actor','id':11,'ports':[5]}]}
        streams.bind_device(0)
        self.assertEqual(streams.parents[0,3][0],[(1,0)])
        self.assertEqual(streams.parents[0,4][0],[(3,0)])
        self.assertNotIn((0,2),streams.parents)

    def test_missing_source_only_at_capture_frontier(self) -> None:
        """Missing interior acceptance fails; an unobserved final edge remains an explicit boundary."""
        streams=Streams.__new__(Streams)
        streams.channels={(0,c):{'width':128} for c in (1,2)}
        streams.messages={(0,1):[],(0,2):[{'ts':8,'value':7,'mask':(1<<128)-1}]}
        streams.parents={}; streams.checked=set(); streams.tail_roots={}; streams.capture_end=16
        with self.assertRaises(ValueError): streams.bind(0,2,[],'FIFO')
        streams.messages[0,2][0]['ts']=16
        streams.bind(0,2,[],'FIFO')
        self.assertIn((0,2,0),streams.tail_roots)

    def test_control_geometry_and_schema(self) -> None:
        """Host broadcast fan-out follows inclusive coordinates, target membership and payload shape."""
        value=(1<<178)|(2<<162)|(4<<146)|(5<<130)|(1<<128)|(2<<120)|(13<<96)
        targets=[{'id':'noise','selector':1,'encodings':[{'op':13,'words':2}]}]
        self.assertTrue(control_select(value,{'point':[4,5],'targets':['noise']},targets))
        self.assertFalse(control_select(value,{'point':[4,6],'targets':['noise']},targets))
        self.assertFalse(control_select(value,{'point':[4,5],'targets':['data']},targets))
        self.assertFalse(control_select(value^(1<<120),{'point':[4,5],'targets':['noise']},targets))


if __name__=='__main__':
    unittest.main()
