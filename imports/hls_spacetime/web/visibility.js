/** Display-only selection. Call with mappedOnly=false for logical layouts;
 * neither these helpers nor their callers remove records from the model. */
export function spatialPoints(points, mappedOnly) {
  return mappedOnly ? points.filter((point) => point.physical) : points;
}

/** Filter established pairs after word/bit pairing, never before: dropping an
 * unknown point must not turn a many-to-many dependency into a one-ended fan.
 * An aggregate centroid cannot rescue an access whose selected bits are all
 * unlocated. Partial words keep their placed portions without inventing edges. */
export function spatialPairs(pairs, sources, targets, mappedOnly) {
  if (!mappedOnly) return pairs;
  if (
    !sources.some((point) => point.physical) ||
    !targets.some((point) => point.physical)
  )
    return [];
  return pairs.filter(([from, to]) => from.physical && to.physical);
}
