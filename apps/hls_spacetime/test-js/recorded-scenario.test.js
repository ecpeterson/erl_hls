import test from "node:test";
import assert from "node:assert/strict";
import {
  recordedScenario,
  validateLatencyProfile,
} from "../web/recorded-scenario.js";

/** Independent tiny observation index: coupled outputs at C1, next-edge commit,
 * then immediate feedback at C3. Its old-value reader shares a replacement edge. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" };
  const events = [
    { id: "input", cycle: 0, outputs: ["input-v"] },
    {
      id: "action1",
      cycle: 1,
      inputs: ["input-v"],
      outputs: ["v1"],
      access: {
        kind: "write",
        resource: "result",
        port: "w",
        before: "root",
        after_version: "v1",
      },
    },
    { id: "valid1", cycle: 1 },
    {
      id: "read1",
      cycle: 2,
      inputs: ["v1"],
      access: {
        kind: "read_request",
        resource: "result",
        port: "r",
        version: "v1",
      },
    },
    { id: "commit1", cycle: 2 },
    {
      id: "action2",
      cycle: 3,
      outputs: ["v2"],
      access: {
        kind: "write",
        resource: "result",
        port: "w",
        before: "v1",
        after_version: "v2",
      },
    },
    { id: "commit2", cycle: 4 },
    { id: "done", cycle: 4 },
  ].map((e, i) => ({
    incarnation: "epoch",
    sequence: i,
    inputs: [],
    outputs: [],
    ...e,
  }));
  const versions = [
    { id: "root", producer: "root", storage: { resource: "result" } },
    { id: "input-v", producer: "input" },
    { id: "v1", producer: "action1", storage: { resource: "result" } },
    { id: "v2", producer: "action2", storage: { resource: "result" } },
  ];
  const model = {
    bundle: { build, capture: { end_cycle: 100 } },
    epochs: new Map([["epoch", { first_cycle: 0, end_cycle: 100 }]]),
    events: new Map(events.map((e) => [e.id, e])),
    orderedEvents: events,
    resources: new Map([
      ["result", { read_latency: 0, collision: "read_first" }],
    ]),
    versions: new Map(versions.map((v) => [v.id, v])),
    consumers: new Map([["v1", ["read1"]]]),
    edges: [
      {
        source: "input",
        target: "action1",
        kind: "version",
        version: "input-v",
      },
      { source: "action1", target: "read1", kind: "version", version: "v1" },
      { source: "read1", target: "commit1", kind: "required" },
      { source: "commit2", target: "done", kind: "required" },
    ],
  };
  const profile = {
    format: "spacetime-latency-profile",
    schema: 1,
    build,
    label: "synthetic owner",
    recording: { bytes: 1, sha256: "1".repeat(64) },
    unknowns: ["synthetic only"],
    evidence: [
      {
        path: "fixture",
        sha256: "0".repeat(64),
        description: "synthetic source contract",
      },
    ],
    groups: [
      { id: "g1", trigger: "action1", members: ["action1", "valid1"] },
      { id: "g2", trigger: "action2", members: ["action2"] },
    ],
    choices: [{ id: "all", label: "all actions", groups: ["g1", "g2"] }],
    edges: [
      {
        source: "action1",
        target: "commit1",
        minLag: 1,
        reason: "result required for commit",
      },
      {
        source: "commit1",
        target: "action2",
        minLag: 1,
        reason: "feedback reissue",
      },
      {
        source: "action2",
        target: "commit2",
        minLag: 1,
        reason: "result required for commit",
      },
    ],
  };
  return { model, profile, recording: profile.recording };
}
const run = (f, options = {}) =>
  recordedScenario(f.model, f.profile, {
    recording: f.recording,
    choice: "all",
    extraLatency: 1,
    startCycle: 0,
    targets: ["done"],
    ...options,
  });
test("coupled outputs delay once and repeated feedback accumulates", () => {
  const f = fixture(),
    before = structuredClone(f),
    result = run(f);
  assert.equal(result.status, "conditional");
  assert.equal(result.candidate.elapsedCycles, 6);
  assert.equal(result.intervention.groups, 2);
  assert.equal(result.intervention.members, 3);
  assert.equal(result.groupFor.get("action1"), result.groupFor.get("valid1"));
  assert.deepEqual(f, before);
});
test("zero intervention reproduces baseline without claiming completeness", () => {
  const r = run(fixture(), { extraLatency: 0 });
  assert.equal(r.candidate.elapsedCycles, 4);
  assert.equal(r.coverage.dependencyComplete, false);
});
test("pre-step carry-in groups are not delayed", () => {
  const r = run(fixture(), { startCycle: 2 });
  assert.equal(r.candidate.elapsedCycles, 3);
  assert.equal(r.intervention.groups, 1);
});
test("only explicit gaps may absorb delay; preserving them is a different scenario", () => {
  const f = fixture();
  f.model.events.get("action2").cycle = 10;
  f.model.events.get("commit2").cycle = 11;
  f.model.events.get("done").cycle = 11;
  assert.equal(run(f).candidate.deltaCycles, 1);
  assert.equal(run(f, { policy: "preserve_gaps" }).candidate.deltaCycles, 2);
});
test("old-value request cannot move past replacement", () => {
  const f = fixture();
  f.model.events.get("read1").cycle = 3;
  f.model.edges = f.model.edges.filter((e) => e.target !== "commit1");
  f.profile.edges = f.profile.edges.filter(
    (e) => e.reason !== "feedback reissue",
  );
  f.profile.groups.push({ id: "read", trigger: "read1", members: ["read1"] });
  f.profile.choices[0].groups = ["read"];
  const r = run(f, { extraLatency: 2 });
  assert.equal(
    r.events.find((e) => e.id === "scenario-group/g2").scenarioCycle,
    5,
  );
});
test("read response preserves declared exact latency", () => {
  const f = fixture(),
    read = f.model.events.get("read1");
  f.model.resources.get("result").read_latency = 2;
  const response = {
    id: "response",
    cycle: 4,
    sequence: 9,
    incarnation: "epoch",
    inputs: ["v1"],
    outputs: [],
    access: {
      kind: "read_result",
      resource: "result",
      port: "r",
      version: "v1",
      request: "read1",
    },
  };
  f.model.events.set("response", response);
  f.model.orderedEvents.push(response);
  f.model.edges.push(
    { source: "read1", target: "response", kind: "read_request" },
    { source: "action1", target: "response", kind: "version", version: "v1" },
  );
  const r = run(f, { targets: ["response"] });
  assert.equal(r.candidate.completionCycle, 5);
});
test("same-edge broadcast reads do not create serial port work", () => {
  const f = fixture(),
    r = { ...f.model.events.get("read1"), id: "read2", sequence: 10 };
  f.model.events.set(r.id, r);
  f.model.orderedEvents.push(r);
  f.model.consumers.get("v1").push(r.id);
  f.model.edges.push({
    source: "action1",
    target: r.id,
    kind: "version",
    version: "v1",
  });
  assert.equal(run(f).candidate.elapsedCycles, 6);
});
test("profile refuses wrong build, overlapping group, and backward obligation", () => {
  for (const mutate of [
    (f) => (f.profile.build = { ...f.profile.build, rtl: "wrong" }),
    (f) => f.profile.groups[1].members.push("action1"),
    (f) => (f.profile.edges[0].minLag = 2),
  ]) {
    const f = fixture();
    mutate(f);
    assert.throws(() =>
      validateLatencyProfile(f.model, f.profile, f.recording),
    );
  }
});

test("same build with another recording is refused", () => {
  const f = fixture();
  f.recording = { bytes: 1, sha256: "2".repeat(64) };
  assert.throws(() => run(f), /recording mismatch/);
});

test("unknown operand roots stay visible in the selected ancestry", () => {
  const f = fixture();
  f.model.versions.set("unknown-input", {
    id: "unknown-input",
    producer: "root",
    origin: "unknown",
  });
  f.model.events.get("action1").inputs.push("unknown-input");
  const result = run(f);
  assert.equal(result.rootCoverage.counts.unknown, 1);
  assert.deepEqual(result.rootCoverage.roots, [
    { id: "unknown-input", origin: "unknown" },
  ]);
  assert.equal(result.coverage.dependencyComplete, false);
});
