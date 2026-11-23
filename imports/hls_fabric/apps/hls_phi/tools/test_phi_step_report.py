"""Whole-step accounting must retain causality, ties and independently decoded status identity."""
import phi_tool_paths  # Resolve shared tooling for this application.
from copy import deepcopy
import unittest

from phi_step_report import Accounting, attach_status, compact_tracks, publication_spacing


def event(ident: str, time: int, duration: int = 0, track: str = 'actor/work') -> dict:
    """Construct an observed interval; display width does not affect causal time."""
    return {'id': ident, 'ts': time, 'dur': duration, 'track': track,
            'name': ident, 'display_duration_ns': 8, 'args': {}}


class AccountingTest(unittest.TestCase):
    """Check elapsed partitioning independently of event-count or displayed block width."""

    def test_ties_and_resource_order(self) -> None:
        """Keep both equally late inputs and component bounds; ignore the later resource release."""
        graph = {'events': [event('left', 0, 8), event('right/tx', 4, 4), event('older', 1, 1),
                            event('fold/fold', 10, 2), event('credit', 9)],
                 'edges': [{'source': name, 'target': 'fold/fold', 'kind': 'contribution'}
                           for name in ['left', 'right/tx', 'older']],
                 'resource_dependencies': [{'source': 'credit', 'target': 'fold/fold'}]}
        index = Accounting(graph)
        result = index.budget('fold/fold', 0)
        self.assertEqual(result['representative_ns'], {'execution/publication': 8, 'input to collect': 2, 'collect/fold': 2})
        self.assertEqual(result['tied_path_min_ns']['execution/publication'], 0)
        self.assertEqual(result['tied_path_max_ns']['execution/publication'], 8)
        self.assertEqual(result['tied_path_max_ns']['first-to-last wire transfer'], 4)
        self.assertEqual(result['tied_path_max_ns']['unobserved root'], 4)
        self.assertEqual(set(result['latest_ancestry']), {'left', 'right/tx', 'fold/fold'})
        self.assertEqual(index.ancestors('fold/fold', 0), {'left', 'right/tx', 'older', 'fold/fold'})

    def test_frontier_clips_a_gap_and_an_execution(self) -> None:
        """Carry-in remains explicit and each time window is counted exactly once."""
        graph = {'events': [event('a', 0, 10), event('b', 20, 8)],
                 'edges': [{'source': 'a', 'target': 'b', 'kind': 'aggregate'}]}
        index = Accounting(graph)
        gap = index.budget('b', 15)
        self.assertEqual(gap['representative_ns'], {'aggregate to executor': 5, 'execution/publication': 8})
        self.assertEqual(gap['frontiers'], ['a'])
        middle = index.budget('b', 5)
        self.assertEqual(middle['representative_ns'], {'aggregate to executor': 10, 'execution/publication': 13})
        graph['events'][1]['ts'] = 9
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            Accounting(graph).budget('b', 0)

    def test_long_chain(self) -> None:
        """Follow many rounds without Python recursion limits or duplicate elapsed accounting."""
        graph = {'events': [event(str(i), 2*i, 1) for i in range(2000)],
                 'edges': [{'source': str(i), 'target': str(i+1), 'kind': 'actor state'} for i in range(1999)]}
        result = Accounting(graph).budget('1999', 0)
        self.assertEqual(result['representative_ns'], {'execution/publication': 2000, 'ordinary/state/other waits': 1999})

    def test_overlapping_branches_keep_distinct_tracks(self) -> None:
        """A tied branch remains a separate visible slice; grouping must not alias its flows."""
        profile = {'events': [event('a', 0, 8), event('b', 0, 16), event('c', 8, 8)], 'tracks': []}
        result = compact_tracks(profile)
        by_id = {e['id']: e for e in result['events']}
        self.assertNotEqual(by_id['a']['track'], by_id['b']['track'])
        self.assertEqual(by_id['a']['track'], by_id['c']['track'])
        self.assertEqual(by_id['b']['dur'], 16)

    def test_publication_spacing_clips_at_frontier(self) -> None:
        """Charge only the retained suffix of a batch's serialization to this window."""
        effects = [{**event(str(i), 16+8*i, track='actor/effect'),
                    'args': {'batch': 'batch', 'position': i}} for i in range(4)]
        result = publication_spacing({'segments': [{'kind': 'commit to effect acceptance',
                                    'start': 24, 'end': 40, 'target': '3'}]}, effects)
        self.assertEqual(result['within_batch_spacing_ns'], 16)
        self.assertEqual(result['commit_to_first_acceptance_ns'], 0)
        self.assertEqual(result['non_clock_spaced_effects'], 0)

    def test_explicit_delay_is_not_silently_ignored(self) -> None:
        """Unsupported graph semantics fail instead of manufacturing an elapsed category."""
        with self.assertRaisesRegex(ValueError, 'explicit edge delays'):
            Accounting({'events': [], 'edges': [{'delay_ns': 8}]})


class StatusTest(unittest.TestCase):
    """Bind the visible completion to the producer, not to a nearby event timestamp."""

    def test_status_identity_full_payload_and_duplicates(self) -> None:
        """Match the public codec's bytes, including flags; reject corruption, unknown bits and repeats."""
        actor = '{actor,{family,phi_x,[2,3]}}'
        payload = bytes.fromhex('0b0000000200030001000000')
        frame = (0x03552211 << 96) | int.from_bytes(payload, 'little')
        source = {**event('source', 100, track='D0/bank2/0/effect'),
                  'args': {'actor': actor, 'payload': hex((6 << 128) | frame), 'known_mask': hex((1 << 136)-1)}}
        graph = {'events': [source], 'edges': [], 'tracks': []}
        routes = {'actors': [{'device': 0, 'name': actor, 'module': 'phi_halo_cell',
                              'outputs': ['north', 'east', 'west', 'south', 'syndrome', 'correction', 'status']}],
                  'lanes': [{'source_device': 0, 'source': actor, 'ports': [5, 6], 'kind': 'external',
                             'destination': '{external,x_decoder_events}'}]}
        status = {'device': 0, 'stream': 'x_decoder_events', 'step': 11, 'x': 2, 'y': 3, 'flags': 1,
                  'header_word': 0x11225503, 'payload_hex': payload.hex(), 'time_ns': 200}
        matched = deepcopy(graph)
        result = attach_status(matched, [status], routes)
        self.assertEqual(result[0]['args']['producer_effect'], 'source')
        self.assertEqual(matched['edges'][0]['kind'], 'public status delivery')
        for changed in [{**status, 'payload_hex': '00'*12}, {**status, 'x': 9}, {**status, 'step': 12}, {**status, 'time_ns': 99}]:
            with self.assertRaises(ValueError):
                attach_status(deepcopy(graph), [changed], routes)
        with self.assertRaises(ValueError):
            attach_status(deepcopy(graph), [status, status], routes)
        graph['events'][0]['args']['known_mask'] = '0xff'
        with self.assertRaisesRegex(ValueError, 'unknown bits'):
            attach_status(graph, [status], routes)


if __name__ == '__main__':
    unittest.main()
