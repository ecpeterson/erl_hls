#!/usr/bin/env python3
"""Check passive signal binding, missing-bit disclosure and ordered payload consistency."""
import json
import gzip
from pathlib import Path
import tempfile
import unittest

from phi_message_trace import alias_parts, declarations, selected_channels
from phi_message_profile import observed_effect, packet_frame, payloads, same_payload, split_cycles
from phi_message_report import intervals


class MessageTraceTests(unittest.TestCase):
    """Identical values remain distinct transactions; lost fields never become fabricated evidence."""

    def test_aliases_and_optimized_bits(self) -> None:
        """Split aliases retain their bit order and absent bits get an explicit unknown mask."""
        flat = {'payload': {'bits': [2, 3, 4, 5, '1', 9]}, 'retained': {'bits': [2, 3, 4, 5]}}
        parts = alias_parts(['payload'], {'retained[3:2]': 2, 'retained[1:0]': 2}, flat)['payload']
        self.assertEqual(parts[0], {'constant': 0, 'known': False, 'offset': 5, 'width': 1})
        self.assertEqual(parts[1], {'constant': 1, 'offset': 4, 'width': 1})
        self.assertEqual([p['name'] for p in parts[2:]], ['retained[3:2]', 'retained[1:0]'])
        self.assertEqual(sum(p['width'] for p in parts), 6)

    def test_ingress_capture_includes_every_port(self) -> None:
        """Retain the fused merger's input ordinals and its wrapped output for identity replay."""
        resources = [{'kind':'channel', 'id':i, 'name':f'__device__SchedulerIngress7_3_next_inst/{port}'}
                     for i,port in enumerate(('_frame_0','_frame_1','_request_out'))]
        self.assertEqual(set(selected_channels(resources)), {0,1,2})

    def test_parallel_outputs_include_payloads(self) -> None:
        """Every concurrent lane and the ordinary tail keep their accepted Egress values."""
        resources = [{'kind': 'channel', 'id': i, 'name': f'phi_ParallelActorOutboxDrainB2S0_0_next_inst/{port}'}
                     for i, port in enumerate(('_batches', '_credits', '_effects', '_fragment_5', '_fragment_9'))]
        self.assertEqual(selected_channels(resources), {2: 'effect', 3: 'effect', 4: 'effect'})

    def test_signal_declarations(self) -> None:
        """Only explicit net declarations define payload ranges; RTL expressions are not parsed."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'test.v'
            path.write_text('  wire [119:101] \\x[119:101] ;\n  wire \\enable ;\n  assign \\unused  = 1;\n')
            self.assertEqual(declarations(path), {'x[119:101]': 19, 'enable': 1})

    def test_accepted_duplicate_payloads_and_epochs(self) -> None:
        """Every accepted clock counts even if bytes repeat; a reset must not join unrelated windows."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            (stage/'message-bindings.json').write_text(json.dumps({'channels': [
                {'device': 0, 'id': 2, 'width': 4, 'known_mask': '0xf'}]}))
            path = stage/'message-trace.csv'
            path.write_text('time_ns,device,epoch,id,value\n8,0,0,2,3\n16,0,0,2,3\n')
            _, records = payloads(stage)
            self.assertEqual(len(records[0, 2]), 2)
            with path.open('a') as output:
                output.write('24,0,1,2,3\n')
            with self.assertRaisesRegex(ValueError, 'one reset epoch'):
                payloads(stage)

    def test_unobserved_final_edge(self) -> None:
        """A simulator stop may omit final-edge payloads, never earlier evidence."""
        item = {'id': 'effect', 'ts': 80, 'args': {'channel': 2}}
        self.assertIsNone(observed_effect(item, {}, 0, 80))
        with self.assertRaisesRegex(ValueError, 'observations disagree'):
            observed_effect(item, {}, 0, 88)
        payload = {'value': 0, 'mask': 15}
        self.assertEqual(observed_effect(item, {(0, 2, 80): payload}, 0, 80), payload)

    def test_cycle_extraction_provenance(self) -> None:
        """A changed original recording cannot reuse stale per-device observations."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            source = stage/'cycle-trace.csv'
            source.write_text('time_ns,device,id,value\n8,0,2,3\n9,1,2,3\n')
            split_cycles(stage, [0, 1])
            split_cycles(stage, [0, 1])
            source.write_text(source.read_text()+'16,0,2,3\n')
            with self.assertRaisesRegex(ValueError, 'extraction changed'):
                split_cycles(stage, [0, 1])

    def test_compressed_recording_reuses_verified_extraction(self) -> None:
        """Compression preserves capture identity; a changed decoded byte still invalidates replay."""
        with tempfile.TemporaryDirectory() as directory:
            stage=Path(directory)
            source=stage/'cycle-trace.csv'
            source.write_text('time_ns,device,id,value\n8,0,2,3\n')
            split_cycles(stage,[0])
            packed=source.with_suffix('.csv.gz')
            packed.write_bytes(gzip.compress(source.read_bytes()))
            source.unlink()
            split_cycles(stage,[0])
            packed.write_bytes(gzip.compress(b'time_ns,device,id,value\n8,0,2,2\n'))
            with self.assertRaisesRegex(ValueError,'extraction changed'):
                split_cycles(stage,[0])

    def test_elapsed_intervals(self) -> None:
        """One message's boundary intervals partition elapsed time without fabricating work."""
        chain = [{'ts': t, 'dur': d, 'track': 'actor/work' if i == 0 else 'boundary'}
                 for i, (t, d) in enumerate([(0,16), (56,0), (64,0), (72,8), (113,0), (129,0), (137,0)])]
        times = intervals(chain)
        self.assertEqual(sum(times.values()), 137)
        self.assertEqual(times['commit_to_effect_acceptance'], 40)
        chain[-1]['ts'] = 128
        with self.assertRaisesRegex(ValueError, 'partition elapsed'):
            intervals(chain)

    def test_local_limiting_handoff(self) -> None:
        """A fixed comparison window remains renderable when its latest input becomes local."""
        chain = [{'ts': 0, 'dur': 16, 'track': 'actor/work'},
                 {'ts': 24, 'dur': 0}, {'ts': 32, 'dur': 0}]
        self.assertEqual(intervals(chain), {'producer_execution_and_publication': 16,
            'commit_to_effect_acceptance': 8, 'effect_to_fragment_queue': 8})
        chain[-1]['ts'] = 16
        with self.assertRaisesRegex(ValueError, 'partition elapsed'):
            intervals(chain)

    def test_wire_frame_bit_order_and_corruption(self) -> None:
        """Transport words reconstruct the DSLX Frame layout, with no payload-value matching heuristic."""
        packet = {'credit': False, 'compact': False, 'complete': True, 'end_ns': 80,
                  'words': [0x48500000, 0x09000003, 0x12345678, 0xabcdef01, 0x1fedcba98]}
        frame = packet_frame(packet)
        self.assertEqual(frame['value'], 0x03000009fedcba98abcdef0112345678)
        same_payload(frame, {'value': 0x12345678, 'mask': 0xffffffff})
        with self.assertRaisesRegex(ValueError, 'payload mismatch'):
            same_payload(frame, {'value': 0x12345679, 'mask': 0xffffffff})
        with self.assertRaisesRegex(ValueError, 'complete full-format'):
            packet_frame({**packet, 'complete': False})


if __name__ == '__main__':
    unittest.main()
