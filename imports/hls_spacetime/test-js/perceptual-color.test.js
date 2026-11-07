import assert from "node:assert/strict";
import test from "node:test";
import {
  FUNCTION_COLORS,
  UNKNOWN_COLOR,
  sceneColor,
  timingExtent,
} from "../web/perceptual-color.js";

// Independently recover Oklab lightness from the final quantized display color.
function lightness(hex) {
  const rgb = [1, 3, 5].map((offset) => {
    const value = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  const [r, g, b] = rgb;
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
}

test("capture timing domain preserves unknowns and known zero", () => {
  assert.deepEqual(timingExtent([null, 0, 4.2, undefined, NaN, -1]), {
    min: 0,
    max: 4.2,
    known: 2,
    unknown: 4,
  });
  assert.deepEqual(timingExtent([null]), {
    min: 0,
    max: null,
    known: 0,
    unknown: 1,
  });
});

test("function colors do not depend on timing or selection", () => {
  for (const [role, color] of Object.entries(FUNCTION_COLORS)) {
    assert.equal(sceneColor({ role, delayNs: 100, maxDelayNs: 100 }), color);
  }
  assert.equal(sceneColor({ role: "unqualified" }), UNKNOWN_COLOR);
});

test("unknown timing is never rendered as a zero-delay sample", () => {
  for (const delayNs of [null, undefined, NaN, Infinity, -1]) {
    assert.equal(
      sceneColor({ mode: "timing", delayNs, maxDelayNs: 10 }),
      UNKNOWN_COLOR,
    );
  }
  assert.notEqual(
    sceneColor({ mode: "timing", delayNs: 0, maxDelayNs: 0 }),
    UNKNOWN_COLOR,
  );
  assert.equal(sceneColor({ mode: "timing", delayNs: 3 }), UNKNOWN_COLOR);
});

test("the final display scale increases perceptual lightness", () => {
  let previous = 0;
  for (let step = 0; step <= 100; step++) {
    const color = sceneColor({
      mode: "timing",
      delayNs: step / 10,
      maxDelayNs: 10,
    });
    assert.match(color, /^#[0-9a-f]{6}$/);
    const current = lightness(color);
    assert.ok(
      current >= previous - 0.0015,
      `${step}: ${current} follows ${previous}`,
    );
    previous = current;
  }
  assert.ok(previous > 0.83);
});

test("one fixed domain gives stable colors across display windows", () => {
  const extent = timingExtent([1, 2, 5, 10]);
  const options = { mode: "timing", delayNs: 2, maxDelayNs: extent.max };
  assert.equal(sceneColor(options), sceneColor({ ...options, focus: true }));
  assert.equal(
    sceneColor({ mode: "timing", delayNs: 20, maxDelayNs: 10 }),
    sceneColor({ mode: "timing", delayNs: 10, maxDelayNs: 10 }),
  );
});
