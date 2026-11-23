import test from "node:test";
import assert from "node:assert/strict";
import { overlayDisplay } from "../web/overlay-display.js";
const storage = (lo, hi, color = "#abc") => ({
  kind: "storage",
  from: [1, 2, lo],
  to: [1, 2, hi],
  color,
  radius: 0.002,
});
test("coincident storage columns become disjoint intervals while evidence stays separate", () => {
  const evidence = [{ version: "a" }, { version: "b" }];
  const scene = {
    markers: [],
    segments: [storage(0, 3), storage(1, 4)],
    storage: evidence,
  };
  const original = structuredClone(scene);
  const result = overlayDisplay(scene);
  assert.deepEqual(
    result.segments.map((s) => [s.from[2], s.to[2], s.contributors]),
    [
      [0, 1, 1],
      [1, 3, 2],
      [3, 4, 1],
    ],
  );
  assert.equal(result.storage, evidence);
  assert.deepEqual(scene, original);
});
test("coincident conflicting categories are neutral but selected thick storage stays visible", () => {
  const result = overlayDisplay({
    markers: [],
    segments: [storage(0, 2, "#f00"), storage(0, 2, "#00f")],
  });
  assert.equal(result.segments.length, 1);
  assert.equal(result.segments[0].color, "#c3cdd4");
  const selected = { ...storage(0, 2, "#fff"), radius: 0.004 };
  assert.equal(
    overlayDisplay({ markers: [], segments: [storage(0, 2), selected] })
      .segments[0].color,
    "#fff",
  );
});
test("direction survives splitting and marker priority resolves overlay duplication", () => {
  const route = { kind: "node", from: [0, 0, 0], to: [1, 1, 0], color: "#abc" };
  const result = overlayDisplay({
    segments: [{ ...storage(3, 0, "#f00"), colorEnd: "#00f" }, route],
    markers: [
      { position: [1, 2, 3], size: 0.01, color: "#f00" },
      { position: [1, 2, 3], size: 0.01, color: "#00f" },
      { position: [1, 2, 3], size: 0.02, color: "#fff", priority: 3 },
    ],
  });
  assert.deepEqual(result.segments[0].from, route.from);
  assert.deepEqual(result.segments[0].to, route.to);
  assert.equal(result.segments[1].color, "#00f");
  assert.equal(result.segments[1].colorEnd, "#f00");
  assert.equal(result.markers.length, 1);
  assert.equal(result.markers[0].color, "#fff");
});

test("repeated dependency overlays draw once and opposite gradients stay neutral", () => {
  const a = {
    kind: "dependency",
    from: [0, 0, 0],
    to: [1, 1, 0],
    color: "#f00",
    colorEnd: "#00f",
    dash: 0.02,
  };
  const b = { ...a, from: a.to, to: a.from };
  const same = overlayDisplay({ markers: [], segments: [a, { ...a }] });
  assert.equal(same.segments.length, 1);
  assert.equal(same.segments[0].contributors, 2);
  assert.equal(same.segments[0].color, "#f00");
  const opposed = overlayDisplay({ markers: [], segments: [a, b] });
  assert.equal(opposed.segments.length, 1);
  assert.equal(opposed.segments[0].color, "#c3cdd4");
  assert.equal(opposed.segments[0].colorEnd, "#c3cdd4");
});

// Every source order must produce the same surface and display evidence.
function orders(rows) {
  if (rows.length < 2) return [rows];
  return rows.flatMap((row, i) =>
    orders(rows.filter((_, j) => j !== i)).map((tail) => [row, ...tail]),
  );
}
const pin = (kind, color, extra = {}) => ({
  position: [1, 2, 3],
  size: 0.004,
  kind,
  color,
  ...extra,
});
const timedPin = (color, extra = {}) =>
  pin("arrival-pin", color, {
    overlayRole: "timing",
    timingUnknown: false,
    ...extra,
  });

test("timing color survives neutral readiness and access markers in every source order", () => {
  const rows = [
    timedPin("#4c87a2"),
    pin("arrival-capture-boundary", "#7e8b91", {
      overlayRole: "annotation",
      size: 0.005,
    }),
    pin("access", "#627780", { priority: 1 }),
  ];
  const expected = overlayDisplay({ markers: rows, segments: [] });
  for (const markers of orders(rows))
    assert.deepEqual(overlayDisplay({ markers, segments: [] }), expected);
  const [marker] = expected.markers;
  assert.equal(marker.color, "#4c87a2");
  assert.equal(
    marker.size,
    0.004,
    "a neutral annotation cannot cover the timing glyph",
  );
  assert.equal(marker.contributors, 3);
  assert.equal(marker.colorConflict, false);
  assert.deepEqual(marker.overlayKinds, [
    "access",
    "arrival-capture-boundary",
    "arrival-pin",
  ]);
  assert.deepEqual(marker.overlayEvidence, {
    known: 1,
    unknown: 0,
    annotations: 2,
  });
});

test("unknown timing is not replaced by a known collision, while explicit focus remains visible", () => {
  const known = timedPin("#86bdc4"),
    unknown = timedPin("#81738f", {
      kind: "arrival-unknown-pin",
      timingUnknown: true,
    }),
    annotation = pin("arrival-capture-boundary", "#7e8b91", {
      overlayRole: "annotation",
    });
  for (const markers of orders([known, unknown, annotation])) {
    const [marker] = overlayDisplay({ markers, segments: [] }).markers;
    assert.equal(marker.color, "#81738f");
    assert.equal(marker.timingUnknown, true);
    assert.equal(marker.colorConflict, false);
    assert.deepEqual(marker.overlayEvidence, {
      known: 1,
      unknown: 1,
      annotations: 1,
    });
  }
  const selected = { ...known, color: "#fff2bc", size: 0.006, priority: 3 };
  for (const markers of orders([selected, unknown, annotation])) {
    const [marker] = overlayDisplay({ markers, segments: [] }).markers;
    assert.equal(marker.color, "#fff2bc");
    assert.equal(marker.size, 0.006);
    assert.equal(marker.overlayEvidence.unknown, 1);
  }
});

test("genuine peer color conflicts stay distinct from unknown timing and annotations", () => {
  const rows = [
    timedPin("#4c87a2"),
    timedPin("#c7a845"),
    pin("arrival-capture-boundary", "#7e8b91", {
      overlayRole: "annotation",
    }),
  ];
  const expected = overlayDisplay({ markers: rows, segments: [] });
  for (const markers of orders(rows))
    assert.deepEqual(overlayDisplay({ markers, segments: [] }), expected);
  assert.equal(expected.markers[0].color, "#c3cdd4");
  assert.equal(expected.markers[0].colorConflict, true);
  assert.equal(expected.markers[0].timingUnknown, false);
  assert.equal(expected.markers[0].overlayEvidence.unknown, 0);
});

test("exact surfaces merge across annotation kinds without losing directed timing color", () => {
  const timing = {
    from: [0, 0, 0],
    to: [1, 1, 1],
    kind: "arrival-propagation",
    radius: 0.002,
    dash: 0,
    color: "#4c87a2",
    colorEnd: "#c7a845",
    overlayRole: "timing",
    timingUnknown: false,
  };
  const readiness = {
    ...timing,
    from: timing.to,
    to: timing.from,
    color: "#7e8b91",
    colorEnd: "#7e8b91",
    kind: "arrival-readiness",
    overlayRole: "annotation",
  };
  const expected = overlayDisplay({
    markers: [],
    segments: [timing, readiness],
  });
  assert.deepEqual(
    overlayDisplay({ markers: [], segments: [readiness, timing] }),
    expected,
  );
  assert.equal(expected.segments.length, 1);
  assert.equal(expected.segments[0].color, timing.color);
  assert.equal(expected.segments[0].colorEnd, timing.colorEnd);
  assert.equal(expected.segments[0].contributors, 2);
  assert.deepEqual(expected.segments[0].overlayKinds, [
    "arrival-propagation",
    "arrival-readiness",
  ]);
  const selected = {
    ...timing,
    color: "#fff2bc",
    colorEnd: "#fff2bc",
    priority: 3,
  };
  assert.equal(
    overlayDisplay({ markers: [], segments: [timing, readiness, selected] })
      .segments[0].color,
    "#fff2bc",
  );
});

test("unequal radii and dash patterns retain intentional core and sleeve geometry", () => {
  const core = {
    from: [0, 0, 0],
    to: [1, 1, 1],
    kind: "arrival-schematic-core",
    color: "#4c87a2",
    radius: 0.0007,
    dash: 0,
  };
  const sleeve = {
    ...core,
    kind: "arrival-schematic",
    radius: 0.0017,
    dash: 0.018,
  };
  const solid = { ...sleeve, kind: "arrival-propagation", dash: 0 };
  const result = overlayDisplay({
    markers: [],
    segments: [core, sleeve, solid],
  });
  assert.equal(result.segments.length, 3);
  assert.deepEqual(
    result.segments.map((s) => [s.radius, s.dash]),
    [
      [0.0007, 0],
      [0.0017, 0],
      [0.0017, 0.018],
    ],
  );
});

test("a storage union shares an exact timing surface without erasing its evidence", () => {
  const residence = storage(0, 2, "#526471"),
    timing = {
      ...residence,
      kind: "arrival-propagation",
      color: "#4c87a2",
      overlayRole: "timing",
      timingUnknown: false,
    };
  const evidence = [{ version: "a" }];
  const scene = {
    markers: [],
    segments: [residence, timing],
    storage: evidence,
  };
  const original = structuredClone(scene);
  const result = overlayDisplay(scene);
  assert.equal(result.segments.length, 1);
  assert.equal(result.segments[0].color, timing.color);
  assert.equal(result.segments[0].contributors, 2);
  assert.deepEqual(result.segments[0].overlayKinds, [
    "arrival-propagation",
    "storage",
  ]);
  assert.equal(result.storage, evidence);
  assert.deepEqual(scene, original);
});
