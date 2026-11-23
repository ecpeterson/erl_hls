"""Focused pictures must preserve the producers of every visible reduction input."""
import phi_tool_paths  # Resolve shared tooling for this application.
from collections import defaultdict
import unittest

from phi_message_report import handoff_selection


class HandoffSelectionTest(unittest.TestCase):
    """Retain competing contributors instead of showing only the latest arrival's chain."""

    def test_all_contributors_and_missing_ancestry(self) -> None:
        """Keep four independent producer chains, opening and consumer; reject an orphan input."""
        events, incoming, outgoing = {}, defaultdict(list), defaultdict(list)

        def event(ident: str, track: str, time: int, duration: int = 0, **args: str) -> dict:
            """Create a minimal timing event with the public profiler's fields."""
            item = {'id': ident, 'track': track, 'ts': time, 'dur': duration, 'args': args}
            events[ident] = item
            return item

        def edge(source: str, target: str) -> None:
            """Record only actual prerequisites in both adjacency indexes."""
            relation = {'source': source, 'target': target}
            incoming[target].append(relation)
            outgoing[source].append(relation)

        fold = event('window/fold', 'consumer/reduction', 100, 8)
        consumer = event('consumer', 'consumer/work', 108, 16)
        edge(fold['id'], consumer['id'])
        event('opening-work', 'consumer/work', 0, 16)
        event('window/open', 'consumer/opening', 20)
        edge('opening-work', 'window/open')
        edge('window/open', fold['id'])
        for i in range(4):
            stem = f'producer{i}'
            event(stem, stem+'/work', i*8, 16)
            event(stem+'/batch', stem+'/outbox', 16+i*8, 24)
            event(stem+'/effect', stem+'/effect', 24+i*8, batch=stem+'/batch')
            event(stem+'/other-effect', stem+'/effect', 32+i*8, batch=stem+'/batch')
            event(f'window/fragment{i}', f'consumer/fragment{i}', 48+i*8)
            edge(stem, stem+'/effect')
            edge(stem+'/effect', f'window/fragment{i}')
            edge(f'window/fragment{i}', fold['id'])
        selected, tracks, chains = handoff_selection(fold, events, incoming, outgoing)
        self.assertEqual(selected, set(events))
        self.assertEqual(set(tracks), {e['track'] for e in events.values()})
        self.assertEqual(len(chains), 5)
        for i in range(4):
            self.assertIn([f'producer{i}', f'producer{i}/effect', f'window/fragment{i}'],
                          [[e['id'] for e in chain] for chain in chains])
        incoming['window/fragment0'].clear()
        with self.assertRaisesRegex(ValueError, 'incomplete message chain'):
            handoff_selection(fold, events, incoming, outgoing)


if __name__ == '__main__':
    unittest.main()
