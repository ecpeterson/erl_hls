import assert from "node:assert/strict";
import test from "node:test";
import { arrivalScene } from "../web/arrival-scene.js";
import { overlayDisplay } from "../web/overlay-display.js";
import {
  DIRECTION_SOURCE_COLOR,
  DIRECTION_SINK_COLOR,
  UNKNOWN_COLOR,
} from "../web/perceptual-color.js";
const p = (x, y, arrivalNs) => ({ x, y, arrivalNs });
const options = {
  cycle: 4,
  budgetNs: 10,
  captureAvailable: true,
  point: ({ x, y }) => ({ x: x / 10, y: y / 10 }),
  world: ({ x, y }, clock) => [x, y, clock],
  shade: () => "#123456",
};
const mark = (arrivalNs, pin = 1) => ({
  pin,
  point: p(10, 20, arrivalNs),
  arrivalNs,
  status: arrivalNs === null ? "unknown" : "known",
});
const root = (arrivalNs) => ({ ...mark(arrivalNs), located: true });

test("propagation rises by arrival while readiness stays a separate neutral link", () => {
  const result = arrivalScene(
    {
      segments: [
        { from: p(0, 0, 1), to: p(10, 20, 3), kind: "propagation" },
        { from: p(10, 20, 3), to: p(10, 20, 6), kind: "readiness" },
      ],
      marks: [mark(6)],
      roots: [root(6)],
    },
    options,
  );
  assert.deepEqual(result.segments[0].from, [0, 0, 4.1]);
  assert.deepEqual(result.segments[0].to, [1, 2, 4.3]);
  assert.equal(result.segments[0].dash, 0);
  assert.equal(result.segments[0].color, "#123456");
  assert.equal(result.segments[1].kind, "arrival-readiness");
  assert.notEqual(result.segments[1].color, "#123456");
  assert.ok(result.segments[1].radius < result.segments[0].radius);
  assert.deepEqual(result.segments[2].from, [1, 2, 4.6]);
  assert.deepEqual(result.segments[2].to, [1, 2, 5]);
});

test("late roots extend beyond the boundary with an overrun annotation", () => {
  const result = arrivalScene(
    { marks: [mark(12)], roots: [root(12)] },
    options,
  );
  assert.equal(result.summary.lateRoots, 1);
  assert.deepEqual(result.segments[0].from, [1, 2, 5]);
  assert.deepEqual(result.segments[0].to, [1, 2, 5.2]);
  assert.equal(result.segments[0].kind, "arrival-overrun");
  assert.equal(result.segments[0].color, result.segments[0].colorEnd);
});

test("a final or reset-retired write gains no following capture geometry", () => {
  const result = arrivalScene(
    { marks: [mark(12)], roots: [root(12), root(null)] },
    { ...options, captureAvailable: false },
  );
  assert.equal(result.summary.uncapturedRoots, 2);
  assert.equal(result.summary.unknownRoots, 1);
  assert.equal(result.segments.length, 0);
  assert.equal(result.markers.length, 1);
  assert.equal(result.markers[0].kind, "arrival-pin");
});

test("unknown mapped timing uses an explicit shelf, not arrival zero", () => {
  const result = arrivalScene(
    {
      segments: [{ from: p(0, 0, null), to: p(10, 20, null), kind: "unknown" }],
      marks: [mark(null)],
      roots: [root(null)],
    },
    options,
  );
  assert.equal(result.summary.unknownSegments, 1);
  assert.equal(result.summary.unknownMarks, 1);
  assert.equal(result.summary.unknownRoots, 1);
  assert.equal(result.segments[0].from[2], 3.82);
  assert.equal(result.markers[0].position[2], 3.82);
  assert.equal(result.markers[0].color, UNKNOWN_COLOR);
  assert.equal(result.markers.length, 1);
});

test("outside scope and missing XY never invent timed physical positions", () => {
  const result = arrivalScene(
    {
      marks: [
        { ...mark(null), status: "not_applicable" },
        { ...mark(null), point: null },
      ],
      roots: [
        { ...root(null), status: "not_applicable" },
        { ...root(2), point: null },
      ],
    },
    options,
  );
  assert.equal(result.markers.length, 0);
  assert.equal(result.segments.length, 0);
  assert.equal(result.summary.unknownMarks, 1);
  assert.equal(result.summary.unknownRoots, 0);
});

test("direction gradients belong only to qualified directed propagation", () => {
  const segments = [
    { from: p(0, 0, 0), to: p(10, 20, 3), kind: "propagation" },
    { from: p(10, 20, 3), to: p(10, 20, 5), kind: "readiness" },
    {
      from: p(0, 0, 0),
      to: p(10, 20, 3),
      kind: "propagation",
      directionUnknown: true,
    },
  ];
  const result = arrivalScene({ segments }, { ...options, mode: "direction" });
  assert.equal(result.segments[0].color, DIRECTION_SOURCE_COLOR);
  assert.equal(result.segments[0].colorEnd, DIRECTION_SINK_COLOR);
  assert.equal(result.segments[1].color, result.segments[1].colorEnd);
  assert.equal(result.segments[2].color, result.segments[2].colorEnd);
});

test("pin-only detail preserves different arrival times at equal XY", () => {
  const result = arrivalScene(
    {
      segments: [{ from: p(0, 0, 0), to: p(10, 20, 3), kind: "propagation" }],
      marks: [mark(3), mark(6, 2)],
      roots: [root(6)],
    },
    { ...options, detail: "overview" },
  );
  assert.equal(result.segments.length, 0);
  assert.deepEqual(
    result.markers.map((m) => m.position),
    [
      [1, 2, 4.3],
      [1, 2, 4.6],
    ],
  );
});

test("empty circuits still validate budget and exact capture equality creates no gap", () => {
  assert.throws(
    () => arrivalScene({}, { ...options, budgetNs: 0 }),
    RangeError,
  );
  const result = arrivalScene({ roots: [root(10)] }, options);
  assert.equal(result.summary.lateRoots, 0);
  assert.equal(result.segments.length, 0);
  assert.equal(result.markers[0].position[2], 5);
});

test("arc focus overrides direction shading but never turns readiness into delay", () => {
  const circuit = {
    segments: [
      { from: p(0, 0, 0), to: p(10, 20, 3), kind: "propagation", arcIds: [4] },
      { from: p(10, 20, 3), to: p(10, 20, 5), kind: "readiness", arcIds: [4] },
    ],
    marks: [
      { ...mark(3), arcIds: [4] },
      { ...mark(0), arcIds: [5] },
    ],
  };
  const result = arrivalScene(circuit, {
    ...options,
    mode: "direction",
    activeArc: 4,
  });
  assert.equal(result.segments[0].color, "#fff2bc");
  assert.equal(result.segments[0].colorEnd, "#fff2bc");
  assert.notEqual(result.segments[1].color, "#fff2bc");
  assert.equal(result.markers[0].color, "#fff2bc");
  assert.ok(result.markers[0].size > result.markers[1].size);
});

test("schematic propagation has a continuous core and distinct dashed sleeve", () => {
  const row = {
    from: p(0, 0, 1),
    to: p(10, 20, 3),
    kind: "propagation",
    schematic: true,
    arcIds: [4],
  };
  const result = arrivalScene(
    { segments: [row] },
    { ...options, mode: "direction" },
  );
  const [core, sleeve] = result.segments;
  assert.equal(core.kind, "arrival-schematic-core");
  assert.equal(core.dash, 0);
  assert.equal(sleeve.kind, "arrival-schematic");
  assert.equal(sleeve.dash, 0.018);
  assert.ok(core.radius < sleeve.radius);
  assert.deepEqual(core.from, [0, 0, 4.1]);
  assert.deepEqual(core.to, [1, 2, 4.3]);
  assert.deepEqual(sleeve.from, core.from);
  assert.deepEqual(sleeve.to, core.to);
  assert.equal(core.color, DIRECTION_SOURCE_COLOR);
  assert.equal(core.colorEnd, DIRECTION_SINK_COLOR);
  assert.equal(sleeve.color, core.color);
  assert.equal(sleeve.colorEnd, core.colorEnd);
  assert.equal(result.summary.unknownSegments, 0);
  const focused = arrivalScene(
    { segments: [row] },
    { ...options, activeArc: 4 },
  );
  assert.ok(
    focused.segments.every(
      (s) => s.color === "#fff2bc" && s.colorEnd === "#fff2bc",
    ),
  );
  assert.ok(focused.segments[0].radius < focused.segments[1].radius);
  assert.equal(
    arrivalScene({ segments: [row] }, { ...options, detail: "overview" })
      .segments.length,
    0,
  );
});

test("schematic metadata never turns unknown or readiness spans into propagation", () => {
  const result = arrivalScene(
    {
      segments: [
        {
          from: p(0, 0, null),
          to: p(10, 20, null),
          kind: "unknown",
          schematic: true,
        },
        {
          from: p(10, 20, 3),
          to: p(10, 20, 5),
          kind: "readiness",
          schematic: true,
        },
      ],
    },
    options,
  );
  assert.equal(result.segments.length, 2);
  assert.equal(result.segments[0].kind, "arrival-unknown");
  assert.equal(result.segments[0].from[2], 3.82);
  assert.equal(result.segments[1].kind, "arrival-readiness");
  assert.ok(result.segments.every((s) => s.dash === 0.018));
});

test("arrival overlay metadata preserves timing at a coincident capture boundary", () => {
  const scene = arrivalScene({ marks: [mark(10)], roots: [root(10)] }, options);
  assert.equal(scene.markers[0].overlayRole, "timing");
  assert.equal(scene.markers[0].timingUnknown, false);
  assert.equal(scene.markers[1].overlayRole, "annotation");
  const [merged] = overlayDisplay(scene).markers;
  assert.equal(merged.color, "#123456");
  assert.equal(merged.contributors, 2);
  assert.deepEqual(merged.overlayEvidence, {
    known: 1,
    unknown: 0,
    annotations: 1,
  });
  const focused = arrivalScene(
    { marks: [{ ...mark(10), arcIds: [4] }], roots: [root(10)] },
    { ...options, activeArc: 4 },
  );
  assert.equal(focused.markers[0].priority, 3);
  assert.equal(overlayDisplay(focused).markers[0].color, "#fff2bc");
});

test("timing uncertainty remains metadata even with a known pin arrival", () => {
  const scene = arrivalScene(
    {
      marks: [{ ...mark(3), timingUnknown: true }, mark(null)],
      segments: [
        {
          from: p(0, 0, 0),
          to: p(10, 20, 3),
          kind: "propagation",
          timingUnknown: true,
        },
        { from: p(10, 20, 3), to: p(10, 20, 5), kind: "readiness" },
      ],
    },
    options,
  );
  assert.ok(
    scene.markers.every(
      (row) => row.overlayRole === "timing" && row.timingUnknown,
    ),
  );
  assert.equal(scene.segments[0].overlayRole, "timing");
  assert.equal(scene.segments[0].timingUnknown, true);
  assert.equal(scene.segments[1].overlayRole, "annotation");
});
