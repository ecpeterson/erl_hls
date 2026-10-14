#!/usr/bin/env python3
"""Validate actor attribution against a four-slot, independently timed observation fixture."""
import gzip
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from phi_actor_profile import reconstruct, classify, extract


def fixture(stage: Path) -> tuple[dict, dict]:
    """Four consecutive executor requests each publish a four-effect batch with a final credit."""
    resources, histories = {}, {}
    fields = {'status': (56, 2), 'site': (58, 2), 'key': (60, 32), 'remaining': (92, 3), 'failure': (95, 16)}
    def channel(ident: int, name: str, transfers: list[int]) -> None:
        """Encode ready/valid on every clock; the adapter must count adjacent handshakes."""
        resources[0, ident] = {'id': ident, 'kind': 'channel', 'name': name}
        histories[0, ident] = [{'cycle': c, 'time_ns': 8*c, 'value': 3 if c in transfers else 2} for c in range(30)]
    for i in range(4):
        channel(i, 'phi_halo_cell/__SharedExecutor_0_next_inst/_request_in' if i == 1 else f'executor{i}',
                list(range(8+i//2, 12+i//2)))
    for ident, name, push, pop in ((20, 'executor_request', 0, 1), (21, 'executor_result', 2, 3)):
        resources[0, ident] = {'id': ident, 'kind': 'fifo', 'name': f'phi_halo_cell/fifo__{name}_', 'push': push, 'pop': pop}
    for slot in range(4):
        ident, cycle = 100+slot, 10+slot
        resources[0, ident] = {'id': ident, 'kind': 'actor', 'slot': slot, 'module': 'phi_halo_cell', 'name': f'phi{slot}',
                              'reduction': {'fields': {n: {'observation_offset': o, 'width': w} for n,(o,w) in fields.items()}}}
        initial = {'cycle': slot+1, 'time_ns': 8*(slot+1), 'value': 1 << 25, 'phase': 'configuring', 'state_write': True,
                   'message_queue_len': 0, 'waiting_for_egress': False, 'in_flight': False}
        histories[0, ident] = [initial, {**initial, 'cycle': cycle, 'time_ns': 8*cycle, 'phase': 'gathering',
                                       'value': (1 << 25) | (1 << 56) | (4 << 92)}]
        for offset, name, transfers in ((0, '_batches', [cycle]), (1, '_credits', [cycle+4]), (2, '_effects', list(range(cycle+1,cycle+5)))):
            channel(30+3*slot+offset, f'phi_halo_cell_ActorOutboxDrain_0__{slot}_next_inst/{name}', transfers)
    (stage/'activity.log').write_text('232 0 29 0\n')
    (stage/'profile-inputs.json').write_text(json.dumps({'device_periods_ns': [8]}))
    (stage/'service.json').write_text(json.dumps({'window_ns': [0, 240]}))
    (stage/'device0-manifest.json').write_text('{}')
    (stage/'trace.csv').write_text('fixture')
    return resources, histories


class ActorProfileTest(unittest.TestCase):
    """Attribution must conserve transactions and reject a changed timing relationship."""

    def test_extract_survives_lossless_compression(self) -> None:
        """Raw and compressed source recordings reuse the same checked device subset."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            raw = stage/'cycle-trace.csv'
            raw.write_text('time_ns,device,id,value\n8,0,2,3\n9,1,2,3\n')
            result = extract(stage,0)
            packed = raw.with_suffix('.csv.gz')
            packed.write_bytes(gzip.compress(raw.read_bytes()))
            raw.unlink()
            self.assertEqual(extract(stage,0), result)
            self.assertEqual(gzip.decompress(result.read_bytes()), b'time_ns,device,id,value\n8,0,2,3\n')
            packed.write_bytes(gzip.compress(b'time_ns,device,id,value\n8,0,2,2\n'))
            with self.assertRaisesRegex(ValueError,'capture changed'):
                extract(stage,0)

    def test_four_actor_pipeline(self) -> None:
        """Four actors overlap while each batch drains in four consecutive cycles."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            data = fixture(stage)
            with patch('phi_actor_profile.read', return_value=data):
                profile, report = reconstruct(stage, 0, stage/'trace.csv')
            self.assertEqual(report['state_writes'], 4)
            self.assertEqual(report['executor_requests'], 4)
            self.assertEqual(report['durations_ns']['outbox_drain_ns']['histogram'], {32: 4})
            self.assertEqual(len(profile['events']), 24)
            self.assertEqual(len(profile['edges']), 4)

    def test_parallel_effects_keep_separate_identities(self) -> None:
        """Four same-cycle lane acceptances remain four effects owned by one batch."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            for slot in range(4):
                stem = f'phi_halo_cell_ParallelActorOutboxDrainB0S{slot}_0_next_inst/'
                for offset, name in enumerate(('_batches', '_credits', '_effects')):
                    ident = 30+3*slot+offset
                    resources[0, ident]['name'] = stem+name
                    if name == '_effects':
                        for sample in histories[0, ident]:
                            sample['value'] = 2
                for lane in range(4):
                    ident = 300+10*slot+lane
                    resources[0, ident] = {'id': ident, 'kind': 'channel', 'name': stem+f'_fragment_{lane}'}
                    histories[0, ident] = [{'cycle': c, 'time_ns': 8*c, 'value': 3 if c == 11+slot else 2} for c in range(30)]
            with patch('phi_actor_profile.read', return_value=(resources, histories)):
                graph, _ = reconstruct(stage, 0, stage/'trace.csv')
            effects = [e for e in graph['events'] if e['track'].endswith('/effect')]
            self.assertEqual(len(effects), 16)
            first = [e for e in effects if e['track'].startswith('0/')]
            self.assertEqual({e['ts'] for e in first}, {88})
            self.assertEqual(len({e['args']['channel'] for e in first}), 4)
            self.assertEqual(len({e['track'] for e in first}), 4)
            self.assertTrue({e['track'] for e in effects} <= {t['id'] for t in graph['tracks']})
            self.assertTrue(all(e['args']['parallel_publication'] for e in effects))
            self.assertFalse(any(edge['source'] in {e['id'] for e in effects} for edge in graph['edges']))

    def test_changed_executor_latency(self) -> None:
        """A moved request invalidates attribution rather than silently assigning it to another actor."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            for ident in (0, 1):
                histories[0, ident][8]['value'] = 2
                histories[0, ident][7]['value'] = 3
            with patch('phi_actor_profile.read', return_value=(resources, histories)), self.assertRaisesRegex(ValueError, 'executor timing'):
                reconstruct(stage, 0, stage/'trace.csv')

    def test_registered_publication(self) -> None:
        """A second publication clock preserves actor/batch identity only under an explicit checked model."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            for slot in range(4):
                sample = histories[0, 100+slot][1]
                sample.update(cycle=sample['cycle']+1, time_ns=sample['time_ns']+8)
                for ident in range(30+3*slot, 33+3*slot):
                    for sample in histories[0, ident]:
                        sample.update(cycle=sample['cycle']+1, time_ns=sample['time_ns']+8)
                    histories[0, ident].insert(0, {'cycle': 0, 'time_ns': 0, 'value': 2})
            with patch('phi_actor_profile.read', return_value=(resources, histories)):
                with self.assertRaisesRegex(ValueError, 'executor timing'):
                    reconstruct(stage, 0, stage/'trace.csv')
                graph, _ = reconstruct(stage, 0, stage/'trace.csv', publication_cycles=2)
                work = [e for e in graph['events'] if e['track'].endswith('/work')]
                self.assertEqual([e['dur'] for e in work], [24]*4)
                self.assertEqual([e['args']['slot'] for e in work], list(range(4)))
                self.assertEqual(graph['metadata']['checked_publication_cycles'], 2)
                for edge in graph['edges']:
                    source = next(e for e in graph['events'] if e['id'] == edge['source'])
                    target = next(e for e in graph['events'] if e['id'] == edge['target'])
                    self.assertLessEqual(source['ts']+source['dur'], target['ts'])
                histories[0, 102][1]['cycle'] += 1
                with self.assertRaisesRegex(ValueError, 'executor timing'):
                    reconstruct(stage, 0, stage/'trace.csv', publication_cycles=2)

    def test_unowned_effect(self) -> None:
        """An extra transfer between batches must not disappear from the accounting."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            histories[0, 32][20]['value'] = 3
            with patch('phi_actor_profile.read', return_value=(resources, histories)), self.assertRaisesRegex(ValueError, 'outside any outbox batch'):
                reconstruct(stage, 0, stage/'trace.csv')

    def test_credit_before_last_effect(self) -> None:
        """The slot credit must correspond to the last effect of that batch."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            histories[0, 31][14]['value'] = 2
            histories[0, 31][15]['value'] = 3
            with patch('phi_actor_profile.read', return_value=(resources, histories)), self.assertRaisesRegex(ValueError, 'final accepted effect'):
                reconstruct(stage, 0, stage/'trace.csv')

    def test_independent_scheduler_slots(self) -> None:
        """Two schedulers retire the same local slot on the same clock without merging identities."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            del resources[0, 20], resources[0, 21], resources[0, 1]
            for bank in range(2):
                for port in range(4):
                    ident = 200+bank*10+port
                    cycles = [8+port//2, 9+port//2]
                    resources[0, ident] = {'id': ident, 'kind': 'channel', 'name': (f'phi_halo_cell__SharedService_{bank}/__SharedExecutor_0/_request_in'
                                 if port == 1 else f'executor{bank}/{port}')}
                    histories[0, ident] = [{'cycle': c, 'time_ns': 8*c, 'value': 3 if c in cycles else 2} for c in range(30)]
                for port, suffix in enumerate(('request', 'result')):
                    ident = 204+bank*10+port
                    resources[0, ident] = {'id': ident, 'kind': 'fifo',
                        'name': f'phi_halo_cell__SharedService_{bank}/fifo__executor_{suffix}_',
                        'push': 200+bank*10+2*port, 'pop': 201+bank*10+2*port}
                for slot in range(2):
                    actor = 2*bank+slot
                    resource = resources[0, 100+actor]
                    resource.update(bank=bank, slot=slot)
                    histories[0, 100+actor][1].update(cycle=10+slot, time_ns=8*(10+slot))
                    for port, name in enumerate(('_batches', '_credits', '_effects')):
                        ident = 30+3*actor+port
                        resources[0, ident]['name'] = f'outbox{bank}/phi_halo_cell_ActorOutboxDrain_0__{slot}_next_inst/{name}'
                        transfers = {s['cycle']-2*bank for s in histories[0, ident] if s['value'] == 3}
                        for sample in histories[0, ident]:
                            sample['value'] = 3 if sample['cycle'] in transfers else 2
            with patch('phi_actor_profile.read', return_value=(resources, histories)):
                graph, report = reconstruct(stage, 0, stage/'trace.csv')
            self.assertEqual(len(report['scheduler_groups']), 2)
            self.assertEqual(report['slots'], 4)
            self.assertNotIn('bank', report)
            self.assertEqual(report['state_writes'], 4)
            self.assertEqual(len(graph['events']), 24)
            self.assertEqual(len({e['id'] for e in graph['events']}), 24)
            self.assertEqual(len({t['id'] for t in graph['tracks']}), 12)

    def test_final_effect_held_after_credit(self) -> None:
        """Releasing batch storage does not erase the last word held in the output register."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            for cycle in range(14, 17):
                histories[0, 32][cycle]['value'] = 1
            histories[0, 32][17]['value'] = 3
            with patch('phi_actor_profile.read', return_value=(resources, histories)):
                graph, report = reconstruct(stage, 0, stage/'trace.csv')
            batch = next(e for e in graph['events'] if e['id'] == 'D0/outbox0/0')
            self.assertEqual(batch['args']['effect_cycles'], [11, 12, 13, 17])
            self.assertEqual(batch['args']['credit_cycle'], 14)
            self.assertEqual(report['durations_ns']['last_effect_after_credit_ns']['worst'], 24)

    def test_credit_held_after_final_effect(self) -> None:
        """A backpressured credit remains continuously offered after the final output transfer."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            resources, histories = fixture(stage)
            histories[0, 31][14]['value'] = 1
            histories[0, 31][15]['value'] = 3
            with patch('phi_actor_profile.read', return_value=(resources, histories)):
                graph, _ = reconstruct(stage, 0, stage/'trace.csv')
            batch = next(e for e in graph['events'] if e['id'] == 'D0/outbox0/0')
            self.assertEqual(batch['args']['last_effect_cycle'], 14)
            self.assertEqual(batch['args']['credit_cycle'], 15)

    def test_aggregate_window_transition(self) -> None:
        """An atomic window replacement is completion work, not four fictitious contribution visits."""
        before = {'status': 1, 'key': 8, 'site': 0, 'remaining': 4}
        self.assertEqual(classify(before, {**before, 'key': 9}, 'gathering', 'gathering'),
                         'aggregate completion + entry')
        self.assertEqual(classify(before, {**before, 'remaining': 3}, 'gathering', 'gathering'),
                         'contribution')


def load_tests(loader: unittest.TestLoader, tests: unittest.TestSuite,
               pattern: str | None) -> unittest.TestSuite:
    """Run progress attribution alongside actor reconstruction in the existing CI entry point."""
    from test_phi_profile_phases import ProgressTests
    tests.addTests(loader.loadTestsFromTestCase(ProgressTests))
    return tests


if __name__ == '__main__':
    unittest.main()
