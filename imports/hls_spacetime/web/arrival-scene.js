/** Build render geometry from static pin arrivals without changing native or
 * recorded identities. Unknown timing has an explicit shelf, never time zero.
 */
import {
  arrivalCoordinate,
  captureDisposition,
  eventCoordinate,
} from "./arrival-layout.js";
import {
  DIRECTION_SOURCE_COLOR,
  DIRECTION_SINK_COLOR,
  UNKNOWN_COLOR,
  OUTSIDE_TIMING_COLOR,
} from "./perceptual-color.js";

const SHELF_OFFSET = -0.18;
const READY_COLOR = "#7e8b91";
const LATE_COLOR = "#f07178";

/** A missing XY location cannot acquire a fabricated physical position. */
function located(value) {
  return value && Number.isFinite(value.x) && Number.isFinite(value.y);
}

/** Convert one complete arrival circuit to scene primitives. Readiness and
 * capture/overrun links are neutral annotations, separate from propagation.
 * Outside-scope pins are omitted; unknown mapped pins use the labelled shelf.
 * Overview draws pin arrivals only, preserving distinct times at equal XY.
 */
export function arrivalScene(
  circuit,
  {
    cycle,
    budgetNs,
    captureAvailable = false,
    point,
    world,
    shade,
    mode = "criticality",
    detail = "routes",
    activeArc = null,
  } = {},
) {
  arrivalCoordinate(cycle, 0, budgetNs);
  if (
    !circuit ||
    ![point, world, shade].every((fn) => typeof fn === "function")
  )
    throw new TypeError(
      "Arrival scene requires a circuit and coordinate/color functions",
    );
  if (typeof captureAvailable !== "boolean")
    throw new TypeError(
      "Capture availability must be explicit boolean evidence",
    );
  if (!["overview", "routes", "switches"].includes(detail))
    throw new RangeError("Unknown arrival detail mode");
  const result = {
    segments: [],
    markers: [],
    focus: [],
    summary: {
      lateRoots: 0,
      unknownRoots: 0,
      uncapturedRoots: 0,
      unknownSegments: 0,
      unknownMarks: 0,
    },
  };
  const phase = (arrivalNs) =>
    arrivalCoordinate(cycle, arrivalNs, budgetNs) ?? cycle + SHELF_OFFSET;
  const position = (raw, arrivalNs = raw.arrivalNs ?? null) =>
    world(point(raw), phase(arrivalNs));
  const mark = (at, color, size, kind, overlay) => {
    result.markers.push({ position: at, color, size, kind, ...overlay });
    result.focus.push(at);
  };
  const span = (
    from,
    to,
    color,
    colorEnd,
    radius,
    kind,
    dash = 0.018,
    overlay,
  ) => {
    if (from.every((value, index) => value === to[index])) return;
    result.segments.push({
      from,
      to,
      color,
      colorEnd,
      radius,
      kind,
      dash,
      ...overlay,
    });
    result.focus.push(from, to);
  };
  for (const row of circuit.segments ?? []) {
    if (row.status === "not_applicable") continue;
    const unknown =
      row.kind === "unknown" ||
      row.from?.arrivalNs === null ||
      row.to?.arrivalNs === null;
    if (unknown) result.summary.unknownSegments++;
    if (detail === "overview" || !located(row.from) || !located(row.to))
      continue;
    const readiness = row.kind === "readiness";
    const active =
      !readiness && activeArc !== null && row.arcIds?.includes(activeArc);
    const directional =
      mode === "direction" &&
      !active &&
      !unknown &&
      !readiness &&
      !row.directionUnknown;
    const color = active
      ? "#fff2bc"
      : unknown
        ? UNKNOWN_COLOR
        : readiness
          ? READY_COLOR
          : mode === "direction"
            ? OUTSIDE_TIMING_COLOR
            : shade(row);
    const from = position(row.from),
      to = position(row.to),
      startColor = directional ? DIRECTION_SOURCE_COLOR : color,
      endColor = directional ? DIRECTION_SINK_COLOR : color;
    const overlay = {
      overlayRole: unknown || !readiness ? "timing" : "annotation",
      timingUnknown: unknown || row.timingUnknown === true,
      priority: active ? 3 : 0,
    };
    const schematic = row.schematic && !unknown && !readiness;
    // A thin solid core keeps endpoint connectivity visible through the wider
    // dashed sleeve. The sleeve identifies interpolation across missing route
    // detail; separate radii avoid coincident tube surfaces.
    if (schematic)
      span(
        from,
        to,
        startColor,
        endColor,
        active ? 0.0013 : 0.0007,
        "arrival-schematic-core",
        0,
        overlay,
      );
    span(
      from,
      to,
      startColor,
      endColor,
      active ? 0.0032 : readiness ? 0.0008 : 0.0017,
      unknown
        ? "arrival-unknown"
        : readiness
          ? "arrival-readiness"
          : schematic
            ? "arrival-schematic"
            : "arrival-propagation",
      unknown || readiness || schematic ? 0.018 : 0,
      overlay,
    );
  }
  for (const row of circuit.marks ?? []) {
    if (row.status === "not_applicable") continue;
    const arrival =
      row.arrivalNs === undefined
        ? (row.point?.arrivalNs ?? null)
        : row.arrivalNs;
    const unknown = arrival === null;
    if (unknown) result.summary.unknownMarks++;
    if (!located(row.point)) continue;
    const active = activeArc !== null && row.arcIds?.includes(activeArc);
    mark(
      position(row.point, arrival),
      active
        ? "#fff2bc"
        : unknown
          ? UNKNOWN_COLOR
          : mode === "direction"
            ? OUTSIDE_TIMING_COLOR
            : shade(row),
      active ? 0.006 : 0.004,
      unknown ? "arrival-unknown-pin" : "arrival-pin",
      {
        overlayRole: "timing",
        timingUnknown: unknown || row.timingUnknown === true,
        priority: active ? 3 : 0,
      },
    );
  }
  const captureCycle = captureAvailable
    ? eventCoordinate({ cycle, access: { kind: "write" } })
    : null;
  for (const root of circuit.roots ?? []) {
    if (root.status === "not_applicable") continue;
    const disposition = captureDisposition(root.arrivalNs ?? null, budgetNs);
    if (disposition.kind === "unknown") result.summary.unknownRoots++;
    if (!captureAvailable) result.summary.uncapturedRoots++;
    if (disposition.kind === "late") result.summary.lateRoots++;
    if (
      !captureAvailable ||
      disposition.kind === "unknown" ||
      !located(root.point) ||
      detail === "overview"
    )
      continue;
    const at = position(root.point, root.arrivalNs);
    const capture = world(point(root.point), captureCycle);
    const late = disposition.kind === "late";
    // A late link points from the hypothetical boundary toward the overrun;
    // it is an annotation, not backwards dataflow or a claimed captured value.
    span(
      late ? capture : at,
      late ? at : capture,
      late ? LATE_COLOR : READY_COLOR,
      late ? LATE_COLOR : READY_COLOR,
      0.0008,
      late ? "arrival-overrun" : "arrival-capture-readiness",
      0.018,
      { overlayRole: "annotation" },
    );
    mark(
      capture,
      late ? LATE_COLOR : READY_COLOR,
      0.005,
      "arrival-capture-boundary",
      { overlayRole: "annotation" },
    );
  }
  return result;
}
