import test from "node:test";
import assert from "node:assert/strict";
import {
  validateClockReference,
  selectClockPeriod,
  absoluteTimeNs,
  timePoint,
  stepElapsed,
} from "../web/clock-reference.js";

/** A global STA summary needs pin evidence, not an available routed-path drawing. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" },
    checkpoint = "c".repeat(64),
    report = { file: "global-paths.rpt", sha256: "b".repeat(64) };
  return {
    bundle: { build, capture: { clock: "clk", device: "part" } },
    catalogue: { build, checkpoint },
    document: {
      clockReference: {
        schema: 1,
        build,
        checkpoint,
        clock: "clk",
        device: "part",
        stage: "routed",
        scope: "global_single_clock_setup",
        targetPeriodNs: 5,
        setupWnsNs: -3,
        summary: { file: "summary.rpt", sha256: "a".repeat(64) },
        limitingPaths: [
          {
            id: "worst",
            source: "r0/C",
            endpoint: "r1/D",
            slackNs: -3,
            report,
          },
        ],
      },
    },
  };
}
const close = (a, b) => assert(Math.abs(a - b) < 1e-10, `${a} != ${b}`);

test("global STA normalizes without geometry and retains immutable provenance", () => {
  const model = fixture(),
    original = structuredClone(model);
  const reference = validateClockReference(model);
  assert.equal(reference.setupPeriodNs, 8);
  assert.equal(reference.limitingPaths[0].endpoint, "r1/D");
  assert(Object.isFrozen(reference));
  assert(Object.isFrozen(reference.build));
  assert(Object.isFrozen(reference.limitingPaths[0].report));
  assert.deepEqual(model, original);
  const automatic = selectClockPeriod(reference);
  assert.equal(automatic.periodNs, 8);
  assert.equal(automatic.source, "global_sta_target_minus_wns");
  assert.equal(automatic.provenance, reference);
  assert.equal(selectClockPeriod(reference, { mode: "target" }).periodNs, 5);
  assert.equal(
    selectClockPeriod(reference, { mode: "manual", manualPeriodNs: 12 })
      .periodNs,
    12,
  );
});

test("missing STA has no implicit period and manual assumptions stay explicit", () => {
  const model = fixture();
  delete model.document.clockReference;
  assert.equal(validateClockReference(model), null);
  for (const mode of ["auto", "target"]) {
    const result = selectClockPeriod(null, { mode });
    assert.equal(result.status, "unavailable");
    assert.equal(result.periodNs, null);
    assert.equal(stepElapsed(10, 25, result).elapsedNs, null);
  }
  assert.equal(
    selectClockPeriod(null, { mode: "manual", manualPeriodNs: 10 }).source,
    "manual_assumption",
  );
  for (const manualPeriodNs of [undefined, null, 0, -1, Infinity, NaN])
    assert.throws(
      () => selectClockPeriod(null, { mode: "manual", manualPeriodNs }),
      /manual period/,
    );
  assert.throws(() => selectClockPeriod(null, { mode: "sdf" }), /selection/);
});

test("foreign, partial and contradictory global metadata fails closed", () => {
  for (const mutate of [
    (m) => {
      m.document.clockReference = [];
    },
    (m) => {
      m.document.clockReference.schema = 2;
    },
    (m) => {
      m.document.clockReference.build = { ...m.bundle.build, rtl: "foreign" };
    },
    (m) => {
      m.document.clockReference.checkpoint = "d".repeat(64);
    },
    (m) => {
      m.document.clockReference.clock = "other";
    },
    (m) => {
      m.document.clockReference.device = "other";
    },
    (m) => {
      m.document.clockReference.stage = "placed";
    },
    (m) => {
      m.document.clockReference.scope = "selected_cone";
    },
    (m) => {
      m.document.clockReference.targetPeriodNs = 0;
    },
    (m) => {
      m.document.clockReference.setupWnsNs = Infinity;
    },
    (m) => {
      m.document.clockReference.setupWnsNs = 5;
    },
    (m) => {
      m.document.clockReference.summary.sha256 = "unknown";
    },
    (m) => {
      m.document.clockReference.limitingPaths = [];
    },
    (m) => {
      m.document.clockReference.limitingPaths[0].slackNs = -2;
    },
    (m) => {
      m.document.clockReference.limitingPaths[0].slackNs = -4;
    },
    (m) => {
      m.document.clockReference.limitingPaths[0].report.sha256 = "bad";
    },
    (m) => {
      m.document.clockReference.limitingPaths.push(
        structuredClone(m.document.clockReference.limitingPaths[0]),
      );
    },
  ]) {
    const model = fixture();
    mutate(model);
    assert.throws(() => validateClockReference(model), /Clock reference:/);
  }
  const rounded = fixture();
  rounded.document.clockReference.limitingPaths[0].slackNs = -3.0004;
  assert.equal(validateClockReference(rounded).setupPeriodNs, 8);
});

/** Optional geometry links refer to an already retained native report identity. */
function withNativePath(model) {
  model.cells = new Map([
    ["r0", { x: 0, y: 0 }],
    ["r1", { x: 1, y: 0 }],
  ]);
  model.document.nativePaths = {
    build: model.bundle.build,
    checkpoint: model.catalogue.checkpoint,
    scope: "static_timing",
    wireGeometry: false,
    report_sha256: "b".repeat(64),
    paths: [
      {
        id: "path1",
        source: "r0/C",
        launchPin: "r0/Q",
        endpoint: "r1/D",
        slackNs: -3,
        dataDelayNs: 8,
        logicDelayNs: 0,
        routeDelayNs: 8,
        logicLevels: 0,
        steps: [
          { cell: "r0", pin: "r0/Q", incrementNs: 0, arrivalNs: 0 },
          { cell: "r1", pin: "r1/D", incrementNs: 8, arrivalNs: 8 },
        ],
        arcs: [
          {
            kind: "net",
            source: "r0/Q",
            target: "r1/D",
            delayNs: 8,
            arrivalNs: 8,
            net: "n",
            fanout: 1,
          },
        ],
      },
    ],
  };
  model.document.clockReference.limitingPaths[0].nativePathId = "path1";
}

test("optional native path references must match identity, endpoints and slack", () => {
  const model = fixture();
  withNativePath(model);
  assert.equal(
    validateClockReference(model).limitingPaths[0].nativePathId,
    "path1",
  );
  for (const mutate of [
    (m) => {
      m.document.clockReference.limitingPaths[0].nativePathId = "missing";
    },
    (m) => {
      m.document.clockReference.limitingPaths[0].source = "other/C";
    },
    (m) => {
      m.document.clockReference.limitingPaths[0].report.sha256 = "e".repeat(64);
    },
    (m) => {
      delete m.document.nativePaths;
    },
  ]) {
    const changed = structuredClone(model);
    mutate(changed);
    assert.throws(() => validateClockReference(changed), /limiting path/);
  }
});

test("common nanosecond coordinates preserve absolute arrival across variant periods", () => {
  const point = { x: 2, y: 3 },
    unitsPerNs = 0.02;
  close(absoluteTimeNs(100, 6, { periodNs: 8, originCycle: 100 }), 6);
  close(absoluteTimeNs(201, 1, { periodNs: 5, originCycle: 200 }), 6);
  const before = timePoint(point, 100 + 6 / 8, {
    periodNs: 8,
    originCycle: 100,
    unitsPerNs,
  });
  const after = timePoint(point, 201 + 1 / 5, {
    periodNs: 5,
    originCycle: 200,
    unitsPerNs,
  });
  assert.deepEqual(before.slice(0, 2), [2, 3]);
  close(before[2], after[2]);
  close(before[2], 0.12);
  close(
    timePoint(point, 101, { periodNs: 8, originCycle: 100, unitsPerNs })[2],
    0.16,
  );
  close(
    timePoint(point, 201, { periodNs: 5, originCycle: 200, unitsPerNs })[2],
    0.1,
  );
  close(
    timePoint(point, 101, {
      periodNs: 8,
      originCycle: 100,
      unitsPerNs,
      originNs: 6,
    })[2],
    0.04,
  );
  assert.equal(absoluteTimeNs(99, 0, { periodNs: 8, originCycle: 100 }), -8);
  assert.equal(
    absoluteTimeNs(100, null, { periodNs: 8, originCycle: 100 }),
    null,
  );
  assert.equal(
    absoluteTimeNs(100, "not_applicable", { periodNs: 8, originCycle: 100 }),
    null,
  );
});

test("recorded step duration scales clocks once and preserves period provenance", () => {
  const selection = selectClockPeriod(validateClockReference(fixture()));
  assert.deepEqual(stepElapsed(100, 120, selection), {
    startCycle: 100,
    endCycle: 120,
    elapsedCycles: 20,
    elapsedNs: 160,
    periodNs: 8,
    periodSource: "global_sta_target_minus_wns",
    status: "available",
  });
  assert.equal(
    stepElapsed(
      200,
      220,
      selectClockPeriod(null, { mode: "manual", manualPeriodNs: 5 }),
    ).elapsedNs,
    100,
  );
  assert.equal(stepElapsed(100, 100, selection).elapsedNs, 0);
  assert.throws(() => stepElapsed(120, 100, selection), /interval/);
  assert.throws(
    () => stepElapsed(0, 1, { status: "available", periodNs: null }),
    /selection/,
  );
});

test("invalid time coordinates and arithmetic overflow reject rather than flatten", () => {
  for (const arrival of [undefined, -1, NaN, Infinity])
    assert.throws(() => absoluteTimeNs(0, arrival, { periodNs: 5 }), /arrival/);
  assert.throws(() => absoluteTimeNs(0.5, 0, { periodNs: 5 }), /clock/);
  assert.throws(() => absoluteTimeNs(1, 0, { periodNs: 0 }), /period/);
  assert.throws(
    () => absoluteTimeNs(2, 0, { periodNs: Number.MAX_VALUE }),
    /finite range/,
  );
  assert.throws(
    () => timePoint({ x: 0, y: 0 }, null, { periodNs: 5, unitsPerNs: 1 }),
    /coordinate/,
  );
  assert.throws(
    () => timePoint({ x: 0, y: 0 }, 1, { periodNs: 5, unitsPerNs: 0 }),
    /scale/,
  );
});
