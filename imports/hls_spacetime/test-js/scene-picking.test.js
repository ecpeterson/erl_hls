import assert from "node:assert/strict";
import test from "node:test";
import {
  sinkPickTargets,
  projectPickTargets,
  pickCandidates,
  PICK_RADII,
} from "../web/scene-picking.js";
import {
  createCamera,
  cameraMatrices,
  projectPoint,
  projectSegment,
} from "../web/camera3d.js";

// Simple CSS-pixel projection keeps distance/depth expectations independent of
// the picking implementation. The native camera boundary is covered separately.
const project = ([x, y, depth]) => ({ x, y, depth, visible: true });
const projection = {
  project,
  projectSegment: (from, to) => [project(from), project(to)],
};
const point = (id, kind = "sink", position = [0, 0, 0.5], extra = {}) => ({
  id,
  kind,
  position,
  ...extra,
});
const span = (id, from = [0, 0, 0.2], to = [10, 0, 0.8]) => ({
  id,
  kind: "storage",
  from,
  to,
  version: id,
});
const ids = (rows) => rows.map((row) => row.target.id);
const near = (actual, expected) =>
  assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} != ${expected}`);

test("explicit picking modes never replace a sink with a nearer event or storage link", () => {
  const targets = [
    point("data/12/5", "sink", [4, 0, 0.7], {
      role: "data",
      pin: 12,
      cycle: 5,
      sinkKey: "data/12",
    }),
    point("event/1", "event", [0, 0, 0.1], { event: { id: "event/1" } }),
    span("version/1"),
  ];
  const original = structuredClone(targets);
  const hits = projectPickTargets(targets, projection);
  assert.deepEqual(
    ids(pickCandidates(hits, { x: 0, y: 0 }, { mode: "sinks" })),
    ["data/12/5"],
  );
  assert.deepEqual(
    ids(pickCandidates(hits, { x: 0, y: 0 }, { mode: "events" })),
    ["event/1"],
  );
  assert.deepEqual(
    ids(pickCandidates(hits, { x: 0, y: 0 }, { mode: "storage" })),
    ["version/1"],
  );
  assert.equal(hits[0].target, targets[0]);
  assert.equal(hits[0].target.sinkKey, "data/12");
  assert.deepEqual(targets, original);
  assert.throws(
    () => pickCandidates(hits, { x: 0, y: 0 }, { mode: "automatic" }),
    /mode/,
  );
});

test("sink endpoints have larger inclusive CSS-pixel hit targets", () => {
  assert.ok(PICK_RADII.sinks > PICK_RADII.events);
  assert.ok(PICK_RADII.sinks > PICK_RADII.storage);
  const hits = projectPickTargets(
    [
      point("sink", "sink", [14, 0, 0.5]),
      point("event", "event", [14, 0, 0.5]),
      span("storage", [14, 0, 0.2], [14, 10, 0.8]),
    ],
    projection,
  );
  assert.deepEqual(
    ids(pickCandidates(hits, { x: 0, y: 0 }, { mode: "sinks" })),
    ["sink"],
  );
  assert.equal(
    pickCandidates(hits, { x: 0, y: 0 }, { mode: "events" }).length,
    0,
  );
  assert.equal(
    pickCandidates(hits, { x: 0, y: 0 }, { mode: "storage" }).length,
    0,
  );
  assert.equal(
    pickCandidates(hits, { x: -0.001, y: 0 }, { mode: "sinks" }).length,
    0,
  );
});

test("all overlaps remain available, sorted by distance, depth and stable identity", () => {
  const targets = [
    point("farther", "sink", [2, 0, 0.01]),
    point("behind", "sink", [1, 0, 0.8]),
    point("b", "sink", [-1, 0, 0.2]),
    point("a", "sink", [0, 1, 0.2]),
  ];
  const hits = projectPickTargets(targets, projection);
  const pick = (rows) =>
    pickCandidates(rows, { x: 0, y: 0 }, { mode: "sinks" });
  assert.deepEqual(ids(pick(hits)), ["a", "b", "behind", "farther"]);
  assert.deepEqual(pick([...hits].reverse()), pick(hits));
  const many = projectPickTargets(
    Array.from({ length: 2000 }, (_, i) =>
      point(`sink/${String(i).padStart(4, "0")}`),
    ),
    projection,
  );
  assert.equal(
    pick(many).length,
    2000,
    "the caller can page every overlap without a hidden cap",
  );
  assert.deepEqual(ids(pick([...many].reverse())), ids(pick(many)));
});

test("screen-space lines preview their nearest point and interpolated depth", () => {
  const hits = projectPickTargets([span("s")], projection);
  const [candidate] = pickCandidates(
    hits,
    { x: 2.5, y: 3 },
    { mode: "storage" },
  );
  assert.deepEqual(candidate.closest, { x: 2.5, y: 0 });
  near(candidate.distancePx, 3);
  near(candidate.depth, 0.35);
  const [before] = pickCandidates(hits, { x: -2, y: 0 }, { mode: "storage" });
  assert.deepEqual(before.closest, { x: 0, y: 0 });
  near(before.depth, 0.2);
  const [after] = pickCandidates(hits, { x: 12, y: 0 }, { mode: "storage" });
  assert.deepEqual(after.closest, { x: 10, y: 0 });
  near(after.depth, 0.8);
});

test("edge-on storage picks the frontmost depth independently of native direction", () => {
  for (const [from, to] of [
    [
      [4, 5, 0.2],
      [4, 5, 0.8],
    ],
    [
      [4, 5, 0.8],
      [4, 5, 0.2],
    ],
  ]) {
    const hits = projectPickTargets([span("edge-on", from, to)], projection);
    const [candidate] = pickCandidates(
      hits,
      { x: 4, y: 6 },
      { mode: "storage" },
    );
    near(candidate.depth, 0.2);
    assert.deepEqual(candidate.closest, { x: 4, y: 5 });
    assert.equal(candidate.distancePx, 1);
  }
});

test("unlocated and clipped targets cannot acquire fabricated pick positions", () => {
  const targets = [
    point("unlocated", "sink", null),
    point("invalid", "sink", [0, NaN, 0.5]),
    point("clipped", "sink", [0, 0, 0.5]),
    span("outside"),
    { id: "missing", kind: "storage", from: null, to: [0, 0, 0] },
  ];
  const hits = projectPickTargets(targets, {
    project: () => ({ x: 0, y: 0, depth: 0, visible: false }),
    projectSegment: () => null,
  });
  assert.deepEqual(hits, []);
  assert.throws(
    () => projectPickTargets([point("", "sink")], projection),
    /identity/,
  );
  assert.throws(
    () => pickCandidates([], { x: NaN, y: 0 }, { mode: "sinks" }),
    /finite/,
  );
  assert.throws(
    () => pickCandidates([], { x: 0, y: 0 }, { mode: "sinks", radiusPx: -1 }),
    /radius/,
  );
});

test("native renderer projection keeps clipped spans and omits out-of-frustum points", () => {
  const viewport = { width: 800, height: 600 };
  const matrix = cameraMatrices(
    createCamera({ yaw: 0, pitch: 0, span: 4 }),
    viewport,
  ).matrix;
  const targets = [
    point("center", "sink", [0, 0, 0]),
    point("outside", "sink", [0, 100, 0]),
    span("crosses", [0, -100, 0], [0, 100, 0]),
  ];
  const hits = projectPickTargets(targets, {
    project: (world) => projectPoint(world, matrix, viewport),
    projectSegment: (from, to) => projectSegment(from, to, matrix, viewport),
  });
  assert.deepEqual(
    hits.map((hit) => hit.target.id),
    ["center", "crosses"],
  );
  const [sink] = pickCandidates(hits, { x: 400, y: 300 }, { mode: "sinks" });
  near(sink.distancePx, 0);
  const [storage] = pickCandidates(
    hits,
    { x: 400, y: 300 },
    { mode: "storage" },
  );
  near(storage.distancePx, 0);
  assert.ok(storage.from.visible && storage.to.visible);
});

test("different role/cycle/arrival representations remain distinct overlap candidates", () => {
  const targets = [
    point("data/4/9/known", "sink", [0, 0, 0.5], {
      sinkKey: "data/4",
      role: "data",
      pin: 4,
      cycle: 9,
      status: "known",
    }),
    point("data/4/9/unknown", "sink", [0, 0, 0.5], {
      sinkKey: "data/4",
      role: "data",
      pin: 4,
      cycle: 9,
      status: "unknown",
    }),
    point("enable/4/9", "sink", [0, 0, 0.5], {
      sinkKey: "enable/4",
      role: "enable",
      pin: 4,
      cycle: 9,
    }),
    point("data/4/10", "sink", [0, 0, 0.5], {
      sinkKey: "data/4",
      role: "data",
      pin: 4,
      cycle: 10,
    }),
  ];
  const candidates = pickCandidates(
    projectPickTargets(targets, projection),
    { x: 0, y: 0 },
    { mode: "sinks" },
  );
  assert.equal(candidates.length, 4);
  assert.equal(
    candidates.filter((row) => row.target.sinkKey === "data/4").length,
    3,
  );
  assert.ok(candidates.some((row) => row.target.status === "unknown"));
});

const root = (arrivalNs, extra = {}) => ({
  role: "data",
  pin: 4,
  status: "known",
  located: true,
  arrivalNs,
  point: { x: 10, y: 20 },
  ...extra,
});
const sinkOptions = {
  cycle: 8,
  budgetNs: 10,
  point: ({ x, y }) => ({ x: x / 10, y: y / 10 }),
  world: ({ x, y }, phase) => [x, y, phase],
  pinName: (pin) => `state_${pin}/D`,
};

test("sink targets preserve role, cycle and multiple arrival representations", () => {
  const circuit = {
    roots: [root(3), root(7), root(3, { role: "enable" }), root(14)],
  };
  const original = structuredClone(circuit);
  const targets = sinkPickTargets(circuit, sinkOptions);
  assert.equal(targets.length, 4);
  assert.equal(new Set(targets.map((target) => target.id)).size, 4);
  assert.deepEqual(
    targets.map((target) => target.sinkKey),
    ["data/4", "data/4", "enable/4", "data/4"],
  );
  assert.deepEqual(
    targets.map((target) => target.position),
    [
      [1, 2, 8.3],
      [1, 2, 8.7],
      [1, 2, 8.3],
      [1, 2, 9.4],
    ],
  );
  assert.deepEqual(targets[0], {
    kind: "sink",
    id: "sink/data/4/8/3",
    sinkKey: "data/4",
    pinName: "state_4/D",
    role: "data",
    pin: 4,
    cycle: 8,
    arrivalNs: 3,
    position: [1, 2, 8.3],
  });
  assert.notEqual(
    sinkPickTargets(circuit, { ...sinkOptions, cycle: 9 })[0].id,
    targets[0].id,
  );
  assert.deepEqual(circuit, original);
});

test("unknown, outside-scope and unlocated roots do not become sink targets", () => {
  const roots = [
    root(null, { status: "unknown" }),
    root(3, { status: "not_applicable" }),
    root(3, { located: false }),
    root(3, { point: null }),
    root(3, { point: { x: NaN, y: 20 } }),
    root(Infinity),
    root(NaN),
    root(-1),
    root(0),
  ];
  const named = [];
  const targets = sinkPickTargets(
    { roots },
    {
      ...sinkOptions,
      pinName: (pin) => {
        named.push(pin);
        return `pin/${pin}`;
      },
    },
  );
  assert.equal(targets.length, 1);
  assert.equal(targets[0].arrivalNs, 0);
  assert.deepEqual(targets[0].position, [1, 2, 8]);
  assert.deepEqual(named, [4]);
  assert.throws(
    () => sinkPickTargets({ roots: [] }, { ...sinkOptions, budgetNs: 0 }),
    RangeError,
  );
  assert.throws(
    () => sinkPickTargets({ roots: [] }, { ...sinkOptions, pinName: null }),
    TypeError,
  );
});
