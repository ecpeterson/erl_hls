import test from "node:test";
import assert from "node:assert/strict";
import { sinkRows } from "../web/sink-paths.js";
import {
  sinkSelections,
  selectedSinkPath,
  visibleSink,
} from "../web/sink-view.js";

// Two sinks share a reconvergent prefix; only the chosen endpoint belongs in
// a focused view. The alternate prefix is 0.3 ns shorter.
function fixture(unknown = false) {
  const cone = {
    id: "data/4,5",
    role: "data",
    pinIndices: [0, 1, 2, 3, 4, 5],
    rootPins: [4, 5],
    frontiers: [
      { pin: 0, kind: "sequential" },
      { pin: 1, kind: "sequential" },
    ],
    arcIndices: [0, 1, 2, 3, 4],
    pinArrivals: {
      registered: [0, 0, 0.4, 1, 1.3, unknown ? null : 1.1],
      static: [0, 0, 0.4, 1, 1.3, unknown ? null : 1.1],
    },
    coverage: {
      cyclic: false,
      unsupportedFrontiers: 0,
      missingTiming: unknown ? 1 : 0,
    },
    registeredTiming: {
      status: unknown ? "unknown" : "known",
      reasons: unknown ? ["missing_registered_path_timing"] : [],
    },
  };
  const index = {
    cones: [cone],
    arcGeometry: [
      [0, 2, 0, 0.1],
      [1, 2, 0, 0.4],
      [2, 3, 1, 0.6],
      [3, 4, 0, 0.3],
      [3, 5, 0, unknown ? null : 0.1],
    ],
    pinGeometry: ["a/Q", "b/Q", "lut/I", "lut/O", "sink-a/D", "sink-b/D"].map(
      (name, i) => [i, i, 0, name],
    ),
    writes: new Map(),
    model: { events: new Map() },
  };
  const layers = [{ cycle: 3, cones: [cone], operations: [] }];
  return { index, cone, layers, rows: sinkRows(index, layers) };
}
const ids = (selection, id) => [...selection.get(id).arcIds].sort();
test("view modes choose full, all-sink or exact selected-endpoint chains", () => {
  const { index, cone, layers, rows } = fixture();
  assert.equal(sinkSelections(index, layers), null);
  const all = sinkSelections(index, layers, { mode: "per-sink" });
  assert.deepEqual(ids(all, cone.id), [1, 2, 3, 4]);
  assert.deepEqual([...all.get(cone.id).rootPins], [4, 5]);
  assert.equal(all.get(cone.id).pathCosts.get(1), 1.3);
  const sink = rows.find((r) => r.pin === 5);
  const one = sinkSelections(index, layers, { mode: "selected", sink });
  assert.deepEqual(ids(one, cone.id), [1, 2, 4]);
  assert.deepEqual([...one.get(cone.id).rootPins], [5]);
  assert.equal(one.get(cone.id).pathCosts.get(1), 1.1);
  assert.equal(selectedSinkPath(index, sink).targetPin, 5);
});
test("near-longest alternatives expand only the chosen sink's closure", () => {
  const { index, cone, layers, rows } = fixture();
  const sink = rows.find((r) => r.pin === 5);
  assert.deepEqual(
    ids(
      sinkSelections(index, layers, { mode: "near", sink, marginNs: 0 }),
      cone.id,
    ),
    [1, 2, 4],
  );
  const near = sinkSelections(index, layers, {
    mode: "near",
    sink,
    marginNs: 0.31,
  });
  assert.deepEqual(ids(near, cone.id), [0, 1, 2, 4]);
  assert.ok(Math.abs(near.get(cone.id).pathCosts.get(0) - 0.8) < 1e-12);
});
test("unknown endpoints do not acquire representative chains from known siblings", () => {
  const { index, cone, layers, rows } = fixture(true);
  const sink = rows.find((r) => r.pin === 5);
  assert.equal(selectedSinkPath(index, sink), null);
  const one = sinkSelections(index, layers, { mode: "selected", sink });
  assert.deepEqual(ids(one, cone.id), []);
  assert.deepEqual([...one.get(cone.id).rootPins], [5]);
  const near = sinkSelections(index, layers, { mode: "near", sink });
  assert.deepEqual(ids(near, cone.id), [0, 1, 2, 4]);
  assert.ok([...near.get(cone.id).pathCosts.values()].every((v) => v === null));
});
test("filtering the selected sink away clears its path and arc membership", () => {
  const { index, layers, rows } = fixture();
  const selected = rows[0];
  assert.equal(visibleSink(rows, selected.key), selected);
  assert.equal(
    visibleSink(
      rows.filter((r) => r.key !== selected.key),
      selected.key,
    ),
    null,
  );
  assert.equal(selectedSinkPath(index, null), null);
  assert.equal(
    sinkSelections(index, layers, { mode: "selected", sink: null }).size,
    0,
  );
  assert.equal(
    sinkSelections(index, [], { mode: "selected", sink: selected }).size,
    0,
  );
  assert.throws(
    () => sinkSelections(index, layers, { mode: "surprise" }),
    /Invalid/,
  );
  assert.throws(
    () => sinkSelections(index, layers, { marginNs: -1 }),
    /Invalid/,
  );
});

// A conservative rejection in one overlapping cone leaves the merged sink
// unknown, even though another cone supplies a finite alternative for that pin.
test("merged unknown sinks retain markers and unthresholded unknown alternatives", () => {
  const { index, cone, layers } = fixture();
  const unknown = structuredClone(cone);
  unknown.id = "unknown/5";
  unknown.rootPins = [5];
  unknown.coverage.unsupportedFrontiers = 1;
  unknown.pinArrivals.registered.fill(null);
  unknown.pinArrivals.static.fill(null);
  index.cones.push(unknown);
  layers[0].cones.push(unknown);
  const sink = sinkRows(index, layers).find((row) => row.pin === 5);
  assert.equal(sink.status, "unknown");
  assert.equal(sink.knownDelayNs, 1.1);
  assert.equal(selectedSinkPath(index, sink), null);
  const all = sinkSelections(index, layers, { mode: "per-sink" });
  // Sink 4 remains known; its shared prefix can still be displayed for sink 4.
  assert.deepEqual(ids(all, cone.id), [1, 2, 3]);
  assert.deepEqual(ids(all, unknown.id), []);
  assert.deepEqual([...all.get(cone.id).rootPins], [4, 5]);
  const selected = sinkSelections(index, layers, { mode: "selected", sink });
  for (const id of [cone.id, unknown.id]) {
    assert.deepEqual(ids(selected, id), []);
    assert.deepEqual([...selected.get(id).rootPins], [5]);
  }
  for (const marginNs of [0, 100]) {
    const near = sinkSelections(index, layers, {
      mode: "near",
      sink,
      marginNs,
    });
    for (const id of [cone.id, unknown.id]) {
      assert.deepEqual(ids(near, id), [0, 1, 2, 4]);
      assert(
        [...near.get(id).pathCosts.values()].every((cost) => cost === null),
      );
    }
  }
});
