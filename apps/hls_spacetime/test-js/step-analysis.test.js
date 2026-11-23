import test from "node:test";
import assert from "node:assert/strict";
import { validateClockReference } from "../web/clock-reference.js";
import {
  validateStepComparison,
  installStepEvidence,
  stepComparisonMetrics,
} from "../web/step-analysis.js";

/** These reported N2 periods and 99-clock intervals are a compact fixture,
 * not a rerun or qualification of the retained native/RTL experiment. */
function fixture() {
  const evidence = [
    {
      file: "witness.json",
      sha256: "e".repeat(64),
      scope: "finite recorded witness",
    },
  ];
  const reference = (id, period) => ({
    schema: 1,
    build: {
      source: `source-${id}`,
      rtl: `rtl-${id}`,
      observation: `observer-${id}`,
    },
    checkpoint: id.repeat(64),
    clock: "clk",
    device: "part",
    stage: "routed",
    scope: "global_single_clock_setup",
    targetPeriodNs: 5,
    setupWnsNs: 5 - period,
    summary: { file: `summary-${id}.rpt`, sha256: id.repeat(64) },
    limitingPaths: [
      {
        id: "worst",
        source: "launch/C",
        endpoint: "capture/D",
        slackNs: 5 - period,
        report: { file: `paths-${id}.rpt`, sha256: "d".repeat(64) },
      },
    ],
  });
  const before = reference("a", 8.997),
    after = reference("b", 5.56);
  const boundary = (id, cycle, eventIds = []) => ({
    id,
    label: id,
    cycle,
    eventIds,
    evidence,
  });
  const comparison = {
    schema: 1,
    id: "step",
    label: "Matched step",
    comparisonKey: "same-workload/step-3",
    current: "before",
    build: before.build,
    incarnation: "epoch",
    start: boundary("start", 100, ["start-event"]),
    end: boundary("end", 199, ["end-event"]),
    variants: [
      {
        id: "before",
        label: "Before",
        startCycle: 100,
        endCycle: 199,
        clockReference: before,
        evidence,
      },
      {
        id: "after",
        label: "After",
        startCycle: 200,
        endCycle: 299,
        clockReference: after,
        evidence,
      },
    ],
    milestones: [
      {
        ...boundary("work", 150, ["work-event"]),
        basis: "validated_control_replay",
      },
    ],
    links: [
      {
        from: "work",
        to: "end",
        label: "Reviewed completion tail",
        basis: "model_dependency",
        evidence,
      },
    ],
    assumptions: ["Matched finite workload"],
    unknowns: ["Untapped exterior handshakes remain unanchored"],
  };
  const model = {
    bundle: { build: before.build, capture: { clock: "clk", device: "part" } },
    catalogue: { build: before.build, checkpoint: before.checkpoint },
    epochs: new Map([
      ["epoch", { id: "epoch", first_cycle: 0, end_cycle: 400 }],
    ]),
    events: new Map([
      ["start-event", { id: "start-event", cycle: 100, incarnation: "epoch" }],
      ["work-event", { id: "work-event", cycle: 150, incarnation: "epoch" }],
      ["end-event", { id: "end-event", cycle: 199, incarnation: "epoch" }],
      [
        "foreign-event",
        { id: "foreign-event", cycle: 199, incarnation: "another" },
      ],
    ]),
    document: { clockReference: before, stepComparison: comparison },
  };
  model.clockReference = validateClockReference(model);
  return model;
}
const close = (a, b) => assert(Math.abs(a - b) < 1e-9, `${a} != ${b}`);

test("matched global periods reproduce the retained 99-clock duration comparison", () => {
  const model = fixture(),
    original = structuredClone(model);
  const comparison = validateStepComparison(model);
  const metrics = stepComparisonMetrics(comparison);
  assert.deepEqual(
    metrics.rows.map((r) => r.elapsedCycles),
    [99, 99],
  );
  close(metrics.rows[0].periodNs, 8.997);
  close(metrics.rows[1].periodNs, 5.56);
  close(metrics.rows[0].elapsedNs / 1000, 0.890703);
  close(metrics.rows[1].elapsedNs / 1000, 0.55044);
  close(metrics.change.elapsedNs, -340.263);
  close(metrics.change.percentReduction, 100 * (1 - 5.56 / 8.997));
  assert.equal(metrics.change.cycleContributionNs, 0);
  close(metrics.change.clockContributionNs, -340.263);
  assert.deepEqual(
    metrics.rows.map((r) => r.current),
    [true, false],
  );
  assert.deepEqual(model, original);
});

test("target and manual modes scale cycles without adding static path delay", () => {
  const comparison = validateStepComparison(fixture());
  for (const [options, expected, source] of [
    [{ mode: "target" }, 495, "original_sta_target"],
    [{ mode: "manual", manualPeriodNs: 10 }, 990, "manual_assumption"],
  ]) {
    const metrics = stepComparisonMetrics(comparison, options);
    assert.deepEqual(
      metrics.rows.map((r) => r.elapsedNs),
      [expected, expected],
    );
    assert(metrics.rows.every((r) => r.periodSource === source));
    assert.equal(metrics.change.elapsedNs, 0);
    assert.equal(metrics.change.clockContributionNs, 0);
    assert.equal(metrics.change.cycleContributionNs, 0);
  }
});

test("cycle and clock contributions use the declared before/after order", () => {
  const model = fixture();
  model.document.stepComparison.variants[1].endCycle = 310;
  const comparison = validateStepComparison(model);
  const metrics = stepComparisonMetrics(comparison);
  close(metrics.change.cycleContributionNs, 11 * 8.997);
  close(metrics.change.clockContributionNs, 110 * (5.56 - 8.997));
  close(
    metrics.change.cycleContributionNs + metrics.change.clockContributionNs,
    metrics.change.elapsedNs,
  );
  const manual = stepComparisonMetrics(comparison, {
    mode: "manual",
    manualPeriodNs: 10,
  });
  assert.equal(manual.change.cycleContributionNs, 110);
  assert.equal(manual.change.clockContributionNs, 0);
  model.document.stepComparison.variants.reverse();
  const reversed = stepComparisonMetrics(validateStepComparison(model));
  assert.equal(reversed.change.before, "after");
  assert.equal(reversed.change.after, "before");
  close(reversed.change.elapsedNs, -metrics.change.elapsedNs);
});

test("exactly two variants and a nonempty correspondence key are required", () => {
  for (const mutate of [
    (v) => {
      delete v.comparisonKey;
    },
    (v) => {
      v.comparisonKey = " ";
    },
    (v) => {
      v.variants.pop();
    },
    (v) => {
      v.variants.push({ ...v.variants[1], id: "third" });
    },
    (v) => {
      v.variants[1].id = v.variants[0].id;
    },
    (v) => {
      v.current = "missing";
    },
  ]) {
    const model = fixture();
    mutate(model.document.stepComparison);
    assert.throws(() => validateStepComparison(model), /Step comparison:/);
  }
});

test("current variant must match this capture's complete STA identity", () => {
  for (const mutate of [
    (r) => {
      r.build.rtl = "foreign";
    },
    (r) => {
      r.checkpoint = "c".repeat(64);
    },
    (r) => {
      r.clock = "other";
    },
    (r) => {
      r.device = "other";
    },
    (r) => {
      r.targetPeriodNs = 6;
    },
    (r) => {
      r.setupWnsNs = -4;
      r.limitingPaths[0].slackNs = -4;
    },
    (r) => {
      r.summary.sha256 = "f".repeat(64);
    },
    (r) => {
      r.summary.file = "other-summary.rpt";
    },
  ]) {
    const model = fixture();
    model.document.stepComparison.variants[0].clockReference = structuredClone(
      model.document.clockReference,
    );
    mutate(model.document.stepComparison.variants[0].clockReference);
    assert.throws(
      () => validateStepComparison(model),
      /current variant STA mismatch/,
    );
  }
  const wrongInterval = fixture();
  wrongInterval.document.stepComparison.variants[0].endCycle++;
  assert.throws(
    () => validateStepComparison(wrongInterval),
    /interval mismatch/,
  );
});

test("graph anchors must exist at the declared cycle and incarnation", () => {
  for (const eventIds of [
    ["absent"],
    ["work-event"],
    ["foreign-event"],
    ["end-event", "end-event"],
  ]) {
    const model = fixture();
    model.document.stepComparison.end.eventIds = eventIds;
    assert.throws(() => validateStepComparison(model), /boundary anchor/);
  }
  const model = fixture();
  model.document.stepComparison.end.eventIds = [];
  model.document.stepComparison.end.label =
    "Externally witnessed completion, no graph tap";
  const count = model.events.size,
    comparison = validateStepComparison(model);
  assert.deepEqual(comparison.end.eventIds, []);
  assert.equal(model.events.size, count);
  assert.deepEqual(comparison.nodes.get("end").eventIds, []);
  assert.equal(stepComparisonMetrics(comparison).rows[0].elapsedCycles, 99);
});

test("milestone and explanation validation cannot fabricate chronology or missing evidence", () => {
  for (const mutate of [
    (v) => {
      v.milestones[0].basis = "inferred";
    },
    (v) => {
      v.milestones[0].evidence = [];
    },
    (v) => {
      v.milestones.push({
        ...v.milestones[0],
        id: "earlier",
        cycle: 140,
        eventIds: [],
      });
    },
    (v) => {
      v.links[0].from = "missing";
    },
    (v) => {
      v.links[0].from = "end";
      v.links[0].to = "work";
    },
    (v) => {
      v.links[0].basis = "physical_cause";
    },
    (v) => {
      v.variants[1].clockReference.limitingPaths[0].nativePathId = "borrowed";
    },
  ]) {
    const model = fixture();
    mutate(model.document.stepComparison);
    assert.throws(() => validateStepComparison(model), /Step comparison:/);
  }
});

test("sidecar installation is atomic on both clock and step validation failures", () => {
  for (const mutate of [
    (p) => {
      p.clockReference = { ...p.clockReference, checkpoint: "f".repeat(64) };
    },
    (p) => {
      p.stepComparison = { ...p.stepComparison, comparisonKey: "" };
    },
    (p) => {
      p.stepComparison = structuredClone(p.stepComparison);
      p.stepComparison.end.eventIds = ["absent"];
    },
  ]) {
    const model = fixture();
    const payload = {
      clockReference: model.document.clockReference,
      stepComparison: model.document.stepComparison,
    };
    model.document = { title: "Original recording" };
    model.clockReference = null;
    model.stepComparison = null;
    const original = structuredClone(model),
      document = model.document;
    mutate(payload);
    assert.throws(() => installStepEvidence(model, payload));
    assert.equal(model.document, document);
    assert.deepEqual(model, original);
  }
  const model = fixture();
  const payload = {
    clockReference: model.document.clockReference,
    stepComparison: model.document.stepComparison,
  };
  model.document = { title: "Original recording" };
  model.clockReference = null;
  model.stepComparison = null;
  const bundle = model.bundle;
  installStepEvidence(model, payload);
  assert.equal(model.bundle, bundle);
  assert.equal(model.document.title, "Original recording");
  assert.equal(model.stepComparison.comparisonKey, "same-workload/step-3");
  close(model.clockReference.setupPeriodNs, 8.997);
  assert.throws(
    () => installStepEvidence(model, payload),
    /replace embedded evidence/,
  );
});
