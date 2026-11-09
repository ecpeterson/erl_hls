import test from "node:test";
import assert from "node:assert/strict";
import { ownerInitial, ownerView, ownerStep } from "../web/clocked-owner.js";
const action = {
  id: "a",
  kind: "action",
  accepted: false,
  nextPending: false,
  batch: { id: "batch" },
};

test("numerical extra edge delays private result and its separate commit", () => {
  let s = ownerInitial({ pending: true });
  let r = ownerStep(s, { cycle: 0, operation: action, extraLatency: 1 });
  assert.deepEqual(
    r.events.map((x) => x.kind),
    ["launch"],
  );
  assert.equal(ownerView(r.state).inputReady, false);
  r = ownerStep(r.state, { cycle: 1 });
  assert.deepEqual(
    r.events.map((x) => x.kind),
    ["private"],
  );
  r = ownerStep(r.state, { cycle: 2 });
  assert.deepEqual(
    r.events.map((x) => x.kind),
    ["commit"],
  );
  assert.equal(r.state.outbox.id, "batch");
  assert.equal(ownerView(r.state).inputReady, true);
});
test("old outbox cannot be reused on its publication edge", () => {
  let r = ownerStep(ownerInitial({ pending: true, outbox: { id: "old" } }), {
    cycle: 0,
    operation: action,
  });
  r = ownerStep(r.state, { cycle: 1, batchReady: true });
  assert.deepEqual(
    r.events.map((x) => x.kind),
    ["publication"],
  );
  assert.ok(r.state.action);
  r = ownerStep(r.state, { cycle: 2 });
  assert.equal(r.completed.id, "a");
});
test("receipt and effectless commit can coexist with old outbox drain", () => {
  const s = ownerInitial({ outbox: { id: "old" } });
  const receipt = {
    id: "r",
    kind: "receipt",
    accepted: true,
    nextPending: true,
    batch: null,
  };
  let r = ownerStep(s, { cycle: 1, operation: receipt, batchReady: true });
  assert.deepEqual(
    r.events.map((x) => x.kind),
    ["publication", "launch", "receipt"],
  );
  r = ownerStep(r.state, { cycle: 2, operation: { ...action, batch: null } });
  r = ownerStep({ ...r.state, outbox: { id: "occupied" } }, { cycle: 3 });
  assert.equal(r.completed.id, "a");
  assert.equal(r.state.outbox.id, "occupied");
});
test("reset cancels private work and outstanding output", () => {
  const s = ownerInitial({
    pending: true,
    outbox: { id: "old" },
    action: { operation: action, privateCycle: 4 },
  });
  assert.deepEqual(
    ownerStep(s, { cycle: 2, reset: true }).state,
    ownerInitial(),
  );
});
test("owner rejects overlap and unsupported pending interpretation", () => {
  const s = ownerStep(ownerInitial({ pending: true }), {
    cycle: 1,
    operation: action,
  }).state;
  assert.throws(
    () => ownerStep(s, { cycle: 2, operation: action }),
    /occupied/,
  );
  assert.throws(
    () =>
      ownerStep(ownerInitial({ pending: null }), {
        cycle: 1,
        operation: action,
      }),
    /Unresolved/,
  );
  assert.throws(
    () => ownerStep(ownerInitial(), { cycle: 1, operation: action }),
    /readiness/,
  );
});
