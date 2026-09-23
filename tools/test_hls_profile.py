#!/usr/bin/env python3
"""Check profile causality, timing, serialization and both renderers."""
import copy
import json
import unittest
import xml.etree.ElementTree as ET

from hls_profile import longest_path, perfetto, svg, validate, window, counter_name


def fixture() -> dict:
    """A fork/join whose slower predecessor differs from its last-listed predecessor."""
    return {'schema': 1, 'unit': 'ns', 'metadata': {'dependency_scope': 'complete fixture'},
            'tracks': [{'id': x, 'name': x} for x in ('a', 'b', 'c')],
            'events': [{'id': 'root', 'track': 'a', 'name': 'begin', 'ts': 0, 'dur': 0},
                       {'id': 'slow', 'track': 'b', 'name': 'slow work', 'ts': 5, 'dur': 40, 'args': {'slot': 3}},
                       {'id': 'fast', 'track': 'c', 'name': 'fast work', 'ts': 5, 'dur': 10},
                       {'id': 'join', 'track': 'a', 'name': 'join <&>', 'ts': 50, 'dur': 10}],
            'edges': [{'source': a, 'target': b, 'kind': 'needs', 'evidence': 'fixture', 'delay_ns': delay}
                      for a, b, delay in [('root', 'slow', 5), ('root', 'fast', 5), ('slow', 'join', 0), ('fast', 'join', 0)]],
            'counters': [{'track': 'a', 'ts': 3, 'name': 'depth', 'value': 2}]}


class ProfileTests(unittest.TestCase):
    """Reject misleading graphs and retain the details required for independent re-analysis."""

    def test_path_and_unassigned_wait(self) -> None:
        """The longest accounted path uses the slow branch and exposes the five-ns gap."""
        result = longest_path(fixture(), 'join')
        self.assertEqual(result['events'], ['root', 'slow', 'join'])
        self.assertEqual((result['accounted_ns'], result['elapsed_ns'], result['unassigned_ns']), (55, 60, 5))

    def test_reject_invalid_dependencies(self) -> None:
        """Missing IDs, time travel, cycles and anonymous evidence must fail before export."""
        for change in ('unknown', 'negative', 'cycle', 'evidence', 'duplicate', 'overlap'):
            p = fixture()
            if change == 'unknown': p['edges'][0]['source'] = 'missing'
            elif change == 'negative': p['edges'][0]['delay_ns'] = -1
            elif change == 'cycle': p['edges'].append({'source': 'root', 'target': 'root', 'kind': 'loop', 'evidence': 'fixture'})
            elif change == 'evidence': del p['edges'][0]['evidence']
            elif change == 'duplicate': p['events'].append(copy.deepcopy(p['events'][0]))
            else: p['events'][2].update(track='b')
            with self.subTest(change=change), self.assertRaises(ValueError): validate(p)

    def test_window_boundaries(self) -> None:
        """Clipping must disclose lost causal context and retain the preceding counter sample."""
        p = window(fixture(), 10, 70)
        self.assertEqual([e['id'] for e in p['events']], ['join'])
        self.assertEqual(p['metadata']['omitted_boundary_edges'], 2)
        self.assertEqual(p['counters'][0]['ts'], 10)
        self.assertEqual(p['counters'][0]['original_ts'], 3)
        self.assertEqual(longest_path(p, 'join')['accounted_ns'], 10)

    def test_legacy_adapter_preserves_aliased_neighbors(self) -> None:
        """Aliased source fragments must preserve multiplicity without ambiguous parallel flows."""
        from phi_profile_timeline import Event, Dependency, timing_profile
        source = Event(2, 'phi_0', 'state_write', 0, 'epoch=4')
        target = Event(3, 'phi_x_plane', 'batch_accept', 1, 'source=0')
        dependency = Dependency(source, target, 'contribution', 'fixture')
        profile = timing_profile([source, target], [dependency, dependency], 7)
        self.assertEqual([e['ts'] for e in profile['events']], [14, 21])
        self.assertEqual(profile['edges'][0]['multiplicity'], 2)
        self.assertEqual(profile['events'][0]['args']['epoch'], '4')

    def test_ambiguous_flow_anchor_rejected(self) -> None:
        """Two instants at the same time on one track cannot be unambiguously bound by Perfetto."""
        p = fixture()
        p['events'].append({'id': 'ambiguous', 'track': 'a', 'name': 'also begin', 'ts': 0, 'dur': 0})
        with self.assertRaisesRegex(ValueError, 'separate tracks'):
            perfetto(p)

    def test_counter_identity_includes_track(self) -> None:
        """Chrome scopes counters by process/name, so distinct logical tracks need distinct names."""
        p = fixture()
        p['counters'].append({'track': 'b', 'name': 'depth', 'ts': 4, 'value': 9})
        counters = [e for e in perfetto(p)['traceEvents'] if e['ph'] == 'C']
        self.assertEqual(len({e['name'] for e in counters}), 2)
        self.assertEqual(json.loads(counter_name(p['counters'][1])), ['b', 'depth'])

    def test_export_cannot_silently_lose_data(self) -> None:
        """Reject reserved argument collisions and counters that cannot survive native double storage."""
        p = fixture()
        p['events'][0]['args'] = {'event_id': 'shadow'}
        with self.assertRaisesRegex(ValueError, 'reserved'):
            perfetto(p)
        p = fixture()
        p['counters'][0]['value'] = 2**53+1
        with self.assertRaisesRegex(ValueError, 'finite double'):
            perfetto(p)

    def test_clock_width_instant_preserves_causality(self) -> None:
        """A handshake's visible clock bin must not become additional causal work."""
        p = fixture()
        p['events'][0]['display_duration_ns'] = 8
        self.assertEqual(longest_path(p, 'join'), longest_path(fixture(), 'join'))
        event = next(e for e in perfetto(p)['traceEvents'] if e.get('ph') == 'X')
        self.assertEqual((event['dur'], event['args']['duration_ns']), (.008, 0))
        self.assertEqual(event['args']['display_duration_ns'], 8)
        tree = ET.fromstring(svg(p, 0, 80))
        rectangles = [e for e in tree.iter('{http://www.w3.org/2000/svg}rect')
                      if e.get('class') == 'event']
        self.assertAlmostEqual(float(rectangles[0].get('width')), 119)
        self.assertNotIn('root', {e['id'] for e in window(p, 0, 7)['events']})

    def test_invalid_clock_widths_are_rejected(self) -> None:
        """Do not hide overlapping clock bins or change the meaning of duration slices."""
        for width in (-1, 1.5, True, 51):
            p = fixture()
            p['events'][0]['display_duration_ns'] = width
            with self.subTest(width=width), self.assertRaises(ValueError):
                validate(p)
        p = fixture()
        p['events'][1]['display_duration_ns'] = 41
        with self.assertRaisesRegex(ValueError, 'expand an instant'):
            validate(p)

    def test_svg_labels_and_evidence_categories(self) -> None:
        """Visible labels escape source text; waits and unknown intervals remain visually distinct."""
        p = fixture()
        p['events'][1]['category'] = 'wait'
        p['events'][2]['category'] = 'unknown'
        tree = ET.fromstring(svg(p, 0, 80))
        texts = [e.text for e in tree.iter('{http://www.w3.org/2000/svg}text')]
        self.assertIn('join <&>', texts)
        fills = {e.get('fill') for e in tree.iter('{http://www.w3.org/2000/svg}rect')}
        self.assertTrue({'#d7a84b', '#c5cbd3'} <= fills)

    def test_roundtrip_and_render(self) -> None:
        """SVG native titles and Perfetto args/flows retain event identity and causality."""
        p = json.loads(json.dumps(fixture()))
        root = ET.fromstring(svg(p, 0, 80, 'join'))
        titles = [e.text for e in root.iter('{http://www.w3.org/2000/svg}title')]
        self.assertTrue(any('join <&>' in text for text in titles))
        trace = perfetto(p)['traceEvents']
        self.assertEqual(sum(e['ph'] == 'X' for e in trace), 4)
        self.assertEqual(sum(e['ph'] == 's' for e in trace), 4)
        self.assertEqual(sum(e['ph'] == 'f' for e in trace), 4)
        self.assertEqual(next(e for e in trace if e.get('name') == 'slow work')['args']['slot'], 3)
        self.assertEqual(sum(e['ph'] == 'C' for e in trace), 1)
        target = next(e for e in trace if e.get('ph') == 'X' and e['args']['event_id'] == 'join')
        self.assertEqual(len(json.loads(target['args']['profile_dependencies'])), 2)


if __name__ == '__main__':
    unittest.main()
