/** Display-only unions at the available tile-coordinate resolution. Native
 * identities remain in the source paint; an aggregate is not a native object. */
const TYPES = ["tiles", "pips", "cells", "segments"];
const SCOPES = ["registered", "static"];
const cache = new WeakMap();

function check(ok, reason) {
  if (!ok) throw Error(`Circuit display: ${reason}`);
}
function point(value) {
  check(
    value && Number.isFinite(value.x) && Number.isFinite(value.y),
    "invalid point",
  );
  return value;
}
function change(counts, key, delta) {
  const count = (counts.get(key) ?? 0) + delta;
  if (count) counts.set(key, count);
  else counts.delete(key);
}

/** A removable maximum avoids rescanning every active route at each sweep edge. */
class Maximum {
  counts = new Map();
  heap = [];

  change(value, delta) {
    const previous = this.counts.get(value) ?? 0;
    change(this.counts, value, delta);
    if (delta < 0 || previous) return;
    let i = this.heap.length;
    this.heap.push(value);
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.heap[parent] >= value) break;
      this.heap[i] = this.heap[parent];
      i = parent;
    }
    this.heap[i] = value;
  }

  value() {
    while (this.heap.length && !this.counts.has(this.heap[0])) {
      const tail = this.heap.pop();
      if (!this.heap.length) break;
      let i = 0;
      while (i * 2 + 1 < this.heap.length) {
        const left = i * 2 + 1,
          right = left + 1,
          child =
            right < this.heap.length && this.heap[right] > this.heap[left]
              ? right
              : left;
        if (this.heap[child] <= tail) break;
        this.heap[i] = this.heap[child];
        i = child;
      }
      this.heap[i] = tail;
    }
    return this.heap.length ? this.heap[0] : null;
  }
}

/** Count metadata contributors so entering/leaving intervals are order independent.
 * Unknown ownership dominates; an inapplicable timing scope contributes nothing. */
class Contributors {
  count = 0;
  roles = new Map();
  owners = new Map();
  boundaries = new Map();
  kinds = new Map();
  directions = new Map();
  shared = 0;
  unknown = 0;
  unplaced = 0;
  costs = Object.fromEntries(
    SCOPES.map((scope) => [
      scope,
      {
        applicable: 0,
        unknown: 0,
        maximum: new Maximum(),
      },
    ]),
  );

  change({ row, direction = 0, physical = true }, delta) {
    this.count += delta;
    change(this.roles, typeof row.role === "string" ? row.role : null, delta);
    change(this.boundaries, row.boundary ?? null, delta);
    change(this.kinds, row.kind ?? null, delta);
    change(this.directions, direction, delta);
    const hasOwner =
      typeof row.computationKey === "string" && row.computationKey.length;
    if (row.computationUnknown || (!row.computationShared && !hasOwner))
      this.unknown += delta;
    else if (row.computationShared) this.shared += delta;
    else change(this.owners, row.computationKey, delta);
    if (!physical) this.unplaced += delta;
    for (const scope of SCOPES) {
      if (row[`${scope}PathApplicable`] === false) continue;
      const state = this.costs[scope],
        value = row[`${scope}PathDelayNs`],
        known =
          typeof value === "number" && Number.isFinite(value) && value >= 0;
      state.applicable += delta;
      if (known) state.maximum.change(value, delta);
      if (!known || row[`${scope}PathTimingUnknown`]) state.unknown += delta;
    }
  }

  metadata() {
    const row = {
      contributors: this.count,
      role: this.roles.size === 1 ? this.roles.keys().next().value : "mixed",
      computationKey:
        !this.unknown && !this.shared && this.owners.size === 1
          ? this.owners.keys().next().value
          : null,
      computationShared:
        !this.unknown && (this.shared > 0 || this.owners.size > 1),
      computationUnknown: this.unknown > 0,
    };
    for (const scope of SCOPES) {
      const state = this.costs[scope];
      row[`${scope}PathDelayNs`] = state.maximum.value();
      row[`${scope}PathTimingUnknown`] = state.unknown > 0;
      row[`${scope}PathApplicable`] = state.applicable > 0;
    }
    return row;
  }

  segment(from, to) {
    const directionUnknown = this.directions.has(0) || this.directions.size > 1,
      reverse = !directionUnknown && this.directions.has(-1),
      kind = this.kinds.has("unresolved")
        ? "unresolved"
        : this.kinds.has("site")
          ? "site"
          : "node";
    return {
      ...this.metadata(),
      from: reverse ? to : from,
      to: reverse ? from : to,
      kind,
      directionUnknown,
      schematic: true,
    };
  }
}

function pointKey(p) {
  return `${p.x}/${p.y}`;
}
function coalescePoints(rows, type) {
  const groups = new Map();
  for (const row of rows) {
    const p = point(row.point),
      key = pointKey(p);
    if (!groups.has(key))
      groups.set(key, { x: p.x, y: p.y, active: new Contributors() });
    groups.get(key).active.change({ row, physical: p.physical === true }, 1);
  }
  return [...groups.values()].map(({ x, y, active }) => {
    const result = {
      ...active.metadata(),
      point: { x, y, physical: active.unplaced === 0 },
    };
    if (type === "cells") {
      result.boundaries = [...active.boundaries.keys()]
        .filter((value) => value !== null)
        .sort();
      result.boundary =
        active.boundaries.size === 1
          ? active.boundaries.keys().next().value
          : "mixed";
    }
    return result;
  });
}

/** Axis-aligned routes share a line sweep; diagonals only share exact endpoints.
 * No near-point snapping, arbitrary intersections or invented bends are used. */
function coalesceSegments(rows) {
  const axes = new Map(),
    diagonals = new Map();
  let zeroLengthSegments = 0;
  for (const row of rows) {
    const a = point(row.from),
      b = point(row.to);
    check(
      ["node", "site", "unresolved"].includes(row.kind),
      "invalid segment kind",
    );
    if (a.x === b.x && a.y === b.y) {
      zeroLengthSegments++;
      continue;
    }
    const axis = a.y === b.y ? "x" : a.x === b.x ? "y" : null,
      ordered = a.x < b.x || (a.x === b.x && a.y < b.y),
      from = ordered ? a : b,
      to = ordered ? b : a,
      entry = {
        row,
        direction: row.directionUnknown ? 0 : ordered ? 1 : -1,
        physical: a.physical === true && b.physical === true,
      };
    if (!axis) {
      const key = `${pointKey(from)}>${pointKey(to)}`;
      if (!diagonals.has(key))
        diagonals.set(key, { from, to, active: new Contributors() });
      diagonals.get(key).active.change(entry, 1);
      continue;
    }
    const fixed = axis === "x" ? a.y : a.x,
      key = `${axis}/${fixed}`;
    if (!axes.has(key)) axes.set(key, { axis, fixed, edges: new Map() });
    const edges = axes.get(key).edges;
    for (const [coordinate, side] of [
      [from[axis], "starts"],
      [to[axis], "ends"],
    ]) {
      if (!edges.has(coordinate))
        edges.set(coordinate, { starts: [], ends: [] });
      edges.get(coordinate)[side].push(entry);
    }
  }
  const result = [];
  for (const { axis, fixed, edges } of axes.values()) {
    const coordinates = [...edges.keys()].sort((a, b) => a - b),
      active = new Contributors();
    for (let i = 0; i < coordinates.length - 1; i++) {
      const coordinate = coordinates[i],
        edge = edges.get(coordinate);
      for (const entry of edge.ends) active.change(entry, -1);
      for (const entry of edge.starts) active.change(entry, 1);
      if (!active.count) continue;
      const p = (value) => ({
        x: axis === "x" ? value : fixed,
        y: axis === "y" ? value : fixed,
        physical: active.unplaced === 0,
      });
      result.push(active.segment(p(coordinate), p(coordinates[i + 1])));
    }
  }
  for (const { from, to, active } of diagonals.values()) {
    const p = ({ x, y }) => ({ x, y, physical: active.unplaced === 0 });
    result.push(active.segment(p(from), p(to)));
  }
  return { rows: result, zeroLengthSegments };
}

/** Coalesce immutable paint for one displayed clock before assigning colors.
 * Contributions and timing remain available; only coincident display geometry
 * is combined. Unresolved visibility is applied before aggregation, so a missing
 * route cannot hide resolved contributors. Both visibility choices are cached.
 * All connecting spans remain schematic, even when their endpoints align. */
export function circuitDisplay(paint, { includeUnresolved = true } = {}) {
  check(paint && typeof paint === "object", "missing paint");
  check(
    typeof includeUnresolved === "boolean",
    "invalid unresolved visibility",
  );
  const cached = cache.get(paint)?.get(includeUnresolved);
  if (cached) return cached;
  for (const type of TYPES)
    check(Array.isArray(paint[type]), `missing ${type}`);
  const selectedSegments = includeUnresolved
    ? paint.segments
    : paint.segments.filter((row) => row.kind !== "unresolved");
  const { rows: segments, zeroLengthSegments } =
      coalesceSegments(selectedSegments),
    result = { ...paint, segments };
  for (const type of TYPES.slice(0, 3))
    result[type] = coalescePoints(paint[type], type);
  result.displaySummary = {
    input: Object.fromEntries(TYPES.map((type) => [type, paint[type].length])),
    output: Object.fromEntries(
      TYPES.map((type) => [type, result[type].length]),
    ),
    zeroLengthSegments,
    filteredUnresolvedSegments: paint.segments.length - selectedSegments.length,
  };
  if (!cache.has(paint)) cache.set(paint, new Map());
  cache.get(paint).set(includeUnresolved, result);
  return result;
}
