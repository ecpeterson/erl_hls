/** Clocked owner service for fixed recorded work. Numerical results and branch
 * decisions are inputs; only service, commit and old-outbox occupancy are replayed.
 * This is a control model, not an interpreter or a timing/functional proof.
 */
export function ownerInitial({
  pending = false,
  outbox = null,
  action = null,
} = {}) {
  return { pending, outbox, action };
}

/** Readiness is independent of the next recorded operation. The coordinator must
 * check that the actual offered head matches that operation, never wait for it.
 */
export function ownerView(state) {
  return {
    inputReady: !state.action && !state.pending,
    internalReady: !state.action && state.pending,
    batch: state.outbox,
  };
}

/** Apply one edge using old state. `operation` is supplied only for an accepted
 * head or pending internal work; extraLatency delays private completion, while
 * commit remains a separate following edge. An occupied old outbox blocks only
 * effect-producing commits, even if the publisher accepts that outbox now.
 * A receipt commits immediately. Unknown next-pending state stops later work.
 */
export function ownerStep(
  state,
  {
    cycle,
    operation = null,
    extraLatency = 0,
    batchReady = false,
    reset = false,
  },
) {
  if (
    !Number.isSafeInteger(cycle) ||
    cycle < 0 ||
    !Number.isSafeInteger(extraLatency) ||
    extraLatency < 0
  )
    throw new RangeError(
      "Owner clocks and latency must be nonnegative integers",
    );
  if (reset)
    return {
      state: ownerInitial(),
      events: [],
      completed: null,
      launched: false,
    };
  const next = { ...state };
  const events = [];
  if (state.outbox && batchReady) {
    next.outbox = null;
    events.push({ kind: "publication", id: state.outbox.id, cycle });
  }
  let completed = null,
    launched = false;
  if (state.action) {
    if (operation) throw new Error("Cannot launch into an occupied owner");
    const { operation: active, privateCycle } = state.action;
    if (cycle === privateCycle)
      events.push({ kind: "private", id: active.id, cycle });
    if (cycle > privateCycle && (!active.batch || !state.outbox)) {
      next.pending = active.nextPending;
      next.action = null;
      if (active.batch) next.outbox = active.batch;
      completed = active;
      events.push({ kind: "commit", id: active.id, cycle });
    }
  } else if (operation) {
    if (state.pending === null)
      throw new Error("Unresolved committed pending predicate");
    if (Boolean(operation.accepted) === Boolean(state.pending))
      throw new Error("Recorded operation disagrees with owner readiness");
    if (
      operation.nextPending !== null &&
      typeof operation.nextPending !== "boolean"
    )
      throw new TypeError("Operation needs an explicit next pending predicate");
    launched = true;
    events.push({ kind: "launch", id: operation.id, cycle });
    if (operation.kind === "receipt") {
      if (extraLatency || operation.batch)
        throw new Error("Receipt cannot pipeline or publish effects");
      next.pending = operation.nextPending;
      completed = operation;
      events.push({ kind: "receipt", id: operation.id, cycle });
    } else if (operation.kind === "action") {
      const privateCycle = cycle + extraLatency;
      if (!Number.isSafeInteger(privateCycle))
        throw new RangeError("Owner cycle overflow");
      next.action = { operation, privateCycle };
      if (!extraLatency)
        events.push({ kind: "private", id: operation.id, cycle });
    } else throw new TypeError("Unknown owner operation kind");
  }
  return { state: next, events, completed, launched };
}
