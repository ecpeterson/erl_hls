import test from "node:test";
import assert from "node:assert/strict";
import { nativePaths } from "../web/native-paths.js";

/** Small native annotation fixture, independent of any observed event graph. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" };
  return {
    bundle: { build },
    catalogue: { checkpoint: "dcp" },
    cells: new Map([
      ["ff0", { id: "ff0", x: 1, y: 2 }],
      ["ff1", { id: "ff1", x: 70, y: 80 }],
    ]),
    document: {
      nativePaths: {
        build,
        checkpoint: "dcp",
        scope: "static_timing",
        wireGeometry: false,
        paths: [
          {
            id: "max/0",
            source: "ff0/C",
            launchPin: "ff0/Q",
            endpoint: "ff1/D",
            slackNs: -2,
            dataDelayNs: 7,
            logicDelayNs: 1,
            routeDelayNs: 6,
            logicLevels: 0,
            arcs: [
              {
                kind: "net",
                source: "ff0/Q",
                target: "ff1/D",
                net: "n",
                fanout: 1,
                delayNs: 6,
                arrivalNs: 6.1,
              },
            ],
            steps: [
              { cell: "ff0", pin: "ff0/Q", incrementNs: 0.1, arrivalNs: 0.1 },
              { cell: "ff1", pin: "ff1/D", incrementNs: null, arrivalNs: null },
            ],
          },
        ],
      },
    },
  };
}

test("native path annotations retain distant placed endpoints without execution edges", () => {
  const model = fixture();
  const original = structuredClone(model);
  assert.equal(nativePaths(model)[0].steps[1].cell, "ff1");
  assert.deepEqual(model, original);
  assert.deepEqual(nativePaths({ document: {} }), []);
});

test("foreign builds, checkpoints, unknown coordinates and endpoint mismatches reject", () => {
  for (const corrupt of [
    (m) => (m.document.nativePaths.build = { ...m.bundle.build, rtl: "other" }),
    (m) => (m.document.nativePaths.checkpoint = "other"),
    (m) => (m.cells.get("ff1").x = null),
    (m) => (m.document.nativePaths.paths[0].endpoint = "ff0/D"),
    (m) => (m.document.nativePaths.paths[0].steps[1].pin = "other/D"),
    (m) => (m.document.nativePaths.paths[0].dataDelayNs = NaN),
    (m) => (m.document.nativePaths.wireGeometry = true),
  ]) {
    const model = fixture();
    corrupt(model);
    assert.throws(() => nativePaths(model));
  }
});

test("static arc gaps, reordered endpoints and fabricated cross-cell logic reject without route data", () => {
  for (const corrupt of [
    (m) => (m.document.nativePaths.paths[0].arcs = []),
    (m) => (m.document.nativePaths.paths[0].arcs[0].source = "ff0/C"),
    (m) => (m.document.nativePaths.paths[0].arcs[0].target = "ff0/Q"),
    (m) => (m.document.nativePaths.paths[0].arcs[0].kind = "logic"),
    (m) => (m.document.nativePaths.paths[0].arcs[0].net = ""),
    (m) => (m.document.nativePaths.paths[0].arcs[0].fanout = -1),
    (m) => (m.document.nativePaths.paths[0].arcs[0].delayNs = NaN),
    (m) => (m.document.nativePaths.paths[0].logicLevels = 1),
  ]) {
    const model = fixture();
    corrupt(model);
    assert.throws(() => nativePaths(model));
  }
});
