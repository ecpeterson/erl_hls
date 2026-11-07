/** Local rendering of saved cycle evidence. All ancestry comes from model.js;
 * screen positions and same-clock annotations never create graph edges. */
import {
  eventsInWindow,
  annotationEvents,
  traceDependencies,
  eventPlacement,
  resourcePlacement,
  resourcesForEvent,
  eventDetails,
  storageSegments,
  storageLifetimes,
} from "./model.js";
import { eventFootprint, accessConnections } from "./footprint.js";
import { nativePaths } from "./native-paths.js";
import { nativeRoutes } from "./native-routes.js";
import { loadComputations } from "./computation-loader.js";
import { loadRecording } from "./recording-loader.js";
import { loadPreparedRenderWorker } from "./prepared-loader.js";
import {
  createPreparedComputations,
  preparedComputationLayers,
  preparedCircuitPaint,
} from "./prepared-computations.js";
import { createScene3D } from "./scene3d.js";
import { clockPoint, sceneBounds, occupiedBins } from "./scene-layout.js";
import {
  sceneColor,
  computationColor,
  timingColor,
  COMPUTATION_SHARED_COLOR,
  DIRECTION_SOURCE_COLOR,
  DIRECTION_SINK_COLOR,
} from "./perceptual-color.js";
import { cachePaint } from "./paint-cache.js";
import {
  createComputations,
  computationLayers,
  computationConnection,
} from "./computation-routes.js";
import {
  computationSelection,
  computationWindowUnion,
} from "./computation-view.js";
import { windowMetrics } from "./metrics.js";
import { layoutLabels } from "./labels.js";
import { spatialPoints, spatialPairs } from "./visibility.js";
const $ = (id) => document.getElementById(id);
const colors = [
  "#67d7c3",
  "#7dafe7",
  "#df9fba",
  "#d6c674",
  "#a4abe9",
  "#ecaa77",
  "#88c6d4",
  "#a6cb9a",
];
const state = {
  model: null,
  selected: null,
  trace: null,
  traceDirection: "backward",
  annotation: null,
  first: 0,
  window: 24,
  scene: null,
  sceneContent: null,
  sceneDirty: true,
  sceneError: null,
  hitsDirty: true,
  frameFull: false,
  autoFit: true,
  eventCache: null,
  loadTimings: {},
  spacing: 8,
  hits: [],
  flatHits: [],
  storageHits: [],
  storageCache: null,
  metricsCache: null,
  storagePointCache: new Map(),
  pointCache: new Map(),
  footprintCache: new Map(),
  nativePaths: [],
  nativePath: null,
  nativeRoutes: new Map(),
  computations: null,
  circuitCache: null,
  circuitPaintCache: new Map(),
  loadController: null,
  traceNote: "",
  resourceCache: new Map(),
  actors: [],
  resource: null,
  cell: null,
  focusVersion: null,
  frame: 0,
  index: new Map(),
  loadSequence: 0,
};
/** Escape untrusted labels before placing small templates in the DOM. */
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
/** Render plain diagnostic messages without exposing executable markup. */
function notice(message, warning = false) {
  $("notice").textContent =
    state.sceneError && message !== state.sceneError
      ? `${message} ${state.sceneError}`
      : message;
  $("notice").classList.toggle("warning", warning || Boolean(state.sceneError));
}
/** Build options with preserved selection when a related filter changes. */
function options(id, values, title, previous = "") {
  const node = $(id);
  node.replaceChildren(new Option(title, ""));
  for (const value of values) node.add(new Option(value, value));
  node.value = values.includes(previous) ? previous : "";
}
/** Read current explicit filters; unknown lineage is never assigned an actor. */
function filters() {
  return Object.fromEntries(
    ["actor", "activation", "operation", "task"].map((k) => [k, $(k).value]),
  );
}
/** Return stable actor color, or grey when no actor association exists. */
function color(event) {
  const i = state.actors.indexOf(event.actor);
  return i < 0 ? "#8c99a4" : colors[i % colors.length];
}
/** Bound and load a JSON projection; no executable or Erlang-term input is accepted. */
async function loadDocument(
  model,
  integrity = "File supplied locally; source evidence not revalidated",
  computationData = null,
) {
  const computations = computationData?.prepared
    ? createPreparedComputations(model, computationData.prepared)
    : createComputations(
        model,
        computationData?.attachment,
        computationData?.routeNets,
      );
  const paths = nativePaths(model);
  const routes = nativeRoutes(model);
  const routeIndex = new Map(
    routes.map((route) => [`${route.pathId}/${route.arcIndex}`, route]),
  );
  // Include routing excursions; a route can leave the placed-cell bounding box.
  if (model.geometryBounds) {
    const bounds = { ...model.geometryBounds };
    const seen = new Set();
    for (const route of routes) {
      for (const object of [
        ...route.pips,
        ...route.nodes.flatMap((node) => node.wires),
      ]) {
        if (
          seen.has(object.id) ||
          !Number.isFinite(object.x) ||
          !Number.isFinite(object.y)
        )
          continue;
        seen.add(object.id);
        bounds.minX = Math.min(bounds.minX, object.x);
        bounds.maxX = Math.max(bounds.maxX, object.x);
        bounds.minY = Math.min(bounds.minY, object.y);
        bounds.maxY = Math.max(bounds.maxY, object.y);
      }
    }
    for (const net of computationData?.routeNets ?? []) {
      for (const object of net.pips ?? []) extendBounds(bounds, object);
      for (const node of net.nodes ?? [])
        for (const wire of node.wires ?? []) extendBounds(bounds, wire);
    }
    model.geometryBounds = bounds;
  }
  state.nativeRoutes = routeIndex;
  state.computations = computations;
  state.circuitCache = null;
  state.circuitPaintCache.clear();
  for (const id of [
    "computation-circuits",
    "circuit-role",
    "circuit-timing",
    "circuit-delay",
    "circuit-unknown",
    "circuit-selected",
  ])
    $(id).disabled = !computations;
  $("computation-circuits").checked = Boolean(computations);
  $("circuit-role").value = "";
  $("circuit-timing").value = "registered_launch";
  $("circuit-delay").value = "0";
  $("circuit-unknown").checked = true;
  $("circuit-selected").checked = false;
  state.model = model;
  state.autoFit = true;
  state.eventCache = null;
  state.selected = null;
  state.trace = null;
  state.annotation = null;
  state.resource = null;
  state.cell = null;
  state.focusVersion = null;
  state.pointCache.clear();
  state.resourceCache.clear();
  state.storageCache = null;
  state.metricsCache = null;
  state.storagePointCache.clear();
  state.footprintCache.clear();
  state.nativePaths = paths;
  state.nativePath = null;
  $("native-path").replaceChildren(new Option("No static path overlay", ""));
  for (const path of state.nativePaths)
    $("native-path").add(
      new Option(
        `${path.id} · ${path.dataDelayNs} ns data · ${path.logicLevels} levels`,
        path.id,
      ),
    );
  $("native-path").disabled = !state.nativePaths.length;
  state.actors = [...new Set(model.orderedEvents.map((e) => e.actor))].sort();
  options("actor", state.actors, "All actors");
  options(
    "operation",
    [...new Set(model.orderedEvents.map((e) => e.operation))].sort(),
    "All operations",
  );
  options(
    "task",
    [...new Set(model.orderedEvents.map((e) => e.task))].sort(),
    "All tasks",
  );
  options("resource", [...model.resources.keys()], "Select a resource");
  updateActivations();
  $("example").replaceChildren(new Option("Choose a recorded example", ""));
  (model.document.examples ?? []).forEach((example, i) =>
    $("example").add(
      new Option(
        example.title ?? example.label ?? example.id ?? `Example ${i + 1}`,
        String(i),
      ),
    ),
  );
  state.first = selectedBounds().firstCycle;
  state.window = Math.min(24, selectedBounds().endCycle - state.first);
  const logical = !model.catalogue;
  $("title").textContent = model.document.title ?? "Saved execution";
  $("subtitle").textContent =
    `${model.bundle.capture.device} · ${model.bundle.capture.clock} · ${model.bundle.evidence}`;
  $("space-unit").textContent = logical
    ? "Logical resource / address lanes · time flows down"
    : "Device tile coordinates · time flows down";
  $("flat-subtitle").textContent = logical
    ? "Logical addresses — physical placement unmeasured"
    : "Unique installed cells, counted once";
  $("identities").textContent = JSON.stringify(
    {
      build: model.bundle.build,
      checkpoint: model.catalogue?.checkpoint ?? null,
      provenance: model.document.provenance,
    },
    null,
    2,
  );
  $("scope").innerHTML =
    `<p><b>${esc(model.bundle.evidence)}</b> · ${model.bundle.capture.complete ? "complete within declared observer scope" : "incomplete capture"}</p><p>${esc(integrity)}</p><p>The time axis reports clocks. Native wire/PIP locations have schematic spans between them; logical connections remain schematic.</p><details><summary>Reported evidence scope</summary>${(model.document.scope ?? []).map((value) => `<p>${esc(value)}</p>`).join("")}</details><details><summary>Observer coverage</summary>${model.bundle.capture.observers.map((observer) => `<p>${esc(observer.id)}: ${esc(observer.scope)}</p>`).join("")}</details>`;
  const measurement = model.document.measurement;
  const failed = measurement?.target_met === false;
  notice(
    failed
      ? `Saved measurement reports a failed ${measurement.target_period_ns} ns target. Execution time is shown in clocks.`
      : logical
        ? "Saved logical capture loaded. Physical placement is unmeasured."
        : "Saved physical capture loaded. Execution time is shown in clocks.",
    failed,
  );
  renderNativePath();
  render();
}
/** Install complete prepared geometry after the recording is already interactive.
 * Native source evidence remains retained at manifest references, not in UI memory. */
function installComputationData(data) {
  state.computations = data.prepared
    ? createPreparedComputations(state.model, data.prepared)
    : createComputations(state.model, data.attachment, data.routeNets);
  if (state.computations.bounds)
    state.model.geometryBounds = state.computations.bounds;
  else
    for (const net of data.routeNets ?? []) {
      for (const pip of net.pips ?? [])
        extendBounds(state.model.geometryBounds, pip);
      for (const node of net.nodes ?? [])
        for (const wire of node.wires ?? [])
          extendBounds(state.model.geometryBounds, wire);
    }
  for (const key of [
    "pointCache",
    "resourceCache",
    "footprintCache",
    "storagePointCache",
    "circuitPaintCache",
  ])
    state[key].clear();
  state.circuitCache = null;
  for (const id of [
    "computation-circuits",
    "circuit-role",
    "circuit-timing",
    "circuit-delay",
    "circuit-unknown",
    "circuit-selected",
  ])
    $(id).disabled = false;
  $("computation-circuits").checked = true;
  state.autoFit = true;
  render();
}

/** Small visible timings distinguish preparation from browser work. */
function showLoadTimings() {
  $("load-metrics").textContent = Object.entries(state.loadTimings)
    .map(([key, value]) => `${key}: ${(value / 1000).toFixed(2)} s`)
    .join(" · ");
}

/** Recorded step bounds; annotation anchors reference existing graph events only. */
function selectedBounds() {
  const d = state.model.document,
    s = d.selection ?? {},
    b = state.model.bundle.capture;
  return {
    firstCycle:
      s.firstCycle ?? s.first_cycle ?? s.interval?.first_cycle ?? b.first_cycle,
    endCycle: s.endCycle ?? s.end_cycle ?? s.interval?.end_cycle ?? b.end_cycle,
  };
}
/** Rebuild activation choices only from the selected actor, preserving identity. */
function updateActivations() {
  if (!state.model) return;
  const prior = $("activation").value,
    actor = $("actor").value;
  options(
    "activation",
    [
      ...new Set(
        state.model.orderedEvents
          .filter(
            (e) =>
              (!actor || e.actor === actor) &&
              e.cycle >= state.first &&
              e.cycle < state.first + state.window,
          )
          .map((e) => e.activation),
      ),
    ].sort(),
    "All activations",
    prior,
  );
}
/** Clip controls to the capture while retaining the complete graph in memory. */
function normalizeWindow() {
  const c = state.model.bundle.capture;
  state.window = Math.max(
    1,
    Math.min(c.end_cycle - c.first_cycle, Math.round(state.window) || 24),
  );
  state.first = Math.max(
    c.first_cycle,
    Math.min(c.end_cycle - state.window, Math.round(state.first) || 0),
  );
  $("first").value = state.first;
  $("first").max = c.end_cycle - 1;
  $("first").min = c.first_cycle;
  $("window").value = state.window;
  $("window").max = c.end_cycle - c.first_cycle;
  $("position").min = c.first_cycle;
  $("position").max = c.end_cycle - state.window;
  $("position").value = state.first;
  $("window-label").textContent =
    `C${state.first}–${state.first + state.window - 1}`;
}
/** Queue one canvas repaint for related inputs or pointer movement. */
function repaint(cameraOnly = false) {
  if (!cameraOnly) {
    state.sceneDirty = true;
    state.frameFull = true;
  }
  if (!state.frame)
    state.frame = requestAnimationFrame(() => {
      state.frame = 0;
      const full = state.frameFull;
      state.frameFull = false;
      try {
        drawStack();
      } catch (error) {
        state.sceneError = `${error.message} Narrow the clock window or choose Occupied tiles; no geometry prefix was rendered.`;
        state.sceneDirty = false;
        state.sceneContent = null;
        state.hits = [];
        state.storageHits = [];
        state.scene?.setScene({});
        state.scene?.render({
          width: $("stack").clientWidth,
          height: $("stack").clientHeight,
          pixelRatio: window.devicePixelRatio || 1,
        });
        notice(state.sceneError, true);
      }
      if (full) {
        if ($("flat-panel").open) drawFlat();
        drawTimeline();
      }
    });
}
/** Synchronize controls, visible event list and selected evidence. */
function render() {
  if (!state.model) return;
  normalizeWindow();
  updateActivations();
  clearFilteredSelection();
  renderMetrics();
  const seeds = new Set(selectionEvents().map((event) => event.id));
  const events = visibleEvents();
  $("fit-selection").disabled =
    !seeds.size && !state.resource && !state.focusVersion;
  $("event-count").textContent =
    `${events.length.toLocaleString()} operations · first 250 listed`;
  $("events").innerHTML =
    events
      .slice(0, 250)
      .map(
        (e) =>
          `<button class="event-row ${seeds.has(e.id) ? "active" : ""}" data-event="${esc(e.id)}"><span>C${e.cycle}</span><span style="color:${color(e)}">${esc(e.actor)}</span><span>${esc(e.operation)}</span><span class="id">${esc(e.id)}</span></button>`,
      )
      .join("") ||
    '<p class="empty">No operations match these filters and clocks.</p>';
  renderInspector();
  renderResource();
  repaint();
}
/** Current-window clocks and overlapping logical storage work use different units.
 * Waits require the producer's explicit per-clock operation classification. */
function renderMetrics() {
  const options = {
    firstCycle: state.first,
    endCycle: state.first + state.window,
    ...filters(),
    usedOnly: !$("full-storage").checked,
    whatIfPeriodNs:
      $("what-if-period").value === ""
        ? null
        : Number($("what-if-period").value),
    waitOperations:
      (state.model.document.metric_hints ?? state.model.bundle.metric_hints)
        ?.wait_operations ?? [],
  };
  const key = JSON.stringify(options);
  if (state.metricsCache?.key !== key)
    state.metricsCache = { key, value: windowMetrics(state.model, options) };
  const metrics = state.metricsCache.value;
  const { storage, waits, installed } = metrics;
  const { spatial, activity, timing } = metrics;
  $("spatial-summary").textContent =
    spatial?.status === "tile_grid"
      ? `${spatial.binSizeTiles} × ${spatial.binSizeTiles} tile bins · peak ${spatial.peakBinCells.toLocaleString()} installed cells · ${spatial.occupiedBins} occupied bins · ${spatial.unplacedCells} unplaced. Blue shading counts unique installed cells; it is not capacity utilization or clock activity.`
      : "Installed-cell concentration unavailable: no qualified tile coordinates.";
  $("activity-summary").textContent =
    `${activity.eventSamples.toLocaleString()} recorded operations on ${activity.clocksWithEvents.toLocaleString()} clocks in view · peak ${activity.peakEventsPerClock} operations per clock. Counts follow filters; they are not electrical switching or proof that other clocks were idle.`;
  $("timing-summary").textContent =
    (timing.reason === "failed_target_is_not_execution_period"
      ? "Physical elapsed time unknown: the native target failed timing. "
      : "Physical elapsed time unknown: no qualified execution period. ") +
    (timing.whatIf
      ? `Hypothetical only: ${timing.whatIf.elapsedClocks} clocks × ${timing.whatIf.periodNs} ns = ${timing.whatIf.elapsedNs.toLocaleString(undefined, { maximumFractionDigits: 6 })} ns. Static path delays are not added again.`
      : "Enter a period for an explicitly hypothetical clocks × period calculation.");
  $("metrics").innerHTML =
    `<div><strong>${metrics.interval.elapsedClocks.toLocaleString()}</strong><span>clocks in view</span></div><div><strong>${storage.totalWordClocks.toLocaleString()}</strong><span>logical word-clocks</span></div><div><strong>${installed ? installed.cells.toLocaleString() : "—"}</strong><span>unique installed cells</span></div>`;
  let detail = $("metrics-detail");
  if (!detail) {
    detail = document.createElement("p");
    detail.id = "metrics-detail";
    detail.className = "storage-summary";
    $("metrics").closest(".summary").after(detail);
  }
  const waitText =
    waits.status === "unclassified"
      ? "Waits: unclassified in this capture."
      : `Wait observations: ${waits.eventSamples.toLocaleString()} on ${waits.clockSamples.toLocaleString()} clocks (${waits.operations.join(", ")}).`;
  detail.textContent =
    `${storage.loadWordClocks.toLocaleString()} load + ${storage.holdWordClocks.toLocaleString()} hold word-clocks · ${storage.policy === "recorded_uses" ? "recorded uses" : "full history"}. ` +
    "Concurrent words add; this is storage residence, not elapsed time. " +
    waitText +
    (metrics.coverage.completeWithinObserverScope
      ? " Counts cover the declared observer scope only."
      : " Incomplete capture: counts cover recorded evidence only.");
}
/** Resolve selection seeds without creating an event for an application annotation. */
function selectionEvents() {
  if (state.selected) return [state.model.events.get(state.selected)];
  return state.annotation
    ? annotationEvents(state.model, state.annotation)
    : [];
}
/** Semantic filters clear excluded selections across the full capture, not the window. */
function clearFilteredSelection() {
  const seeds = selectionEvents();
  if (!seeds.length) return;
  const matching = new Set(
    eventsInWindow(state.model, filters()).map((event) => event.id),
  );
  if (seeds.some((event) => matching.has(event.id))) return;
  state.selected = null;
  state.trace = null;
  state.annotation = null;
  state.focusVersion = null;
  state.resource = null;
  state.cell = null;
  state.traceNote = "";
  $("resource").value = "";
  $("example").value = "";
}
/** Shared contributors are visited once when following several completion endpoints. */
function traceSelection(direction) {
  const seeds = selectionEvents().map((event) => event.id);
  if (!seeds.length) return;
  state.trace = traceDependencies(state.model, seeds, { direction });
  state.traceDirection = direction;
}
/** One half-open window for all synchronized views. */
function visibleEvents() {
  const opts = {
    firstCycle: state.first,
    endCycle: state.first + state.window,
    ...filters(),
  };
  const key = JSON.stringify(opts);
  if (state.eventCache?.key !== key)
    state.eventCache = { key, events: eventsInWindow(state.model, opts) };
  return state.eventCache.events;
}
/** Cache logical-resource layout. Unknown placement occupies a labelled rail. */
function resourcePoint(id) {
  if (state.resourceCache.has(id)) return state.resourceCache.get(id);
  const model = state.model,
    placement = resourcePlacement(model, id),
    cells = placement.cells.filter(
      (c) => Number.isFinite(c.x) && Number.isFinite(c.y),
    );
  const bounds = model.geometryBounds;
  let point;
  if (cells.length && bounds) {
    const x = cells.reduce((s, c) => s + c.x, 0) / cells.length,
      y = cells.reduce((s, c) => s + c.y, 0) / cells.length;
    point = {
      x: ((x - bounds.minX) / (bounds.maxX - bounds.minX || 1) - 0.5) * 2,
      y: ((y - bounds.minY) / (bounds.maxY - bounds.minY || 1) - 0.5) * 2,
      physical: true,
    };
  } else {
    const ids = [...model.resources.keys()],
      i = ids.indexOf(id);
    point = {
      x: model.catalogue ? 1.3 : ((i % 5) - 0.5) * 0.65,
      y: model.catalogue
        ? -1 + (2 * i) / Math.max(1, ids.length - 1)
        : Math.floor(i / 5) * 0.5,
      physical: false,
    };
  }
  state.resourceCache.set(id, point);
  return point;
}
/** Position an operation at the centroid of its explicit resource groups only. */
function eventPoint(event) {
  if (event.access?.kind === "read_result" && state.model.catalogue)
    return unknownStoragePoint(event.access.resource);
  if (state.pointCache.has(event.id)) return state.pointCache.get(event.id);
  const ids = resourcesForEvent(event),
    points = ids.map(resourcePoint);
  const known = points.filter((p) => p.physical),
    use = known.length ? known : points;
  const point = use.length
    ? {
        x: use.reduce((s, p) => s + p.x, 0) / use.length,
        y: use.reduce((s, p) => s + p.y, 0) / use.length,
        physical: known.length > 0,
      }
    : {
        x: 1.55,
        y:
          -1 +
          (2 * Math.max(0, state.actors.indexOf(event.actor))) /
            Math.max(1, state.actors.length - 1),
        physical: false,
      };
  if (!state.model.catalogue && event.access)
    point.y += event.access.address * 0.6;
  state.pointCache.set(event.id, point);
  return point;
}
/** Normalize measured tile coordinates without moving any point to a centroid. */
function cellPoint(cell) {
  const b = state.model.geometryBounds;
  return {
    x: ((cell.x - b.minX) / (b.maxX - b.minX || 1) - 0.5) * 2,
    y: ((cell.y - b.minY) / (b.maxY - b.minY || 1) - 0.5) * 2,
    physical: true,
  };
}
/** Native cells sharing a tile overlap at this scale; retain their identities
 * while drawing one glyph per occupied tile. Unknown bits keep their own rail. */
function accessGeometry(event) {
  const key = event.access
    ? JSON.stringify([
        event.access.resource,
        event.access.kind,
        event.access.mask ?? null,
        event.access.read_mask ?? null,
      ])
    : event.id;
  if (state.footprintCache.has(key)) return state.footprintCache.get(key);
  const footprint = eventFootprint(state.model, event.id);
  const tiles = new Map();
  for (const cell of footprint.cells) {
    const key = `${cell.x}/${cell.y}`;
    if (!tiles.has(key)) tiles.set(key, { ...cellPoint(cell), cells: [] });
    tiles.get(key).cells.push(cell.id);
  }
  const points = [...tiles.values()];
  if (
    footprint.resource &&
    (footprint.unknownBits ||
      footprint.unplacedCells.length ||
      footprint.candidateCells.length)
  )
    points.push({ ...unknownStoragePoint(footprint.resource), cells: [] });
  if (!points.length) {
    // The response's copy/consumer logic is not located at the source FF.
    const resource = footprint.resource;
    points.push(
      resource && state.model.catalogue
        ? { ...unknownStoragePoint(resource), cells: [] }
        : eventPoint(event),
    );
  }
  const geometry = { footprint, points };
  if (state.footprintCache.size >= 512) state.footprintCache.clear();
  state.footprintCache.set(key, geometry);
  return geometry;
}
/** Hide only geometry without native coordinates. Logical-only captures retain
 * their lanes; this display preference never filters graph records or metrics. */
function mappedOnly() {
  return Boolean(state.model.catalogue) && !$("show-unmapped").checked;
}
/** Extend chip space with measured wire/PIP coordinates, never inferred paths. */
function extendBounds(bounds, object) {
  if (!Number.isFinite(object.x) || !Number.isFinite(object.y)) return;
  bounds.minX = Math.min(bounds.minX, object.x);
  bounds.maxX = Math.max(bounds.maxX, object.x);
  bounds.minY = Math.min(bounds.minY, object.y);
  bounds.maxY = Math.max(bounds.maxY, object.y);
}

/** Cache the visible clock-layer unions independently of the camera. All graph
 * rows remain retained when functionality or static-delay filters hide geometry. */
function circuitLayers() {
  if (!state.computations || !$("computation-circuits").checked) return [];
  const selectedOnly = $("circuit-selected").checked;
  const key = JSON.stringify([
    state.first,
    state.window,
    filters(),
    selectedOnly,
    selectedOnly ? selectionEvents().map((e) => e.id) : null,
    $("circuit-role").value,
    $("circuit-timing").value,
    $("circuit-delay").value,
    $("circuit-unknown").checked,
  ]);
  if (state.circuitCache?.key === key) return state.circuitCache.layers;
  const supplied = selectedOnly
    ? computationSelection(
        selectionEvents(),
        eventsInWindow(state.model, filters()),
      )
    : visibleEvents();
  const generated = (
    state.computations.prepared ? preparedComputationLayers : computationLayers
  )(state.computations, supplied, {
    roles: $("circuit-role").value
      ? [$("circuit-role").value]
      : ["data", "enable", "reset"],
    minimumDelayNs: Number($("circuit-delay").value),
    timingMetric: $("circuit-timing").value,
    includeUnknownTiming: $("circuit-unknown").checked,
  });
  const layers = generated.filter(
    (layer) =>
      layer.cycle >= state.first && layer.cycle < state.first + state.window,
  );
  for (const layer of layers) layer.paint = circuitPaint(layer);
  state.circuitCache = {
    key,
    layers,
    flatPaint: circuitPaint(computationWindowUnion(layers)),
    selectionState: !selectedOnly
      ? null
      : !supplied.length
        ? "no_selection"
        : !generated.length
          ? "no_associated_writes"
          : !layers.length
            ? "outside_window"
            : null,
  };
  return layers;
}

/** Deduplicate shared circuitry per clock, keeping full occurrence/cone records.
 * Wire coordinates are unordered tile memberships. Only native PIP order gives
 * connectivity spans; the inter-PIP spans and pin/site links are schematic. */
function circuitPaint(layer) {
  if (state.computations.prepared) {
    const paint = preparedCircuitPaint(state.computations, layer);
    const key = paint.cacheKey;
    if (state.circuitPaintCache.has(key))
      return state.circuitPaintCache.get(key);
    const normalized = {
      ...paint,
      segments: paint.segments.map((row) => ({
        ...row,
        from: cellPoint(row.from),
        to: cellPoint(row.to),
      })),
      tiles: paint.tiles.map((row) => ({
        ...row,
        point: cellPoint(row.point),
      })),
      pips: paint.pips.map((row) => ({ ...row, point: cellPoint(row.point) })),
      cells: paint.cells.map((row) => ({
        ...row,
        point: cellPoint(row.point),
      })),
    };
    cachePaint(state.circuitPaintCache, key, normalized);
    return normalized;
  }
  const key = layer.cones
    .map((cone) => cone.id)
    .sort()
    .join("|");
  if (state.circuitPaintCache.has(key)) return state.circuitPaintCache.get(key);
  const index = state.computations,
    tiles = new Map(),
    pips = new Map(),
    segments = new Map(),
    cells = new Map();
  const rolesByArc = new Map();
  const point = (cellIndex) => {
    const cell = state.model.cells.get(index.cells[cellIndex]?.id);
    return cell && Number.isFinite(cell.x) && Number.isFinite(cell.y)
      ? cellPoint(cell)
      : null;
  };
  const add = (map, id, item, roles) => {
    if (!map.has(id)) map.set(id, { ...item, roles: new Set() });
    for (const role of roles) map.get(id).roles.add(role);
  };
  for (const cone of layer.cones) {
    for (const arc of cone.arcIndices) {
      if (!rolesByArc.has(arc)) rolesByArc.set(arc, new Set());
      rolesByArc.get(arc).add(cone.role);
    }
    for (const c of cone.cellIndices) {
      const p = point(c);
      if (p)
        add(cells, c, { point: p, boundary: index.cells[c].boundary }, [
          cone.role,
        ]);
    }
  }
  const dispositions = {};
  const segment = (key, from, to, roles, kind) => {
    if (from && to) add(segments, key, { from, to, kind }, roles);
  };
  for (const a of layer.arcs) {
    const arc = index.arcs[a],
      roles = rolesByArc.get(a),
      from = point(index.pins[arc.from].cell),
      to = point(index.pins[arc.to].cell);
    if (arc.kind === "logic") continue;
    const route = computationConnection(index, a);
    dispositions[route.disposition] =
      (dispositions[route.disposition] ?? 0) + 1;
    for (const node of route.nodes)
      for (const wire of node.wires)
        if (Number.isFinite(wire.x) && Number.isFinite(wire.y))
          add(
            tiles,
            `${arc.net}/${wire.x}/${wire.y}`,
            { point: cellPoint(wire) },
            roles,
          );
    const switches = route.pips.map((pip) => {
      if (!Number.isFinite(pip.x) || !Number.isFinite(pip.y)) return null;
      const p = cellPoint(pip);
      add(pips, `${arc.net}/${pip.id}`, { point: p }, roles);
      return p;
    });
    if (!route.nodes.length) {
      segment(`unresolved/${a}`, from, to, roles, "unresolved");
      continue;
    }
    const ends = [from, ...switches, to];
    const identities = [
      `pin/${arc.from}`,
      ...route.pips.map((pip) => pip.id),
      `pin/${arc.to}`,
    ];
    for (let i = 1; i < ends.length; i++)
      segment(
        `${arc.net}/${identities[i - 1]}/${identities[i]}`,
        ends[i - 1],
        ends[i],
        roles,
        i === 1 || i === ends.length - 1 ? "site" : "node",
      );
  }
  const result = {
    tiles: [...tiles.values()],
    pips: [...pips.values()],
    cells: [...cells.values()],
    segments: [...segments.values()],
    dispositions,
  };
  for (const rows of [result.tiles, result.pips, result.cells, result.segments])
    for (const row of rows)
      row.role = row.roles.size === 1 ? [...row.roles][0] : "mixed";
  cachePaint(state.circuitPaintCache, key, result);
  return result;
}

/** Horizontal native circuits are associated with recorded writes at that clock.
 * They are structural fan-in, including mux alternatives, not observed switching. */
function drawComputations(ctx, project, flat = false) {
  const layers = circuitLayers();
  const rendered =
    flat && layers.length
      ? [{ cycle: 0, paint: state.circuitCache.flatPaint }]
      : layers;
  const palette = {
    data: "#67d7c3",
    enable: "#efb96a",
    reset: "#bb9df0",
    mixed: "#dce5ea",
  };
  for (const layer of rendered) {
    const paint = layer.paint;
    ctx.globalAlpha = 0.5;
    for (const stroke of paint.segments) {
      if (stroke.kind === "unresolved" && mappedOnly()) continue;
      line(
        ctx,
        project(stroke.from, layer.cycle),
        project(stroke.to, layer.cycle),
        stroke.kind === "unresolved" ? "#84909c" : palette[stroke.role],
        0.7,
        true,
      );
    }
    ctx.globalAlpha = 0.55;
    for (const mark of paint.tiles) {
      const p = project(mark.point, layer.cycle);
      ctx.fillStyle = palette[mark.role];
      ctx.fillRect(p.x - 0.6, p.y - 0.6, 1.2, 1.2);
    }
    ctx.globalAlpha = 0.8;
    for (const mark of paint.pips) {
      const p = project(mark.point, layer.cycle);
      ctx.fillStyle = palette[mark.role];
      ctx.fillRect(p.x - 1, p.y - 1, 2, 2);
    }
    for (const mark of paint.cells) {
      const p = project(mark.point, layer.cycle);
      ctx.strokeStyle = palette[mark.role];
      if (mark.boundary === "sequential") {
        ctx.fillStyle = palette[mark.role];
        ctx.fillRect(p.x - 2, p.y - 2, 4, 4);
      } else if (mark.boundary === "constant") {
        ctx.beginPath();
        ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
        ctx.stroke();
      } else ctx.strokeRect(p.x - 1.5, p.y - 1.5, 3, 3);
    }
  }
  ctx.globalAlpha = 1;
  return layers;
}

/** Separate retained write/mapping counts from displayed cone/route counts. */
function renderCircuitSummary(layers) {
  const node = $("circuit-summary");
  if (!state.computations) {
    node.textContent =
      "Computation routing attachment unavailable for this recording.";
    return;
  }
  if (!$("computation-circuits").checked) {
    node.textContent =
      "Computation circuits hidden; complete evidence retained.";
    return;
  }
  const selectionMessages = {
    no_selection:
      "Select a recorded write or one of its explicit producers to show its circuits.",
    no_associated_writes:
      "The selection has no associated recorded write. Circuit overlays belong to writes and their explicit producers.",
    outside_window:
      "The selected writes lie outside the displayed clock window.",
  };
  const selectionMessage =
    selectionMessages[state.circuitCache?.selectionState];
  if (selectionMessage) {
    node.textContent = `${selectionMessage} The complete recording remains loaded; full native evidence is retained.`;
    return;
  }
  let writes = 0,
    arcs = 0,
    unknown = 0,
    untimed = 0,
    noLaunch = 0,
    filtered = 0,
    pips = 0;
  const dispositions = {};
  for (const layer of layers) {
    writes += layer.operations.length;
    arcs += layer.arcs.length;
    unknown += layer.coverage.unknownBits;
    for (const cone of layer.cones) {
      if (layer.timingMetric === "registered_launch") {
        if (cone.registeredTiming.status === "not_applicable") noLaunch++;
        else if (cone.registeredDelayNs === null) untimed++;
      } else if (cone.staticDelayNs === null) untimed++;
    }
    filtered += layer.coverage.filteredCones;
    pips += layer.paint.pips.length;
    for (const [key, value] of Object.entries(layer.paint.dispositions))
      dispositions[key] = (dispositions[key] ?? 0) + value;
  }
  const launchSummary =
    $("circuit-timing").value === "registered_launch"
      ? ` · ${noLaunch} displayed cones without a registered launch`
      : "";
  node.textContent =
    `${writes.toLocaleString()} recorded writes · ${arcs.toLocaleString()} native arcs summed across ${layers.length} clocks · ${pips.toLocaleString()} PIP locations summed across clocks · ${unknown.toLocaleString()} unmapped target-bit occurrences · ${untimed} displayed cones with unknown timing${launchSummary} · ${filtered} filtered write-cone occurrences. ` +
    Object.entries(dispositions)
      .map(([key, value]) => `${value.toLocaleString()} ${key} net arcs`)
      .join(" · ") +
    ". Structural fan-in includes unsensitized alternatives. Colors follow the selected legend. Delay is a conservative SDF bound in the selected scope, not STA slack or an execution period.";
}

/** Native routing is a tile footprint, not a metal-track layout. Solid markers
 * are actual selected-node wire tiles and PIP locations. Dotted node spans show
 * electrical connectivity between PIPs; site/logic geometry remains schematic.
 * The whole overlay is static and never adds execution dependencies. */
function drawNativePath(ctx, project, flat = false, labels = null) {
  const path = state.nativePath;
  if (!path) return;
  const cycle = Math.max(
    state.first,
    Math.min(
      state.first + state.window - 1,
      state.model.events.get(state.selected)?.cycle ?? state.first,
    ),
  );
  const point = (object) => project(cellPoint(object), cycle);
  const pins = path.steps.map((step) =>
    point(state.model.cells.get(step.cell)),
  );
  ctx.globalAlpha = 0.95;
  for (let i = 0; i < path.arcs.length; i++) {
    const arc = path.arcs[i],
      route = state.nativeRoutes.get(`${path.id}/${i}`);
    const from = pins[i],
      to = pins[i + 1];
    if (arc.kind === "logic") {
      line(ctx, from, to, "#ef88d1", 2, true);
      continue;
    }
    if (!route?.nodes.length) {
      line(ctx, from, to, "#d7ab77", 1.5, true);
      continue;
    }
    // A node's wires form an unordered electrical union. Do not sort them into
    // a fictitious trajectory; draw each measured tile membership separately.
    const tiles = new Set();
    for (const node of route.nodes)
      for (const wire of node.wires) {
        const id = `${wire.x}/${wire.y}`;
        if (
          !Number.isFinite(wire.x) ||
          !Number.isFinite(wire.y) ||
          tiles.has(id)
        )
          continue;
        tiles.add(id);
        const p = point(wire);
        ctx.fillStyle = "#b9adff";
        ctx.fillRect(p.x - 1.5, p.y - 1.5, 3, 3);
      }
    const switches = route.pips.map((pip) =>
      Number.isFinite(pip.x) && Number.isFinite(pip.y) ? point(pip) : null,
    );
    const ends = [from, ...switches, to];
    for (let j = 1; j < ends.length; j++) {
      if (!ends[j - 1] || !ends[j]) continue;
      line(
        ctx,
        ends[j - 1],
        ends[j],
        j === 1 || j === ends.length - 1 ? "#d7ab77" : "#a99ce8",
        1.4,
        true,
      );
    }
    for (const p of switches) {
      if (!p) continue;
      ctx.fillStyle = "#f4cf78";
      ctx.fillRect(p.x - 1.8, p.y - 1.8, 3.6, 3.6);
    }
  }
  for (const p of pins) {
    ctx.fillStyle = "#ef88d1";
    ctx.fillRect(p.x - 2, p.y - 2, 4, 4);
  }
  ctx.font = "10px ui-monospace,monospace";
  ctx.fillStyle = "#ffd3f2";
  const text = flat ? path.id : `${path.id} static · not cycle-attributed`;
  if (labels) labels.add(text, pins[0].x + 6, pins[0].y - 9, 80);
  else ctx.fillText(text, pins[0].x + 6, pins[0].y - 9);
  ctx.globalAlpha = 1;
}

/** Backing-store sizing follows CSS pixels while preserving sharp high-DPI text. */
function canvasContext(id) {
  const canvas = $(id),
    rect = canvas.getBoundingClientRect(),
    dpr = window.devicePixelRatio || 1;
  if (
    canvas.width !== Math.round(rect.width * dpr) ||
    canvas.height !== Math.round(rect.height * dpr)
  ) {
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
  }
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, rect.width, rect.height);
  return { canvas, ctx, w: rect.width, h: rect.height };
}
/** A schematic segment. Dashed lines signify residence or off-window clipping. */
function line(ctx, a, b, stroke, width = 1, dashed = false) {
  ctx.beginPath();
  ctx.setLineDash(dashed ? [4, 4] : []);
  ctx.strokeStyle = stroke;
  ctx.lineWidth = width;
  ctx.moveTo(a.x, a.y);
  ctx.lineTo(b.x, b.y);
  ctx.stroke();
  ctx.setLineDash([]);
}
/** Queue canvas labels in CSS pixels, then paint a non-overlapping subset.
 * Axis labels win over optional edge labels; exact details stay in the inspector. */
function canvasLabels(ctx, width, height) {
  const candidates = [];
  return {
    add(text, x, baseline, priority = 0, key = text) {
      const size = parseFloat(ctx.font) || 10;
      candidates.push({
        text,
        x,
        y: baseline - size,
        width: ctx.measureText(text).width,
        height: size + 2,
        baseline,
        priority,
        key,
        font: ctx.font,
        color: ctx.fillStyle,
      });
    },
    draw() {
      ctx.globalAlpha = 1;
      for (const label of layoutLabels(candidates, { width, height })) {
        ctx.font = label.font;
        ctx.fillStyle = label.color;
        ctx.fillText(label.text, label.x, label.baseline);
      }
    },
  };
}
/** Draw one footprint outline with no cloned geometry arrays. */
/** Residence can belong to a selected input chain, not only its final consumer.
 * The example's explicit version is preferred; this never adds an ancestry edge. */
function selectedLifetimes() {
  const found = new Map();
  if (state.focusVersion && state.model.lifetimes.has(state.focusVersion)) {
    const life = state.model.lifetimes.get(state.focusVersion);
    found.set(life.version, life);
  }
  const ids =
    state.trace?.events.map((e) => e.id) ??
    selectionEvents().map((event) => event.id);
  for (const id of ids)
    for (const life of eventDetails(state.model, id).lifetimes)
      found.set(life.version, life);
  return [...found.values()];
}

/** Query window histories independently of selection. Selection only emphasizes
 * evidence; it does not create cross-clock data or assign a word to an actor. */
function visibleStorage() {
  const options = {
    firstCycle: state.first,
    endCycle: state.first + state.window,
    ...filters(),
    usedOnly: !$("full-storage").checked,
  };
  const key = JSON.stringify(options);
  if (state.storageCache?.key !== key)
    state.storageCache = {
      key,
      segments: storageSegments(state.model, options),
    };
  return state.storageCache.segments;
}
/** Place unknown bits on their own labelled rail even for partly placed words. */
function unknownStoragePoint(resource) {
  const ids = [...state.model.resources.keys()],
    i = ids.indexOf(resource);
  return {
    x: 1.3,
    y: -1 + (2 * i) / Math.max(1, ids.length - 1),
    physical: false,
  };
}
/** Expand only an explicitly chosen word into qualified native cell positions.
 * Folded bits sharing a cell draw once. Unknown/candidate bits never acquire
 * positions merely because a neighbouring bit has a binding. */
function storagePoints(segment) {
  const expand =
    $("expand-storage").checked && state.resource === segment.resource;
  const key = JSON.stringify([segment.resource, segment.address, expand]);
  if (state.storagePointCache.has(key)) return state.storagePointCache.get(key);
  const save = (points) => {
    state.storagePointCache.set(key, points);
    return points;
  };
  const model = state.model,
    placement = resourcePlacement(model, segment.resource);
  const b = model.geometryBounds;
  if (!model.catalogue) {
    const base = resourcePoint(segment.resource);
    return save([
      { ...base, y: base.y + segment.address * 0.6, kind: "logical" },
    ]);
  }
  const placed = placement.cells.filter(
    (c) => Number.isFinite(c.x) && Number.isFinite(c.y),
  );
  const points =
    expand && b
      ? placed.map((c) => ({
          x: ((c.x - b.minX) / (b.maxX - b.minX || 1) - 0.5) * 2,
          y: ((c.y - b.minY) / (b.maxY - b.minY || 1) - 0.5) * 2,
          physical: true,
          kind: "cell",
          cell: c.id,
        }))
      : placed.length
        ? [{ ...resourcePoint(segment.resource), kind: "group" }]
        : [];
  if (
    !placed.length ||
    placement.unknownBits ||
    placement.candidateCells.length ||
    placed.length < placement.cells.length
  )
    points.push({ ...unknownStoragePoint(segment.resource), kind: "unknown" });
  return save(points);
}
/** Static timing, routed topology coverage and missing geometry are separate
 * from recorded use. Per-arc rows disclose gaps instead of drawing fanout trees. */
function renderNativePath() {
  const path = state.nativePath;
  const routes = path
    ? path.arcs.flatMap((arc, i) => {
        const route = state.nativeRoutes.get(`${path.id}/${i}`);
        return route ? [route] : [];
      })
    : [];
  const resolved = routes.filter(
    (route) => route.disposition === "resolved",
  ).length;
  const partial = routes.filter(
    (route) => route.disposition === "partial",
  ).length;
  $("native-path-summary").textContent = path
    ? `${path.dataDelayNs} ns data = ${path.logicDelayNs} logic + ${path.routeDelayNs} route; slack ${path.slackNs} ns. Static STA path; activity at this clock unknown. ` +
      (routes.length
        ? `${resolved} resolved + ${partial} partial of ${path.arcs.filter((arc) => arc.kind === "net").length} net arcs have branch geometry; partial endpoints retain unknown alternatives. Violet marks native wire tiles; gold marks routing switches. Dotted spans show node connectivity or missing site geometry, not exact metal bends.`
        : "No routing geometry supplied; dotted segments join placed cells only.")
    : state.nativePaths.length
      ? "Select a saved static path to inspect its ordered combinational logic and routing, independently of this clock's execution."
      : "Native timing-path detail is unavailable for this capture.";
  $("native-path-steps").innerHTML = path
    ? `<p>${esc(path.source)} → ${esc(path.endpoint)}</p><ol>${path.steps
        .map((step, i) => {
          const route = state.nativeRoutes.get(`${path.id}/${i}`);
          const arc = path.arcs[i];
          const detail = route
            ? `${route.disposition} · ${route.pips.length} PIPs · ${route.nodes.length} routed nodes · ${route.excludedPips} PIPs not displayed; gaps: ${route.gaps.map((gap) => (typeof gap === "string" ? gap : JSON.stringify(gap))).join(", ")}`
            : arc?.kind === "logic"
              ? "cell logic arc; internal geometry unavailable"
              : arc
                ? "wire geometry unavailable"
                : "endpoint";
          return `<li>${esc(step.pin)}${step.incrementNs === null ? "" : ` · +${step.incrementNs} ns`}<br><span class="muted">${esc(detail)}</span></li>`;
        })
        .join("")}</ol>`
    : "";
}

/** Assemble world geometry only when data or visibility changes. Camera motion
 * reuses the GPU buffers and does not redo graph queries, filtering or unions. */
function buildStackScene() {
  const result = {
    segments: [],
    markers: [],
    surfaces: [],
    events: [],
    storage: [],
    labels: [],
    focus: [],
    selection: [],
  };
  const world = (p, c) =>
    clockPoint(p, c, state.first, state.window, state.spacing);
  const segment = (
    a,
    b,
    color,
    radius = 0.002,
    kind = "route",
    colorEnd = color,
  ) => result.segments.push({ from: a, to: b, color, colorEnd, radius, kind });
  const marker = (position, color, size = 0.006) =>
    result.markers.push({ position, color, size });
  const interval = Math.max(1, Math.ceil(state.window / 8));
  for (let c = state.first; c < state.first + state.window; c += interval) {
    const corners = [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1],
    ].map(([x, y]) => world({ x, y }, c));
    for (let i = 0; i < 4; i++)
      segment(corners[i], corners[(i + 1) % 4], "#2d4855", 0.0009, "frame");
    result.labels.push({
      text: `C${c}`,
      position: world({ x: -1.04, y: -1.04 }, c),
      alternatives: corners,
    });
  }
  for (const epoch of state.model.bundle.capture.incarnations.slice(1)) {
    if (
      epoch.first_cycle < state.first ||
      epoch.first_cycle >= state.first + state.window
    )
      continue;
    const a = world({ x: -1, y: -1 }, epoch.first_cycle),
      b = world({ x: 1, y: -1 }, epoch.first_cycle);
    segment(a, b, "#ea8b94", 0.004, "reset");
    result.labels.push({ text: `Reset · ${epoch.id}`, position: a });
  }
  if ($("context").checked)
    for (const cell of state.model.cells.values()) {
      if (Number.isFinite(cell.x) && Number.isFinite(cell.y))
        marker(world(cellPoint(cell), state.first), "#344c59", 0.004);
    }
  const layers = circuitLayers();
  renderCircuitSummary(layers);
  const metric = $("circuit-timing").value;
  const delayKey =
    metric === "registered_launch" ? "registeredDelayNs" : "staticDelayNs";
  const maximum =
    state.computations?.maxDelays?.[
      metric === "registered_launch" ? "registered" : "static"
    ] ?? null;
  for (const value of ["timing", "computation", "computation-timing"]) {
    const option = $("color-mode").querySelector(`option[value="${value}"]`);
    option.disabled = !state.computations?.prepared;
    option.title = option.disabled
      ? "Prepare rendering data to enable this color style"
      : "";
  }
  if ($("color-mode").selectedOptions[0].disabled)
    $("color-mode").value = "role";
  const mode = $("color-mode").value;
  const membershipMode =
    mode === "computation" || mode === "computation-timing";
  const scalarMode = mode === "timing" || mode === "computation-timing";
  $("role-legend").hidden = mode !== "role";
  $("timing-legend").hidden = !scalarMode;
  $("computation-legend").hidden = !membershipMode;
  $("direction-legend").hidden = mode !== "direction";
  $("timing-min").textContent = "0 ns";
  $("timing-max").textContent =
    maximum === null ? "unknown" : `${Number(maximum).toFixed(2)} ns`;
  $("timing-ramp").style.background =
    mode === "computation-timing"
      ? `linear-gradient(90deg, ${sceneColor({ mode, computationShared: true, delayNs: 0, maxDelayNs: 1 })}, ${sceneColor({ mode, computationShared: true, delayNs: 1, maxDelayNs: 1 })})`
      : `linear-gradient(90deg, ${timingColor(0, 1)}, ${timingColor(0.5, 1)}, ${timingColor(1, 1)})`;
  $("direction-ramp").style.background =
    `linear-gradient(90deg, ${DIRECTION_SOURCE_COLOR}, ${DIRECTION_SINK_COLOR})`;
  const destinations = [
    ...new Set(layers.flatMap((layer) => layer.paint.computations ?? [])),
  ].sort();
  document.querySelector(".computation-shared").style.background =
    COMPUTATION_SHARED_COLOR;
  $("computation-count").textContent =
    `${destinations.length} destination computations`;
  $("computation-key").innerHTML = destinations
    .map(
      (key) =>
        `<span title="${esc(key)}"><i style="background:${computationColor(key)}"></i>${esc(key)}</span>`,
    )
    .join("");
  const detail = $("detail-level").value;
  const dim = $("ghost-context").checked;
  // A small style cache avoids repeating perceptual color conversion per primitive.
  const palette = new Map();
  const shade = (row) => {
    if (mode === "direction") return "#627780";
    const delayNs = row[
      metric === "registered_launch"
        ? "registeredTimingUnknown"
        : "staticTimingUnknown"
    ]
      ? null
      : (row[delayKey] ?? row.delayNs ?? null);
    const key = JSON.stringify([
      row.role,
      row.computationKey,
      row.computationShared,
      delayNs,
    ]);
    if (!palette.has(key))
      palette.set(
        key,
        sceneColor({
          role: row.role,
          mode,
          computationKey: row.computationKey,
          computationShared: row.computationShared,
          delayNs,
          maxDelayNs: maximum,
        }),
      );
    return palette.get(key);
  };
  for (const layer of layers) {
    const paint = layer.paint;
    const markRows =
      detail === "switches"
        ? [...paint.cells, ...paint.pips, ...paint.tiles]
        : paint.cells;
    if (detail !== "overview")
      for (const row of paint.segments) {
        if (row.kind === "unresolved" && mappedOnly()) continue;
        const a = world(row.from, layer.cycle),
          b = world(row.to, layer.cycle);
        segment(
          a,
          b,
          row.kind === "unresolved"
            ? "#788495"
            : mode === "direction"
              ? DIRECTION_SOURCE_COLOR
              : shade(row),
          0.0017,
          row.kind,
          row.kind === "unresolved"
            ? "#788495"
            : mode === "direction"
              ? DIRECTION_SINK_COLOR
              : shade(row),
        );
        result.focus.push(a, b);
      }
    const marks = (
      detail === "overview" ? [...paint.tiles, ...paint.cells] : markRows
    ).map((row) => ({
      position: world(row.point, layer.cycle),
      color: shade(row),
      role: row.role,
      computationKey: row.computationKey,
      computationShared: row.computationShared,
      delayNs: row[delayKey] ?? null,
      timingUnknown: Boolean(
        row[
          metric === "registered_launch"
            ? "registeredTimingUnknown"
            : "staticTimingUnknown"
        ],
      ),
      size: row.boundary === "sequential" ? 0.006 : 0.0035,
    }));
    const displayed =
      detail === "overview"
        ? occupiedBins(marks).map((row) => ({
            ...row,
            color: shade({
              ...row,
              [delayKey]: row.timingUnknown ? null : row.delayNs,
              [metric === "registered_launch"
                ? "registeredTimingUnknown"
                : "staticTimingUnknown"]: row.timingUnknown,
            }),
          }))
        : marks;
    for (const row of displayed) {
      result.markers.push(row);
      result.focus.push(row.position);
    }
  }
  const activeVersions = new Set(selectedLifetimes().map((x) => x.version));
  const storage = $("residence").checked ? visibleStorage() : [];
  let loads = 0,
    holds = 0;
  for (const item of storage) {
    item.kind === "write" ? loads++ : holds++;
    for (const p of spatialPoints(storagePoints(item), mappedOnly())) {
      const active =
        activeVersions.has(item.version) || item.resource === state.resource;
      const a = world(p, item.visibleFromCycle),
        b = world(p, item.visibleToCycle);
      const color =
        mode === "direction"
          ? DIRECTION_SOURCE_COLOR
          : membershipMode
            ? computationColor(item.resource)
            : scalarMode
              ? "#526471"
              : p.kind === "unknown"
                ? "#8c99a4"
                : active
                  ? "#f7d684"
                  : dim
                    ? "#455962"
                    : item.kind === "write"
                      ? "#86c5dc"
                      : "#789eae";
      const endColor = mode === "direction" ? DIRECTION_SINK_COLOR : color;
      segment(
        a,
        b,
        color,
        active ? 0.004 : item.kind === "write" ? 0.0028 : 0.0018,
        "storage",
        endColor,
      );
      if (item.kind === "write" && !item.afterWindow)
        marker(b, active ? "#f3f5ed" : endColor, active ? 0.012 : 0.007);
      result.storage.push({ from: a, to: b, segment: item, point: p });
      result.focus.push(a, b);
      if (active) result.selection.push(a, b);
    }
  }
  $("storage-summary").textContent =
    `${$("full-storage").checked ? "Full storage history" : "Recorded uses only"} · ${loads} loads · ${holds} residence spans · ${result.storage.length.toLocaleString()} spatial links. Thick links load a value; thin links retain it.`;
  const seeds = new Set(selectionEvents().map((e) => e.id));
  const pathIds = new Set(state.trace?.events.map((e) => e.id) ?? []);
  const expanded = $("access-footprints").checked && state.model.catalogue;
  let glyphs = 0;
  for (const event of visibleEvents()) {
    const geometry = expanded || mappedOnly() ? accessGeometry(event) : null;
    if (mappedOnly() && !geometry.points.some((p) => p.physical)) continue;
    for (const point of spatialPoints(
      expanded ? geometry.points : [eventPoint(event)],
      mappedOnly(),
    )) {
      const position = world(point, event.cycle),
        active = seeds.has(event.id),
        onPath = pathIds.has(event.id);
      const resources = resourcesForEvent(event);
      const accessColor = membershipMode
        ? resources.length === 1
          ? computationColor(resources[0])
          : resources.length > 1
            ? COMPUTATION_SHARED_COLOR
            : "#627780"
        : mode === "direction" || scalarMode
          ? "#627780"
          : color(event);
      marker(
        position,
        active ? "#f3f5ed" : onPath ? "#d3dcda" : dim ? "#536b77" : accessColor,
        active ? 0.014 : onPath ? 0.009 : 0.004,
      );
      result.events.push({ position, event });
      result.focus.push(position);
      if (active) result.selection.push(position);
      glyphs++;
    }
  }
  let traces = 0;
  for (const edge of state.trace?.edges ?? []) {
    const from = state.model.events.get(edge.source),
      to = state.model.events.get(edge.target);
    if (from.cycle >= state.first + state.window || to.cycle < state.first)
      continue;
    const sources =
      expanded || mappedOnly()
        ? accessGeometry(from).points
        : [eventPoint(from)];
    const targets =
      expanded || mappedOnly() ? accessGeometry(to).points : [eventPoint(to)];
    const connection = expanded
      ? accessConnections(from, to, sources, targets)
      : { aggregate: false, pairs: [[eventPoint(from), eventPoint(to)]] };
    const pairs = spatialPairs(
      connection.aggregate
        ? [[eventPoint(from), eventPoint(to)]]
        : connection.pairs,
      sources,
      targets,
      mappedOnly(),
    );
    for (const [source, target] of pairs) {
      segment(
        world(source, Math.max(state.first, from.cycle)),
        world(target, Math.min(state.first + state.window - 1, to.cycle)),
        mode === "direction" ? DIRECTION_SOURCE_COLOR : "#d8dedc",
        0.003,
        "dependency",
        mode === "direction" ? DIRECTION_SINK_COLOR : "#d8dedc",
      );
      result.focus.push(
        world(source, Math.max(state.first, from.cycle)),
        world(target, Math.min(state.first + state.window - 1, to.cycle)),
      );
      traces++;
    }
  }
  if (state.nativePath) {
    const cycle = Math.max(
      state.first,
      Math.min(
        state.first + state.window - 1,
        state.model.events.get(state.selected)?.cycle ?? state.first,
      ),
    );
    for (let i = 0; i < state.nativePath.arcs.length; i++) {
      const a = world(
        cellPoint(state.model.cells.get(state.nativePath.steps[i].cell)),
        cycle,
      );
      const b = world(
        cellPoint(state.model.cells.get(state.nativePath.steps[i + 1].cell)),
        cycle,
      );
      const route = state.nativeRoutes.get(`${state.nativePath.id}/${i}`);
      const positions = [
        a,
        ...(route?.pips ?? []).map((p) =>
          Number.isFinite(p.x) && Number.isFinite(p.y)
            ? world(cellPoint(p), cycle)
            : null,
        ),
        b,
      ];
      for (let j = 1; j < positions.length; j++)
        if (positions[j - 1] && positions[j]) {
          segment(positions[j - 1], positions[j], "#ee91d5", 0.004, "static");
          result.focus.push(positions[j - 1], positions[j]);
        }
    }
  }
  $("access-summary").textContent =
    `${glyphs.toLocaleString()} access positions · ${traces} selected dependency links · ${detail === "overview" ? "occupied-bin overview (aggregated, not native geometry)" : detail === "routes" ? "route spans and cells; switch markers hidden" : "route spans, cells, switches and wire tiles"}${mappedOnly() ? " · unmapped geometry hidden; evidence retained" : ""}`;
  if (
    state.computations &&
    $("computation-circuits").checked &&
    selectionEvents().length
  ) {
    const selectedLayers = (
      state.computations.prepared
        ? preparedComputationLayers
        : computationLayers
    )(
      state.computations,
      computationSelection(
        selectionEvents(),
        eventsInWindow(state.model, filters()),
      ),
      {
        roles: $("circuit-role").value
          ? [$("circuit-role").value]
          : ["data", "enable", "reset"],
        minimumDelayNs: Number($("circuit-delay").value),
        timingMetric: metric,
        includeUnknownTiming: $("circuit-unknown").checked,
      },
    );
    for (const layer of selectedLayers) {
      if (
        layer.cycle < state.first ||
        layer.cycle >= state.first + state.window
      )
        continue;
      const paint = circuitPaint(layer);
      for (const row of paint.segments)
        if (row.kind !== "unresolved" || !mappedOnly())
          result.selection.push(
            world(row.from, layer.cycle),
            world(row.to, layer.cycle),
          );
      for (const row of paint.cells)
        result.selection.push(world(row.point, layer.cycle));
    }
  }
  result.bounds = sceneBounds(result.focus);
  result.selectionBounds = sceneBounds(
    result.selection.length ? result.selection : result.focus,
  );
  return result;
}

/** Paint opaque depth-tested geometry, with sparse labels on the interaction
 * overlay. Projected hit candidates keep their depth and reject clipped points. */
function drawStack() {
  const { ctx, w, h } = canvasContext("stack");
  if (!state.model || (state.sceneError && !state.sceneDirty)) return;
  if (state.sceneDirty) state.sceneError = null;
  if (!state.scene) {
    state.scene = createScene3D($("scene3d"), {
      onUnsupported: (message) => {
        state.sceneError = message;
        notice(message, true);
      },
      onContextLost: (message) => {
        state.sceneError = message;
        notice(message, true);
      },
      onContextRestored: () => {
        state.sceneError = null;
        notice("3D context restored; saved evidence is unchanged.");
        repaint(true);
      },
    });
    if (!state.scene) return;
  }
  if (state.sceneDirty || !state.sceneContent) {
    const started = performance.now();
    state.sceneContent = buildStackScene();
    state.scene.setScene(state.sceneContent);
    state.sceneDirty = false;
    if (state.autoFit) {
      state.scene.fit(state.sceneContent.bounds);
      state.autoFit = false;
    }
    state.loadTimings["Latest scene preparation"] = performance.now() - started;
    showLoadTimings();
  }
  state.scene.render({
    width: w,
    height: h,
    pixelRatio: window.devicePixelRatio || 1,
    shading: ["role", "computation"].includes($("color-mode").value),
  });
  const project = (point) => state.scene.project(point);
  const labels = canvasLabels(ctx, w, h);
  ctx.font = "11px ui-monospace,monospace";
  ctx.fillStyle = "#a5bdc8";
  for (const label of state.sceneContent.labels) {
    const candidates = (label.alternatives ?? [label.position])
      .map(project)
      .filter((p) => p.visible);
    const p = candidates.sort((a, b) => a.x - b.x)[0];
    if (p) labels.add(label.text, Math.max(4, p.x - 44), p.y - 6, 100);
  }
  labels.draw();
  state.hitsDirty = true;
}
/** Picking is deferred until the pointer settles; dragging only updates the GPU
 * camera and sparse labels. Frontmost equal-distance candidates win. */
function ensureSceneHits() {
  if (!state.hitsDirty || !state.sceneContent || !state.scene) return;
  const project = (point) => state.scene.project(point);
  state.hits = state.sceneContent.events
    .map((row) => ({ ...project(row.position), event: row.event }))
    .filter((p) => p.visible)
    .sort((a, b) => b.depth - a.depth);
  state.storageHits = state.sceneContent.storage.flatMap((row) => {
    const points = state.scene.projectSegment(row.from, row.to);
    return points ? [{ ...row, a: points[0], b: points[1] }] : [];
  });
  state.hitsDirty = false;
}
/** Flat chip projection retains installed population, rather than layer copies. */
function drawFlat() {
  const { ctx, w, h } = canvasContext("flat");
  if (!state.model) return;
  state.flatHits = [];
  const model = state.model,
    b = model.geometryBounds;
  const selected = state.resource
    ? resourcePlacement(model, state.resource).cells
    : state.selected
      ? eventPlacement(model, state.selected).cells
      : [];
  const chosen = new Set(selected.map((c) => c.id));
  if (b) {
    const scale = Math.min(
        (w - 32) / (b.maxX - b.minX || 1),
        (h - 32) / (b.maxY - b.minY || 1),
      ),
      ox = (w - (b.maxX - b.minX) * scale) / 2,
      oy = (h - (b.maxY - b.minY) * scale) / 2;
    const spatial = state.metricsCache?.value.spatial;
    if ($("spatial-density").checked && spatial?.status === "tile_grid") {
      for (const bin of spatial.bins) {
        const x = ox + (bin.x - b.minX) * scale;
        const y = h - oy - (bin.y + spatial.binSizeTiles - b.minY) * scale;
        ctx.fillStyle = `rgba(90, 150, 220, ${0.08 + (0.32 * bin.installedCells) / spatial.peakBinCells})`;
        ctx.fillRect(
          x,
          y,
          spatial.binSizeTiles * scale,
          spatial.binSizeTiles * scale,
        );
      }
    }
    for (const cell of model.cells.values()) {
      if (!Number.isFinite(cell.x) || !Number.isFinite(cell.y)) continue;
      const p = {
          x: ox + (cell.x - b.minX) * scale,
          y: h - oy - (cell.y - b.minY) * scale,
        },
        active = chosen.has(cell.id);
      ctx.fillStyle =
        cell.id === state.cell ? "#ffffff" : active ? "#f7d684" : "#3a5361";
      const size = active ? 3 : 1.3;
      ctx.fillRect(p.x - size / 2, p.y - size / 2, size, size);
      if (active) state.flatHits.push({ ...p, cell });
    }
    const projectCircuit = (point) => {
      const x = (point.x / 2 + 0.5) * (b.maxX - b.minX) + b.minX;
      const y = (point.y / 2 + 0.5) * (b.maxY - b.minY) + b.minY;
      return { x: ox + (x - b.minX) * scale, y: h - oy - (y - b.minY) * scale };
    };
    drawComputations(ctx, projectCircuit, true);
    if (state.nativePath)
      drawNativePath(
        ctx,
        (point) => {
          const x = (point.x / 2 + 0.5) * (b.maxX - b.minX) + b.minX;
          const y = (point.y / 2 + 0.5) * (b.maxY - b.minY) + b.minY;
          return {
            x: ox + (x - b.minX) * scale,
            y: h - oy - (y - b.minY) * scale,
          };
        },
        true,
      );
  } else {
    let row = 0;
    for (const resource of model.resources.values()) {
      for (let address = 0; address < (resource.depth ?? 1); address++) {
        const y = 30 + row * 45;
        ctx.strokeStyle =
          state.resource === resource.id ? "#f7d684" : "#537480";
        ctx.strokeRect(16, y, w - 32, 30);
        ctx.fillStyle = "#b6cad4";
        ctx.font = "10px ui-monospace,monospace";
        ctx.fillText(`${resource.id} [${address}]`, 24, y + 19);
        row++;
      }
    }
  }
}
/** Whole-capture timeline with window overlay and independent public markers. */
function drawTimeline() {
  const { ctx, w, h } = canvasContext("timeline");
  if (!state.model) return;
  const model = state.model,
    c = model.bundle.capture,
    x = (cycle) =>
      16 + ((cycle - c.first_cycle) / (c.end_cycle - c.first_cycle)) * (w - 32);
  ctx.fillStyle = "#65dac71a";
  ctx.fillRect(
    x(state.first),
    5,
    x(state.first + state.window) - x(state.first),
    h - 26,
  );
  const selected = state.selected
    ? model.events.get(state.selected)
    : state.annotation;
  const selectedActor = $("actor").value;
  for (const event of model.orderedEvents) {
    if (selectedActor && event.actor !== selectedActor) continue;
    const y =
      19 +
      Math.max(0, state.actors.indexOf(event.actor)) *
        Math.min(9, 50 / Math.max(1, state.actors.length - 1));
    ctx.fillStyle = color(event);
    ctx.globalAlpha = 0.35;
    ctx.fillRect(x(event.cycle), y, 1, 5);
  }
  ctx.globalAlpha = 1;
  for (const boundary of model.document.annotations?.boundaries ?? []) {
    const cycle = boundary.cycle;
    if (!Number.isFinite(cycle)) continue;
    line(
      ctx,
      { x: x(cycle), y: 6 },
      { x: x(cycle), y: h - 20 },
      "#f1bb6c",
      1,
      true,
    );
  }
  if (selected) {
    line(
      ctx,
      { x: x(selected.cycle), y: 4 },
      { x: x(selected.cycle), y: h - 18 },
      "#fff0ac",
      2,
    );
  }
  for (const epoch of model.bundle.capture.incarnations.slice(1)) {
    line(
      ctx,
      { x: x(epoch.first_cycle), y: 5 },
      { x: x(epoch.first_cycle), y: h - 19 },
      "#ea8b94",
      2,
    );
  }
  ctx.fillStyle = "#829daa";
  ctx.font = "9px ui-monospace,monospace";
  for (let i = 0; i <= 5; i++) {
    const cycle = Math.round(
      c.first_cycle + ((c.end_cycle - c.first_cycle) * i) / 5,
    );
    ctx.fillText(`C${cycle}`, Math.min(w - 46, x(cycle)), h - 7);
  }
  $("timeline-label").textContent =
    `${c.end_cycle - c.first_cycle} clocks retained · ${model.bundle.capture.incarnations.length} incarnation(s)`;
}
/** Choose a recorded event, retaining ancestry outside the current window. */
function selectEvent(id, move = true) {
  if (!state.model?.events.has(id)) return;
  state.selected = id;
  state.annotation = null;
  state.trace = null;
  state.cell = null;
  state.focusVersion = null;
  const event = state.model.events.get(id);
  state.resource =
    event.access?.resource ?? resourcesForEvent(event)[0] ?? null;
  $("resource").value = state.resource ?? "";
  if (
    move &&
    (event.cycle < state.first || event.cycle >= state.first + state.window)
  )
    state.first = event.cycle - Math.floor(state.window / 2);
  render();
}
/** Select a stored version, including roots with no fabricated producer event. */
function selectStorage(version, cell = null) {
  const life = state.model.lifetimes.get(version);
  if (!life) return;
  state.selected = life.producer;
  state.trace = null;
  state.annotation = null;
  state.focusVersion = version;
  state.resource = life.resource;
  state.cell = cell;
  $("resource").value = life.resource;
  render();
}
/** Follow explicitly bound contributors while leaving unanchored observations as context. */
function selectAnnotation(annotation) {
  const anchors = annotationEvents(state.model, annotation);
  if (anchors.length > 1000) {
    notice(
      "This viewer can follow at most 1,000 completion contributors at once.",
      true,
    );
    return;
  }
  state.selected = null;
  state.trace = null;
  state.annotation = annotation;
  traceSelection("backward");
  state.resource = null;
  state.cell = null;
  state.focusVersion = null;
  $("resource").value = "";
  state.first = annotation.cycle - Math.floor(state.window / 2);
  render();
}
/** Neighbour buttons are exact dependency endpoints; root versions stop traversal. */
function neighborButtons(details) {
  const entries = [
    ...details.predecessors.map((edge) => ({
      id: edge.source,
      kind: `input · ${edge.kind}`,
    })),
    ...details.successors.map((edge) => ({
      id: edge.target,
      kind: `consumer · ${edge.kind}`,
    })),
  ];
  return entries
    .slice(0, 80)
    .map(({ id, kind }) => {
      const e = state.model.events.get(id);
      return `<button data-event="${esc(id)}"><span class="muted">${esc(kind)}</span><br>C${e.cycle} · ${esc(e.operation)} · ${esc(e.actor)} <span class="muted">${esc(id)}</span></button>`;
    })
    .join("");
}
/** Explain producer/consumer identities, residence and evidence without inferred causes. */
function renderInspector() {
  const fp = state.selected
    ? eventFootprint(state.model, state.selected)
    : null;
  $("access-detail").textContent = fp
    ? fp.reason +
      (fp.cells.length
        ? ` ${fp.cells.length} placed native cells; ${fp.unknownBits} unresolved bits.`
        : "")
    : "Select an access to inspect its bit-selection scope.";
  const seeds = selectionEvents();
  $("backward").disabled = !seeds.length;
  $("forward").disabled = !seeds.length;
  if (state.annotation) {
    $("selected-kind").textContent = "Public annotation";
    $("selection").innerHTML =
      `<h3>Completion · C${state.annotation.cycle}</h3>` +
      (seeds.length
        ? `<span class="pill">${seeds.length} recorded contributors</span><p class="evidence-note">Inputs follows every bound endpoint. Only recorded dependencies are shown; numerical and control ancestry may remain partial.</p><dl><dt>Incarnation</dt><dd>${esc(state.annotation.graph_incarnation)}</dd><dt>Contributors</dt><dd>${seeds.map((event) => `${esc(event.id)} · C${event.cycle}`).join("<br>")}</dd></dl>`
        : '<span class="pill unknown">Ancestry unavailable</span><p class="evidence-note">No recorded endpoint is bound to this observation. Sharing its clock creates no dependency.</p>') +
      `<details><summary>Public record</summary><pre class="muted">${esc(JSON.stringify(state.annotation, null, 2))}</pre></details>`;
    $("neighbors").innerHTML = seeds
      .slice(0, 80)
      .map(
        (event) =>
          `<button data-event="${esc(event.id)}"><span class="muted">Contributing endpoint</span><br>C${event.cycle} · ${esc(event.operation)} · ${esc(event.actor)}<br>${esc(event.id)}</button>`,
      )
      .join("");
    renderTraceSummary();
    return;
  }
  if (!state.selected && state.focusVersion) {
    const life = state.model.lifetimes.get(state.focusVersion);
    $("selected-kind").textContent = "Stored root";
    $("selection").innerHTML =
      `<h3>${esc(life.version)}</h3><p>${esc(life.resource)} [${life.address}]</p><p>${esc(life.origin)} root, available C${life.firstCycle}–C${life.endCycle - 1}. No producer before this recording/incarnation is implied.</p><p>${esc(life.continuity)} · ${life.pending.length} pending or retired read request(s).</p><p>${esc(life.evidence)}</p>`;
    $("neighbors").innerHTML = life.requests
      .map(
        (id) =>
          `<button data-event="${esc(id)}">Read at C${state.model.events.get(id).cycle}</button>`,
      )
      .join("");
    $("trace-summary").textContent =
      "Storage residence is separate from numerical ancestry.";
    return;
  }
  if (!state.selected) {
    $("selected-kind").textContent = "No selection";
    $("selection").innerHTML =
      '<p class="empty">Choose a recorded example or select an operation.</p>';
    $("neighbors").innerHTML = "";
    $("trace-summary").textContent = "";
    return;
  }
  const d = eventDetails(state.model, state.selected),
    e = d.event;
  $("selected-kind").textContent = `C${e.cycle}`;
  const lifetimes = selectedLifetimes();
  $("selection").innerHTML =
    `<h3>${esc(e.operation)}</h3><span class="pill">${esc(e.actor)}</span> <span class="pill unknown">${esc(d.placement.status.replaceAll("_", " "))}</span><dl><dt>Event</dt><dd>${esc(e.id)}</dd><dt>Task</dt><dd>${esc(e.task)}</dd><dt>Activation</dt><dd>${esc(e.activation)}</dd><dt>Incarnation</dt><dd>${esc(e.incarnation)}</dd><dt>Input versions</dt><dd>${d.inputs.map((v) => `${esc(v.id)} (${esc(v.origin)})`).join(", ") || "None recorded"}</dd><dt>Output versions</dt><dd>${d.outputs.map((v) => esc(v.id)).join(", ") || "None recorded"}</dd>${e.access ? `<dt>Storage</dt><dd>${esc(e.access.resource)} [${e.access.address}] · ${esc(e.access.kind)}</dd>${e.access.mask ? `<dt>Write mask</dt><dd>${esc(e.access.mask)}</dd>` : ""}${e.access.read_mask ? `<dt>Selected read bits</dt><dd>${esc(e.access.read_mask)}</dd>` : ""}` : ""}</dl><p class="evidence-note">${esc(e.evidence)}</p>${d.inputs
      .filter((v) => v.producer === "root")
      .map(
        (v) =>
          `<p class="evidence-note">${esc(v.id)}: ${esc(v.origin)} root. ${esc(v.evidence)}</p>`,
      )
      .join("")}${lifetimes
      .slice(0, 12)
      .map(
        (life) =>
          `<details open><summary>${esc(life.version)} · storage history</summary><p>${life.firstCycle < life.endCycle ? `Available C${life.firstCycle} to C${life.endCycle - 1}.` : `Availability begins at C${life.firstCycle}, beyond the captured interval.`} ${life.origin === "event" ? "Written by " + esc(life.producer) + "." : esc(life.origin) + " root."}</p><p>${life.holds.length} explicit holds; ${life.requests.length} reads. ${life.lastUseCycle === null ? "No recorded use; hidden from the default storage view." : `Last recorded use at C${life.lastUseCycle}; the default view stops there.`} Persistence between observed operations is residence within the declared capture scope, not an attributed wait.</p>${life.pending.map((p) => `<p class="annotation">${esc(p.status)}: request ${esc(p.event)}, due C${p.dueCycle}</p>`).join("")}<p class="muted">${esc(life.continuity)}</p></details>`,
      )
      .join(
        "",
      )}${lifetimes.length > 12 ? `<p>${lifetimes.length - 12} more histories on this path; select a resource or version for detail.</p>` : ""}`;
  $("neighbors").innerHTML = neighborButtons(d);
  renderTraceSummary();
}
/** Explain bounded traversal and its explicit roots without claiming full causal coverage. */
function renderTraceSummary() {
  if (!state.trace) {
    $("trace-summary").textContent = selectionEvents().length
      ? "Follow inputs or consumers. Chronological neighbours are not dependencies."
      : "No recorded dependency endpoints supplied.";
    return;
  }
  const roots = [
    ...new Map(
      state.trace.roots.map(({ version }) => [version.id, version]),
    ).values(),
  ];
  $("trace-summary").innerHTML =
    `${state.traceDirection === "backward" ? "Inputs" : "Consumers"}: ${state.trace.events.length} recorded operations · ${state.trace.edges.length} dependencies · ${roots.length} root versions` +
    (state.trace.truncated ? " · traversal capped at 1,000 operations" : "") +
    '<p class="evidence-note">Partial recorded ancestry, not a complete computation or critical path.</p>' +
    roots
      .slice(0, 8)
      .map(
        (version) =>
          `<p>${esc(version.id)} · ${esc(version.origin)} root: ${esc(version.evidence)}</p>`,
      )
      .join("") +
    (roots.length > 8
      ? `<p>${roots.length - 8} more root versions stop this traversal.</p>`
      : "");
}
/** Expose complete per-resource coverage and a bounded expandable cell listing. */
function renderResource() {
  const placements = state.resource
    ? [resourcePlacement(state.model, state.resource)]
    : state.selected
      ? eventPlacement(state.model, state.selected).resources
      : [];
  const cells = [
    ...new Map(
      placements.flatMap((p) => p.cells).map((c) => [c.id, c]),
    ).values(),
  ];
  $("resource-summary").innerHTML =
    placements
      .map(
        (p) =>
          `<p><b>${esc(p.resource)}</b><br>${esc(p.coverage.status.replaceAll("_", " "))}<br>${p.supportedBits} supported bits · ${p.unknownBits} unknown bits · ${p.cells.length} associated cells</p><p>${esc(p.binding?.evidence ?? p.coverage.reason ?? "No measured physical binding.")}</p>${(p.binding?.generated ?? []).map((id) => `<p class="muted">${esc(state.model.catalogue?.generated?.find((g) => g.id === id)?.source ?? id)}</p>`).join("")}`,
      )
      .join("") || "Select an operation to inspect its resource bindings.";
  const histories = state.resource
    ? storageLifetimes(state.model, {
        resource: state.resource,
        firstCycle: state.first,
        endCycle: state.first + state.window,
      })
    : [];
  $("storage-history").innerHTML = histories.length
    ? `<p>${histories.length} versions of this resource intersect the window. Full histories remain inspectable even when their strands are hidden.</p>` +
      histories
        .slice(0, 80)
        .map(
          (life) =>
            `<button data-version="${esc(life.version)}">${esc(life.version)} · C${life.firstCycle}–C${life.endCycle - 1} · ${life.writeCycle === null ? esc(life.origin) : `write C${life.writeCycle}`} · ${life.lastUseCycle === null ? "no recorded use" : `last use C${life.lastUseCycle}`}</button>`,
        )
        .join("") +
      (histories.length > 80
        ? "<p>First 80 listed; narrow the clock window to inspect the rest.</p>"
        : "")
    : "Select a storage resource to inspect its versions.";
  $("expand-storage").disabled = !state.resource || !state.model.catalogue;
  $("flat-subtitle").textContent = cells.length
    ? `${cells.length} associated native storage cells highlighted`
    : "Unique installed cells, counted once";
  $("cell-count").textContent = `(${cells.length})`;
  $("cells").innerHTML =
    cells
      .slice(0, 600)
      .map(
        (c) =>
          `<div class="cell-row" role="button" tabindex="0" data-cell="${esc(c.id)}">${esc(c.id)}<span>${esc(c.kind)} · ${esc(c.site)} / ${esc(c.bel)} · tile (${c.x}, ${c.y})</span></div>`,
      )
      .join("") +
    (cells.length > 600
      ? "<p>First 600 cells listed; all are drawn on the flat chip.</p>"
      : "");
}
/** Apply a fixture's inspectable entry point, never a fabricated causal chain. */
function chooseExample(index) {
  const example = state.model.document.examples?.[index];
  if (!example) return;
  ["actor", "activation", "operation", "task"].forEach(
    (key) => ($(key).value = ""),
  );
  updateActivations();
  if (example.annotation || example.graph_events) {
    selectAnnotation(example.annotation ?? example);
    if (example.firstCycle !== undefined) state.first = example.firstCycle;
    if (example.endCycle !== undefined)
      state.window = example.endCycle - state.first;
    render();
    return;
  }
  const id =
    example.event ??
    example.eventId ??
    example.events?.at(-1) ??
    example.consumer;
  if (id && state.model.events.has(id)) {
    selectEvent(id);
    traceSelection("backward");
    state.focusVersion = example.version ?? null;
    const life = state.model.lifetimes.get(state.focusVersion);
    if (life) {
      state.resource = life.resource;
      $("resource").value = life.resource;
    }
    state.first = example.firstCycle ?? state.first;
    state.window = Math.max(
      8,
      (example.endCycle ?? state.first + 24) - state.first,
    );
    render();
  } else if (Number.isFinite(example.cycle)) selectAnnotation(example);
  else notice("This example has no selectable recorded event.", true);
}
/** Canvas hit test returns the nearest visible operation; a tie remains selectable in the list. */
function nearest(hits, x, y, limit = 12) {
  let best = null,
    dist = limit * limit;
  for (const hit of hits) {
    const d = (hit.x - x) ** 2 + (hit.y - y) ** 2;
    if (
      d < dist - 1e-6 ||
      (Math.abs(d - dist) <= 1e-6 &&
        (hit.depth ?? 0) <= (best?.depth ?? Infinity))
    ) {
      dist = d;
      best = hit;
    }
  }
  return best;
}
/** Nearest rendered storage span, independently of dense same-clock dots. */
function nearestStorage(x, y) {
  let best = null,
    distance = 25,
    bestDepth = Infinity;
  for (const hit of state.storageHits) {
    const dx = hit.b.x - hit.a.x,
      dy = hit.b.y - hit.a.y;
    const t = Math.max(
      0,
      Math.min(
        1,
        ((x - hit.a.x) * dx + (y - hit.a.y) * dy) / (dx * dx + dy * dy || 1),
      ),
    );
    const d = (x - hit.a.x - t * dx) ** 2 + (y - hit.a.y - t * dy) ** 2;
    const depth =
      (hit.a.depth ?? 0) + t * ((hit.b.depth ?? 0) - (hit.a.depth ?? 0));
    if (
      d < distance - 1e-6 ||
      (Math.abs(d - distance) <= 1e-6 && depth < bestDepth)
    ) {
      best = hit;
      distance = d;
      bestDepth = depth;
    }
  }
  return best;
}
/** Local pointer coordinates independent of page scrolling. */
function pointer(event) {
  const r = event.currentTarget.getBoundingClientRect();
  return { x: event.clientX - r.left, y: event.clientY - r.top };
}
/** Prevent controls for the old capture from acting while replacement data loads. */
function setBusy(busy) {
  for (const id of [
    "example",
    "actor",
    "activation",
    "operation",
    "task",
    "resource",
    "first",
    "window",
    "position",
    "step",
    "completion",
    "all",
    "previous",
    "next",
  ])
    $(id).disabled = busy;
}
/** Bind all interactive controls after the static interface exists. */
function bindControls() {
  $("help-button").onclick = () => {
    const open = $("help").hidden;
    $("help").hidden = !open;
    $("help-button").setAttribute("aria-expanded", String(open));
  };
  $("capture").onchange = async () => {
    if (!$("capture").value) return;
    const sequence = ++state.loadSequence;
    state.loadController?.abort();
    state.loadController = new AbortController();
    const signal = state.loadController.signal,
      url = $("capture").value,
      started = performance.now();
    state.loadTimings = {};
    setBusy(true);
    try {
      notice("Reading saved capture…");
      const response = await fetch(url, { signal });
      if (!response.ok)
        throw Error(`Capture fetch failed (${response.status})`);
      const bytes = await response.arrayBuffer(),
        byteLength = bytes.byteLength;
      if (byteLength > 128 * 1024 * 1024)
        throw Error("Projection exceeds 128 MiB");
      const expected = state.index.get(url);
      if (!expected || byteLength !== expected.bytes)
        throw Error("Projection length does not match the local index");
      const digest = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      if (digest !== expected.sha256)
        throw Error("Projection digest does not match the local index");
      state.loadTimings["Recording fetch and verification"] =
        performance.now() - started;
      notice("Preparing the recording in a background worker…");
      const decoded = await loadRecording(bytes, { signal });
      if (sequence !== state.loadSequence) return;
      state.loadTimings["Recording JSON parse"] = decoded.timings.parseMs;
      state.loadTimings["Recording index"] = decoded.timings.indexMs;
      await loadDocument(
        decoded.model,
        "Projection bytes verified against the local index; source evidence was verified during preparation.",
      );
      if (state.model.document.examples?.length) {
        $("example").value = "0";
        chooseExample(0);
      }
      setBusy(false);
      await new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      );
      if (sequence !== state.loadSequence) return;
      state.loadTimings["First recording frame"] = performance.now() - started;
      showLoadTimings();
      if (expected.render || expected.computations) {
        notice(
          "Recording is interactive. Loading its complete circuit geometry…",
        );
        const routeStarted = performance.now();
        const options = {
          entry: expected.render ?? expected.computations,
          source: expected.computations,
          signal,
          view: { bytes: byteLength, sha256: digest },
          baseUrl: new URL("data/", window.location.href).href,
          progress: (message) => {
            if (sequence === state.loadSequence)
              notice(`Recording is interactive. ${message}`);
          },
        };
        const data = expected.render
          ? { prepared: await loadPreparedRenderWorker(options) }
          : await loadComputations(options);
        if (sequence !== state.loadSequence) return;
        installComputationData(data);
        await new Promise((resolve) =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        );
        if (sequence !== state.loadSequence) return;
        state.loadTimings["Circuit load through first frame"] =
          performance.now() - routeStarted;
        state.loadTimings["Complete initial view"] =
          performance.now() - started;
        showLoadTimings();
        notice(
          expected.render
            ? "Prepared circuitry loaded. Complete source evidence is retained; displayed timing remains a static bound."
            : "Complete native routing loaded. Preparing a render index will make subsequent loads cheaper.",
        );
      }
    } catch (error) {
      if (sequence === state.loadSequence) notice(error.message, true);
    } finally {
      if (sequence === state.loadSequence) setBusy(false);
    }
  };
  $("file").onchange = async () => {
    const sequence = ++state.loadSequence;
    state.loadController?.abort();
    state.loadController = new AbortController();
    const file = $("file").files[0];
    if (!file) return;
    setBusy(true);
    try {
      if (file.size > 128 * 1024 * 1024) throw Error("File exceeds 128 MiB");
      const decoded = await loadRecording(await file.arrayBuffer(), {
        signal: state.loadController.signal,
      });
      if (sequence !== state.loadSequence) return;
      await loadDocument(decoded.model);
    } catch (error) {
      if (sequence === state.loadSequence) notice(error.message, true);
    } finally {
      if (sequence === state.loadSequence) setBusy(false);
    }
  };
  for (const key of ["actor", "activation", "operation", "task"])
    $(key).onchange = () => {
      if (key === "actor") updateActivations();
      render();
    };
  $("clear-filters").onclick = () => {
    for (const k of ["actor", "activation", "operation", "task"])
      $(k).value = "";
    updateActivations();
    render();
  };
  $("first").onchange = () => {
    state.first = Number($("first").value);
    render();
  };
  $("window").onchange = () => {
    state.window = Number($("window").value);
    render();
  };
  $("position").oninput = () => {
    state.first = Number($("position").value);
    render();
  };
  $("spacing").oninput = () => {
    state.spacing = Number($("spacing").value);
    repaint();
  };
  $("spatial-density").onchange = () => repaint();
  $("what-if-period").onchange = () => {
    const input = $("what-if-period");
    const period = Number(input.value);
    if (
      input.value !== "" &&
      (!Number.isFinite(period) ||
        period <= 0 ||
        period * state.window > Number.MAX_SAFE_INTEGER)
    ) {
      input.value = "";
      notice(
        "A hypothetical period must be positive and within the numeric range.",
        true,
      );
    }
    render();
  };
  for (const id of [
    "computation-circuits",
    "circuit-role",
    "circuit-timing",
    "circuit-unknown",
    "circuit-selected",
  ])
    $(id).onchange = () => repaint();
  $("circuit-delay").onchange = () => {
    const value = Number($("circuit-delay").value);
    if (!Number.isFinite(value) || value < 0) $("circuit-delay").value = "0";
    repaint();
  };
  $("context").onchange = () => repaint();
  $("show-unmapped").onchange = () => repaint();
  $("residence").onchange = () => repaint();
  $("full-storage").onchange = render;
  $("access-footprints").onchange = () => repaint();
  $("native-path").onchange = () => {
    state.nativePath =
      state.nativePaths.find((p) => p.id === $("native-path").value) ?? null;
    renderNativePath();
    repaint();
  };
  $("expand-storage").onchange = () => repaint();
  $("reset-camera").onclick = () => {
    state.scene?.preset("isometric");
    for (const button of ["camera-top", "camera-side", "camera-isometric"])
      $(button).setAttribute(
        "aria-pressed",
        String(button === "camera-isometric"),
      );
    if (state.sceneContent) state.scene?.fit(state.sceneContent.bounds);
    repaint(true);
  };
  $("previous").onclick = () => {
    state.first -= state.window;
    render();
  };
  $("next").onclick = () => {
    state.first += state.window;
    render();
  };
  $("step").onclick = () => {
    if (!state.model) return;
    const b = selectedBounds();
    state.first = b.firstCycle;
    state.window = b.endCycle - b.firstCycle;
    render();
  };
  $("completion").onclick = () => {
    const annotation = state.model?.document.annotations?.boundaries?.find(
      (b) => b.cycle === state.model.document.selection?.completionCycle,
    );
    if (annotation) selectAnnotation(annotation);
    else
      notice("No public completion annotation is supplied for this fixture.");
  };
  $("all").onclick = () => {
    if (!state.model) return;
    const c = state.model.bundle.capture;
    state.first = c.first_cycle;
    state.window = c.end_cycle - c.first_cycle;
    render();
  };
  $("example").onchange = () => {
    if ($("example").value !== "") chooseExample(Number($("example").value));
  };
  $("resource").onchange = () => {
    state.resource = $("resource").value || null;
    $("fit-selection").disabled =
      !state.resource && !state.selected && !state.focusVersion;
    state.cell = null;
    renderResource();
    repaint();
  };
  for (const direction of ["backward", "forward"])
    $(direction).onclick = () => {
      traceSelection(direction);
      render();
    };
  $("clear-trace").onclick = () => {
    state.trace = null;
    render();
  };
  document.addEventListener("click", (e) => {
    const target = e.target.closest("[data-event]");
    if (target) selectEvent(target.dataset.event);
    const version = e.target.closest("[data-version]");
    if (version) selectStorage(version.dataset.version);
    const cell = e.target.closest("[data-cell]");
    if (cell) {
      state.cell = cell.dataset.cell;
      repaint();
      notice(`Selected cell: ${state.cell}`);
    }
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.target.matches("[data-cell]")) e.target.click();
  });
  const stack = $("stack");
  let drag = null;
  stack.onpointerdown = (e) => {
    drag = {
      ...pointer(e),
      moved: false,
      distance: 0,
      pan: e.shiftKey || e.button === 1 || $("camera-mode").value === "pan",
    };
    stack.setPointerCapture(e.pointerId);
  };
  stack.onpointermove = (e) => {
    const p = pointer(e);
    if (drag) {
      const dx = p.x - drag.x,
        dy = p.y - drag.y;
      drag.distance += Math.abs(dx) + Math.abs(dy);
      if (drag.distance > 4) drag.moved = true;
      if (drag.pan) state.scene?.pan(dx, dy);
      else state.scene?.orbit(dx * 0.008, dy * 0.008);
      drag.x = p.x;
      drag.y = p.y;
      repaint(true);
    } else {
      ensureSceneHits();
      const hit = nearest(state.hits, p.x, p.y, 5);
      const storage = hit ? null : nearestStorage(p.x, p.y);
      $("tooltip").hidden = !hit && !storage;
      if (hit || storage) {
        $("tooltip").textContent = hit
          ? `C${hit.event.cycle} · ${hit.event.actor} · ${hit.event.operation}`
          : `${storage.segment.kind === "write" ? "Load" : "Residence"} C${storage.segment.fromCycle}→C${storage.segment.toCycle} · ${storage.segment.version} · ${storage.point.cell ?? storage.segment.resource}`;
        $("tooltip").style.left =
          `${Math.min(p.x + 12, stack.clientWidth - 220)}px`;
        $("tooltip").style.top = `${p.y + 14}px`;
      }
    }
  };
  stack.onpointerup = (e) => {
    const p = pointer(e);
    if (drag && !drag.moved) {
      ensureSceneHits();
      const hit = nearest(state.hits, p.x, p.y, 5);
      const storage = hit ? null : nearestStorage(p.x, p.y);
      if (hit) selectEvent(hit.event.id, false);
      else if (storage)
        selectStorage(storage.segment.version, storage.point.cell ?? null);
    }
    drag = null;
  };
  stack.onwheel = (e) => {
    e.preventDefault();
    state.scene?.zoom(Math.exp(-e.deltaY * 0.0015));
    repaint(true);
  };
  stack.oncontextmenu = (e) => e.preventDefault();
  stack.onpointercancel = () => (drag = null);
  stack.onpointerleave = () => {
    $("tooltip").hidden = true;
  };
  stack.onkeydown = (e) => {
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
      const x = e.key === "ArrowLeft" ? -1 : e.key === "ArrowRight" ? 1 : 0;
      const y = e.key === "ArrowUp" ? -1 : e.key === "ArrowDown" ? 1 : 0;
      if (e.shiftKey) state.scene?.pan(x * 20, y * 20);
      else state.scene?.orbit(x * 0.1, y * 0.1);
      e.preventDefault();
      repaint(true);
    } else if (["+", "=", "-"].includes(e.key)) {
      state.scene?.zoom(e.key === "-" ? 1 / 1.2 : 1.2);
      e.preventDefault();
      repaint(true);
    }
  };
  $("flat").onclick = (e) => {
    const p = pointer(e),
      hit = nearest(state.flatHits, p.x, p.y);
    if (hit) {
      state.cell = hit.cell.id;
      notice(
        `${hit.cell.kind} · ${hit.cell.id} · ${hit.cell.site}/${hit.cell.bel}`,
      );
      $("cell-details").open = true;
      repaint();
    }
  };
  $("timeline").onclick = (e) => {
    if (!state.model) return;
    const p = pointer(e),
      c = state.model.bundle.capture;
    state.first =
      Math.round(
        c.first_cycle +
          ((p.x - 16) / ($("timeline").clientWidth - 32)) *
            (c.end_cycle - c.first_cycle),
      ) - Math.floor(state.window / 2);
    render();
  };
  $("toggle-inspector").onclick = () => {
    const open = $("evidence-inspector").hidden;
    $("evidence-inspector").hidden = !open;
    $("explorer").classList.toggle("inspector-open", open);
    $("toggle-inspector").setAttribute("aria-expanded", String(open));
    repaint();
  };
  $("scene-focus").onclick = () => {
    const open = document.body.classList.toggle("scene-focus");
    $("scene-focus").setAttribute("aria-pressed", String(open));
    repaint();
  };
  $("flat-panel").ontoggle = () => repaint();
  for (const [id, preset] of [
    ["camera-top", "chip"],
    ["camera-side", "xz"],
    ["camera-isometric", "isometric"],
  ])
    $(id).onclick = () => {
      state.scene?.preset(preset);
      if (state.sceneContent) state.scene?.fit(state.sceneContent.bounds);
      for (const button of ["camera-top", "camera-side", "camera-isometric"])
        $(button).setAttribute("aria-pressed", String(button === id));
      repaint(true);
    };
  $("zoom-in").onclick = () => {
    state.scene?.zoom(1.3);
    repaint(true);
  };
  $("zoom-out").onclick = () => {
    state.scene?.zoom(1 / 1.3);
    repaint(true);
  };
  $("fit-selection").onclick = () => {
    if (state.sceneContent)
      state.scene?.fit(state.sceneContent.selectionBounds);
    repaint(true);
  };
  for (const id of ["color-mode", "detail-level", "ghost-context"])
    $(id).onchange = () => repaint();
  new ResizeObserver(() => repaint()).observe(
    document.querySelector(".workspace"),
  );
}
/** Saved examples are optional; a missing local index leaves file-open usable. */
async function initialize() {
  bindControls();
  try {
    const response = await fetch("data/index.json");
    if (!response.ok) return;
    const index = await response.json();
    const entries = Array.isArray(index)
      ? index
      : (index.captures ?? index.examples ?? index.files ?? []);
    for (const entry of entries) {
      const path = entry.file;
      if (typeof path !== "string" || !/^[-a-zA-Z0-9_]+\.json$/.test(path))
        throw Error("Unsafe example filename");
      const url = `data/${path}`;
      state.index.set(url, entry);
      $("capture").add(
        new Option(
          entry.title ?? entry.label ?? entry.name ?? entry.id ?? path,
          url,
        ),
      );
    }
    if (entries.length) {
      $("capture").selectedIndex = 1;
      await $("capture").onchange();
    }
  } catch (e) {
    notice(
      `Cannot open saved example: ${e.message}. You can still open a projection file.`,
      true,
    );
  }
}
initialize();
