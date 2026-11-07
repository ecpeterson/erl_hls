/** Spatial storage evidence for a recorded operation. Native cells stay at
 * their actual tile positions; this module never substitutes a centroid or
 * turns stored-value correspondence into a native switching/enable claim. */
import { resourcePlacement } from "./model.js";

/** Decode a canonical, unsigned hexadecimal mask without rounding wide words.
 * Leading zeroes/lowercase digits and set bits above the declared width reject. */
function accessMask(text, width) {
  if (typeof text !== "string" || !/^0x(?:0|[1-9A-F][0-9A-F]*)$/.test(text))
    throw Error("Access footprint requires a canonical hexadecimal mask");
  const digits = text.slice(2);
  const significant =
    text === "0x0"
      ? 0
      : (digits.length - 1) * 4 +
        Math.floor(Math.log2(parseInt(digits[0], 16))) +
        1;
  if (significant > width)
    throw Error("Access footprint mask exceeds word width");
  const population = [...digits].reduce(
    (count, digit) =>
      count +
      [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4][parseInt(digit, 16)],
    0,
  );
  return { value: BigInt(text), population };
}

/** Bounds summarize the actual placed set without inventing a representative
 * location. Unplaced cells contribute no coordinate or extent. */
function spatialBounds(cells) {
  return cells.length
    ? cells.reduce(
        (bounds, cell) => ({
          minX: Math.min(bounds.minX, cell.x),
          maxX: Math.max(bounds.maxX, cell.x),
          minY: Math.min(bounds.minY, cell.y),
          maxY: Math.max(bounds.maxY, cell.y),
        }),
        { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity },
      )
    : null;
}

/** Return placed storage cells associated with one recorded access. Writes use
 * the exact logical bit mask where bit bindings exist. Reads use an explicit
 * producer-supplied read mask, otherwise provide only whole-word context. A
 * whole-cell binding without bit identities also remains contextual, even for
 * writes. Folded bits share one cell entry with all selected logical bit IDs.
 *
 * cells/unplacedCells hold native records plus bits/accessed/contextual flags;
 * accessed means selected by a logical access mask, never native enable/activity.
 * unknownBits counts considered bits lacking a supported cell identity;
 * unplacedBits separately counts supported bits without a finite coordinate.
 * candidateCells are unresolved whole-word candidates, not selected access bits.
 * A delayed response is not placed at the source word: its execution location
 * needs separate evidence. Unknown events, widths, bit IDs and masks reject.
 */
export function eventFootprint(model, eventId) {
  const event = model.events.get(eventId);
  if (!event) throw Error(`Unknown footprint event: ${eventId}`);
  const access = event.access;
  const result = {
    event: eventId,
    resource: access?.resource ?? null,
    kind: access?.kind ?? null,
    mode: "unknown",
    reason: "This operation has no qualified logic placement.",
    cells: [],
    unplacedCells: [],
    candidateCells: [],
    bounds: null,
    bitSelectionKnown: false,
    consideredBits: 0,
    selectedBits: null,
    unknownBits: 0,
    unplacedBits: 0,
  };
  if (access?.kind === "read_result") {
    result.reason =
      "The response uses a copy selected at its request; its execution location is unknown.";
    return result;
  }
  if (!access || !["write", "read_request", "hold"].includes(access.kind))
    return result;
  const placement = resourcePlacement(model, access.resource);
  const width = model.resources.get(access.resource).width;
  if (!Number.isSafeInteger(width) || width <= 0)
    throw Error("Invalid footprint word width");
  const write = access.kind === "write";
  const selectedRead =
    access.kind === "read_request" && access.read_mask !== undefined;
  const mask =
    write || selectedRead
      ? accessMask(write ? access.mask : access.read_mask, width)
      : null;
  if (selectedRead && !mask.population)
    throw Error("Read footprint mask is empty");
  const known = mask !== null;
  const consideredBits = known ? mask.population : width;
  Object.assign(result, {
    mode: write ? "write_bits" : selectedRead ? "read_bits" : "word_context",
    bitSelectionKnown: known,
    consideredBits,
    selectedBits: known ? consideredBits : null,
    unknownBits: consideredBits,
    reason: write
      ? "Logical write-mask bits at qualified stored-value locations; native enable and switching are not established."
      : selectedRead
        ? "Recorded selected operational read bits at qualified stored-value locations; not sensitized gate activity."
        : access.kind === "hold"
          ? "Whole-word storage context; a hold is not a computation or read."
          : "Whole-word storage context; the consumed read-bit subset is unknown.",
  });
  if (!consideredBits) return result;
  const bindingBits = placement.binding?.bits ?? [];
  const chosen = new Map();
  const add = (cell, bit, accessed) => {
    if (!chosen.has(cell.id))
      chosen.set(cell.id, {
        ...cell,
        bits: [],
        accessed,
        contextual: !accessed,
      });
    if (bit !== null) chosen.get(cell.id).bits.push(bit);
  };
  if (bindingBits.length) {
    const seen = new Set();
    for (const binding of bindingBits) {
      if (
        !Number.isSafeInteger(binding.bit) ||
        binding.bit < 0 ||
        binding.bit >= width ||
        seen.has(binding.bit)
      )
        throw Error(`Invalid or duplicate footprint bit: ${binding.bit}`);
      seen.add(binding.bit);
      if (known && !((mask.value >> BigInt(binding.bit)) & 1n)) continue;
      if (binding.status !== "supported") continue;
      const cell = model.cells.get(binding.cell);
      if (!cell) continue;
      result.unknownBits--;
      if (!Number.isFinite(cell.x) || !Number.isFinite(cell.y))
        result.unplacedBits++;
      add(cell, binding.bit, known);
    }
  } else {
    for (const cell of placement.cells) add(cell, null, false);
    result.mode = "word_context";
    result.reason = known
      ? "Logical access mask is known, but the cell binding has no bit identities; only whole-word context is available."
      : result.reason;
  }
  for (const cell of chosen.values()) {
    cell.bits.sort((a, b) => a - b);
    (Number.isFinite(cell.x) && Number.isFinite(cell.y)
      ? result.cells
      : result.unplacedCells
    ).push(cell);
  }
  result.candidateCells = placement.candidateCells;
  result.bounds = spatialBounds(result.cells);
  return result;
}

/** Pair storage footprints only where the word dependency supports it. A write's
 * mask identifies new bits, not the old bits that may feed its computation, so
 * incoming write dependencies always remain aggregate. A read can match tile
 * positions within the same word as contextual storage correspondence; this
 * does not identify its consumed bits. One-ended fans remain schematic word
 * dependencies. Empty intersections and many-to-many cross-word relationships
 * fall back to one explicitly aggregate connection, never a Cartesian product.
 */
export function accessConnections(from, to, sources, targets) {
  if (!sources.length || !targets.length || to.access?.kind === "write")
    return { aggregate: true, pairs: [] };
  if (sources.length === 1 || targets.length === 1)
    return {
      aggregate: false,
      pairs: sources.flatMap((a) => targets.map((b) => [a, b])),
    };
  if (
    from.access?.resource === to.access?.resource &&
    to.access?.kind === "read_request"
  ) {
    const destinations = new Map(targets.map((p) => [`${p.x}/${p.y}`, p]));
    const pairs = sources
      .filter((p) => destinations.has(`${p.x}/${p.y}`))
      .map((p) => [p, destinations.get(`${p.x}/${p.y}`)]);
    if (pairs.length) return { aggregate: false, pairs };
  }
  return { aggregate: true, pairs: [] };
}
