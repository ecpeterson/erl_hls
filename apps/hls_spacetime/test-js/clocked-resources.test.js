import assert from "node:assert/strict";
import test from "node:test";
import {
  publicationInitial,
  publicationView,
  publicationStep,
  captureInitial,
  captureStep,
  pairInitial,
  pairSelect,
  pairStep,
  inboxInitial,
  inboxEligible,
  inboxView,
  inboxStep,
} from "../web/clocked-resources.js";

/** Opaque values and explicit physical slot identities distinguish occurrences. */
const item = (id, recipient, slot = `link/${recipient}/slot/0`) => ({
  id,
  recipient,
  slot,
  payload: { value: id },
});
const batch = (id, deliveries) => ({ id, deliveries });

test("publication drains independently in source order and cannot refill on its last drain edge", () => {
  const initial = publicationInitial(2);
  const first = batch("first", [
    item("a", 0, "a-slot"),
    item("b", 1),
    item("c", 0, "c-slot"),
  ]);
  const admitted = publicationStep(initial, { batch: first });
  assert.equal(admitted.batchAccepted, true);
  assert.deepEqual(admitted.delivered, []);
  assert.deepEqual(
    publicationView(admitted.state, { freeSlots: new Set(["a-slot"]) })
      .acceptedRecipients,
    [0],
  );
  const second = publicationStep(admitted.state, { acceptedRecipients: [0] });
  assert.deepEqual(
    second.delivered.map(({ id }) => id),
    ["a"],
  );
  assert.deepEqual(
    publicationView(second.state).offers.map(({ id }) => id),
    ["c", "b"],
  );
  const next = batch("next", [item("d", 1)]);
  const drained = publicationStep(second.state, {
    acceptedRecipients: [0, 1],
    batch: next,
  });
  assert.equal(drained.batchAccepted, false);
  assert.equal(publicationView(drained.state).ready, true);
  assert.deepEqual(
    drained.delivered.map(({ id }) => id),
    ["c", "b"],
  );
  assert.equal(
    publicationStep(drained.state, { batch: next }).batchAccepted,
    true,
  );
  assert.deepEqual(initial, publicationInitial(2));
  assert.equal(first.deliveries.length, 3);
});

test("publication observes exact selected-slot credit rather than any free slot for a recipient", () => {
  const state = publicationStep(publicationInitial(1), {
    batch: batch("b", [item("oldest", 0, "full"), item("later", 0, "free")]),
  }).state;
  const view = publicationView(state, { freeSlots: new Set(["free"]) });
  assert.deepEqual(
    view.offers.map(({ id }) => id),
    ["oldest"],
  );
  assert.deepEqual(view.acceptedRecipients, []);
  assert.equal(view.ready, false);
  assert.deepEqual(publicationStep(state).state, state);
});

test("empty publication and reset preserve old-state admission semantics", () => {
  const empty = publicationStep(publicationInitial(3), {
    batch: batch("empty", []),
  });
  assert.equal(empty.batchAccepted, true);
  assert.deepEqual(empty.state, publicationInitial(3));
  const busy = publicationStep(empty.state, {
    batch: batch("b", [item("v", 2)]),
  }).state;
  const reset = publicationStep(busy, {
    reset: true,
    acceptedRecipients: [2],
    batch: batch("lost", [item("w", 0)]),
  });
  assert.deepEqual(reset, {
    state: publicationInitial(3),
    batchAccepted: false,
    delivered: [],
  });
});

test("capture retains its payload across take and release without same-edge reuse", () => {
  const value = { deliveryId: "x", payload: 12 };
  const full = captureStep(captureInitial(), { arrive: value });
  assert.equal(full.arrived, true);
  const leased = captureStep(full.state, { take: true });
  assert.equal(leased.state.owner, "leased");
  assert.deepEqual(leased.state.value, value);
  assert.throws(
    () =>
      captureStep(leased.state, { release: true, arrive: { deliveryId: "y" } }),
    /old free credit/,
  );
  const released = captureStep(leased.state, { release: true });
  assert.deepEqual(released.state, { owner: "free", value });
  assert.equal(
    captureStep(released.state, { arrive: { deliveryId: "y" } }).state.owner,
    "full",
  );
  assert.deepEqual(
    captureStep(leased.state, { reset: true, release: true }).state,
    captureInitial(),
  );
});

test("receiver take is registered before release, making slot reuse two edges later", () => {
  let inbox = inboxInitial(1);
  let capture = captureStep(captureInitial(), {
    arrive: { deliveryId: "old" },
  }).state;
  // Edge t: receipt acceptance and consume are coherent; release is still zero.
  const consumed = inboxStep(inbox, {
    heads: [0],
    accepted: true,
    headDone: true,
    dispatched: true,
  });
  assert.deepEqual(consumed.output.take, [0]);
  assert.deepEqual(consumed.output.release, []);
  capture = captureStep(capture, {
    take: true,
    release: consumed.output.release.includes(0),
  }).state;
  inbox = consumed.state;
  assert.equal(capture.owner, "leased");
  // Edge t+1: old registered release retires the lease but supplies no old credit.
  const next = inboxStep(inbox);
  assert.deepEqual(next.output.release, [0]);
  assert.throws(
    () =>
      captureStep(capture, { release: true, arrive: { deliveryId: "new" } }),
    /old free credit/,
  );
  capture = captureStep(capture, {
    release: next.output.release.includes(0),
  }).state;
  // Edge t+2: the next arrival may consume the now-old free credit.
  assert.equal(
    captureStep(capture, { arrive: { deliveryId: "new" } }).state.owner,
    "full",
  );
  assert.deepEqual(inboxStep(next.state).output.release, []);
});

test("pair selection bypasses postponed elders and places arrivals after surviving messages", () => {
  let state = pairInitial(4);
  state = pairStep(state, { arrive: 2 });
  state = pairStep(state, { arrive: 0 });
  assert.equal(pairSelect(state, [0, 2]), 2);
  assert.equal(pairSelect(state, [0]), 0);
  assert.equal(pairSelect(state, [1, 3]), null);
  const next = pairStep(state, { take: 0, arrive: 3 });
  assert.deepEqual(next.pending, [2, 3]);
  assert.equal(pairSelect(next, [2, 3]), 2);
  assert.throws(
    () => pairStep(state, { take: 2, arrive: 2 }),
    /old pending slot/,
  );
  assert.deepEqual(state.pending, [2, 0]);
  assert.deepEqual(pairStep(next, { reset: true }), pairInitial(4));
});

test("inbox cursor advances on acceptance and held ownership survives busy entry retries", () => {
  const initial = { ...inboxInitial(4), cursor: 2 };
  const unaccepted = inboxStep(initial, { heads: [0, 3] });
  assert.equal(unaccepted.state.cursor, 2);
  assert.equal(inboxView(initial, { heads: [0, 3] }).pick, 3);
  const accepted = inboxStep(initial, { heads: [0, 3], accepted: true });
  assert.equal(accepted.state.cursor, 0);
  assert.equal(accepted.state.held, 3);
  assert.deepEqual(
    inboxEligible(accepted.state, { ownerBusy: true, internalPending: true }),
    [3],
  );
  assert.equal(
    inboxView(accepted.state, { heads: [0, 3], ownerBusy: true }).offered,
    false,
  );
  const held = inboxStep(accepted.state, { heads: [0, 3], ownerBusy: true });
  assert.deepEqual(held.state, accepted.state);
  const committed = inboxStep(held.state, {
    heads: [3],
    ownerBusy: true,
    headDone: true,
    dispatched: true,
  });
  assert.equal(committed.state.held, null);
  assert.equal(committed.state.cursor, 0);
  assert.deepEqual(committed.output.take, [3]);
});

test("postponement preserves capture ownership; phase boundaries wake even same-edge postponement", () => {
  const first = inboxStep(inboxInitial(3), {
    heads: [0, 1],
    accepted: true,
    headDone: true,
    dispatched: true,
    directive: 1,
  });
  assert.deepEqual(first.output.take, []);
  assert.deepEqual(first.output.postpone, [0]);
  assert.deepEqual(first.state.released, []);
  assert.deepEqual(inboxEligible(first.state), [1, 2]);
  const second = inboxStep(first.state, {
    heads: [0, 1],
    accepted: true,
    headDone: true,
    dispatched: true,
    directive: 1,
    phaseBoundary: true,
  });
  assert.deepEqual(second.output.eligible, [1, 2]);
  assert.deepEqual(second.output.postpone, [1]);
  assert.deepEqual(second.state.postponed, []);
  assert.deepEqual(inboxEligible(second.state), [0, 1, 2]);
});

test("owner availability masks new offers while reset cancels reservations and pending release", () => {
  const state = inboxInitial(2);
  for (const controls of [
    { enabled: false },
    { ownerBusy: true },
    { internalPending: true },
    { failed: true },
  ]) {
    assert.deepEqual(inboxEligible(state, controls), []);
    assert.equal(inboxView(state, { heads: [0], ...controls }).offered, false);
  }
  const held = inboxStep(state, { heads: [1], accepted: true }).state;
  assert.deepEqual(inboxEligible(held, { enabled: false }), []);
  assert.deepEqual(inboxStep(held, { reset: true }), {
    state: inboxInitial(2),
    output: { eligible: [], accepted: [], take: [], postpone: [], release: [] },
  });
});

test("malformed state and impossible accepted handshakes reject", () => {
  assert.throws(() => publicationInitial(0), /positive/);
  assert.throws(
    () => publicationStep(publicationInitial(1), { acceptedRecipients: [0] }),
    /no old publication/,
  );
  assert.throws(
    () =>
      publicationStep(publicationInitial(1), {
        batch: batch("b", [item("same", 0), item("same", 0)]),
      }),
    /Duplicate/,
  );
  assert.throws(
    () =>
      publicationView({ recipientCount: 1, batchId: "orphan", queues: [[]] }),
    /occupancy/,
  );
  assert.throws(
    () => captureStep(captureInitial(), { take: true }),
    /old full/,
  );
  assert.throws(
    () => captureStep({ owner: "leased", value: null }),
    /no value/,
  );
  assert.throws(
    () => pairSelect({ slotCount: 2, pending: [0, 0] }, [0]),
    /duplicate/,
  );
  assert.throws(
    () => inboxStep(inboxInitial(2), { accepted: true }),
    /no offered/,
  );
  assert.throws(
    () => inboxStep(inboxInitial(2), { heads: [0], headDone: true }),
    /no reservation/,
  );
  assert.throws(
    () => inboxStep(inboxInitial(2), { dispatched: true }),
    /coherent/,
  );
  assert.throws(
    () => inboxView({ ...inboxInitial(2), cursor: 2 }),
    /Invalid inbox/,
  );
});
