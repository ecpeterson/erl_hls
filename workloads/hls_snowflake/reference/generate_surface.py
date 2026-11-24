#!/usr/bin/env python3
"""Generate small planar surface-code witnesses from pinned, unchanged localuf."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import random
from typing import Any

import generate as repetition

POINTERS = {**repetition.POINTERS, "N": 5, "S": 6}
NEIGHBOR_ORDER = ["N", "W", "D", "U", "E", "S"]


def make_decoder(distance: int, surface: type, snowflake: type) -> Any:
    """Construct the unchanged 2:1 fast/full decoder with its standard frugal window."""
    return snowflake(surface(distance, "phenomenological", scheme="frugal",
                             commit_height=1, buffer_height=2 * (distance // 2)),
                     merger="fast", schedule="2:1", unrooter="full")


def ordered_nodes(decoder: Any) -> list[Any]:
    """Return nodes in time, north/south, then west/east coordinate order."""
    return sorted(decoder.NODES.values(), key=lambda node: (node.INDEX[2], *node.INDEX[:2]))


def snapshot(decoder: Any) -> dict[str, list[list[int]]]:
    """Capture the same algorithm registers as the repetition witnesses."""
    return {"nodes": [[POINTERS[node.pointer] if field == "pointer" else int(getattr(node, field))
                       for field in repetition.NODE_FIELDS] for node in ordered_nodes(decoder)],
            "edges": [[int(edge.growth), int(edge.correction)] for edge in decoder.EDGES.values()]}


class Observer(repetition.Observer):
    """Observe six-neighbor phases and actual defect transfers without changing decisions."""

    def __init__(self, decoder: Any) -> None:
        """Attach the existing counters and use surface-coordinate snapshots."""
        self.transfers: list[list[int]] = []
        self.node_indices = {node.INDEX: i for i, node in enumerate(ordered_nodes(decoder))}
        self.edge_indices = {edge: i for i, edge in enumerate(decoder.EDGES)}
        super().__init__(decoder)
        self.before = snapshot(decoder)

    def count_push(self, node: Any) -> None:
        """Record each actual source, destination and correction edge before syncing."""
        super().count_push(node)
        if node.pointer != "C" and not node._IS_BOUNDARY and node.defect:
            edge, end = node.NEIGHBORS[node.pointer]
            self.transfers.append([self.node_indices[node.INDEX], self.node_indices[edge[end]],
                                   self.edge_indices[edge]])

    def record(self) -> None:
        """Record a complete synchronous phase, including quiescence checks."""
        after = snapshot(self.decoder)
        self.phases.append({
            "phase": repetition.STAGES[int(self.decoder._stage)],
            "active_nodes": sum(node.active for node in self.decoder.NODES.values()),
            "busy_nodes": sum(node.busy for node in self.decoder.NODES.values()),
            "reset_nodes": sum(node.cid == -1 for node in self.decoder.NODES.values()),
            "changed_nodes": sum(a != b for a, b in zip(self.before["nodes"], after["nodes"], strict=True)),
            "changed_edges": sum(a != b for a, b in zip(self.before["edges"], after["edges"], strict=True)),
            "transfers": self.transfers,
            "work": dict(sorted(self.work.items())),
        })
        self.before = after
        self.transfers = []
        self.work.clear()


def geometry(decoder: Any) -> dict[str, Any]:
    """Describe stable coordinates, directions and every input/output mask position."""
    distance, height = decoder.CODE.D, decoder.CODE.SCHEME.WINDOW_HEIGHT
    nodes = ordered_nodes(decoder)
    node_index = {node.INDEX: i for i, node in enumerate(nodes)}
    edge_index = {edge: i for i, edge in enumerate(decoder.EDGES)}
    detectors = [(i, j) for i in range(distance) for j in range(distance - 1)]
    spatial = [tuple(v[:2] for v in edge) for edge in decoder.EDGES
               if edge[0][2] == edge[1][2] == 0]
    temporal = [((i, j, 0), (i, j, 1)) for i, j in detectors]
    return {"kind": "surface", "distance": distance, "window_height": height,
            "neighbor_order": NEIGHBOR_ORDER, "syndrome_coordinates": detectors,
            "spatial_edges": spatial, "temporal_edges": temporal,
            "cid_boundary_threshold": 2 * distance * height,
            "boundary_cid_shift": 2 * distance, "bulk_cid_shift": distance * (distance - 1),
            "nodes": [{"coordinate": node.INDEX, "id": node.ID, "boundary": node._IS_BOUNDARY,
                       "syndrome_bit": detectors.index(node.INDEX[:2])
                       if node.INDEX[2] == height - 1 and not node._IS_BOUNDARY else None,
                       "neighbors": [{"direction": POINTERS[direction], "node_index": node_index[edge[end]],
                                      "edge_index": edge_index[edge]}
                                     for direction, (edge, end) in node.NEIGHBORS.items()]}
                      for node in nodes],
            "edges": list(decoder.EDGES)}


def data_syndrome(mask: int, graph: dict[str, Any]) -> int:
    """Return detector parity of spatial faults, excluding rough-boundary vertices."""
    detector_index = {tuple(v): i for i, v in enumerate(graph["syndrome_coordinates"])}
    syndrome = 0
    for bit, edge in enumerate(graph["spatial_edges"]):
        if mask & (1 << bit):
            for vertex in edge:
                if tuple(vertex) in detector_index:
                    syndrome ^= 1 << detector_index[tuple(vertex)]
    return syndrome


def retire(decoder: Any, graph: dict[str, Any], index: int) -> dict[str, int]:
    """Read immutable spatial and temporal correction masks before the next drop."""
    spatial = sum(int(decoder.EDGES[tuple((*v, 0) for v in edge)].correction) << bit
                  for bit, edge in enumerate(graph["spatial_edges"]))
    temporal = sum(int(decoder.EDGES[edge].correction) << bit
                   for bit, edge in enumerate(graph["temporal_edges"]))
    return {"retired_sheet": index - graph["window_height"],
            "retired_spatial_mask": spatial, "retired_temporal_mask": temporal}


def run_case(name: str, distance: int, faults: list[tuple[int, int]], surface: type,
             snowflake: type, detailed: bool = True) -> dict[str, Any]:
    """Run a stream, cross-check untouched reference state, and validate drained parity."""
    decoder = make_decoder(distance, surface, snowflake)
    control = make_decoder(distance, surface, snowflake)
    observer = Observer(decoder)
    graph = geometry(decoder)
    height = graph["window_height"]
    inputs = faults + [(0, 0)] * (3 * height + 4)
    previous = data_parity = correction_parity = 0
    records = []
    for index, (data, measurement) in enumerate(inputs):
        mask = data_syndrome(data, graph) ^ measurement ^ previous
        previous = measurement
        syndrome = {(*vertex, height - 1) for bit, vertex in enumerate(graph["syndrome_coordinates"])
                    if mask & (1 << bit)}
        retired = retire(decoder, graph, index)
        assert retired == retire(control, graph, index), (name, index, "retirement")
        data_parity ^= data
        correction_parity ^= retired["retired_spatial_mask"]
        observer.phases.clear()
        runtime = int(decoder.decode(syndrome, time_only="all"))
        assert runtime == control.decode(syndrome, time_only="all"), (name, index, "runtime")
        state = snapshot(decoder)
        assert state == snapshot(control), (name, index, "state")
        record = {"index": index, "data_fault_mask": data, "measurement_fault_mask": measurement,
                  "input_mask": mask, **retired, "reference_runtime_all": runtime,
                  "phase_counts": dict(Counter(phase["phase"] for phase in observer.phases))}
        if detailed:
            record.update(state=state, phases=list(observer.phases))
        records.append(record)
    residual = data_parity ^ correction_parity
    assert data_syndrome(residual, graph) == 0, (name, "nonzero final syndrome", residual)
    assert not decoder.syndrome and not decoder.correction and not any(
        node.active for node in decoder.NODES.values()), (name, "quiet tail did not drain")
    # The batch classifier independently checks the homology of the final spatial residual.
    spatial_code = surface(distance, "code capacity")
    residual_edges = {edge for bit, edge in enumerate(graph["spatial_edges"]) if residual & (1 << bit)}
    assert not spatial_code.get_syndrome(residual_edges)
    logical_parity = int(spatial_code.get_logical_error(residual_edges))
    return {"name": name, "distance": distance, "window_height": height,
            "fault_sheets": len(faults), "quiet_tail_sheets": len(inputs) - len(faults),
            "final_data_residual_mask": residual, "logical_parity": logical_parity, "sheets": records}


def named_faults(distance: int, graph: dict[str, Any]) -> list[tuple[str, list[tuple[int, int]]]]:
    """Choose deterministic boundary, transverse, measurement, burst and continuous streams."""
    spatial = graph["spatial_edges"]
    data_bits, measurement_bits = len(spatial), len(graph["syndrome_coordinates"])
    west = next(i for i, (u, _v) in enumerate(spatial) if u == (0, -1))
    east = next(i for i, (_u, v) in enumerate(spatial) if v == (distance - 1, distance - 1))
    south = next(i for i, (u, v) in enumerate(spatial) if u[0] + 1 == v[0])
    far_south = (distance - 1) * (distance - 1) - 1
    rng = random.Random(0x53555246 + distance)
    continuous = [(sum((rng.random() < 0.025) << bit for bit in range(data_bits)),
                   sum((rng.random() < 0.025) << bit for bit in range(measurement_bits))) for _ in range(96)]
    burst = [(0, 0)] * 4 + [((1 << data_bits) - 1, 1), (3, 0),
            (0, (1 << measurement_bits) - 1), (1 << west, 1)] + [(0, 0)] * 8
    return [("zero", [(0, 0)] * 12), ("west_boundary", [(1 << west, 0)]),
            ("east_boundary", [(1 << east, 0)]), ("north_transverse", [(1 << south, 0)]),
            ("south_transverse", [(1 << far_south, 0)]), ("measurement_pair", [(0, 1), (0, 0)]),
            ("repeated_measurement", [(0, 1 << (measurement_bits // 2))] * (2 * distance) + [(0, 0)]),
            ("burst", burst), ("continuous", continuous)]


def main() -> None:
    """Write isolated surface fixtures and provenance without touching repetition witnesses."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=repetition.CACHE / "localuf")
    parser.add_argument("--output", type=Path, default=repetition.ROOT / "workloads/hls_snowflake/priv/fixtures")
    args = parser.parse_args()
    _repetition, snowflake = repetition.load_reference(args.reference)
    from localuf import Surface
    args.output.mkdir(parents=True, exist_ok=True)
    graphs = {d: geometry(make_decoder(d, Surface, snowflake)) for d in (3, 5)}
    common = {"schema": "snowflake-surface-fixtures-v1", "reference_revision": repetition.REVISION,
              "noise": "phenomenological", "code": "unrotated planar surface, one CSS sector",
              "schedule": "2:1", "merger": "fast", "unrooter": "full",
              "node_fields": repetition.NODE_FIELDS, "edge_fields": ["growth", "correction"],
              "pointers": POINTERS, "time_unit": "algorithmic phases, not hardware cycles"}
    named = [run_case(f"surface_d{d}_{name}", d, faults, Surface, snowflake)
             for d in (3, 5) for name, faults in named_faults(d, graphs[d])
             if d == 3 or name in ("burst", "continuous")]
    unrooting = next(case for case in named if case["name"] == "surface_d3_repeated_measurement")
    assert any(phase["reset_nodes"] for sheet in unrooting["sheets"] for phase in sheet["phases"]), \
        "The explicit unrooting witness must enter RESET."
    # Exactly zero or one fault in all 19 locations per sheet, across three d=3 sheets.
    enumerated = [run_case("surface_d3_w0", 3, [(0, 0)] * 3, Surface, snowflake, detailed=False)]
    for position in range(57):
        sheet, bit = divmod(position, 19)
        faults = [(0, 0)] * 3
        faults[sheet] = (1 << bit, 0) if bit < 13 else (0, 1 << (bit - 13))
        case = run_case(f"surface_d3_w1_{position}", 3, faults, Surface, snowflake, detailed=False)
        assert case["logical_parity"] == 0, case["name"]
        enumerated.append(case)
    documents = {"surface-named.json": {**common, "geometries": list(graphs.values()), "cases": named},
                 "surface-enumerated.json": {**common, "enumeration": {"distance": 3, "sheets": 3,
                                            "fault_positions": 57, "maximum_weight": 1}, "cases": enumerated}}
    summary = {}
    for name, document in documents.items():
        payload = (json.dumps(document, separators=(",", ":")) + "\n").encode()
        (args.output / name).write_bytes(payload)
        summary[name] = {"sha256": hashlib.sha256(payload).hexdigest(), "cases": len(document["cases"]),
                         "sheets": sum(len(case["sheets"]) for case in document["cases"]),
                         "odd_final_logical_parities": sum(case["logical_parity"] for case in document["cases"])}
    provenance = {"schema": "snowflake-surface-reference-provenance-v1", "repository": "https://github.com/timchan0/localuf",
                  "revision": repetition.REVISION, "version": "3.4.4", "license": "MIT",
                  "python": platform.python_version(), "fixtures": summary,
                  "source_sha256": {name: hashlib.sha256((args.reference / name).read_bytes()).hexdigest()
                                    for name in ("localuf/codes.py", "localuf/decoders/snowflake/main.py")},
                  "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  "observer_helpers_sha256": hashlib.sha256(Path(repetition.__file__).read_bytes()).hexdigest(),
                  "requirements_sha256": hashlib.sha256(Path(__file__).with_name("requirements.lock").read_bytes()).hexdigest()}
    (args.output / "surface-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    for case in named:
        phases = [phase for sheet in case["sheets"] for phase in sheet["phases"]]
        print(case["name"], "reset-node phases", sum(phase["reset_nodes"] for phase in phases),
              "transfers", sum(len(phase["transfers"]) for phase in phases))


if __name__ == "__main__":
    main()
