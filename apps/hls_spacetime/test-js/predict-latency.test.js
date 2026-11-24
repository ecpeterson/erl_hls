import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, rm, truncate } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import {
  predictLatency,
  writePrediction,
  parseArguments,
} from "../scripts/predict-latency.mjs";
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const options = {
  choice: "all",
  baselinePeriodNs: 10,
  candidatePeriodNs: 5,
  savedStep: true,
};
function fixture(change = () => {}) {
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" };
  const events = [
    { id: "input", cycle: 0 },
    { id: "action", cycle: 1, inputs: ["root"], outputs: ["v"] },
    { id: "valid", cycle: 1 },
    { id: "early", cycle: 3, inputs: ["v"] },
    { id: "done", cycle: 4, inputs: ["v"] },
  ].map((event, sequence) => ({
    incarnation: "epoch",
    observer: "obs",
    sequence,
    inputs: [],
    outputs: [],
    ...event,
  }));
  const document = {
    format: "spacetime-view",
    schema: 1,
    selection: { previousCompletionCycle: 0, completionCycle: 4 },
    annotations: {
      public: [
        {
          id: "before",
          cycle: 0,
          graph_events: ["input"],
          graph_incarnation: "epoch",
          dependency_endpoint: true,
        },
        {
          id: "early-output",
          cycle: 3,
          graph_events: ["early"],
          graph_incarnation: "epoch",
          dependency_endpoint: true,
        },
        {
          id: "completion",
          cycle: 4,
          graph_events: ["done"],
          graph_incarnation: "epoch",
          dependency_endpoint: true,
        },
        { id: "unanchored-context", cycle: 4 },
      ],
    },
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        first_cycle: 0,
        end_cycle: 20,
        complete: true,
        observers: [{ id: "obs", gaps: [] }],
        incarnations: [{ id: "epoch", first_cycle: 0, end_cycle: 20 }],
      },
      events,
      resources: [],
      relations: [],
      versions: [
        {
          id: "root",
          producer: "root",
          origin: "unknown",
          incarnation: "epoch",
          storage: null,
        },
        {
          id: "v",
          producer: "action",
          origin: "event",
          incarnation: "epoch",
          storage: null,
        },
      ],
    },
  };
  change(document);
  const recording = Buffer.from(JSON.stringify(document));
  const profile = Buffer.from(
    JSON.stringify({
      format: "spacetime-latency-profile",
      schema: 1,
      build,
      label: "fixture owner",
      recording: { bytes: recording.length, sha256: sha(recording) },
      evidence: [
        {
          description: "trusted fixture obligations",
          path: "/must-not-be-opened",
          sha256: "0".repeat(64),
        },
      ],
      groups: [
        { id: "action-group", trigger: "action", members: ["action", "valid"] },
      ],
      choices: [{ id: "all", label: "all actions", groups: ["action-group"] }],
      edges: [
        {
          source: "action",
          target: "done",
          minLag: 1,
          reason: "completion needs result",
        },
      ],
      unknowns: ["synthetic fixed-work model"],
    }),
  );
  return { recording, profile };
}

test("saved-step includes every anchored public output and compactly compares both policies", () => {
  const { recording, profile } = fixture(),
    before = [Buffer.from(recording), Buffer.from(profile)];
  const report = predictLatency(recording, profile, options);
  assert.deepEqual(report.selection.targets, ["early", "done"]);
  assert.deepEqual(report.selection.publicAnnotations, [
    "early-output",
    "completion",
  ]);
  assert.deepEqual(report.inputs.recording, {
    bytes: recording.length,
    sha256: sha(recording),
  });
  assert.equal(report.inputs.profile.sha256, sha(profile));
  assert.deepEqual(
    report.reports.map((r) => r.policy),
    ["absorb_gaps", "preserve_gaps"],
  );
  assert.deepEqual(
    report.reports.map((r) => r.result.candidate.elapsedCycles),
    [4, 5],
  );
  for (const { result, time } of report.reports) {
    assert.equal(result.status, "conditional");
    assert.equal(result.intervention.groups, 1);
    assert.equal(result.intervention.members, 2);
    assert.deepEqual(result.rootCoverage, { counts: { unknown: 1 } });
    assert.equal(result.constraints.sourceObligations, 1);
    assert.equal("events" in result, false);
    assert.equal("groupFor" in result, false);
    assert.equal(result.targets.length, 2);
    assert.equal(time.candidateElapsedNs, result.candidate.elapsedCycles * 5);
    assert.equal(time.baselineElapsedNs, 40);
  }
  assert.deepEqual([recording, profile], before);
});

test("explicit targets and one policy require no saved selection", () => {
  const f = fixture((document) => {
    delete document.selection;
  });
  const report = predictLatency(f.recording, f.profile, {
    ...options,
    savedStep: false,
    startCycle: 0,
    targets: ["done", "done"],
    policy: "preserve_gaps",
    extraLatency: 0,
  });
  assert.equal(report.reports.length, 1);
  assert.equal(report.reports[0].result.candidate.elapsedCycles, 4);
  assert.deepEqual(report.selection.targets, ["done"]);
});

test("saved completion must be reached by an accepted output anchor", () => {
  const f = fixture((document) => {
    document.annotations.public = document.annotations.public.filter(
      (a) => a.id !== "completion",
    );
  });
  assert.throws(
    () => predictLatency(f.recording, f.profile, options),
    /terminal public output anchor/,
  );
});

test("target-only group bindings survive compact output", () => {
  const f = fixture();
  const report = predictLatency(f.recording, f.profile, {
    ...options,
    savedStep: false,
    startCycle: 0,
    targets: ["action", "valid"],
    policy: "absorb_gaps",
  });
  assert.deepEqual(report.reports[0].result.targetAssociations, [
    { event: "action", scenarioNode: "scenario-group/action-group" },
    { event: "valid", scenarioNode: "scenario-group/action-group" },
  ]);
  assert.equal(report.reports[0].result.targets.length, 1);
});

test("byte binding rejects same-shaped modified recordings and bad selection", () => {
  const f = fixture();
  assert.throws(
    () =>
      predictLatency(
        Buffer.concat([f.recording, Buffer.from(" ")]),
        f.profile,
        options,
      ),
    /recording mismatch/,
  );
  for (const extra of [
    { savedStep: false },
    { startCycle: 0 },
    { policy: "guess" },
    { baselinePeriodNs: 0 },
    { extraLatency: -1 },
    { choice: "missing" },
    { savedStep: false, startCycle: 0, targets: ["missing"] },
  ])
    assert.throws(() =>
      predictLatency(f.recording, f.profile, { ...options, ...extra }),
    );
  const noAnchors = fixture((document) => {
    document.annotations.public = [];
  });
  assert.throws(
    () => predictLatency(noAnchors.recording, noAnchors.profile, options),
    /public output anchors/,
  );
  const oversized = Buffer.alloc(4 * 1024 * 1024 + 1, 32);
  assert.throws(
    () => predictLatency(f.recording, oversized, options),
    /profile exceeds byte bound/,
  );
});

test("last scalar options win and malformed command arguments reject", () => {
  assert.deepEqual(
    parseArguments([
      "--choice",
      "first",
      "--choice",
      "last",
      "--extra-latency",
      "1",
      "--extra-latency",
      "2",
      "--baseline-period",
      "8",
      "--baseline-period",
      "10",
      "--candidate-period",
      "5e0",
      "--start-cycle",
      "0",
      "--targets",
      "early",
      "--targets",
      "early,done",
      "--policy",
      "absorb_gaps",
      "--policy",
      "both",
    ]),
    {
      choice: "last",
      extraLatency: 2,
      baselinePeriodNs: 10,
      candidatePeriodNs: 5,
      startCycle: 0,
      targets: ["early", "done"],
      policy: "both",
    },
  );
  assert.deepEqual(parseArguments(["--saved-step", "--saved-step"]), {
    savedStep: true,
  });
  for (const args of [
    ["--bad", "x"],
    ["--choice"],
    ["--extra-latency", "1.2"],
    ["--start-cycle", "-1"],
    ["--candidate-period", "Infinity"],
    ["--targets", "a,,b"],
    ["--policy", "other"],
    ["--saved-step", "--targets", "done"],
  ])
    assert.throws(() => parseArguments(args));
});

test("fresh bounded output preserves inputs and refuses overwrite or oversized input", async () => {
  const dir = await mkdtemp(join(tmpdir(), "spacetime-predict-latency-"));
  try {
    const f = fixture(),
      recording = join(dir, "recording.json"),
      profile = join(dir, "profile.json"),
      output = join(dir, "prediction.json");
    await writeFile(recording, f.recording);
    await writeFile(profile, f.profile);
    const args = { ...options, recording, profile, output };
    const saved = await writePrediction(args),
      bytes = await readFile(output);
    assert.equal(saved.sha256, sha(bytes));
    assert.equal(saved.bytes, bytes.length);
    assert.equal(JSON.parse(bytes).reports.length, 2);
    await assert.rejects(writePrediction(args), /EEXIST/);
    assert.deepEqual(await readFile(recording), f.recording);
    assert.deepEqual(await readFile(profile), f.profile);
    const huge = join(dir, "huge.json");
    await writeFile(huge, "{}");
    await truncate(huge, 128 * 1024 * 1024 + 1);
    await assert.rejects(
      writePrediction({
        ...args,
        recording: huge,
        output: join(dir, "never.json"),
      }),
      /byte bound/,
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
