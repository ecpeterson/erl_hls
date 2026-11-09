import assert from "node:assert/strict";
import test from "node:test";
import { arrivalRuler } from "../web/arrival-ruler.js";
import { layoutLabels, projectLabelAnchors } from "../web/labels.js";

test("quarter labels share the native geometry's common hypothetical budget", () => {
  const labels = arrivalRuler(7, 2, 10);
  assert.deepEqual(
    labels.map((label) => label.coordinate),
    [7.25, 7.5, 7.75, 8.25, 8.5, 8.75],
  );
  assert.deepEqual(
    labels.map((label) => label.text),
    ["+2.5 ns", "+5 ns", "+7.5 ns", "+2.5 ns", "+5 ns", "+7.5 ns"],
  );
  assert.equal(new Set(labels.map((label) => label.key)).size, 6);
  assert.deepEqual(
    arrivalRuler(7, 1, 5).map((label) => label.offsetNs),
    [1.25, 2.5, 3.75],
  );
});

test("wide windows hide minor labels only and invalid inputs still reject", () => {
  assert.equal(arrivalRuler(7, 4, 10).length, 12);
  assert.deepEqual(arrivalRuler(7, 5, 10), []);
  for (const window of [0, -1, 0.5, NaN, Infinity])
    assert.throws(() => arrivalRuler(7, window, 10), RangeError);
  for (const first of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER])
    assert.throws(() => arrivalRuler(first, 5, 10), RangeError);
  for (const budget of [0, -1, NaN, Infinity])
    assert.throws(() => arrivalRuler(7, 5, budget), RangeError);
});

test("minor labels follow the Q axis and lose collisions to its major labels", () => {
  const labels = arrivalRuler(7, 1, 10).map((label) => ({
    ...label,
    anchorGroup: "clock-axis",
    alternatives: [
      { x: 80, y: (label.coordinate - 7) * 80, visible: true },
      { x: 160, y: (label.coordinate - 7) * 80, visible: true },
    ],
  }));
  labels.unshift({
    text: "Q sample 7",
    anchorGroup: "clock-axis",
    alternatives: [
      { x: 80, y: 0, visible: true },
      { x: 160, y: 0, visible: true },
    ],
  });
  const projected = projectLabelAnchors(labels, (point) => point);
  assert.ok(projected.every(({ point }) => point.x === 80));
  const rectangles = projected.map(({ label, point }, index) => ({
    ...label,
    x: point.x,
    y: point.y,
    width: 50,
    height: 20,
    priority: index === 0 ? 100 : 90,
  }));
  const visible = layoutLabels(rectangles, { width: 320, height: 200 });
  assert.equal(visible[0].text, "Q sample 7");
  assert.ok(!visible.some((label) => label.coordinate === 7.25));
  assert.ok(visible.some((label) => label.coordinate === 7.5));
});
