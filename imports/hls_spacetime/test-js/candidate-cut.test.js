import test from "node:test";
import assert from "node:assert/strict";
import { candidateCut } from "../web/candidate-cut.js";

const near = (a, b) => Math.abs(a - b) < 1e-11;
const sorted = (rows) => [...rows].sort((a, b) => a - b);
const baseEdges = [
  [0, 1, 0, 0.2],
  [1, 2, 1, 1],
  [2, 3, 0, 0.3],
  [7, 4, 0, 1],
  [3, 5, 1, 0.8],
  [4, 5, 1, 0.4],
  [5, 6, 0, 0.2],
];
/** Exhaustive path enumeration is an independent small-DAG timing oracle. It
 * supplies fixture arrivals, not implementation helper results or a native proof. */
function paths(edges, sources, sink) {
  const result = [];
  function walk(pin, ids, delay) {
    assert(ids.length <= edges.length, "fixture cycle");
    if (pin === sink) result.push({ ids, delay });
    edges.forEach(([from, to, , cost], id) => {
      if (from === pin)
        walk(
          to,
          [...ids, id],
          delay === null || cost === null ? null : delay + cost,
        );
    });
  }
  for (const pin of sources) walk(pin, [], 0);
  return result;
}
function fixture({ edges = baseEdges, secondKind = "sequential" } = {}) {
  const pinGeometry = [
    [0, 0, 0, "launch/Q"],
    [1, 1, 0, "a/I"],
    [1, 2, 0, "a/O"],
    [2, 3, 0, "b/I0"],
    [2, 3, 1, "b/I1"],
    [2, 4, 0, "b/O"],
    [0, 5, 0, "launch/D"],
    [3, 0, 1, "side/Q"],
  ];
  const frontiers = [
    { pin: 0, kind: "sequential" },
    { pin: 7, kind: secondKind },
  ];
  const pinIndices = pinGeometry.map((_, pin) => pin);
  const arrivals = (scope) =>
    pinIndices.map((pin) => {
      const rows = paths(
        edges,
        frontiers
          .filter((f) => scope === "static" || f.kind === "sequential")
          .map((f) => f.pin),
        pin,
      );
      return !rows.length
        ? "not_applicable"
        : rows.some((p) => p.delay === null)
          ? null
          : Math.max(...rows.map((p) => p.delay));
    });
  const cone = {
    id: "data/6",
    role: "data",
    rootPins: [6],
    pinIndices,
    arcIndices: edges.map((_, i) => i),
    frontiers,
    pinArrivals: {
      registered: arrivals("registered"),
      static: arrivals("static"),
    },
    coverage: { cyclic: false, unsupportedFrontiers: 0 },
  };
  const index = {
    pinGeometry,
    arcGeometry: structuredClone(edges),
    cones: [cone],
  };
  return {
    index,
    cone,
    layers: [{ cycle: 3, cones: [cone] }],
    sink: { pin: 6, role: "data" },
  };
}
const analyze = (f, thresholdNs, scope = "registered") =>
  candidateCut(f.index, f.layers, f.sink, { thresholdNs, scope });
function checkOracle(f, result, scope = "registered") {
  assert.equal(result.status, "known");
  const sources = f.cone.frontiers
    .filter((row) => scope === "static" || row.kind === "sequential")
    .map((row) => row.pin);
  const allPaths = paths(f.index.arcGeometry, sources, f.sink.pin);
  const crossing = new Set(result.crossingArcIds),
    before = new Set(result.beforeArcIds),
    after = new Set(result.afterArcIds);
  let firstMaximum = 0,
    secondMaximum = 0;
  const signals = new Set();
  for (const path of allPaths) {
    const cuts = path.ids.filter((arc) => crossing.has(arc));
    assert.equal(cuts.length, 1, "every eligible path crosses exactly once");
    const at = path.ids.indexOf(cuts[0]);
    assert(path.ids.slice(0, at).every((arc) => before.has(arc)));
    assert(path.ids.slice(at).every((arc) => after.has(arc)));
    const sum = (ids) =>
      ids.reduce((n, arc) => n + f.index.arcGeometry[arc][3], 0);
    firstMaximum = Math.max(firstMaximum, sum(path.ids.slice(0, at)));
    secondMaximum = Math.max(secondMaximum, sum(path.ids.slice(at)));
    signals.add(f.index.arcGeometry[cuts[0]][0]);
  }
  assert(near(result.stage1DelayNs, firstMaximum));
  assert(near(result.stage2DelayNs, secondMaximum));
  assert.equal(result.crossingSignals, signals.size);
  assert(
    result.crossingArcIds.every((arc) => f.index.arcGeometry[arc][2] === 0),
  );
}

test("full reconvergent fan-in includes the late side source and preserves Q/D boundaries", () => {
  const f = fixture(),
    original = structuredClone(f.index),
    result = analyze(f, 1.3);
  checkOracle(f, result);
  assert(near(result.originalDelayNs, 2.5));
  assert(near(result.stage1DelayNs, 1.2));
  assert(near(result.stage2DelayNs, 1.6));
  assert(!near(result.stage2DelayNs, result.originalDelayNs - 1.3));
  assert.equal(result.signalBits, 2);
  assert.equal(result.alignmentSourceBits, 1);
  assert.deepEqual(
    result.crossings.map((row) => row.fromPin),
    [2, 7],
  );
  assert.equal(result.crossings[1].alignmentSource, true);
  assert.equal(result.crossings[1].name, "side/Q");
  assert.deepEqual(result.crossings[0].point, { x: 2, y: 0 });
  assert.equal(result.alignmentComplete, true);
  assert(result.beforePins.includes(0) && result.afterPins.includes(6));
  assert.deepEqual(f.index, original);
  assert.deepEqual(
    sorted(result.selection.get(f.cone.id).arcIds),
    f.cone.arcIndices,
  );
  assert.deepEqual([...result.selection.get(f.cone.id).rootPins], [6]);
});

test("a threshold inside a logic cell leaves the entire cell after the cut", () => {
  const f = fixture(),
    result = analyze(f, 0.5);
  checkOracle(f, result);
  assert(result.afterPins.includes(1) && result.afterPins.includes(2));
  assert.equal(result.stage1DelayNs, 0);
  assert(near(result.stage2DelayNs, result.originalDelayNs));
  assert.deepEqual(
    result.crossings.map((row) => row.fromPin),
    [0, 7],
  );
});

test("a shared driver crosses once even when it feeds several input pins", () => {
  const edges = baseEdges.map((row) => [...row]);
  edges[3] = [2, 4, 0, 0.5];
  const f = fixture({ edges }),
    result = analyze(f, 1.3);
  checkOracle(f, result);
  assert.equal(result.signalBits, 1);
  assert.equal(result.crossingFanout, 2);
  assert.deepEqual(result.crossings[0].toPins, [3, 4]);
  assert.deepEqual(result.crossings[0].arcIds, [2, 3]);
});

test("unit prefix cannot admit a fast downstream cell before its whole predecessor", () => {
  // a has a slow output going directly to the sink and a fast output feeding b.
  // b's own 0.4 ns bound fits the threshold, but indivisible a must stay after.
  const edges = [
    [0, 1, 0, 0.1],
    [1, 2, 1, 2],
    [1, 4, 1, 0.1],
    [4, 3, 0, 0.1],
    [3, 5, 1, 0.1],
    [2, 6, 0, 0.1],
    [5, 6, 0, 0.1],
  ];
  const f = fixture({ edges });
  f.index.pinGeometry[4][0] = 1;
  const result = analyze(f, 0.5);
  checkOracle(f, result);
  assert(result.afterPins.includes(4) && result.afterPins.includes(5));
  assert(near(f.cone.pinArrivals.registered[5], 0.4));
  assert.deepEqual(
    result.crossings.map((row) => row.fromPin),
    [0],
  );
});

test("external side inputs stay disclosed and do not acquire fabricated registered timing", () => {
  const edges = baseEdges.map((row) => [...row]);
  edges[3][3] = null;
  const f = fixture({ edges, secondKind: "external" }),
    result = analyze(f, 1.3);
  checkOracle(f, result);
  assert.equal(result.signalBits, 1);
  assert.equal(result.alignmentComplete, false);
  assert.deepEqual(result.outsideArcIds, [3, 5]);
  assert.deepEqual(
    result.sideInputs.map((row) => [
      row.pin,
      row.kind,
      row.feedsStage1,
      row.feedsStage2,
      row.alignmentRequired,
    ]),
    [[7, "external", false, true, true]],
  );
  assert.equal(analyze(f, 1.3, "static").reason, "unknown_eligible_timing");
  const later = analyze(f, 3);
  assert.equal(later.sideInputs[0].feedsStage1, true);
  assert.equal(later.sideInputs[0].alignmentRequired, false);
});

test("explicit constant-frontier crossings need no added register bit", () => {
  const f = fixture({ secondKind: "constant" }),
    result = analyze(f, 1.3, "static");
  checkOracle(f, result, "static");
  assert.equal(result.crossingSignals, 2);
  assert.equal(result.signalBits, 1);
  assert.equal(
    result.crossings.find((row) => row.fromPin === 7).requiresRegister,
    false,
  );
  assert.equal(result.alignmentSourceBits, 0);
});

test("small DAG enumeration checks both stage maxima across weights and thresholds", () => {
  for (let bits = 0; bits < 32; bits++) {
    const edges = baseEdges.map((row, i) => [
      row[0],
      row[1],
      row[2],
      i < 5 ? ((bits >> i) & 1) * 0.5 : row[3],
    ]);
    const f = fixture({ edges });
    for (const threshold of [0, 0.25, 0.75, 2, 10])
      checkOracle(f, analyze(f, threshold));
  }
});

test("all contributing cones and complete ancestry remain selected without sibling sink branches", () => {
  const f = fixture();
  const second = { ...f.cone, id: "other/data/6" };
  f.index.cones.push(second);
  f.layers.push({ cycle: 4, cones: [second] });
  f.index.pinGeometry.push([4, 4, 2, "other/D"]);
  f.index.arcGeometry.push([2, 8, 0, 9]);
  f.cone.arcIndices.push(7);
  f.cone.pinIndices.push(8);
  f.cone.rootPins.push(8);
  f.cone.pinArrivals.registered.push(10.2);
  f.cone.pinArrivals.static.push(10.2);
  const result = analyze(f, 1.3);
  assert.equal(result.status, "known");
  assert.equal(result.selection.size, 2);
  assert(!result.includedArcIds.includes(7));
  for (const row of result.selection.values()) assert(!row.arcIds.has(7));
});

test("unknown timing, unsupported frontiers and cycles fail closed", () => {
  const unknown = fixture();
  unknown.index.arcGeometry[2][3] = null;
  const result = analyze(unknown, 1);
  assert.equal(result.reason, "unknown_eligible_timing");
  assert.equal(result.stage1DelayNs, null);
  assert.equal(result.stage2DelayNs, null);
  assert.equal(result.signalBits, null);
  const unsupported = fixture();
  unsupported.cone.coverage.unsupportedFrontiers = 1;
  assert.equal(
    analyze(unsupported, 1).reason,
    "unsupported_or_missing_frontier",
  );
  const cycle = fixture();
  cycle.index.arcGeometry.push([5, 1, 0, 0.2]);
  cycle.cone.arcIndices.push(7);
  assert.equal(analyze(cycle, 1).reason, "cycle");
  const stale = fixture();
  stale.cone.pinArrivals.registered[6] = null;
  assert.equal(analyze(stale, 1).reason, "unknown_saved_sink_arrival");
});

test("cell contraction cycles fail even when the pin graph is acyclic", () => {
  const f = fixture();
  f.index.pinGeometry[5][0] = 1;
  f.index.pinGeometry[3][0] = 1;
  f.index.pinGeometry[4][0] = 1;
  // Separate pins of a common cell enclose b: grouping must not create a
  // topologically invalid boundary that returns from stage 2 to stage 1.
  f.index.pinGeometry[2][0] = 2;
  f.index.pinGeometry[1][0] = 2;
  f.index.pinGeometry[0][0] = 1;
  // A genuine a -> b -> a unit pattern with all native logic arcs intact.
  f.index.pinGeometry.push([2, 6, 0, "a/I2"], [2, 7, 0, "a/O2"]);
  f.index.arcGeometry[6] = [5, 8, 0, 0.2];
  f.index.arcGeometry.push([8, 9, 1, 0.2], [9, 6, 0, 0.2]);
  f.cone.arcIndices.push(7, 8);
  f.cone.pinIndices.push(8, 9);
  f.cone.pinArrivals.registered = f.cone.pinIndices.map((pin) =>
    Math.max(
      ...paths(f.index.arcGeometry, [0, 7], pin).map((row) => row.delay),
    ),
  );
  f.cone.pinArrivals.static = [...f.cone.pinArrivals.registered];
  assert.equal(analyze(f, 2).reason, "indivisible_cell_cycle");
});

test("cache keys include scope, threshold and visible cone population; cache eviction is bounded", () => {
  const f = fixture(),
    first = analyze(f, 1);
  assert.equal(analyze(f, 1), first);
  assert.notEqual(analyze(f, 1, "static"), first);
  assert.notEqual(analyze(f, 2), first);
  assert.equal(
    candidateCut(f.index, [], f.sink, { thresholdNs: 1 }).reason,
    "sink_not_visible",
  );
  for (let n = 3; n < 12; n++) analyze(f, n);
  assert.notEqual(analyze(f, 1), first);
  assert.throws(() => analyze(f, -1), /threshold/);
  assert.throws(() => analyze(f, Infinity), /threshold/);
  assert.throws(() => analyze(f, 1, "made_up"), /scope/);
});
