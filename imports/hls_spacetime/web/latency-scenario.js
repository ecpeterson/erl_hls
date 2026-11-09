/** Conditional delay propagation over explicit event constraints. This model
 * freezes observed work, dependencies, order and release floors. It neither
 * schedules hardware nor derives service time from timestamps or residence.
 */
const ASSUMPTIONS = Object.freeze([
  "The same events, values, dependencies and declared order remain applicable.",
  "Recorded event cycles remain release floors; unexplained gaps may absorb delay.",
  "Only supplied edge lags model service or transfer latency.",
  "Each event's extra latency is added after its own prerequisites become ready.",
  "External releases and unrecorded dependencies do not change in this scenario.",
  "Constraint consistency does not establish hardware feasibility or progress.",
]);
const integer = (value) => Number.isSafeInteger(value) && value >= 0;
const textId = (value) => typeof value === "string" && value.length > 0;
const lexical = (left, right) => (left < right ? -1 : left > right ? 1 : 0);

function requireValue(condition, message) {
  if (!condition) throw new TypeError(message);
}
function requireCycle(value, label) {
  if (!integer(value))
    throw new RangeError(`${label} must be a nonnegative safe integer`);
}
function checkedAdd(left, right) {
  const value = left + right;
  return Number.isSafeInteger(value) ? value : null;
}

/** Validate explicit identities and timing assumptions, retaining every edge.
 * Duplicate endpoint pairs may express different constraints; none is discarded.
 */
function graph(input) {
  requireValue(input && typeof input === "object", "Missing latency scenario");
  const { events, edges, start, bounds, targets } = input;
  requireValue(
    Array.isArray(events) && Array.isArray(edges),
    "Events and edges must be arrays",
  );
  requireValue(
    start && textId(start.incarnation),
    "An explicit start incarnation is required",
  );
  requireCycle(start.cycle, "Start cycle");
  requireValue(
    bounds && ["reset", "capture"].includes(bounds.endKind),
    "An explicit reset or capture boundary is required",
  );
  requireCycle(bounds.firstCycle, "First cycle");
  requireCycle(bounds.endCycle, "End cycle");
  if (!(bounds.firstCycle <= start.cycle && start.cycle < bounds.endCycle))
    throw new RangeError("Start lies outside the half-open incarnation bounds");
  requireValue(
    Array.isArray(targets) &&
      targets.length > 0 &&
      new Set(targets).size === targets.length,
    "Explicit distinct completion targets are required",
  );
  const dependencyComplete = input.dependencyComplete ?? false;
  requireValue(
    typeof dependencyComplete === "boolean",
    "Dependency completeness must be explicit boolean evidence",
  );
  const unknowns = input.unknowns ?? [];
  requireValue(
    Array.isArray(unknowns),
    "Unknown dependency dispositions must be an array",
  );
  const byId = new Map();
  const incoming = new Map(),
    outgoing = new Map();
  for (const event of events) {
    requireValue(
      event && textId(event.id) && !byId.has(event.id),
      "Missing or duplicate event identity",
    );
    requireCycle(event.cycle, `Cycle of ${event.id}`);
    requireCycle(event.extraLatency ?? 0, `Extra latency of ${event.id}`);
    requireValue(
      event.incarnation === start.incarnation,
      `Event crosses the selected incarnation: ${event.id}`,
    );
    if (event.cycle < bounds.firstCycle || event.cycle >= bounds.endCycle)
      throw new RangeError(
        `Recorded event lies outside incarnation bounds: ${event.id}`,
      );
    byId.set(event.id, event);
    incoming.set(event.id, []);
    outgoing.set(event.id, []);
  }
  for (const target of targets)
    requireValue(
      textId(target) && byId.has(target),
      `Unknown completion target: ${target}`,
    );
  const constraints = edges.map((edge, index) => {
    requireValue(
      edge && byId.has(edge.source) && byId.has(edge.target),
      `Unknown constraint endpoint: ${index}`,
    );
    requireCycle(edge.minLag, `Minimum lag of constraint ${index}`);
    if (edge.maxLag !== undefined) {
      requireCycle(edge.maxLag, `Maximum lag of constraint ${index}`);
      if (edge.maxLag < edge.minLag)
        throw new RangeError(`Maximum lag precedes minimum lag: ${index}`);
    }
    const constraint = { ...edge, index };
    incoming.get(edge.target).push(constraint);
    outgoing.get(edge.source).push(constraint);
    return constraint;
  });
  const completionCycle = targets.reduce(
    (maximum, id) => Math.max(maximum, byId.get(id).cycle),
    0,
  );
  if (completionCycle < start.cycle)
    throw new RangeError("All completion targets precede the explicit start");
  const ancestors = new Set(targets),
    pending = [...targets];
  for (let cursor = 0; cursor < pending.length; cursor++) {
    for (const edge of incoming.get(pending[cursor])) {
      if (!ancestors.has(edge.source)) {
        ancestors.add(edge.source);
        pending.push(edge.source);
      }
    }
  }
  return {
    byId,
    incoming,
    outgoing,
    constraints,
    ancestors,
    baseline: { completionCycle, elapsedCycles: completionCycle - start.cycle },
    coverage: { dependencyComplete, unknowns: unknowns.slice() },
  };
}

/** Return a safe topological order, or unresolved identities if any cycle exists.
 * Even zero-lag cycles are outside this explicit-DAG model and reject; timestamps
 * or input order never silently break a cycle into a favorable schedule.
 */
function topological(events, incoming, outgoing) {
  const remaining = new Map(
    events.map((event) => [event.id, incoming.get(event.id).length]),
  );
  const order = events
    .filter((event) => remaining.get(event.id) === 0)
    .map((event) => event.id);
  for (let cursor = 0; cursor < order.length; cursor++) {
    for (const edge of outgoing.get(order[cursor])) {
      const count = remaining.get(edge.target) - 1;
      remaining.set(edge.target, count);
      if (count === 0) order.push(edge.target);
    }
  }
  return order.length === events.length
    ? { order, unresolved: [] }
    : {
        order: [],
        unresolved: events
          .filter((event) => remaining.get(event.id) > 0)
          .map((event) => event.id),
      };
}

/** Propagate repeated nonnegative extra latencies through explicit clock lags.
 * For each event v: T(v)=max(recordedCycle(v), max(T(u)+minLag(u,v)))+extra(v).
 * No lag is inferred from recorded gaps. Zero intervention exactly reproduces
 * a valid baseline. maxLag checks constrain only their declared edges.
 *
 * start={cycle,incarnation}; bounds={firstCycle,endCycle,endKind:reset|capture};
 * targets are accepted-action event IDs, not inferred public completion records.
 * A reset crossing in target ancestry invalidates the scenario. A capture-tail
 * crossing censors its completion score; unrelated downstream exits do not.
 * All otherwise consistent results remain conditional, including when declared
 * dependency coverage is complete. Unknowns pass through without becoming zero.
 * Malformed inputs throw; graph/latency contradictions return status invalid.
 */
export function latencyScenario(input) {
  const g = graph(input);
  const result = {
    status: "conditional",
    reason: null,
    baseline: g.baseline,
    candidate: null,
    provisional: null,
    events: [],
    targets: input.targets.map((id) => ({
      id,
      baselineCycle: g.byId.get(id).cycle,
      scenarioCycle: null,
    })),
    violations: [],
    coverage: g.coverage,
    assumptions: [...ASSUMPTIONS],
    scope: {
      start: { ...input.start },
      bounds: { ...input.bounds },
      targets: [...input.targets],
      events: input.events.length,
      edges: input.edges.length,
      ancestorEvents: g.ancestors.size,
      intervenedEvents: input.events.filter(
        (event) => (event.extraLatency ?? 0) > 0,
      ).length,
      ancestorInterventions: input.events.filter(
        (event) => g.ancestors.has(event.id) && (event.extraLatency ?? 0) > 0,
      ).length,
    },
  };
  const invalid = (reason, violations) => ({
    ...result,
    status: "invalid",
    reason,
    violations,
  });
  const { order, unresolved } = topological(
    input.events,
    g.incoming,
    g.outgoing,
  );
  if (unresolved.length)
    return invalid("dependency_cycle", [
      { kind: "dependency_cycle", unresolvedEventIds: unresolved },
    ]);
  const baselineViolations = [];
  for (const edge of g.constraints) {
    const gap = g.byId.get(edge.target).cycle - g.byId.get(edge.source).cycle;
    if (gap < edge.minLag || (edge.maxLag !== undefined && gap > edge.maxLag))
      baselineViolations.push({
        kind: "baseline_constraint",
        edge: edge.index,
        source: edge.source,
        target: edge.target,
        gap,
        minLag: edge.minLag,
        maxLag: edge.maxLag ?? null,
      });
  }
  if (baselineViolations.length)
    return invalid("baseline_constraint_violation", baselineViolations);
  const times = new Map();
  for (const id of order) {
    const event = g.byId.get(id);
    let availabilityCycle = event.cycle;
    const arrivals = [];
    for (const edge of g.incoming.get(id)) {
      const arrival = checkedAdd(times.get(edge.source), edge.minLag);
      if (arrival === null)
        return invalid("cycle_overflow", [
          { kind: "cycle_overflow", event: id, edge: edge.index },
        ]);
      arrivals.push([edge.source, arrival]);
      availabilityCycle = Math.max(availabilityCycle, arrival);
    }
    const extraLatency = event.extraLatency ?? 0;
    const scenarioCycle = checkedAdd(availabilityCycle, extraLatency);
    if (scenarioCycle === null)
      return invalid("cycle_overflow", [{ kind: "cycle_overflow", event: id }]);
    times.set(id, scenarioCycle);
    result.events.push({
      ...event,
      extraLatency,
      availabilityCycle,
      scenarioCycle,
      deltaCycles: scenarioCycle - event.cycle,
      blockingPredecessors: [
        ...new Set(
          arrivals
            .filter(([, arrival]) => arrival === availabilityCycle)
            .map(([source]) => source),
        ),
      ].sort(lexical),
      baselineFloorBinding: event.cycle === availabilityCycle,
    });
  }
  result.targets = result.targets.map((target) => ({
    ...target,
    scenarioCycle: times.get(target.id),
  }));
  const maxLagViolations = g.constraints
    .filter(
      (edge) =>
        edge.maxLag !== undefined &&
        times.get(edge.target) - times.get(edge.source) > edge.maxLag,
    )
    .map((edge) => ({
      kind: "maximum_lag",
      edge: edge.index,
      source: edge.source,
      target: edge.target,
      gap: times.get(edge.target) - times.get(edge.source),
      maxLag: edge.maxLag,
    }));
  if (maxLagViolations.length)
    return invalid("maximum_lag_violation", maxLagViolations);
  const completionCycle = result.targets.reduce(
    (maximum, target) => Math.max(maximum, target.scenarioCycle),
    0,
  );
  const timing = {
    completionCycle,
    elapsedCycles: completionCycle - input.start.cycle,
    deltaCycles: completionCycle - result.baseline.completionCycle,
  };
  const boundaryExits = result.events
    .filter(
      (event) =>
        g.ancestors.has(event.id) &&
        event.scenarioCycle >= input.bounds.endCycle,
    )
    .map((event) => ({
      kind: `${input.bounds.endKind}_boundary`,
      event: event.id,
      scenarioCycle: event.scenarioCycle,
      boundaryCycle: input.bounds.endCycle,
    }));
  if (boundaryExits.length) {
    if (input.bounds.endKind === "reset")
      return invalid("reset_boundary", boundaryExits);
    return {
      ...result,
      status: "censored",
      reason: "capture_boundary",
      provisional: timing,
      violations: boundaryExits,
    };
  }
  result.candidate = timing;
  return result;
}

/** Compare explicitly assumed periods only for an uncensored conditional result.
 * Break-even is baselineElapsedNs/candidateClocks, not a predicted clock period.
 * Zero elapsed denominators produce null ratios, never Infinity or invented gain.
 * Invalid/censored scenarios have no score even when their computed times exist.
 */
export function periodSensitivity(
  result,
  { baselinePeriodNs, candidatePeriodNs } = {},
) {
  for (const [label, period] of [
    ["Baseline", baselinePeriodNs],
    ["Candidate", candidatePeriodNs],
  ])
    if (!Number.isFinite(period) || period <= 0)
      throw new RangeError(`${label} period must be finite and positive`);
  const assumptions = { baselinePeriodNs, candidatePeriodNs };
  if (result?.status !== "conditional" || !result.candidate)
    return {
      status: "unavailable",
      reason: result?.status ?? "missing_scenario",
      assumptions,
    };
  const baselineElapsedNs = result.baseline.elapsedCycles * baselinePeriodNs;
  const candidateElapsedNs = result.candidate.elapsedCycles * candidatePeriodNs;
  if (![baselineElapsedNs, candidateElapsedNs].every(Number.isFinite))
    throw new RangeError(
      "Assumed elapsed time overflows the finite numeric range",
    );
  const improvementNs = baselineElapsedNs - candidateElapsedNs;
  const score = {
    status: "conditional",
    assumptions,
    baselineElapsedNs,
    candidateElapsedNs,
    improvementNs,
    improvementPercent:
      baselineElapsedNs > 0 ? (improvementNs / baselineElapsedNs) * 100 : null,
    speedup:
      candidateElapsedNs > 0 ? baselineElapsedNs / candidateElapsedNs : null,
    breakEvenCandidatePeriodNs:
      result.candidate.elapsedCycles > 0
        ? baselineElapsedNs / result.candidate.elapsedCycles
        : null,
  };
  if (
    [
      score.improvementPercent,
      score.speedup,
      score.breakEvenCandidatePeriodNs,
    ].some((value) => value !== null && !Number.isFinite(value))
  )
    throw new RangeError(
      "Assumed period ratio overflows the finite numeric range",
    );
  return score;
}
