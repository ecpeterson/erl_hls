/** Clocked ownership and selection rules for the source-protocol backend.
 * All observations use old state; callers commit returned states together.
 * Payloads are opaque recorded values. These controls do not evaluate actors.
 */
const count = (value) => Number.isSafeInteger(value) && value > 0;
const index = (value, size) =>
  Number.isSafeInteger(value) && value >= 0 && value < size;
const identity = (value) => typeof value === "string" && value.length > 0;
const slotKey = (value) =>
  identity(value) || (Number.isSafeInteger(value) && value >= 0);

/** Reject malformed state or impossible accepted handshakes. */
function requireValue(condition, message) {
  if (!condition) throw new TypeError(message);
}

/** Copy a bounded set of indices, rejecting duplicates rather than hiding them. */
function indices(values, size, label) {
  requireValue(
    Array.isArray(values) || values instanceof Set,
    `${label} must be an array or Set`,
  );
  const result = [...values];
  requireValue(
    result.every((value) => index(value, size)),
    `${label} contains an invalid index`,
  );
  requireValue(
    new Set(result).size === result.length,
    `${label} contains duplicate indices`,
  );
  return result;
}

/** Delivery order within each recipient is the order in the offered batch. */
function delivery(value, recipientCount) {
  requireValue(
    value && identity(value.id) && index(value.recipient, recipientCount),
    "Invalid publication delivery",
  );
  const slot = value.slot ?? value.recipient;
  requireValue(slotKey(slot), "Invalid delivery capture-slot identity");
  requireValue(Object.hasOwn(value, "payload"), "Delivery has no payload");
  return { ...value, slot };
}

/** Validate the single publication and its remaining per-recipient queues. */
function publicationState(state) {
  requireValue(
    state &&
      count(state.recipientCount) &&
      Array.isArray(state.queues) &&
      state.queues.length === state.recipientCount,
    "Invalid publication state",
  );
  const ids = new Set();
  let busy = false;
  state.queues.forEach((queue, recipient) => {
    requireValue(Array.isArray(queue), "Invalid publication recipient queue");
    for (const item of queue) {
      delivery(item, state.recipientCount);
      requireValue(
        item.recipient === recipient && !ids.has(item.id),
        "Publication delivery identity or recipient mismatch",
      );
      ids.add(item.id);
      busy = true;
    }
  });
  requireValue(
    busy ? identity(state.batchId) : state.batchId === null,
    "Publication occupancy and batch identity disagree",
  );
  return busy;
}

/** An idle source publication; accepting an empty batch leaves it idle. */
export function publicationInitial(recipientCount) {
  requireValue(count(recipientCount), "Recipient count must be positive");
  return {
    recipientCount,
    batchId: null,
    queues: Array.from({ length: recipientCount }, () => []),
  };
}

/** Observe one oldest delivery per recipient. freeSlots is a Set of target slot
 * identities (delivery.slot, or recipient when omitted), derived from old credit.
 * Missing freeSlots grants no credit. ready concerns a new batch, not deliveries.
 */
export function publicationView(state, { freeSlots = new Set() } = {}) {
  const busy = publicationState(state);
  requireValue(
    freeSlots instanceof Set && [...freeSlots].every(slotKey),
    "freeSlots must contain capture-slot identities",
  );
  const offers = state.queues.flatMap((queue) =>
    queue.length
      ? [{ ...queue[0], slot: queue[0].slot ?? queue[0].recipient }]
      : [],
  );
  return {
    busy,
    ready: !busy,
    offers,
    acceptedRecipients: offers
      .filter((item) => freeSlots.has(item.slot))
      .map((item) => item.recipient),
  };
}

/** Retire accepted OLD deliveries, or admit a batch while OLD state is idle.
 * A last-delivery transfer cannot admit another batch on the same edge. A busy
 * offer is retained by its caller, not queued here. reset cancels ownership.
 */
export function publicationStep(
  state,
  { batch = null, acceptedRecipients = [], reset = false } = {},
) {
  const busy = publicationState(state);
  if (reset)
    return {
      state: publicationInitial(state.recipientCount),
      batchAccepted: false,
      delivered: [],
    };
  const accepted = indices(
    acceptedRecipients,
    state.recipientCount,
    "Accepted recipients",
  );
  for (const recipient of accepted)
    requireValue(
      state.queues[recipient].length > 0,
      "Acceptance has no old publication delivery",
    );
  let incoming = null;
  if (batch !== null) {
    requireValue(
      batch && identity(batch.id) && Array.isArray(batch.deliveries),
      "Invalid publication batch",
    );
    incoming = batch.deliveries.map((item) =>
      delivery(item, state.recipientCount),
    );
    requireValue(
      new Set(incoming.map((item) => item.id)).size === incoming.length,
      "Duplicate publication delivery identity",
    );
  }
  const delivered = accepted.map((recipient) => ({
    ...state.queues[recipient][0],
  }));
  let queues = state.queues.map((queue, recipient) =>
    accepted.includes(recipient) ? queue.slice(1) : queue.slice(),
  );
  const batchAccepted = !busy && incoming !== null;
  if (batchAccepted) {
    queues = Array.from({ length: state.recipientCount }, () => []);
    for (const item of incoming) queues[item.recipient].push(item);
  }
  return {
    state: {
      recipientCount: state.recipientCount,
      batchId: queues.some((queue) => queue.length)
        ? batchAccepted
          ? batch.id
          : state.batchId
        : null,
      queues,
    },
    batchAccepted,
    delivered,
  };
}

/** A capture's payload remains readable while FULL or LEASED, and may remain
 * physically unchanged while FREE. Only ownership supplies validity.
 */
function captureState(state) {
  requireValue(
    state &&
      ["free", "full", "leased"].includes(state.owner) &&
      Object.hasOwn(state, "value"),
    "Invalid capture state",
  );
  requireValue(
    state.owner === "free" || state.value != null,
    "Owned capture has no value",
  );
}

/** Reset state of one physical payload slot. */
export function captureInitial() {
  return { owner: "free", value: null };
}

/** Apply accepted arrival/take/release signals to old ownership. release is the
 * receiver's OLD registered release, not this edge's take. Releasing a slot cannot
 * accept a new arrival until the next edge. Impossible accepted signals reject.
 */
export function captureStep(
  state,
  { arrive = null, take = false, release = false, reset = false } = {},
) {
  captureState(state);
  if (reset)
    return {
      state: captureInitial(),
      arrived: false,
      taken: false,
      released: false,
    };
  requireValue(
    typeof take === "boolean" && typeof release === "boolean",
    "Capture handshakes must be boolean",
  );
  requireValue(
    arrive === null || state.owner === "free",
    "Arrival lacks old free credit",
  );
  requireValue(
    !take || state.owner === "full",
    "Take lacks an old full capture",
  );
  requireValue(
    !release || state.owner === "leased",
    "Release lacks an old lease",
  );
  const next =
    arrive !== null
      ? { owner: "full", value: arrive }
      : take
        ? { ...state, owner: "leased" }
        : release
          ? { ...state, owner: "free" }
          : { ...state };
  return {
    state: next,
    arrived: arrive !== null,
    taken: take,
    released: release,
  };
}

/** Pending captures ordered within exactly one sender/recipient pair. */
function pairState(state) {
  requireValue(
    state && count(state.slotCount) && Array.isArray(state.pending),
    "Invalid sender-pair state",
  );
  indices(state.pending, state.slotCount, "Pending pair slots");
}

/** No pending messages after reset. */
export function pairInitial(slotCount) {
  requireValue(count(slotCount), "Pair slot count must be positive");
  return { slotCount, pending: [] };
}

/** Oldest eligible pending capture; postponed older captures may be bypassed. */
export function pairSelect(state, eligible) {
  pairState(state);
  const allowed = new Set(
    indices(eligible, state.slotCount, "Eligible pair slots"),
  );
  return state.pending.find((slot) => allowed.has(slot)) ?? null;
}

/** Retire the accepted old slot before ordering one new arrival after survivors.
 * Capture credit forbids arriving into an old pending slot, even if taken now.
 */
export function pairStep(
  state,
  { arrive = null, take = null, reset = false } = {},
) {
  pairState(state);
  if (reset) return pairInitial(state.slotCount);
  requireValue(
    take === null ||
      (index(take, state.slotCount) && state.pending.includes(take)),
    "Pair take has no pending slot",
  );
  requireValue(
    arrive === null ||
      (index(arrive, state.slotCount) && !state.pending.includes(arrive)),
    "Pair arrival reuses an old pending slot",
  );
  return {
    slotCount: state.slotCount,
    pending: [
      ...state.pending.filter((slot) => slot !== take),
      ...(arrive === null ? [] : [arrive]),
    ],
  };
}

/** Receiver indices are flattened physical/startup identities, not payloads. */
function inboxState(state) {
  requireValue(
    state &&
      count(state.slotCount) &&
      index(state.cursor, state.slotCount) &&
      Array.isArray(state.postponed) &&
      Array.isArray(state.released),
    "Invalid inbox state",
  );
  requireValue(
    state.held === null || index(state.held, state.slotCount),
    "Invalid held inbox slot",
  );
  indices(state.postponed, state.slotCount, "Postponed slots");
  const released = indices(
    state.released,
    state.slotCount,
    "Registered releases",
  );
  requireValue(
    released.length <= 1,
    "One inbox cannot release multiple heads per edge",
  );
}

/** Empty reservations, no postponement, and initial round-robin cursor. */
export function inboxInitial(slotCount) {
  requireValue(count(slotCount), "Inbox slot count must be positive");
  return { slotCount, cursor: 0, held: null, postponed: [], released: [] };
}

/** Eligibility depends only on registered receiver/owner state. A held head
 * remains eligible during its owner's action; enabled=false masks reset/startup
 * or an explicit pipeline busy state before that held-head rule.
 */
export function inboxEligible(
  state,
  {
    enabled = true,
    ownerBusy = false,
    internalPending = false,
    failed = false,
  } = {},
) {
  inboxState(state);
  requireValue(
    [enabled, ownerBusy, internalPending, failed].every(
      (value) => typeof value === "boolean",
    ),
    "Inbox controls must be boolean",
  );
  if (!enabled) return [];
  if (state.held !== null) return [state.held];
  if (ownerBusy || internalPending || failed) return [];
  return Array.from({ length: state.slotCount }, (_, slot) => slot).filter(
    (slot) => !state.postponed.includes(slot),
  );
}

/** Select among caller-supplied oldest eligible pair heads. Selection alone does
 * not advance the cursor or dequeue anything. Existing reservations suppress offers.
 */
export function inboxView(state, { heads = [], ...controls } = {}) {
  const eligible = inboxEligible(state, controls);
  const requests = new Set(
    indices(heads, state.slotCount, "Inbox heads").filter((slot) =>
      eligible.includes(slot),
    ),
  );
  let pick = null;
  for (let offset = 0; offset < state.slotCount; offset++) {
    const slot = (state.cursor + offset) % state.slotCount;
    if (requests.has(slot)) {
      pick = slot;
      break;
    }
  }
  return {
    eligible,
    pick,
    offered: state.held === null && pick !== null,
    reservation: state.held ?? pick,
  };
}

/** Apply one owner's coherent result. accepted advances the cursor; headDone
 * ends a reservation. Source directives 0/1 consume/postpone; others do neither.
 * Phase boundaries clear all postponement, including a new same-edge postpone.
 * output.release is old state; output.take becomes next edge's registered release.
 */
export function inboxStep(
  state,
  {
    heads = [],
    accepted = false,
    headDone = false,
    dispatched = false,
    directive = 0,
    phaseBoundary = false,
    reset = false,
    ...controls
  } = {},
) {
  inboxState(state);
  if (reset)
    return {
      state: inboxInitial(state.slotCount),
      output: {
        eligible: [],
        accepted: [],
        take: [],
        postpone: [],
        release: [],
      },
    };
  requireValue(
    [accepted, headDone, dispatched, phaseBoundary].every(
      (value) => typeof value === "boolean",
    ) && index(directive, 4),
    "Invalid owner result",
  );
  const view = inboxView(state, { heads, ...controls });
  requireValue(
    !accepted || view.offered,
    "Inbox acceptance has no offered head",
  );
  requireValue(
    !headDone || state.held !== null || accepted,
    "Head retirement has no reservation",
  );
  requireValue(
    !dispatched || headDone,
    "Dispatch has no coherent head retirement",
  );
  const take = dispatched && directive === 0 ? [view.reservation] : [];
  const postpone = dispatched && directive === 1 ? [view.reservation] : [];
  return {
    state: {
      slotCount: state.slotCount,
      cursor: accepted ? (view.pick + 1) % state.slotCount : state.cursor,
      held: headDone ? null : accepted ? view.reservation : state.held,
      postponed: phaseBoundary
        ? []
        : [...new Set([...state.postponed, ...postpone])],
      released: take,
    },
    output: {
      eligible: view.eligible,
      accepted: accepted ? [view.reservation] : [],
      take,
      postpone,
      release: state.released.slice(),
    },
  };
}
