/** A within-clock ruler uses the same hypothetical budget as arrival geometry.
 * It labels display coordinates only; no marker implies a recorded operation.
 */
import { arrivalCoordinate } from "./arrival-layout.js";

/** Return quarter-budget labels for each clock in windows of at most four.
 * Larger windows omit only minor ruler labels. Values are offsets from that
 * clock's Q reference, not accumulated physical time across clock boundaries.
 * Invalid clocks, windows and budgets reject even when labels would be hidden.
 */
export function arrivalRuler(first, window, budgetNs) {
  if (!Number.isSafeInteger(window) || window < 1)
    throw new RangeError("Ruler window must be a positive safe integer");
  arrivalCoordinate(first, 0, budgetNs);
  arrivalCoordinate(first + window, 0, budgetNs);
  if (window > 4) return [];
  const labels = [];
  for (let cycle = first; cycle < first + window; cycle++)
    for (let quarter = 1; quarter <= 3; quarter++) {
      const offsetNs = budgetNs * (quarter / 4);
      labels.push({
        coordinate: arrivalCoordinate(cycle, offsetNs, budgetNs),
        offsetNs,
        text: `+${Number(offsetNs.toPrecision(4))} ns`,
        key: `arrival-ruler:${cycle}:${quarter}`,
      });
    }
  return labels;
}
