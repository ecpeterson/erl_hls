#!/usr/bin/env python3
"""Test finite actor generation/checking and optionally inject, shrink and replay an RTL defect."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

import actor_differential as differential
import actor_differential_cases as cases


def word(**values: int) -> str:
    """Pack synthetic checker observations; this does not model actor behavior."""
    fields = {"phase": 47, "value": 39, "occupied": 31, "postponed": 23,
              "failure": 19, "pending": 18, "accepted": 17,
              "valid": 16, "port": 8, "payload": 0}
    return f"{sum(value << fields[name] for name, value in values.items()):016x}"


def trace(rows: list[list[str]]) -> str:
    """Format one complete synthetic trace for each checker-test segment."""
    return "\n".join(f"ACTOR {segment} {clock} {value}"
                     for segment, values in enumerate(rows)
                     for clock, value in enumerate(values)) + "\nPASS: actor trace complete\n"


class GeneratorTests(unittest.TestCase):
    """Validate deterministic descriptors and scope-preserving schedule reductions."""

    def test_generation_and_reduction(self) -> None:
        """Replay is independent of generation order; every reduction retains exact actor source."""
        forward = {i: cases.generate(751, i) for i in range(20)}
        backward = {i: cases.generate(751, i) for i in reversed(range(20))}
        self.assertEqual(forward, backward)
        self.assertNotEqual(forward[0], cases.generate(752, 0))
        for program in forward.values():
            self.assertTrue(cases.valid(program))
            for small in cases.reductions(program):
                self.assertTrue(cases.valid(small))
                self.assertLess(cases.cost(small), cases.cost(program))
                self.assertEqual(cases.source(small), cases.source(program))

    def test_rejects_malformed_replays(self) -> None:
        """Malformed JSON descriptors fail before compiling or running an actor."""
        good = cases.generate(751, 0)
        for program in (None, [], {}, {**good, "segments": [None]},
                        {**good, "segments": [{"reset": True, "ready": 0, "commands": [[5, 0]]}]},
                        {**good, "initial": True}, {**good, "operator": "div"}):
            self.assertFalse(cases.valid(program))


class CheckerTests(unittest.TestCase):
    """Check observer layout, ordering, stalls, incomplete tails and latched failure independently."""

    def setUp(self) -> None:
        """Build one trace with two accepted commands and two ordered outputs."""
        self.program = cases.generate(1, 0)
        self.program["segments"] = [{"reset": True, "ready": 0xFFFF, "commands": [[2, 1], [2, 2]]}]
        self.oracle = {"segments": [{"phase": 1, "value": 23, "postponed": 0,
                                     "failure": 0, "events": [[1, 7], [0, 9]]}]}
        self.rows = [[word(phase=1, value=23, accepted=1, valid=1, port=1, payload=7),
                      word(phase=1, value=23, accepted=1, valid=1, payload=9)] +
                     [word(phase=1, value=23)] * (cases.HORIZON - 2)]

    def test_observation_layout(self) -> None:
        """The observation has no dependency on the generated Machine representation."""
        self.assertEqual(differential.observation(int(word(phase=1, value=255, occupied=3,
            postponed=2, failure=2, pending=1, accepted=1, valid=1, port=1, payload=43), 16)),
            {"phase": 1, "value": 255, "occupied": 3, "postponed": 2, "failure": 2,
             "pending": 1, "accepted": 1, "event": (1, 43)})

    def test_complete_prefix_and_missing_cycles(self) -> None:
        """Successful prefixes require complete horizons and all offered commands to drain."""
        self.assertIsNone(differential.compare(self.program, self.oracle, trace(self.rows)))
        self.rows[0].pop()
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "horizon")

    def test_ordered_effects_and_state(self) -> None:
        """Reordering otherwise equal effects and changing committed state are both detected."""
        self.rows[0][:2] = reversed(self.rows[0][:2])
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "ordered_events")
        self.rows[0][-1] = word(phase=1, value=24)
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "value")

    def test_stalls_and_incomplete_tail(self) -> None:
        """An output during backpressure is a mismatch; an undrained tail is not equality."""
        self.program["segments"][0]["ready"] = 0
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "stalled_output")
        self.program["segments"][0]["ready"] = 0xFFFF
        self.program["segments"][0]["commands"].append([2, 3])
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["category"], "incomplete_tail")

    def test_stalled_entry_cannot_commit_early(self) -> None:
        """A blocked entry cannot replace data even if its eventual drained state is correct."""
        self.program["segments"][0]["ready"] = 1
        self.rows[0][:2] = [word(pending=1), word(value=1, pending=1)]
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "stalled_commit")

    def test_failure_is_sticky_until_reset(self) -> None:
        """A later clean checkpoint cannot conceal state movement during latched failure."""
        self.oracle["segments"][0].update(failure=2, events=[])
        self.rows = [[word(phase=1, value=23, failure=2)] * cases.HORIZON]
        self.assertIsNone(differential.compare(self.program, self.oracle, trace(self.rows)))
        self.rows[0][3] = word(phase=1, value=24, failure=2)
        self.assertEqual(differential.compare(self.program, self.oracle, trace(self.rows))["reason"], "failure_latch")
        self.rows[0][3] = word(phase=1, value=23, failure=2)
        self.program["segments"].append({"reset": True, "ready": 0xFFFF, "commands": []})
        self.oracle["segments"].append({"phase": 0, "value": 3, "postponed": 0, "failure": 0, "events": []})
        self.rows.append([word(value=3)] * cases.HORIZON)
        self.assertIsNone(differential.compare(self.program, self.oracle, trace(self.rows)))


class ShrinkerTests(unittest.TestCase):
    """Exercise reduction search separately from expensive compilation."""

    def test_preserves_signature_and_budget(self) -> None:
        """Unrelated mismatches never qualify; a hard attempt budget bounds repeated tool work."""
        failure = {"status": "failed", "phase": "rtl", "category": "result_mismatch", "reason": "value"}

        class Probe:
            """Expose a deterministic reduction predicate, not an actor implementation."""

            def __init__(self, stage: Path) -> None:
                """Retain the same evidence destination shape as the real runner."""
                self.stage = stage

            def run_actor(self, program: cases.Program, name: str) -> dict:
                """Only the command carrying value seven preserves this synthetic defect."""
                present = any([2, 7] in s["commands"] for s in program["segments"])
                return {**failure, "stage": name, "reason": "value" if present else "phase"}

        program = cases.generate(751, 0)
        program["segments"] = [{"reset": True, "ready": 9, "commands": [[2, 1], [2, 7], [3, 2]]},
                               {"reset": False, "ready": 3, "commands": [[2, 4]]}]
        with tempfile.TemporaryDirectory() as directory:
            probe = Probe(Path(directory))
            small = differential.minimize(probe, program, failure, 40)
            self.assertEqual(small["segments"], [{"reset": True, "ready": 0, "commands": [[2, 7]]}])
            self.assertEqual(cases.source(program), cases.source(small))
            history = json.loads((probe.stage / "shrink.json").read_text())
            self.assertTrue(any(not h["accepted"] for h in history["history"]))
            differential.minimize(probe, program, failure, 2)
            self.assertEqual(json.loads((probe.stage / "shrink.json").read_text())["attempts"], 2)


def integration(xls: Path, stage: Path, compile: bool) -> None:
    """Corrupt actual generated arithmetic, detect and shrink its RTL mismatch, then replay cleanly."""
    class CorruptLiteral(differential.Runner):
        """Alter only the generated helper; the independently executed BEAM source stays intact."""

        def inject(self, source: Path) -> None:
            """Replace the fixture's unique bias constant, rejecting stale injection assumptions."""
            text, count = re.subn(r'\+ \(7\)', '+ (6)', source.read_text())
            if count != 1:
                raise AssertionError(f"expected one generated bias constant, found {count}")
            source.write_text(text)

    program = {**cases.generate(1, 0), "initial": 0, "entry": 0, "bias": 7,
               "operator": "+", "threshold": 0, "reverse": False, "bad": 99,
               "segments": [{"reset": True, "ready": 0xFFFF, "commands": [[2, 1], [2, 2]]},
                            {"reset": False, "ready": 0xFFFF, "commands": []}]}
    runner = CorruptLiteral(xls, stage)
    runner.prepare(compile=compile)
    failure = runner.run_actor(program, "injected")
    assert failure.get("category") == "result_mismatch", failure
    small = differential.minimize(runner, program, failure, 12)
    assert cases.cost(small) < cases.cost(program), small
    assert sum(len(s["commands"]) for s in small["segments"]) == 1, small
    clean = differential.Runner(xls, stage / "clean-replay")
    clean.prepare(compile=False)
    replay = clean.run_actor(small, "case")
    assert replay["status"] == "ok", replay
    print("PASS: injected actor RTL mismatch detected, schedule shrunk, clean replay agrees with BEAM")


def main() -> None:
    """Run fast unit tests unless an explicit XLS tool directory enables the bounded integration."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xls-root", type=Path)
    parser.add_argument("--stage", type=Path, default=differential.ROOT / "_build/actor-differential-self-test")
    parser.add_argument("--skip-compile", action="store_true")
    args = parser.parse_args()
    if args.xls_root:
        if args.stage.exists():
            parser.error("self-test stage already exists; choose a fresh directory")
        integration(args.xls_root, args.stage, not args.skip_compile)
    else:
        unittest.main(argv=[sys.argv[0]])


if __name__ == "__main__":
    main()
