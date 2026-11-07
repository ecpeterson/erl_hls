/** Pure saved-recording indexes. These checks protect the view; they do not rerun
 * the producer's full validator or establish physical/dynamic equivalence. */

/** Reject a malformed projection with a concise, inspectable cause. */
function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

/** Index a table while rejecting duplicate identities instead of hiding records. */
function index(rows, label, key = "id") {
  requireValue(
    rows === undefined || Array.isArray(rows),
    `Invalid ${label} table`,
  );
  const result = new Map();
  for (const row of rows ?? []) {
    requireValue(
      row &&
        typeof row[key] === "string" &&
        row[key].length > 0 &&
        !result.has(row[key]),
      `Invalid or duplicate ${label}: ${row?.[key]}`,
    );
    result.set(row[key], row);
  }
  return result;
}

/** Append to a small fan-in/fan-out index. */
function append(map, key, value) {
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(value);
}

/** Compare the three content identities without relying on JSON key order. */
function sameBuild(left, right) {
  return ["source", "rtl", "observation"].every(
    (key) => left?.[key] === right?.[key],
  );
}

/** Check acyclicity over every recorded dependency class. Equal-cycle edges
 * can be valid, but a self-loop or a cycle is never an execution history.
 * Kahn's queue avoids recursion depth limits on long saved traces. */
function requireAcyclic(model) {
  const remaining = new Map([...model.events.keys()].map((id) => [id, 0]));
  for (const edge of model.edges)
    remaining.set(edge.target, remaining.get(edge.target) + 1);
  const ready = [...remaining]
    .filter(([, count]) => count === 0)
    .map(([id]) => id);
  for (let cursor = 0; cursor < ready.length; cursor++) {
    for (const edge of model.outgoing.get(ready[cursor]) ?? []) {
      const count = remaining.get(edge.target) - 1;
      remaining.set(edge.target, count);
      if (count === 0) ready.push(edge.target);
    }
  }
  requireValue(
    ready.length === model.events.size,
    "Dependency graph contains a cycle",
  );
}

/** Cycle counters must remain exactly representable in browser arithmetic. */
function validCycle(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/** Return only explicit logical associations, never actor-name inferred hardware. */
export function resourcesForEvent(event) {
  return [
    ...new Set([
      ...(event.resources ?? []),
      ...(event.access ? [event.access.resource] : []),
    ]),
  ];
}

/** Build reusable indexes once. Geometry remains one unique cell table regardless
 * of the number of displayed clocks. All dependency edges come from recorded
 * versions, read requests or explicit relations; chronology creates no edge. */
export function createModel(document) {
  requireValue(
    document?.format === "spacetime-view" && document.schema === 1,
    "Unsupported viewer projection",
  );
  const bundle = document.bundle;
  requireValue(
    bundle?.format === "spacetime" &&
      bundle.schema === 1 &&
      bundle.unit === "cycle",
    "Unsupported execution recording",
  );
  for (const table of ["events", "versions", "resources", "relations"]) {
    requireValue(
      Array.isArray(bundle[table]),
      `Missing or invalid ${table} table`,
    );
  }
  const capture = bundle.capture;
  requireValue(
    capture &&
      validCycle(capture.first_cycle) &&
      validCycle(capture.end_cycle) &&
      capture.first_cycle < capture.end_cycle &&
      typeof capture.complete === "boolean" &&
      Array.isArray(capture.observers) &&
      Array.isArray(capture.incarnations),
    "Invalid capture bounds",
  );
  for (const epoch of capture.incarnations) {
    requireValue(
      epoch &&
        validCycle(epoch.first_cycle) &&
        validCycle(epoch.end_cycle) &&
        epoch.first_cycle >= capture.first_cycle &&
        epoch.end_cycle <= capture.end_cycle &&
        epoch.first_cycle < epoch.end_cycle,
      `Invalid incarnation bounds: ${epoch?.id}`,
    );
  }
  const observers = index(capture.observers, "observer");
  for (const observer of observers.values()) {
    requireValue(
      Array.isArray(observer.gaps),
      `Invalid observer gaps: ${observer.id}`,
    );
    requireValue(
      !capture.complete || observer.gaps.length === 0,
      `Complete capture declares observer loss: ${observer.id}`,
    );
  }
  const events = index(bundle.events, "event");
  const versions = index(bundle.versions, "version");
  const resources = index(bundle.resources, "resource");
  const catalogue = document.catalogue ?? null;
  requireValue(
    !catalogue || sameBuild(bundle.build, catalogue.build),
    "Execution/physical build mismatch",
  );
  const cells = index(catalogue?.cells, "cell");
  const bindings = index(catalogue?.bindings, "binding", "resource");
  const epochs = index(bundle.capture.incarnations, "incarnation");
  const model = {
    document,
    bundle,
    catalogue,
    events,
    versions,
    resources,
    cells,
    bindings,
    epochs,
    orderedEvents: [...events.values()].sort(
      (a, b) => a.cycle - b.cycle || a.sequence - b.sequence,
    ),
    incoming: new Map(),
    outgoing: new Map(),
    roots: new Map(),
    consumers: new Map(),
    accesses: new Map(),
    storageUses: new Map(),
    lifetimes: new Map(),
    edges: [],
    resourceCoverage: index(
      document.coverage?.resource_associations,
      "resource coverage",
      "resource",
    ),
    geometryBounds: null,
  };
  const edgeKeys = new Set();
  const addEdge = (edge) => {
    const source = events.get(edge.source),
      target = events.get(edge.target);
    requireValue(
      source && target,
      `Missing dependency endpoint: ${edge.source} -> ${edge.target}`,
    );
    requireValue(
      source.incarnation === target.incarnation && source.cycle <= target.cycle,
      `Dependency crosses reset or runs backward: ${edge.source} -> ${edge.target}`,
    );
    const key = JSON.stringify([
      edge.source,
      edge.target,
      edge.kind,
      edge.version,
      edge.resource,
    ]);
    if (edgeKeys.has(key)) return;
    edgeKeys.add(key);
    model.edges.push(edge);
    append(model.incoming, edge.target, edge);
    append(model.outgoing, edge.source, edge);
  };
  for (const event of events.values()) {
    const epoch = epochs.get(event.incarnation);
    requireValue(
      validCycle(event.cycle) &&
        validCycle(event.sequence) &&
        epoch &&
        event.cycle >= epoch.first_cycle &&
        event.cycle < epoch.end_cycle,
      `Invalid event cycle/incarnation: ${event.id}`,
    );
    requireValue(
      Array.isArray(event.inputs) && Array.isArray(event.outputs),
      `Invalid event version lists: ${event.id}`,
    );
    requireValue(
      observers.has(event.observer),
      `Missing event observer: ${event.observer}`,
    );
    for (const resource of resourcesForEvent(event))
      requireValue(resources.has(resource), `Missing resource: ${resource}`);
    for (const id of event.inputs) {
      const version = versions.get(id);
      requireValue(
        version && version.incarnation === event.incarnation,
        `Missing or cross-reset input: ${id}`,
      );
      append(model.consumers, id, event.id);
      if (version.producer === "root") append(model.roots, event.id, version);
      else
        addEdge({
          source: version.producer,
          target: event.id,
          kind: "version",
          version: id,
          evidence: version.evidence,
        });
    }
    for (const id of event.outputs)
      requireValue(
        versions.get(id)?.producer === event.id,
        `Output producer mismatch: ${id}`,
      );
    if (event.access) {
      append(model.accesses, event.access.resource, event);
      recordStorageUse(model, event);
      if (event.access.kind === "read_result")
        addEdge({
          source: event.access.request,
          target: event.id,
          kind: "read_request",
          evidence: event.evidence,
        });
    }
  }
  for (const relation of bundle.relations) {
    requireValue(
      ["required", "resource_order"].includes(relation.kind),
      `Unknown relation: ${relation.kind}`,
    );
    addEdge({ ...relation });
  }
  requireAcyclic(model);
  for (const version of versions.values()) {
    if (version.producer !== "root")
      requireValue(
        events.get(version.producer)?.outputs.includes(version.id),
        `Missing version producer: ${version.id}`,
      );
    if (version.storage) {
      requireValue(
        resources.has(version.storage.resource),
        `Missing storage resource: ${version.id}`,
      );
      model.lifetimes.set(version.id, makeLifetime(model, version));
    }
  }
  const placed = [...cells.values()].filter(
    (cell) => Number.isFinite(cell.x) && Number.isFinite(cell.y),
  );
  if (placed.length)
    model.geometryBounds = placed.reduce(
      (box, cell) => ({
        minX: Math.min(box.minX, cell.x),
        maxX: Math.max(box.maxX, cell.x),
        minY: Math.min(box.minY, cell.y),
        maxY: Math.max(box.maxY, cell.y),
      }),
      { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity },
    );
  return model;
}

/** Index each access by the selected/replaced version once. A resource can
 * have arbitrarily many writes over time; residence lookup must not rescan
 * its complete history for every version. */
function recordStorageUse(model, event) {
  const { kind, before, version } = event.access;
  const buckets = {
    write: "replacements",
    read_request: "requests",
    read_result: "responses",
    hold: "holds",
  };
  const bucket = buckets[kind],
    id = kind === "write" ? before : version;
  requireValue(
    bucket && model.versions.has(id),
    `Invalid storage access version: ${event.id}`,
  );
  if (!model.storageUses.has(id)) model.storageUses.set(id, {});
  const uses = model.storageUses.get(id);
  if (!uses[bucket]) uses[bucket] = [];
  uses[bucket].push(event);
}

/** Identify recorded uses of the stored value. A hold merely observes residence;
 * a response uses the copy latched by its request, not the source word again.
 * Other explicit inputs (including preserved bits of a masked write) count.
 * Absence here means no recorded use, never proof of dead hardware state. */
function storageUseEvents(model, version, requests) {
  const ids = new Set([
    ...(model.consumers.get(version) ?? []),
    ...requests.map((event) => event.id),
  ]);
  return [...ids]
    .map((id) => model.events.get(id))
    .filter(
      (event) =>
        !(
          event.access?.version === version &&
          ["hold", "read_result"].includes(event.access.kind)
        ),
    );
}

/** Derive one word's pre-edge residence. A write at C is available at C+1;
 * the old version is still readable at its replacement edge under read-first.
 * Requests may outlive replacement, so responses are retained separately. */
function makeLifetime(model, version) {
  const producer = model.events.get(version.producer);
  const epoch = model.epochs.get(version.incarnation);
  requireValue(epoch, `Missing version incarnation: ${version.id}`);
  const {
    replacements = [],
    requests = [],
    responses = [],
    holds = [],
  } = model.storageUses.get(version.id) ?? {};
  requireValue(
    replacements.length <= 1,
    `Multiple replacements of stored version: ${version.id}`,
  );
  const replacement = replacements[0];
  const uses = storageUseEvents(model, version.id, requests);
  const returned = new Set(responses.map((event) => event.access.request));
  const resource = model.resources.get(version.storage.resource);
  const pending = requests
    .filter((event) => !returned.has(event.id))
    .map((event) => ({
      event: event.id,
      cycle: event.cycle,
      dueCycle: event.cycle + resource.read_latency,
      status:
        event.cycle + resource.read_latency < epoch.end_cycle
          ? "missing_response"
          : epoch.end_cycle < model.bundle.capture.end_cycle
            ? "reset_retired"
            : "capture_boundary",
    }));
  return {
    version: version.id,
    resource: version.storage.resource,
    address: version.storage.address,
    incarnation: version.incarnation,
    origin: version.origin,
    producer: producer?.id ?? null,
    writeCycle: producer?.cycle ?? null,
    firstCycle: producer ? producer.cycle + 1 : epoch.first_cycle,
    endCycle: replacement ? replacement.cycle + 1 : epoch.end_cycle,
    replacement: replacement?.id ?? null,
    requests: requests.map((event) => event.id),
    responses: responses.map((event) => event.id),
    holds: holds.map((event) => event.id),
    pending,
    uses: uses.map((event) => event.id),
    lastUseCycle: uses.reduce(
      (last, event) => Math.max(last ?? 0, event.cycle),
      null,
    ),
    continuity: model.bundle.capture.complete
      ? "within_declared_capture_scope"
      : "uncertain_capture",
    evidence: version.evidence,
  };
}

/** Select a half-open clock window and explicit actor/activation/operation/task
 * filters. An empty filter means all; operation is the recorded phase/action. */
export function eventsInWindow(model, options = {}) {
  const {
    firstCycle = model.bundle.capture.first_cycle,
    endCycle = model.bundle.capture.end_cycle,
  } = options;
  return model.orderedEvents.filter(
    (event) =>
      event.cycle >= firstCycle &&
      event.cycle < endCycle &&
      ["actor", "activation", "operation", "task", "incarnation"].every(
        (key) => !options[key] || event[key] === options[key],
      ),
  );
}

/** Traverse recorded dependencies without adding serial-observer or replacement
 * edges. Roots stop traversal; resource order is separately opt-in. Returns
 * event objects, event-to-event edges and {version, consumer} root stops. */
export function traceDependencies(
  model,
  eventId,
  { direction = "backward", includeOrder = false, maxEvents = 1000 } = {},
) {
  requireValue(model.events.has(eventId), `Unknown event: ${eventId}`);
  requireValue(
    ["backward", "forward"].includes(direction),
    `Unknown direction: ${direction}`,
  );
  requireValue(
    Number.isSafeInteger(maxEvents) && maxEvents > 0,
    "Invalid traversal bound",
  );
  const visited = new Set([eventId]),
    queue = [eventId],
    edges = [],
    roots = [];
  let truncated = false;
  for (let cursor = 0; cursor < queue.length; cursor++) {
    const id = queue[cursor];
    if (direction === "backward")
      for (const version of model.roots.get(id) ?? [])
        roots.push({ version, consumer: id });
    for (const edge of (direction === "backward"
      ? model.incoming
      : model.outgoing
    ).get(id) ?? []) {
      if (edge.kind === "resource_order" && !includeOrder) continue;
      const other = direction === "backward" ? edge.source : edge.target;
      if (!visited.has(other)) {
        if (visited.size >= maxEvents) {
          truncated = true;
          continue;
        }
        visited.add(other);
        queue.push(other);
      }
      edges.push(edge);
    }
  }
  return {
    events: queue.map((id) => model.events.get(id)),
    edges,
    roots,
    truncated,
  };
}

/** Return intersecting residences; clip only presentation coordinates, retaining
 * original producers and boundaries for off-window ancestry inspection. */
export function storageLifetimes(
  model,
  {
    firstCycle = model.bundle.capture.first_cycle,
    endCycle = model.bundle.capture.end_cycle,
    resource,
    incarnation,
  } = {},
) {
  return [...model.lifetimes.values()]
    .filter(
      (life) =>
        (!resource || life.resource === resource) &&
        (!incarnation || life.incarnation === incarnation) &&
        life.firstCycle < endCycle &&
        life.endCycle > firstCycle,
    )
    .map((life) => ({
      ...life,
      visibleFirstCycle: Math.max(firstCycle, life.firstCycle),
      visibleEndCycle: Math.min(endCycle, life.endCycle),
      beforeWindow: life.firstCycle < firstCycle,
      afterWindow: life.endCycle > endCycle,
    }));
}

/** Select a lifetime through explicit recorded event fields, not an inferred
 * owner. Producers and actual consumers/accesses may be outside the display
 * window; selecting their context does not assign their actor to the storage. */
function lifetimeMatchesEvents(model, lifetime, options) {
  const fields = ["actor", "activation", "operation", "task"].filter(
    (key) => options[key],
  );
  if (!fields.length) return true;
  const ids = new Set([
    ...(lifetime.producer ? [lifetime.producer] : []),
    ...(model.consumers.get(lifetime.version) ?? []),
    ...lifetime.requests,
    ...lifetime.responses,
    ...lifetime.holds,
  ]);
  return [...ids].some((id) => {
    const event = model.events.get(id);
    return event && fields.every((key) => event[key] === options[key]);
  });
}

/** Return grouped storage connections between captured pre-edge samples.
 * A write at C connects to its new word at C+1; retaining that word connects
 * its first available sample to its final available sample. Single-sample
 * words still have a write connection. Root words have no invented write.
 *
 * The requested window is half-open [firstCycle, endCycle). Segment from/to
 * fields are inclusive sample endpoints; visibleFromCycle/visibleToCycle clip
 * them to [firstCycle, endCycle-1]. Zero-length intersections are omitted.
 * At most two intervals are returned per stored version, never one per clock.
 * A version's lifetime remains attached for off-window history, uncertain
 * capture coverage and pending reads. These intervals add no causal edges.
 *
 * Optional resource/version(s)/incarnation selectors restrict storage identity.
 * Actor/activation/operation/task selectors match explicit associated events,
 * including off-window consumers; they never imply exclusive storage ownership.
 * With usedOnly, omit versions with no recorded use and end residence at the
 * last use, even outside the window. Holds and delayed read responses do not
 * extend it. The full lifetime and graph remain unchanged; omitted versions
 * are not proven dead, especially where capture/consumer coverage is partial.
 */
export function storageSegments(model, options = {}) {
  const {
    firstCycle = model.bundle.capture.first_cycle,
    endCycle = model.bundle.capture.end_cycle,
    resource,
    version,
    versions,
    incarnation,
    usedOnly = false,
  } = options;
  requireValue(
    validCycle(firstCycle) && validCycle(endCycle) && firstCycle < endCycle,
    "Invalid storage display window",
  );
  const selectedVersions = versions === undefined ? null : new Set(versions);
  const segments = [];
  const appendSegment = (kind, lifetime, fromCycle, toCycle) => {
    const visibleFromCycle = Math.max(firstCycle, fromCycle);
    const visibleToCycle = Math.min(endCycle - 1, toCycle);
    if (visibleFromCycle >= visibleToCycle) return;
    segments.push({
      kind,
      version: lifetime.version,
      resource: lifetime.resource,
      address: lifetime.address,
      incarnation: lifetime.incarnation,
      fromCycle,
      toCycle,
      visibleFromCycle,
      visibleToCycle,
      beforeWindow: fromCycle < firstCycle,
      afterWindow: toCycle >= endCycle,
      lifetime,
    });
  };
  for (const lifetime of model.lifetimes.values()) {
    if (
      (usedOnly && lifetime.lastUseCycle === null) ||
      (resource && lifetime.resource !== resource) ||
      (version && lifetime.version !== version) ||
      (selectedVersions && !selectedVersions.has(lifetime.version)) ||
      (incarnation && lifetime.incarnation !== incarnation) ||
      !lifetimeMatchesEvents(model, lifetime, options)
    )
      continue;
    const epoch = model.epochs.get(lifetime.incarnation);
    requireValue(
      lifetime.firstCycle >= epoch.first_cycle &&
        lifetime.firstCycle <= lifetime.endCycle &&
        lifetime.endCycle <= epoch.end_cycle,
      `Storage residence crosses reset or runs backward: ${lifetime.version}`,
    );
    if (lifetime.producer) {
      const producer = model.events.get(lifetime.producer);
      requireValue(
        producer.incarnation === lifetime.incarnation &&
          producer.access?.kind === "write" &&
          producer.access.after_version === lifetime.version &&
          producer.access.resource === lifetime.resource &&
          producer.access.address === lifetime.address,
        `Stored version has no matching write: ${lifetime.version}`,
      );
      // The last recorded D/enable has no following Q sample. Neither a reset
      // nor the capture boundary supplies that missing transfer observation.
      // A write-first read at C can consume the new value before Q at C+1;
      // if there is no later use, its dependency needs no storage bridge.
      if (
        lifetime.firstCycle < epoch.end_cycle &&
        (!usedOnly || lifetime.lastUseCycle >= lifetime.firstCycle)
      )
        appendSegment(
          "write",
          lifetime,
          lifetime.writeCycle,
          lifetime.firstCycle,
        );
    }
    const lastSample = usedOnly
      ? Math.min(lifetime.endCycle - 1, lifetime.lastUseCycle)
      : lifetime.endCycle - 1;
    appendSegment("hold", lifetime, lifetime.firstCycle, lastSample);
  }
  return segments;
}

/** Return supported cell positions and separate unresolved candidates. Bitwise
 * evidence may support part of an ambiguous word; it does not map actor logic. */
export function resourcePlacement(model, resourceId) {
  requireValue(
    model.resources.has(resourceId),
    `Unknown resource: ${resourceId}`,
  );
  const binding = model.bindings.get(resourceId);
  const resource = model.resources.get(resourceId);
  const bits = binding?.bits ?? [];
  const supported = bits.filter((bit) => bit.status === "supported");
  const established =
    binding &&
    !["ambiguous", "unmapped", "optimized_away"].includes(binding.disposition);
  const ids = new Set(
    bits.length
      ? supported.map((bit) => bit.cell)
      : established
        ? binding.cells
        : [],
  );
  const candidates = (binding?.cells ?? []).filter((id) => !ids.has(id));
  const cells = [...ids].map((id) => model.cells.get(id)).filter(Boolean);
  const coverage = model.resourceCoverage.get(resourceId) ?? {
    resource: resourceId,
    status: !model.catalogue
      ? "unmeasured"
      : !binding || binding.disposition === "unmapped"
        ? "unmapped"
        : binding.disposition === "ambiguous"
          ? "ambiguous"
          : "declared_binding",
    disposition: binding?.disposition ?? "unmapped",
    reason: !model.catalogue
      ? "No physical catalogue; logical placement only"
      : (binding?.evidence ?? "No supplied binding"),
  };
  return {
    resource: resourceId,
    binding: binding ?? null,
    coverage,
    cells,
    candidateCells: candidates.map((id) => model.cells.get(id)).filter(Boolean),
    supportedBits: supported.length,
    unknownBits: bits.filter((bit) => bit.status === "unknown").length,
    totalBits: resource.width ?? null,
    unplacedCells: cells.filter((cell) => cell.x === null || cell.y === null)
      .length,
  };
}

/** Aggregate event associations without implying its complete circuit footprint
 * or exclusive ownership. Unmapped resources remain in the result. */
export function eventPlacement(model, eventId) {
  const event = model.events.get(eventId);
  requireValue(event, `Unknown event: ${eventId}`);
  const resources = resourcesForEvent(event).map((id) =>
    resourcePlacement(model, id),
  );
  const cells = [
    ...new Map(
      resources.flatMap((row) => row.cells).map((cell) => [cell.id, cell]),
    ).values(),
  ];
  const statuses = new Set(resources.map((row) => row.coverage.status));
  const status = !resources.length
    ? "unresolved"
    : statuses.size === 1
      ? [...statuses][0]
      : "partial_value_correspondence";
  return {
    event: eventId,
    resources,
    cells,
    status,
    scope:
      "Logical resource association and finite stored-value correspondence; not a dynamic circuit footprint",
  };
}

/** Supply one inspector record, preserving source evidence, unknown inputs,
 * storage history, physical disposition and independent public annotations. */
export function eventDetails(model, eventId) {
  const event = model.events.get(eventId);
  requireValue(event, `Unknown event: ${eventId}`);
  return {
    event,
    inputs: event.inputs.map((id) => model.versions.get(id)),
    outputs: event.outputs.map((id) => model.versions.get(id)),
    predecessors: model.incoming.get(eventId) ?? [],
    successors: model.outgoing.get(eventId) ?? [],
    placement: eventPlacement(model, eventId),
    lifetimes: [...new Set([...event.inputs, ...event.outputs])]
      .map((id) => model.lifetimes.get(id))
      .filter(Boolean),
    annotations: (model.document.annotations?.public ?? []).filter(
      (annotation) => annotation.cycle === event.cycle,
    ),
    annotationScope:
      "Same-clock context only; public observations are not dependency endpoints",
  };
}
