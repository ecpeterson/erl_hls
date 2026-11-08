import assert from "node:assert/strict";
import test from "node:test";
import { neighborhoodScene, cutScene } from "../web/neighborhood-scene.js";

const options = {
  cycle: 12,
  point: ({ x, y }) => ({ x: x / 10, y: y / 20 }),
  world: ({ x, y }, cycle) => [x, -cycle, y],
};
const region = { minX: 0, maxX: 10, minY: 0, maxY: 20 };
const cell = (index, kind, x, y) => ({
  index,
  kind,
  cell: { id: `cell${index}`, kind: "LUT6", x, y },
});
const sink = (pin, x, y, insideRegion = true) => ({
  pin,
  name: `sink${pin}`,
  point: { x, y },
  insideRegion,
});
const fixture = () => ({
  region,
  cells: [cell(1, "family", 0, 0), cell(2, "context", 10, 20)],
  fanouts: [
    {
      pin: 1,
      name: "driver",
      point: { x: 0, y: 0 },
      sinks: [sink(2, 10, 20), sink(3, 30, 60, false)],
      familySinkPins: 1,
      totalSinkPins: 2,
    },
  ],
});

test("installed neighborhood cells and outline share one reference plane", () => {
  const result = neighborhoodScene(fixture(), options);
  assert.equal(result.segments.length, 4);
  assert.deepEqual(
    result.markers.map((m) => m.position),
    [
      [0, -12, 0],
      [1, -12, 1],
    ],
  );
  assert.notEqual(result.markers[0].color, result.markers[1].color);
  assert.ok(result.markers[0].priority > result.markers[1].priority);
  assert.deepEqual(result.segments[0].from, [0, -12, 0]);
  assert.deepEqual(result.segments[0].to, [1, -12, 0]);
  assert.equal(
    result.labels[0].text,
    "Placed neighborhood · context, not activity",
  );
  assert.equal(result.labels[0].alternatives.length, 4);
  assert.ok(result.markers.every((m) => !Object.hasOwn(m, "arrivalNs")));
});

test("context visibility does not move or erase the family focus", () => {
  const all = neighborhoodScene(fixture(), options);
  const family = neighborhoodScene(fixture(), {
    ...options,
    showContext: false,
  });
  assert.equal(family.markers.length, 1);
  assert.equal(family.markers[0].kind, "neighborhood-family");
  assert.deepEqual(family.focus, all.focus);
  assert.deepEqual(family.segments, all.segments);
});

test("selected fanout includes all located sinks outside the neighborhood", () => {
  const result = neighborhoodScene(fixture(), {
    ...options,
    driverPin: 1,
    showContext: false,
  });
  const spokes = result.segments.filter(
    (s) => s.kind === "neighborhood-fanout",
  );
  assert.equal(spokes.length, 2);
  assert.deepEqual(spokes[1].from, [0, -12, 0]);
  assert.deepEqual(spokes[1].to, [3, -12, 3]);
  assert.equal(spokes[1].insideRegion, false);
  assert.equal(spokes[1].fromPin, 1);
  assert.equal(spokes[1].toPin, 3);
  assert.ok(spokes.every((s) => s.dash > 0));
  assert.ok(result.focus.some((p) => p[0] === 3 && p[2] === 3));
  assert.ok(
    result.labels.some(
      (l) => l.text === "Fanout spokes · connectivity, not routing",
    ),
  );
});

test("unknown positions never acquire a fabricated cell, driver or spoke", () => {
  const neighborhood = fixture();
  neighborhood.cells.push(
    cell(3, "family", null, 10),
    cell(4, "context", 50, 50),
  );
  neighborhood.fanouts[0].point = null;
  neighborhood.fanouts[0].sinks.push({ pin: 4, name: "unknown", point: null });
  const result = neighborhoodScene(neighborhood, { ...options, driverPin: 1 });
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-family").length,
    1,
  );
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-context").length,
    1,
  );
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-sink").length,
    2,
  );
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-driver").length,
    0,
  );
  assert.equal(
    result.segments.filter((s) => s.kind === "neighborhood-fanout").length,
    0,
  );
  assert.match(result.labels.at(-1).text, /driver location unknown/);
});

test("coincident identities remain distinct without inventing zero-length routing", () => {
  const neighborhood = fixture();
  neighborhood.cells.push(cell(3, "context", 0, 0));
  neighborhood.fanouts[0].sinks = [
    sink(4, 0, 0),
    sink(5, 10, 20),
    sink(6, 10, 20),
  ];
  const before = structuredClone(neighborhood);
  const result = neighborhoodScene(neighborhood, { ...options, driverPin: 1 });
  assert.equal(result.markers.filter((m) => m.cellId).length, 3);
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-sink").length,
    3,
  );
  const spokes = result.segments.filter(
    (s) => s.kind === "neighborhood-fanout",
  );
  assert.equal(spokes.length, 2);
  assert.notEqual(spokes[0].toPin, spokes[1].toPin);
  assert.deepEqual(spokes[0].to, spokes[1].to);
  assert.deepEqual(neighborhood, before);
});

test("large fanout has no rendering membership cap", () => {
  const neighborhood = fixture();
  neighborhood.fanouts[0].sinks = Array.from({ length: 4097 }, (_, i) =>
    sink(i + 2, i + 1, 30, false),
  );
  neighborhood.fanouts[0].totalSinkPins = 4097;
  const result = neighborhoodScene(neighborhood, { ...options, driverPin: 1 });
  assert.equal(
    result.segments.filter((s) => s.kind === "neighborhood-fanout").length,
    4097,
  );
  assert.equal(
    result.markers.filter((m) => m.kind === "neighborhood-sink").length,
    4097,
  );
});

test("empty or missing regions stay empty, and invalid coordinate contracts reject", () => {
  assert.deepEqual(
    neighborhoodScene({ region: null, cells: [], fanouts: [] }, options),
    { segments: [], markers: [], focus: [], labels: [] },
  );
  assert.equal(
    neighborhoodScene(fixture(), { ...options, driverPin: 999 }).markers.length,
    2,
  );
  assert.throws(
    () => neighborhoodScene(fixture(), { ...options, cycle: NaN }),
    TypeError,
  );
  assert.throws(
    () => neighborhoodScene(fixture(), { ...options, showContext: "false" }),
    TypeError,
  );
  assert.throws(
    () => neighborhoodScene(fixture(), { ...options, point: null }),
    TypeError,
  );
  assert.throws(
    () =>
      neighborhoodScene(
        { ...fixture(), region: { ...region, maxX: -1 } },
        options,
      ),
    RangeError,
  );
});

const cutOptions = { ...options, budgetNs: 10 };
const crossing = (fromPin, arrival, requiresRegister = true) => ({
  fromPin,
  point: { x: 10, y: 20 },
  originalArrivalNs: arrival,
  requiresRegister,
});

test("proposed cuts mark original arrivals, not invented stage boundaries", () => {
  const cut = {
    status: "known",
    stage1DelayNs: 99,
    stage2DelayNs: 100,
    crossings: [crossing(8, 3), crossing(9, 11)],
  };
  const result = cutScene(cut, { ...cutOptions, selectedPin: 9 });
  assert.deepEqual(result.segments, []);
  assert.deepEqual(
    result.markers.map((m) => m.position),
    [
      [1, -12.3, 1],
      [1, -13.1, 1],
    ],
  );
  assert.equal(result.markers[1].pin, 9);
  assert.ok(result.markers[1].size > result.markers[0].size);
  assert.ok(result.markers[1].priority > result.markers[0].priority);
  assert.equal(result.labels.length, 1);
  assert.equal(
    result.labels[0].text,
    "Proposed boundary · original arrival positions",
  );
  assert.deepEqual(result.labels[0].position, result.markers[1].position);
  assert.deepEqual(
    result.focus,
    result.markers.map((m) => m.position),
  );
});

test("constant crossings are distinct subdued connections, not requested flip-flops", () => {
  const cut = {
    status: "known",
    crossings: [crossing(8, 0), crossing(9, 0, false)],
  };
  const before = structuredClone(cut);
  const result = cutScene(cut, { ...cutOptions, selectedPin: 9 });
  assert.equal(result.markers.length, 2);
  assert.equal(result.markers[0].kind, "candidate-cut-signal");
  assert.equal(result.markers[1].kind, "candidate-cut-constant");
  assert.equal(result.markers[1].requiresRegister, false);
  assert.notEqual(result.markers[0].color, result.markers[1].color);
  assert.ok(result.markers[1].size > result.markers[0].size);
  assert.deepEqual(cut, before);
});

test("unknown cut evidence never creates a proposed position", () => {
  for (const status of ["unknown", "not_applicable"])
    assert.deepEqual(
      cutScene({ status, crossings: [crossing(8, 3)] }, cutOptions),
      { segments: [], markers: [], focus: [], labels: [] },
    );
  const cut = {
    status: "known",
    crossings: [
      { ...crossing(8, 3), point: null },
      crossing(9, null),
      crossing(10, "not_applicable"),
    ],
  };
  assert.deepEqual(cutScene(cut, cutOptions), {
    segments: [],
    markers: [],
    focus: [],
    labels: [],
  });
  assert.throws(
    () => cutScene(cut, { ...cutOptions, budgetNs: 0 }),
    RangeError,
  );
});

test("proposed boundary keeps every crossing without per-bit labels", () => {
  const cut = {
    status: "known",
    crossings: Array.from({ length: 4097 }, (_, i) => crossing(i, 3)),
  };
  const result = cutScene(cut, cutOptions);
  assert.equal(result.markers.length, 4097);
  assert.equal(result.focus.length, 4097);
  assert.equal(result.labels.length, 1);
  assert.equal(result.segments.length, 0);
});
