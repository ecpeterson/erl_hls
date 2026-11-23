import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { controlReplay } from "../web/control-replay.js";

/** Small independent workload; its expected clocks below are manually enumerated. */
const fixture = () =>
  JSON.parse(
    readFileSync(
      new URL("./fixtures/control-profile.json", import.meta.url),
      "utf8",
    ),
  );
const cycleOf = (result, kind, id) =>
  result.events.find((event) => event.kind === kind && event.id === id)?.cycle;

test("two-actor replay honors every register boundary and the gateway's polling phase", () => {
  const profile = fixture();
  const before = structuredClone(profile);
  const result = controlReplay(profile);
  assert.equal(result.status, "conditional");
  assert.deepEqual(result.completion, { cycle: 11, elapsedCycles: 11 });
  // A computes C1, commits C2, publishes C3, and B captures C4.
  assert.equal(cycleOf(result, "private", "make"), 1);
  assert.equal(cycleOf(result, "commit", "make"), 2);
  assert.equal(cycleOf(result, "publication", "a-batch"), 3);
  assert.equal(cycleOf(result, "arrival", "message"), 4);
  // B consumes C5, releases C6, computes C6, commits C7, publishes C8.
  assert.equal(cycleOf(result, "receipt", "receive"), 5);
  assert.equal(cycleOf(result, "private", "respond"), 6);
  assert.equal(cycleOf(result, "commit", "respond"), 7);
  assert.equal(cycleOf(result, "publication", "b-batch"), 8);
  assert.deepEqual(
    result.controls.find((row) => row.actor === "b" && row.cycle === 5).take,
    [0],
  );
  assert.deepEqual(
    result.controls.find((row) => row.actor === "b" && row.cycle === 6).release,
    [0],
  );
  // C9 captures the frame; words become available only in C10 and C11.
  assert.equal(cycleOf(result, "frame_transfer", "done"), 9);
  assert.deepEqual(
    result.words.map(({ cycle, data }) => [cycle, data]),
    [
      [10, 17],
      [11, 0],
    ],
  );
  assert.deepEqual(profile, before);
});

test("one extra arithmetic edge can cost two clocks through unchanged round-robin polling", () => {
  const result = controlReplay(fixture(), { extraLatency: 1, actors: ["a"] });
  assert.equal(result.status, "conditional");
  assert.equal(cycleOf(result, "private", "make"), 2);
  assert.equal(cycleOf(result, "arrival", "message"), 5);
  assert.equal(cycleOf(result, "receipt", "receive"), 6);
  assert.equal(cycleOf(result, "publication", "b-batch"), 9);
  // The frame is ready C10, when the transmitter polls management. Event polling
  // returns C11, then the two words transfer C12/C13. No saved event clocks exist.
  assert.equal(cycleOf(result, "frame_transfer", "done"), 11);
  assert.deepEqual(
    result.words.map(({ cycle }) => cycle),
    [12, 13],
  );
  assert.deepEqual(result.completion, { cycle: 13, elapsedCycles: 13 });
});

test("absolute output-ready windows alter added latency without a fitted gap rule", () => {
  const profile = fixture();
  profile.host.outputReady = { period: 3, residues: [0, 1] };
  const baseline = controlReplay(profile);
  const delayed = controlReplay(profile, { extraLatency: 1, actors: ["a"] });
  // Baseline's second word stalls C11; the delayed frame hits ready C12/C13.
  assert.deepEqual(
    baseline.words.map(({ cycle }) => cycle),
    [10, 12],
  );
  assert.deepEqual(
    delayed.words.map(({ cycle }) => cycle),
    [12, 13],
  );
  assert.equal(delayed.completion.cycle - baseline.completion.cycle, 1);
});

test("causal host response is released after accepted output and reaches actor one edge later", () => {
  const profile = fixture();
  const actor = profile.actors[0];
  actor.slots = [{ kind: "host" }];
  actor.operations.push(
    {
      id: "ack",
      kind: "receipt",
      accepted: true,
      input: { slot: 0, id: "reply" },
      nextPending: true,
      dispatched: true,
      directive: 0,
      phaseBoundary: false,
      batch: null,
    },
    {
      id: "finish",
      kind: "action",
      accepted: false,
      nextPending: false,
      dispatched: true,
      directive: 0,
      phaseBoundary: true,
      batch: {
        id: "final-batch",
        deliveries: [
          {
            id: "final-delivery",
            recipient: 1,
            slot: "endpoint/public",
            payload: null,
            kind: "boundary",
            endpoint: "public",
            frame: "after",
          },
        ],
      },
    },
  );
  profile.publishers[0].state = {
    recipientCount: 2,
    batchId: null,
    queues: [[], []],
  };
  profile.endpoints[0].producers = ["a", "b"];
  profile.host.commands = [
    {
      id: "reply",
      words: [7],
      floors: [1],
      causes: ["done"],
      responseGap: 2,
      recipients: ["a"],
    },
  ];
  profile.host.frames.push({ id: "after", words: [18, 0] });
  profile.targets = ["after"];
  const result = controlReplay(profile);
  assert.equal(result.status, "conditional");
  assert.equal(cycleOf(result, "public", "done"), 11);
  assert.deepEqual(
    result.inputWords.map(({ command, cycle }) => [command, cycle]),
    [["reply", 13]],
  );
  assert.equal(cycleOf(result, "receipt", "ack"), 14);
  assert.equal(cycleOf(result, "private", "finish"), 15);
  assert.equal(cycleOf(result, "commit", "finish"), 16);
  assert.equal(cycleOf(result, "publication", "final-batch"), 17);
  assert.equal(cycleOf(result, "frame_transfer", "after"), 19);
  assert.equal(result.completion.cycle, 21);
});

test("changed offered identity rejects instead of waiting for the recorded head", () => {
  const profile = fixture();
  profile.actors[1].operations[0].input.id = "another-message";
  const result = controlReplay(profile);
  assert.equal(result.status, "invalid");
  assert.equal(result.lastCycle, 5);
  assert.equal(result.reason.kind, "work_order_changed");
  assert.equal(result.reason.actual.id, "message");
  assert.equal(result.completion, null);
});

test("reset and finite work tail censor without inventing completion", () => {
  const reset = fixture();
  reset.resetCycles = [4];
  assert.equal(controlReplay(reset).reason, "reset_boundary");
  const tail = fixture();
  tail.actors[1].operations = [];
  const result = controlReplay(tail);
  assert.equal(result.status, "censored");
  assert.equal(result.reason.kind, "recorded_work_tail");
  assert.equal(result.lastCycle, 5);
  assert.equal(result.completion, null);
});

// One sender/recipient pair has one source offer and one consumer per edge.
// Different physical slots do not make simultaneous pair transfers legal.
test("multiple independent recipient offers cannot silently arrive in one sender pair", () => {
  const profile = fixture();
  profile.links[0].slots.push({ owner: "free", value: null });
  profile.links[0].order.slotCount = 2;
  profile.publishers[0].state = {
    recipientCount: 2,
    batchId: null,
    queues: [[], []],
  };
  profile.actors[0].operations[0].batch.deliveries.push({
    id: "second",
    recipient: 1,
    slot: "link/pair/slot/1",
    payload: null,
    kind: "capture",
    link: "pair",
    captureSlot: 1,
  });
  assert.throws(
    () => controlReplay(profile),
    /Multiple arrivals in sender pair pair/,
  );
});

test("one sender pair cannot be retired by two separately mapped consumers", () => {
  const profile = fixture();
  profile.links[0].slots = [
    { owner: "full", value: { id: "first" } },
    { owner: "full", value: { id: "second" } },
  ];
  profile.links[0].order = { slotCount: 2, pending: [0, 1] };
  profile.actors.forEach((actor, index) => {
    actor.initial.owner = { pending: false };
    actor.slots = [{ kind: "capture", link: "pair", slot: index }];
    actor.operations = [
      {
        id: `receipt-${index}`,
        kind: "receipt",
        accepted: true,
        input: { slot: 0, id: index === 0 ? "first" : "second" },
        nextPending: false,
        dispatched: true,
        directive: 0,
        phaseBoundary: false,
        batch: null,
      },
    ];
  });
  assert.throws(
    () => controlReplay(profile),
    /Multiple takes in sender pair pair/,
  );
});

test("unsupported active transmitter checkpoints reject instead of losing retained words", () => {
  for (const initial of [
    { frame: { id: "done", words: [17, 0] } },
    { source: 0 },
    { index: 1 },
  ]) {
    const profile = fixture();
    Object.assign(profile.host.initial.transmitter, initial);
    assert.throws(() => controlReplay(profile), /idle transmitter checkpoint/);
  }
  const idle = fixture();
  Object.assign(idle.host.initial.transmitter, {
    frame: null,
    source: null,
    index: 0,
  });
  assert.equal(controlReplay(idle).completion.cycle, 11);
});

test("checkpoint completion facts require known frames strictly in the established prefix", () => {
  for (const cycle of [1, 2, -1, 0.5]) {
    const profile = fixture();
    profile.host.frames.push({ id: "prefix", words: [19, 0] });
    profile.host.initial.completed.prefix = cycle;
    assert.throws(() => controlReplay(profile), /before the checkpoint/);
  }
  const missing = fixture();
  missing.host.initial.completed.unlisted = 0;
  assert.throws(() => controlReplay(missing), /known frame/);
  const prefix = fixture();
  prefix.host.frames.push({ id: "prefix", words: [19, 0] });
  prefix.host.initial.completed.prefix = 0;
  assert.equal(controlReplay(prefix).completion.cycle, 11);
});

test("undeclared failure domain and unknown interventions cannot silently produce a score", () => {
  const missing = fixture();
  delete missing.failureFree;
  assert.throws(() => controlReplay(missing), /failure-free/);
  assert.throws(
    () => controlReplay({ ...fixture(), failureFree: false }),
    /failure-free/,
  );
  assert.throws(
    () => controlReplay(fixture(), { actors: ["absent"], extraLatency: 1 }),
    /identities/,
  );
});
