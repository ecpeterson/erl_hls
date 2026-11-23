/** Hypothetical register boundaries over complete selected-sink fan-in. Costs
 * reuse saved independent SDF envelopes; no physical retiming is performed. */
const caches = new WeakMap();
const finite = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;
const sorted = (values) => [...values].sort((a, b) => a - b);
const close = (a, b) => Math.abs(a - b) <= 1e-12 * Math.max(1, a, b);
function check(ok, message) {
  if (!ok) throw Error(`Candidate cut: ${message}`);
}
function point(index, pin) {
  const [, x, y] = index.pinGeometry[pin];
  return Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
}
function identity(index, pin) {
  return { pin, name: index.pinGeometry[pin][3], point: point(index, pin) };
}
function adjacent(edges) {
  const incoming = new Map(),
    outgoing = new Map();
  for (const [id, from, to] of edges) {
    if (!incoming.has(to)) incoming.set(to, []);
    if (!outgoing.has(from)) outgoing.set(from, []);
    incoming.get(to).push([id, from]);
    outgoing.get(from).push([id, to]);
  }
  return { incoming, outgoing };
}
function topological(pins, edges) {
  const { outgoing } = adjacent(edges);
  const degree = new Map([...pins].map((pin) => [pin, 0]));
  for (const [, , to] of edges) degree.set(to, degree.get(to) + 1);
  const order = [...pins].filter((pin) => !degree.get(pin));
  for (let i = 0; i < order.length; i++)
    for (const [, to] of outgoing.get(order[i]) ?? []) {
      degree.set(to, degree.get(to) - 1);
      if (!degree.get(to)) order.push(to);
    }
  return order.length === pins.size ? order : null;
}
function closure(seeds, adjacency) {
  const found = new Set(seeds),
    queue = [...seeds];
  for (let i = 0; i < queue.length; i++)
    for (const [, next] of adjacency.get(queue[i]) ?? [])
      if (!found.has(next)) {
        found.add(next);
        queue.push(next);
      }
  return found;
}

/** Cache only complete results within a bounded population budget. Oversized
 * analyses remain complete but uncached; immutable source indexes own the cache. */
function remember(index, key, result) {
  if (!caches.has(index)) caches.set(index, new Map());
  const cache = caches.get(index),
    size = result.includedArcIds.length;
  if (size > 250000) return result;
  let total = size;
  for (const row of cache.values()) total += row.includedArcIds.length;
  while (cache.size && (cache.size >= 8 || total > 250000)) {
    const first = cache.keys().next().value;
    total -= cache.get(first).includedArcIds.length;
    cache.delete(first);
  }
  cache.set(key, result);
  return result;
}

/** Analyze all visible contributing cones for one role/native sink. Combinational
 * cells are indivisible units; Q launch pins and the selected D/control pin remain
 * separate boundary units even when they belong to the same sequential cell.
 * A unit enters stage 1 only if its latest eligible arrival is <= threshold and
 * every eligible predecessor is already there. Sources are before, sink after.
 *
 * Crossing net arcs are cut immediately after their driver; their entire saved
 * delay belongs to stage 2. Distinct driver pins count bits, not fanout loads.
 * Stage 2 is recomputed from zero at those drivers, including direct-source
 * alignment registers. Excluded side inputs keep scoped estimates conditional.
 *
 * Returns known/unknown/not_applicable with complete selected arc identities.
 * Unknown eligible timing, unsupported boundaries, pin/unit cycles or inconsistent
 * saved arrivals produce no numeric cut estimate. Malformed options/indices throw.
 * The FF count is a lower bound excluding tags, valid/reset and other actor state;
 * one added logical boundary is not a legality, throughput or frequency claim. */
export function candidateCut(
  index,
  layers,
  sink,
  { scope = "registered", thresholdNs } = {},
) {
  check(
    ["registered", "static"].includes(scope) && finite(thresholdNs),
    "invalid scope/threshold",
  );
  check(
    index &&
      Array.isArray(index.pinGeometry) &&
      Array.isArray(index.arcGeometry),
    "missing prepared graph",
  );
  check(
    Array.isArray(layers) &&
      sink &&
      Number.isSafeInteger(sink.pin) &&
      index.pinGeometry[sink.pin],
    "invalid sink/layers",
  );
  const cones = [
    ...new Map(
      layers
        .flatMap((layer) => layer.cones)
        .filter(
          (cone) => cone.role === sink.role && cone.rootPins.includes(sink.pin),
        )
        .map((cone) => [cone.id, cone]),
    ).values(),
  ].sort((a, b) => a.id.localeCompare(b.id));
  const key = JSON.stringify([
    scope,
    thresholdNs,
    sink.role,
    sink.pin,
    cones.map((cone) => cone.id),
  ]);
  if (caches.get(index)?.has(key)) return caches.get(index).get(key);
  const report = {
    kind: "hypothetical_register_cut",
    scope,
    thresholdNs,
    sink: { ...identity(index, sink.pin), role: sink.role },
    status: "unknown",
    reason: null,
    reasons: [],
    originalDelayNs: null,
    stage1DelayNs: null,
    stage2DelayNs: null,
    signalBits: null,
    crossingSignals: 0,
    crossingFanout: 0,
    alignmentSourceBits: 0,
    alignmentComplete: false,
    alignmentScope: "eligible_launch_signals_only",
    addedBoundaryEdges: 1,
    crossings: [],
    sideInputs: [],
    beforeArcIds: [],
    afterArcIds: [],
    crossingArcIds: [],
    includedArcIds: [],
    eligibleArcIds: [],
    outsideArcIds: [],
    beforePins: [],
    afterPins: [],
    selection: new Map(),
    exclusions: [
      "clock_to_q",
      "setup",
      "clock_skew",
      "new_register_and_routing_cost",
      "tags_valid_reset_and_other_actor_state",
      "functional_retiming_legality",
    ],
  };
  const fail = (reason, status = "unknown") => {
    report.status = status;
    report.reason = reason;
    report.reasons = [reason];
    return remember(index, key, report);
  };
  if (!cones.length) return fail("sink_not_visible", "not_applicable");
  const allArcs = sorted(new Set(cones.flatMap((cone) => cone.arcIndices)));
  const edges = allArcs.map((id) => {
    const arc = index.arcGeometry[id];
    check(
      arc?.length === 4 &&
        index.pinGeometry[arc[0]] &&
        index.pinGeometry[arc[1]] &&
        [0, 1].includes(arc[2]) &&
        (arc[3] === null || finite(arc[3])),
      "invalid native arc",
    );
    return [id, arc[0], arc[1]];
  });
  const ancestry = closure([sink.pin], adjacent(edges).incoming);
  const relevant = edges.filter(([, , to]) => ancestry.has(to));
  report.includedArcIds = relevant.map(([id]) => id);
  const relevantIds = new Set(report.includedArcIds);
  for (const cone of cones)
    report.selection.set(cone.id, {
      arcIds: new Set(cone.arcIndices.filter((id) => relevantIds.has(id))),
      rootPins: new Set([sink.pin]),
    });
  const frontiers = new Map();
  for (const cone of cones)
    for (const row of cone.frontiers)
      if (ancestry.has(row.pin)) {
        if (frontiers.has(row.pin) && frontiers.get(row.pin) !== row.kind)
          return fail("conflicting_frontier");
        frontiers.set(row.pin, row.kind);
      }
  if (cones.some((cone) => cone.coverage.cyclic)) return fail("cycle");
  if (
    cones.some((cone) => cone.coverage.unsupportedFrontiers) ||
    [...frontiers.values()].some(
      (kind) => !["sequential", "external", "constant"].includes(kind),
    )
  )
    return fail("unsupported_or_missing_frontier");
  const order = topological(ancestry, relevant);
  if (!order) return fail("cycle");
  const fullAdjacency = adjacent(relevant);
  if (
    [...ancestry].some(
      (pin) => !fullAdjacency.incoming.has(pin) && !frontiers.has(pin),
    )
  )
    return fail("missing_frontier");
  if ([...frontiers.keys()].some((pin) => fullAdjacency.incoming.has(pin)))
    return fail("frontier_has_incoming_arc");
  const launches = new Set(
    [...frontiers]
      .filter(([, kind]) => scope === "static" || kind === "sequential")
      .map(([pin]) => pin),
  );
  const reachable = closure(launches, fullAdjacency.outgoing);
  if (!reachable.has(sink.pin))
    return fail("no_eligible_launch_path", "not_applicable");
  if (launches.has(sink.pin)) return fail("sink_is_launch_frontier");
  const eligible = relevant.filter(([, from]) => reachable.has(from));
  report.eligibleArcIds = eligible.map(([id]) => id);
  report.outsideArcIds = relevant
    .filter(([, from]) => !reachable.has(from))
    .map(([id]) => id);
  if (eligible.some(([id]) => index.arcGeometry[id][3] === null))
    return fail("unknown_eligible_timing");
  const incoming = adjacent(eligible).incoming,
    arrivals = new Map([...launches].map((pin) => [pin, 0]));
  for (const pin of order)
    if (reachable.has(pin) && !launches.has(pin)) {
      let maximum = 0;
      for (const [id, from] of incoming.get(pin) ?? [])
        maximum = Math.max(
          maximum,
          arrivals.get(from) + index.arcGeometry[id][3],
        );
      if (!finite(maximum)) return fail("nonfinite_arrival");
      arrivals.set(pin, maximum);
    }
  for (const cone of cones) {
    const saved = cone.pinArrivals[scope][cone.pinIndices.indexOf(sink.pin)];
    if (saved === "not_applicable") continue;
    if (!finite(saved)) return fail("unknown_saved_sink_arrival");
    if (!close(saved, arrivals.get(sink.pin)))
      return fail("inconsistent_saved_sink_arrival");
  }
  const combinational = new Set();
  for (const [id, from, to] of eligible)
    if (index.arcGeometry[id][2] === 1) {
      const cell = index.pinGeometry[from][0];
      if (
        cell === null ||
        cell !== index.pinGeometry[to][0] ||
        launches.has(from) ||
        launches.has(to) ||
        from === sink.pin ||
        to === sink.pin
      )
        return fail("unsupported_logic_boundary");
      combinational.add(cell);
    }
  const unitFor = (pin) =>
    launches.has(pin) || pin === sink.pin
      ? `boundary/${pin}`
      : combinational.has(index.pinGeometry[pin][0])
        ? `cell/${index.pinGeometry[pin][0]}`
        : `pin/${pin}`;
  const units = new Map();
  for (const pin of order)
    if (reachable.has(pin)) {
      const id = unitFor(pin);
      if (!units.has(id))
        units.set(id, { pins: [], arrival: 0, predecessors: new Set() });
      units.get(id).pins.push(pin);
      units.get(id).arrival = Math.max(
        units.get(id).arrival,
        arrivals.get(pin),
      );
    }
  const unitEdges = [],
    seenEdges = new Set();
  for (const [id, from, to] of eligible) {
    const a = unitFor(from),
      b = unitFor(to);
    if (a === b) continue;
    const key = JSON.stringify([a, b]);
    if (!seenEdges.has(key)) {
      seenEdges.add(key);
      unitEdges.push([id, a, b]);
    }
    units.get(b).predecessors.add(a);
  }
  const unitOrder = topological(new Set(units.keys()), unitEdges);
  if (!unitOrder) return fail("indivisible_cell_cycle");
  const before = new Set(),
    launchUnits = new Set([...launches].map(unitFor));
  for (const id of unitOrder) {
    const unit = units.get(id);
    if (
      launchUnits.has(id) ||
      (id !== unitFor(sink.pin) &&
        unit.arrival <= thresholdNs &&
        [...unit.predecessors].every((from) => before.has(from)))
    )
      before.add(id);
  }
  const cut = new Map();
  for (const [id, from, to] of eligible) {
    const a = before.has(unitFor(from)),
      b = before.has(unitFor(to));
    if (!a && b) return fail("cut_backedge");
    if (a && b) report.beforeArcIds.push(id);
    else {
      report.afterArcIds.push(id);
      if (a) {
        if (index.arcGeometry[id][2] !== 0)
          return fail("cut_inside_combinational_cell");
        report.crossingArcIds.push(id);
        if (!cut.has(from))
          cut.set(from, {
            fromPin: from,
            name: index.pinGeometry[from][3],
            point: point(index, from),
            originalArrivalNs: arrivals.get(from),
            toPins: new Set(),
            arcIds: [],
            alignmentSource:
              launches.has(from) && frontiers.get(from) !== "constant",
            requiresRegister: frontiers.get(from) !== "constant",
          });
        cut.get(from).toPins.add(to);
        cut.get(from).arcIds.push(id);
      }
    }
  }
  if (!cut.size) return fail("no_crossing_signals");
  const stage2 = new Map();
  for (const pin of order)
    if (reachable.has(pin) && !before.has(unitFor(pin))) {
      let maximum = 0;
      for (const [id, from] of incoming.get(pin) ?? []) {
        const prefix = before.has(unitFor(from)) ? 0 : stage2.get(from);
        maximum = Math.max(maximum, prefix + index.arcGeometry[id][3]);
      }
      if (!finite(maximum)) return fail("nonfinite_second_stage");
      stage2.set(pin, maximum);
    }
  // Excluded source timing is not filled with zero. Follow its first entry into
  // eligible circuitry to disclose which stage needs independently aligned input.
  const sideStages = new Map();
  for (let i = order.length - 1; i >= 0; i--) {
    const pin = order[i];
    if (reachable.has(pin))
      sideStages.set(pin, before.has(unitFor(pin)) ? 1 : 2);
    else {
      let mask = 0;
      for (const [, to] of fullAdjacency.outgoing.get(pin) ?? [])
        mask |= sideStages.get(to) ?? 0;
      sideStages.set(pin, mask);
    }
  }
  for (const [pin, kind] of frontiers)
    if (!launches.has(pin)) {
      const stages = sideStages.get(pin) ?? 0;
      report.sideInputs.push({
        ...identity(index, pin),
        kind,
        feedsStage1: Boolean(stages & 1),
        feedsStage2: Boolean(stages & 2),
        alignmentRequired: Boolean(stages & 2) && kind !== "constant",
        status: "outside_registered_scope",
      });
    }
  report.sideInputs.sort((a, b) => a.pin - b.pin);
  report.crossings = [...cut.values()]
    .map((row) => ({ ...row, toPins: sorted(row.toPins) }))
    .sort((a, b) => a.fromPin - b.fromPin);
  report.beforePins = sorted(
    [...reachable].filter((pin) => before.has(unitFor(pin))),
  );
  report.afterPins = sorted(
    [...reachable].filter((pin) => !before.has(unitFor(pin))),
  );
  report.stage1DelayNs = report.crossings.reduce(
    (max, row) => Math.max(max, row.originalArrivalNs),
    0,
  );
  report.stage2DelayNs = stage2.get(sink.pin);
  report.originalDelayNs = arrivals.get(sink.pin);
  report.crossingSignals = report.crossings.length;
  report.signalBits = report.crossings.filter(
    (row) => row.requiresRegister,
  ).length;
  report.crossingFanout = report.crossings.reduce(
    (sum, row) => sum + row.toPins.length,
    0,
  );
  report.alignmentSourceBits = report.crossings.filter(
    (row) => row.alignmentSource,
  ).length;
  report.alignmentComplete = !report.sideInputs.length;
  report.status = "known";
  return remember(index, key, report);
}
