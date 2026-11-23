import assert from "node:assert/strict";
import test from "node:test";
import { hostInitial, hostView, hostStep } from "../web/clocked-host.js";

const command = (id, overrides = {}) => ({
  id,
  words: [10, 20, 30],
  floors: [10, 11, 12],
  causes: [],
  responseGap: 0,
  recipients: [0],
  ...overrides,
});

/** Run the explicit host policy one clock at a time, independent of device work. */
function run(
  commands,
  completed,
  { start = 0, end = 100, ready = () => true } = {},
) {
  let state = hostInitial(commands);
  const accepted = [];
  for (let cycle = start; cycle < end && !state.complete; cycle++) {
    const result = hostStep(state, { cycle, ready: ready(cycle), completed });
    if (result.acceptedWord) accepted.push(result.acceptedWord);
    state = result.state;
  }
  return { state, accepted };
}

test("source-linked correction waits for its completion plus preserved response gap", () => {
  // Baseline host/5 policy: seven words, original offered floors, gap two.
  // The completion is a supplied causal observation, not a target input cycle.
  const feedback = command("host/5", {
    words: [65543, 33554437, 1, 1, 0, 268435457, 1],
    floors: [1854, 1855, 1856, 1857, 1858, 1859, 1860],
    causes: ["correction"],
    responseGap: 2,
    recipients: [1],
  });
  const early = run(
    [feedback],
    { correction: 1852 },
    { start: 1840, end: 1900 },
  );
  const late = run(
    [feedback],
    { correction: 1857 },
    { start: 1840, end: 1900 },
  );
  assert.deepEqual(
    early.accepted.map((word) => word.cycle),
    [1854, 1855, 1856, 1857, 1858, 1859, 1860],
  );
  assert.deepEqual(
    late.accepted.map((word) => word.cycle),
    [1859, 1860, 1861, 1862, 1863, 1864, 1865],
  );
  assert.equal(late.state.complete, true);
  assert.ok(late.accepted.every((word) => word.releaseCycle === 1859));
  assert.deepEqual(late.accepted.at(-1).recipients, [1]);
});

test("all causes must complete and the latest controls a shared response", () => {
  let state = hostInitial([
    command("readout", { causes: ["left", "right"], responseGap: 2 }),
  ]);
  assert.equal(hostView(state, 30, { left: 11 }).valid, false);
  state = hostStep(state, {
    cycle: 30,
    ready: true,
    completed: { left: 11 },
  }).state;
  assert.equal(hostView(state, 31, { right: 30 }).valid, false);
  const view = hostView(state, 32, { right: 30 });
  assert.equal(view.valid, true);
  assert.equal(view.releaseCycle, 32);
});

test("missing or future-dated completion cannot be replaced by a zero-latency cause", () => {
  const state = hostInitial([
    command("feedback", { causes: ["future"], responseGap: 2 }),
  ]);
  assert.equal(hostView(state, 100).valid, false);
  assert.equal(hostView(state, 100, { future: 101 }).releaseCycle, null);
  assert.equal(hostView(state, 102, { future: 101 }).valid, false);
  assert.equal(hostView(state, 103, { future: 101 }).valid, true);
});

test("per-word exogenous floors stay absolute rather than shifting with command start", () => {
  const policy = command("sparse", {
    floors: [10, 40, 41],
    causes: ["done"],
    responseGap: 2,
  });
  const result = run([policy], { done: 18 });
  assert.deepEqual(
    result.accepted.map((word) => word.cycle),
    [20, 40, 41],
  );
  const exogenous = run(
    [
      command("later", {
        floors: [40, 41, 42],
        causes: ["done"],
        responseGap: 2,
      }),
    ],
    { done: 18 },
  );
  assert.equal(exogenous.accepted[0].cycle, 40);
});

test("a held offer stays valid and retains copied words while ready is false", () => {
  const input = command("held");
  let state = hostInitial([input]);
  state = hostStep(state, { cycle: 10, ready: false }).state;
  input.words[0] = 99;
  input.floors[0] = 1000;
  for (let cycle = 11; cycle <= 13; cycle++) {
    const view = hostView(state, cycle);
    assert.equal(view.word, 10);
    assert.equal(view.valid, true);
    assert.equal(view.index, 0);
    const result = hostStep(state, { cycle, ready: false });
    assert.equal(result.acceptedWord, null);
    state = result.state;
  }
  const result = hostStep(state, { cycle: 14, ready: true });
  assert.equal(result.acceptedWord.word, 10);
  assert.equal(hostView(result.state, 15).word, 20);
});

test("command order and one accepted word per edge survive earlier later-command floors", () => {
  const result = run([
    command("first", { floors: [20, 20, 20] }),
    command("second", { floors: [0, 0, 0] }),
  ]);
  assert.deepEqual(
    result.accepted.map(({ command, cycle }) => [command, cycle]),
    [
      ["first", 20],
      ["first", 21],
      ["first", 22],
      ["second", 23],
      ["second", 24],
      ["second", 25],
    ],
  );
  assert.equal(result.accepted.filter((word) => word.last).length, 2);
});

test("completion facts persist across delta ledgers and contradictory rewrites reject", () => {
  let state = hostInitial(
    [command("causal", { causes: ["a", "b"], responseGap: 2 })],
    { a: 5 },
  );
  state = hostStep(state, { cycle: 8, ready: true, completed: { b: 7 } }).state;
  assert.equal(hostView(state, 10).valid, true);
  assert.throws(() => hostView(state, 10, { a: 9 }), /changed completion/);
  assert.equal(state.completed.a, 5);
  assert.equal(state.completed.b, 7);
});

test("initial reset suppresses acceptance and does not silently replay accepted work", () => {
  let state = hostInitial([command("setup", { floors: [0, 0, 0] })]);
  for (let cycle = 0; cycle < 8; cycle++) {
    const result = hostStep(state, { cycle, ready: true, reset: true });
    assert.equal(result.acceptedWord, null);
    assert.equal(result.state.acceptedWords, 0);
    state = result.state;
  }
  const accepted = hostStep(state, { cycle: 8, ready: true });
  assert.equal(accepted.acceptedWord.index, 0);
  assert.throws(
    () => hostStep(accepted.state, { cycle: 9, ready: true, reset: true }),
    /new host workload/,
  );
});

test("finite host completion is explicit, including the empty workload", () => {
  const empty = hostInitial([]);
  assert.equal(empty.complete, true);
  assert.equal(hostView(empty, 0).valid, false);
  const result = run([command("one", { words: [42], floors: [0] })]);
  assert.equal(result.state.complete, true);
  assert.equal(hostView(result.state, 1).complete, true);
  assert.equal(
    hostStep(result.state, { cycle: 1, ready: true }).acceptedWord,
    null,
  );
});

test("views and steps are pure and a cycle cannot retire multiple words", () => {
  const state = hostInitial([command("pure")]);
  const before = structuredClone(state);
  hostView(state, 10);
  const stepped = hostStep(state, { cycle: 10, ready: true });
  assert.deepEqual(state, before);
  assert.throws(
    () => hostStep(stepped.state, { cycle: 10, ready: true }),
    /previous step/,
  );
  assert.throws(() => hostView(stepped.state, 9), /previous step/);
});

test("malformed policy or unsafe completion arithmetic rejects explicitly", () => {
  assert.throws(() => hostInitial([command("a"), command("a")]), /duplicate/);
  for (const invalid of [
    { words: [] },
    { words: [-1] },
    { floors: [0] },
    { causes: ["a", "a"] },
    { responseGap: -1 },
    { recipients: null },
  ]) {
    assert.throws(() => hostInitial([command("a", invalid)]), /Clocked host/);
  }
  assert.throws(() => hostInitial([], { a: NaN }), /completion/);
  assert.throws(() => hostInitial([], new Map()), /completion/);
  const state = hostInitial([
    command("overflow", { causes: ["a"], responseGap: 1 }),
  ]);
  assert.throws(
    () =>
      hostView(state, Number.MAX_SAFE_INTEGER, { a: Number.MAX_SAFE_INTEGER }),
    /safe clock/,
  );
  assert.throws(() => hostStep(state, { cycle: 0, ready: 1 }), /nonboolean/);
});
