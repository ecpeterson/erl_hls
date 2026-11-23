/** Focused saved-action navigation. Metadata selects existing graph members;
 * it never creates execution dependencies or establishes cross-build identity. */

/** Reject invalid navigation metadata before a partial selection reaches the UI. */
function requireValue(condition, message) {
  if (!condition) throw Error(`Action chain: ${message}`);
}

/** Require a nonempty, unique set of existing event references. */
function eventIds(model, ids, label) {
  requireValue(Array.isArray(ids) && ids.length > 0, `empty ${label}`);
  requireValue(new Set(ids).size === ids.length, `duplicate ${label}`);
  for (const id of ids)
    requireValue(model.events.has(id), `unknown ${label} event ${id}`);
}

/** Validate labels and graph references. The comparison key is producer-supplied
 * semantic correspondence, not a claim of native equivalence between captures. */
export function validateChain(model, chain) {
  requireValue(chain && typeof chain === "object", "invalid descriptor");
  for (const name of ["id", "title", "comparisonKey"])
    requireValue(
      typeof chain[name] === "string" && chain[name].length > 0,
      `missing ${name}`,
    );
  eventIds(model, chain.sources, "source");
  eventIds(model, chain.sinks, "sink");
  const targets = chainTargetMasks(model, chain);
  const incarnation = model.events.get(chain.sources[0]).incarnation;
  const epoch = model.epochs.get(incarnation);
  requireValue(
    Number.isSafeInteger(chain.firstCycle) &&
      Number.isSafeInteger(chain.endCycle) &&
      chain.firstCycle < chain.endCycle &&
      chain.firstCycle >= epoch.first_cycle &&
      chain.endCycle <= epoch.end_cycle,
    `invalid window ${chain.id}`,
  );
  requireValue(Array.isArray(chain.milestones ?? []), "invalid milestones");
  for (const milestone of chain.milestones ?? []) {
    requireValue(
      milestone &&
        typeof milestone.label === "string" &&
        milestone.label.length > 0,
      "invalid milestone label",
    );
    requireValue(
      model.events.has(milestone.event),
      `unknown milestone event ${milestone.event}`,
    );
  }
  for (const id of [
    ...chain.sources,
    ...chain.sinks,
    ...targets.keys(),
    ...(chain.milestones ?? []).map((row) => row.event),
  ]) {
    const event = model.events.get(id);
    requireValue(event.incarnation === incarnation, `cross-reset event ${id}`);
    requireValue(
      event.cycle >= chain.firstCycle && event.cycle < chain.endCycle,
      `event outside window ${id}`,
    );
  }
  requireValue(
    Array.isArray(chain.versions ?? []) &&
      new Set(chain.versions ?? []).size === (chain.versions ?? []).length,
    "invalid versions",
  );
  for (const id of chain.versions ?? [])
    requireValue(
      model.versions.get(id)?.incarnation === incarnation,
      `unknown or cross-reset version ${id}`,
    );
  if (chain.spatialBounds !== undefined) {
    const bounds = chain.spatialBounds;
    requireValue(
      bounds &&
        ["minX", "maxX", "minY", "maxY"].every((key) =>
          Number.isFinite(bounds[key]),
        ) &&
        bounds.minX < bounds.maxX &&
        bounds.minY < bounds.maxY,
      "invalid shared display bounds",
    );
    for (const cell of model.cells.values()) {
      if (!Number.isFinite(cell.x) || !Number.isFinite(cell.y)) continue;
      requireValue(
        cell.x >= bounds.minX &&
          cell.x <= bounds.maxX &&
          cell.y >= bounds.minY &&
          cell.y <= bounds.maxY,
        `shared display bounds exclude native cell ${cell.id}`,
      );
    }
  }
  return chain;
}

/** Validate a displayed bit subset without changing the actual recorded write.
 * Masks are navigation only; they never establish gate sensitization. */
export function chainTargetMasks(model, chain) {
  const targets = chain?.targets ?? [];
  requireValue(Array.isArray(targets), "invalid targets");
  const result = new Map();
  for (const target of targets) {
    const event = model.events.get(target?.event);
    requireValue(
      event?.access?.kind === "write",
      `target is not a write ${target?.event}`,
    );
    requireValue(!result.has(event.id), `duplicate target ${event.id}`);
    requireValue(
      typeof target.mask === "string" && /^0x[0-9a-f]+$/i.test(target.mask),
      `invalid target mask ${event.id}`,
    );
    const selected = BigInt(target.mask),
      written = BigInt(event.access.mask);
    const width = model.resources.get(event.access.resource).width;
    requireValue(
      selected > 0n &&
        selected < 1n << BigInt(width) &&
        (selected & written) === selected,
      `target mask outside recorded write ${event.id}`,
    );
    result.set(event.id, `0x${selected.toString(16).toUpperCase()}`);
  }
  return result;
}

/** Primary destinations are an explicit display scope, not bit-level causality.
 * Keeping the full event corridor separately preserves its control ancestry. */
export function chainCircuitSelection(
  chain,
  events,
  { onlyChain = true, includeContext = false } = {},
) {
  if (!chain || !onlyChain || includeContext || !chain.targets?.length)
    return events;
  const targets = new Set(chain.targets.map((target) => target.event));
  return events.filter((event) => targets.has(event.id));
}

/** Clip focused residence to recorded uses in this action, retaining global
 * lifetime evidence unchanged. Exact read masks exclude disjoint field uses;
 * absent masks/direct consumers remain possible uses with explicit uncertainty.
 * No per-bit dependency or dynamic hardware activity is inferred from a mask.
 */
export function chainStorageSegments(
  model,
  chain,
  trace,
  segments,
  { includeContext = false } = {},
) {
  const selected = new Set(trace.events.map((event) => event.id));
  if (includeContext)
    for (const edge of trace.boundaryInputs) selected.add(edge.source);
  const versions = new Set(
    includeContext ? trace.versions : trace.focusVersions,
  );
  const targets = chainTargetMasks(model, chain);
  const lastUses = new Map(),
    unresolved = [],
    excludedReads = [],
    unusedVersions = [];
  for (const version of versions) {
    const lifetime = model.lifetimes.get(version);
    if (!lifetime) continue;
    const width = model.resources.get(lifetime.resource).width;
    const fullMask = (1n << BigInt(width)) - 1n;
    const target = targets.get(lifetime.producer);
    const mask = target === undefined ? fullMask : BigInt(target);
    let last = null;
    for (const id of lifetime.uses) {
      if (!selected.has(id)) continue;
      const event = model.events.get(id),
        access = event.access;
      let useMask = null;
      if (
        access?.kind === "read_request" &&
        access.version === version &&
        access.read_mask !== undefined
      ) {
        requireValue(
          typeof access.read_mask === "string" &&
            /^0x[0-9a-f]+$/i.test(access.read_mask),
          `invalid read mask ${id}`,
        );
        useMask = BigInt(access.read_mask);
        requireValue(
          useMask > 0n && (useMask & fullMask) === useMask,
          `read mask outside word ${id}`,
        );
      }
      if (useMask !== null && (useMask & mask) === 0n) {
        excludedReads.push({ version, event: id });
        continue;
      }
      if (useMask === null && mask !== fullMask)
        unresolved.push({
          version,
          event: id,
          reason: "unknown_consumed_bits",
        });
      last = Math.max(last ?? event.cycle, event.cycle);
    }
    lastUses.set(version, last);
    if (last === null) unusedVersions.push(version);
  }
  return {
    unresolved,
    excludedReads,
    unusedVersions,
    lastUses,
    segments: segments.flatMap((segment) => {
      const last = lastUses.get(segment.version);
      if (last === undefined || last === null) return [];
      const toCycle = Math.min(segment.toCycle, last);
      const visibleToCycle = Math.min(segment.visibleToCycle, toCycle);
      if (segment.visibleFromCycle >= visibleToCycle) return [];
      return [
        {
          ...segment,
          toCycle,
          visibleToCycle,
          afterWindow: segment.afterWindow && visibleToCycle < toCycle,
          chainLastUseCycle: last,
        },
      ];
    }),
  };
}

/** Index explicit action definitions without hiding duplicate semantic keys. */
export function indexChains(model, chains = []) {
  requireValue(Array.isArray(chains), "invalid chains table");
  const ids = new Set(),
    keys = new Set();
  for (const chain of chains) {
    validateChain(model, chain);
    requireValue(!ids.has(chain.id), `duplicate id ${chain.id}`);
    requireValue(
      !keys.has(chain.comparisonKey),
      `duplicate comparison key ${chain.comparisonKey}`,
    );
    ids.add(chain.id);
    keys.add(chain.comparisonKey);
  }
  return new Map(chains.map((chain) => [chain.id, chain]));
}

/** Walk the bounded action interval without following resource chronology.
 * A full intersection avoids the arbitrary prefix of a bounded broad BFS. */
function reachable(model, seeds, chain, direction) {
  const visited = new Set(seeds),
    queue = [...seeds];
  const adjacency = direction === "forward" ? model.outgoing : model.incoming;
  for (let cursor = 0; cursor < queue.length; cursor++)
    for (const edge of adjacency.get(queue[cursor]) ?? []) {
      if (edge.kind === "resource_order") continue;
      const id = direction === "forward" ? edge.target : edge.source;
      const event = model.events.get(id);
      if (
        event.cycle < chain.firstCycle ||
        event.cycle >= chain.endCycle ||
        visited.has(id)
      )
        continue;
      visited.add(id);
      queue.push(id);
    }
  return visited;
}

/** Select every recorded path between the declared sources and sinks. Missing
 * connections remain isolated anchors with an unresolved disposition; external
 * inputs are disclosed separately, never silently incorporated as chain work. */
export function traceChain(model, definition) {
  const chain = validateChain(model, definition);
  const forward = reachable(model, chain.sources, chain, "forward");
  const backward = reachable(model, chain.sinks, chain, "backward");
  const corridor = new Set([...forward].filter((id) => backward.has(id)));
  const unresolved = {
    sources: chain.sources.filter((id) => !corridor.has(id)),
    sinks: chain.sinks.filter((id) => !corridor.has(id)),
    milestones: (chain.milestones ?? []).filter(
      (row) => !corridor.has(row.event),
    ),
  };
  const selected = new Set([
    ...corridor,
    ...chain.sources,
    ...chain.sinks,
    ...(chain.milestones ?? []).map((row) => row.event),
  ]);
  for (const id of chainTargetMasks(model, chain).keys())
    requireValue(selected.has(id), `target outside chain ${id}`);
  const edges = [],
    boundaryInputs = [],
    boundaryOutputs = [],
    roots = [];
  for (const id of selected) {
    for (const edge of model.incoming.get(id) ?? []) {
      if (edge.kind === "resource_order") continue;
      if (selected.has(edge.source)) edges.push(edge);
      else boundaryInputs.push(edge);
    }
    for (const edge of model.outgoing.get(id) ?? [])
      if (edge.kind !== "resource_order" && !selected.has(edge.target))
        boundaryOutputs.push(edge);
    for (const version of model.roots.get(id) ?? [])
      roots.push({ version, consumer: id });
  }
  const versions = new Set();
  for (const id of selected) {
    const event = model.events.get(id);
    for (const version of [...event.inputs, ...event.outputs])
      if (model.versions.get(version).storage) versions.add(version);
    if (event.access?.version) versions.add(event.access.version);
  }
  for (const id of chain.versions ?? [])
    requireValue(versions.has(id), `nominated version outside chain ${id}`);
  return {
    events: model.orderedEvents.filter((event) => selected.has(event.id)),
    edges,
    roots,
    versions: [...versions],
    focusVersions: chain.versions?.length ? chain.versions : [...versions],
    boundaryInputs,
    boundaryOutputs,
    unresolved,
    truncated: false,
    connected: Object.values(unresolved).every((rows) => rows.length === 0),
  };
}

/** Reuse only a unique explicit semantic key when changing implementation. */
export function matchingChain(model, comparisonKey) {
  if (!comparisonKey) return null;
  return (
    [...model.chains.values()].find(
      (chain) => chain.comparisonKey === comparisonKey,
    ) ?? null
  );
}

/** A shared display extent preserves tile scale without changing coordinates.
 * A caller may retain the explicit frame after clearing selection. Reject
 * cropping native geometry, including routes loaded after the selection clears. */
export function chainDisplayBounds(chain, nativeBounds, retainedBounds = null) {
  const bounds = chain?.spatialBounds ?? retainedBounds;
  if (!bounds) return nativeBounds;
  if (nativeBounds)
    requireValue(
      bounds.minX <= nativeBounds.minX &&
        bounds.maxX >= nativeBounds.maxX &&
        bounds.minY <= nativeBounds.minY &&
        bounds.maxY >= nativeBounds.maxY,
      "shared display bounds exclude native geometry",
    );
  return { ...bounds };
}
