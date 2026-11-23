import assert from "node:assert/strict";
import test from "node:test";
import { latencyScenario, periodSensitivity } from "../web/latency-scenario.js";

const event = (id, cycle, extraLatency = 0) => ({
  id,
  cycle,
  extraLatency,
  incarnation: "epoch0",
});
const edge = (source, target, minLag = 0, maxLag) => ({
  source,
  target,
  minLag,
  ...(maxLag === undefined ? {} : { maxLag }),
});
function scenario(events, edges, targets, extra = {}) {
  return {
    events,
    edges,
    targets,
    start: { cycle: 0, incarnation: "epoch0" },
    bounds: { firstCycle: 0, endCycle: 50, endKind: "capture" },
    dependencyComplete: true,
    unknowns: [],
    ...extra,
  };
}
const time = (result, id) => result.events.find((row) => row.id === id);

/** Independent small clock-by-clock oracle: start ready operations, then retire
 * their extra latency. Zero-duration operations reach a same-clock fixed point.
 * It does not use topological sorting or the solver's maximum-time recurrence.
 */
function clockOracle(input, horizon = 40) {
  const finished = new Map(),
    pending = new Map(),
    begun = new Set();
  for (let clock = 0; clock < horizon; clock++) {
    for (const [id, due] of pending)
      if (due === clock) {
        finished.set(id, clock);
        pending.delete(id);
      }
    let changed = true;
    while (changed) {
      changed = false;
      for (const operation of input.events) {
        if (begun.has(operation.id) || operation.cycle > clock) continue;
        const inputs = input.edges.filter(
          (constraint) => constraint.target === operation.id,
        );
        if (
          inputs.some(
            (constraint) =>
              !finished.has(constraint.source) ||
              finished.get(constraint.source) + constraint.minLag > clock,
          )
        )
          continue;
        begun.add(operation.id);
        const due = clock + (operation.extraLatency ?? 0);
        if (due === clock) finished.set(operation.id, clock);
        else pending.set(operation.id, due);
        changed = true;
      }
    }
  }
  assert.equal(
    finished.size,
    input.events.length,
    "small oracle horizon must cover every operation",
  );
  return finished;
}

test("zero intervention reproduces the witnessed baseline without changing evidence", () => {
  const input = scenario(
    [event("a", 0), event("b", 3), event("done", 5)],
    [edge("a", "b", 1), edge("b", "done", 1)],
    ["done"],
  );
  const before = structuredClone(input);
  const result = latencyScenario(input);
  assert.equal(result.status, "conditional");
  assert.deepEqual(result.baseline, { completionCycle: 5, elapsedCycles: 5 });
  assert.deepEqual(result.candidate, {
    completionCycle: 5,
    elapsedCycles: 5,
    deltaCycles: 0,
  });
  assert.deepEqual(
    result.events.map((row) => row.scenarioCycle),
    [0, 3, 5],
  );
  assert.equal(time(result, "b").baselineFloorBinding, true);
  assert.deepEqual(time(result, "b").blockingPredecessors, []);
  assert.deepEqual(input, before);
});

test("declared minimum lags let gaps absorb delays without timestamp telescoping", () => {
  const edges = [edge("a", "b", 1), edge("b", "done", 1)];
  const absorbed = latencyScenario(
    scenario([event("a", 0, 2), event("b", 3), event("done", 5)], edges, [
      "done",
    ]),
  );
  assert.deepEqual(
    absorbed.events.map((row) => row.scenarioCycle),
    [2, 3, 5],
  );
  assert.equal(absorbed.candidate.deltaCycles, 0);
  const excess = latencyScenario(
    scenario([event("a", 0, 4), event("b", 3), event("done", 5)], edges, [
      "done",
    ]),
  );
  assert.deepEqual(
    excess.events.map((row) => row.scenarioCycle),
    [4, 5, 6],
  );
  assert.equal(excess.candidate.deltaCycles, 1);
});

test("extra latency applies after readiness on every repeated invocation", () => {
  const result = latencyScenario(
    scenario(
      [event("a", 0, 1), event("b", 1, 1), event("done", 2, 1)],
      [edge("a", "b", 1), edge("b", "done", 1)],
      ["done"],
    ),
  );
  assert.deepEqual(
    result.events.map((row) => row.availabilityCycle),
    [0, 2, 4],
  );
  assert.deepEqual(
    result.events.map((row) => row.scenarioCycle),
    [1, 3, 5],
  );
  assert.equal(result.candidate.deltaCycles, 3);
  assert.equal(result.scope.ancestorInterventions, 3);
});

test("fanin ties and multiple completion endpoints are retained exactly", () => {
  const result = latencyScenario(
    scenario(
      [event("b", 0, 2), event("a", 0, 2), event("join", 2), event("other", 4)],
      [edge("a", "join", 1), edge("b", "join", 1), edge("a", "join", 0)],
      ["join", "other"],
    ),
  );
  assert.deepEqual(time(result, "join").blockingPredecessors, ["a", "b"]);
  assert.equal(time(result, "join").scenarioCycle, 3);
  assert.equal(time(result, "join").baselineFloorBinding, false);
  assert.deepEqual(result.targets, [
    { id: "join", baselineCycle: 2, scenarioCycle: 3 },
    { id: "other", baselineCycle: 4, scenarioCycle: 4 },
  ]);
  assert.equal(result.candidate.completionCycle, 4);
});

test("explicit old-value anti-dependencies preserve reads before replacement", () => {
  const input = scenario(
    [
      event("write", 0),
      event("read", 1, 3),
      event("replace", 2),
      event("done", 3),
    ],
    [
      edge("write", "read", 1),
      edge("read", "replace", 0),
      edge("replace", "done", 1),
    ],
    ["done"],
  );
  const readFirst = latencyScenario(input);
  assert.equal(time(readFirst, "read").scenarioCycle, 4);
  assert.equal(time(readFirst, "replace").scenarioCycle, 4);
  assert.equal(readFirst.candidate.completionCycle, 5);
  const strict = latencyScenario({
    ...input,
    edges: [input.edges[0], edge("read", "replace", 1), input.edges[2]],
  });
  assert.equal(time(strict, "replace").scenarioCycle, 5);
  assert.equal(strict.candidate.completionCycle, 6);
});

test("storage-port order is supplied separately and not inferred from chronological neighbors", () => {
  const events = [event("first", 0, 3), event("next", 1), event("done", 2)];
  const independent = latencyScenario(
    scenario(events, [edge("next", "done", 1)], ["done"]),
  );
  assert.equal(independent.candidate.completionCycle, 2);
  const ordered = latencyScenario(
    scenario(
      events,
      [edge("first", "next", 1), edge("next", "done", 1)],
      ["done"],
    ),
  );
  assert.equal(ordered.candidate.completionCycle, 5);
});

test("declared memory latency remains exact and its violation has no completion score", () => {
  const input = scenario(
    [event("request", 2, 1), event("result", 4), event("done", 6)],
    [edge("request", "result", 2, 2), edge("result", "done", 0)],
    ["done"],
  );
  const moved = latencyScenario(input);
  assert.equal(time(moved, "request").scenarioCycle, 3);
  assert.equal(time(moved, "result").scenarioCycle, 5);
  assert.equal(moved.candidate.completionCycle, 6);
  const violated = latencyScenario({
    ...input,
    events: [event("request", 2), event("result", 4, 1), event("done", 6)],
  });
  assert.equal(violated.status, "invalid");
  assert.equal(violated.reason, "maximum_lag_violation");
  assert.equal(violated.candidate, null);
  assert.equal(violated.violations[0].gap, 3);
  assert.deepEqual(
    periodSensitivity(violated, { baselinePeriodNs: 10, candidatePeriodNs: 5 }),
    {
      status: "unavailable",
      reason: "invalid",
      assumptions: { baselinePeriodNs: 10, candidatePeriodNs: 5 },
    },
  );
});

test("same-edge write-first zero-latency response is expressible without invented Q delay", () => {
  const result = latencyScenario(
    scenario(
      [event("write", 1, 2), event("request", 1), event("result", 1)],
      [edge("write", "request", 0), edge("request", "result", 0, 0)],
      ["result"],
    ),
  );
  assert.deepEqual(
    result.events.map((row) => row.scenarioCycle),
    [3, 3, 3],
  );
  assert.equal(result.status, "conditional");
});

test("known small schedules match an independent clock-by-clock oracle", () => {
  const inputs = [
    scenario(
      [event("done", 5), event("b", 3), event("a", 0, 4)],
      [edge("a", "b", 1), edge("b", "done", 1)],
      ["done"],
    ),
    scenario(
      [event("done", 2, 1), event("b", 1, 1), event("a", 0, 1)],
      [edge("a", "b", 1), edge("b", "done", 1)],
      ["done"],
    ),
    scenario(
      [event("join", 2), event("a", 0, 2), event("b", 1, 3), event("done", 4)],
      [edge("a", "join", 1), edge("b", "join", 1), edge("join", "done", 0)],
      ["done"],
    ),
    scenario(
      [event("result", 4), event("request", 2, 1), event("done", 6)],
      [edge("request", "result", 2, 2), edge("result", "done", 0)],
      ["done"],
    ),
  ];
  for (const input of inputs) {
    const expected = clockOracle(input);
    const result = latencyScenario(input);
    assert.equal(result.status, "conditional");
    for (const row of result.events)
      assert.equal(row.scenarioCycle, expected.get(row.id));
  }
});

test("carry-in and unknown dependency metadata remain conditional rather than complete", () => {
  const unknowns = [
    { kind: "carry_in", version: "initial-word" },
    { kind: "unknown_control", event: "done" },
  ];
  const input = scenario(
    [event("root", 5), event("done", 7)],
    [edge("root", "done", 0)],
    ["done"],
    {
      start: { cycle: 6, incarnation: "epoch0" },
      bounds: { firstCycle: 5, endCycle: 10, endKind: "capture" },
      unknowns,
    },
  );
  delete input.dependencyComplete;
  const result = latencyScenario(input);
  assert.equal(result.status, "conditional");
  assert.equal(result.coverage.dependencyComplete, false);
  assert.deepEqual(result.coverage.unknowns, unknowns);
  assert.notEqual(result.coverage.unknowns, unknowns);
  assert.equal(result.baseline.elapsedCycles, 1);
  assert.ok(
    result.assumptions.some((value) =>
      value.includes("unrecorded dependencies"),
    ),
  );
});

test("reset crossings invalidate while capture-tail crossings censor", () => {
  const input = scenario(
    [event("write", 8, 2), event("done", 9)],
    [edge("write", "done", 1)],
    ["done"],
    { bounds: { firstCycle: 0, endCycle: 10, endKind: "capture" } },
  );
  const censored = latencyScenario(input);
  assert.equal(censored.status, "censored");
  assert.equal(censored.candidate, null);
  assert.equal(censored.provisional.completionCycle, 11);
  assert.deepEqual(
    censored.violations.map((row) => row.event),
    ["write", "done"],
  );
  const invalid = latencyScenario({
    ...input,
    bounds: { ...input.bounds, endKind: "reset" },
  });
  assert.equal(invalid.status, "invalid");
  assert.equal(invalid.reason, "reset_boundary");
  assert.equal(invalid.candidate, null);
  assert.equal(invalid.provisional, null);
  assert.equal(
    periodSensitivity(censored, { baselinePeriodNs: 10, candidatePeriodNs: 1 })
      .status,
    "unavailable",
  );
});

test("unrelated downstream capture exits do not censor selected completion", () => {
  const result = latencyScenario(
    scenario(
      [event("done", 4), event("later", 8, 10)],
      [edge("done", "later", 0)],
      ["done"],
      { bounds: { firstCycle: 0, endCycle: 10, endKind: "capture" } },
    ),
  );
  assert.equal(result.status, "conditional");
  assert.equal(result.candidate.completionCycle, 4);
  assert.equal(time(result, "later").scenarioCycle, 18);
  assert.equal(result.scope.ancestorEvents, 1);
  assert.equal(result.scope.ancestorInterventions, 0);
});

test("positive and zero ordering cycles fail without trusting input order", () => {
  for (const lag of [0, 1]) {
    const result = latencyScenario(
      scenario(
        [event("a", 1), event("b", 1)],
        [edge("a", "b", lag), edge("b", "a", lag)],
        ["b"],
      ),
    );
    assert.equal(result.status, "invalid");
    assert.equal(result.reason, "dependency_cycle");
    assert.equal(result.candidate, null);
    assert.deepEqual(result.violations[0].unresolvedEventIds, ["a", "b"]);
  }
});

test("a contradictory recorded baseline is not repaired by zero intervention", () => {
  for (const constraint of [edge("a", "b", 3), edge("a", "b", 0, 1)]) {
    const result = latencyScenario(
      scenario([event("a", 0), event("b", 2)], [constraint], ["b"]),
    );
    assert.equal(result.status, "invalid");
    assert.equal(result.reason, "baseline_constraint_violation");
    assert.equal(result.candidate, null);
  }
});

test("overflow, cross-reset identities and malformed bounds are never favorable estimates", () => {
  const input = scenario(
    [event("a", 0), event("done", 2)],
    [edge("a", "done", 1)],
    ["done"],
  );
  assert.throws(
    () =>
      latencyScenario({
        ...input,
        events: [event("a", 0), { ...event("done", 2), incarnation: "epoch1" }],
      }),
    /incarnation/,
  );
  assert.throws(
    () =>
      latencyScenario({
        ...input,
        start: { cycle: 50, incarnation: "epoch0" },
      }),
    RangeError,
  );
  assert.throws(
    () =>
      latencyScenario({ ...input, events: [event("a", -1), event("done", 2)] }),
    RangeError,
  );
  assert.throws(
    () =>
      latencyScenario({
        ...input,
        events: [event("a", 0, 0.5), event("done", 2)],
      }),
    RangeError,
  );
  assert.throws(
    () => latencyScenario({ ...input, edges: [edge("a", "done", -1)] }),
    RangeError,
  );
  assert.throws(
    () => latencyScenario({ ...input, targets: ["missing"] }),
    /target/,
  );
  assert.throws(
    () => latencyScenario({ ...input, targets: ["done", "done"] }),
    /distinct/,
  );
  const end = Number.MAX_SAFE_INTEGER;
  const overflow = latencyScenario(
    scenario([event("done", end - 2, 10)], [], ["done"], {
      start: { cycle: end - 3, incarnation: "epoch0" },
      bounds: { firstCycle: end - 3, endCycle: end, endKind: "capture" },
    }),
  );
  assert.equal(overflow.status, "invalid");
  assert.equal(overflow.reason, "cycle_overflow");
  assert.equal(overflow.candidate, null);
});

test("period sensitivity uses only explicit baseline and candidate assumptions", () => {
  const result = latencyScenario(
    scenario([event("done", 10, 2)], [], ["done"]),
  );
  const score = periodSensitivity(result, {
    baselinePeriodNs: 10,
    candidatePeriodNs: 5,
  });
  assert.equal(score.baselineElapsedNs, 100);
  assert.equal(score.candidateElapsedNs, 60);
  assert.equal(score.improvementNs, 40);
  assert.equal(score.improvementPercent, 40);
  assert.equal(score.speedup, 100 / 60);
  assert.equal(score.breakEvenCandidatePeriodNs, 100 / 12);
  assert.equal(score.status, "conditional");
  assert.throws(() => periodSensitivity(result), RangeError);
  assert.throws(
    () =>
      periodSensitivity(result, { baselinePeriodNs: 0, candidatePeriodNs: 5 }),
    RangeError,
  );
  assert.throws(
    () =>
      periodSensitivity(result, {
        baselinePeriodNs: Number.MAX_VALUE,
        candidatePeriodNs: 5,
      }),
    RangeError,
  );
});

test("zero elapsed intervals never invent finite ratios or benefits", () => {
  const result = latencyScenario(scenario([event("done", 0)], [], ["done"]));
  const score = periodSensitivity(result, {
    baselinePeriodNs: 10,
    candidatePeriodNs: 5,
  });
  assert.equal(score.baselineElapsedNs, 0);
  assert.equal(score.candidateElapsedNs, 0);
  assert.equal(score.improvementNs, 0);
  assert.equal(score.improvementPercent, null);
  assert.equal(score.speedup, null);
  assert.equal(score.breakEvenCandidatePeriodNs, null);
});
