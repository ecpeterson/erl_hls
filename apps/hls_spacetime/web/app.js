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
import {
  traceChain,
  matchingChain,
  chainDisplayBounds,
  chainTargetMasks,
  chainCircuitSelection,
  chainStorageSegments,
} from "./action-chain.js";
import { eventFootprint, accessConnections } from "./footprint.js";
import { nativePaths } from "./native-paths.js";
import { nativeRoutes } from "./native-routes.js";
import { openxc7Routing, showOpenxc7Routes } from "./openxc7-routes.js";
import { loadComputations, publicationUrl } from "./computation-loader.js";
import { loadRecording } from "./recording-loader.js";
import { loadPreparedRenderWorker } from "./prepared-loader.js";
import {
  createPreparedComputations,
  preparedComputationLayers,
  preparedCircuitPaint,
} from "./prepared-computations.js";
import { circuitDisplay } from "./circuit-display.js";
import { createSinkInspector } from "./sink-inspector.js";
import { arrivalCircuit } from "./arrival-circuits.js";
import { arrivalScene } from "./arrival-scene.js";
import { arrivalRuler } from "./arrival-ruler.js";
import { selectClockPeriod, timePoint } from "./clock-reference.js";
import { clockSink } from "./clock-sink.js";
import {
  createStepComparison,
  installStepEvidence,
} from "./step-comparison.js";
import { loadStepEvidence } from "./step-evidence-loader.js";
import { neighborhoodScene, cutScene } from "./neighborhood-scene.js";
import { createRegionalControls } from "./regional-controls.js";
import { createScenarioControls } from "./scenario-controls.js";
import { createSceneSelection } from "./scene-selection.js";
import { sinkPickTargets } from "./scene-picking.js";
import {
  arrivalEventAnchor,
  arrivalEventConnection,
} from "./arrival-events.js";
import { overlayDisplay } from "./overlay-display.js";
import { createScene3D } from "./scene3d.js";
import { sceneBounds, occupiedBins } from "./scene-layout.js";
import {
  sceneColor,
  computationColor,
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
  computationControlSelection,
} from "./computation-view.js";
import { windowMetrics } from "./metrics.js";
import { layoutLabels, projectLabelAnchors } from "./labels.js";
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
  chain: null,
  chainMatchNote: null,
  nativeBounds: null,
  displayBounds: null,
  expectsPrepared: false,
  first: 0,
  window: 24,
  scene: null,
  sceneContent: null,
  sceneDirty: true,
  sceneError: null,
  frameFull: false,
  autoFit: true,
  eventCache: null,
  loadTimings: {},
  spacing: 8,
  manualPeriodNs: 10,
  clockSelection: null,
  timeOriginCycle: null,
  flatHits: [],
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
const sinkInspector = createSinkInspector(() => {
  $("pick-notice").textContent = "";
  repaint();
});
const sceneSelection = createSceneSelection({
  onChoose(target) {
    if (target.kind === "sink") {
      if (!sinkInspector.choose(target.sinkKey)) return false;
      $("sink-panel").open = true;
    } else if (target.kind === "event") {
      if (
        state.model.events.get(target.event.id) !== target.event ||
        !visibleEvents().includes(target.event)
      )
        return false;
      selectEvent(target.event.id, false);
    } else {
      if (!visibleStorage().includes(target.segment)) return false;
      selectStorage(target.segment.version, target.point.cell ?? null);
    }
    return true;
  },
  onOverlay: () => drawStackOverlay(),
});
const regionalControls = createRegionalControls(() => repaint());
const scenarioControls = createScenarioControls();
const stepComparison = createStepComparison({
  element: $("step-comparison"),
  onFocusBoundary: (boundary) => focusStepBoundary(boundary, false),
  onTraceCompletion: (boundary) => focusStepBoundary(boundary, true),
  onInspectClockPath: inspectClockPath,
});

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
  { preparedExpected = false, computationsExpected = false } = {},
) {
  sceneSelection.reset();
  regionalControls.configure();
  scenarioControls.configure();
  if (!computationData && model.document.openxc7Computations)
    computationData = {
      attachment: model.document.openxc7Computations,
      routeNets: model.document.openxc7Routes?.nets ?? [],
    };
  const computations = computationData?.prepared
    ? createPreparedComputations(model, computationData.prepared)
    : createComputations(
        model,
        computationData?.attachment,
        computationData?.routeNets,
      );
  const paths = nativePaths(model);
  showOpenxc7Routes(
    $("openxc7-routing"),
    openxc7Routing(model, model.document.openxc7Routes),
  );
  const nativeTiming =
    model.document.openxc7Timing ??
    model.document.openxc7Computations?.timingModel;
  const modelNote = $("openxc7-timing-model");
  modelNote.hidden = !nativeTiming;
  if (nativeTiming) {
    const predicted =
      nativeTiming.predicted ??
      model.document.openxc7Computations.arcs.filter(
        (a) => a.timing.basis === "predicted",
      ).length;
    modelNote.textContent = `nextpnr structural timing · ${predicted} predicted net delays · ${nativeTiming.unresolved_delays} unavailable delay queries. Slice flip-flops use compiled clock constants.${nativeTiming.bram_model_sha256 ? " RAM timing is qualified by primitive configuration." : ""}${nativeTiming.carry_di_model ? " Carry DI arcs use placed-site variant maxima." : ""} Per-entry database characterization is unverified.`;
  }
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
  state.expectsPrepared = Boolean(computations?.prepared || preparedExpected);
  $("computation-circuits").checked = Boolean(
    computations || computationsExpected || preparedExpected,
  );
  $("time-layout").disabled = !computations?.prepared;
  $("time-layout").value = state.expectsPrepared ? "arrival" : "flat";
  $("pick-mode").value = state.expectsPrepared ? "sinks" : "writes";
  if (state.expectsPrepared) {
    $("color-mode").value = "criticality";
    state.spacing = 32;
    $("spacing").value = state.spacing;
  }
  $("circuit-role").value = "";
  $("circuit-timing").value = "registered_launch";
  $("circuit-delay").value = "0";
  $("circuit-unknown").checked = true;
  $("circuit-selected").checked = false;
  state.model = model;
  state.timeOriginCycle =
    model.stepComparison?.start.cycle ?? selectedBounds().firstCycle;
  state.nativeBounds = model.geometryBounds;
  state.displayBounds = null;
  state.autoFit = true;
  state.eventCache = null;
  state.selected = null;
  state.trace = null;
  state.annotation = null;
  state.chain = null;
  state.chainMatchNote = null;
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
  $("chain").replaceChildren(new Option("Choose an action chain", ""));
  for (const chain of model.chains.values())
    $("chain").add(new Option(chain.title, chain.id));
  $("chain-panel").hidden = model.chains.size === 0;
  state.first = selectedBounds().firstCycle;
  state.window = Math.min(
    state.expectsPrepared ? 3 : 24,
    selectedBounds().endCycle - state.first,
  );
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
  state.model.geometryBounds = state.nativeBounds
    ? { ...state.nativeBounds }
    : null;
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
  state.nativeBounds = state.model.geometryBounds;
  state.model.geometryBounds = chainDisplayBounds(
    state.chain,
    state.nativeBounds,
    state.displayBounds,
  );
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
  $("time-layout").disabled = !state.computations.prepared;
  if (!state.computations.prepared) $("time-layout").value = "flat";
  // Defaults were chosen before interaction. Installing geometry must not reset
  // the user's window, camera, picking mode or controls, even without a chain.
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
/** Clock selection uses whole-design metadata, never the visible circuit subset.
 * Captures without qualified clock metadata retain an explicit manual fallback.
 * The manual value is shared across capture changes and is never overwritten by
 * an automatic or original-target selection.
 */
function syncClockControls() {
  const mode = $("clock-source").value;
  const options = { mode, manualPeriodNs: state.manualPeriodNs };
  const selected = selectClockPeriod(
    state.model?.clockReference ?? null,
    options,
  );
  const fallback = selected.status !== "available";
  state.clockSelection = fallback
    ? {
        ...selectClockPeriod(null, { ...options, mode: "manual" }),
        requestedMode: mode,
        fallback: true,
        label: `Manual fallback (${state.manualPeriodNs} ns)`,
      }
    : selected;
  const input = $("arrival-budget");
  input.value = Number(state.clockSelection.periodNs.toPrecision(12));
  input.readOnly = mode !== "manual";
  input.title =
    mode === "manual"
      ? "Shared hypothetical period; changing it does not change static arc delays"
      : "Resolved from the selected period source; choose Manual to override";
  const available = Boolean(state.model?.clockReference);
  $("clock-source").querySelector('option[value="target"]').disabled =
    !available;
  const evidence = state.clockSelection.provenance;
  const basis = evidence
    ? mode === "auto"
      ? `${evidence.targetPeriodNs} ns target − (${evidence.setupWnsNs} ns WNS). `
      : `${evidence.targetPeriodNs} ns original constraint. `
    : "";
  $("clock-reference-note").textContent =
    `${state.clockSelection.label}. ${fallback ? "Requested clock evidence is unavailable; using the shared manual value. " : ""}${basis}This is a reference estimate or assumption, not a measured running clock. One common nanosecond scale is retained across captures; filters do not change the period.`;
  $("clock-reference-evidence").hidden = !available;
  $("clock-reference-provenance").textContent = available
    ? JSON.stringify(state.model.clockReference, null, 2)
    : "";
  return state.clockSelection;
}

/** The chosen action/step establishes elapsed-time zero. Ordinary event picks
 * and filters retain it. Neither a changed period nor a matched capture recenters
 * time about its visible midpoint; the camera retains the common comparison scale.
 */
function clockOriginCycle() {
  return state.timeOriginCycle ?? selectedBounds().firstCycle;
}

/** Keep the compact scene identifiable without reopening its hidden controls. */
function renderSceneCaption() {
  if (!state.model) return;
  const labels = [state.model.document.title ?? "Saved execution"];
  if (state.chain) labels.push(state.chain.title);
  labels.push(`C${state.first}–${state.first + state.window - 1}`);
  const clock = state.clockSelection ?? syncClockControls();
  labels.push(
    `${Number(clock.periodNs.toPrecision(12))} ns · ${clock.label} · common ns scale · t=0 at C${clockOriginCycle()}`,
  );
  $("scene-caption").textContent = labels.join(" · ");
}
/** Queue one canvas repaint for related inputs or pointer movement. */
function repaint(cameraOnly = false) {
  renderSceneCaption();
  sceneSelection.invalidate();
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
        sceneSelection.reset();
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
  $("pick-notice").textContent = "";
  normalizeWindow();
  syncClockControls();
  stepComparison.update(state.model, {
    clockSelection: state.clockSelection,
    firstCycle: state.first,
    endCycle: state.first + state.window,
  });
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
  renderChain();
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
    whatIfPeriodNs: state.clockSelection.periodNs,
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
    `${state.clockSelection.label}: ${timing.whatIf.elapsedClocks} clocks × ${Number(timing.whatIf.periodNs.toPrecision(12))} ns = ${timing.whatIf.elapsedNs.toLocaleString(undefined, { maximumFractionDigits: 6 })} ns for this window. This reference estimate uses the same period as the scene and whole-step panel; it is not measured elapsed time. Static path delays are not added again.`;
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
  if (state.chain)
    return state.chain.sinks.map((id) => state.model.events.get(id));
  return state.annotation
    ? annotationEvents(state.model, state.annotation)
    : [];
}
/** Semantic filters clear excluded selections across the full capture, not the window. */
function clearFilteredSelection() {
  const seeds = state.chain ? state.trace.events : selectionEvents();
  if (!seeds.length) return;
  const matching = new Set(
    eventsInWindow(state.model, filters()).map((event) => event.id),
  );
  if (seeds.some((event) => matching.has(event.id))) return;
  state.selected = null;
  state.trace = null;
  state.annotation = null;
  state.focusVersion = null;
  state.chain = null;
  $("chain").value = "";
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
  state.chain = null;
  $("chain").value = "";
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
  const key = JSON.stringify([
    opts,
    state.chain?.id,
    $("chain-only").checked,
    $("chain-context").checked,
  ]);
  if (state.eventCache?.key !== key) {
    let events = eventsInWindow(state.model, opts);
    if (state.chain && $("chain-only").checked) {
      const ids = new Set(state.trace.events.map((event) => event.id));
      if ($("chain-context").checked)
        for (const edge of state.trace.boundaryInputs) ids.add(edge.source);
      events = events.filter((event) => ids.has(event.id));
    }
    state.eventCache = { key, events };
  }
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
  const displayMask =
    state.chain && $("chain-only").checked
      ? chainTargetMasks(state.model, state.chain).get(event.id)
      : undefined;
  const key = event.access
    ? JSON.stringify([
        event.access.resource,
        event.access.kind,
        event.access.mask ?? null,
        event.access.read_mask ?? null,
        displayMask ?? null,
      ])
    : event.id;
  if (state.footprintCache.has(key)) return state.footprintCache.get(key);
  const footprint = eventFootprint(state.model, event.id, { displayMask });
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

/** Arrival phases require the qualified native pin and arc tables. */
function arrivalEnabled() {
  return (
    Boolean(state.computations?.prepared) &&
    $("time-layout").value === "arrival"
  );
}
/** A following sample must exist in this incarnation before depicting capture.
 * The final pre-edge sample alone does not establish next-Q observation. */
function captureAvailable(cycle) {
  return state.model.bundle.capture.incarnations.some(
    (epoch) => epoch.first_cycle <= cycle && cycle + 1 < epoch.end_cycle,
  );
}
/** Cache the visible clock-layer unions independently of the camera. All graph
 * rows remain retained when functionality or static-delay filters hide geometry. */
function circuitLayers() {
  if (!state.computations || !$("computation-circuits").checked) return [];
  const selectedOnly = $("circuit-selected").checked && !state.chain;
  const key = JSON.stringify([
    state.first,
    state.window,
    filters(),
    state.chain?.id,
    $("chain-only").checked,
    $("chain-context").checked,
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
    : chainCircuitSelection(state.chain, visibleEvents(), {
        onlyChain: $("chain-only").checked,
        includeContext: $("chain-context").checked,
      });
  const generated = (
    state.computations.prepared ? preparedComputationLayers : computationLayers
  )(state.computations, supplied, {
    roles: $("circuit-role").value
      ? [$("circuit-role").value]
      : ["data", "enable", "reset"],
    minimumDelayNs: Number($("circuit-delay").value),
    timingMetric: $("circuit-timing").value,
    includeUnknownTiming: $("circuit-unknown").checked,
    targetMasks:
      state.chain && $("chain-only").checked
        ? chainTargetMasks(state.model, state.chain)
        : new Map(),
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
      if (!index.attachment.timingModel)
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
    ". Structural fan-in includes unsensitized alternatives. Colors follow the selected legend. Timing color bounds complete source-to-sink paths through the geometry; the filter uses whole-cone bounds. Neither is STA slack or an execution period.";
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
      if (!state.model.document.openxc7Routes)
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
  if (state.chain)
    return state.trace.focusVersions
      .map((id) => state.model.lifetimes.get(id))
      .filter(Boolean);
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
    endCycle: state.first + state.window + (arrivalEnabled() ? 1 : 0),
    ...filters(),
    usedOnly: !$("full-storage").checked,
  };
  const key = JSON.stringify(options);
  if (state.storageCache?.key !== key)
    state.storageCache = {
      key,
      segments: storageSegments(state.model, options),
    };
  return state.chain && $("chain-only").checked
    ? chainStorageSegments(
        state.model,
        state.chain,
        state.trace,
        state.storageCache.segments,
        {
          includeContext: $("chain-context").checked,
        },
      ).segments
    : state.storageCache.segments;
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
    $("expand-storage").checked &&
    (state.resource === segment.resource || Boolean(state.chain));
  const producer = state.model.versions.get(segment.version).producer;
  const displayMask =
    state.chain && $("chain-only").checked
      ? chainTargetMasks(state.model, state.chain).get(producer)
      : undefined;
  const key = JSON.stringify([
    segment.resource,
    segment.address,
    expand,
    displayMask,
  ]);
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
  const subset = displayMask
    ? eventFootprint(model, producer, { displayMask })
    : null;
  const represented = subset
    ? [...subset.cells, ...subset.unplacedCells]
    : placement.cells;
  const placed = represented.filter(
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
    (subset ? subset.unknownBits : placement.unknownBits) ||
    (!subset && placement.candidateCells.length) ||
    placed.length < represented.length
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
    ? `${path.dataDelayNs} ns data = ${path.logicDelayNs} logic + ${path.routeDelayNs} route; slack ${path.slackNs} ns.${path.requiredNs !== undefined ? ` Required ${path.requiredNs} ns, capture setup ${path.setupNs} ns.` : ""} Static STA path; activity at this clock unknown. ` +
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

/** Small inspection table exposes native arc identities and local versus complete
 * delay. Only table rows are paged; the renderer retains every visible arc. */
function renderArrivalDetails(circuits, maximum, summaries, eventOmissions) {
  $("untimed-summary").hidden = !arrivalEnabled();
  $("arrival-details").hidden = !arrivalEnabled();
  if (!arrivalEnabled()) return;
  const arcs = new Map();
  for (const circuit of circuits)
    for (const row of circuit.details) {
      const old = arcs.get(row.arc);
      if (!old) arcs.set(row.arc, { ...row });
      else {
        old.pathDelayNs =
          old.pathDelayNs === null
            ? row.pathDelayNs
            : row.pathDelayNs === null
              ? old.pathDelayNs
              : Math.max(old.pathDelayNs, row.pathDelayNs);
        old.timingUnknown ||= row.timingUnknown;
        old.arrivalUnknown ||= row.arrivalUnknown;
        old.schematic ||= row.schematic;
        old.geometryIncomplete ||= row.geometryIncomplete;
        for (const field of ["arrivalFromNs", "arrivalViaNs", "arrivalToNs"])
          if (old[field] !== row[field]) {
            old[field] = null;
            old.arrivalUnknown = true;
          }
      }
    }
  const rows = [...arcs.values()].sort(
    (a, b) =>
      (b.pathDelayNs ?? -1) - (a.pathDelayNs ?? -1) ||
      (b.delayNs ?? -1) - (a.delayNs ?? -1),
  );
  const format = (value) =>
    typeof value === "number"
      ? value.toFixed(3)
      : value === "not_applicable"
        ? "outside scope"
        : "unknown";
  const count = (key) => summaries.reduce((n, row) => n + (row[key] ?? 0), 0);
  sinkInspector.updateGeometry(circuits);
  $("untimed-summary").textContent =
    `${count("unknownSegments").toLocaleString()} spans · ${count("unknownMarks").toLocaleString()} pin marks · ${count("unknownRoots").toLocaleString()} roots lack arrival timing. ${eventOmissions.events.toLocaleString()} event overlays and ${eventOmissions.dependencies.toLocaleString()} dependency overlays lack qualified boundary coordinates. These are omitted here; clock planes, event lists and inspectors retain the evidence. Missing timing is not zero.${eventOmissions.staticPath ? " The saved STA path overlay also remains in clock planes because its geometry has no qualified arrival heights." : ""}`;
  $("untimed-summary").hidden =
    !count("unknownSegments") &&
    !count("unknownMarks") &&
    !count("unknownRoots") &&
    !eventOmissions.events &&
    !eventOmissions.dependencies &&
    !eventOmissions.staticPath;
  $("arrival-summary").textContent =
    `${arcs.size.toLocaleString()} distinct visible arcs · ${rows.filter((row) => row.schematic).length} schematic endpoint connections (native route geometry incomplete) · ${count("lateRoots")} late roots at the ${$("arrival-budget").value} ns reference period · ${count("unknownRoots")} roots without arrival · ${count("uncapturedRoots")} roots without a following sample. ${count("unknownSegments")} untimed spans and ${count("unknownMarks")} untimed pin marks omitted from arrival view. Showing the first ${Math.min(40, rows.length)} inspection rows; clock planes retain spatial context.`;
  $("arrival-table").innerHTML =
    `<table><thead><tr><th>Native arc / pins</th><th>Geometry</th><th>Local ns</th><th>Complete ns</th><th>Below longest ns</th><th>Arrival from → via → latest ns</th></tr></thead><tbody>${rows
      .slice(0, 40)
      .map(
        (row) =>
          `<tr><td>${esc(row.arc)}: ${esc(row.fromPin)} → ${esc(row.toPin)}</td><td>${row.schematic ? "schematic endpoint connection" : row.geometryIncomplete ? "incomplete" : row.located ? "retained endpoints / connectivity" : "unlocated"}</td><td>${format(row.delayNs)}</td><td>${row.timingUnknown ? "unknown" : format(row.pathDelayNs)}</td><td>${format(!row.timingUnknown && row.pathDelayNs !== null && maximum !== null ? maximum - row.pathDelayNs : null)}</td><td>${format(row.arrivalFromNs)} → ${format(row.arrivalViaNs)} → ${format(row.arrivalToNs)}</td></tr>`,
      )
      .join("")}</tbody></table>`;
}

/** Assemble world geometry only when data or visibility changes. Camera motion
 * reuses the GPU buffers and does not redo graph queries, filtering or unions. */
function buildStackScene() {
  const result = {
    segments: [],
    markers: [],
    surfaces: [],
    targets: [],
    labels: [],
    focus: [],
    selection: [],
  };
  const clock = state.clockSelection ?? syncClockControls();
  const world = (p, c) =>
    timePoint(p, c, {
      periodNs: clock.periodNs,
      originCycle: clockOriginCycle(),
      unitsPerNs: state.spacing / 800,
    });
  const segment = (
    a,
    b,
    color,
    radius = 0.002,
    kind = "route",
    colorEnd = color,
    dash = 0,
  ) =>
    result.segments.push({
      from: a,
      to: b,
      color,
      colorEnd,
      radius,
      kind,
      dash,
    });
  const marker = (position, color, size = 0.006, priority = 0) =>
    result.markers.push({ position, color, size, priority });
  const arrival = arrivalEnabled();
  $("pick-mode").querySelector('option[value="sinks"]').disabled = !arrival;
  const controlSelection = computationControlSelection({
    preparedPending: state.expectsPrepared && !state.computations,
    prepared: Boolean(state.computations?.prepared),
    arrival,
    pickMode: $("pick-mode").value,
    colorMode: $("color-mode").value,
  });
  $("pick-mode").value = controlSelection.pickMode;
  const pickMode = controlSelection.pickMode;
  const interval = Math.max(1, Math.ceil(state.window / 8));
  const planes = [];
  for (let c = state.first; c < state.first + state.window; c += interval)
    planes.push(c);
  if (arrival) planes.push(state.first + state.window);
  for (const c of planes) {
    const corners = [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1],
    ].map(([x, y]) => world({ x, y }, c));
    for (let i = 0; i < 4; i++)
      segment(corners[i], corners[(i + 1) % 4], "#2d4855", 0.0009, "frame");
    const elapsedNs = Number(
      ((c - clockOriginCycle()) * clock.periodNs).toFixed(3),
    );
    result.labels.push({
      text: arrival
        ? c < state.model.bundle.capture.end_cycle
          ? `Q C${c} · ${elapsedNs} ns`
          : `Boundary C${c} · ${elapsedNs} ns (no Q)`
        : `C${c} · ${elapsedNs} ns`,
      position: world({ x: -1.04, y: -1.04 }, c),
      alternatives: corners,
      anchorGroup: "clock-axis",
    });
  }
  if (arrival)
    for (const label of arrivalRuler(
      state.first,
      state.window,
      state.clockSelection.periodNs,
    )) {
      const corners = [
        [-1, -1],
        [1, -1],
        [1, 1],
        [-1, 1],
      ].map(([x, y]) => world({ x, y }, label.coordinate));
      result.labels.push({
        ...label,
        position: corners[0],
        alternatives: corners,
        anchorGroup: "clock-axis",
        minor: true,
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
        marker(world(cellPoint(cell), state.first), "#344c59", 0.004, -1);
    }
  const layers = circuitLayers();
  renderCircuitSummary(layers);
  const metric = $("circuit-timing").value;
  const delayKey =
    metric === "registered_launch"
      ? "registeredPathDelayNs"
      : "staticPathDelayNs";
  const applicableKey =
    metric === "registered_launch"
      ? "registeredPathApplicable"
      : "staticPathApplicable";
  const maximum =
    state.computations?.maxDelays?.[
      metric === "registered_launch" ? "registered" : "static"
    ] ?? null;
  for (const value of ["computation", "criticality", "delay-kind"]) {
    const option = $("color-mode").querySelector(`option[value="${value}"]`);
    option.disabled =
      !state.computations?.prepared || (value === "delay-kind" && !arrival);
    option.title = option.disabled
      ? "Prepare rendering data to enable this color style"
      : "";
  }
  $("color-mode").value = controlSelection.colorMode;
  const mode = $("color-mode").value;
  const membershipMode = mode === "computation" || mode === "criticality";
  const neutralTiming = mode === "criticality" || mode === "delay-kind";
  sinkInspector.update(state.computations, layers, {
    enabled: arrival,
    scope: metric === "registered_launch" ? "registered" : "static",
  });
  const explorer = sinkInspector.explorer;
  regionalControls.update(state.computations, explorer.neighborhood);
  scenarioControls.update(state.computations, explorer.cut);
  const cutMode = explorer.mode === "cut";
  $("color-mode").disabled = cutMode;
  $("analysis-legend").hidden = !["neighborhood", "cut"].includes(
    explorer.mode,
  );
  $("analysis-legend").textContent = cutMode
    ? "Candidate cut: amber before, blue after, gold crossing bits. Original arrival geometry; no new hardware or timing measurement."
    : "Neighborhood: representative paths to similarly timed nearby sinks; installed logic on a separate reference plane. Driver spokes show connectivity, not routed wires or activity.";
  $("delay-kind-legend").hidden = cutMode || mode !== "delay-kind";
  $("role-legend").hidden = cutMode || mode !== "role";
  $("arrival-legend").hidden = !arrival;
  $("arrival-ruler-note").textContent =
    state.window <= 4
      ? "Ruler: nanoseconds after each Q reference at quarter-budget intervals; labels yield to clock labels when crowded."
      : "Minor ruler labels are omitted for windows over four clocks; no computation geometry is omitted.";
  $("urgency-window").disabled = !["criticality", "delay-kind"].includes(mode);
  $("urgency-legend").hidden =
    cutMode || !["criticality", "delay-kind"].includes(mode);
  $("urgency-summary").textContent =
    `Bright: within ${$("urgency-window").value} ns of the capture-wide longest ${metric === "registered_launch" ? "registered-launch" : "static"} path (${maximum?.toFixed(3) ?? "unknown"} ns). Relative structural margin, not STA slack or congestion.`;
  $("computation-legend").hidden = cutMode || !membershipMode;
  $("direction-legend").hidden = cutMode || mode !== "direction";
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
  $("detail-level").querySelector('option[value="overview"]').textContent =
    arrival ? "Pin arrivals" : "Occupied tiles";
  $("detail-level").querySelector('option[value="switches"]').disabled =
    arrival;
  if (arrival && $("detail-level").value === "switches")
    $("detail-level").value = "routes";
  const detail = $("detail-level").value;
  const dim = $("ghost-context").checked;
  // A small style cache avoids repeating perceptual color conversion per primitive.
  const palette = new Map();
  const shade = (row) => {
    if (mode === "direction") return "#627780";
    const delayNs = row[
      metric === "registered_launch"
        ? "registeredPathTimingUnknown"
        : "staticPathTimingUnknown"
    ]
      ? null
      : (row[delayKey] ?? row.delayNs ?? null);
    const key = JSON.stringify([
      row.role,
      row.delayKind,
      row.computationKey,
      row.computationShared,
      row[applicableKey],
      delayNs,
    ]);
    if (!palette.has(key))
      palette.set(
        key,
        sceneColor({
          role: row.role,
          kind: row.delayKind,
          mode,
          computationKey: row.computationKey,
          computationShared: row.computationShared,
          delayNs,
          timingApplicable: row[applicableKey],
          maxDelayNs: maximum,
          marginWindowNs: Number($("urgency-window").value),
        }),
      );
    return palette.get(key);
  };
  const arrivalCircuits = [],
    arrivalSummaries = [];
  for (const layer of layers) {
    if (arrival) {
      const circuit = arrivalCircuit(state.computations, layer, {
        scope: metric === "registered_launch" ? "registered" : "static",
        includeUnresolved: !mappedOnly(),
        bridgeKnownGeometry: true,
        selection: sinkInspector.selection,
      });
      const scene = arrivalScene(circuit, {
        cycle: layer.cycle,
        budgetNs: state.clockSelection.periodNs,
        captureAvailable: captureAvailable(layer.cycle),
        point: cellPoint,
        world,
        shade: (row) =>
          explorer.shade(
            row,
            shade({
              ...row,
              [delayKey]: row.timingUnknown ? null : row.pathDelayNs,
              [applicableKey]: row.status !== "not_applicable",
              [metric === "registered_launch"
                ? "registeredPathTimingUnknown"
                : "staticPathTimingUnknown"]: row.timingUnknown,
            }),
          ),
        mode: cutMode ? "cut" : mode,
        detail,
        activeArc: sinkInspector.activeArc,
      });
      if (sinkInspector.focused)
        result.selection = result.selection.concat(scene.focus);
      // Concatenation avoids argument limits on complete native populations.
      result.segments = result.segments.concat(scene.segments);
      result.markers = result.markers.concat(scene.markers);
      result.focus = result.focus.concat(scene.focus);
      if (explorer.cut?.status === "known" && circuit.summary.arcs) {
        const boundary = cutScene(explorer.cut, {
          cycle: layer.cycle,
          budgetNs: state.clockSelection.periodNs,
          point: cellPoint,
          world,
          selectedPin: explorer.cutPin,
        });
        result.markers = result.markers.concat(boundary.markers);
        result.labels = result.labels.concat(boundary.labels);
        result.focus = result.focus.concat(boundary.focus);
        result.selection = result.selection.concat(boundary.focus);
      }
      result.targets = result.targets.concat(
        sinkPickTargets(circuit, {
          cycle: layer.cycle,
          budgetNs: state.clockSelection.periodNs,
          point: cellPoint,
          world,
          pinName: (pin) =>
            state.computations.pinGeometry[pin]?.[3] ?? String(pin),
        }),
      );
      arrivalCircuits.push(circuit);
      arrivalSummaries.push(scene.summary);
      continue;
    }
    const paint = circuitDisplay(layer.paint, {
      includeUnresolved: !mappedOnly(),
    });
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
          (row.kind === "unresolved" || row.directionUnknown) &&
            mode === "direction"
            ? "#788495"
            : mode === "direction"
              ? DIRECTION_SOURCE_COLOR
              : shade(row),
          0.0017,
          row.kind,
          (row.kind === "unresolved" || row.directionUnknown) &&
            mode === "direction"
            ? "#788495"
            : mode === "direction"
              ? DIRECTION_SINK_COLOR
              : shade(row),
          0.018,
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
      timingApplicable: row[applicableKey] !== false,
      timingUnknown: Boolean(
        row[
          metric === "registered_launch"
            ? "registeredPathTimingUnknown"
            : "staticPathTimingUnknown"
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
              [applicableKey]: row.timingApplicable,
              [metric === "registered_launch"
                ? "registeredPathTimingUnknown"
                : "staticPathTimingUnknown"]: row.timingUnknown,
            }),
          }))
        : marks;
    for (const row of displayed) {
      result.markers.push(row);
      result.focus.push(row.position);
    }
  }
  if (explorer.neighborhood?.region) {
    const familyCycles = explorer.neighborhood.members.flatMap(
      (row) => row.cycles,
    );
    const referenceCycle = familyCycles.reduce(
      (first, cycle) => Math.min(first, cycle),
      Infinity,
    );
    const contextCycle =
      (Number.isFinite(referenceCycle) ? referenceCycle : state.first) - 0.25;
    const context = neighborhoodScene(explorer.neighborhood, {
      cycle: contextCycle,
      point: cellPoint,
      world,
      driverPin: explorer.driverPin,
      showContext: explorer.showContext,
    });
    result.segments = result.segments.concat(context.segments);
    result.markers = result.markers.concat(context.markers);
    result.labels = result.labels.concat(context.labels);
    result.focus = result.focus.concat(context.focus);
    result.selection = result.selection.concat(context.focus);
  }
  const regional = regionalControls.scene({
    cycle: state.first + state.window + 0.3,
    point: cellPoint,
    world,
    showCells: true,
  });
  if (regional) {
    for (const key of ["surfaces", "segments", "markers", "labels", "focus"])
      result[key] = result[key].concat(regional[key]);
    result.selection = result.selection.concat(regional.selection);
  }
  const activeVersions = new Set(selectedLifetimes().map((x) => x.version));
  const storage =
    $("residence").checked && (!sinkInspector.focused || pickMode === "storage")
      ? visibleStorage()
      : [];
  let loads = 0,
    holds = 0;
  for (const item of storage) {
    // Qualified arrival-to-capture annotations replace full-clock load glyphs.
    // Qualified register captures remain boundary markers; holds retain sampled evidence.
    if (arrival && item.kind === "write") continue;
    item.kind === "write" ? loads++ : holds++;
    for (const p of spatialPoints(storagePoints(item), mappedOnly())) {
      const active =
        activeVersions.has(item.version) || item.resource === state.resource;
      const a = world(p, item.visibleFromCycle),
        b = world(p, item.visibleToCycle);
      const color =
        mode === "direction"
          ? DIRECTION_SOURCE_COLOR
          : neutralTiming
            ? active
              ? "#60737e"
              : "#3e515c"
            : membershipMode
              ? computationColor(item.resource)
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
        neutralTiming
          ? active
            ? 0.001
            : 0.0006
          : active
            ? 0.004
            : item.kind === "write"
              ? 0.0028
              : 0.0018,
        "storage",
        endColor,
      );
      if (item.kind === "write" && !item.afterWindow)
        marker(
          b,
          active ? "#f3f5ed" : endColor,
          active ? 0.012 : 0.007,
          active ? 3 : 1,
        );
      result.targets.push({
        kind: "storage",
        id: JSON.stringify([
          item.version,
          p.cell ?? p.kind,
          item.visibleFromCycle,
          item.visibleToCycle,
        ]),
        from: a,
        to: b,
        segment: item,
        point: p,
      });
      result.focus.push(a, b);
      if (active) result.selection.push(a, b);
    }
  }
  $("storage-summary").textContent =
    `${$("full-storage").checked ? "Full storage history" : "Recorded uses only"} · ${loads} loads · ${holds} residence spans · ${result.targets.filter((row) => row.kind === "storage").length.toLocaleString()} spatial links. ${arrival ? "Arrival view shows readiness separately; residence spans retain sampled values." : "Thick links load a value; thin links retain it."}`;
  const seeds = new Set(selectionEvents().map((e) => e.id));
  const pathIds = new Set(state.trace?.events.map((e) => e.id) ?? []);
  const expanded = $("access-footprints").checked && state.model.catalogue;
  let glyphs = 0;
  const eventOmissions = { events: 0, dependencies: 0, staticPath: false };
  for (const event of sinkInspector.focused &&
  !["reads", "writes"].includes(pickMode)
    ? []
    : visibleEvents()) {
    const coordinate = arrival
      ? arrivalEventAnchor(state.model, event).coordinate
      : event.cycle;
    if (coordinate === null) {
      eventOmissions.events++;
      continue;
    }
    const geometry = expanded || mappedOnly() ? accessGeometry(event) : null;
    if (mappedOnly() && !geometry.points.some((p) => p.physical)) continue;
    for (const point of spatialPoints(
      expanded ? geometry.points : [eventPoint(event)],
      mappedOnly(),
    )) {
      const position = world(point, coordinate),
        active = seeds.has(event.id),
        onPath = pathIds.has(event.id);
      const resources = resourcesForEvent(event);
      const accessColor = neutralTiming
        ? "#627780"
        : membershipMode
          ? resources.length === 1
            ? computationColor(resources[0])
            : resources.length > 1
              ? COMPUTATION_SHARED_COLOR
              : "#627780"
          : mode === "direction"
            ? "#627780"
            : color(event);
      const highlight = active && (!state.chain || state.selected === event.id);
      marker(
        position,
        highlight
          ? "#f3f5ed"
          : neutralTiming
            ? "#627780"
            : onPath
              ? "#d3dcda"
              : dim
                ? "#536b77"
                : accessColor,
        highlight ? 0.014 : neutralTiming ? 0.004 : onPath ? 0.009 : 0.004,
        highlight ? 3 : neutralTiming ? 0 : onPath ? 2 : 1,
      );
      result.targets.push({ kind: "event", id: event.id, position, event });
      result.focus.push(position);
      if (active) result.selection.push(position);
      glyphs++;
    }
  }
  let traces = 0;
  for (const edge of sinkInspector.focused ? [] : (state.trace?.edges ?? [])) {
    const from = state.model.events.get(edge.source),
      to = state.model.events.get(edge.target);
    if (from.cycle >= state.first + state.window || to.cycle < state.first)
      continue;
    const coordinates = arrival
      ? arrivalEventConnection(state.model, from, to)
      : { from: from.cycle, to: to.cycle };
    if (!coordinates) {
      eventOmissions.dependencies++;
      continue;
    }
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
        world(source, Math.max(state.first, coordinates.from)),
        world(
          target,
          Math.min(
            state.first + state.window - (arrival ? 0 : 1),
            coordinates.to,
          ),
        ),
        mode === "direction"
          ? DIRECTION_SOURCE_COLOR
          : neutralTiming
            ? "#536975"
            : "#d8dedc",
        neutralTiming ? 0.00065 : 0.003,
        "dependency",
        mode === "direction"
          ? DIRECTION_SINK_COLOR
          : neutralTiming
            ? "#536975"
            : "#d8dedc",
        0.018,
      );
      result.focus.push(
        world(source, Math.max(state.first, coordinates.from)),
        world(
          target,
          Math.min(
            state.first + state.window - (arrival ? 0 : 1),
            coordinates.to,
          ),
        ),
      );
      traces++;
    }
  }
  eventOmissions.staticPath = Boolean(
    arrival && state.nativePath && !sinkInspector.focused,
  );
  if (state.nativePath && !sinkInspector.focused && !arrival) {
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
          segment(
            positions[j - 1],
            positions[j],
            "#ee91d5",
            0.004,
            "static",
            "#ee91d5",
            0.018,
          );
          result.focus.push(positions[j - 1], positions[j]);
        }
    }
  }
  renderArrivalDetails(
    arrivalCircuits,
    maximum,
    arrivalSummaries,
    eventOmissions,
  );
  $("access-summary").textContent =
    `${glyphs.toLocaleString()} access positions · ${traces} selected dependency links · ${detail === "overview" ? (arrival ? "native pin arrival markers" : "occupied-bin overview (aggregated, not native geometry)") : detail === "routes" ? "schematic routing links and cells; switch markers hidden" : "schematic links, cells, switches and wire tiles"}${mappedOnly() ? " · unmapped geometry hidden; evidence retained" : ""}`;
  if (
    state.computations &&
    $("computation-circuits").checked &&
    selectionEvents().length &&
    !sinkInspector.focused
  ) {
    const selectedLayers = state.chain
      ? circuitLayers()
      : (state.computations.prepared
          ? preparedComputationLayers
          : computationLayers)(
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
      if (arrival) {
        const scene = arrivalScene(
          arrivalCircuit(state.computations, layer, {
            scope: metric === "registered_launch" ? "registered" : "static",
            includeUnresolved: !mappedOnly(),
            bridgeKnownGeometry: true,
          }),
          {
            cycle: layer.cycle,
            budgetNs: state.clockSelection.periodNs,
            captureAvailable: captureAvailable(layer.cycle),
            point: cellPoint,
            world,
            shade,
            mode,
            detail,
          },
        );
        result.selection = result.selection.concat(scene.focus);
        continue;
      }
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
  $("fit-selection").disabled = sinkInspector.focused
    ? result.selection.length === 0
    : !selectionEvents().length && !state.resource && !state.focusVersion;
  result.bounds = sceneBounds(result.focus);
  result.selectionBounds = sceneBounds(
    result.selection.length ? result.selection : result.focus,
  );
  return overlayDisplay(result);
}

/** Paint opaque depth-tested geometry, with sparse labels on the interaction
 * overlay. Projected hit candidates keep their depth and reject clipped points. */
function drawStack() {
  const { w, h } = canvasContext("stack");
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
  sceneSelection.project(state.sceneContent.targets, state.scene, {
    sinkKey: sinkInspector.key,
    eventId: state.selected?.id,
  });
  drawStackOverlay();
}
/** Hover changes only the annotation canvas; GPU geometry and graph caches stay intact. */
function drawStackOverlay() {
  const { ctx, w, h } = canvasContext("stack");
  if (!state.scene || !state.sceneContent) return;
  const project = (point) => state.scene.project(point);
  const labels = canvasLabels(ctx, w, h);
  for (const { label, point } of projectLabelAnchors(
    state.sceneContent.labels,
    project,
  )) {
    ctx.font = `${label.minor ? 10 : 11}px ui-monospace,monospace`;
    ctx.fillStyle = label.minor ? "#7d949f" : "#a5bdc8";
    labels.add(
      label.text,
      Math.max(4, point.x - 44),
      point.y - 6,
      label.minor ? 90 : 100,
      label.key ?? label.text,
    );
  }
  labels.draw();
  sceneSelection.draw(ctx);
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
function selectEvent(id, move = true, keepChain = false) {
  if (!state.model?.events.has(id)) return;
  if (keepChain) {
    $("sink-mode").value = "all";
    $("sink-mode").onchange();
  }
  if (!keepChain) {
    state.chain = null;
    $("chain").value = "";
  }
  state.selected = id;
  state.annotation = null;
  if (!keepChain) state.trace = null;
  state.cell = null;
  state.focusVersion = null;
  const event = state.model.events.get(id);
  state.resource =
    event.access?.resource ?? resourcesForEvent(event)[0] ?? null;
  $("resource").value = state.resource ?? "";
  if (
    move &&
    (event.cycle < state.first || event.cycle >= state.first + state.window)
  ) {
    state.first = event.cycle - Math.floor(state.window / 2);
    state.autoFit = true;
  }
  render();
}
/** Select a stored version, including roots with no fabricated producer event. */
function selectStorage(version, cell = null) {
  state.chain = null;
  $("chain").value = "";
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
/** Navigate an explicit step boundary or trace only its retained event anchors.
 * A public boundary later than those events remains separate metadata; it never
 * becomes a new graph event or gains ancestry from chronological proximity.
 */
function focusStepBoundary(boundary, trace) {
  state.timeOriginCycle = state.model.stepComparison.start.cycle;
  const events = boundary.eventIds.map((id) => state.model.events.get(id));
  if (events.some((event) => !event)) return;
  for (const key of ["actor", "activation", "operation", "task"])
    $(key).value = "";
  state.chain = null;
  state.selected = null;
  state.trace = null;
  state.resource = null;
  state.cell = null;
  state.focusVersion = null;
  $("chain").value = "";
  $("resource").value = "";
  $("sink-mode").value = "all";
  state.annotation = {
    label: boundary.label,
    cycle: events.length
      ? Math.max(...events.map((event) => event.cycle))
      : boundary.cycle,
    publicBoundaryCycle: boundary.cycle,
    ...(events.length
      ? {
          graph_events: boundary.eventIds,
          graph_incarnation: events[0].incarnation,
          dependency_endpoint: true,
        }
      : { dependency_endpoint: false }),
  };
  if (trace && events.length) traceSelection("backward");
  state.first = boundary.cycle - Math.floor(state.window / 2);
  state.autoFit = true;
  render();
  if (!events.length)
    notice(
      `${boundary.label}: this boundary has no recorded event anchors; no ancestry was inferred.`,
    );
}

/** Inspect the prepared sink whose exact pin identity matches the global STA
 * endpoint. Its recorded write association locates the view, not STA activity;
 * the displayed SDF maximizing chain need not be the original STA path.
 */
function inspectClockPath(row) {
  const step = state.model.stepComparison;
  const match = clockSink(state.computations, row.endpoint, {
    firstCycle: step?.start.cycle,
    endCycle: step?.end.cycle,
  });
  if (match.status !== "available") {
    notice(
      `${match.reason} The global STA report summary remains available.`,
      true,
    );
    return;
  }
  for (const key of ["actor", "activation", "operation", "task"])
    $(key).value = "";
  state.chain = null;
  state.annotation = null;
  state.trace = null;
  state.selected = match.event.id;
  state.resource = match.event.access.resource;
  state.cell = null;
  state.focusVersion = null;
  state.timeOriginCycle = step?.start.cycle ?? selectedBounds().firstCycle;
  $("chain").value = "";
  $("resource").value = state.resource;
  $("time-layout").value = "arrival";
  $("computation-circuits").checked = true;
  $("circuit-role").value = "";
  $("circuit-delay").value = "0";
  $("circuit-unknown").checked = true;
  $("circuit-selected").checked = false;
  $("sink-mode").value = "selected";
  state.first = match.event.cycle - 1;
  state.window = 3;
  normalizeWindow();
  sinkInspector.update(state.computations, circuitLayers(), {
    enabled: true,
    scope:
      $("circuit-timing").value === "registered_launch"
        ? "registered"
        : "static",
  });
  if (!sinkInspector.choose(match.key)) {
    notice(
      "The exact limiting sink is associated with a write but unavailable in the current circuit view.",
      true,
    );
    return;
  }
  $("sink-panel").open = true;
  state.autoFit = true;
  render();
  notice(
    `Showing a ${state.model.document.openxc7Timing || state.model.document.openxc7Computations ? "nextpnr" : "SDF"} maximizing path to the exact STA-limiting sink at its recorded write C${match.event.cycle}${match.withinStep ? " inside this step" : " outside this step"}. This chain may differ from the native STA path; its activity in this step is not established.`,
  );
}

/** Follow explicitly bound contributors while leaving unanchored observations as context. */
function selectAnnotation(annotation) {
  state.chain = null;
  $("chain").value = "";
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
  state.autoFit = true;
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
  if (state.chain && !state.selected) {
    $("selected-kind").textContent = "Recorded action chain";
    $("selection").innerHTML =
      `<h3>${esc(state.chain.title)}</h3><p>${esc(state.chain.evidence ?? "Producer-selected action; every connection comes from the recorded graph.")}</p><p>Semantic comparison key: ${esc(state.chain.comparisonKey)}</p>`;
    $("neighbors").innerHTML = state.trace.boundaryInputs
      .map(
        (edge) =>
          `<button data-event="${esc(edge.source)}">Outside input · ${esc(edge.kind)} · ${esc(edge.source)}</button>`,
      )
      .join("");
    renderTraceSummary();
    return;
  }
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
    `${state.chain ? "Action corridor" : state.traceDirection === "backward" ? "Inputs" : "Consumers"}: ${state.trace.events.length} recorded operations · ${state.trace.edges.length} dependencies · ${roots.length} root versions` +
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
  $("expand-storage").disabled =
    (!state.resource && !state.chain) || !state.model.catalogue;
  $("flat-subtitle").textContent = cells.length
    ? `${cells.length} associated native storage cells highlighted`
    : "Unique installed cells, counted once";
  $("cell-count").textContent = `(${cells.length})`;
  $("cells").innerHTML =
    cells
      .slice(0, 600)
      .map(
        (c) =>
          `<div class="cell-row" role="button" tabindex="0" data-cell="${esc(c.id)}">${esc(c.id)}<span>${esc(c.kind)} · ${esc(c.site ?? c.tile)} / ${esc(c.bel)} · tile (${c.x}, ${c.y})</span></div>`,
      )
      .join("") +
    (cells.length > 600
      ? "<p>First 600 cells listed; all are drawn on the flat chip.</p>"
      : "");
}
/** Select a finite semantic action using only existing graph paths. */
function chooseChain(id) {
  const chain = state.model.chains.get(id);
  state.chain = chain ?? null;
  state.chainMatchNote = null;
  if (chain)
    state.displayBounds = chain.spatialBounds
      ? { ...chain.spatialBounds }
      : null;
  state.model.geometryBounds = chainDisplayBounds(
    chain,
    state.nativeBounds,
    state.displayBounds,
  );
  for (const key of [
    "pointCache",
    "resourceCache",
    "footprintCache",
    "storagePointCache",
    "circuitPaintCache",
  ])
    state[key].clear();
  state.circuitCache = null;
  state.selected = null;
  state.annotation = null;
  state.focusVersion = null;
  state.resource = null;
  state.cell = null;
  $("resource").value = "";
  $("example").value = "";
  if (!chain) {
    state.trace = null;
    render();
    return;
  }
  for (const filter of ["actor", "activation", "operation", "task"])
    $(filter).value = "";
  state.trace = traceChain(state.model, chain);
  state.first = chain.firstCycle;
  state.timeOriginCycle = chain.firstCycle;
  state.window = chain.endCycle - chain.firstCycle;
  $("chain").value = id;
  $("circuit-selected").checked = false;
  $("sink-mode").value = "all";
  $("ghost-context").checked = true;
  state.autoFit = true;
  render();
}

/** Milestones are navigation labels, not added computation or dependency nodes. */
function renderChain() {
  const chain = state.chain;
  $("chain-panel").hidden =
    state.model.chains.size === 0 && !state.chainMatchNote;
  $("chain-only").disabled = !chain;
  $("chain-context").disabled = !chain;
  $("chain-summary").textContent = chain
    ? `${state.trace.connected ? "Recorded source-to-sink paths" : "Unresolved connection: isolated anchors retained"} · ${state.trace.events.length} operations · ${state.trace.focusVersions.length} focused stored versions · ${state.trace.boundaryInputs.length} outside inputs.${chain.targets?.length && $("chain-only").checked && !$("chain-context").checked ? " Primary destination circuitry; other recorded/control circuitry hidden (enable Adjacent input context to show it)." : ""} Destination bit masks limit the display, not the recorded writes. Physical cones show structural alternatives, not gate activity.`
    : (state.chainMatchNote ??
      "Choose a recorded action to follow its value through clock boundaries.");
  if (chain && $("chain-only").checked) {
    const residence = chainStorageSegments(
      state.model,
      chain,
      state.trace,
      [],
      {
        includeContext: $("chain-context").checked,
      },
    );
    $("chain-summary").textContent +=
      ` Residence stops at this action's recorded uses of the displayed fields; global history stays in the inspector.${residence.unresolved.length ? ` ${residence.unresolved.length} field-use masks unresolved; their possible uses are retained.` : ""}${residence.unusedVersions.length ? ` ${residence.unusedVersions.length} versions have no matching recorded use in this action and no residence link.` : ""}`;
  }
  $("chain-milestones").innerHTML = (chain?.milestones ?? [])
    .map((milestone) => {
      const event = state.model.events.get(milestone.event);
      const unresolved = state.trace.unresolved.milestones.some(
        (row) => row.event === event.id,
      );
      return `<button data-chain-event="${esc(event.id)}"><b>${esc(milestone.label)}</b><span>C${event.cycle}${unresolved ? " · unresolved" : ""}</span></button>`;
    })
    .join("");
}

/** Apply a fixture's inspectable entry point, never a fabricated causal chain. */
function chooseExample(index) {
  const example = state.model.document.examples?.[index];
  if (!example) return;
  state.autoFit = true;
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
/** Flat-chip hit test chooses a native cell; scene evidence uses explicit target modes. */
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

/** Local pointer coordinates independent of page scrolling. */
function pointer(event) {
  const r = event.currentTarget.getBoundingClientRect();
  return { x: event.clientX - r.left, y: event.clientY - r.top };
}
/** Prevent controls for the old capture from acting while replacement data loads. */
function setBusy(busy) {
  for (const id of [
    "example",
    "chain",
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
    "clock-source",
    "arrival-budget",
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
    sceneSelection.reset();
    const captureComparisonView = () => {
      const comparison = state.chain ?? state.model?.stepComparison;
      if (!comparison?.comparisonKey) return null;
      const origin = state.chain
        ? state.chain.firstCycle
        : comparison.start.cycle;
      return {
        kind: state.chain ? "chain" : "step",
        key: comparison.comparisonKey,
        offset: state.first - origin,
        originOffset: clockOriginCycle() - origin,
        window: state.window,
        manualPeriodNs: state.manualPeriodNs,
        camera: state.scene?.getCamera(),
        controls: Object.fromEntries(
          [
            "clock-source",
            "time-layout",
            "color-mode",
            "urgency-window",
            "spacing",
            "detail-level",
            "pick-mode",
            "computation-circuits",
            "circuit-role",
            "circuit-timing",
            "circuit-delay",
            "circuit-unknown",
            "circuit-selected",
            "ghost-context",
          ].map((id) => [
            id,
            {
              value: $(id).value,
              checked: $(id).type === "checkbox" ? $(id).checked : undefined,
            },
          ]),
        ),
      };
    };
    const previousView = captureComparisonView();
    const restoreComparisonView = (snapshot = previousView) => {
      const comparison =
        snapshot?.kind === "chain" ? state.chain : state.model.stepComparison;
      if (!snapshot || !comparison || comparison.comparisonKey !== snapshot.key)
        return;
      const origin =
        snapshot.kind === "chain"
          ? comparison.firstCycle
          : comparison.start.cycle;
      state.first = origin + snapshot.offset;
      state.timeOriginCycle = origin + snapshot.originOffset;
      state.window = snapshot.window;
      state.manualPeriodNs = snapshot.manualPeriodNs;
      for (const [id, control] of Object.entries(snapshot.controls)) {
        $(id).value = control.value;
        if (typeof control.checked === "boolean")
          $(id).checked = control.checked;
      }
      if (!state.expectsPrepared && !state.computations?.prepared)
        $("time-layout").value = "flat";
      state.spacing = Number($("spacing").value);
      syncClockControls();
      if (snapshot.camera) state.scene?.setCamera(snapshot.camera);
      state.autoFit = !snapshot.camera;
      render();
    };
    const sequence = ++state.loadSequence;
    stepComparison.reset();
    regionalControls.configure();
    scenarioControls.configure();
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
      const stepEvidence = await loadStepEvidence({
        entry: expected.stepEvidence,
        recording: { bytes: byteLength, sha256: digest },
        baseUrl: new URL("data/", window.location.href).href,
        signal,
      });
      if (sequence !== state.loadSequence) return;
      if (stepEvidence) installStepEvidence(decoded.model, stepEvidence);
      await loadDocument(
        decoded.model,
        "Projection bytes verified against the local index; source evidence was verified during preparation.",
        null,
        {
          preparedExpected: Boolean(expected.render),
          computationsExpected: Boolean(expected.computations),
        },
      );
      scenarioControls.configure(state.model, {
        entry: expected.latencyProfile,
        recording: { bytes: byteLength, sha256: digest },
        baseUrl: new URL("data/", window.location.href).href,
      });
      regionalControls.configure(state.model, {
        entry: expected.regions,
        view: { bytes: byteLength, sha256: digest },
        source: expected.computations,
        baseUrl: new URL("data/", window.location.href).href,
      });
      const matched =
        previousView?.kind === "chain"
          ? matchingChain(state.model, previousView.key)
          : previousView?.key === state.model.stepComparison?.comparisonKey
            ? state.model.stepComparison
            : null;
      const initial = previousView
        ? previousView.kind === "chain"
          ? matched
          : null
        : state.model.chains.values().next().value;
      state.chainMatchNote =
        previousView && !matched
          ? `No matching ${previousView.kind} for ${previousView.key} in this capture. Select another explicitly; no comparison was inferred.`
          : null;
      if (initial) {
        chooseChain(initial.id);
        restoreComparisonView();
      } else if (matched) {
        restoreComparisonView();
      } else if (!previousView && state.model.document.examples?.length) {
        $("example").value = "0";
        chooseExample(0);
      } else {
        render();
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
    sceneSelection.reset();
    const sequence = ++state.loadSequence;
    stepComparison.reset();
    regionalControls.configure();
    scenarioControls.configure();
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
    state.autoFit = true;
    render();
  };
  $("window").onchange = () => {
    state.window = Number($("window").value);
    state.autoFit = true;
    render();
  };
  $("position").oninput = () => {
    state.first = Number($("position").value);
    state.autoFit = true;
    render();
  };
  $("spacing").oninput = () => {
    state.spacing = Number($("spacing").value);
    repaint();
  };
  $("spatial-density").onchange = () => repaint();
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
    state.autoFit = true;
    render();
  };
  $("next").onclick = () => {
    state.first += state.window;
    state.autoFit = true;
    render();
  };
  $("step").onclick = () => {
    if (!state.model) return;
    const b = selectedBounds();
    state.first = b.firstCycle;
    state.window = b.endCycle - b.firstCycle;
    state.autoFit = true;
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
    state.autoFit = true;
    render();
  };
  $("example").onchange = () => {
    if ($("example").value !== "") chooseExample(Number($("example").value));
  };
  $("chain").onchange = () => chooseChain($("chain").value);
  $("chain-only").onchange = render;
  $("chain-context").onchange = render;
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
    state.chain = null;
    $("chain").value = "";
    state.trace = null;
    render();
  };
  document.addEventListener("click", (e) => {
    const milestone = e.target.closest("[data-chain-event]");
    if (milestone) selectEvent(milestone.dataset.chainEvent, true, true);
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
  $("pick-all").onchange = () => drawStackOverlay();
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
      sceneSelection.hover(p);
    }
  };
  stack.onpointerup = (e) => {
    const p = pointer(e);
    if (drag && !drag.moved && !drag.pan && e.button === 0) {
      sceneSelection.click(p);
    }
    drag = null;
  };
  stack.onwheel = (e) => {
    e.preventDefault();
    state.scene?.zoom(Math.exp(-e.deltaY * 0.0015));
    repaint(true);
  };
  stack.oncontextmenu = (e) => e.preventDefault();
  stack.onpointercancel = () => {
    drag = null;
    sceneSelection.clear();
    drawStackOverlay();
  };
  stack.onpointerleave = () => {
    sceneSelection.leave();
  };
  stack.onkeydown = (e) => {
    if (e.key === "Escape") {
      sceneSelection.clear();
      drawStackOverlay();
    } else if (
      ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)
    ) {
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
        `${hit.cell.kind} · ${hit.cell.id} · ${hit.cell.site ?? hit.cell.tile}/${hit.cell.bel}`,
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
    state.autoFit = true;
    render();
  };
  $("toggle-inspector").onclick = () => {
    const open = $("evidence-inspector").hidden;
    $("evidence-inspector").hidden = !open;
    $("explorer").classList.toggle("inspector-open", open);
    $("toggle-inspector").setAttribute("aria-expanded", String(open));
    repaint();
  };
  $("toggle-scene-controls").onclick = () => {
    const hidden = $("scene-panel").classList.toggle("scene-controls-hidden");
    $("toggle-scene-controls").textContent = hidden
      ? "Show controls"
      : "Hide controls";
    $("toggle-scene-controls").setAttribute("aria-expanded", String(!hidden));
    repaint(true);
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
  for (const id of [
    "pick-mode",
    "color-mode",
    "detail-level",
    "ghost-context",
    "time-layout",
    "urgency-window",
  ])
    $(id).onchange = () => {
      for (const control of ["arrival-budget", "urgency-window"])
        if (!$(control).checkValidity()) {
          $(control).reportValidity();
          return;
        }
      if (id === "time-layout") state.autoFit = true;
      if (id === "time-layout" && arrivalEnabled())
        $("pick-mode").value = "sinks";
      repaint();
    };
  $("clock-source").onchange = () => {
    state.autoFit = false;
    syncClockControls();
    render();
  };
  $("arrival-budget").onchange = () => {
    const input = $("arrival-budget");
    if (!input.checkValidity()) {
      input.reportValidity();
      return;
    }
    const periodNs = Number(input.value);
    const clocks = state.model
      ? state.model.bundle.capture.end_cycle -
        state.model.bundle.capture.first_cycle
      : 1;
    if (periodNs * clocks > Number.MAX_SAFE_INTEGER) {
      notice(
        "The manual period exceeds the viewer's numeric range for this capture.",
        true,
      );
      syncClockControls();
      return;
    }
    state.manualPeriodNs = periodNs;
    state.autoFit = false;
    $("clock-source").value = "manual";
    syncClockControls();
    render();
  };
  const resize = new ResizeObserver(() => repaint());
  resize.observe(document.querySelector(".workspace"));
  resize.observe($("scene-frame"));
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
      const url = publicationUrl(
        path,
        new URL("data/", window.location.href).href,
      );
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
