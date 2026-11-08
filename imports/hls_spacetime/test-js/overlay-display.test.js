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
