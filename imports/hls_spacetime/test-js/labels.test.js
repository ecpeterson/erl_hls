import test from "node:test";
import assert from "node:assert/strict";
import { layoutLabels } from "../web/labels.js";

const viewport = { width: 320, height: 200 };
const label = (text, x, y, extra = {}) => ({
  text,
  x,
  y,
  width: 40,
  height: 10,
  ...extra,
});

test("clock-axis priority wins even when optional graph text was queued first", () => {
  const optional = label("word dependency", 25, 24, { width: 95 });
  const clock = label("C1851", 20, 20, { priority: 100 });
  const distant = label("static path", 150, 20);
  const input = [optional, distant, clock];
  assert.deepEqual(layoutLabels(input, viewport), [clock, distant]);
  assert.deepEqual(input, [optional, distant, clock]);
});

test("clipped endpoints deduplicate by cycle and direction across many bit links", () => {
  const before = label("← C1851", 5, 5, { key: "clip:before:1851" });
  const sameCycle = label("← C1851", 100, 60, { key: "clip:before:1851" });
  const after = label("C1851 →", 200, 100, { key: "clip:after:1851" });
  assert.deepEqual(layoutLabels([before, sameCycle, after], viewport), [
    before,
    after,
  ]);
  assert.deepEqual(
    layoutLabels([label("C1851", 5, 5), label("C1851", 100, 60)], viewport),
    [label("C1851", 5, 5)],
  );
});

test("offscreen or occluded copies do not reserve the duplicate key", () => {
  const obstacle = label("C1852", 20, 20, { priority: 100 });
  const clipped = label("before", -1, 5);
  const hidden = label("before", 30, 25);
  const visible = label("before", 100, 100);
  assert.deepEqual(
    layoutLabels([clipped, hidden, visible, obstacle], viewport),
    [obstacle, visible],
  );
});

test("screen rectangles respect text width, height, viewport and one padding gap", () => {
  const first = label("wide label", 0, 0, { width: 80 });
  const tooClose = label("close", 82, 0);
  const horizontal = label("beside", 83, 0);
  const vertical = label("below", 0, 13);
  const beyond = label("right edge", 300, 150);
  const lower = label("bottom edge", 200, 195);
  assert.deepEqual(
    layoutLabels(
      [first, tooClose, horizontal, vertical, beyond, lower],
      viewport,
    ),
    [first, horizontal, vertical],
  );
  assert.deepEqual(
    layoutLabels([first, label("touching", 80, 0)], { ...viewport, gap: 0 }),
    [first, label("touching", 80, 0)],
  );
});

test("ties are stable, metadata survives and invalid rectangles are omitted", () => {
  const first = label("one", 20, 20, { color: "gold", baseline: 29 });
  const second = label("two", 21, 21);
  const invalid = [
    label("nan", NaN, 10),
    label("infinite", 0, Infinity),
    label("empty", 0, 0, { width: 0 }),
    label("negative", 0, 0, { height: -1 }),
    label("", 200, 50),
  ];
  const placed = layoutLabels([...invalid, first, second], viewport);
  assert.deepEqual(placed, [first]);
  assert.equal(placed[0], first);
});
