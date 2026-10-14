#!/usr/bin/env python3
"""Check that local progress attribution conserves time and exposes missing evidence."""
from pathlib import Path
import tempfile
import unittest

from phi_reduction_profile import extend as reductions
from phi_profile_phases import boundary_bins, handoffs, intervals
from test_phi_reduction_profile import fixture as reduction_fixture


def fixture(stage: Path) -> tuple[dict, dict, dict]:
    """One complete collector follows four queued fragments and an ordinary opening activation."""
    profile, report, resources, histories = reduction_fixture(stage)
    resources[0, 100]['bank'] = 0
    for e, request, result in zip(profile['events'], (0, 10), (0, 11)):
        e['args'].update(request_cycle=request, result_cycle=result)
    reductions(profile, report, stage, 0, resources, histories)
    for ident, name, cycles in ((31, 'mux_pop', [8]), (32, 'phi_halo_cell/scheduler/_aggregate_in', [9]),
                                (33, 'phi_halo_cell/scheduler/_ram_read_req_out', [0, 9]),
                                (34, 'phi_halo_cell/scheduler/__SharedExecutor_0_next_inst/_request_in', [0, 10])):
        resources[0, ident] = {'kind': 'channel', 'id': ident, 'name': name}
        histories[0, ident] = ([{'cycle': 0, 'value': 0}] if cycles[0] else [])+sorted([{'cycle': c, 'value': value}
            for cycle in cycles for c, value in ((cycle, 3), (cycle+1, 0))], key=lambda s: s['cycle'])
    resources[0, 35] = {'kind': 'fifo', 'id': 35, 'name': 'aggregate_queue', 'push': 1, 'pop': 31, 'capacity': 1}
    resources[0, 36] = {'kind': 'fifo', 'id': 36, 'name': 'phi_halo_cell/scheduler/fifo__executor_request_', 'pop': 34, 'push': 34}
    for (_, ident), resource in resources.items():
        resource.setdefault('name', f'fixture{ident}')
    return profile, resources, histories


class ProgressTests(unittest.TestCase):
    """Timing identities must be supported by conserved streams, not visual proximity."""

    def test_contiguous_progress(self) -> None:
        """A completed window explains every nanosecond without counting overlapping hardware twice."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            p, resources, histories = fixture(stage)
            captures, reads = handoffs(p, resources, histories, stage, 0)
            segments, details = intervals(p, captures, reads)
            ordered = sorted(segments, key=lambda e: e['ts'])
            self.assertEqual(sum(e['dur'] for e in ordered), 96)
            self.assertTrue(all(a['ts']+a['dur'] == b['ts'] for a, b in zip(ordered, ordered[1:])))
            self.assertEqual(details['handoffs'][0]['mux_queue_ns'], 8)
            self.assertEqual(details['handoffs'][0]['scheduler_pending_ns'], 0)
            self.assertEqual(next(e for e in ordered if e['name'] == 'wait fragments 3')['dur'], 8)
            self.assertEqual(next(e for e in ordered if e['name'] == 'collect / fold')['dur'], 8)

    def test_join_bins_keep_tied_late_inputs(self) -> None:
        """Clock-width blocks keep original timestamps and label every tied last input."""
        p = {'metadata': {'clock_period_ns': 8}, 'events': [
            {'id': i, 'track': '0/'+track, 'ts': ts, 'dur': dur, 'name': i}
            for i, track, ts, dur in [('a', 'fragment0', 8, 0), ('b', 'fragment1', 16, 0),
                                    ('c', 'opening', 16, 0), ('d', 'reduction', 16, 8)]],
             'edges': [{'source': i, 'target': 'd'} for i in 'abc']}
        boundary_bins(p)
        self.assertEqual([e['dur'] for e in p['events']], [0, 0, 0, 8])
        self.assertEqual([e['name'] for e in p['events']], ['a', 'b / last required', 'c / last required', 'd'])
        self.assertEqual(p['events'][1]['display_duration_ns'], 8)

    def test_ticket_loader_ram_owner(self) -> None:
        """Follow the manifest's ticket consumer to RAM; reject an unowned read before its ticket."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            p, resources, histories = fixture(stage)
            resources[0, 33]['name'] = 'phi_halo_cell/scheduler/loader/_ram_read_req_out'
            resources[0, 40] = {'kind': 'channel', 'id': 40, 'name': 'phi_halo_cell/scheduler/loader/_tickets'}
            histories[0, 40] = [dict(s) for s in histories[0, 33]]
            resources[0, 41] = {'kind': 'fifo', 'id': 41, 'capacity': 1,
                               'name': 'phi_halo_cell/scheduler/fifo__dispatch_ticket_', 'push': 40, 'pop': 40}
            captures, reads = handoffs(p, resources, histories, stage, 0)
            self.assertEqual(sorted(reads.values()), [0, 9])
            self.assertEqual(len(captures), 1)
            histories[0, 40][-2]['cycle'] = 10
            histories[0, 40][-1]['cycle'] = 11
            with self.assertRaisesRegex(ValueError, 'loader ticket/RAM'):
                handoffs(p, resources, histories, stage, 0)

    def test_staged_ticket_ram_owner(self) -> None:
        """A ticket stage before the loader is not mistaken for the RAM owner."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            p, resources, histories = fixture(stage)
            resources[0, 36]['name'] = 'phi_halo_cell/scheduler/fifo__loaded_request_'
            resources[0, 33]['name'] = 'phi_halo_cell/scheduler/loader/_ram_read_req_out'
            for ident, owner in ((40, 'stage'), (42, 'loader')):
                resources[0, ident] = {'kind': 'channel', 'id': ident,
                                      'name': f'phi_halo_cell/scheduler/{owner}/_tickets'}
                histories[0, ident] = [dict(s) for s in histories[0, 33]]
            for ident, port, name in ((41, 40, 'dispatch_ticket'), (43, 42, 'queued_ticket')):
                resources[0, ident] = {'kind': 'fifo', 'id': ident, 'capacity': 1,
                                      'name': f'phi_halo_cell/scheduler/fifo__{name}_', 'push': port, 'pop': port}
            captures, reads = handoffs(p, resources, histories, stage, 0)
            self.assertEqual(sorted(reads.values()), [0, 9])
            self.assertEqual(len(captures), 1)

    def test_corrupt_streams_fail(self) -> None:
        """Reject phantom mux captures, backwards transfers and unmatched RAM requests."""
        for ident, cycle, message in ((32, 6, 'backwards'), (33, 12, 'RAM read'), (31, 5, 'backwards')):
            with self.subTest(ident=ident), tempfile.TemporaryDirectory() as directory:
                stage = Path(directory)
                p, resources, histories = fixture(stage)
                histories[0, ident] = [{'cycle': cycle, 'value': 3}, {'cycle': cycle+1, 'value': 0}]
                if ident == 33:
                    histories[0, ident][:0] = [{'cycle': 0, 'value': 3}, {'cycle': 1, 'value': 0}]
                elif cycle:
                    histories[0, ident].insert(0, {'cycle': 0, 'value': 0})
                with self.assertRaisesRegex(ValueError, message):
                    handoffs(p, resources, histories, stage, 0)

    def test_capture_tail_uses_actor_reservations(self) -> None:
        """Four actors may own unfinished RAM reads; a fifth unexplained request is rejected."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            p, resources, histories = fixture(stage)
            for slot in range(1, 4):
                resources[0, 100+slot] = {**resources[0, 100], 'id': 100+slot, 'name': f'phi{slot}'}
            histories[0, 33] += [{'cycle': 13, 'value': 3}, {'cycle': 17, 'value': 0}]
            _, reads = handoffs(p, resources, histories, stage, 0)
            self.assertEqual(sorted(reads.values()), [0, 9])
            histories[0, 33][-1]['cycle'] = 18
            with self.assertRaisesRegex(ValueError, 'capture tail'):
                handoffs(p, resources, histories, stage, 0)

    def test_ordinary_gap_keeps_observation_limits(self) -> None:
        """An ordinary mailbox wait can be observed empty, but is unknown without a projection."""
        p = {'metadata': {'clock_period_ns': 8, 'reset_release_ns': 0}, 'edges': [], 'events': [
            {'id': 'a', 'track': '0/work', 'ts': 0, 'dur': 16, 'args': {'actor': 'phi0', 'result_cycle': 1}},
            {'id': 'b', 'track': '0/work', 'ts': 80, 'dur': 16, 'args': {'actor': 'phi0', 'result_cycle': 11}}]}
        reads = {'a': 0, 'b': 9}
        segments, _ = intervals(p, {}, reads)
        self.assertEqual(next(e for e in segments if e['name'] == 'unattributed gap')['dur'], 56)
        obs = {'phi0': [{'time_ns': 16, 'message_queue_len': 0, 'phase': 'measuring', 'waiting_for_egress': True}]}
        segments, _ = intervals(p, {}, reads, obs)
        wait = next(e for e in segments if e['name'] == 'observed empty mailbox')
        self.assertEqual(wait['dur'], 56)
        self.assertTrue(wait['args']['outbox_reserved'])
        self.assertIn('not proof', wait['args']['evidence'])
        self.assertEqual(next(e for e in segments if e['name'] == 'state RAM read')['dur'], 8)
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            intervals(p, {}, {'a': 0, 'b': 1})


if __name__ == '__main__':
    unittest.main()
