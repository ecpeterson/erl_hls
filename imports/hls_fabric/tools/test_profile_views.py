"""Check nested presentation without weakening the causal graph or losing observations."""

import unittest
from profile_views import actor_views, perfetto


def event(name: str, ts: int, dur: int, category: str = "handshake") -> dict:
    """Make one real vertex observation on a distinct semantic track."""
    return {
        "id": name,
        "ts": ts,
        "dur": dur,
        "display_duration_ns": dur or 8,
        "name": name,
        "category": category,
        "track": "activation/owner/4" if category == "ownership" else "activation/" + name,
        "args": {"source": 4, "group": 1},
    }


class ProfileViewsTests(unittest.TestCase):
    """Require legal Perfetto nesting and retain equal-time boundaries in one clock bin."""

    def test_ownership_and_boundaries_share_one_stream(self) -> None:
        """An ownership interval contains boundary bins; coincident ports retain both identities."""
        profile = {
            "events": [
                event("owned", 0, 32, "ownership"),
                event("dispatch", 0, 0),
                event("write", 24, 0),
                event("batch", 24, 0),
                event("retire", 32, 0),
            ]
        }
        (view,) = actor_views(profile)
        self.assertEqual(view["name"], "Executor 1 / vertex 04")
        self.assertEqual([s["depth"] for s in view["slices"]], [0, 1, 1, 0])
        self.assertEqual(view["slices"][2]["source_event_ids"], ["write", "batch"])
        original = {"traceEvents": [{"ph": "s", "pid": 4, "id": 8, "name": "real causal flow"}]}
        result = perfetto(profile, original)
        self.assertEqual(result["traceEvents"][-1], original["traceEvents"][0])
        slices = [e for e in result["traceEvents"] if e["ph"] == "X"]
        self.assertEqual(len({(e["pid"], e["tid"]) for e in slices}), 1)
        self.assertTrue(all(e["args"]["display_only"] for e in slices))
        self.assertEqual(len(original["traceEvents"]), 1)

    def test_crossing_intervals_rejected(self) -> None:
        """A combined display must not silently truncate events at an ownership boundary."""
        with self.assertRaisesRegex(ValueError, "crossing"):
            actor_views({"events": [event("owned", 0, 30, "ownership"), event("clock", 24, 0)]})


if __name__ == "__main__":
    unittest.main()
