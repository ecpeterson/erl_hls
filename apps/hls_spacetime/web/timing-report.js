/** Explain static bounds through recorded writes. This report does not infer
 * sensitization, STA slack, physical period, waits or a multi-clock critical path. */
import {
  computationLayers,
  computationConnection,
} from "./computation-routes.js";
import { timingPath } from "./timing-paths.js";

function check(ok, reason) {
  if (!ok) throw Error(`Timing report: ${reason}`);
}
function countBy(rows, key) {
  const counts = {};
  for (const row of rows) {
    const value = key(row);
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}
function sorted(values) {
  return [...new Set(values)].sort();
}

/** Native names are exact graph identities; locations are tile coordinates,
 * not inferred wire shapes or micrometres. */
function pinDescription(index, id) {
  if (id === null) return null;
  const pin = index.pins[id],
    cell = index.cells[pin.cell];
  const location = cell && index.model.cells.get(cell.id);
  return {
    index: id,
    id: pin.id,
    cell: cell?.id ?? null,
    primitive: cell?.kind ?? null,
    tile:
      Number.isFinite(location?.x) && Number.isFinite(location?.y)
        ? { x: location.x, y: location.y }
        : null,
  };
}

/** Report one representative maximizing chain, including every arc's original
 * corner/condition annotations. Geometry completeness never changes its delay. */
function explain(index, cone, scope, fanout) {
  const path = timingPath(index, cone, { scope });
  let cumulativeNs = 0;
  const arcs = path.arcIndices.map((id) => {
    const arc = index.arcs[id],
      delayNs = index.delays[id];
    const arrivalFromNs = cumulativeNs;
    cumulativeNs += delayNs;
    const route = arc.kind === "net" ? computationConnection(index, id) : null;
    return {
      index: id,
      id: arc.id,
      kind: arc.kind,
      from: pinDescription(index, arc.from),
      to: pinDescription(index, arc.to),
      net: arc.kind === "net" ? index.nets[arc.net].id : null,
      nativeNetSinkPins:
        arc.kind === "net" ? (fanout.get(arc.net)?.size ?? 0) : null,
      delayNs,
      arrivalFromNs,
      arrivalToNs: cumulativeNs,
      timing: arc.timing,
      route: route
        ? {
            disposition: route.disposition,
            nodes: route.nodes.length,
            pips: route.pips.length,
            gaps: route.gaps,
          }
        : null,
    };
  });
  const { sourcePin, targetPin, arcIndices, ...bound } = path;
  return {
    id: cone.id,
    ...bound,
    source: pinDescription(index, sourcePin),
    target: pinDescription(index, targetPin),
    coverage: cone.coverage,
    sinkPins: cone.rootPins.length,
    pathLogicCells: new Set(
      arcs.filter((a) => a.kind === "logic").map((a) => a.from.cell),
    ).size,
    pathNativeNets: new Set(
      arcs.filter((a) => a.kind === "net").map((a) => a.net),
    ).size,
    path: arcs,
    rankedPathArcs: arcs
      .map((arc, position) => ({ position, arc: arc.id, delayNs: arc.delayNs }))
      .sort((a, b) => b.delayNs - a.delayNs || a.arc.localeCompare(b.arc)),
    pathRouteDispositions: countBy(
      arcs.filter((a) => a.route),
      (a) => a.route.disposition,
    ),
  };
}

/** All selected writes and shared cones are retained, including unknown/inapplicable
 * bounds and unmapped target bits. Occurrence counts do not multiply static delay.
 * The half-open cycle window selects write timestamps; an event can select its
 * explicit producer-owned writes. Nothing implies that those writes sensitized
 * every structural path, or that omitted paths cannot limit the physical clock. */
export function timingReport(
  index,
  {
    scope = "registered",
    firstCycle = index.model.bundle.capture.first_cycle,
    endCycle = index.model.bundle.capture.end_cycle,
    event = null,
  } = {},
) {
  check(
    ["registered", "static"].includes(scope),
    "scope must be registered or static",
  );
  const capture = index.model.bundle.capture;
  check(
    Number.isSafeInteger(firstCycle) &&
      Number.isSafeInteger(endCycle) &&
      firstCycle >= capture.first_cycle &&
      endCycle <= capture.end_cycle &&
      firstCycle < endCycle,
    "cycle window must be nonempty and within the capture",
  );
  check(
    event === null || index.operations.has(event),
    "unknown selected event",
  );
  const candidateIds =
    event === null
      ? [...index.operations.keys()]
      : index.operations.get(event).applicability === "storage_write"
        ? [event]
        : (index.operations.get(event).writes ?? []);
  const selected = [...new Set(candidateIds)].filter((id) => {
    const e = index.model.events.get(id);
    return (
      e.access?.kind === "write" && e.cycle >= firstCycle && e.cycle < endCycle
    );
  });
  computationLayers(index, selected);
  const writes = selected
    .map((id) => {
      const e = index.model.events.get(id),
        op = index.operations.get(id),
        cached = index.writeCones.get(id);
      return {
        event: id,
        cycle: e.cycle,
        incarnation: e.incarnation ?? null,
        actor: e.actor ?? null,
        task: e.task ?? null,
        resource: e.access.resource,
        mask: e.access.mask,
        producers: op.producers ?? [],
        status: op.status,
        unknowns: op.unknowns,
        coverage: cached.coverage,
        cones: cached.cones.map((c) => c.id).sort(),
      };
    })
    .sort((a, b) => a.cycle - b.cycle || a.event.localeCompare(b.event));
  const members = new Map();
  for (const write of writes)
    for (const id of write.cones) {
      if (!members.has(id)) members.set(id, []);
      members.get(id).push(write);
    }
  const fanout = new Map();
  for (const arc of index.arcs)
    if (arc.kind === "net") {
      if (!fanout.has(arc.net)) fanout.set(arc.net, new Set());
      fanout.get(arc.net).add(arc.to);
    }
  const cones = [...members]
    .map(([id, rows]) => ({
      ...explain(index, index.cones.get(id), scope, fanout),
      occurrences: {
        writes: rows.length,
        cycles: new Set(rows.map((w) => w.cycle)).size,
        firstCycle: rows[0].cycle,
        lastCycle: rows.at(-1).cycle,
        resources: sorted(rows.map((w) => w.resource)),
        actors: sorted(rows.map((w) => w.actor).filter((a) => a !== null)),
      },
    }))
    .sort(
      (a, b) =>
        (b.delayNs ?? -1) - (a.delayNs ?? -1) || a.id.localeCompare(b.id),
    );
  // Native cone keys encode hundreds of root pins. Keep that identity once;
  // occurrence rows use compact report-local references, never repeated keys.
  const references = new Map(cones.map((cone, id) => [cone.id, id]));
  for (const cone of cones) {
    cone.sourceConeId = cone.id;
    cone.id = references.get(cone.id);
  }
  for (const write of writes)
    write.cones = write.cones.map((id) => references.get(id));
  const finite = cones.filter((c) => c.status === "known");
  return {
    format: "spacetime-timing-report",
    schema: 1,
    evidence: index.attachment.timingModel
      ? "representative_maximum_nextpnr_arc_estimate"
      : "representative_maximum_independent_arc_sdf_envelope",
    ...(index.attachment.timingModel && {
      timingModel: index.attachment.timingModel,
    }),
    interpretation: [
      "One deterministic maximizing chain per selected shared cone; ties are not exhaustively enumerated.",
      index.attachment.timingModel
        ? "Propagation uses the single supplied nextpnr estimate for each arc."
        : "Each arc uses its largest supplied fast/slow corner and conditional delay independently; a chain need not be jointly sensitizable or a single-corner STA path.",
      "Excludes clock-to-Q, setup, clock skew, timing constraints/exceptions and dynamic activity. This is neither STA slack nor a physical clock period.",
      "Recorded write membership is structural association, not evidence that this path switched. Data, enable and reset cones remain separate.",
      "A known path delay may have partial or unavailable geometry. Unmapped target bits remain outside the analyzed native cones.",
      "Repeated writes do not multiply static delay; cross-clock elapsed time, waits and a whole-step critical path are not calculated.",
    ],
    build: index.attachment.build,
    checkpoint: index.attachment.checkpoint,
    capture,
    selection: { scope, firstCycle, endCycle, event },
    summary: {
      writes: writes.length,
      sharedCones: cones.length,
      coneStatus: countBy(cones, (c) => c.status),
      roles: countBy(cones, (c) => c.role),
      maximumKnownPathNs: finite.length ? finite[0].delayNs : null,
      writesWithUnknownTargetBits: writes.filter(
        (w) => w.coverage.unknownBits > 0,
      ).length,
      writesWithoutNativeCones: writes.filter((w) => !w.cones.length).length,
      requestedBitOccurrences: writes.reduce(
        (n, w) => n + w.coverage.requestedBits,
        0,
      ),
      mappedBitOccurrences: writes.reduce(
        (n, w) => n + w.coverage.mappedBits,
        0,
      ),
      unknownBitOccurrences: writes.reduce(
        (n, w) => n + w.coverage.unknownBits,
        0,
      ),
    },
    cones,
    writes,
  };
}

/** A short human index accompanies the complete machine-readable report. The
 * preview is explicitly limited; report.json always retains every selected row. */
export function timingReportMarkdown(report) {
  const n = (value) => (value === null ? "unknown" : value.toFixed(4));
  const code = (value) =>
    `<code>${String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("`", "&#96;")
      .replaceAll("|", "&#124;")
      .replace(/[\r\n]+/g, " ")}</code>`;
  const lines = [
    "# Recorded-computation timing report",
    "",
    `Write clocks [${report.selection.firstCycle}, ${report.selection.endCycle}); scope: ${report.selection.scope}.`,
    "",
    `${report.summary.writes} writes, ${report.summary.sharedCones} shared cones. Maximum **known structural envelope**: ${n(report.summary.maximumKnownPathNs)} ns.`,
    "",
    `Cone dispositions: ${JSON.stringify(report.summary.coneStatus)}. ${report.summary.writesWithUnknownTargetBits} writes have unmapped target bits; ${report.summary.writesWithoutNativeCones} have no native cone.`,
    "",
    report.timingModel
      ? "Delays use one nextpnr model and cover combinational propagation between the selected endpoints."
      : "These are independent per-arc SDF maxima, excluding clock and endpoint timing checks. They are not STA slack, a physical period or a dynamically sensitized path. Occurrences do not multiply delay.",
    "",
    "## Longest known chains",
    "",
    "Preview of at most 12 cones; report.json retains every selected cone, ordered chain, original arc annotation and write association.",
    "",
    "| Cone | Role | Total ns | Net ns | Logic ns | Writes | Launch → sink |",
    "| --- | --- | ---: | ---: | ---: | ---: | --- |",
  ];
  for (const c of report.cones.filter((c) => c.status === "known").slice(0, 12))
    lines.push(
      `| ${code(c.id)} | ${c.role} | ${n(c.delayNs)} | ${n(c.netDelayNs)} | ${n(c.logicDelayNs)} | ${c.occurrences.writes} | ${code(c.source.id)} → ${code(c.target.id)} |`,
    );
  const worst = report.cones.find((c) => c.status === "known");
  if (worst) {
    lines.push(
      "",
      "## Largest individual contributions on the first chain",
      "",
      "Preview of at most 12 arcs, sorted by delay; JSON retains their original chain positions and all other arcs.",
      "",
      "| Position | Kind | Delay ns | Net sink pins | Geometry | From → to |",
      "| ---: | --- | ---: | ---: | --- | --- |",
    );
    for (const ranked of worst.rankedPathArcs.slice(0, 12)) {
      const a = worst.path[ranked.position];
      lines.push(
        `| ${ranked.position} | ${a.kind} | ${n(a.delayNs)} | ${a.nativeNetSinkPins ?? "—"} | ${a.route?.disposition ?? "primitive arc"} | ${code(a.from.id)} → ${code(a.to.id)} |`,
      );
    }
  }
  lines.push(
    "",
    "Known endpoint delay and route geometry are separate. Partial routes retain native attachment gaps; no missing geometry is assigned zero delay. Fanout is native sink-pin count, not a measurement of congestion.",
    "",
  );
  return lines.join("\n");
}
