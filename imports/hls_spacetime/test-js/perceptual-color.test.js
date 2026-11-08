import assert from "node:assert/strict";
import test from "node:test";
import {
  COMPUTATION_COLORS,
  COMPUTATION_SHARED_COLOR,
  DIRECTION_SINK_COLOR,
  DIRECTION_SOURCE_COLOR,
  FUNCTION_COLORS,
  UNKNOWN_COLOR,
  OUTSIDE_TIMING_COLOR,
  computationColor,
  directionColor,
  sceneColor,
  timingColor,
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
      OUTSIDE_TIMING_COLOR,
    );
  }
  assert.notEqual(
    sceneColor({ mode: "timing", delayNs: 0, maxDelayNs: 0 }),
    UNKNOWN_COLOR,
    OUTSIDE_TIMING_COLOR,
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

test("computation categories are stable and approximately equal in lightness", () => {
  assert.equal(new Set(COMPUTATION_COLORS).size, 12);
  for (const color of COMPUTATION_COLORS) {
    assert.ok(Math.abs(lightness(color) - 0.73) < 0.003);
    assert.notEqual(color, UNKNOWN_COLOR);
  }
  const keys = ["actor/1:compute", "actor/2:publish", "φ/update", 0, 45];
  const original = keys.map(computationColor);
  assert.deepEqual(
    [...keys].reverse().map(computationColor).reverse(),
    original,
  );
  assert.ok(original.every((color) => COMPUTATION_COLORS.includes(color)));
  for (const key of [null, undefined, "", NaN, 0.5, {}, []]) {
    assert.equal(computationColor(key), UNKNOWN_COLOR);
  }
});

test("direction has fixed source/sink endpoints and ordered lightness", () => {
  assert.equal(directionColor(0), DIRECTION_SOURCE_COLOR);
  assert.equal(directionColor(1), DIRECTION_SINK_COLOR);
  assert.equal(directionColor(-2), DIRECTION_SOURCE_COLOR);
  assert.equal(directionColor(2), DIRECTION_SINK_COLOR);
  assert.ok(lightness(DIRECTION_SOURCE_COLOR) < 0.51);
  assert.ok(lightness(DIRECTION_SINK_COLOR) > 0.87);
  let previous = 0;
  for (let step = 0; step <= 100; step++) {
    const current = lightness(directionColor(step / 100));
    assert.ok(current >= previous - 0.0015);
    previous = current;
  }
  for (const value of [null, undefined, NaN, Infinity]) {
    assert.equal(directionColor(value), UNKNOWN_COLOR);
  }
});

test("timing separates dim low-delay and bright high-delay circuitry", () => {
  assert.ok(lightness(timingColor(0, 10)) < 0.41);
  assert.ok(lightness(timingColor(10, 10)) > 0.89);
  assert.equal(
    timingColor(3, 10),
    sceneColor({ mode: "timing", delayNs: 3, maxDelayNs: 10 }),
  );
});

test("computation modes preserve categorical identity and unknown timing", () => {
  const options = { mode: "computation", computationKey: "actor/1:update" };
  assert.equal(sceneColor(options), computationColor(options.computationKey));
  assert.equal(
    sceneColor({ ...options, delayNs: 10, maxDelayNs: 10 }),
    sceneColor(options),
  );
  const hybrid = { ...options, mode: "computation-timing", maxDelayNs: 10 };
  assert.equal(sceneColor(hybrid), UNKNOWN_COLOR);
  assert.equal(
    sceneColor({ ...hybrid, computationKey: null, delayNs: 10 }),
    UNKNOWN_COLOR,
    OUTSIDE_TIMING_COLOR,
  );
  let previous = 0;
  for (let step = 0; step <= 100; step++) {
    const current = lightness(sceneColor({ ...hybrid, delayNs: step / 10 }));
    assert.ok(current >= previous - 0.0015);
    previous = current;
  }
  assert.ok(previous > 0.89);
  assert.throws(() => sceneColor({ mode: "invented" }), RangeError);
});

test("known shared computations use neutral gray without claiming an identity", () => {
  assert.equal(
    sceneColor({ mode: "computation", computationShared: true }),
    COMPUTATION_SHARED_COLOR,
  );
  assert.notEqual(COMPUTATION_SHARED_COLOR, UNKNOWN_COLOR);
  assert.equal(sceneColor({ mode: "computation" }), UNKNOWN_COLOR);
  const hybrid = {
    mode: "computation-timing",
    computationShared: true,
    maxDelayNs: 10,
  };
  assert.equal(sceneColor(hybrid), UNKNOWN_COLOR);
  for (const delayNs of [0, 5, 10]) {
    const color = sceneColor({ ...hybrid, delayNs });
    assert.equal(color.slice(1, 3), color.slice(3, 5));
    assert.equal(color.slice(3, 5), color.slice(5, 7));
    assert.equal(
      color,
      sceneColor({ ...hybrid, delayNs, computationKey: "ignored/when/shared" }),
    );
  }
});

test("outside-scope timing is distinct from unknown and zero without changing categorical styles", () => {
  for (const mode of ["timing", "computation-timing"]) {
    assert.equal(
      sceneColor({ mode, timingApplicable: false }),
      OUTSIDE_TIMING_COLOR,
    );
    assert.notEqual(sceneColor({ mode, maxDelayNs: 1 }), OUTSIDE_TIMING_COLOR);
    assert.notEqual(
      sceneColor({ mode, computationKey: "a", delayNs: 0, maxDelayNs: 1 }),
      OUTSIDE_TIMING_COLOR,
    );
  }
  assert.equal(
    sceneColor({
      mode: "computation",
      computationKey: "a",
      timingApplicable: false,
    }),
    computationColor("a"),
  );
});

test("relative urgency uses a fixed capture maximum and preserves unknown ownership/timing", () => {
  const base = {
    mode: "criticality",
    computationKey: "actor",
    maxDelayNs: 10,
    marginWindowNs: 1,
  };
  const distant = sceneColor({ ...base, delayNs: 8 });
  const near = sceneColor({ ...base, delayNs: 9.5 });
  const critical = sceneColor({ ...base, delayNs: 10 });
  assert(lightness(distant) < lightness(near));
  assert(lightness(near) < lightness(critical));
  assert.equal(distant, sceneColor({ ...base, delayNs: 0 }));
  assert.equal(sceneColor({ ...base, delayNs: null }), UNKNOWN_COLOR);
  assert.equal(
    sceneColor({ ...base, delayNs: 10, computationKey: null }),
    UNKNOWN_COLOR,
  );
  assert.equal(
    sceneColor({ ...base, delayNs: 10, timingApplicable: false }),
    OUTSIDE_TIMING_COLOR,
  );
  assert.throws(
    () => sceneColor({ ...base, delayNs: 10, marginWindowNs: 0 }),
    /positive/,
  );
});
