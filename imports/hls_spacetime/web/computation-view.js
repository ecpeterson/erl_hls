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

/** A pending prepared attachment is not a capability rejection. Preserve the
 * intended control values until it arrives, including intervening user choices;
 * only a genuinely unavailable color or sink view gets a fallback. */
export function computationControlSelection({
  preparedPending,
  prepared,
  arrival,
  pickMode,
  colorMode,
}) {
  const preparedColor = ["computation", "criticality", "delay-kind"].includes(
    colorMode,
  );
  const colorAvailable =
    !preparedColor || (prepared && (colorMode !== "delay-kind" || arrival));
  return {
    pickMode:
      !preparedPending && !arrival && pickMode === "sinks"
        ? "writes"
        : pickMode,
    colorMode: !preparedPending && !colorAvailable ? "role" : colorMode,
  };
}
