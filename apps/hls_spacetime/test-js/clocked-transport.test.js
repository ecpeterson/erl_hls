import assert from "node:assert/strict";
import test from "node:test";
import {
  transmitterInitial,
  transmitterView,
  transmitterStep,
  egressInitial,
  egressView,
  egressStep,
} from "../web/clocked-transport.js";

const packet = (id, tag = 0x11, payload = [4, 0, 0]) => ({
  id,
  words: [0x00090001, ((tag << 24) >>> 0) + payload.length, ...payload],
});

/** One explicit edge, always providing the complete table including management. */
function tx(state, frames, outputReady = true, extra = {}) {
  return transmitterStep(state, { frames, outputReady, ...extra });
}

/** A source-ready arrival is held until accepted. No saved output clocks enter
 * this miniature simulator: the polling state and absolute ready rule set them.
 */
function delayedFrame(available) {
  let state = transmitterInitial(2, { started: true, cursor: 2 });
  const frame = packet("correction", 0x0b, [4, 0, 2]);
  let pending = true;
  const accepted = [],
    words = [],
    views = [];
  for (let cycle = 1775; cycle < 1880; cycle++) {
    const view = transmitterView(state);
    if (view.valid) views.push(cycle);
    const result = tx(
      state,
      [null, pending && cycle >= available ? frame : null, null],
      cycle % 19 >= 7,
    );
    if (result.acceptedSource !== null) {
      accepted.push(cycle);
      pending = false;
    }
    if (result.acceptedWord) words.push(cycle);
    state = result.state;
    if (!pending && words.length === frame.words.length) break;
  }
  return { accepted, words, views };
}

test("a ten-clock frame delay misses the polling phase and delays first word twelve", () => {
  const baseline = delayedFrame(1840),
    variant = delayedFrame(1850);
  assert.deepEqual(baseline.accepted, [1840]);
  assert.deepEqual(variant.accepted, [1852]);
  assert.equal(variant.views[0] - baseline.views[0], 12);
  assert.deepEqual(baseline.words, [1841, 1842, 1850, 1851, 1852]);
  assert.deepEqual(variant.words, [1853, 1854, 1855, 1856, 1857]);
});

test("an empty poll advances one source even when the public output is stalled", () => {
  const input = transmitterInitial(2, { started: true });
  const waiting = packet("event-one");
  const first = tx(input, [null, waiting, null], false);
  assert.equal(first.acceptedSource, null);
  assert.equal(first.state.cursor, 1);
  const second = tx(first.state, [null, waiting, null], false);
  assert.equal(second.acceptedSource, 1);
  assert.equal(second.acceptedWord, null);
  assert.equal(transmitterView(first.state).valid, false);
  assert.equal(transmitterView(second.state).data, waiting.words[0]);
  assert.deepEqual(input, transmitterInitial(2, { started: true }));
});

test("packet words and cursor hold through backpressure without accepting another frame", () => {
  const input = packet("a");
  let state = tx(transmitterInitial(1, { started: true }), [input, null]).state;
  input.words[0] = 0; // accepted frame has independent held storage
  const original = structuredClone(state);
  for (let i = 0; i < 3; i++) {
    const result = tx(state, [packet("later"), null], false);
    assert.equal(result.acceptedSource, null);
    assert.equal(result.acceptedWord, null);
    assert.deepEqual(result.state, original);
    assert.equal(transmitterView(result.state).data, 0x00090001);
    state = result.state;
  }
  const result = tx(state, [packet("later"), null]);
  assert.equal(result.acceptedWord.index, 0);
  assert.equal(result.state.index, 1);
  assert.equal(result.state.cursor, state.cursor);
});

test("the final accepted word and the next frame poll occupy separate clocks", () => {
  let state = tx(transmitterInitial(1, { started: true }), [
    packet("a", 0x11, []),
    null,
  ]).state;
  state = tx(state, [packet("b"), null]).state;
  const last = tx(state, [packet("b"), null]);
  assert.equal(last.acceptedWord.last, true);
  assert.equal(last.acceptedSource, null);
  assert.equal(transmitterView(last.state).valid, false);
  const management = tx(last.state, [packet("b"), null]);
  assert.equal(management.acceptedSource, null);
  const capture = tx(management.state, [packet("b"), null]);
  assert.equal(capture.acceptedSource, 0);
  assert.equal(capture.acceptedWord, null);
});

test("ordinary streams remain disabled until the attachment ack final beat is accepted", () => {
  const event = packet("event"),
    ack = packet("ack", 0x81, [1]);
  let state = transmitterInitial(2);
  state = tx(state, [event, event, null]).state;
  assert.equal(state.started, false);
  const poll = tx(state, [event, event, ack]);
  assert.equal(poll.acceptedSource, 2);
  state = poll.state;
  for (let i = 0; i < ack.words.length - 1; i++) {
    state = tx(state, [event, event, null]).state;
    assert.equal(state.started, false);
  }
  state = tx(state, [event, event, null], false).state;
  assert.equal(state.started, false);
  state = tx(state, [event, event, null]).state;
  assert.equal(state.started, true);
});

test("management fault disables future events; unrelated management replies do not", () => {
  for (const [tag, expected] of [
    [0xff, false],
    [0x83, true],
  ]) {
    let state = transmitterInitial(1, { started: true, cursor: 1 });
    const frame = packet(`management-${tag}`, tag, []);
    state = tx(state, [null, frame]).state;
    for (const _word of frame.words) state = tx(state, [null, null]).state;
    assert.equal(state.started, expected);
  }
});

test("explicit admission gating never pretends an acknowledgment occurred", () => {
  const event = packet("event");
  const unattached = tx(transmitterInitial(1), [event, null], true, {
    attached: true,
  });
  assert.equal(unattached.acceptedSource, null);
  const disabled = tx(
    transmitterInitial(1, { started: true }),
    [event, null],
    true,
    { attached: false },
  );
  assert.equal(disabled.acceptedSource, null);
  assert.equal(disabled.state.started, true);
  assert.equal(disabled.state.cursor, 1);
});

test("reset cancels a packet without an accepted word and clears attachment", () => {
  let state = tx(transmitterInitial(1, { started: true }), [
    packet("a"),
    null,
  ]).state;
  const reset = tx(state, [null, null], true, { reset: true });
  assert.deepEqual(reset.state, transmitterInitial(1));
  assert.equal(reset.acceptedSource, null);
  assert.equal(reset.acceptedWord, null);
});

test("held egress grants cannot be displaced by a newly arrived higher-priority producer", () => {
  const a = packet("a"),
    b = packet("b");
  const initial = egressInitial(2);
  const held = egressStep(initial, { frames: [null, b], outputReady: false });
  assert.equal(held.selectedSource, 1);
  assert.equal(held.acceptedSource, null);
  assert.equal(held.state.cursor, 0);
  assert.equal(egressView(held.state, [a, b]).source, 1);
  const accepted = egressStep(held.state, {
    frames: [a, b],
    outputReady: true,
  });
  assert.equal(accepted.acceptedSource, 1);
  assert.equal(accepted.state.cursor, 0);
  assert.equal(egressView(accepted.state, [a, null]).source, 0);
  assert.deepEqual(initial, egressInitial(2));
});

test("egress wraps round robin only after accepted transfers", () => {
  const frames = [packet("a"), packet("b"), packet("c")];
  let state = egressInitial(3, { cursor: 2 });
  const order = [];
  for (let i = 0; i < 6; i++) {
    const next = egressStep(state, { frames, outputReady: true });
    order.push(next.acceptedSource);
    state = next.state;
  }
  assert.deepEqual(order, [2, 0, 1, 2, 0, 1]);
});

test("egress rejects withdrawn or changed held offers and reset retires the lock", () => {
  const frame = packet("a");
  const state = egressStep(egressInitial(2), {
    frames: [frame, null],
    outputReady: false,
  }).state;
  assert.throws(() => egressView(state, [null, null]), /held producer/);
  assert.throws(
    () => egressView(state, [packet("different"), null]),
    /held producer/,
  );
  assert.throws(
    () => egressView(state, [packet("a", 0x11, [5, 0, 0]), null]),
    /held producer/,
  );
  const reset = egressStep(state, {
    frames: [null, null],
    outputReady: true,
    reset: true,
  });
  assert.deepEqual(reset.state, egressInitial(2));
  assert.equal(reset.acceptedSource, null);
});

test("a held endpoint selection composes with one-stream polling without a hidden frame buffer", () => {
  const a = packet("a"),
    b = packet("b");
  let arbiter = egressInitial(2),
    transmitter = transmitterInitial(2, { started: true });
  const firstView = egressView(arbiter, [null, b]);
  let send = tx(transmitter, [null, firstView.frame, null]);
  arbiter = egressStep(arbiter, {
    frames: [null, b],
    outputReady: send.acceptedSource === 1,
  }).state;
  transmitter = send.state;
  assert.equal(transmitterView(transmitter).valid, false);
  const secondView = egressView(arbiter, [a, b]);
  send = tx(transmitter, [null, secondView.frame, null]);
  const retire = egressStep(arbiter, {
    frames: [a, b],
    outputReady: send.acceptedSource === 1,
  });
  assert.equal(retire.acceptedSource, 1);
  assert.equal(transmitterView(send.state).id, "b");
});

test("malformed frames, missing table entries and invalid cursors reject", () => {
  assert.throws(() => transmitterInitial(-1), /stream count/);
  assert.throws(() => transmitterInitial(2, { cursor: 3 }), /cursor/);
  assert.throws(() => egressInitial(0), /producer count/);
  assert.throws(() => tx(transmitterInitial(1), [undefined, null]), /frame/);
  assert.throws(() => tx(transmitterInitial(1), [null]), /table size/);
  assert.throws(
    () => tx(transmitterInitial(1), [{ id: "bad", words: [0, 3] }, null]),
    /frame/,
  );
  assert.throws(
    () => tx(transmitterInitial(1), [packet("a"), null], 1),
    /control/,
  );
});
