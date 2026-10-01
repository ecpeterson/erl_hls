"""Check causal identities when adapting scheduler traces to common profiles."""
from backend_paths import PUBLIC
import unittest

class AdapterTests(unittest.TestCase):
    def test_dispatch_tickets_match_reads_by_actor(self) -> None:
        """Concurrent reservations must not attribute a read to another actor."""
        from phi_profile_timeline import Event, build_dependencies
        events = [Event(1, 'phi_0', 'dispatch_accept', 0, ''),
                  Event(2, 'phi_0', 'dispatch_accept', 1, ''),
                  Event(3, 'phi_0', 'state_read', 1, ''),
                  Event(4, 'phi_0', 'state_read', 0, '')]
        dependencies = build_dependencies(events, [['phi_0']], ['phi_x_plane'],
                                          {'phi_0': 'window_router_0'}, {'x': {0: [0]}})
        self.assertEqual([(d.source.slot, d.target.slot, d.source.cycle, d.target.cycle)
                          for d in dependencies if d.kind == 'ticket_to_read'],
                         [(1, 1, 2, 3), (0, 0, 1, 4)])

    def test_scheduler_adapter_preserves_aliased_neighbors(self) -> None:
        """Aliased source fragments must preserve multiplicity without ambiguous parallel flows."""
        from phi_profile_timeline import Event, Dependency, timing_profile
        source = Event(2, 'phi_0', 'state_write', 0, 'epoch=4')
        target = Event(3, 'phi_x_plane', 'batch_accept', 1, 'source=0')
        dependency = Dependency(source, target, 'contribution', 'fixture')
        profile = timing_profile([source, target], [dependency, dependency], 7)
        self.assertEqual([e['ts'] for e in profile['events']], [14, 21])
        self.assertEqual(profile['edges'][0]['multiplicity'], 2)
        self.assertEqual(profile['events'][0]['args']['epoch'], '4')


if __name__ == "__main__":
    unittest.main()
