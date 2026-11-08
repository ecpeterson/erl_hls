/** Static arrival-time layout of selected native timing arcs. Tile coordinates
 * and pin identities remain native; interpolation along schematic chord length
 * is a display convention, never measured propagation along a metal track. */
const caches = new WeakMap();
const SCOPES = new Set(["registered", "static"]);
const CACHE_ROWS = 1_000_000;
const CACHE_KEYS = 16;

function check(ok, reason) {
  if (!ok) throw Error(`Arrival circuits: ${reason}`);
}
function numeric(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}
function arrivalStatus(value) {
  return numeric(value)
    ? "known"
    : value === "not_applicable"
      ? "not_applicable"
      : "unknown";
}
function xy(index, pin) {
  const row = index.pinGeometry[pin];
  return row && Number.isFinite(row[1]) && Number.isFinite(row[2])
    ? { x: row[1], y: row[2] }
    : null;
}
function at(point, arrivalNs) {
  return {
    x: point.x,
    y: point.y,
    arrivalNs: numeric(arrivalNs) ? arrivalNs : null,
  };
}
function pointKey(point) {
  return JSON.stringify([point.x, point.y, point.arrivalNs]);
}
function sameValue(left, right) {
  return (
    left === right ||
    (numeric(left) &&
      numeric(right) &&
      Math.abs(left - right) <= 1e-12 * Math.max(1, left, right))
  );
}

/** A unique branch still needs all ordered coordinates before its end-to-end
 * delay can be interpolated. Intra-site chords are always schematic; other native
 * gap categories or a missing chord leave intermediate arrival positions unknown. */
function completeBranch(route, geometry, from, to) {
  const sameXY = (a, b) => a && b && a.x === b.x && a.y === b.y;
  return (
    route?.disposition === "resolved" &&
    !Object.entries(route.gapCounts ?? {}).some(
      ([kind, count]) => kind !== "intrasite" && count > 0,
    ) &&
    geometry.length > 0 &&
    sameXY(geometry[0].from, from) &&
    sameXY(geometry.at(-1).to, to) &&
    geometry.every((row, i) => i === 0 || sameXY(geometry[i - 1].to, row.from))
  );
}

/** Membership follows displayed writes, so native aliases never choose an owner
 * by traversal order. Clock/event IDs are deliberately absent from static caches. */
function memberships(index, layer) {
  const rows = new Map(layer.cones.map((cone) => [cone.id, new Set()]));
  for (const operation of layer.operations ?? []) {
    const write = index.writes.get(operation.event);
    const resource = index.model.events.get(operation.event)?.access?.resource;
    check(write && typeof resource === "string", "missing write destination");
    for (const coneId of write.cones)
      rows.get(index.cones[coneId].id)?.add(resource);
  }
  return [...rows]
    .map(([id, resources]) => [id, [...resources].sort()])
    .sort(([left], [right]) => left.localeCompare(right));
}

/** The cache describes the exact selected closure, not a caller-provided key.
 * Known cones outside the current layer are harmless; their geometry stays hidden. */
function selectedClosure(index, selection) {
  if (selection === null) return { choices: null, rows: null };
  check(selection instanceof Map, "selection must be a Map or null");
  const cones = new Map(index.cones.map((cone) => [cone.id, cone])),
    choices = new Map(),
    rows = [];
  for (const [id, choice] of selection) {
    const cone = cones.get(id);
    check(
      cone && choice?.arcIds instanceof Set && choice?.rootPins instanceof Set,
      "invalid selected cone",
    );
    const allowedArcs = new Set(cone.arcIndices),
      allowedRoots = new Set(cone.rootPins);
    const arcIds = [...choice.arcIds].sort((a, b) => a - b),
      rootPins = [...choice.rootPins].sort((a, b) => a - b);
    check(
      arcIds.every((arc) => allowedArcs.has(arc)) &&
        rootPins.every((pin) => allowedRoots.has(pin)),
      "selection outside cone",
    );
    check(
      choice.pathCosts === undefined || choice.pathCosts instanceof Map,
      "selected path costs must be a Map",
    );
    const costs =
      choice.pathCosts === undefined
        ? null
        : [...choice.pathCosts].sort(([a], [b]) => a - b);
    if (costs)
      check(
        costs.every(
          ([arc, value]) =>
            choice.arcIds.has(arc) &&
            (numeric(value) || value === null || value === "not_applicable"),
        ),
        "invalid selected path cost",
      );
    choices.set(id, {
      arcIds: new Set(arcIds),
      rootPins: new Set(rootPins),
      pathCosts: costs === null ? null : new Map(costs),
    });
    rows.push([id, arcIds, rootPins, costs]);
  }
  rows.sort(([left], [right]) => left.localeCompare(right));
  return { choices, rows };
}

/** Metadata unions retain exact contributing graph IDs. A known alternative
 * never fills an unknown timing or destination contribution. */
function contribution(target, source) {
  for (const key of ["arcIds", "pinIds", "coneIds", "roles", "resources"])
    for (const value of source[key] ?? []) target[key].add(value);
  if (source.delayKind) target.delayKinds.add(source.delayKind);
  target.computationUnknown ||= source.computationUnknown;
  target.timingUnknown ||= source.timingUnknown;
  if (numeric(source.pathDelayNs))
    target.pathDelayNs = Math.max(target.pathDelayNs ?? 0, source.pathDelayNs);
  if (source.localDelayNs !== undefined)
    target.localDelays.add(source.localDelayNs);
  target.contributors++;
}
function aggregate(row, source) {
  const result = {
    ...row,
    arcIds: new Set(),
    pinIds: new Set(),
    coneIds: new Set(),
    roles: new Set(),
    resources: new Set(),
    localDelays: new Set(),
    delayKinds: new Set(),
    computationUnknown: false,
    timingUnknown: false,
    pathDelayNs: null,
    contributors: 0,
  };
  contribution(result, source);
  return result;
}
function finished(row) {
  const {
    roles,
    resources,
    localDelays,
    delayKinds,
    arcIds,
    pinIds,
    coneIds,
    ...result
  } = row;
  const owners = [...resources].sort();
  return {
    ...result,
    role: roles.size === 1 ? [...roles][0] : "mixed",
    computationKey:
      !row.computationUnknown && owners.length === 1 ? owners[0] : null,
    computationShared: !row.computationUnknown && owners.length > 1,
    destinationResources: owners,
    arcIds: [...arcIds].sort((a, b) => a - b),
    pinIds: [...pinIds].sort((a, b) => a - b),
    coneIds: [...coneIds].sort(),
    localDelayNs: localDelays.size === 1 ? [...localDelays][0] : null,
    delayKind:
      delayKinds.size === 1
        ? [...delayKinds][0]
        : delayKinds.size > 1
          ? "mixed"
          : null,
  };
}

/** Exact XYZ/time geometry may share a glyph. Different arrival coordinates
 * cannot collapse just because their XY footprint coincides. */
function addSegment(rows, row, source) {
  const left = pointKey(row.from),
    right = pointKey(row.to);
  const forward = left <= right;
  const key = JSON.stringify([
    row.kind,
    forward ? left : right,
    forward ? right : left,
    row.status,
  ]);
  if (!rows.has(key))
    rows.set(key, aggregate({ ...row, direction: forward }, source));
  else {
    const previous = rows.get(key);
    previous.directionUnknown ||=
      previous.direction !== forward || row.directionUnknown;
    for (const key of ["geometryKind", "interpolation"])
      if (previous[key] !== row[key]) previous[key] = "mixed";
    contribution(previous, source);
  }
}
function addMark(rows, pin, point, value, source) {
  if (!point) return;
  const status = arrivalStatus(value),
    position = at(point, value);
  const key = JSON.stringify([pin, pointKey(position), status]);
  if (!rows.has(key))
    rows.set(
      key,
      aggregate(
        { pin, point: position, arrivalNs: position.arrivalNs, status },
        source,
      ),
    );
  else contribution(rows.get(key), source);
}

/** Shared native route rows are immutable. Cache eviction drops reusable display
 * work only; an oversized complete result is returned without caching it. */
function stateFor(index) {
  if (!caches.has(index))
    caches.set(index, {
      routes: new Map(index.routes.map((route) => [route.arc, route])),
      results: new Map(),
    });
  return caches.get(index);
}
function remember(cache, key, result) {
  const size = (value) =>
    value.segments.length +
    value.marks.length +
    value.roots.length +
    value.details.length;
  const rows = size(result);
  if (rows > CACHE_ROWS) return result;
  let total = rows;
  for (const value of cache.values()) total += size(value);
  while (cache.size && (cache.size >= CACHE_KEYS || total > CACHE_ROWS)) {
    const oldest = cache.keys().next().value;
    total -= size(cache.get(oldest));
    cache.delete(oldest);
  }
  cache.set(key, result);
  return result;
}

/** Compute one complete selected arrival layout. Propagation ends at A(from)+d;
 * a separate readiness link reaches the latest reconvergent A(to), never a storage
 * edge. Unknown arrival geometry has null times. Outside-scope arcs retain detail
 * rows but produce no propagation. Missing coordinates are counted, never filled.
 * Roots expose pin/role/destination/cone identities; the caller joins current write
 * events and sampling edges. Optional selection filters before aggregation; its
 * path-cost overrides never change local delays or cached pin arrivals.
 * No actual capture time is inferred here. */
export function arrivalCircuit(
  index,
  layer,
  { scope = "registered", includeUnresolved = true, selection = null } = {},
) {
  check(
    index &&
      Array.isArray(index.pinGeometry) &&
      Array.isArray(index.arcGeometry),
    "missing geometry tables",
  );
  check(
    SCOPES.has(scope) && typeof includeUnresolved === "boolean",
    "invalid display scope",
  );
  const closure = selectedClosure(index, selection),
    selectedCones =
      closure.choices === null
        ? layer.cones
        : layer.cones.filter((cone) => closure.choices.has(cone.id));
  const membershipRows = memberships(index, { ...layer, cones: selectedCones }),
    owners = new Map(membershipRows);
  const cache = stateFor(index),
    key = JSON.stringify([
      scope,
      includeUnresolved,
      membershipRows,
      closure.rows,
    ]);
  if (cache.results.has(key)) return cache.results.get(key);
  const segments = new Map(),
    marks = new Map(),
    roots = new Map(),
    details = new Map();
  const summary = {
    arcContributions: 0,
    inputSegments: 0,
    filteredSegments: 0,
    unlocatedArcs: 0,
    geometryUnavailableArcs: 0,
    unknownReadiness: 0,
  };
  const unavailable = new Set(),
    unlocated = new Set(),
    incomplete = new Set();
  const emit = (row, source) => {
    summary.inputSegments++;
    addSegment(segments, row, source);
  };
  for (const cone of selectedCones) {
    const choice = closure.choices?.get(cone.id),
      selectedRoots = choice?.rootPins ?? new Set(cone.rootPins),
      touchedPins = choice ? new Set(selectedRoots) : null;
    if (choice)
      for (const arcId of choice.arcIds) {
        const arc = index.arcGeometry[arcId];
        check(arc?.length === 4, "invalid selected arc geometry");
        touchedPins.add(arc[0]);
        touchedPins.add(arc[1]);
      }
    const resources = owners.get(cone.id),
      pinArrivals = cone.pinArrivals?.[scope],
      costs = cone.pathDelays?.[scope];
    check(
      pinArrivals?.length === cone.pinIndices.length &&
        costs?.length === cone.arcIndices.length,
      "unaligned cone timing arrays",
    );
    const arrivals = new Map(
      cone.pinIndices.map((pin, position) => [pin, pinArrivals[position]]),
    );
    const base = {
      coneIds: [cone.id],
      roles: [cone.role],
      resources,
      computationUnknown: resources.length === 0,
    };
    for (const pin of cone.pinIndices) {
      if (touchedPins && !touchedPins.has(pin)) continue;
      const value = arrivals.get(pin);
      addMark(marks, pin, xy(index, pin), value, {
        ...base,
        pinIds: [pin],
        timingUnknown: value === null,
      });
    }
    for (const pin of selectedRoots) {
      const point = xy(index, pin),
        value = arrivals.get(pin),
        status = arrivalStatus(value);
      const rootKey = JSON.stringify([pin, cone.role, value]);
      const source = { ...base, pinIds: [pin], timingUnknown: value === null };
      if (!roots.has(rootKey))
        roots.set(
          rootKey,
          aggregate(
            {
              pin,
              point: point ? at(point, value) : null,
              arrivalNs: numeric(value) ? value : null,
              status,
              located: Boolean(point),
            },
            source,
          ),
        );
      else contribution(roots.get(rootKey), source);
    }
    cone.arcIndices.forEach((arcId, position) => {
      if (choice && !choice.arcIds.has(arcId)) return;
      summary.arcContributions++;
      const arc = index.arcGeometry[arcId];
      check(
        arc?.length === 4 && [0, 1].includes(arc[2]),
        "invalid arc geometry",
      );
      const [fromPin, toPin, type, delay] = arc;
      const from = xy(index, fromPin),
        to = xy(index, toPin);
      const head = arrivals.get(fromPin),
        tail = arrivals.get(toPin),
        cost = choice?.pathCosts?.has(arcId)
          ? choice.pathCosts.get(arcId)
          : costs[position];
      const outside = cost === "not_applicable" || head === "not_applicable";
      const via =
        numeric(head) && numeric(delay) && Number.isFinite(head + delay)
          ? head + delay
          : null;
      const known = !outside && numeric(head) && numeric(via);
      const status = outside ? "not_applicable" : known ? "known" : "unknown";
      if (known && numeric(tail))
        check(
          via <= tail || sameValue(via, tail),
          "target arrival precedes propagation",
        );
      const source = {
        ...base,
        arcIds: [arcId],
        pinIds: [fromPin, toPin],
        localDelayNs: delay,
        delayKind: type === 0 ? "net" : "logic",
        pathDelayNs: numeric(cost) ? cost : null,
        timingUnknown: !outside && cost === null,
      };
      const detail = {
        arc: arcId,
        fromPin,
        toPin,
        kind: type === 0 ? "net" : "logic",
        status,
        arrivalFromNs: numeric(head) ? head : null,
        arrivalViaNs: via,
        arrivalToNs: numeric(tail) ? tail : null,
        delayNs: delay,
        located: Boolean(from && to),
        arrivalUnknown: !outside && (!known || !numeric(tail)),
      };
      if (!details.has(arcId)) details.set(arcId, aggregate(detail, source));
      else {
        const previous = details.get(arcId);
        for (const field of ["arrivalFromNs", "arrivalViaNs", "arrivalToNs"])
          if (!sameValue(previous[field], detail[field])) {
            previous[field] = null;
            previous.arrivalUnknown = true;
          }
        if (previous.status !== detail.status) previous.status = "unknown";
        previous.arrivalUnknown ||= detail.arrivalUnknown;
        contribution(previous, source);
      }
      for (const pin of [fromPin, toPin]) {
        addMark(marks, pin, xy(index, pin), arrivals.get(pin), {
          ...source,
          pinIds: [pin],
        });
        if (selectedRoots.has(pin)) {
          const rootKey = JSON.stringify([pin, cone.role, arrivals.get(pin)]);
          contribution(roots.get(rootKey), source);
        }
      }
      if (outside) return;
      if (!from || !to) unlocated.add(arcId);
      let geometry,
        completeGeometry = true;
      if (type === 1)
        geometry = from && to ? [{ from, to, kind: "logic" }] : [];
      else {
        const route = cache.routes.get(arcId);
        geometry = (route?.primitives ?? [])
          .map((id) => index.primitives[id])
          .filter((row) => row?.type === "segments");
        completeGeometry = completeBranch(route, geometry, from, to);
        if (!completeGeometry) incomplete.add(arcId);
      }
      if (
        !geometry.length ||
        (!includeUnresolved &&
          geometry.every((row) => row.kind === "unresolved"))
      )
        unavailable.add(arcId);
      // Visibility must not redistribute delay: fractions use the complete
      // retained branch, including unresolved chords that may be hidden.
      const lengths = geometry.map((row) =>
        Math.hypot(row.to.x - row.from.x, row.to.y - row.from.y),
      );
      const total = lengths.reduce((sum, length) => sum + length, 0);
      let traversed = 0;
      geometry.forEach((row, i) => {
        const start = total ? traversed / total : i / geometry.length;
        traversed += lengths[i];
        const end = total ? traversed / total : (i + 1) / geometry.length;
        if (!includeUnresolved && row.kind === "unresolved") {
          summary.filteredSegments++;
          return;
        }
        const located = known && completeGeometry && row.kind !== "unresolved";
        emit(
          {
            from: at(row.from, located ? head + delay * start : null),
            to: at(row.to, located ? head + delay * end : null),
            kind: located ? "propagation" : "unknown",
            status: located
              ? "known"
              : row.kind === "unresolved"
                ? "unresolved_geometry"
                : !completeGeometry
                  ? "incomplete_geometry"
                  : "unknown_arrival",
            directionUnknown: row.kind === "unresolved",
            geometryKind: row.kind,
            interpolation:
              type === 1
                ? "native_logic_arc_endpoints"
                : "display_chord_length_fraction",
          },
          source,
        );
      });
      if (known && numeric(tail) && tail > via && !sameValue(tail, via) && to)
        emit(
          {
            from: at(to, via),
            to: at(to, tail),
            kind: "readiness",
            status: "known",
            interpolation: "latest_input_readiness_not_storage",
          },
          source,
        );
      else if (known && !numeric(tail)) summary.unknownReadiness++;
    });
  }
  const segmentRows = [...segments.values()].map((row) => {
    const { direction, ...result } = finished(row);
    return result;
  });
  const detailRows = [...details.values()]
    .map(finished)
    .sort((a, b) => a.arc - b.arc);
  Object.assign(summary, {
    arcs: detailRows.length,
    knownArcs: detailRows.filter((row) => row.status === "known").length,
    unknownArcs: detailRows.filter((row) => row.status === "unknown").length,
    outsideArcs: detailRows.filter((row) => row.status === "not_applicable")
      .length,
    unlocatedArcs: unlocated.size,
    geometryUnavailableArcs: unavailable.size,
    geometryIncompleteArcs: incomplete.size,
    mergedSegments: summary.inputSegments - segmentRows.length,
    propagationSegments: segmentRows.filter((row) => row.kind === "propagation")
      .length,
    readinessSegments: segmentRows.filter((row) => row.kind === "readiness")
      .length,
    unknownSegments: segmentRows.filter((row) => row.kind === "unknown").length,
  });
  return remember(cache.results, key, {
    segments: segmentRows,
    marks: [...marks.values()].map(finished),
    roots: [...roots.values()].map(finished),
    details: detailRows,
    summary,
  });
}
