import test from "node:test";
import assert from "node:assert/strict";
import { arrivalCircuit } from "../web/arrival-circuits.js";

/** Two net arcs around a same-tile logic arc; the net's two chords share delay
 * by display length, while the logic arc has nonzero vertical propagation. */
function fixture() {
  const cone = {
    id: "sink/data",
    role: "data",
    pinIndices: [0, 1, 2, 3],
    arcIndices: [0, 1, 2],
    rootPins: [3],
    pinArrivals: { registered: [0, 2, 5, 6], static: [0, 2, 5, 6] },
    pathDelays: { registered: [6, 6, 6], static: [6, 6, 6] },
  };
  const segment = (x0, x1) => ({
    type: "segments",
    from: { x: x0, y: 0 },
    to: { x: x1, y: 0 },
    kind: "node",
  });
  const index = {
    pinGeometry: [
      [0, 0, 0],
      [1, 10, 0],
      [1, 10, 0],
      [2, 20, 0],
    ],
    arcGeometry: [
      [0, 1, 0, 2],
      [1, 2, 1, 3],
      [2, 3, 0, 1],
    ],
    primitives: [segment(0, 5), segment(5, 10), segment(10, 20)],
    routes: [
      { arc: 0, primitives: [0, 1], disposition: "resolved" },
      { arc: 2, primitives: [2], disposition: "resolved" },
    ],
    cones: [cone],
    writes: new Map([["write", { cones: [0] }]]),
    model: { events: new Map([["write", { access: { resource: "word" } }]]) },
  };
  const layer = { cones: [cone], operations: [{ event: "write" }] };
  return { index, layer };
}
const approx = (a, b) => assert(Math.abs(a - b) < 1e-12, `${a} != ${b}`);

test("propagation interpolates local delay along chords and keeps logic delay vertical", () => {
  const { index, layer } = fixture(),
    original = structuredClone(index);
  const result = arrivalCircuit(index, layer);
  assert.equal(result.summary.arcs, 3);
  assert.equal(result.summary.knownArcs, 3);
  assert.equal(result.summary.propagationSegments, 4);
  assert.equal(result.summary.readinessSegments, 0);
  const first = result.segments.filter((row) => row.arcIds.includes(0));
  assert.deepEqual(
    first.map((row) => [row.from.arrivalNs, row.to.arrivalNs]),
    [
      [0, 1],
      [1, 2],
    ],
  );
  const logic = result.segments.find((row) => row.arcIds.includes(1));
  assert.deepEqual(logic.from, { x: 10, y: 0, arrivalNs: 2 });
  assert.deepEqual(logic.to, { x: 10, y: 0, arrivalNs: 5 });
  assert.equal(logic.localDelayNs, 3);
  assert.equal(logic.pathDelayNs, 6);
  assert.equal(logic.computationKey, "word");
  assert.equal(result.roots[0].pin, 3);
  assert.equal(result.roots[0].arrivalNs, 6);
  assert.equal(result.roots[0].pathDelayNs, 6);
  assert.deepEqual(result.roots[0].destinationResources, ["word"]);
  assert.equal(result.details[1].kind, "logic");
  assert.equal(result.details[1].delayNs, 3);
  assert.equal(result.details[1].arrivalViaNs, 5);
  assert.equal(result.marks.find((row) => row.pin === 2).pathDelayNs, 6);
  assert.equal(arrivalCircuit(index, layer), result);
  assert.deepEqual(index, original);
});

test("reconvergence exposes readiness separately instead of charging it to propagation", () => {
  const { index, layer } = fixture(),
    cone = layer.cones[0];
  index.pinGeometry.push([3, -5, 0], [1, 10, 0]);
  index.arcGeometry.push([4, 5, 0, 5], [5, 2, 1, 3]);
  index.primitives.push({
    type: "segments",
    from: { x: -5, y: 0 },
    to: { x: 10, y: 0 },
    kind: "node",
  });
  index.routes.push({ arc: 3, primitives: [3], disposition: "resolved" });
  cone.pinIndices.push(4, 5);
  cone.arcIndices.push(3, 4);
  for (const scope of ["registered", "static"]) {
    cone.pinArrivals[scope] = [0, 2, 8, 9, 0, 5];
    cone.pathDelays[scope] = [6, 6, 9, 9, 9];
  }
  const result = arrivalCircuit(index, layer),
    ready = result.segments.filter((row) => row.kind === "readiness");
  assert.equal(ready.length, 1);
  assert.deepEqual([ready[0].from.arrivalNs, ready[0].to.arrivalNs], [5, 8]);
  assert.equal(ready[0].interpolation, "latest_input_readiness_not_storage");
  const propagation = result.segments.find(
    (row) => row.kind === "propagation" && row.arcIds.includes(1),
  );
  assert.equal(propagation.localDelayNs, 3);
  approx(propagation.to.arrivalNs - propagation.from.arrivalNs, 3);
  assert.equal(result.details.find((row) => row.arc === 1).arrivalToNs, 8);
  assert(
    result.segments.some(
      (row) =>
        row.kind === "propagation" &&
        row.from.arrivalNs === 5 &&
        row.to.arrivalNs === 8,
    ),
  );
});

test("identical timing geometry unions contributors but differing arrival times remain distinct", () => {
  const { index, layer } = fixture(),
    other = structuredClone(layer.cones[0]);
  other.id = "other/data";
  other.pathDelays = { registered: [7, 7, 7], static: [7, 7, 7] };
  index.cones.push(other);
  index.writes.set("other", { cones: [1] });
  index.model.events.set("other", { access: { resource: "other" } });
  layer.cones.push(other);
  layer.operations.push({ event: "other" });
  const shared = arrivalCircuit(index, layer);
  assert.equal(shared.segments.length, 4);
  assert.equal(shared.summary.mergedSegments, 4);
  assert(
    shared.segments.every(
      (row) =>
        row.computationShared &&
        row.computationKey === null &&
        row.pathDelayNs === 7,
    ),
  );
  assert.equal(shared.details.length, 3);
  const first = arrivalCircuit(index, {
    cones: [index.cones[0]],
    operations: [{ event: "write" }],
  });
  assert(first.segments.every((row) => row.computationKey === "word"));
  const shifted = fixture(),
    late = structuredClone(shifted.layer.cones[0]);
  late.id = "later/data";
  for (const scope of ["registered", "static"])
    late.pinArrivals[scope] = late.pinArrivals[scope].map((value) => value + 1);
  shifted.index.cones.push(late);
  shifted.index.writes.set("other", { cones: [1] });
  shifted.index.model.events.set("other", { access: { resource: "other" } });
  shifted.layer.cones.push(late);
  shifted.layer.operations.push({ event: "other" });
  const separated = arrivalCircuit(shifted.index, shifted.layer);
  assert.equal(separated.segments.length, 8);
  assert.equal(separated.summary.mergedSegments, 0);
});

test("unknown arrival, outside scope and missing coordinates stay explicit", () => {
  const unknown = fixture();
  unknown.index.arcGeometry[1][3] = null;
  unknown.layer.cones[0].pinArrivals.registered = [0, 2, null, null];
  unknown.layer.cones[0].pathDelays.registered = [null, null, null];
  const result = arrivalCircuit(unknown.index, unknown.layer);
  assert.equal(result.summary.unknownArcs, 2);
  assert(
    result.segments
      .filter((row) => row.kind === "unknown")
      .every((row) => row.from.arrivalNs === null && row.to.arrivalNs === null),
  );
  assert.equal(result.details[1].arrivalFromNs, 2);
  assert.equal(result.details[1].arrivalViaNs, null);
  assert.equal(result.roots[0].status, "unknown");
  const outside = fixture();
  outside.layer.cones[0].pinArrivals.registered.fill("not_applicable");
  outside.layer.cones[0].pathDelays.registered.fill("not_applicable");
  const excluded = arrivalCircuit(outside.index, outside.layer);
  assert.equal(excluded.segments.length, 0);
  assert.equal(excluded.summary.outsideArcs, 3);
  assert(excluded.marks.every((row) => row.status === "not_applicable"));
  const missing = fixture();
  missing.index.pinGeometry[3] = [null, null, null];
  missing.index.routes[1].primitives = [];
  const absent = arrivalCircuit(missing.index, missing.layer);
  assert.equal(absent.summary.unlocatedArcs, 1);
  assert.equal(absent.summary.geometryUnavailableArcs, 1);
  assert.equal(absent.roots[0].point, null);
  assert.equal(absent.roots[0].located, false);
});

test("unresolved visibility never invents a route and zero-XY nets retain positive delay", () => {
  const unresolved = fixture();
  unresolved.index.primitives[2].kind = "unresolved";
  const shown = arrivalCircuit(unresolved.index, unresolved.layer),
    hidden = arrivalCircuit(unresolved.index, unresolved.layer, {
      includeUnresolved: false,
    });
  assert(
    shown.segments.some(
      (row) =>
        row.status === "unresolved_geometry" && row.from.arrivalNs === null,
    ),
  );
  assert.equal(hidden.summary.filteredSegments, 1);
  assert.equal(hidden.summary.geometryUnavailableArcs, 1);
  assert(!hidden.segments.some((row) => row.status === "unresolved_geometry"));
  const zero = fixture();
  for (const primitive of zero.index.primitives.slice(0, 2)) {
    primitive.from = { x: 0, y: 0 };
    primitive.to = { x: 0, y: 0 };
  }
  zero.index.pinGeometry[1] = [1, 0, 0];
  zero.index.pinGeometry[2] = [1, 0, 0];
  const vertical = arrivalCircuit(zero.index, zero.layer).segments.filter(
    (row) => row.arcIds.includes(0),
  );
  assert.equal(vertical.length, 2);
  assert(
    vertical.every(
      (row) =>
        row.from.x === row.to.x &&
        row.from.y === row.to.y &&
        row.to.arrivalNs > row.from.arrivalNs,
    ),
  );
  approx(
    vertical.reduce(
      (sum, row) => sum + row.to.arrivalNs - row.from.arrivalNs,
      0,
    ),
    2,
  );
});

test("hiding unresolved chords preserves arrival coordinates on visible branches", () => {
  for (const zeroLength of [false, true]) {
    const { index, layer } = fixture();
    const chord = (from, to, kind) => ({
      type: "segments",
      from: { x: zeroLength ? 0 : from, y: 0 },
      to: { x: zeroLength ? 0 : to, y: 0 },
      kind,
    });
    index.primitives = [
      chord(0, 2, "node"),
      chord(2, 8, "unresolved"),
      chord(8, 10, "node"),
    ];
    index.routes[0].primitives = [0, 1, 2];
    index.routes[1].primitives = [];
    if (zeroLength) {
      index.pinGeometry[1] = [1, 0, 0];
      index.pinGeometry[2] = [1, 0, 0];
    }
    const shown = arrivalCircuit(index, layer);
    const hidden = arrivalCircuit(index, layer, { includeUnresolved: false });
    const visible = (result) =>
      result.segments.filter(
        (row) => row.arcIds.includes(0) && row.geometryKind !== "unresolved",
      );
    assert.deepEqual(visible(hidden), visible(shown));
    assert.equal(hidden.summary.filteredSegments, 1);
    const spans = visible(hidden);
    approx(spans[0].to.arrivalNs, zeroLength ? 2 / 3 : 0.4);
    approx(spans[1].from.arrivalNs, zeroLength ? 4 / 3 : 1.6);
    approx(spans[1].to.arrivalNs, 2);
  }
});

test("incomplete routes retain pin and arc timing without invented intermediate arrivals", () => {
  for (const reason of ["discontinuous", "partial", "gap", "endpoint"]) {
    const { index, layer } = fixture();
    if (reason === "discontinuous") index.primitives[1].from.x = 7;
    if (reason === "partial") index.routes[0].disposition = "partial";
    if (reason === "gap") index.routes[0].gapCounts = { pip_location: 1 };
    if (reason === "endpoint") index.primitives[0].from.x = 1;
    const result = arrivalCircuit(index, layer);
    const spans = result.segments.filter((row) => row.arcIds.includes(0));
    assert.equal(spans.length, 2);
    assert(spans.every((row) => row.status === "incomplete_geometry"));
    assert(
      spans.every(
        (row) => row.from.arrivalNs === null && row.to.arrivalNs === null,
      ),
    );
    assert.equal(result.summary.geometryIncompleteArcs, 1);
    assert.equal(result.details[0].arrivalFromNs, 0);
    assert.equal(result.details[0].arrivalViaNs, 2);
    assert.equal(result.details[0].arrivalToNs, 2);
    assert.equal(result.marks.find((row) => row.pin === 1).arrivalNs, 2);
  }
  const complete = fixture();
  // Native exports always disclose unknown intra-site metal shape. Known tile
  // endpoints still permit the explicitly schematic chord interpolation.
  complete.index.routes[0].gapCounts = { intrasite: 2 };
  const retained = arrivalCircuit(complete.index, complete.layer);
  assert.equal(retained.summary.geometryIncompleteArcs, 0);
  assert(retained.segments.every((row) => row.kind === "propagation"));
});

test("missing write associations stay unowned and inconsistent timing rejects", () => {
  const { index, layer } = fixture();
  const result = arrivalCircuit(index, { cones: layer.cones });
  assert(
    result.segments.every(
      (row) => row.computationKey === null && row.computationUnknown,
    ),
  );
  assert(result.roots.every((row) => row.destinationResources.length === 0));
  assert.throws(
    () => arrivalCircuit(index, layer, { scope: "made-up" }),
    /scope/,
  );
  const bad = fixture();
  bad.layer.cones[0].pinArrivals.registered[1] = 1;
  assert.throws(
    () => arrivalCircuit(bad.index, bad.layer),
    /precedes propagation/,
  );
});
