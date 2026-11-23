/** Placed neighborhood context on one reference plane. These glyphs identify
 * installed cells and represented fanout, never activity or routed metal. */
import { arrivalCoordinate } from "./arrival-layout.js";

const FAMILY_COLOR = "#65858c";
const CONTEXT_COLOR = "#414c54";
const OUTLINE_COLOR = "#61747e";
const DRIVER_COLOR = "#d6bc87";
const SINK_COLOR = "#a5a4c8";

function located(value) {
  return value && Number.isFinite(value.x) && Number.isFinite(value.y);
}
function inside(point, region) {
  return (
    !region ||
    (point.x >= region.minX &&
      point.x <= region.maxX &&
      point.y >= region.minY &&
      point.y <= region.maxY)
  );
}

/** Draw every located installed cell supplied inside the neighborhood region,
 * optionally hiding context cells. Distinct cell and pin identities remain
 * distinct even at coincident tile coordinates; the caller may merge glyphs.
 * A selected driver's spokes include every located represented sink, including
 * sinks outside the region. Direct dashed chords express connectivity only.
 * All geometry uses cycle as a reference plane, without an arrival-time claim.
 * Null locations supply no geometry, and a null region supplies no outline.
 */
export function neighborhoodScene(
  neighborhood,
  { cycle, point, world, driverPin = null, showContext = true } = {},
) {
  if (
    !neighborhood ||
    !Number.isFinite(cycle) ||
    ![point, world].every((fn) => typeof fn === "function") ||
    typeof showContext !== "boolean"
  )
    throw new TypeError(
      "Neighborhood scene requires a reference cycle, coordinate functions and explicit visibility",
    );
  const { region } = neighborhood;
  if (
    region &&
    (![region.minX, region.maxX, region.minY, region.maxY].every(
      Number.isFinite,
    ) ||
      region.minX > region.maxX ||
      region.minY > region.maxY)
  )
    throw new RangeError("Invalid neighborhood region");
  const result = { segments: [], markers: [], focus: [], labels: [] };
  const position = (raw) => world(point(raw), cycle);
  const mark = (raw, color, size, kind, identity, priority) => {
    const at = position(raw);
    result.markers.push({
      position: at,
      color,
      size,
      kind,
      priority,
      ...identity,
    });
    return at;
  };
  const span = (from, to, color, radius, kind, dash, identity = {}) => {
    if (from.every((value, i) => value === to[i])) return;
    result.segments.push({
      from,
      to,
      color,
      colorEnd: color,
      radius,
      kind,
      dash,
      ...identity,
    });
  };
  let corners = [];
  if (region) {
    corners = [
      { x: region.minX, y: region.minY },
      { x: region.maxX, y: region.minY },
      { x: region.maxX, y: region.maxY },
      { x: region.minX, y: region.maxY },
    ].map(position);
    for (let i = 0; i < corners.length; i++)
      span(
        corners[i],
        corners[(i + 1) % corners.length],
        OUTLINE_COLOR,
        0.0006,
        "neighborhood-region",
        0,
      );
    result.focus.push(...corners);
    result.labels.push({
      text: "Placed neighborhood · context, not activity",
      position: corners[0],
      alternatives: corners,
    });
  }
  for (const row of neighborhood.cells ?? []) {
    if (
      !located(row.cell) ||
      !inside(row.cell, region) ||
      (!showContext && row.kind === "context")
    )
      continue;
    const family = row.kind === "family";
    const at = mark(
      row.cell,
      family ? FAMILY_COLOR : CONTEXT_COLOR,
      family ? 0.0035 : 0.0025,
      `neighborhood-${row.kind}`,
      { cellIndex: row.index, cellId: row.cell.id },
      family ? 1 : 0,
    );
    if (family) result.focus.push(at);
  }
  const driver =
    driverPin === null
      ? null
      : neighborhood.fanouts?.find((row) => row.pin === driverPin);
  if (!driver) return result;
  const origin = located(driver.point)
    ? mark(
        driver.point,
        DRIVER_COLOR,
        0.006,
        "neighborhood-driver",
        { pin: driver.pin },
        3,
      )
    : null;
  if (origin) result.focus.push(origin);
  const ends = [];
  for (const sink of driver.sinks) {
    if (!located(sink.point)) continue;
    const at = mark(
      sink.point,
      SINK_COLOR,
      0.004,
      "neighborhood-sink",
      { pin: sink.pin, insideRegion: sink.insideRegion },
      2,
    );
    ends.push(at);
    result.focus.push(at);
    if (origin)
      span(origin, at, SINK_COLOR, 0.0008, "neighborhood-fanout", 0.014, {
        fromPin: driver.pin,
        toPin: sink.pin,
        insideRegion: sink.insideRegion,
      });
  }
  const anchor = origin ?? ends[0] ?? corners[0];
  if (anchor)
    result.labels.push({
      text: origin
        ? "Fanout spokes · connectivity, not routing"
        : "Fanout sinks · driver location unknown; no connecting spokes",
      position: anchor,
    });
  return result;
}

/** Mark a known proposed boundary at the crossings' original native positions
 * and saved arrival heights. No new register placement or stage timing is drawn.
 * Constant crossings use subdued glyphs; they do not request a flip-flop.
 * Unknown locations/arrivals remain absent, and every located crossing is kept.
 * The selectedPin identity is the crossing's fromPin, not a destination load.
 */
export function cutScene(
  cut,
  { cycle, budgetNs, point, world, selectedPin = null } = {},
) {
  arrivalCoordinate(cycle, 0, budgetNs);
  if (![point, world].every((fn) => typeof fn === "function"))
    throw new TypeError("Cut scene requires coordinate functions");
  const result = { segments: [], markers: [], focus: [], labels: [] };
  if (cut?.status !== "known") return result;
  for (const crossing of cut.crossings) {
    if (!located(crossing.point)) continue;
    const coordinate = arrivalCoordinate(
      cycle,
      crossing.originalArrivalNs,
      budgetNs,
    );
    if (coordinate === null) continue;
    const position = world(point(crossing.point), coordinate);
    const constant = crossing.requiresRegister === false;
    const selected = crossing.fromPin === selectedPin;
    result.markers.push({
      position,
      pin: crossing.fromPin,
      color: constant ? "#797969" : "#e1bc70",
      size: selected ? 0.008 : constant ? 0.0035 : 0.005,
      priority: selected ? 5 : 4,
      kind: constant ? "candidate-cut-constant" : "candidate-cut-signal",
      requiresRegister: !constant,
    });
    result.focus.push(position);
  }
  const anchor =
    result.markers.find((row) => row.pin === selectedPin) ?? result.markers[0];
  if (anchor)
    result.labels.push({
      text: "Proposed boundary · original arrival positions",
      position: anchor.position,
    });
  return result;
}
