#!/usr/bin/env python3
"""Generate deterministic repetition-code witnesses from pinned, unchanged localuf."""

from __future__ import annotations

import argparse
from collections import Counter
from collections.abc import Callable
from functools import wraps
import hashlib
from itertools import combinations
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import sys
from typing import Any

REVISION = "daf81a10ed5d201c0bcaf6a1d5cdc6563a06b96c"
ROOT = Path(__file__).resolve().parents[3]
CACHE = ROOT / "_build/snowflake-reference"
POINTERS = {"C": 0, "W": 1, "E": 2, "D": 3, "U": 4}
NODE_FIELDS = ["active", "whole", "cid", "defect", "pointer", "grown", "unrooted", "busy"]
STAGES = ["drop", "grow_whole", "merge_whole", "grow_half", "merge_half"]


def load_reference(path: Path) -> tuple[type, type]:
    """Load the pinned checkout, rejecting a different revision or local edits."""
    revision = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    changed = subprocess.check_output(["git", "-C", str(path), "status", "--porcelain", "--untracked-files=no"], text=True)
    if revision != REVISION or changed:
        raise ValueError(f"Expected clean localuf {REVISION}; got {revision}, changes={changed!r}")
    os.environ.setdefault("MPLCONFIGDIR", str(CACHE / "matplotlib"))
    os.environ.setdefault("MPLBACKEND", "Agg")
    sys.path.insert(0, str(path))
    from localuf import Repetition
    from localuf.decoders import Snowflake
    return Repetition, Snowflake


def node_values(node: Any) -> list[int]:
    """Return the public algorithm registers in the fixture's fixed field order."""
    return [POINTERS[node.pointer] if field == "pointer" else int(getattr(node, field)) for field in NODE_FIELDS]


def snapshot(decoder: Any) -> dict[str, list[list[int]]]:
    """Capture current node and edge registers in stable geometry order."""
    nodes = sorted(decoder.NODES.values(), key=lambda node: (node.INDEX[1], node.INDEX[0]))
    return {"nodes": [node_values(node) for node in nodes],
            "edges": [[int(edge.growth), int(edge.correction)] for edge in decoder.EDGES.values()]}


class Observer:
    """Observe complete reference phases without replacing algorithm decisions."""

    def __init__(self, decoder: Any) -> None:
        """Attach counters to one decoder; all wrapped calls retain their arguments."""
        self.decoder = decoder
        self.phases: list[dict[str, Any]] = []
        self.work: Counter[str] = Counter()
        self.before = snapshot(decoder)
        self.wrap(decoder, "drop", after=self.record)
        self.wrap(decoder._SCHEDULE, "grow", after=self.record)
        last_node = next(reversed(decoder.NODES.values()))
        self.wrap(last_node, "update_after_merging", after=self.record)
        for node in decoder.NODES.values():
            self.wrap(node, "merging", counter="node_merge_visits")
            self.wrap(node, "grow_whole", counter="node_growth_visits")
            self.wrap(node, "grow_half", counter="node_growth_visits")
            self.wrap(node.FRIENDSHIP, "drop", counter="node_drop_visits")
            self.wrap(node.UNROOTER, "_compare_cid", counter="cid_comparisons")
            self.wrap(node.UNROOTER, "_check_grown", counter="grown_checks")
            self.wrap(node, "syncing", before=lambda n=node: self.count_push(n))
        for edge in decoder.EDGES.values():
            self.wrap(edge.CONTACT, "drop", counter="edge_drop_visits")

    def wrap(self, owner: Any, name: str, counter: str | None = None,
             before: Callable[[], None] | None = None,
             after: Callable[[], None] | None = None) -> None:
        """Wrap a bound method with observational callbacks."""
        original = getattr(owner, name)

        @wraps(original)
        def observed(*args: Any, **kwargs: Any) -> Any:
            """Call the original method and record only external counters."""
            if counter is not None:
                self.work[counter] += 1
            if before is not None:
                before()
            result = original(*args, **kwargs)
            if after is not None:
                after()
            return result

        setattr(owner, name, observed)

    def count_push(self, node: Any) -> None:
        """Count the reference's conditional defect-relay operation."""
        if node.pointer != "C" and not node._IS_BOUNDARY and node.defect:
            self.work["defect_pushes"] += 1

    def record(self) -> None:
        """Record a full synchronous phase, including idle merge termination passes."""
        after = snapshot(self.decoder)
        self.phases.append({
            "phase": STAGES[int(self.decoder._stage)],
            "active_nodes": sum(node.active for node in self.decoder.NODES.values()),
            "busy_nodes": sum(node.busy for node in self.decoder.NODES.values()),
            "reset_nodes": sum(node.cid == -1 for node in self.decoder.NODES.values()),
            "changed_nodes": sum(a != b for a, b in zip(self.before["nodes"], after["nodes"], strict=True)),
            "changed_edges": sum(a != b for a, b in zip(self.before["edges"], after["edges"], strict=True)),
            "work": dict(sorted(self.work.items())),
        })
        self.before = after
        self.work.clear()


def fault_syndrome(distance: int, data: int, measurement: int, previous: int) -> int:
    """Convert new data faults and consecutive measurement errors to detection events."""
    mask = (1 << (distance - 1)) - 1
    return ((data ^ (data >> 1)) & mask) ^ measurement ^ previous


def retire(decoder: Any, distance: int, index: int) -> dict[str, int]:
    """Read corrections leaving the window at the beginning of this input sheet."""
    spatial = sum(int(decoder.EDGES[((q - 1, 0), (q, 0))].correction) << q for q in range(distance))
    temporal = sum(int(decoder.EDGES[((j, 0), (j, 1))].correction) << j for j in range(distance - 1))
    return {"retired_sheet": index - decoder.CODE.SCHEME.WINDOW_HEIGHT,
            "retired_spatial_mask": spatial, "retired_temporal_mask": temporal}


def run_case(name: str, distance: int, faults: list[tuple[int, int]],
             repetition: type, snowflake: type, states: bool = True) -> dict[str, Any]:
    """Run a continuous stream and quiet tail; compare observed and untouched instances."""
    code = repetition(distance, "phenomenological", scheme="frugal", commit_height=1, buffer_height=2 * (distance // 2))
    decoder = snowflake(code, merger="fast", schedule="2:1", unrooter="full")
    control = snowflake(repetition(distance, "phenomenological", scheme="frugal"), merger="fast", schedule="2:1", unrooter="full")
    observer = Observer(decoder)
    height = code.SCHEME.WINDOW_HEIGHT
    inputs = faults + [(0, 0)] * (3 * height + 4)
    previous = 0
    records: list[dict[str, Any]] = []
    data_parity = 0
    correction_parity = 0
    for index, (data, measurement) in enumerate(inputs):
        syndrome_mask = fault_syndrome(distance, data, measurement, previous)
        previous = measurement
        syndrome = {(j, height - 1) for j in range(distance - 1) if (syndrome_mask >> j) & 1}
        retired = retire(decoder, distance, index)
        assert retired == retire(control, distance, index)
        data_parity ^= data
        correction_parity ^= retired["retired_spatial_mask"]
        observer.phases.clear()
        runtime = int(decoder.decode(syndrome, time_only="all"))
        assert runtime == control.decode(syndrome, time_only="all")
        state = snapshot(decoder)
        assert state == snapshot(control), (name, index)
        record = {"index": index, "data_fault_mask": data, "measurement_fault_mask": measurement,
                  "input_mask": syndrome_mask, **retired, "reference_runtime_all": runtime,
                  "phase_counts": dict(Counter(phase["phase"] for phase in observer.phases)),
                  "phases": list(observer.phases)}
        if states:
            record["state"] = state
        records.append(record)
    residual = data_parity ^ correction_parity
    if residual not in (0, (1 << distance) - 1):
        raise AssertionError((name, "non-logical final residual", residual))
    if decoder.syndrome or any(node.active for node in decoder.NODES.values()) or decoder.correction:
        raise AssertionError((name, "quiet tail did not drain"))
    return {"name": name, "distance": distance, "window_height": height,
            "fault_sheets": len(faults), "quiet_tail_sheets": len(inputs) - len(faults),
            "final_data_residual_mask": residual, "logical_failure": bool(residual), "sheets": records}


def named_faults(distance: int) -> list[tuple[str, list[tuple[int, int]]]]:
    """Return reproducible quiet, boundary, measurement, burst and sustained inputs."""
    rng = random.Random(0x534E4F57 + distance)
    low = [(sum((rng.random() < 0.025) << q for q in range(distance)),
            sum((rng.random() < 0.025) << q for q in range(distance - 1))) for _ in range(96)]
    burst = [(0, 0)] * 4 + [((1 << distance) - 1, 1), (3, 0), (0, (1 << (distance - 1)) - 1), (1, 1)] + [(0, 0)] * 8
    return [("zero", [(0, 0)] * 12), ("west_boundary", [(1, 0)]),
            ("east_boundary", [(1 << (distance - 1), 0)]),
            ("measurement_pair", [(0, 1), (0, 0)]),
            ("repeated_measurement", [(0, 1)] * (2 * distance) + [(0, 0)]),
            ("burst", burst), ("continuous", low)]


def geometry(distance: int, repetition: type, snowflake: type) -> dict[str, Any]:
    """Describe fixed node/edge ordering for state comparisons."""
    decoder = snowflake(repetition(distance, "phenomenological", scheme="frugal"))
    nodes = sorted(decoder.NODES.values(), key=lambda node: (node.INDEX[1], node.INDEX[0]))
    return {"distance": distance, "window_height": decoder.CODE.SCHEME.WINDOW_HEIGHT,
            "nodes": [{"coordinate": list(node.INDEX), "id": node.ID} for node in nodes],
            "edges": [[list(v) for v in edge] for edge in decoder.EDGES]}


def main() -> None:
    """Write the named and enumerated fixtures, with compact reproducibility metadata."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=CACHE / "localuf")
    parser.add_argument("--output", type=Path, default=ROOT / "apps/hls_snowflake/priv/fixtures")
    args = parser.parse_args()
    repetition, snowflake = load_reference(args.reference)
    args.output.mkdir(parents=True, exist_ok=True)
    common = {"schema": "snowflake-repetition-fixtures-v1", "reference_revision": REVISION,
              "noise": "phenomenological", "schedule": "2:1", "merger": "fast", "unrooter": "full",
              "node_fields": NODE_FIELDS, "edge_fields": ["growth", "correction"], "pointers": POINTERS,
              "time_unit": "algorithmic phases; neither runtime_all nor phase count is hardware cycles"}
    named = [run_case(f"d{d}_{name}", d, faults, repetition, snowflake)
             for d in (3, 5) for name, faults in named_faults(d)]
    cases = []
    # Every weight-0, 1 or 2 phenomenological fault pattern across three d=3 sheets.
    for weight in range(3):
        for positions in combinations(range(15), weight):
            faults = [[0, 0] for _ in range(3)]
            for position in positions:
                sheet, bit = divmod(position, 5)
                faults[sheet][0 if bit < 3 else 1] |= 1 << (bit if bit < 3 else bit - 3)
            case = run_case("d3_w" + str(weight) + "_" + "-".join(map(str, positions)), 3,
                            [tuple(pair) for pair in faults], repetition, snowflake, states=False)
            for sheet in case["sheets"]:
                del sheet["phases"]
            cases.append(case)
    documents = {
        "named.json": {**common, "geometries": [geometry(d, repetition, snowflake) for d in (3, 5)], "cases": named},
        "enumerated.json": {**common, "enumeration": {"distance": 3, "sheets": 3, "fault_positions": 15, "maximum_weight": 2}, "cases": cases},
    }
    summary = {}
    for name, document in documents.items():
        payload = (json.dumps(document, separators=(",", ":")) + "\n").encode()
        (args.output / name).write_bytes(payload)
        summary[name] = {"sha256": hashlib.sha256(payload).hexdigest(), "cases": len(document["cases"]),
                         "sheets": sum(len(case["sheets"]) for case in document["cases"]),
                         "logical_failures": sum(case["logical_failure"] for case in document["cases"])}
    provenance = {
        "schema": "snowflake-reference-provenance-v1",
        "repository": "https://github.com/timchan0/localuf", "revision": REVISION,
        "version": "3.4.4", "license": "MIT", "python": platform.python_version(),
        "reference_algorithm_sha256": hashlib.sha256((args.reference / "localuf/decoders/snowflake/main.py").read_bytes()).hexdigest(),
        "requirements_sha256": hashlib.sha256(Path(__file__).with_name("requirements.lock").read_bytes()).hexdigest(),
        "fixtures": summary,
    }
    (args.output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
