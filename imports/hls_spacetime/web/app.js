/** Local rendering of saved cycle evidence. All ancestry comes from model.js;
 * screen positions and same-clock annotations never create graph edges. */
import {
  createModel,
  eventsInWindow,
  traceDependencies,
  eventPlacement,
  resourcePlacement,
  resourcesForEvent,
  eventDetails,
  storageSegments,
  storageLifetimes,
} from "./model.js";
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
  storagePointCache: new Map(),
  pointCache: new Map(),
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
) {
  if (text.length > 128 * 1024 * 1024)
    throw Error("Viewer projection exceeds the 128 MiB limit");
  const model = createModel(JSON.parse(text));
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
  state.storagePointCache.clear();
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
    `<p><b>${esc(model.bundle.evidence)}</b> · ${model.bundle.capture.complete ? "complete within declared observer scope" : "incomplete capture"}</p><p>${esc(integrity)}</p><p>Connections are schematic; this view reports clocks only.</p><details><summary>Reported evidence scope</summary>${(model.document.scope ?? []).map((value) => `<p>${esc(value)}</p>`).join("")}</details><details><summary>Observer coverage</summary>${model.bundle.capture.observers.map((observer) => `<p>${esc(observer.id)}: ${esc(observer.scope)}</p>`).join("")}</details>`;
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
  render();
}
/** Recorded selected-step bounds; public annotations stay outside the event graph. */
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
  const b = selectedBounds();
  $("metrics").innerHTML =
    `<div><strong>${b.endCycle - b.firstCycle}</strong><span>clocks in selection</span></div><div><strong>${state.model.resources.size}</strong><span>logical resources</span></div><div><strong>${state.model.catalogue ? state.model.cells.size.toLocaleString() : "—"}</strong><span>installed primitives</span></div>`;
  const events = visibleEvents();
  $("event-count").textContent =
    `${events.length.toLocaleString()} operations · first 250 listed`;
  $("events").innerHTML =
    events
      .slice(0, 250)
      .map(
        (e) =>
          `<button class="event-row ${e.id === state.selected ? "active" : ""}" data-event="${esc(e.id)}"><span>C${e.cycle}</span><span style="color:${color(e)}">${esc(e.actor)}</span><span>${esc(e.operation)}</span><span class="id">${esc(e.id)}</span></button>`,
      )
      .join("") ||
    '<p class="empty">No operations match these filters and clocks.</p>';
  renderInspector();
  renderResource();
  repaint();
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
/** Draw one footprint outline with no cloned geometry arrays. */
function layer(ctx, project, cycle, alpha) {
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
  ctx.fillText(`C${cycle}`, a.x - 30, a.y);
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
    (state.selected ? [state.selected] : []);
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
 * from an overwritten word to the next word. Counts disclose drawing bounds. */
function drawResidence(ctx, project) {
  state.storageHits = [];
  if (!$("residence").checked) {
    $("storage-summary").textContent = "Cross-cycle storage hidden";
    return;
  }
  const segments = visibleStorage();
  const selected = new Set(selectedLifetimes().map((life) => life.version));
  // Show selected details first if the explicit graphics budget is reached.
  const emphasized = (segment) =>
    selected.has(segment.version) || segment.resource === state.resource;
  const ordered = [...segments].sort(
    (a, b) => Number(emphasized(b)) - Number(emphasized(a)),
  );
  let drawn = 0,
    omitted = 0,
    loads = 0,
    holds = 0,
    cells = new Set();
  for (const segment of ordered) {
    if (segment.kind === "write") loads++;
    else holds++;
    for (const point of storagePoints(segment)) {
      if (drawn >= 20000) {
        omitted++;
        continue;
      }
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
    `${words} words · ${loads} load bridges · ${holds} residence spans` +
    (cells.size ? ` · ${cells.size} expanded cells` : " · grouped by word") +
    (omitted
      ? ` · ${omitted} strokes omitted (20,000-stroke limit; narrow the window)`
      : "") +
    (state.window === 1
      ? " · show at least two clocks for cross-cycle links"
      : "");
}
/** Render graph edges only; off-window endpoints are clipped and labelled. */
function drawTrace(ctx, project) {
  if (!state.trace) return;
  for (const edge of state.trace.edges) {
    const from = state.model.events.get(edge.source),
      to = state.model.events.get(edge.target);
    if (from.cycle >= state.first + state.window || to.cycle < state.first)
      continue;
    const outside =
      from.cycle < state.first || to.cycle >= state.first + state.window;
    const a = project(eventPoint(from), Math.max(state.first, from.cycle)),
      b = project(
        eventPoint(to),
        Math.min(state.first + state.window - 1, to.cycle),
      );
    line(
      ctx,
      a,
      b,
      edge.kind === "resource_order" ? "#a8a0cc" : "#f7d684",
      1.5,
      outside,
    );
    if (outside) {
      ctx.font = "9px ui-monospace,monospace";
      ctx.fillStyle = "#f7d684";
      ctx.fillText(
        from.cycle < state.first ? `← C${from.cycle}` : `C${to.cycle} →`,
        a.x + 5,
        a.y - 4,
      );
    }
  }
}
/** Draw the chip stack using a bounded window and shared geometry. */
function drawStack() {
  const { ctx, w, h } = canvasContext("stack");
  if (!state.model) return;
  const project = projector(w, h),
    interval = Math.max(1, Math.ceil(state.window / 12));
  for (let c = state.first; c < state.first + state.window; c += interval)
    layer(ctx, project, c, 0.3);
  if ((state.window - 1) % interval)
    layer(ctx, project, state.first + state.window - 1, 0.3);
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
    ctx.fillText(`Reset · ${epoch.id}`, a.x + 6, a.y - 6);
  }
  installedContext(ctx, project);
  drawResidence(ctx, project);
  drawTrace(ctx, project);
  state.hits = [];
  const pathIds = new Set(state.trace?.events.map((e) => e.id) ?? []);
  for (const event of visibleEvents()) {
    const point = eventPoint(event),
      p = project(point, event.cycle),
      selected = event.id === state.selected,
      onPath = pathIds.has(event.id);
    ctx.globalAlpha =
      state.trace && !onPath
        ? 0.16
        : point.physical || !state.model.catalogue
          ? 0.8
          : 0.45;
    ctx.fillStyle = selected
      ? "#fff0ac"
      : onPath
        ? "#f7d684"
        : point.physical || !state.model.catalogue
          ? color(event)
          : "#8c99a4";
    ctx.beginPath();
    ctx.arc(p.x, p.y, selected ? 5 : onPath ? 3.5 : 2, 0, Math.PI * 2);
    ctx.fill();
    if (selected) {
      ctx.strokeStyle = "#fff5c5";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(p.x, p.y, 9, 0, Math.PI * 2);
      ctx.stroke();
    }
    state.hits.push({ ...p, event });
  }
  ctx.globalAlpha = 1;
  const p = project({ x: 1.4, y: 0 }, state.first);
  ctx.fillStyle = "#91a7b3";
  ctx.font = "10px system-ui";
  ctx.fillText(
    state.model.catalogue ? "UNMAPPED / UNKNOWN" : "LOGICAL LAYOUT",
    p.x - 50,
    p.y - 23,
  );
  if (state.annotation) {
    const cycle = state.annotation.cycle;
    if (cycle >= state.first && cycle < state.first + state.window) {
      const p = project({ x: -1.2, y: 1 }, cycle);
      ctx.fillStyle = "#f1bb6c";
      ctx.fillText(`Public completion · C${cycle}`, p.x, p.y + 16);
    }
  }
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
  const selected = state.selected ? model.events.get(state.selected) : null;
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
  state.resource = resourcesForEvent(event)[0] ?? null;
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
/** Inspect an annotation without inventing a graph node or causal endpoint. */
function selectAnnotation(annotation) {
  state.selected = null;
  state.trace = null;
  state.annotation = annotation;
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
  $("backward").disabled = !state.selected;
  $("forward").disabled = !state.selected;
  if (state.annotation) {
    $("selected-kind").textContent = "Public annotation";
    $("selection").innerHTML =
      `<h3>Completion · C${state.annotation.cycle}</h3><span class="pill unknown">Ancestry unavailable</span><p class="evidence-note">This application-level completion is not a captured graph event. No edge connects it to the operations on the same clock.</p><pre class="muted">${esc(JSON.stringify(state.annotation, null, 2))}</pre>`;
    $("neighbors").innerHTML = "";
    $("trace-summary").textContent =
      "Choose a recorded residence example to inspect supported dependencies.";
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
    `<h3>${esc(e.operation)}</h3><span class="pill">${esc(e.actor)}</span> <span class="pill unknown">${esc(d.placement.status.replaceAll("_", " "))}</span><dl><dt>Event</dt><dd>${esc(e.id)}</dd><dt>Task</dt><dd>${esc(e.task)}</dd><dt>Activation</dt><dd>${esc(e.activation)}</dd><dt>Incarnation</dt><dd>${esc(e.incarnation)}</dd><dt>Input versions</dt><dd>${d.inputs.map((v) => `${esc(v.id)} (${esc(v.origin)})`).join(", ") || "None recorded"}</dd><dt>Output versions</dt><dd>${d.outputs.map((v) => esc(v.id)).join(", ") || "None recorded"}</dd>${e.access ? `<dt>Storage</dt><dd>${esc(e.access.resource)} [${e.access.address}] · ${esc(e.access.kind)}</dd>${e.access.mask ? `<dt>Write mask</dt><dd>${esc(e.access.mask)}</dd>` : ""}` : ""}</dl><p class="evidence-note">${esc(e.evidence)}</p>${d.inputs
      .filter((v) => v.producer === "root")
      .map(
        (v) =>
          `<p class="evidence-note">${esc(v.id)}: ${esc(v.origin)} root. ${esc(v.evidence)}</p>`,
      )
      .join("")}${lifetimes
      .slice(0, 12)
      .map(
        (life) =>
          `<details open><summary>${esc(life.version)} · storage history</summary><p>${life.firstCycle < life.endCycle ? `Available C${life.firstCycle} to C${life.endCycle - 1}.` : `Availability begins at C${life.firstCycle}, beyond the captured interval.`} ${life.origin === "event" ? "Written by " + esc(life.producer) + "." : esc(life.origin) + " root."}</p><p>${life.holds.length} explicit holds; ${life.requests.length} reads. Persistence between observed operations is residence within the declared capture scope, not an attributed wait.</p>${life.pending.map((p) => `<p class="annotation">${esc(p.status)}: request ${esc(p.event)}, due C${p.dueCycle}</p>`).join("")}<p class="muted">${esc(life.continuity)}</p></details>`,
      )
      .join(
        "",
      )}${lifetimes.length > 12 ? `<p>${lifetimes.length - 12} more histories on this path; select a resource or version for detail.</p>` : ""}`;
  $("neighbors").innerHTML = neighborButtons(d);
  $("trace-summary").innerHTML = state.trace
    ? `${state.trace.events.length} connected operations · ${state.trace.roots.length} root stops${state.trace.truncated ? " · traversal capped at 1,000 operations" : ""}${state.trace.roots
        .slice(0, 8)
        .map(
          (r) =>
            `<p class="evidence-note">${esc(r.version.id)} · ${esc(r.version.origin)} root: ${esc(r.version.evidence)}</p>`,
        )
        .join("")}`
    : "Follow inputs or consumers. Chronological neighbours are not dependencies.";
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
    ? `<p>${histories.length} versions of this resource intersect the window.</p>` +
      histories
        .slice(0, 80)
        .map(
          (life) =>
            `<button data-version="${esc(life.version)}">${esc(life.version)} · C${life.firstCycle}–C${life.endCycle - 1} · ${life.writeCycle === null ? esc(life.origin) : `write C${life.writeCycle}`}</button>`,
        )
        .join("") +
      (histories.length > 80
        ? "<p>First 80 listed; narrow the clock window to inspect the rest.</p>"
        : "")
    : "Select a storage resource to inspect its versions.";
  $("expand-storage").disabled = !state.resource || !state.model.catalogue;
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
  const id =
    example.event ??
    example.eventId ??
    example.events?.at(-1) ??
    example.consumer;
  if (id && state.model.events.has(id)) {
    ["actor", "activation", "operation", "task"].forEach(
      (k) => ($(k).value = ""),
    );
    updateActivations();
    selectEvent(id);
    state.trace = traceDependencies(state.model, id, { direction: "backward" });
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
  else if (example.annotation) selectAnnotation(example.annotation);
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
    const url = $("capture").value;
    setBusy(true);
    try {
      notice("Reading saved capture…");
      const response = await fetch(url);
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
      if (sequence !== state.loadSequence) return;
      await loadDocument(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        "Projection bytes verified against local index; original evidence was verified when this projection was prepared.",
      );
    } catch (e) {
      if (sequence === state.loadSequence) notice(e.message, true);
    } finally {
      if (sequence === state.loadSequence) setBusy(false);
    }
  };
  $("file").onchange = async () => {
    const sequence = ++state.loadSequence;
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
  $("context").onchange = repaint;
  $("residence").onchange = repaint;
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
      if (!state.selected) return;
      state.trace = traceDependencies(state.model, state.selected, {
        direction,
      });
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
