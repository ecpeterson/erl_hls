/** Screen-space picking for explicit sink, event and storage interaction modes.
 * Projection establishes frustum visibility, not visibility through opaque
 * geometry. No mode falls back to another class of evidence or caps overlaps.
 */
import { arrivalCoordinate } from "./arrival-layout.js";

export const PICK_RADII = Object.freeze({ sinks: 14, events: 8, storage: 7 });
const KINDS = Object.freeze({
  sinks: "sink",
  events: "event",
  storage: "storage",
});
const TARGET_KINDS = new Set(Object.values(KINDS));
const worldPoint = (point) =>
  Array.isArray(point) && point.length === 3 && point.every(Number.isFinite);
const screenPoint = (point) =>
  point?.visible === true &&
  [point.x, point.y, point.depth].every(Number.isFinite);
const lexical = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/** Turn already filtered arrival roots into explicit sink endpoint targets.
 * Only known, located roots have pick geometry; unknown/outside-scope timing
 * never receives a guessed position. Role/pin identifies the inspector sink;
 * cycle and retained arrival distinguish its potentially multiple display
 * representations. The common arrival budget is shared with rendered geometry.
 */
export function sinkPickTargets(
  circuit,
  { cycle, budgetNs, point, world, pinName } = {},
) {
  arrivalCoordinate(cycle, 0, budgetNs);
  if (
    !circuit ||
    ![point, world, pinName].every((fn) => typeof fn === "function")
  )
    throw new TypeError(
      "Sink picking requires a circuit and coordinate/name functions",
    );
  const result = [];
  for (const root of circuit.roots ?? []) {
    if (
      root.status !== "known" ||
      root.located !== true ||
      !root.point ||
      ![root.point.x, root.point.y].every(Number.isFinite) ||
      !Number.isFinite(root.arrivalNs) ||
      root.arrivalNs < 0
    )
      continue;
    const { role, pin, arrivalNs } = root;
    result.push({
      kind: "sink",
      id: `sink/${role}/${pin}/${cycle}/${arrivalNs}`,
      sinkKey: `${role}/${pin}`,
      pinName: pinName(pin),
      role,
      pin,
      cycle,
      arrivalNs,
      position: world(
        point(root.point),
        arrivalCoordinate(cycle, arrivalNs, budgetNs),
      ),
    });
  }
  return result;
}

/** Project explicitly identified world targets with the renderer's camera.
 * Each target has kind sink/event/storage, a stable nonempty id, and either
 * position or from/to. Unknown positions and clipped geometry are omitted.
 * Sink role/pin/cycle, event/version identities and all other payload stay on
 * target unchanged. Multiple representations of one logical identity remain
 * separate; callers may offer them together without discarding their evidence.
 */
export function projectPickTargets(targets, { project, projectSegment }) {
  if (
    !Array.isArray(targets) ||
    typeof project !== "function" ||
    typeof projectSegment !== "function"
  )
    throw new TypeError(
      "Picking requires targets and renderer projection functions",
    );
  const result = [];
  for (const target of targets) {
    if (
      !TARGET_KINDS.has(target?.kind) ||
      typeof target.id !== "string" ||
      target.id.length === 0
    )
      throw new TypeError(
        "Pick targets require a known kind and stable identity",
      );
    if (target.position !== undefined) {
      if (!worldPoint(target.position)) continue;
      const point = project(target.position);
      if (screenPoint(point)) result.push({ target, shape: "point", point });
      continue;
    }
    if (!worldPoint(target.from) || !worldPoint(target.to)) continue;
    const span = projectSegment(target.from, target.to);
    if (span?.length === 2 && span.every(screenPoint))
      result.push({ target, shape: "segment", from: span[0], to: span[1] });
  }
  return result;
}

// Projected segment depth interpolates in screen space. An edge-on segment
// chooses its nearest endpoint in depth, independently of native edge direction.
function closest(hit, pointer) {
  if (hit.shape === "point") return hit.point;
  const { from, to } = hit;
  const dx = to.x - from.x,
    dy = to.y - from.y;
  const length2 = dx * dx + dy * dy;
  if (length2 === 0) return from.depth <= to.depth ? from : to;
  const fraction = Math.max(
    0,
    Math.min(
      1,
      ((pointer.x - from.x) * dx + (pointer.y - from.y) * dy) / length2,
    ),
  );
  if (fraction === 0) return from;
  if (fraction === 1) return to;
  return {
    x: from.x + fraction * dx,
    y: from.y + fraction * dy,
    depth: from.depth + fraction * (to.depth - from.depth),
  };
}
function geometryKey(hit) {
  const points = hit.shape === "point" ? [hit.point] : [hit.from, hit.to];
  return points
    .map((p) => [p.x, p.y, p.depth].join("/"))
    .sort()
    .join(">");
}

/** Return every matching target within its CSS-pixel hit radius, ordered by
 * distance, then frontmost depth, then stable identity/geometry. The first is a
 * hover preview, not permission to hide the other candidates or auto-select a
 * different mode. Each result retains the projected hit plus distancePx, depth
 * and closest:{x,y}; an overlapping sink can therefore be previewed and offered
 * in a complete disambiguation list. No timing ranking is inferred by picking.
 */
export function pickCandidates(
  hits,
  pointer,
  { mode, radiusPx = PICK_RADII[mode] } = {},
) {
  if (!Object.hasOwn(KINDS, mode)) throw new RangeError("Unknown picking mode");
  if (
    !Array.isArray(hits) ||
    ![pointer?.x, pointer?.y].every(Number.isFinite) ||
    !Number.isFinite(radiusPx) ||
    radiusPx < 0
  )
    throw new TypeError(
      "Picking requires finite CSS-pixel coordinates and radius",
    );
  const result = [];
  for (const hit of hits) {
    if (hit.target.kind !== KINDS[mode]) continue;
    const point = closest(hit, pointer);
    const distancePx = Math.hypot(point.x - pointer.x, point.y - pointer.y);
    if (distancePx > radiusPx) continue;
    result.push({
      ...hit,
      distancePx,
      depth: point.depth,
      closest: { x: point.x, y: point.y },
    });
  }
  return result.sort(
    (a, b) =>
      a.distancePx - b.distancePx ||
      a.depth - b.depth ||
      lexical(a.target.id, b.target.id) ||
      lexical(geometryKey(a), geometryKey(b)),
  );
}
