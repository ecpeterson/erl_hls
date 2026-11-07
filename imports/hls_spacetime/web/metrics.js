/** Summaries keep installed-cell distribution separate from recorded temporal
 * activity and overlapping storage occupancy. No cell count is device capacity,
 * and no observed dependency span is a complete critical-path result. */
import { eventsInWindow, storageSegments, traceDependencies } from "./model.js";

/** Keep bounded browser arithmetic exact instead of rounding large totals. */
function requireCount(value, label, positive = false) {
  if (!Number.isSafeInteger(value) || value < (positive ? 1 : 0))
    throw Error(`Metrics: invalid ${label}`);
}

/** Count each catalogue identity once, including explicitly unplaced cells.
 * Missing catalogue evidence is null population, never measured zero area. */
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

/** Fixed square bins count unique catalogue identities at measured tile-grid
 * coordinates, independently of event filters or repeated clock layers. Bins
 * align to coordinate zero and include no inferred empty sites. Their counts
 * describe concentration, not utilization: no site-capacity census is supplied.
 * Unknown units suppress binning; missing coordinates and primitive kinds stay
 * explicit. Work scales with catalogue cells, never the extent of the grid. */
function spatialDistribution(model, binSizeTiles) {
  if (!model.catalogue) return null;
  const unit = model.catalogue.coordinate_unit ?? null;
  const qualified = unit === "tile_grid";
  const bins = new Map(),
    tiles = new Set();
  let placedCells = 0,
    unknownKindCells = 0;
  for (const cell of model.cells.values()) {
    const kind =
      typeof cell.kind === "string" && cell.kind.length ? cell.kind : "unknown";
    if (kind === "unknown") unknownKindCells++;
    if (!Number.isFinite(cell.x) || !Number.isFinite(cell.y)) continue;
    placedCells++;
    if (!qualified) continue;
    requireCount(cell.x, "tile X coordinate");
    requireCount(cell.y, "tile Y coordinate");
    const x = Math.floor(cell.x / binSizeTiles) * binSizeTiles,
      y = Math.floor(cell.y / binSizeTiles) * binSizeTiles,
      key = `${x}/${y}`;
    if (!bins.has(key)) bins.set(key, { x, y, cells: 0, kinds: new Map() });
    const bin = bins.get(key);
    bin.cells++;
    bin.kinds.set(kind, (bin.kinds.get(kind) ?? 0) + 1);
    tiles.add(`${cell.x}/${cell.y}`);
  }
  const rows = [...bins.values()].sort((a, b) => a.y - b.y || a.x - b.x);
  let peakBinCells = 0;
  for (const row of rows) peakBinCells = Math.max(peakBinCells, row.cells);
  return {
    status: qualified ? "tile_grid" : "unknown_coordinate_unit",
    coordinateUnit: unit,
    binSizeTiles,
    cells: model.cells.size,
    placedCells,
    unplacedCells: model.cells.size - placedCells,
    unknownKindCells,
    occupiedTiles: qualified ? tiles.size : null,
    occupiedBins: qualified ? rows.length : null,
    peakBinCells: qualified ? peakBinCells : null,
    bins: rows.map(({ x, y, cells, kinds }) => ({
      x,
      y,
      installedCells: cells,
      byKind: Object.fromEntries(
        [...kinds].sort(([a], [b]) => a.localeCompare(b)),
      ),
    })),
    scope: "unique_installed_cells_not_capacity_or_switching",
  };
}

/** Count recorded operations once at their observed clocks. Simultaneous
 * operations add; missing operations are not idle-time evidence. These samples
 * obey the window/semantic filters and never assign activity to placed gates. */
function recordedActivity(events) {
  const clocks = new Map(),
    operations = new Map();
  let peakEventsPerClock = 0;
  for (const event of events) {
    const count = (clocks.get(event.cycle) ?? 0) + 1;
    clocks.set(event.cycle, count);
    peakEventsPerClock = Math.max(peakEventsPerClock, count);
    const operation = event.operation ?? "unknown";
    operations.set(operation, (operations.get(operation) ?? 0) + 1);
  }
  return {
    eventSamples: events.length,
    clocksWithEvents: clocks.size,
    peakEventsPerClock,
    byOperation: Object.fromEntries(
      [...operations].sort(([a], [b]) => a.localeCompare(b)),
    ),
    byClock: [...clocks]
      .sort(([a], [b]) => a - b)
      .map(([cycle, eventSamples]) => ({ cycle, eventSamples })),
    scope: "recorded_operations_not_electrical_activity_or_idle_time",
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

/** A target constraint or static-path delay never establishes an execution
 * period. Keep physical elapsed time unknown; an explicitly supplied what-if
 * multiplies interval clocks by its hypothetical period once. Nanoseconds use
 * bounded floating-point arithmetic, separately from exact clock counts. */
function intervalTiming(model, elapsedClocks, whatIfPeriodNs) {
  let whatIf = null;
  if (whatIfPeriodNs !== null) {
    if (
      typeof whatIfPeriodNs !== "number" ||
      !Number.isFinite(whatIfPeriodNs) ||
      whatIfPeriodNs <= 0 ||
      whatIfPeriodNs > Number.MAX_SAFE_INTEGER
    )
      throw Error("Metrics: invalid hypothetical clock period");
    const elapsedNs = elapsedClocks * whatIfPeriodNs;
    if (!Number.isFinite(elapsedNs) || elapsedNs > Number.MAX_SAFE_INTEGER)
      throw Error("Metrics: hypothetical elapsed time exceeds numeric bound");
    whatIf = {
      periodNs: whatIfPeriodNs,
      elapsedClocks,
      elapsedNs,
      scope: "hypothetical_clock_period_not_execution_measurement",
    };
  }
  return {
    execution: null,
    reason:
      model.document.measurement?.target_met === false
        ? "failed_target_is_not_execution_period"
        : "no_qualified_execution_period",
    whatIf,
    scope: "elapsed_clocks_times_period_without_adding_static_path_delay",
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
 * associations. Installed cells and fixed tileBinSize square bins always
 * describe the whole unique catalogue; activity counts selected recorded
 * operations, never inferred switching or physical resource demand.
 * selectedEvent independently requests backward ancestry, including off-window
 * contributors. waitOperations must name producer-qualified per-clock wait
 * observations; absent classification returns null sample counts. Completeness
 * refers only to the recording's declared observer scope, never complete causal
 * coverage. whatIfPeriodNs optionally supplies a hypothetical period; it never
 * qualifies execution time or adds static delays. All work is bounded by saved
 * rows, not the numeric clock interval.
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
    tileBinSize = 16,
    whatIfPeriodNs = null,
  } = options;
  requireCount(firstCycle, "first clock");
  requireCount(endCycle, "end clock");
  requireCount(maxRecords, "record bound", true);
  requireCount(maxTraceEvents, "ancestry bound", true);
  requireCount(tileBinSize, "tile bin size", true);
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
    timing: intervalTiming(model, endCycle - firstCycle, whatIfPeriodNs),
    recordedEvents: events.length,
    storage: storageTotals(model, selection),
    installed: installedPopulation(model),
    spatial: spatialDistribution(model, tileBinSize),
    activity: recordedActivity(events),
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
