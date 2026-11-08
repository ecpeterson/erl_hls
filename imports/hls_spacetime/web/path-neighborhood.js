/** Compare nearby visible sink paths using retained static timing and placement.
 * The family is structural: nearby installed cells and net fanout do not establish
 * switching, congestion or a causal explanation for routing delay. */
import { sinkRows, sinkPath } from "./sink-paths.js";
import { selectedSinkPath } from "./sink-view.js";

const caches = new WeakMap();
const RESULT_KEYS = 8;
const finite = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;
const close = (left, right) =>
  Math.abs(left - right) <= 1e-12 * Math.max(1, left, right);

/** Native tile positions are optional; missing coordinates never become zero. */
function point(index, pin) {
  const row = index.pinGeometry[pin];
  return row && Number.isFinite(row[1]) && Number.isFinite(row[2])
    ? { x: row[1], y: row[2] }
    : null;
}
function inside(region, value) {
  return Boolean(
    region &&
      value &&
      Number.isFinite(value.x) &&
      Number.isFinite(value.y) &&
      value.x >= region.minX &&
      value.x <= region.maxX &&
      value.y >= region.minY &&
      value.y <= region.maxY,
  );
}
function pinName(index, pin) {
  return index.pinGeometry[pin]?.[3] ?? null;
}

/** Adjacency spans every represented net arc, including hidden/unrelated cones.
 * Parallel records for the same driver/target count as one physical load pin. */
function cacheFor(index) {
  if (!caches.has(index)) {
    const drivers = new Map();
    for (const [from, to, kind] of index.arcGeometry) {
      if (kind !== 0) continue;
      if (!drivers.has(from)) drivers.set(from, new Set());
      drivers.get(from).add(to);
    }
    caches.set(index, { drivers, layers: new WeakMap() });
  }
  return caches.get(index);
}
function layerCache(cache, index, layers, scope) {
  if (!cache.layers.has(layers)) cache.layers.set(layers, new Map());
  const scopes = cache.layers.get(layers);
  if (!scopes.has(scope))
    scopes.set(scope, {
      rows: sinkRows(index, layers, { scope }),
      cones: new Map(
        layers.flatMap((layer) => layer.cones.map((cone) => [cone.id, cone])),
      ),
      results: new Map(),
    });
  return scopes.get(scope);
}
function remember(cache, key, value) {
  while (cache.size >= RESULT_KEYS) cache.delete(cache.keys().next().value);
  cache.set(key, value);
  return value;
}

/** Bounds include every located native pin on the selected representative chain.
 * A rectangle is a selection region, not an estimate of occupied routing area. */
function pathRegion(index, path, paddingTiles) {
  const pins = new Set([path.sourcePin, path.targetPin]);
  for (const id of path.arcIndices) {
    const [from, to] = index.arcGeometry[id];
    pins.add(from);
    pins.add(to);
  }
  const positions = [...pins].map((pin) => point(index, pin)).filter(Boolean);
  if (!positions.length) return null;
  const bounds = {
    minX: Infinity,
    maxX: -Infinity,
    minY: Infinity,
    maxY: -Infinity,
  };
  for (const p of positions) {
    bounds.minX = Math.min(bounds.minX, p.x);
    bounds.maxX = Math.max(bounds.maxX, p.x);
    bounds.minY = Math.min(bounds.minY, p.y);
    bounds.maxY = Math.max(bounds.maxY, p.y);
  }
  bounds.minX -= paddingTiles;
  bounds.maxX += paddingTiles;
  bounds.minY -= paddingTiles;
  bounds.maxY += paddingTiles;
  if (!Object.values(bounds).every(Number.isFinite))
    throw new RangeError("Path neighborhood bounds overflow");
  return bounds;
}

/** Compare graph identities, not coincident pixels. Prefix time counts each
 * ordered arc once and stops at the first divergence from the chosen chain. */
function overlap(index, path, selected) {
  const chosen = new Set(selected.arcIndices);
  let sharedPrefixArcs = 0,
    sharedPrefixNs = 0;
  if (path.sourcePin === selected.sourcePin)
    for (
      let i = 0;
      i < Math.min(path.arcIndices.length, selected.arcIndices.length);
      i++
    ) {
      if (path.arcIndices[i] !== selected.arcIndices[i]) break;
      sharedPrefixArcs++;
      sharedPrefixNs += index.arcGeometry[path.arcIndices[i]][3];
    }
  return {
    sharedArcCount: new Set(path.arcIndices.filter((id) => chosen.has(id)))
      .size,
    sharedPrefixArcs,
    sharedPrefixNs,
  };
}

/** Union all qualified cone contributions for one role/sink. The displayed
 * representative may be one of several tied paths; it is never every alternative. */
function contribute(index, cones, member, scope, selection) {
  const memberArcs = new Set();
  let representatives = 0;
  for (const id of member.coneIds) {
    const cone = cones.get(id);
    if (
      !cone ||
      cone.role !== member.role ||
      !cone.rootPins.includes(member.pin)
    )
      continue;
    const path = sinkPath(index, cone, member.pin, { scope });
    if (path.status !== "known") continue;
    representatives++;
    if (!selection.has(id))
      selection.set(id, {
        arcIds: new Set(),
        rootPins: new Set(),
        pathCosts: new Map(),
      });
    const selected = selection.get(id);
    selected.rootPins.add(member.pin);
    for (const arc of path.arcIndices) {
      memberArcs.add(arc);
      selected.arcIds.add(arc);
      selected.pathCosts.set(
        arc,
        Math.max(selected.pathCosts.get(arc) ?? 0, path.delayNs),
      );
    }
  }
  return { memberArcs, representatives };
}

/** Full represented driver loads are independent of family and region filters.
 * familySinkPins counts outgoing target pins on family representative chains,
 * not write events or unique destination registers. */
function fanoutRows(index, adjacency, used, region) {
  return [...used]
    .map(([pin, family]) => {
      const sinks = [...(adjacency.get(pin) ?? [])]
        .sort((a, b) => a - b)
        .map((target) => {
          const position = point(index, target);
          return {
            pin: target,
            name: pinName(index, target),
            point: position,
            insideRegion: inside(region, position),
          };
        });
      return {
        pin,
        name: pinName(index, pin),
        point: point(index, pin),
        sinks,
        familySinkPins: family.size,
        totalSinkPins: sinks.length,
      };
    })
    .sort((a, b) => b.totalSinkPins - a.totalSinkPins || a.pin - b.pin);
}

/** Find every visible qualified sink within the selected path's tile rectangle
 * and absolute timing tolerance. All roles may qualify. Input indexes/layers and
 * returned cached collections are immutable by contract. Unknown/outside-scope
 * or unlocated sinks are counted separately and never admitted by guessed values.
 * Context includes every installed catalogue cell in the rectangle, irrespective
 * of event visibility; coincident cell locations retain separate identities.
 * Cache eviction discards reusable work only, never truncates a result. */
export function pathNeighborhood(
  index,
  layers,
  sink,
  { scope = "registered", marginNs = 0.1, paddingTiles = 12 } = {},
) {
  if (
    !["registered", "static"].includes(scope) ||
    !finite(marginNs) ||
    !finite(paddingTiles)
  )
    throw new RangeError("Invalid path neighborhood scope, margin or padding");
  const cache = cacheFor(index),
    state = layerCache(cache, index, layers, scope),
    key = JSON.stringify([sink?.key ?? null, marginNs, paddingTiles]);
  if (state.results.has(key)) return state.results.get(key);
  const selected = state.rows.find((row) => row.key === sink?.key) ?? null;
  const summary = {
    status: "no_selection",
    scope,
    marginNs,
    paddingTiles,
    visibleSinks: state.rows.length,
    knownSinks: state.rows.filter((row) => row.status === "known").length,
    unknownSinks: state.rows.filter((row) => row.status === "unknown").length,
    outsideScopeSinks: state.rows.filter(
      (row) => row.status === "not_applicable",
    ).length,
    unlocatedSinks: state.rows.filter((row) => !point(index, row.pin)).length,
    outsideRegionSinks: 0,
    outsideMarginSinks: 0,
    unavailablePaths: 0,
    members: 0,
    memberWriteAssociations: 0,
    memberClocks: 0,
    arcs: 0,
    sharedArcs: 0,
    familyCells: 0,
    contextCells: 0,
    unlocatedCells: 0,
    familyCellsOutsideRegion: 0,
    drivers: 0,
    representedFanoutConnections: 0,
    membersWithPathTies: 0,
    additionalConeRepresentatives: 0,
    representativeOnly: true,
    selectedDelayNs: selected?.delayNs ?? null,
  };
  const result = {
    region: null,
    members: [],
    selection: new Map(),
    arcUse: new Map(),
    cells: [],
    fanouts: [],
    summary,
  };
  const done = () => remember(state.results, key, result);
  if (!selected) return done();
  if (selected.status !== "known") {
    summary.status =
      selected.status === "not_applicable"
        ? "outside_scope_selection"
        : "unknown_selection";
    return done();
  }
  if (!point(index, selected.pin)) {
    summary.status = "unlocated_selection";
    return done();
  }
  const selectedPath = selectedSinkPath(index, selected, { scope });
  if (!selectedPath) {
    summary.status = "unavailable_selected_path";
    return done();
  }
  result.region = pathRegion(index, selectedPath, paddingTiles);
  if (!result.region) {
    summary.status = "unlocated_selected_path";
    return done();
  }
  summary.status = "known";
  const catalogue = index.model.catalogue?.cells ?? [];
  const catalogueIds = new Set(catalogue.map((cell) => cell.id));
  const familyCells = new Set(),
    usedDrivers = new Map(),
    writeEvents = new Set(),
    clocks = new Set();
  const addPinCell = (pin) => {
    // Prepared native cell indexes need not equal catalogue array positions.
    // The retained canonical pin name is exactly <native cell>/<port>.
    const name = index.pinGeometry[pin]?.[3];
    const cell = name?.slice(0, name.lastIndexOf("/"));
    if (catalogueIds.has(cell)) familyCells.add(cell);
  };
  for (const row of state.rows) {
    if (row.status !== "known" || !point(index, row.pin)) continue;
    if (!inside(result.region, point(index, row.pin))) {
      summary.outsideRegionSinks++;
      continue;
    }
    const gap = Math.abs(row.delayNs - selected.delayNs);
    if (gap > marginNs && !close(gap, marginNs)) {
      summary.outsideMarginSinks++;
      continue;
    }
    const path =
      row.key === selected.key
        ? selectedPath
        : selectedSinkPath(index, row, { scope });
    if (!path) {
      summary.unavailablePaths++;
      continue;
    }
    const member = {
      ...row,
      path,
      point: point(index, row.pin),
      sourcePoint: point(index, path.sourcePin),
      ...overlap(index, path, selectedPath),
    };
    result.members.push(member);
    for (const id of row.writeEvents) writeEvents.add(id);
    for (const cycle of row.cycles) clocks.add(cycle);
    if (path.ties.branchingEncountered) summary.membersWithPathTies++;
    const { memberArcs, representatives } = contribute(
      index,
      state.cones,
      member,
      scope,
      result.selection,
    );
    summary.additionalConeRepresentatives += Math.max(0, representatives - 1);
    addPinCell(path.sourcePin);
    addPinCell(row.pin);
    for (const arc of memberArcs) {
      result.arcUse.set(arc, (result.arcUse.get(arc) ?? 0) + 1);
      const [from, to, kind] = index.arcGeometry[arc];
      addPinCell(from);
      addPinCell(to);
      if (kind === 0) {
        if (!usedDrivers.has(from)) usedDrivers.set(from, new Set());
        usedDrivers.get(from).add(to);
      }
    }
  }
  result.members.sort(
    (a, b) => b.delayNs - a.delayNs || a.key.localeCompare(b.key),
  );
  catalogue.forEach((cell, i) => {
    const located = Number.isFinite(cell.x) && Number.isFinite(cell.y);
    if (!located) summary.unlocatedCells++;
    if (inside(result.region, cell))
      result.cells.push({
        index: i,
        cell,
        kind: familyCells.has(cell.id) ? "family" : "context",
      });
    else if (familyCells.has(cell.id)) summary.familyCellsOutsideRegion++;
  });
  result.fanouts = fanoutRows(index, cache.drivers, usedDrivers, result.region);
  Object.assign(summary, {
    members: result.members.length,
    memberWriteAssociations: writeEvents.size,
    memberClocks: clocks.size,
    arcs: result.arcUse.size,
    sharedArcs: [...result.arcUse.values()].filter((n) => n > 1).length,
    familyCells: result.cells.filter((row) => row.kind === "family").length,
    contextCells: result.cells.filter((row) => row.kind === "context").length,
    drivers: result.fanouts.length,
    representedFanoutConnections: result.fanouts.reduce(
      (n, row) => n + row.totalSinkPins,
      0,
    ),
  });
  return done();
}
