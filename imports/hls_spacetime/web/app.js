/** Local rendering of saved cycle evidence. All ancestry comes from model.js;
 * screen positions and same-clock annotations never create graph edges. */
import {
  createModel,
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
  yaw: -0.6,
  tilt: 0.5,
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
  $("notice").textContent = message;
  $("notice").classList.toggle("warning", warning);
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
  text,
  integrity = "File supplied locally; source evidence not revalidated",
  computationData = null,
) {
  if (text.length > 128 * 1024 * 1024)
    throw Error("Viewer projection exceeds the 128 MiB limit");
  const model = createModel(JSON.parse(text));
  const computations = createComputations(
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
function repaint() {
  if (!state.frame)
    state.frame = requestAnimationFrame(() => {
      state.frame = 0;
      drawAll();
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
  return eventsInWindow(state.model, {
    firstCycle: state.first,
    endCycle: state.first + state.window,
    ...filters(),
  });
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
  const generated = computationLayers(state.computations, supplied, {
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
  if (state.circuitPaintCache.size >= 256) state.circuitPaintCache.clear();
  state.circuitPaintCache.set(key, result);
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
      "Computation circuits hidden; complete native graph retained.";
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
    node.textContent = `${selectionMessage} The complete recording and native graph remain loaded.`;
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
    ". Teal: data; amber: enable; purple: reset; white: shared roles. Structural fan-in includes unsensitized alternatives. Delay is a conservative SDF bound in the selected scope, not STA slack or an execution period.";
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
/** Orthographic camera. Space rotates independently of downward clock layers. */
function projector(w, h) {
  const depth = Math.min(
    h * 0.7,
    Math.max(50, (state.window - 1) * state.spacing),
  );
  const scale = Math.min(w * 0.23, (h - depth) * 0.8 + 50, 130),
    cosine = Math.cos(state.yaw),
    sine = Math.sin(state.yaw);
  return (point, cycle) => ({
    x: w * 0.44 + (point.x * cosine - point.y * sine) * scale,
    y:
      (h - depth) / 2 +
      (point.x * sine + point.y * cosine) * scale * state.tilt +
      ((cycle - state.first) * depth) / Math.max(1, state.window - 1),
  });
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
function layer(ctx, project, cycle, alpha, labels) {
  const corners = [
    { x: -1, y: -1 },
    { x: 1, y: -1 },
    { x: 1, y: 1 },
    { x: -1, y: 1 },
  ].map((p) => project(p, cycle));
  ctx.beginPath();
  corners.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
  ctx.closePath();
  ctx.fillStyle = `rgba(38,66,79,${alpha * 0.3})`;
  ctx.fill();
  ctx.strokeStyle = `rgba(112,150,167,${alpha})`;
  ctx.lineWidth = 0.7;
  ctx.stroke();
  const a = project({ x: -1.07, y: -1.1 }, cycle);
  ctx.fillStyle = "#718b99";
  ctx.font = "9px ui-monospace,monospace";
  labels.add(`C${cycle}`, a.x - 30, a.y, 100);
}
/** Reuse the unique cell table for faint context at the first layer. */
function installedContext(ctx, project) {
  if (!$("context").checked || !state.model.catalogue) return;
  const b = state.model.geometryBounds;
  if (!b) return;
  ctx.fillStyle = "#506d7a55";
  for (const cell of state.model.cells.values()) {
    if (!Number.isFinite(cell.x) || !Number.isFinite(cell.y)) continue;
    const p = project(
      {
        x: ((cell.x - b.minX) / (b.maxX - b.minX || 1) - 0.5) * 2,
        y: ((cell.y - b.minY) / (b.maxY - b.minY || 1) - 0.5) * 2,
      },
      state.first,
    );
    ctx.fillRect(p.x, p.y, 1, 1);
  }
}
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
/** Draw observed load bridges and same-version residence, never a dependency
 * from an overwritten word to the next word. The selected window controls cost. */
function drawResidence(ctx, project) {
  state.storageHits = [];
  if (!$("residence").checked) {
    $("storage-summary").textContent = "Cross-cycle storage hidden";
    return;
  }
  const segments = visibleStorage();
  const selected = new Set(selectedLifetimes().map((life) => life.version));
  // Draw selected details last so surrounding history cannot cover them.
  const emphasized = (segment) =>
    selected.has(segment.version) || segment.resource === state.resource;
  const ordered = [...segments].sort(
    (a, b) => Number(emphasized(a)) - Number(emphasized(b)),
  );
  let drawn = 0,
    loads = 0,
    holds = 0,
    cells = new Set();
  for (const segment of ordered) {
    if (segment.kind === "write") loads++;
    else holds++;
    for (const point of spatialPoints(storagePoints(segment), mappedOnly())) {
      const active = emphasized(segment),
        uncertain =
          segment.lifetime.continuity !== "within_declared_capture_scope";
      const a = project(point, segment.visibleFromCycle),
        b = project(point, segment.visibleToCycle);
      const stroke =
        point.kind === "unknown" || uncertain
          ? "#8c99a4"
          : active
            ? "#f7d684"
            : segment.kind === "write"
              ? "#67b9cc"
              : "#7797a8";
      ctx.globalAlpha = active ? 0.9 : point.kind === "cell" ? 0.32 : 0.48;
      line(
        ctx,
        a,
        b,
        stroke,
        active && point.kind !== "cell"
          ? 2.3
          : segment.kind === "write"
            ? 1.5
            : 1,
        segment.kind === "hold" || uncertain || point.kind === "unknown",
      );
      // A square marks Q at the next sample, even for a single-cycle value.
      if (segment.kind === "write" && !segment.afterWindow) {
        ctx.fillStyle = stroke;
        ctx.fillRect(b.x - 2, b.y - 2, 4, 4);
      }
      ctx.fillStyle = stroke;
      if (segment.beforeWindow) ctx.fillRect(a.x - 3, a.y - 1, 6, 2);
      if (segment.afterWindow) ctx.fillRect(b.x - 3, b.y - 1, 6, 2);
      state.storageHits.push({ a, b, segment, point });
      if (point.cell) cells.add(point.cell);
      drawn++;
    }
  }
  ctx.globalAlpha = 1;
  const words = new Set(segments.map((s) => `${s.resource}/${s.address}`)).size;
  $("storage-summary").textContent =
    ($("full-storage").checked
      ? "Full storage history · "
      : "Recorded uses only · ") +
    `${words} words · ${loads} load bridges · ${holds} residence spans` +
    (cells.size ? ` · ${cells.size} expanded cells` : " · grouped by word") +
    ` · ${drawn.toLocaleString()} strokes` +
    (state.window === 1
      ? " · show at least two clocks for cross-cycle links"
      : "");
}
/** Render graph edges only; off-window endpoints are clipped and labelled. */
function drawTrace(ctx, project, labels) {
  state.traceNote = "";
  if (!state.trace) return;
  let aggregates = 0,
    drawn = 0;
  const expanded = $("access-footprints").checked && state.model.catalogue;
  for (const edge of state.trace.edges) {
    const from = state.model.events.get(edge.source),
      to = state.model.events.get(edge.target);
    if (from.cycle >= state.first + state.window || to.cycle < state.first)
      continue;
    const outside =
      from.cycle < state.first || to.cycle >= state.first + state.window;
    const sources =
      expanded || mappedOnly()
        ? accessGeometry(from).points
        : [eventPoint(from)];
    const targets =
      expanded || mappedOnly() ? accessGeometry(to).points : [eventPoint(to)];
    const connection = expanded
      ? accessConnections(from, to, sources, targets)
      : { aggregate: false, pairs: [[eventPoint(from), eventPoint(to)]] };
    const { aggregate } = connection;
    const pairs = spatialPairs(
      aggregate ? [[eventPoint(from), eventPoint(to)]] : connection.pairs,
      sources,
      targets,
      mappedOnly(),
    );
    if (aggregate && pairs.length) aggregates++;
    for (const [source, target] of pairs) {
      const a = project(source, Math.max(state.first, from.cycle));
      const b = project(
        target,
        Math.min(state.first + state.window - 1, to.cycle),
      );
      ctx.globalAlpha = pairs.length > 1 ? 0.25 : 0.85;
      line(
        ctx,
        a,
        b,
        edge.kind === "resource_order" ? "#a8a0cc" : "#f7d684",
        1,
        outside,
      );
      if (outside) {
        ctx.font = "9px ui-monospace,monospace";
        ctx.fillStyle = "#f7d684";
        if (from.cycle < state.first)
          labels.add(`← C${from.cycle}`, a.x + 5, a.y - 4, 10);
        if (to.cycle >= state.first + state.window)
          labels.add(`C${to.cycle} →`, b.x + 5, b.y - 4, 10);
      }
      drawn++;
    }
  }
  ctx.globalAlpha = 1;
  state.traceNote = ` · ${drawn.toLocaleString()} dependency strokes${aggregates ? ` · ${aggregates} aggregate links (bit pairing unknown)` : ""}`;
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

/** Draw every access in the user-selected window using shared geometry. */
function drawStack() {
  const { ctx, w, h } = canvasContext("stack");
  if (!state.model) return;
  const project = projector(w, h),
    labels = canvasLabels(ctx, w, h),
    interval = Math.max(1, Math.ceil(state.window / 12));
  $("show-unmapped").disabled = !state.model.catalogue;
  for (let c = state.first; c < state.first + state.window; c += interval)
    layer(ctx, project, c, 0.3, labels);
  if ((state.window - 1) % interval)
    layer(ctx, project, state.first + state.window - 1, 0.3, labels);
  for (const epoch of state.model.bundle.capture.incarnations.slice(1)) {
    if (
      epoch.first_cycle < state.first ||
      epoch.first_cycle >= state.first + state.window
    )
      continue;
    const a = project({ x: -1, y: -1 }, epoch.first_cycle);
    const b = project({ x: 1, y: -1 }, epoch.first_cycle);
    line(ctx, a, b, "#ea8b94", 2);
    ctx.fillStyle = "#ea8b94";
    ctx.font = "10px system-ui";
    labels.add(`Reset · ${epoch.id}`, a.x + 6, a.y - 6, 90);
  }
  installedContext(ctx, project);
  renderCircuitSummary(drawComputations(ctx, project));
  drawResidence(ctx, project);
  drawTrace(ctx, project, labels);
  state.hits = [];
  const pathIds = new Set(state.trace?.events.map((e) => e.id) ?? []);
  const seeds = new Set(selectionEvents().map((event) => event.id));
  const events = visibleEvents().sort(
    (a, b) =>
      Number(seeds.has(a.id) || pathIds.has(a.id)) -
      Number(seeds.has(b.id) || pathIds.has(b.id)),
  );
  let drawn = 0;
  const expanded = $("access-footprints").checked && state.model.catalogue;
  for (const event of events) {
    const selected = seeds.has(event.id),
      onPath = pathIds.has(event.id);
    const geometry = expanded || mappedOnly() ? accessGeometry(event) : null;
    // A compact word centroid does not locate an access selecting unknown bits.
    if (mappedOnly() && !geometry.points.some((point) => point.physical))
      continue;
    const points = spatialPoints(
      expanded ? geometry.points : [eventPoint(event)],
      mappedOnly(),
    );
    for (const point of points) {
      const p = project(point, event.cycle);
      ctx.globalAlpha =
        state.trace && !onPath
          ? 0.14
          : point.physical || !state.model.catalogue
            ? 0.8
            : 0.45;
      const stroke = selected
        ? "#fff0ac"
        : onPath
          ? "#f7d684"
          : point.physical || !state.model.catalogue
            ? color(event)
            : "#8c99a4";
      ctx.fillStyle = ctx.strokeStyle = stroke;
      ctx.beginPath();
      ctx.arc(p.x, p.y, selected ? 3.5 : onPath ? 2.4 : 1.5, 0, Math.PI * 2);
      if (geometry?.footprint.mode === "word_context" && point.physical)
        ctx.stroke();
      else ctx.fill();
      if (selected && points.length === 1) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, 8, 0, Math.PI * 2);
        ctx.stroke();
      }
      state.hits.push({ ...p, event });
      drawn++;
    }
  }
  $("access-summary").textContent = !state.model.catalogue
    ? "Logical layout · native access placement unmeasured"
    : expanded
      ? "Accesses at native tiles · hollow = word context, read-bit subset unknown"
      : "Compact aggregate symbols · centers are not computation locations";
  $("access-summary").textContent +=
    ` · ${drawn.toLocaleString()} access glyphs` + state.traceNote;
  $("access-summary").textContent += mappedOnly()
    ? " · unmapped geometry hidden; records and totals retained"
    : "";
  drawNativePath(ctx, project, false, labels);
  ctx.globalAlpha = 1;
  const p = project({ x: 1.4, y: 0 }, state.first);
  ctx.fillStyle = "#91a7b3";
  ctx.font = "10px system-ui";
  if (!mappedOnly())
    labels.add(
      state.model.catalogue ? "UNMAPPED / UNKNOWN" : "LOGICAL LAYOUT",
      p.x - 50,
      p.y - 23,
      60,
    );
  if (state.annotation) {
    const cycle = state.annotation.cycle;
    if (cycle >= state.first && cycle < state.first + state.window) {
      const p = project({ x: -1.2, y: 1 }, cycle);
      ctx.fillStyle = "#f1bb6c";
      labels.add(`Public completion · C${cycle}`, p.x, p.y + 16, 90);
    }
  }
  labels.draw();
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
/** Paint synchronized canvases after data and layout changes. */
function drawAll() {
  drawStack();
  drawFlat();
  drawTimeline();
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
    if (d <= dist) {
      dist = d;
      best = hit;
    }
  }
  return best;
}
/** Nearest rendered storage span, independently of dense same-clock dots. */
function nearestStorage(x, y) {
  let best = null,
    distance = 25;
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
    if (d <= distance) {
      best = hit;
      distance = d;
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
    const signal = state.loadController.signal;
    const url = $("capture").value;
    setBusy(true);
    try {
      notice("Reading saved capture…");
      const response = await fetch(url, { signal });
      if (!response.ok)
        throw Error(`Capture fetch failed (${response.status})`);
      const bytes = await response.arrayBuffer();
      if (bytes.byteLength > 128 * 1024 * 1024)
        throw Error("Projection exceeds 128 MiB");
      const expected = state.index.get(url);
      if (!expected || bytes.byteLength !== expected.bytes)
        throw Error("Projection length does not match the local index");
      const digest = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      if (digest !== expected.sha256)
        throw Error("Projection digest does not match the local index");
      const computationData = await loadComputations({
        entry: expected.computations,
        signal,
        view: { bytes: bytes.byteLength, sha256: digest },
        baseUrl: new URL("data/", window.location.href).href,
        progress: (message) => {
          if (sequence === state.loadSequence) notice(message);
        },
      });
      if (sequence !== state.loadSequence) return;
      await loadDocument(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        "Projection bytes verified against local index; original evidence was verified when this projection was prepared.",
        computationData,
      );
    } catch (e) {
      if (sequence === state.loadSequence) notice(e.message, true);
    } finally {
      if (sequence === state.loadSequence) setBusy(false);
    }
  };
  $("file").onchange = async () => {
    const sequence = ++state.loadSequence;
    state.loadController?.abort();
    state.loadController = null;
    const file = $("file").files[0];
    if (!file) return;
    try {
      if (file.size > 128 * 1024 * 1024) throw Error("File exceeds 128 MiB");
      const text = await file.text();
      if (sequence !== state.loadSequence) return;
      await loadDocument(text);
    } catch (e) {
      notice(e.message, true);
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
  $("spatial-density").onchange = repaint;
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
    $(id).onchange = repaint;
  $("circuit-delay").onchange = () => {
    const value = Number($("circuit-delay").value);
    if (!Number.isFinite(value) || value < 0) $("circuit-delay").value = "0";
    repaint();
  };
  $("context").onchange = repaint;
  $("show-unmapped").onchange = repaint;
  $("residence").onchange = repaint;
  $("full-storage").onchange = render;
  $("access-footprints").onchange = repaint;
  $("native-path").onchange = () => {
    state.nativePath =
      state.nativePaths.find((p) => p.id === $("native-path").value) ?? null;
    renderNativePath();
    repaint();
  };
  $("expand-storage").onchange = repaint;
  $("reset-camera").onclick = () => {
    state.yaw = -0.6;
    state.tilt = 0.5;
    repaint();
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
    drag = { ...pointer(e), yaw: state.yaw, tilt: state.tilt, moved: false };
    stack.setPointerCapture(e.pointerId);
  };
  stack.onpointermove = (e) => {
    const p = pointer(e);
    if (drag) {
      const dx = p.x - drag.x,
        dy = p.y - drag.y;
      if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true;
      state.yaw = drag.yaw + dx * 0.008;
      state.tilt = Math.max(0.12, Math.min(1, drag.tilt + dy * 0.003));
      repaint();
    } else {
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
      const hit = nearest(state.hits, p.x, p.y, 5);
      const storage = hit ? null : nearestStorage(p.x, p.y);
      if (hit) selectEvent(hit.event.id, false);
      else if (storage)
        selectStorage(storage.segment.version, storage.point.cell ?? null);
    }
    drag = null;
  };
  stack.onpointercancel = () => (drag = null);
  stack.onpointerleave = () => {
    $("tooltip").hidden = true;
  };
  stack.onkeydown = (e) => {
    if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
      state.yaw += e.key === "ArrowRight" ? 0.1 : -0.1;
      repaint();
      e.preventDefault();
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
  new ResizeObserver(repaint).observe(document.querySelector(".workspace"));
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
      if (state.model?.document.examples?.length) {
        $("example").value = "0";
        chooseExample(0);
      }
    }
  } catch (e) {
    notice(
      `Cannot open saved example: ${e.message}. You can still open a projection file.`,
      true,
    );
  }
}
initialize();
