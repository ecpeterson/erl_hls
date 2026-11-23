/** Explain a cached static cone bound with one representative native pin path.
 * Costs are independent per-arc SDF envelopes, not a sensitized path, STA slack,
 * or a clock period. This module never fills missing timing or recomputes bounds.
 */
const SCOPES = new Set(["registered", "static"]);
const finite = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;

function requireValue(ok, message) {
  if (!ok) throw Error(`Timing path: ${message}`);
}

/** Sums differing only at floating-point precision are equivalent. This is not
 * an engineering timing margin; sink and predecessor tie counts use this rule. */
function equalDelay(left, right) {
  return (
    finite(left) &&
    finite(right) &&
    Math.abs(left - right) <= 1e-12 * Math.max(1, left, right)
  );
}

/** Use native identifiers rather than graph-array position or locale collation. */
function identityOrder(rows) {
  return (left, right) =>
    rows[left].id < rows[right].id
      ? -1
      : rows[left].id > rows[right].id
        ? 1
        : left - right;
}

/** Qualification remains owned by computation-routes. Static scope includes all
 * supported frontiers; registered scope retains its existing reachability reasons. */
function qualification(cone, scope) {
  if (scope === "registered")
    return {
      status: cone.registeredTiming.status,
      reasons: [...cone.registeredTiming.reasons],
      delayNs: cone.registeredDelayNs,
    };
  const reasons = [];
  if (cone.coverage.missingTiming) reasons.push("missing_static_path_timing");
  if (cone.coverage.unsupportedFrontiers)
    reasons.push("unsupported_or_missing_frontier");
  if (cone.coverage.cyclic) reasons.push("cycle");
  if (!finite(cone.staticDelayNs) && !reasons.length)
    reasons.push("missing_static_bound");
  return {
    status: reasons.length ? "unknown" : "known",
    reasons,
    delayNs: cone.staticDelayNs,
  };
}

/** Extract one representative longest source-to-selected-root path from a
 * validated createComputations index and its cached cone. References are numeric
 * indices into that exact graph. Unknown/inapplicable bounds return no path.
 * Known paths backtrack cached latest pin arrivals, choose native-ID-sorted ties,
 * and reconcile their net/logic sums with the existing total. Inconsistent cached
 * evidence throws rather than publishing a plausible partial path. Traversal is
 * bounded by the cone's pin population and never enumerates alternative paths.
 * branchingEncountered counts only whether the selected backtrack met a tie;
 * maxSinkCount counts all equally maximal eligible roots. Neither counts paths.
 */
export function timingPath(index, cone, { scope = "registered" } = {}) {
  requireValue(SCOPES.has(scope), "invalid scope");
  const qualified = qualification(cone, scope);
  requireValue(
    ["known", "unknown", "not_applicable"].includes(qualified.status),
    "invalid cached qualification",
  );
  const result = {
    scope,
    role: cone.role,
    status: qualified.status,
    reasons: qualified.reasons,
    delayNs: null,
    sourcePin: null,
    targetPin: null,
    arcIndices: [],
    netDelayNs: null,
    logicDelayNs: null,
    ties: {
      maxSinkCount: 0,
      branchingEncountered: false,
      representativeOnly: true,
    },
  };
  if (qualified.status !== "known") return result;
  requireValue(finite(qualified.delayNs), "known bound has no finite delay");
  const values = cone.pinArrivals[scope];
  requireValue(
    values.length === cone.pinIndices.length,
    "unaligned cached pin arrivals",
  );
  const arrivals = new Map(
    cone.pinIndices.map((pin, position) => [pin, values[position]]),
  );
  requireValue(
    cone.rootPins.every(
      (pin) =>
        finite(arrivals.get(pin)) ||
        (scope === "registered" && arrivals.get(pin) === "not_applicable"),
    ),
    "known bound has an unknown selected root",
  );
  const maximal = cone.rootPins
    .filter((pin) => equalDelay(arrivals.get(pin), qualified.delayNs))
    .sort(identityOrder(index.pins));
  requireValue(maximal.length > 0, "cached root arrival disagrees with bound");
  requireValue(
    cone.rootPins.every(
      (pin) =>
        !finite(arrivals.get(pin)) ||
        arrivals.get(pin) < qualified.delayNs ||
        equalDelay(arrivals.get(pin), qualified.delayNs),
    ),
    "selected root exceeds cached bound",
  );
  const sources = new Set(
    cone.frontiers
      .filter(
        (frontier) => scope === "static" || frontier.kind === "sequential",
      )
      .map((frontier) => frontier.pin),
  );
  const included = new Set(cone.arcIndices),
    visited = new Set(),
    reverse = [];
  let pin = maximal[0],
    branching = false;
  while (!sources.has(pin)) {
    requireValue(
      !visited.has(pin) && visited.size < cone.pinIndices.length,
      "backtrack exceeds acyclic cone",
    );
    visited.add(pin);
    const candidates = index.incoming[pin]
      .filter((arcIndex) => {
        if (!included.has(arcIndex)) return false;
        const arc = index.arcs[arcIndex],
          delay = index.delays[arcIndex],
          head = arrivals.get(arc.from);
        return (
          finite(delay) &&
          finite(head) &&
          equalDelay(head + delay, arrivals.get(pin))
        );
      })
      .sort(identityOrder(index.arcs));
    requireValue(
      candidates.length > 0,
      "no predecessor explains cached arrival",
    );
    branching ||= candidates.length > 1;
    const selected = candidates[0];
    reverse.push(selected);
    pin = index.arcs[selected].from;
  }
  requireValue(equalDelay(arrivals.get(pin), 0), "source arrival is not zero");
  const arcIndices = reverse.reverse();
  let netDelayNs = 0,
    logicDelayNs = 0,
    sum = 0;
  for (const arcIndex of arcIndices) {
    const delay = index.delays[arcIndex];
    if (index.arcs[arcIndex].kind === "net") netDelayNs += delay;
    else logicDelayNs += delay;
    sum += delay;
  }
  requireValue(
    equalDelay(sum, qualified.delayNs) &&
      equalDelay(netDelayNs + logicDelayNs, qualified.delayNs),
    "representative sum disagrees with cached bound",
  );
  return {
    ...result,
    delayNs: qualified.delayNs,
    sourcePin: pin,
    targetPin: maximal[0],
    arcIndices,
    netDelayNs,
    logicDelayNs,
    ties: {
      maxSinkCount: maximal.length,
      branchingEncountered: branching,
      representativeOnly: true,
    },
  };
}
