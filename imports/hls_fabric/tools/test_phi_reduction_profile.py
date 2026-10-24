#!/usr/bin/env python3
"""Check causal attribution from fragment queues through one completed actor window."""
import json
from pathlib import Path
import tempfile
import unittest

from phi_reduction_profile import extend, aggregate_handoffs
from backend_commands import digest


def fixture(stage: Path) -> tuple[dict, dict, dict, dict]:
    """Four staggered arrivals join an earlier opening and reach a later executor request."""
    opened = {'status': 1, 'site': 0, 'key': 7}
    profile = {'metadata': {'clock_period_ns': 8, 'reset_release_ns': 0, 'capture_cycles': 20},
        'tracks': [], 'edges': [], 'counters': [], 'events': [
            {'id': 'open', 'track': '0/work', 'name': 'phase transition + entry', 'ts': 0, 'dur': 8,
             'args': {'actor': 'phi0', 'reduction_before': {**opened, 'status': 0}, 'reduction_after': opened}},
            {'id': 'complete', 'track': '0/work', 'name': 'aggregate completion', 'ts': 80, 'dur': 16,
             'args': {'actor': 'phi0', 'reduction_before': opened, 'reduction_after': {**opened, 'status': 0}}}]}
    resources = {(0, 100): {'id': 100, 'kind': 'actor', 'module': 'phi_halo_cell', 'name': 'phi0'}}
    histories = {}
    for ident, port, cycle in [(0, '_opened', 2), (1, '_aggregate', 7),
                              *[(2+i, f'_frame_{i}', 6) for i in range(4)],
                              *[(10+i, f'push{i}', 2+i) for i in range(4)], (14, 'open_push', 2)]:
        resources[0, ident] = {'id': ident, 'kind': 'channel',
            'name': f'__ReductionCollector8_0__0_next_inst/{port}' if ident < 6 else port}
        histories[0, ident] = [{'cycle': 0, 'value': 0}, {'cycle': cycle, 'value': 3}, {'cycle': cycle+1, 'value': 0}]
    for i in range(4):
        resources[0, 20+i] = {'id': 20+i, 'kind': 'fifo', 'pop': 2+i, 'push': 10+i, 'capacity': 2}
        histories[0, 20+i] = [{'time_ns': 0, 'occupancy': 0},
            {'time_ns': 8*(3+i), 'occupancy': 1}, {'time_ns': 56, 'occupancy': 0}]
    resources[0, 30] = {'id': 30, 'kind': 'fifo', 'pop': 0, 'push': 14}
    for ident, port, cycle in [(31, '_incoming__0', 8), (32, '_outgoing', 9), (33, '_aggregate_in', 9)]:
        resources[0, ident] = {'id': ident, 'kind': 'channel',
            'name': ('__actor_ReductionMux_0__1_next_inst/' if ident < 33 else 'service/')+port}
        histories[0, ident] = [{'cycle': 0, 'value': 0}, {'cycle': cycle, 'value': 3}, {'cycle': cycle+1, 'value': 0}]
    resources[0, 34] = {'id': 34, 'kind': 'fifo', 'push': 1, 'pop': 31, 'capacity': 1}
    resources[0, 35] = {'id': 35, 'kind': 'fifo', 'push': 32, 'pop': 33, 'capacity': 1}
    (stage/'device0-manifest.json').write_text('{}')
    (stage/'device0-reduction-bindings.json').write_text(json.dumps({
        'manifest_sha256': digest(stage/'device0-manifest.json'), 'actors': [{'name': 'phi0', 'index': 8}]}))
    return profile, {'window_ns': [0, 200]}, resources, histories


class ReductionProfileTest(unittest.TestCase):
    """Recorded identities and temporal order must support every added dependency."""

    def test_complete_handoff(self) -> None:
        """Separate arrival spread, collection delay and scheduler wait without another simulation."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            profile, report, resources, histories = fixture(stage)
            extend(profile, report, stage, 0, resources, histories)
            result = report['reduction_handoffs']
            self.assertEqual(result['completed_windows'], 1)
            self.assertEqual(result['durations_ns']['last_fragment_to_aggregate_ns']['mean'], 16)
            self.assertEqual(result['durations_ns']['aggregate_to_executor_request_ns']['mean'], 24)
            self.assertEqual(result['durations_ns']['fragment_arrival_span_ns']['mean'], 24)
            self.assertEqual(len(profile['edges']), 10)
            self.assertEqual([result['durations_ns'][key]['mean'] for key in
                ('aggregate_queue_to_mux_ns','aggregate_mux_forward_ns','aggregate_mux_to_scheduler_ns',
                 'aggregate_scheduler_to_executor_ns')], [8,8,0,8])
            self.assertEqual([c['value'] for c in profile['counters'] if c['track'] == '0/fragment0'], [0, 1, 0])
            self.assertEqual(len(profile['counters']), 12)

    def test_same_cycle_aggregate_forwarding(self) -> None:
        """A shorter mux keeps the same causal identity even when intermediate acceptances coincide."""
        with tempfile.TemporaryDirectory() as directory:
            stage=Path(directory)
            profile,report,resources,histories=fixture(stage)
            for port in (32,33):
                histories[0,port][1]['cycle']=8
                histories[0,port][2]['cycle']=9
            extend(profile,report,stage,0,resources,histories)
            self.assertEqual(report['reduction_handoffs']['durations_ns']['aggregate_mux_forward_ns']['mean'],0)
            chain=[e for e in profile['edges'] if e['kind'].startswith('aggregate')]
            self.assertEqual([e['kind'] for e in chain],['aggregate queue','aggregate mux','aggregate capture','aggregate'])

    def test_mux_cannot_forward_before_selection(self) -> None:
        """Reject a capture that forwards an aggregate before accepting its mux input."""
        with tempfile.TemporaryDirectory() as directory:
            stage=Path(directory)
            profile,report,resources,histories=fixture(stage)
            histories[0,32][1]['cycle']=7
            histories[0,32][2]['cycle']=8
            with self.assertRaisesRegex(ValueError,'FIFO order'):
                extend(profile,report,stage,0,resources,histories)

    def test_mux_duplicate_grants_fail(self) -> None:
        """One mux output cannot explain two input acceptances on the same clock."""
        with tempfile.TemporaryDirectory() as directory:
            stage=Path(directory)
            profile,report,resources,histories=fixture(stage)
            resources[0,36]={'id':36,'kind':'channel','name':'__actor_ReductionMux_0__1_next_inst/_incoming__1'}
            histories[0,36]=histories[0,31]
            with self.assertRaisesRegex(ValueError,'multiple inputs'):
                extend(profile,report,stage,0,resources,histories)

    def test_window_identity_mismatch(self) -> None:
        """An ordinal match is insufficient when the committed key differs."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            profile, report, resources, histories = fixture(stage)
            profile['events'][1]['args']['reduction_before'] = {'status': 1, 'site': 0, 'key': 8}
            with self.assertRaisesRegex(ValueError, 'opening window'):
                extend(profile, report, stage, 0, resources, histories)

    def test_binding_from_another_recording(self) -> None:
        """Do not reuse collector identities after the hardware catalog changes."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            profile, report, resources, histories = fixture(stage)
            (stage/'device0-manifest.json').write_text('{"changed":true}')
            with self.assertRaisesRegex(ValueError, 'another recording'):
                extend(profile, report, stage, 0, resources, histories)

    def test_fragment_cannot_arrive_after_collection(self) -> None:
        """Reject a capture that would require a queue to produce an unaccepted frame."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            profile, report, resources, histories = fixture(stage)
            histories[0, 10][1]['cycle'] = 8
            histories[0, 10][2]['cycle'] = 9
            with self.assertRaisesRegex(ValueError, 'bounded queue'):
                extend(profile, report, stage, 0, resources, histories)


if __name__ == '__main__':
    unittest.main()
