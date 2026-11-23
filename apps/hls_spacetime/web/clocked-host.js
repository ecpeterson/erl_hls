/** Finite, ordered host stimulus with explicit offered-word floors and causal
 * response gaps. These are host-policy inputs, not device service latencies.
 * Each view precedes an edge; step retires at most one accepted word on it.
 */
const clock = (value) => Number.isSafeInteger(value) && value >= 0;
const identifier = (value) => typeof value === "string" && value.length > 0;

/** Invalid or contradictory policy must not silently turn required work idle. */
function check(condition, message) {
  if (!condition) throw new TypeError(`Clocked host: ${message}`);
}

/** Copy and validate immutable completion facts; omission never erases a fact. */
function completions(previous, incoming) {
  check(
    incoming &&
      typeof incoming === "object" &&
      !Array.isArray(incoming) &&
      [Object.prototype, null].includes(Object.getPrototypeOf(incoming)),
    "invalid completion ledger",
  );
  const result = { ...previous };
  for (const [id, cycle] of Object.entries(incoming)) {
    check(identifier(id) && clock(cycle), "invalid completion fact");
    check(
      !Object.hasOwn(previous, id) || previous[id] === cycle,
      `changed completion for ${id}`,
    );
    Object.defineProperty(result, id, {
      value: cycle,
      enumerable: true,
      writable: true,
      configurable: true,
    });
  }
  return result;
}

/** Own the command arrays so mutating an input fixture cannot change a held word. */
function commandValues(commands) {
  check(Array.isArray(commands), "commands must be an array");
  const ids = new Set();
  return commands.map((command) => {
    check(
      command && identifier(command.id) && !ids.has(command.id),
      "invalid or duplicate command id",
    );
    ids.add(command.id);
    const { words, floors, causes, responseGap, recipients } = command;
    check(
      Array.isArray(words) &&
        words.length > 0 &&
        words.every((word) => clock(word) && word <= 0xffffffff),
      "invalid command words",
    );
    check(
      Array.isArray(floors) &&
        floors.length === words.length &&
        floors.every(clock),
      "invalid word floors",
    );
    check(
      Array.isArray(causes) &&
        causes.every(identifier) &&
        new Set(causes).size === causes.length,
      "invalid command causes",
    );
    check(clock(responseGap), "invalid response gap");
    check(
      Array.isArray(recipients) &&
        recipients.every((value) => clock(value) || identifier(value)),
      "invalid recipient identities",
    );
    return {
      id: command.id,
      words: words.slice(),
      floors: floors.slice(),
      causes: causes.slice(),
      responseGap,
      recipients: recipients.slice(),
    };
  });
}

/** Start one explicitly supplied host workload. A seeded completion ledger can
 * describe an established prefix; it neither executes attachment nor validates
 * reset/incarnation compatibility. complete means all these command words were
 * accepted, not that the application finished or that a capture is complete.
 */
export function hostInitial(commands, completed = {}) {
  const copied = commandValues(commands);
  return {
    commands: copied,
    completed: completions({}, completed),
    commandIndex: 0,
    wordIndex: 0,
    releaseCycle: null,
    held: false,
    acceptedWords: 0,
    lastCycle: null,
    complete: copied.length === 0,
  };
}

/** Earliest permitted command start; later words retain their own exogenous
 * floors. A missing or future-dated cause remains waiting, never zero latency.
 */
function release(command, cycle, completed) {
  let latest = 0;
  for (const cause of command.causes) {
    if (!Object.hasOwn(completed, cause) || completed[cause] > cycle)
      return null;
    latest = Math.max(latest, completed[cause]);
  }
  const causal = command.causes.length ? latest + command.responseGap : 0;
  check(clock(causal), "response release exceeds safe clock range");
  return Math.max(command.floors[0], causal);
}

/** A word is offered independently of ready. Once offered and stalled, it stays
 * valid with unchanged data/last. Callers supply only completions already known
 * at this edge's observation phase; current-edge output retirement belongs to
 * the following observation. This function does not mutate state or the ledger.
 */
export function hostView(state, cycle, completed = {}) {
  check(clock(cycle), "invalid observation cycle");
  check(
    state.lastCycle === null || cycle > state.lastCycle,
    "observation must follow the previous step",
  );
  const facts = completions(state.completed, completed);
  if (state.complete)
    return {
      valid: false,
      word: null,
      last: false,
      command: null,
      index: null,
      releaseCycle: null,
      complete: true,
    };
  const command = state.commands[state.commandIndex];
  const releaseCycle = state.releaseCycle ?? release(command, cycle, facts);
  const valid =
    state.held ||
    (releaseCycle !== null &&
      cycle >= releaseCycle &&
      cycle >= command.floors[state.wordIndex]);
  return {
    valid,
    word: valid ? command.words[state.wordIndex] : null,
    last: valid && state.wordIndex === command.words.length - 1,
    command: command.id,
    index: state.wordIndex,
    releaseCycle,
    complete: false,
  };
}

/** Advance one edge, retaining causal facts and a stalled offer. No automatic
 * packet parsing, recipient delivery or application completion is inferred.
 * Initial reset clocks suppress offers without advancing the host workload.
 * A reset after acceptance rejects: construct a new explicit workload/prefix
 * for a new device incarnation rather than replaying or resuming partial work.
 */
export function hostStep(
  state,
  { ready, cycle, completed = {}, reset = false },
) {
  check(
    typeof ready === "boolean" && typeof reset === "boolean",
    "nonboolean control",
  );
  const view = hostView(state, cycle, completed);
  const facts = completions(state.completed, completed);
  if (reset) {
    check(
      state.acceptedWords === 0,
      "reset after accepted work requires a new host workload",
    );
    return {
      state: {
        ...state,
        completed: facts,
        releaseCycle: null,
        held: false,
        lastCycle: cycle,
      },
      acceptedWord: null,
    };
  }
  const next = {
    ...state,
    completed: facts,
    releaseCycle: view.releaseCycle,
    held: view.valid && !ready,
    lastCycle: cycle,
  };
  if (!view.valid || !ready) return { state: next, acceptedWord: null };
  const command = state.commands[state.commandIndex];
  const acceptedWord = {
    command: command.id,
    index: state.wordIndex,
    word: view.word,
    last: view.last,
    cycle,
    releaseCycle: view.releaseCycle,
    recipients: command.recipients.slice(),
  };
  next.acceptedWords++;
  if (view.last) {
    next.commandIndex++;
    next.wordIndex = 0;
    next.releaseCycle = null;
    next.complete = next.commandIndex === state.commands.length;
  } else next.wordIndex++;
  return { state: next, acceptedWord };
}
