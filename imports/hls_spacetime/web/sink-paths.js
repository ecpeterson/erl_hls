/** Per-sink explanations of independent SDF arc envelopes. Cached pin arrivals
 * remain the authority: these paths are not sensitized execution or STA slack. */
const caches = new WeakMap();
const SCOPES = new Set(["registered", "static"]);
const finite = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;
const close = (a, b) =>
  finite(a) && finite(b) && Math.abs(a - b) <= 1e-12 * Math.max(1, a, b);
const lexical = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
function check(ok, reason) {
  if (!ok) throw Error(`Sink paths: ${reason}`);
}
function cacheFor(index) {
  if (!caches.has(index))
    caches.set(index, { cones: new WeakMap(), corridors: new Map() });
  return caches.get(index);
}
function coneState(index, cone) {
  const cache = cacheFor(index).cones;
  if (!cache.has(cone))
    cache.set(cone, {
      positions: new Map(cone.pinIndices.map((pin, i) => [pin, i])),
      scopes: new Map(),
      graph: null,
    });
  return cache.get(cone);
}
function pinName(index, pin) {
  return typeof index.pinGeometry[pin]?.[3] === "string"
    ? index.pinGeometry[pin][3]
    : null;
}
function arrival(state, cone, scope, pin) {
  const position = state.positions.get(pin);
  check(position !== undefined, "pin outside cone");
  return cone.pinArrivals[scope][position];
}

/** Qualification is local to this selected sink. Missing timing at a sibling root
 * does not invalidate a finite arrival here; cycles/unsupported frontiers retain
 * the original cone-wide conservative rejection. No new bound is invented. */
function qualify(state, cone, pin, scope) {
  const reasons = [];
  if (cone.coverage.cyclic) reasons.push("cycle");
  if (cone.coverage.unsupportedFrontiers)
    reasons.push("unsupported_or_missing_frontier");
  const value = arrival(state, cone, scope, pin);
  if (reasons.length) return { status: "unknown", reasons, delayNs: null };
  if (finite(value)) return { status: "known", reasons, delayNs: value };
  if (value === "not_applicable")
    return {
      status: "not_applicable",
      reasons: [
        scope === "registered"
          ? "no_registered_launch_path"
          : "no_supported_launch_path",
      ],
      delayNs: null,
    };
  check(value === null, "invalid cached sink arrival");
  return {
    status: "unknown",
    reasons: ["unknown_sink_arrival"],
    delayNs: null,
  };
}

/** Enumerate every displayed role/sink, retaining distinct write occurrences and
 * unknown contributors. delayNs is a qualified maximum only when all applicable
 * cone contributions are known; knownDelayNs is separately labelled partial data.
 * Layers without operation associations retain sinks but claim no write owner. */
export function sinkRows(index, layers, { scope = "registered" } = {}) {
  check(SCOPES.has(scope), "invalid scope");
  const rows = new Map();
  for (const layer of layers) {
    const visible = new Map(layer.cones.map((cone) => [cone.id, cone]));
    for (const cone of layer.cones) {
      const state = coneState(index, cone);
      for (const pin of cone.rootPins) {
        const key = `${cone.role}/${pin}`;
        if (!rows.has(key))
          rows.set(key, {
            key,
            role: cone.role,
            pin,
            pinName: pinName(index, pin),
            writes: new Set(),
            cycles: new Set(),
            resources: new Set(),
            contributions: new Map(),
          });
        const row = rows.get(key);
        if (Number.isSafeInteger(layer.cycle)) row.cycles.add(layer.cycle);
        if (!row.contributions.has(cone.id))
          row.contributions.set(cone.id, {
            coneId: cone.id,
            ...qualify(state, cone, pin, scope),
          });
      }
    }
    for (const operation of layer.operations ?? []) {
      const write = index.writes.get(operation.event),
        event = index.model.events.get(operation.event);
      check(
        write && event?.access?.kind === "write",
        "missing write association",
      );
      for (const id of write.cones) {
        const cone = visible.get(index.cones[id].id);
        if (!cone) continue;
        for (const pin of cone.rootPins) {
          const row = rows.get(`${cone.role}/${pin}`);
          row.writes.add(event.id);
          row.resources.add(event.access.resource);
        }
      }
    }
  }
  return [...rows.values()]
    .map(({ writes, cycles, resources, contributions, ...row }) => {
      const values = [...contributions.values()].sort((a, b) =>
        lexical(a.coneId, b.coneId),
      );
      const known = values.filter((value) => value.status === "known"),
        unknown = values.filter((value) => value.status === "unknown");
      const knownDelayNs = known.reduce(
        (max, value) => Math.max(max ?? 0, value.delayNs),
        null,
      );
      const status = unknown.length
        ? "unknown"
        : known.length
          ? "known"
          : "not_applicable";
      const relevant =
        status === "unknown" ? unknown : status === "known" ? [] : values;
      const representative =
        status === "unknown"
          ? unknown[0]
          : status === "known"
            ? known.find((value) => close(value.delayNs, knownDelayNs))
            : values[0];
      return {
        ...row,
        scope,
        status,
        reasons: [
          ...new Set(relevant.flatMap((value) => value.reasons)),
        ].sort(),
        delayNs: status === "known" ? knownDelayNs : null,
        knownDelayNs,
        occurrences: writes.size,
        writeEvents: [...writes].sort(),
        cycles: [...cycles].sort((a, b) => a - b),
        resources: [...resources].sort(),
        coneIds: values.map((value) => value.coneId),
        representativeConeId: representative.coneId,
        contributions: values,
      };
    })
    .sort(
      (a, b) =>
        lexical(a.role, b.role) ||
        lexical(a.pinName ?? "", b.pinName ?? "") ||
        a.pin - b.pin,
    );
}

/** Build adjacency/topological order once per immutable prepared cone. Ordinary
 * sink listing never constructs this graph. Parallel arcs keep their identities. */
function graphFor(index, cone, state) {
  if (state.graph) return state.graph;
  const incoming = new Map(),
    outgoing = new Map(),
    degree = new Map(cone.pinIndices.map((pin) => [pin, 0]));
  for (const id of cone.arcIndices) {
    const [from, to] = index.arcGeometry[id];
    check(degree.has(from) && degree.has(to), "arc outside cone pins");
    if (!incoming.has(to)) incoming.set(to, []);
    if (!outgoing.has(from)) outgoing.set(from, []);
    incoming.get(to).push(id);
    outgoing.get(from).push(id);
    degree.set(to, degree.get(to) + 1);
  }
  const order = cone.pinIndices.filter((pin) => degree.get(pin) === 0);
  for (let i = 0; i < order.length; i++)
    for (const id of outgoing.get(order[i]) ?? []) {
      const to = index.arcGeometry[id][1];
      degree.set(to, degree.get(to) - 1);
      if (degree.get(to) === 0) order.push(to);
    }
  state.graph = {
    incoming,
    outgoing,
    order,
    cyclic: order.length !== cone.pinIndices.length,
  };
  return state.graph;
}

/** Source eligibility is structural. An unknown prefix does not become outside
 * scope. Predecessor choices are memoized so thousands of sinks share backtracks. */
function scopeFor(index, cone, state, scope) {
  if (state.scopes.has(scope)) return state.scopes.get(scope);
  const graph = graphFor(index, cone, state);
  const sources = new Set(
    cone.frontiers
      .filter(
        (frontier) => scope === "static" || frontier.kind === "sequential",
      )
      .map((frontier) => frontier.pin),
  );
  const reachable = new Set(sources),
    queue = [...sources];
  for (let i = 0; i < queue.length; i++)
    for (const id of graph.outgoing.get(queue[i]) ?? []) {
      const to = index.arcGeometry[id][1];
      if (!reachable.has(to)) {
        reachable.add(to);
        queue.push(to);
      }
    }
  const nativeNames = cone.pinIndices.every(
    (pin) => pinName(index, pin) !== null,
  );
  const order = (a, b) => {
    const left = index.arcGeometry[a],
      right = index.arcGeometry[b];
    return (
      (nativeNames
        ? lexical(pinName(index, left[0]), pinName(index, right[0])) ||
          lexical(pinName(index, left[1]), pinName(index, right[1]))
        : left[0] - right[0] || left[1] - right[1]) ||
      left[2] - right[2] ||
      a - b
    );
  };
  const result = {
    graph,
    sources,
    reachable,
    predecessors: new Map(),
    order,
    identityOrder: nativeNames ? "native_pin_names" : "numeric_pin_refs",
  };
  state.scopes.set(scope, result);
  return result;
}
function predecessor(index, cone, state, scoped, scope, pin) {
  if (!scoped.predecessors.has(pin)) {
    const choices = (scoped.graph.incoming.get(pin) ?? [])
      .filter((id) => {
        const [from, , , delay] = index.arcGeometry[id],
          head = arrival(state, cone, scope, from);
        return (
          finite(head) &&
          finite(delay) &&
          close(head + delay, arrival(state, cone, scope, pin))
        );
      })
      .sort(scoped.order);
    check(choices.length > 0, "no predecessor explains sink arrival");
    scoped.predecessors.set(pin, { arc: choices[0], tied: choices.length > 1 });
  }
  return scoped.predecessors.get(pin);
}

/** One chain is O(path length) after the shared predecessor cache. Zero-delay
 * chains terminate at a declared source; repeated pins reject stale cyclic data. */
function representative(index, cone, state, scoped, scope, sink, delayNs) {
  const reverse = [],
    visited = new Set();
  let pin = sink,
    branchingEncountered = false;
  while (!scoped.sources.has(pin)) {
    check(
      !visited.has(pin) && visited.size < cone.pinIndices.length,
      "backtrack exceeds acyclic cone",
    );
    visited.add(pin);
    const choice = predecessor(index, cone, state, scoped, scope, pin);
    branchingEncountered ||= choice.tied;
    reverse.push(choice.arc);
    pin = index.arcGeometry[choice.arc][0];
  }
  check(
    close(arrival(state, cone, scope, pin), 0),
    "source arrival is not zero",
  );
  const arcIndices = reverse.reverse();
  let netDelayNs = 0,
    logicDelayNs = 0,
    sum = 0;
  for (const id of arcIndices) {
    const [, , kind, delay] = index.arcGeometry[id];
    if (kind === 0) netDelayNs += delay;
    else logicDelayNs += delay;
    sum += delay;
  }
  check(
    close(sum, delayNs) && close(netDelayNs + logicDelayNs, delayNs),
    "representative sum disagrees with sink arrival",
  );
  return {
    sourcePin: pin,
    arcIndices,
    netDelayNs,
    logicDelayNs,
    branchingEncountered,
  };
}
function mergeDistance(distances, pin, candidate) {
  const old = distances.get(pin);
  if (!old) distances.set(pin, candidate);
  else {
    old.unknown ||= candidate.unknown;
    if (candidate.known !== null)
      old.known = Math.max(old.known ?? 0, candidate.known);
  }
}

/** Only an explicitly requested selected sink gets a reverse suffix pass. Costs
 * combine the cached eligible prefix, local arc, and sink-specific longest suffix.
 * A null eligible prefix/suffix stays unknown even if a finite alternative exists. */
function corridorCosts(index, cone, state, scoped, scope, sink, qualified) {
  const cache = cacheFor(index).corridors,
    key = JSON.stringify([cone.id, scope, sink]);
  if (cache.has(key)) return cache.get(key);
  const barrier = scoped.graph.cyclic || cone.coverage.unsupportedFrontiers;
  const suffix = new Map([[sink, { known: 0, unknown: false }]]);
  if (barrier) {
    const queue = [sink];
    for (let i = 0; i < queue.length; i++)
      for (const id of scoped.graph.incoming.get(queue[i]) ?? []) {
        const from = index.arcGeometry[id][0];
        if (!suffix.has(from)) {
          suffix.set(from, { known: null, unknown: true });
          queue.push(from);
        }
      }
  } else
    for (let i = scoped.graph.order.length - 1; i >= 0; i--) {
      const pin = scoped.graph.order[i];
      for (const id of scoped.graph.outgoing.get(pin) ?? []) {
        const [, to, , delay] = index.arcGeometry[id],
          tail = suffix.get(to);
        if (!tail) continue;
        const sum =
          tail.known !== null && delay !== null ? tail.known + delay : null;
        mergeDistance(suffix, pin, {
          known: finite(sum) ? sum : null,
          unknown: tail.unknown || delay === null || !finite(sum),
        });
      }
    }
  const costs = cone.arcIndices.map((arc) => {
    const [from, to, , delay] = index.arcGeometry[arc],
      tail = suffix.get(to);
    let status = "not_applicable",
      pathDelayNs = null,
      marginNs = null;
    if (tail && (barrier || scoped.reachable.has(from))) {
      const head = arrival(state, cone, scope, from);
      status = "unknown";
      if (
        !barrier &&
        finite(head) &&
        finite(delay) &&
        !tail.unknown &&
        finite(tail.known) &&
        finite(head + delay + tail.known)
      ) {
        status = "known";
        pathDelayNs = head + delay + tail.known;
        if (qualified.status === "known") {
          check(
            pathDelayNs < qualified.delayNs ||
              close(pathDelayNs, qualified.delayNs),
            "through-path exceeds sink arrival",
          );
          marginNs = Math.max(0, qualified.delayNs - pathDelayNs);
        }
      }
    }
    return { arc, status, pathDelayNs, marginNs };
  });
  // Bounded derived caching is not a data cap: oversized complete results return
  // uncached, and eviction never removes arcs from a report.
  if (costs.length <= 250000) {
    let rows = costs.length;
    for (const old of cache.values()) rows += old.length;
    while (cache.size && (cache.size >= 8 || rows > 250000)) {
      const oldest = cache.keys().next().value;
      rows -= cache.get(oldest).length;
      cache.delete(oldest);
    }
    cache.set(key, costs);
  }
  return costs;
}

/** Explain one selected role/sink using its cached arrival, independent of sibling
 * root status. With corridor=false (default), no suffix/per-arc report is built.
 * corridor=true retains every cone arc's disposition and the union of all arcs
 * on a source-to-this-sink path within marginNs of this sink's longest cost.
 * This union is not a claim that every recombination is itself near-longest.
 * Unknown alternatives remain separate; an unknown sink has no qualified longest
 * path/corridor, even if some per-arc alternatives have finite envelope costs.
 */
export function sinkPath(
  index,
  cone,
  pin,
  { scope = "registered", marginNs = 0, corridor = false } = {},
) {
  check(
    SCOPES.has(scope) && finite(marginNs) && typeof corridor === "boolean",
    "invalid scope/margin/corridor",
  );
  check(cone.rootPins.includes(pin), "selected pin is not a cone sink");
  const state = coneState(index, cone),
    qualified = qualify(state, cone, pin, scope);
  let scoped;
  if (qualified.status === "known" || corridor) {
    scoped = scopeFor(index, cone, state, scope);
    if (scoped.graph.cyclic && qualified.status !== "unknown") {
      qualified.status = "unknown";
      qualified.delayNs = null;
      qualified.reasons = ["cycle"];
    }
  }
  const result = {
    scope,
    role: cone.role,
    ...qualified,
    sourcePin: null,
    targetPin: pin,
    arcIndices: [],
    netDelayNs: null,
    logicDelayNs: null,
    ties: {
      branchingEncountered: false,
      representativeOnly: true,
      identityOrder: scoped?.identityOrder ?? "not_used",
    },
    marginNs,
    corridorComputed: corridor,
    corridorArcIds: [],
    unknownArcIds: [],
    arcCosts: [],
  };
  if (qualified.status === "known") {
    const path = representative(
      index,
      cone,
      state,
      scoped,
      scope,
      pin,
      qualified.delayNs,
    );
    result.sourcePin = path.sourcePin;
    result.arcIndices = path.arcIndices;
    result.netDelayNs = path.netDelayNs;
    result.logicDelayNs = path.logicDelayNs;
    result.ties.branchingEncountered = path.branchingEncountered;
  }
  if (corridor) {
    result.arcCosts = corridorCosts(
      index,
      cone,
      state,
      scoped,
      scope,
      pin,
      qualified,
    ).map((row) => ({
      ...row,
      inCorridor:
        row.marginNs !== null &&
        (row.marginNs <= marginNs || close(row.marginNs, marginNs)),
    }));
    result.corridorArcIds = result.arcCosts
      .filter((row) => row.inCorridor)
      .map((row) => row.arc);
    result.unknownArcIds = result.arcCosts
      .filter((row) => row.status === "unknown")
      .map((row) => row.arc);
  }
  return result;
}
