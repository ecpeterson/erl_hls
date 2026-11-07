/** Cycle-only summaries of saved observations. Interval length, overlapping
 * storage occupancy, recorded wait samples and static hardware capacity are
 * separate quantities; none is a physical period or a complete critical path. */
import { eventsInWindow, storageSegments, traceDependencies } from "./model.js";

/** Keep bounded browser arithmetic exact instead of rounding large totals. */
function requireCount(value, label, positive = false) {
  if (!Number.isSafeInteger(value) || value < (positive ? 1 : 0))
    throw Error(`Metrics: invalid ${label}`);
}

/** Count each catalogue identity once, including explicitly unplaced cells.
 * Missing catalogue evidence is null capacity, never measured zero area. */
function installedPopulation(model) {
  if (!model.catalogue) return null;
  const byKind = new Map();
  let placedCells = 0;
  for (const cell of model.cells.values()) {
    const kind = cell.kind ?? "unknown";
    byKind.set(kind, (byKind.get(kind) ?? 0) + 1);
    if (Number.isFinite(cell.x) && Number.isFinite(cell.y)) placedCells++;
  }
  return {
    cells: model.cells.size,
    placedCells,
    unplacedCells: model.cells.size - placedCells,
    byKind: Object.fromEntries(
      [...byKind].sort(([a], [b]) => a.localeCompare(b)),
    ),
  };
}

/** Sum visible adjacent-clock links once per logical stored version. Overlapping
 * words deliberately add, while resource aliases never multiply native area.
 * Only connections with both sampled endpoints inside the window contribute. */
function storageTotals(model, options) {
  const segments = storageSegments(model, options);
  const words = new Set(),
    versions = new Set();
  let loadWordClocks = 0,
    holdWordClocks = 0;
  for (const segment of segments) {
    const clocks = segment.visibleToCycle - segment.visibleFromCycle;
    if (segment.kind === "write") loadWordClocks += clocks;
    else holdWordClocks += clocks;
    requireCount(loadWordClocks, "load word-clocks");
    requireCount(holdWordClocks, "hold word-clocks");
    words.add(JSON.stringify([segment.resource, segment.address]));
    versions.add(segment.version);
  }
  const totalWordClocks = loadWordClocks + holdWordClocks;
  requireCount(totalWordClocks, "total word-clocks");
  return {
    policy: options.usedOnly ? "recorded_uses" : "full_history",
    wordsWithConnections: words.size,
    versionsWithConnections: versions.size,
    loadWordClocks,
    holdWordClocks,
    totalWordClocks,
  };
}

/** Count one-clock observations only for operations explicitly classified by
 * the caller's producer contract. Concurrent waits share a sampled clock but
 * retain distinct event counts. No matching samples establish no global bound
 * on waits, and a gap in operations never becomes a wait observation. */
function waitSamples(events, operations) {
  const wanted = new Set(operations),
    cycles = new Set(),
    byOperation = new Map();
  let eventSamples = 0;
  for (const event of events) {
    if (!wanted.has(event.operation)) continue;
    eventSamples++;
    cycles.add(event.cycle);
    byOperation.set(
      event.operation,
      (byOperation.get(event.operation) ?? 0) + 1,
    );
  }
  return {
    status: !wanted.size
      ? "unclassified"
      : eventSamples
        ? "observed"
        : "not_observed",
    operations: [...wanted].sort(),
    eventSamples: wanted.size ? eventSamples : null,
    clockSamples: wanted.size ? cycles.size : null,
    byOperation: Object.fromEntries(
      [...byOperation].sort(([a], [b]) => a.localeCompare(b)),
    ),
  };
}

/** Summarize backward recorded ancestry, excluding resource order. The span is
 * only earliest-to-selected event distance; unknown roots and truncation forbid
 * interpreting it as complete computation latency or a critical-path result. */
function ancestrySummary(model, event, firstCycle, endCycle, maxEvents) {
  if (event === null) return null;
  const trace = traceDependencies(model, event, { maxEvents });
  const rootVersions = new Map(
    trace.roots.map(({ version }) => [version.id, version]),
  );
  const rootsByOrigin = new Map();
  for (const root of rootVersions.values())
    rootsByOrigin.set(root.origin, (rootsByOrigin.get(root.origin) ?? 0) + 1);
  let earliestCycle = Infinity,
    latestCycle = -Infinity,
    eventsOutsideWindow = 0;
  for (const item of trace.events) {
    earliestCycle = Math.min(earliestCycle, item.cycle);
    latestCycle = Math.max(latestCycle, item.cycle);
    if (item.cycle < firstCycle || item.cycle >= endCycle)
      eventsOutsideWindow++;
  }
  return {
    event,
    events: trace.events.length,
    edges: trace.edges.length,
    eventsOutsideWindow,
    earliestCycle,
    latestCycle,
    spanClocks: latestCycle - earliestCycle,
    rootVersions: rootVersions.size,
    rootsByOrigin: Object.fromEntries(
      [...rootsByOrigin].sort(([a], [b]) => a.localeCompare(b)),
    ),
    truncated: trace.truncated,
    scope: "recorded_dependencies_only",
  };
}

/** Summarize a half-open window contained in the saved capture. elapsedClocks is
 * endCycle-firstCycle; storage totals count adjacent sampled edges, so a one-
 * clock window has no storage link. Loads and holds are aggregate word-clocks:
 * simultaneous words add and must not be added to elapsedClocks. usedOnly defaults
 * true to match the viewer; false includes all recorded storage history.
 *
 * Actor/activation/operation/task filters apply to events and explicit storage
 * associations. Installed cells always describe the whole unique catalogue.
 * selectedEvent independently requests backward ancestry, including off-window
 * contributors. waitOperations must name producer-qualified per-clock wait
 * observations; absent classification returns null sample counts. Completeness
 * refers only to the recording's declared observer scope, never complete causal
 * coverage. All work is bounded by saved rows, not the numeric clock interval.
 * Invalid bounds, unknown selected events and inexact aggregate counts reject.
 */
export function windowMetrics(model, options = {}) {
  const capture = model.bundle.capture;
  const {
    firstCycle = capture.first_cycle,
    endCycle = capture.end_cycle,
    selectedEvent = null,
    usedOnly = true,
    waitOperations = [],
    maxRecords = 1_000_000,
    maxTraceEvents = 10_000,
  } = options;
  requireCount(firstCycle, "first clock");
  requireCount(endCycle, "end clock");
  requireCount(maxRecords, "record bound", true);
  requireCount(maxTraceEvents, "ancestry bound", true);
  if (
    firstCycle < capture.first_cycle ||
    endCycle > capture.end_cycle ||
    firstCycle >= endCycle
  )
    throw Error("Metrics: window outside capture");
  if (
    typeof usedOnly !== "boolean" ||
    !Array.isArray(waitOperations) ||
    waitOperations.some((name) => typeof name !== "string" || !name.length)
  )
    throw Error("Metrics: invalid storage policy or wait classification");
  const records =
    model.events.size +
    model.versions.size +
    model.lifetimes.size +
    model.cells.size +
    model.edges.length;
  if (records > maxRecords) throw Error("Metrics: record bound exceeded");
  const selection = { ...options, firstCycle, endCycle, usedOnly };
  const events = eventsInWindow(model, selection);
  return {
    interval: { firstCycle, endCycle, elapsedClocks: endCycle - firstCycle },
    coverage: {
      completeWithinObserverScope: capture.complete,
      evidence: capture.evidence ?? null,
      incarnations: [...model.epochs.values()]
        .filter(
          (epoch) =>
            epoch.first_cycle < endCycle && epoch.end_cycle > firstCycle,
        )
        .map((epoch) => epoch.id),
    },
    recordedEvents: events.length,
    storage: storageTotals(model, selection),
    installed: installedPopulation(model),
    waits: waitSamples(events, waitOperations),
    ancestry: ancestrySummary(
      model,
      selectedEvent,
      firstCycle,
      endCycle,
      maxTraceEvents,
    ),
  };
}
