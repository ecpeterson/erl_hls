/** Retain only semantic selection seeds admitted by the current filters. The
 * caller supplies all matching events, independent of the displayed clock window;
 * producer-to-write associations remain the computation model's responsibility. */
export function computationSelection(seeds, matchingEvents) {
  const allowed = new Set(matchingEvents.map((event) => event.id));
  return seeds.filter((event) => allowed.has(event.id));
}

/** Union static circuitry for a flat footprint, without changing per-clock
 * occurrences. Preserve distinct role cones even where their arcs overlap, so
 * shared data/enable/reset geometry can retain all of its roles. */
export function computationWindowUnion(layers) {
  const cones = new Map(),
    arcs = new Set(),
    operations = new Map();
  for (const layer of layers) {
    for (const cone of layer.cones) cones.set(cone.id, cone);
    for (const arc of layer.arcs) arcs.add(arc);
    for (const op of layer.operations ?? []) operations.set(op.event, op);
  }
  return {
    cones: [...cones.values()],
    arcs: [...arcs],
    operations: [...operations.values()],
  };
}
