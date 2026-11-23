/** Per-sink scene selection. Filter exact graph identities before geometry is
 * merged; coincident pixels never establish path membership. */
import { sinkRows, sinkPath } from "./sink-paths.js";
const MODES = new Set(["all", "per-sink", "selected", "near"]);

/** Preserve an explicit selection only while it remains in the visible sink
 * population. Filtering must not leave a former sink or arc highlighted. */
export function visibleSink(rows, key) {
  return rows.find((row) => row.key === key) ?? null;
}

/** Select one representative maximizing chain per sink, or the selected sink's
 * chain/near-longest corridor. Unknown roots remain markers without invented
 * representative chains. All source records remain available outside this view.
 * An arc shared by selected chains takes their maximum bound; an unknown eligible
 * contribution is never replaced by a known one. */
export function sinkSelections(
  index,
  layers,
  { scope = "registered", mode = "all", sink = null, marginNs = 0.5 } = {},
) {
  if (!MODES.has(mode) || !Number.isFinite(marginNs) || marginNs < 0)
    throw Error("Invalid sink view");
  if (mode === "all") return null;
  const cones = new Map(
    layers.flatMap((layer) => layer.cones.map((cone) => [cone.id, cone])),
  );
  // Qualification belongs to the visible role/sink union, not whichever cone
  // happens to supply a finite alternative. Keep roots even when no chain qualifies.
  const merged =
    mode === "per-sink"
      ? new Map(sinkRows(index, layers, { scope }).map((row) => [row.key, row]))
      : null;
  const selections = new Map();
  for (const cone of cones.values()) {
    const roots =
      mode === "per-sink"
        ? cone.rootPins
        : sink && cone.role === sink.role && cone.rootPins.includes(sink.pin)
          ? [sink.pin]
          : [];
    if (!roots.length) continue;
    const selected = {
      arcIds: new Set(),
      rootPins: new Set(roots),
      pathCosts: new Map(),
    };
    const add = (arc, cost) => {
      selected.arcIds.add(arc);
      const previous = selected.pathCosts.get(arc);
      selected.pathCosts.set(
        arc,
        previous === null || cost === null
          ? null
          : Math.max(previous ?? 0, cost),
      );
    };
    for (const pin of roots) {
      const status =
        mode === "per-sink"
          ? merged.get(`${cone.role}/${pin}`).status
          : sink.status;
      if (mode !== "near" && status !== "known") continue;
      const path = sinkPath(index, cone, pin, {
        scope,
        marginNs,
        corridor: mode === "near",
      });
      if (mode === "near") {
        if (status === "unknown") {
          // No complete bound exists against which to threshold alternatives.
          // Preserve the full eligible closure and make every displayed cost unknown.
          for (const row of path.arcCosts)
            if (row.status !== "not_applicable") add(row.arc, null);
        } else {
          const included = new Set([
            ...path.corridorArcIds,
            ...path.unknownArcIds,
          ]);
          for (const row of path.arcCosts)
            if (included.has(row.arc)) add(row.arc, row.pathDelayNs);
        }
      } else if (path.status === "known")
        for (const arc of path.arcIndices) add(arc, path.delayNs);
    }
    selections.set(cone.id, selected);
  }
  return selections;
}

/** Resolve a listed sink back to a native cone; maximum finite contributors win
 * deterministically, while the merged row's unknown status prevents claiming a
 * complete path from a known alternative. */
export function selectedSinkPath(index, row, { scope = "registered" } = {}) {
  if (!row || row.status !== "known") return null;
  const candidates = index.cones.filter((cone) =>
    row.coneIds.includes(cone.id),
  );
  const paths = candidates.map((cone) =>
    sinkPath(index, cone, row.pin, { scope }),
  );
  return (
    paths
      .filter((p) => p.status === "known")
      .sort((a, b) => b.delayNs - a.delayNs || a.sourcePin - b.sourcePin)[0] ??
    null
  );
}
