import test from "node:test";
import assert from "node:assert/strict";
import {
  createComputations,
  computationLayers,
} from "../web/computation-routes.js";
import { prepareRenderData } from "../scripts/prepare-render.mjs";
import {
  createPreparedComputations,
  preparedComputationLayers,
  preparedCircuitPaint,
} from "../web/prepared-computations.js";

/** Reconvergent two-input logic, three writes, one semantic producer and a read.
 * Only one of two logical bits has a qualified native destination. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o" };
  const cells = [
    { id: "source", kind: "FDRE", boundary: "sequential" },
    { id: "lut", kind: "LUT2", boundary: "combinational" },
    { id: "sink", kind: "FDRE", boundary: "sequential" },
    { id: "constant", kind: "VCC", boundary: "constant" },
  ];
  const pins = [
    { id: "source/Q", cell: 0, pin: "Q", direction: "OUT", net: 0 },
    { id: "lut/I0", cell: 1, pin: "I0", direction: "IN", net: 0 },
    { id: "lut/I1", cell: 1, pin: "I1", direction: "IN", net: 0 },
    { id: "lut/O", cell: 1, pin: "O", direction: "OUT", net: 1 },
    { id: "sink/D", cell: 2, pin: "D", direction: "IN", net: 1 },
    { id: "sink/CE", cell: 2, pin: "CE", direction: "IN", net: 2 },
    { id: "constant/P", cell: 3, pin: "P", direction: "OUT", net: 2 },
    { id: "sink/R", cell: 2, pin: "R", direction: "IN", net: 2 },
    { id: "sink/Q", cell: 2, pin: "Q", direction: "OUT", net: 3 },
  ];
  const timing = (ps) => ({
    fast: [{ maxPs: ps / 2, guards: [] }],
    slow: [{ maxPs: ps, guards: [] }],
  });
  const arcs = [
    { id: "n0a", kind: "net", from: 0, to: 1, net: 0, timing: timing(100) },
    { id: "n0b", kind: "net", from: 0, to: 2, net: 0, timing: timing(100) },
    { id: "logic0", kind: "logic", from: 1, to: 3, timing: timing(300) },
    { id: "logic1", kind: "logic", from: 2, to: 3, timing: timing(500) },
    { id: "n1", kind: "net", from: 3, to: 4, net: 1, timing: timing(400) },
    { id: "enable", kind: "net", from: 6, to: 5, net: 2, timing: timing(200) },
    { id: "reset", kind: "net", from: 6, to: 7, net: 2, timing: timing(200) },
  ];
  const events = new Map([
    ...["w0", "w1", "w2"].map((id, i) => [
      id,
      {
        id,
        cycle: i === 2 ? 6 : 5,
        access: { kind: "write", resource: "word", mask: "0x3" },
      },
    ]),
    ["producer", { id: "producer", cycle: 5 }],
    ["read", { id: "read", cycle: 4 }],
  ]);
  const operations = [...events.values()].map((event) => ({
    event: event.id,
    kind: event.access ? "register_write" : event.id,
    applicability: event.access ? "storage_write" : "semantic_context",
    status: "partial",
    targets: event.access ? [{ resource: "word", mask: "0x3" }] : [],
    sources: [],
    unknowns: [],
    writes: event.id === "producer" ? ["w0", "w1"] : [],
  }));
  const attachment = {
    schema: 1,
    scope: "structural_native_connectivity",
    build,
    checkpoint: "c",
    cells,
    pins,
    nets: [0, 1, 2, 3].map((n) => ({ id: `n${n}` })),
    arcs,
    bindings: [
      {
        resource: "word",
        bits: [
          { bit: 0, status: "supported", q: 8, d: 4, ce: 5, reset: 7 },
          { bit: 1, status: "unknown" },
        ],
      },
    ],
    operations,
  };
  attachment.routingComplete = true;
  const model = {
    bundle: { build },
    catalogue: { checkpoint: "c" },
    cells: new Map(
      cells.map((cell, i) => [
        cell.id,
        { ...cell, x: 10 + i * 10, y: 20 + i * 10 },
      ]),
    ),
    geometryBounds: { minX: 10, maxX: 40, minY: 20, maxY: 50 },
    resources: new Map([["word", { id: "word", width: 2 }]]),
    events,
  };
  const routeNets = attachment.nets.map((n) =>
    n.id === "n1"
      ? route()
      : {
          ...n,
          status: "complete",
          route_status: "ROUTED",
          nodes: [],
          pips: [],
          issues: [],
          pin_attachments: [],
        },
  );
  return { model, attachment, routeNets };
}

/** A native branch uses explicit assigned PIPs and exact endpoint attachment. */
function route() {
  return {
    id: "n1",
    status: "complete",
    route_status: "ROUTED",
    issues: [],
    nodes: ["a", "b"].map((id, i) => ({
      id,
      wires: [{ id: `wire-${id}`, tile: `tile-${i}`, x: i, y: 0 }],
    })),
    pips: [
      {
        id: "pip",
        tile: "tile-0",
        x: 0,
        y: 0,
        from_node: "a",
        to_node: "b",
        direction_status: "directional",
      },
    ],
    pin_attachments: [
      ["lut/O", "OUT", "a"],
      ["sink/D", "IN", "b"],
    ].map(([pin, direction, node]) => ({
      pin,
      direction,
      status: "resolved",
      bel_pins: [pin],
      routing_node: node,
      site_pins: [{ id: `site-${node}`, node }],
    })),
  };
}

test("offline preparation preserves every occurrence and shares static cones/geometry", () => {
  const { model, attachment, routeNets } = fixture();
  const source = createComputations(model, attachment, routeNets);
  const data = prepareRenderData(model, { attachment, routeNets });
  const prepared = createPreparedComputations(model, data);
  assert.equal(data.operations.length, model.events.size);
  assert.equal(data.writes.length, 3);
  assert.equal(data.cones.length, 3);
  assert.equal(data.maxDelays.registered, 1);
  assert.equal(data.maxDelays.static, 1);
  assert.equal(data.bounds.minX, 0);
  assert.equal(data.sourceCounts.routeNets, 4);
  for (const options of [
    {},
    { roles: ["data"] },
    { roles: ["enable", "reset"] },
    { minimumDelayNs: 1.1 },
    { timingMetric: "registered_launch", includeUnknownTiming: false },
  ]) {
    const old = computationLayers(source, ["producer", "w0", "w2"], options);
    const fresh = preparedComputationLayers(
      prepared,
      ["producer", "w0", "w2"],
      options,
    );
    assert.deepEqual(
      fresh.map((l) => ({
        cycle: l.cycle,
        coverage: l.coverage,
        ops: l.operations.map((o) => o.event),
        arcs: l.arcs,
        cones: l.cones.map((c) => c.id),
      })),
      old.map((l) => ({
        cycle: l.cycle,
        coverage: l.coverage,
        ops: l.operations.map((o) => o.event),
        arcs: l.arcs,
        cones: l.cones.map((c) => c.id),
      })),
    );
  }
  assert.deepEqual(preparedComputationLayers(prepared, ["read"]), []);
});

test("paint retains raw coordinates and combines roles without treating outside paths as unknown", () => {
  const { model, attachment, routeNets } = fixture();
  const prepared = createPreparedComputations(
    model,
    prepareRenderData(model, { attachment, routeNets }),
  );
  const [layer] = preparedComputationLayers(prepared, ["w0"]);
  const paint = preparedCircuitPaint(prepared, layer);
  const sink = paint.cells.find((c) => c.sourceCell === 2);
  assert.deepEqual(sink.point, { x: 30, y: 40, physical: true });
  assert.equal(sink.role, "mixed");
  assert.equal(sink.computationKey, "word");
  assert.equal(sink.computationShared, false);
  assert.deepEqual(paint.computations, ["word"]);
  assert.equal("roles" in sink, false);
  assert.equal(sink.registeredPathDelayNs, 1);
  assert.equal(sink.staticPathDelayNs, 1);
  assert.equal(sink.registeredPathTimingUnknown, false);
  assert.equal(sink.staticPathTimingUnknown, false);
  assert.equal(sink.registeredPathApplicable, true);
  assert.equal(sink.staticPathApplicable, true);
  assert.equal(paint.pips.length, 1);
  assert.equal(paint.dispositions.resolved, 1);
  assert.equal(paint.dispositions.unavailable, 4);
  assert.equal(preparedCircuitPaint(prepared, layer), paint);
  const [enable] = preparedComputationLayers(prepared, ["w0"], {
    roles: ["enable"],
  });
  const unknown = preparedCircuitPaint(prepared, enable).cells[0];
  assert.equal(unknown.registeredPathDelayNs, null);
  assert.equal(unknown.registeredPathTimingUnknown, false);
  assert.equal(unknown.registeredPathApplicable, false);
  assert.equal(unknown.computationKey, "word");
  const [nextClock] = preparedComputationLayers(prepared, ["w2"]);
  assert.equal(preparedCircuitPaint(prepared, nextClock), paint);
});

test("missing coverage, stale identities and invented references reject", () => {
  const { model, attachment, routeNets } = fixture();
  const original = prepareRenderData(model, { attachment, routeNets });
  for (const mutate of [
    (d) => (d.algorithm = 1),
    (d) => (d.algorithm = 2),
    (d) => (d.algorithm = 4),
    (d) => (d.schema = 2),
    (d) => delete d.pinGeometry,
    (d) => delete d.arcGeometry,
    (d) => d.pinGeometry.pop(),
    (d) => d.arcGeometry.pop(),
    (d) => (d.pinGeometry[0] = [d.sourceCounts.cells, 1, 2]),
    (d) => (d.pinGeometry[0] = [-1, 1, 2]),
    (d) => (d.pinGeometry[0] = [null, null, 2]),
    (d) => (d.pinGeometry[0] = [0, NaN, 2]),
    (d) => (d.pinGeometry[0] = [0, 1, Infinity]),
    (d) => (d.pinGeometry[0] = [0, 1, 2, 3]),
    (d) => (d.arcGeometry[0] = [d.sourceCounts.pins, 1, 0, 1]),
    (d) => (d.arcGeometry[0] = [0, d.sourceCounts.pins, 0, 1]),
    (d) => (d.arcGeometry[0] = [0, 1, 2, 1]),
    (d) => (d.arcGeometry[0] = [0, 1, 0, -1]),
    (d) => (d.arcGeometry[0] = [0, 1, 0, NaN]),
    (d) => (d.arcGeometry[0] = [0, 1, 0, "not_applicable"]),
    (d) => (d.arcGeometry[0] = [0, 1, 0]),
    (d) => delete d.cones[0].pinArrivals,
    (d) => d.cones[0].pinArrivals.registered.pop(),
    (d) => d.cones[0].pinArrivals.static.push(0),
    (d) => (d.cones[0].pinArrivals.registered[0] = -1),
    (d) => (d.cones[0].pinArrivals.static[0] = Infinity),
    (d) => (d.cones[0].pinArrivals.static[0] = "unknown"),
    (d) => delete d.cones[0].pinArrivals.static[0],
    (d) => delete d.cones[0].pathDelays,
    (d) => d.cones[0].pathDelays.registered.pop(),
    (d) => d.cones[0].pathDelays.static.push(0),
    (d) => (d.cones[0].pathDelays.registered[0] = -1),
    (d) => (d.cones[0].pathDelays.static[0] = "not_applicable"),
    (d) => (d.cones[0].pathDelays.registered[0] = "unknown"),
    (d) => delete d.cones[0].primitivePathDelays,
    (d) => d.cones[0].primitivePathDelays.registered.pop(),
    (d) => (d.cones[0].primitivePathDelays.registered[0] = NaN),
    (d) => (d.cones[0].primitivePathDelays.static[0] = Infinity),
    (d) => delete d.cones[0].primitivePathDelays.static[0],
    (d) => d.operations.pop(),
    (d) => d.writes.pop(),
    (d) => (d.writes[0].coverage.unknownBits = 0),
    (d) => (d.build = { ...d.build, rtl: "wrong" }),
    (d) => d.cones[0].primitives.push(999999),
    (d) => d.routes[0].primitives.push(999999),
    (d) => (d.maxDelays.registered = 99),
    (d) => (d.primitives[0].point.x = NaN),
    (d) => d.cones[0].arcIndices.push(d.sourceCounts.arcs),
    (d) => d.cones[0].rootPins.push(d.sourceCounts.pins),
    (d) => (d.primitives[0].sourceCell = d.sourceCounts.cells),
    (d) =>
      d.cones[0].arcIndices.splice(
        d.cones[0].arcIndices.indexOf(d.routes[d.cones[0].routes[0]].arc),
        1,
      ),
    (d) =>
      d.cones[0].primitives.splice(
        d.cones[0].primitives.indexOf(
          d.routes[d.cones[0].routes[0]].primitives[0],
        ),
        1,
      ),
  ]) {
    const copy = structuredClone(original);
    mutate(copy);
    assert.throws(() => createPreparedComputations(model, copy));
  }
  assert.equal(createPreparedComputations(model, null), null);
  attachment.routingComplete = false;
  assert.throws(
    () => prepareRenderData(model, { attachment, routeNets }),
    /routing must be complete/,
  );
});

/** A second logical destination may alias existing native roots, or have its own
 * FF while sharing upstream logic. Neither case assigns shared logic one owner. */
function secondDestination(separateCell) {
  const f = fixture();
  const { model, attachment } = f;
  model.resources.set("second", { id: "second", width: 2 });
  model.events.get("w1").access.resource = "second";
  attachment.operations.find((op) => op.event === "w1").targets[0].resource =
    "second";
  const binding = structuredClone(attachment.bindings[0]);
  binding.resource = "second";
  if (separateCell) {
    const cell = { id: "second-sink", kind: "FDRE", boundary: "sequential" };
    attachment.cells.push(cell);
    model.cells.set(cell.id, { ...cell, x: 50, y: 50 });
    model.geometryBounds.maxX = 50;
    attachment.pins.push(
      { id: "second-sink/D", cell: 4, pin: "D", direction: "IN", net: 1 },
      { id: "second-sink/Q", cell: 4, pin: "Q", direction: "OUT", net: 3 },
    );
    attachment.arcs.push({
      ...structuredClone(attachment.arcs.find((arc) => arc.id === "n1")),
      id: "second-sink-input",
      to: 9,
    });
    binding.bits[0] = { bit: 0, status: "supported", d: 9, q: 10 };
  }
  attachment.bindings.push(binding);
  return createPreparedComputations(
    model,
    prepareRenderData(model, {
      attachment,
      routeNets: f.routeNets,
    }),
  );
}

test("two distinct destination registers retain exclusive sinks and shared upstream membership", () => {
  const index = secondDestination(true);
  const [layer] = preparedComputationLayers(index, ["w0", "w1"]);
  const paint = preparedCircuitPaint(index, layer);
  const source = paint.cells.find((row) => row.sourceCell === 0);
  assert.equal(source.computationKey, null);
  assert.equal(source.computationShared, true);
  assert.equal(
    paint.cells.find((row) => row.sourceCell === 2).computationKey,
    "word",
  );
  assert.equal(
    paint.cells.find((row) => row.sourceCell === 4).computationKey,
    "second",
  );
  assert.deepEqual(paint.computations, ["second", "word"]);
});

test("aliased roots have selection-specific membership and cannot reuse wrong cached colors", () => {
  const index = secondDestination(false);
  const selected = (ids) => preparedComputationLayers(index, ids)[0];
  const firstLayer = selected(["w0"]),
    secondLayer = selected(["w1"]);
  assert.deepEqual(
    firstLayer.cones.map((c) => c.id),
    secondLayer.cones.map((c) => c.id),
  );
  const first = preparedCircuitPaint(index, firstLayer);
  const second = preparedCircuitPaint(index, secondLayer);
  assert.notEqual(first.cacheKey, second.cacheKey);
  assert.notEqual(first, second);
  assert(
    first.cells.every(
      (row) => row.computationKey === "word" && !row.computationShared,
    ),
  );
  assert(
    second.cells.every(
      (row) => row.computationKey === "second" && !row.computationShared,
    ),
  );
  const shared = preparedCircuitPaint(index, selected(["w0", "w1"]));
  assert(
    shared.cells.every(
      (row) => row.computationKey === null && row.computationShared,
    ),
  );
  assert.deepEqual(shared.computations, ["second", "word"]);
  assert.equal(preparedCircuitPaint(index, selected(["w1", "w0"])), shared);
  assert.equal(preparedCircuitPaint(index, selected(["w0"])), first);
  assert.deepEqual(first.computations, ["word"]);
});

test("geometry without displayed write associations leaves destination membership unknown", () => {
  const index = secondDestination(false);
  const [layer] = preparedComputationLayers(index, ["w0"]);
  const associated = preparedCircuitPaint(index, layer);
  const { operations, ...geometryOnly } = layer;
  const unassociated = preparedCircuitPaint(index, geometryOnly);
  assert.notEqual(associated.cacheKey, unassociated.cacheKey);
  assert.deepEqual(unassociated.computations, []);
  assert(
    unassociated.cells.every(
      (row) => row.computationKey === null && !row.computationShared,
    ),
  );
});

test("unknown cone membership dominates a known owner in either traversal order", () => {
  for (const reverse of [false, true]) {
    const index = secondDestination(true);
    const [layer] = preparedComputationLayers(index, ["w0", "w1"]);
    const paint = preparedCircuitPaint(index, {
      ...layer,
      operations: layer.operations.filter(
        (operation) => operation.event === "w0",
      ),
      cones: reverse ? [...layer.cones].reverse() : layer.cones,
    });
    const sharedSource = paint.cells.find((row) => row.sourceCell === 0);
    assert.equal(sharedSource.computationKey, null);
    assert.equal(sharedSource.computationShared, false);
    assert.equal(sharedSource.computationUnknown, true);
    const knownSink = paint.cells.find((row) => row.sourceCell === 2);
    assert.equal(knownSink.computationKey, "word");
    assert.equal(knownSink.computationUnknown, false);
    const unknownSink = paint.cells.find((row) => row.sourceCell === 4);
    assert.equal(unknownSink.computationKey, null);
    assert.equal(unknownSink.computationShared, false);
    assert.equal(unknownSink.computationUnknown, true);
    assert.deepEqual(paint.computations, ["word"]);
  }
});

test("short and long reconvergent branches retain their own complete path cost", () => {
  const { model, attachment, routeNets } = fixture();
  const index = createPreparedComputations(
    model,
    prepareRenderData(model, { attachment, routeNets }),
  );
  const [layer] = preparedComputationLayers(index, ["w0"], { roles: ["data"] });
  const paint = preparedCircuitPaint(index, layer);
  const paths = paint.segments
    .filter((row) => row.sourceNet === 0)
    .map((row) => row.registeredPathDelayNs)
    .sort((a, b) => a - b);
  assert.equal(paths.length, 2);
  assert(Math.abs(paths[0] - 0.8) < 1e-12);
  assert(Math.abs(paths[1] - 1) < 1e-12);
  assert.equal(paint.pips[0].registeredPathDelayNs, 1);
  assert.equal(index.maxDelays.registered, 1);
  assert.equal(layer.cones[0].registeredDelayNs, 1);
});

/** Synthetic aligned costs isolate aggregation from the source graph algorithm:
 * all three cones touch the sink, but their eligibility is deliberately distinct. */
function paintCostFixture(costs) {
  const { model, attachment, routeNets } = fixture();
  const data = prepareRenderData(model, { attachment, routeNets });
  const sinkId = data.primitives.find(
    (primitive) => primitive.type === "cells" && primitive.sourceCell === 2,
  ).id;
  for (const cone of data.cones) {
    const position = cone.primitives.indexOf(sinkId);
    assert(position >= 0);
    for (const scope of ["registered", "static"])
      cone.primitivePathDelays[scope][position] = costs[cone.role];
  }
  return createPreparedComputations(model, data);
}

test("shared geometry keeps the maximum path cost and distinguishes unknown from inapplicable", () => {
  const index = paintCostFixture({
    data: 0.4,
    enable: 0.8,
    reset: "not_applicable",
  });
  const sink = (roles) => {
    const [layer] = preparedComputationLayers(index, ["w0"], { roles });
    return preparedCircuitPaint(index, layer).cells.find(
      (row) => row.sourceCell === 2,
    );
  };
  const shared = sink(["data", "enable", "reset"]);
  for (const scope of ["registered", "static"]) {
    assert.equal(shared[`${scope}PathDelayNs`], 0.8);
    assert.equal(shared[`${scope}PathTimingUnknown`], false);
    assert.equal(shared[`${scope}PathApplicable`], true);
    const outside = sink(["reset"]);
    assert.equal(outside[`${scope}PathDelayNs`], null);
    assert.equal(outside[`${scope}PathTimingUnknown`], false);
    assert.equal(outside[`${scope}PathApplicable`], false);
  }
  const unknownIndex = paintCostFixture({
    data: 0.8,
    enable: "not_applicable",
    reset: null,
  });
  for (const [roles, expectedDelay, expectedUnknown] of [
    [["data", "enable"], 0.8, false],
    [["data", "reset"], 0.8, true],
    [["reset"], null, true],
  ]) {
    const [layer] = preparedComputationLayers(unknownIndex, ["w0"], { roles });
    const row = preparedCircuitPaint(unknownIndex, layer).cells.find(
      (item) => item.sourceCell === 2,
    );
    for (const scope of ["registered", "static"]) {
      assert.equal(row[`${scope}PathDelayNs`], expectedDelay);
      assert.equal(row[`${scope}PathTimingUnknown`], expectedUnknown);
      assert.equal(row[`${scope}PathApplicable`], true);
    }
  }
});

test("global color bounds use finite primitive path costs even when cone bounds are unknown", () => {
  const { model, attachment, routeNets } = fixture();
  const data = prepareRenderData(model, { attachment, routeNets });
  for (const cone of data.cones) {
    cone.registeredDelayNs = null;
    cone.staticDelayNs = null;
    for (const scope of ["registered", "static"])
      cone.primitivePathDelays[scope].fill("not_applicable");
  }
  data.cones[0].primitivePathDelays.registered[0] = 0.25;
  data.cones[0].primitivePathDelays.static[0] = 0.5;
  data.maxDelays = { registered: 0.25, static: 0.5 };
  const index = createPreparedComputations(model, data);
  assert.deepEqual(index.maxDelays, { registered: 0.25, static: 0.5 });
  const [filtered] = preparedComputationLayers(index, ["w0"], {
    includeUnknownTiming: false,
  });
  assert.equal(filtered.cones.length, 0);
  data.maxDelays.registered = null;
  assert.throws(
    () => createPreparedComputations(model, data),
    /global timing summary mismatch/,
  );
  data.cones[0].primitivePathDelays.registered[0] = null;
  data.cones[0].primitivePathDelays.static[0] = "not_applicable";
  data.maxDelays = { registered: null, static: null };
  assert.deepEqual(
    createPreparedComputations(model, data).maxDelays,
    data.maxDelays,
  );
});

test("pin/arc geometry and aligned arrivals retain known, unknown and outside values", () => {
  const { model, attachment, routeNets } = fixture();
  const data = prepareRenderData(model, { attachment, routeNets });
  assert.equal(data.pinGeometry.length, attachment.pins.length);
  assert.equal(data.arcGeometry.length, attachment.arcs.length);
  data.pinGeometry[0] = [null, null, null];
  data.pinGeometry[1] = [1, null, null];
  data.pinGeometry[2] = [null, -1.25, 2.5];
  data.arcGeometry[0] = [0, 1, 0, null];
  data.arcGeometry[1] = [0, 2, 1, 0];
  const arrivals = data.cones[0].pinArrivals;
  for (const scope of ["registered", "static"]) {
    arrivals[scope][0] = 0;
    arrivals[scope][1] = null;
    arrivals[scope][2] = "not_applicable";
  }
  const index = createPreparedComputations(model, data);
  assert.equal(index.pinGeometry, data.pinGeometry);
  assert.equal(index.arcGeometry, data.arcGeometry);
  assert.equal(index.cones[0].pinArrivals, arrivals);
  assert.deepEqual(index.cones[0].pinArrivals.static.slice(0, 3), [
    0,
    null,
    "not_applicable",
  ]);
});
