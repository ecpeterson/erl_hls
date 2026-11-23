/** Clocked packet transport derived from the ordered gateway and endpoint
 * arbiter. Every call advances one edge from old state; cycles and arrivals are
 * supplied by the caller, never inferred from saved output timestamps. These
 * finite state machines model handshakes, not electrical timing or capacity.
 */
const integer = (value) => Number.isSafeInteger(value) && value >= 0;

/** Reject malformed contracts before they can turn missing work into idle time. */
function check(condition, message) {
  if (!condition) throw new TypeError(`Clocked transport: ${message}`);
}

/** Validate the routed-word ABI used by this gateway (eight payload words max). */
function frameValue(frame) {
  if (frame === null) return null;
  check(
    frame &&
      typeof frame.id === "string" &&
      frame.id.length > 0 &&
      Array.isArray(frame.words) &&
      frame.words.length >= 2 &&
      frame.words.length <= 10 &&
      frame.words.every((word) => integer(word) && word <= 0xffffffff) &&
      frame.words.length === 2 + (frame.words[1] & 255),
    "invalid routed frame",
  );
  return frame;
}

/** A frame table is complete and explicit; only null denotes no offered frame. */
function frameTable(frames, count) {
  check(Array.isArray(frames) && frames.length === count, "frame table size");
  frames.forEach(frameValue);
}

/** Copy retained packet words so later caller changes cannot alter held data. */
function copyFrame(frame) {
  return { id: frame.id, words: frame.words.slice() };
}

/** Reset state has not transmitted attachment acknowledgment. A caller may seed
 * a separately established boundary with {started:true,cursor}; this is a model
 * input, not evidence that attachment occurred. Events occupy indices 0..N-1;
 * management occupies N. N may be zero, and is bounded to 256.
 */
export function transmitterInitial(
  streamCount,
  { started = false, cursor = 0 } = {},
) {
  check(integer(streamCount) && streamCount <= 256, "invalid stream count");
  check(typeof started === "boolean", "invalid started state");
  check(integer(cursor) && cursor <= streamCount, "invalid transmit cursor");
  return { streamCount, started, cursor, frame: null, source: null, index: 0 };
}

/** Current old-state output; invalid data has no meaningful value. Capturing a
 * new frame does not expose a word until the next state's view. A stalled word
 * is unchanged because step does not advance its retained index.
 */
export function transmitterView(state) {
  if (state.frame === null)
    return {
      valid: false,
      data: null,
      last: false,
      source: null,
      index: null,
      id: null,
    };
  return {
    valid: true,
    data: state.frame.words[state.index],
    last: state.index === state.frame.words.length - 1,
    source: state.source,
    index: state.index,
    id: state.frame.id,
  };
}

/** Advance one old-state polling/sending edge. Idle polls only one source and
 * advances cursor even when empty, independently of outputReady. Sending never
 * polls and advances only on outputReady. A management 0x81 final accepted word
 * sets started; 0xff clears it. Other management replies leave it unchanged.
 *
 * attached is an additional caller-supplied admission gate (default true), not
 * an acknowledgment shortcut: event polling still requires state.started.
 * Dropping it suppresses new event receives without changing an in-flight frame.
 * Reset cancels old transfers and restores the actual unattached initial state.
 */
export function transmitterStep(
  state,
  { frames, outputReady, attached = true, reset = false },
) {
  frameTable(frames, state.streamCount + 1);
  check(
    [outputReady, attached, reset].every((value) => typeof value === "boolean"),
    "nonboolean transmit control",
  );
  if (reset)
    return {
      state: transmitterInitial(state.streamCount),
      acceptedSource: null,
      acceptedWord: null,
    };
  const view = transmitterView(state);
  if (view.valid) {
    if (!outputReady)
      return { state, acceptedSource: null, acceptedWord: null };
    const { valid: _valid, ...acceptedWord } = view;
    let started = state.started;
    if (view.last && state.source === state.streamCount) {
      const tag = state.frame.words[1] >>> 24;
      if (tag === 0x81) started = true;
      else if (tag === 0xff) started = false;
    }
    return {
      state: {
        ...state,
        started,
        frame: view.last ? null : state.frame,
        source: view.last ? null : state.source,
        index: view.last ? 0 : state.index + 1,
      },
      acceptedSource: null,
      acceptedWord,
    };
  }
  const source = !state.started ? state.streamCount : state.cursor;
  const frame =
    source === state.streamCount || attached ? frames[source] : null;
  return {
    state: {
      ...state,
      cursor: (state.cursor + 1) % (state.streamCount + 1),
      frame: frame === null ? null : copyFrame(frame),
      source: frame === null ? null : source,
      index: 0,
    },
    acceptedSource: frame === null ? null : source,
    acceptedWord: null,
  };
}

/** Round-robin endpoint state. Held-frame bytes are a software contract check,
 * not additional hardware storage: the producer must itself retain its offer.
 */
export function egressInitial(producerCount, { cursor = 0 } = {}) {
  check(
    integer(producerCount) && producerCount > 0 && producerCount <= 256,
    "invalid producer count",
  );
  check(integer(cursor) && cursor < producerCount, "invalid egress cursor");
  return { producerCount, cursor, held: null, heldFrame: null };
}

/** Select from old valid offers, independently of recipient readiness. A stalled
 * grant survives later competing arrivals. Withdrawal or mutation of the held
 * frame violates the source ready/valid contract and rejects explicitly.
 */
export function egressView(state, frames, { reset = false } = {}) {
  frameTable(frames, state.producerCount);
  check(typeof reset === "boolean", "nonboolean egress reset");
  if (reset) return { valid: false, source: null, frame: null };
  let source = state.held;
  if (source !== null) {
    const current = frames[source],
      previous = state.heldFrame;
    check(
      current !== null &&
        current.id === previous.id &&
        current.words.length === previous.words.length &&
        current.words.every((word, index) => word === previous.words[index]),
      "held producer changed its frame",
    );
  } else {
    for (let offset = 0; offset < state.producerCount; offset++) {
      const candidate = (state.cursor + offset) % state.producerCount;
      if (frames[candidate] !== null) {
        source = candidate;
        break;
      }
    }
  }
  return source === null
    ? { valid: false, source: null, frame: null }
    : { valid: true, source, frame: frames[source] };
}

/** Retire only the selected accepted frame. The next cursor follows that source;
 * otherwise a valid offer locks its source. This arbiter forwards a frame in the
 * current clock and adds no packet register or extra transfer latency.
 */
export function egressStep(state, { frames, outputReady, reset = false }) {
  check(typeof outputReady === "boolean", "nonboolean egress ready");
  const view = egressView(state, frames, { reset });
  if (reset)
    return {
      state: egressInitial(state.producerCount),
      selectedSource: null,
      acceptedSource: null,
      frame: null,
    };
  const accepted = view.valid && outputReady;
  const next = accepted
    ? {
        ...state,
        cursor: (view.source + 1) % state.producerCount,
        held: null,
        heldFrame: null,
      }
    : view.valid
      ? {
          ...state,
          held: view.source,
          heldFrame: state.heldFrame ?? copyFrame(view.frame),
        }
      : state;
  return {
    state: next,
    selectedSource: view.source,
    acceptedSource: accepted ? view.source : null,
    frame: view.frame,
  };
}
