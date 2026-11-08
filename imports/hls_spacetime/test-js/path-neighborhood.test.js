import test from "node:test";
import assert from "node:assert/strict";
import { pathNeighborhood } from "../web/path-neighborhood.js";
import { sinkRows } from "../web/sink-paths.js";

/** Two near sinks share a prefix. Unrelated fanout includes remote and unlocated
 * loads with no visible write, while a colocated cell is only placement context. */
function fixture() {
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
      registered: [0, 0, 0.4, 1, 1.3, 1.25],
      static: [0, 0, 0.4, 1, 1.3, 1.25],
    },
    coverage: { cyclic: false, unsupportedFrontiers: 0, missingTiming: 0 },
  };
  const cells = [
    ["a", 0],
    ["b", 1],
    ["lut", 2],
    ["sink-a", 4],
    ["sink-b", 5],
    ["remote", 90],
    ["unlocated", null],
    ["coincident-context", 2],
    ["nearby-context", 3],
  ].map(([id, x]) => ({
    id,
    x,
    y: x === null ? null : 0,
    ref: id === "lut" ? "LUT2" : "FDRE",
  }));
  const index = {
    cones: [cone],
    arcGeometry: [
      [0, 2, 0, 0.1],
      [1, 2, 0, 0.4],
      [2, 3, 1, 0.6],
      [3, 4, 0, 0.3],
      [3, 5, 0, 0.25],
      [3, 6, 0, 0.2],
      [3, 6, 0, 0.2],
      [3, 7, 0, null],
    ],
    pinGeometry: [
      [0, 0, 0, "a/Q"],
      [1, 1, 0, "b/Q"],
      [2, 2, 0, "lut/I"],
      [2, 2, 0, "lut/O"],
      [3, 4, 0, "sink-a/D"],
      [4, 5, 0, "sink-b/D"],
      [5, 90, 0, "remote/D"],
      [6, null, null, "unlocated/D"],
    ],
    writes: new Map([
      ["w1", { cones: [0] }],
      ["w2", { cones: [0] }],
    ]),
    model: {
      catalogue: { cells },
      events: new Map(
        ["w1", "w2"].map((id, i) => [
          id,
          { id, cycle: i + 3, access: { kind: "write", resource: "word" } },
        ]),
      ),
    },
  };
  const layers = [3, 4].map((cycle, i) => ({
    cycle,
    cones: [cone],
    operations: [{ event: `w${i + 1}` }],
  }));
  return {
    index,
    cone,
    layers,
    sink: sinkRows(index, layers).find((row) => row.pin === 4),
  };
}
const approx = (actual, expected) =>
  assert.ok(Math.abs(actual - expected) < 1e-10);

/** Append an independent sink without making existing source arrays inconsistent. */
function extra(
  f,
  { id, delay = 1.3, x = 4, role = "data", unknown = false, outside = false },
) {
  const pin = f.index.pinGeometry.length,
    cell = f.index.model.catalogue.cells.length,
    arc = f.index.arcGeometry.length;
  f.index.pinGeometry.push([cell, x, x === null ? null : 0, `${id}/D`]);
  f.index.model.catalogue.cells.push({
    id,
    x,
    y: x === null ? null : 0,
    ref: "FDRE",
  });
  f.index.arcGeometry.push([3, pin, 0, unknown ? null : delay - 1]);
  const value = unknown ? null : outside ? "not_applicable" : delay;
  const cone = {
    ...f.cone,
    id,
    role,
    rootPins: [pin],
    pinIndices: [...f.cone.pinIndices, pin],
    arcIndices: [...f.cone.arcIndices, arc],
    pinArrivals: {
      registered: [...f.cone.pinArrivals.registered, value],
      static: [...f.cone.pinArrivals.static, value],
    },
  };
  f.index.cones.push(cone);
  for (const layer of f.layers) layer.cones.push(cone);
  return pin;
}

test("family membership filters timing and native position while allowing every role", () => {
  const f = fixture();
  const enabled = extra(f, { id: "enable", role: "enable", delay: 1.2 });
  extra(f, { id: "far", x: 40, delay: 1.3 });
  extra(f, { id: "slow", delay: 2 });
  const before = structuredClone(f.index);
  const result = pathNeighborhood(f.index, f.layers, f.sink, {
    paddingTiles: 2,
  });
  assert.deepEqual(result.region, { minX: -1, maxX: 6, minY: -2, maxY: 2 });
  assert.deepEqual(
    new Set(result.members.map((row) => row.pin)),
    new Set([4, 5, enabled]),
  );
  assert.equal(result.summary.outsideRegionSinks, 1);
  assert.equal(result.summary.outsideMarginSinks, 1);
  assert.equal(result.summary.memberWriteAssociations, 2);
  assert.equal(result.summary.memberClocks, 2);
  assert.deepEqual(result.members.find((row) => row.pin === 4).sourcePoint, {
    x: 1,
    y: 0,
  });
  assert.deepEqual(f.index, before);
  assert.equal(
    pathNeighborhood(
      f.index,
      f.layers,
      { key: f.sink.key },
      { paddingTiles: 2 },
    ),
    result,
  );
  assert.notEqual(
    pathNeighborhood(f.index, f.layers, f.sink, { paddingTiles: 3 }),
    result,
  );
});

test("prefix and shared arcs count identities once per member despite repeated clocks/cones", () => {
  const f = fixture(),
    duplicate = structuredClone(f.cone);
  duplicate.id = "second-contributor";
  f.index.cones.push(duplicate);
  for (const layer of f.layers) layer.cones.push(duplicate);
  const result = pathNeighborhood(f.index, f.layers, f.sink, {
    paddingTiles: 2,
  });
  assert.equal(result.members.length, 2);
  const second = result.members.find((row) => row.pin === 5);
  assert.equal(second.sharedArcCount, 2);
  assert.equal(second.sharedPrefixArcs, 2);
  approx(second.sharedPrefixNs, 1);
  assert.equal(result.arcUse.get(1), 2);
  assert.equal(result.arcUse.get(2), 2);
  assert.equal(result.arcUse.get(3), 1);
  assert.equal(result.arcUse.get(4), 1);
  assert.equal(result.arcUse.has(0), false);
  assert.equal(result.summary.sharedArcs, 2);
  assert.equal(result.summary.additionalConeRepresentatives, 2);
  for (const id of [f.cone.id, duplicate.id]) {
    const selected = result.selection.get(id);
    assert.deepEqual([...selected.arcIds].sort(), [1, 2, 3, 4]);
    assert.deepEqual([...selected.rootPins].sort(), [4, 5]);
    approx(selected.pathCosts.get(1), 1.3);
    approx(selected.pathCosts.get(4), 1.25);
  }
});

test("full represented fanout includes unrelated, outside-region and unlocated loads", () => {
  const f = fixture();
  const result = pathNeighborhood(f.index, f.layers, f.sink, {
    paddingTiles: 2,
  });
  const fanout = result.fanouts[0];
  assert.equal(fanout.pin, 3);
  assert.equal(fanout.name, "lut/O");
  assert.deepEqual(fanout.point, { x: 2, y: 0 });
  assert.equal(fanout.familySinkPins, 2);
  assert.equal(fanout.totalSinkPins, 4);
  assert.deepEqual(
    fanout.sinks.map((row) => row.pin),
    [4, 5, 6, 7],
  );
  assert.equal(fanout.sinks.find((row) => row.pin === 6).insideRegion, false);
  assert.deepEqual(fanout.sinks.find((row) => row.pin === 6).point, {
    x: 90,
    y: 0,
  });
  assert.equal(fanout.sinks.find((row) => row.pin === 7).point, null);
  assert.equal(fanout.sinks.find((row) => row.pin === 7).insideRegion, false);
});

test("placement context is complete inside the region and never merged by coordinates", () => {
  const f = fixture();
  const result = pathNeighborhood(f.index, f.layers, f.sink, {
    paddingTiles: 2,
  });
  assert.deepEqual(
    result.cells.map((row) => row.index),
    [0, 1, 2, 3, 4, 7, 8],
  );
  assert.equal(result.cells.find((row) => row.index === 2).kind, "family");
  assert.equal(result.cells.find((row) => row.index === 7).kind, "context");
  assert.equal(result.cells.find((row) => row.index === 0).kind, "context");
  assert.equal(result.summary.familyCells, 4);
  assert.equal(result.summary.contextCells, 3);
  assert.equal(result.summary.unlocatedCells, 1);
});

test("unknown, outside-scope and unlocated candidates never receive invented membership", () => {
  const f = fixture();
  const unknown = extra(f, { id: "unknown", unknown: true });
  const outside = extra(f, { id: "outside", outside: true });
  const unlocated = extra(f, { id: "no-location", x: null });
  const result = pathNeighborhood(f.index, f.layers, f.sink, {
    paddingTiles: 2,
  });
  assert.deepEqual(result.members.map((row) => row.pin).sort(), [4, 5]);
  assert.equal(result.summary.unknownSinks, 1);
  assert.equal(result.summary.outsideScopeSinks, 1);
  assert.equal(result.summary.unlocatedSinks, 1);
  const rows = sinkRows(f.index, f.layers);
  for (const [pin, status] of [
    [unknown, "unknown_selection"],
    [outside, "outside_scope_selection"],
    [unlocated, "unlocated_selection"],
  ]) {
    const empty = pathNeighborhood(
      f.index,
      f.layers,
      rows.find((row) => row.pin === pin),
    );
    assert.equal(empty.region, null);
    assert.equal(empty.members.length, 0);
    assert.equal(empty.selection.size, 0);
    assert.equal(empty.summary.status, status);
  }
  assert.equal(
    pathNeighborhood(f.index, [], f.sink).summary.status,
    "no_selection",
  );
});

test("zero tolerance, scopes and input bounds remain explicit", () => {
  const f = fixture();
  assert.equal(
    pathNeighborhood(f.index, f.layers, f.sink, {
      marginNs: 0,
      paddingTiles: 2,
    }).members.length,
    1,
  );
  assert.equal(
    pathNeighborhood(f.index, f.layers, f.sink, {
      scope: "static",
      paddingTiles: 2,
    }).members.length,
    2,
  );
  for (const options of [
    { marginNs: -1 },
    { paddingTiles: null },
    { paddingTiles: Infinity },
    { scope: "invented" },
  ])
    assert.throws(
      () => pathNeighborhood(f.index, f.layers, f.sink, options),
      /Invalid/,
    );
});
