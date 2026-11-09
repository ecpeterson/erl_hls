/** Arrival-layout coordinates are display phases, never measured timestamps.
 * B_C anchors old Q sampled before edge C; B_(C+1) is that edge's capture
 * boundary and the next sample's Q. Saved event cycles remain unchanged.
 */

/** Capture cycles are exact nonnegative integers, not fractional phases. */
function requireCycle(cycle) {
  if (!Number.isSafeInteger(cycle) || cycle < 0)
    throw new RangeError("Cycle must be a nonnegative safe integer");
}

/** One finite positive hypothetical budget is shared by the displayed clocks. */
function requireBudget(budgetNs) {
  if (!Number.isFinite(budgetNs) || budgetNs <= 0)
    throw new RangeError("Arrival budget must be finite and positive");
}

/** Unknown and outside-scope arrivals are explicit, distinct dispositions. */
function arrivalKind(arrivalNs) {
  if (arrivalNs === null) return "unknown";
  if (arrivalNs === "not_applicable") return "not_applicable";
  if (!Number.isFinite(arrivalNs) || arrivalNs < 0)
    throw new RangeError(
      "Arrival must be finite and nonnegative or explicit unknown/not_applicable",
    );
  return "known";
}

/** Place a latest static arrival relative to B_C using a common budget.
 * Unknown/outside-scope arrivals have no coordinate. Late values extend beyond
 * B_(C+1); neither clamping nor per-cone normalization hides an overrun.
 */
export function arrivalCoordinate(cycle, arrivalNs, budgetNs) {
  requireCycle(cycle);
  requireBudget(budgetNs);
  if (arrivalKind(arrivalNs) !== "known") return null;
  const coordinate = cycle + arrivalNs / budgetNs;
  if (!Number.isFinite(coordinate) || coordinate > Number.MAX_SAFE_INTEGER)
    throw new RangeError("Arrival coordinate exceeds the finite display range");
  return coordinate;
}

/** A recorded write at C belongs to capture boundary B_(C+1). Other events
 * retain their cycle anchor. This arithmetic helper does not qualify an event
 * for arrival geometry: callers must establish boundary semantics first using
 * arrivalEventAnchor or an explicit native capture predicate.
 */
export function eventCoordinate(event) {
  requireCycle(event?.cycle);
  const coordinate = event.cycle + (event.access?.kind === "write" ? 1 : 0);
  if (!Number.isSafeInteger(coordinate))
    throw new RangeError("Event coordinate exceeds the exact display range");
  return coordinate;
}

/** Compare a static D arrival with the hypothetical capture budget. Equality
 * is ready, with zero margin. Negative margin is late; this is not STA slack.
 */
export function captureDisposition(arrivalNs, budgetNs) {
  requireBudget(budgetNs);
  const kind = arrivalKind(arrivalNs);
  if (kind !== "known") return { kind, marginNs: null };
  const marginNs = budgetNs - arrivalNs;
  return { kind: marginNs >= 0 ? "ready" : "late", marginNs };
}
