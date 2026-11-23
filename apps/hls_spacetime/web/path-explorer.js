/** Controls for saved-evidence neighborhood and hypothetical register-cut views.
 * Analysis is rebuilt on explicit inputs; camera movement reuses the result. */
import { pathNeighborhood } from "./path-neighborhood.js";
import { candidateCut } from "./candidate-cut.js";
import { sinkSelections } from "./sink-view.js";
const $ = (id) => document.getElementById(id),
  PAGE = 12;
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const ns = (value) =>
  typeof value === "number" ? value.toFixed(3) : "unknown";
const short = (value) => value.split("/").slice(-2).join("/");
export const CUT_COLORS = {
  before: "#e6ac62",
  after: "#72b1e8",
  crossing: "#f3dc88",
  mixed: "#91a2a9",
};

/** Read only valid numeric controls; invalid edits never replace the last model. */
function numberChange(id, accept) {
  $(id).onchange = () => {
    if (!$(id).checkValidity() || $(id).value === "")
      return $(id).reportValidity();
    accept(Number($(id).value));
  };
}

/** Owns analysis-only controls and exposes immutable results to the scene.
 * Changing the selected sink or its scope resets a proposed cut to half its bound. */
export function createPathExplorer(onChange, chooseSink) {
  let neighborhood = null,
    cut = null,
    driverPin = null,
    cutPin = null,
    cutSelection = new Map(),
    fullGraph = false;
  let marginNs = 0.1,
    paddingTiles = 12,
    thresholdNs = null,
    showContext = true;
  let contextIndex = null,
    contextKey = null,
    mode = "all",
    page = 0,
    cutPage = 0,
    before = new Set(),
    after = new Set();
  const invalidate = () => onChange();
  numberChange("family-margin", (v) => {
    marginNs = v;
    page = 0;
    invalidate();
  });
  numberChange("family-padding", (v) => {
    paddingTiles = v;
    page = 0;
    invalidate();
  });
  numberChange("cut-time", (v) => {
    thresholdNs = v;
    cutPage = 0;
    invalidate();
  });
  $("cut-full-graph").onchange = () => {
    fullGraph = $("cut-full-graph").checked;
    invalidate();
  };
  $("cut-threshold").oninput = () => {
    thresholdNs = Number($("cut-threshold").value);
    cutPage = 0;
    invalidate();
  };
  $("family-context").onchange = () => {
    showContext = $("family-context").checked;
    invalidate();
  };
  $("family-driver").onchange = () => {
    driverPin =
      $("family-driver").value === "" ? null : Number($("family-driver").value);
    invalidate();
  };
  $("family-list").onclick = (event) => {
    const node = event.target.closest("[data-sink]");
    if (node) chooseSink(node.dataset.sink);
  };
  $("cut-list").onclick = (event) => {
    const node = event.target.closest("[data-cut-pin]");
    if (node) {
      const pin = Number(node.dataset.cutPin);
      cutPin = pin === cutPin ? null : pin;
      invalidate();
    }
  };
  for (const [id, change] of [
    ["family-prev", () => page--],
    ["family-next", () => page++],
    ["cut-prev", () => cutPage--],
    ["cut-next", () => cutPage++],
  ])
    $(id).onclick = () => {
      change();
      invalidate();
    };
  function familyDetails() {
    const members = neighborhood?.members ?? [],
      counts = neighborhood?.summary ?? {};
    page = Math.max(
      0,
      Math.min(page, Math.max(0, Math.ceil(members.length / PAGE) - 1)),
    );
    const cells = neighborhood?.cells ?? [];
    $("family-summary").textContent = neighborhood?.region
      ? `${members.length} similar timed sinks with placed endpoints in the selected path’s bounding box + ${paddingTiles} tiles; ±${marginNs} ns from the selected sink. ${cells.filter((c) => c.kind === "family").length} path cells and ${cells.filter((c) => c.kind === "context").length} other installed cells in that region. Context is placement, not observed activity or congestion.`
      : "A known selected path with located native endpoints is needed to define a neighborhood.";
    $("family-coverage").textContent =
      `${counts.visibleSinks ?? 0} visible sinks: ${counts.knownSinks ?? 0} known timing, ${counts.unknownSinks ?? 0} unknown, ${counts.outsideScopeSinks ?? 0} outside the launch scope. Across those groups, ${counts.unlocatedSinks ?? 0} lack coordinates. ${counts.sharedArcs ?? 0} native arcs are shared by multiple family members. One representative chain per qualifying cone/sink; tied alternatives are not exhaustively enumerated.`;
    $("family-list").innerHTML =
      `<table><thead><tr><th>Similar sink</th><th>ns</th><th>Shared arcs</th></tr></thead><tbody>${members
        .slice(page * PAGE, (page + 1) * PAGE)
        .map(
          (r) =>
            `<tr><td><button type="button" class="sink-name" data-sink="${esc(r.key)}" title="${esc(r.pinName)}">${esc(short(r.pinName))}</button></td><td>${ns(r.delayNs)}</td><td>${r.sharedArcCount}</td></tr>`,
        )
        .join("")}</tbody></table>`;
    $("family-page").textContent =
      `${members.length} sinks · page ${page + 1} / ${Math.max(1, Math.ceil(members.length / PAGE))}`;
    $("family-prev").disabled = page === 0;
    $("family-next").disabled = (page + 1) * PAGE >= members.length;
    const drivers = neighborhood?.fanouts ?? [];
    if (!drivers.some((r) => r.pin === driverPin)) driverPin = null;
    $("family-driver").innerHTML =
      `<option value="">No fanout overlay</option>${drivers.map((r) => `<option value="${r.pin}">${esc(short(r.name))} · ${r.totalSinkPins} sinks</option>`).join("")}`;
    $("family-driver").value = driverPin === null ? "" : String(driverPin);
    const driver = drivers.find((r) => r.pin === driverPin);
    $("family-driver-summary").textContent = driver
      ? `${driver.name}: ${driver.totalSinkPins} represented sink pins, ${driver.familySinkPins} on family paths; ${driver.sinks.filter((r) => r.point && !r.insideRegion).length} outside the region, ${driver.sinks.filter((r) => !r.point).length} unlocated. Spokes join native pin locations; they are not routed wire geometry or activity.`
      : "Choose a driver to see every represented consumer, including those outside this region and outside the displayed paths.";
  }
  function cutDetails() {
    const known = cut?.status === "known",
      crossings = cut?.crossings ?? [];
    before = new Set(cut?.beforeArcIds ?? []);
    after = new Set(cut?.afterArcIds ?? []);
    if (!crossings.some((r) => r.fromPin === cutPin)) cutPin = null;
    $("cut-summary").textContent = known
      ? `Retained-delay estimate: stage 1 ${ns(cut.stage1DelayNs)} ns · stage 2 ${ns(cut.stage2DelayNs)} ns. ${cut.signalBits} nonconstant native bits require storage at the proposed boundary (${crossings.length} crossing signals). Whole combinational cells stay together; the second stage is recomputed across the complete eligible fan-in.`
      : `Cut estimate unavailable: ${cut?.reason ?? cut?.reasons?.join(", ") ?? "select a known sink"}.`;
    $("cut-limits").textContent =
      "This is a hypothetical cut in the selected sink’s input graph, not a design change. Bit count is a register lower bound; actor context, valid/reset, other outputs and control are excluded. Delays reuse current routing and exclude new register/clock overhead. Actor reissue interval and achieved clock period are unknown.";
    const sideInputs = cut?.sideInputs ?? [];
    $("cut-side-inputs").textContent = known
      ? `${cut.alignmentSourceBits} direct-source bypass bits need alignment storage. Every eligible launch-to-sink path crosses once. ${sideInputs.filter((r) => r.kind === "external").length} external and ${sideInputs.filter((r) => r.kind === "constant").length} constant side inputs lie outside this timing scope; ${sideInputs.filter((r) => r.alignmentRequired).length} external inputs feeding stage 2 still need alignment. The surrounding actor protocol is not qualified.`
      : "Unknown timing or unsupported graph structure prevents a complete numeric estimate.";
    const a = known ? cut.stage1DelayNs : 0,
      b = known ? cut.stage2DelayNs : 0,
      max = Math.max(a, b, 0.001);
    $("cut-bars").innerHTML = known
      ? `<div><span>Stage 1</span><i style="width:${(80 * a) / max}%;background:${CUT_COLORS.before}"></i><b>${ns(a)} ns</b></div><div><span>Stage 2</span><i style="width:${(80 * b) / max}%;background:${CUT_COLORS.after}"></i><b>${ns(b)} ns</b></div>`
      : "";
    cutPage = Math.max(
      0,
      Math.min(cutPage, Math.max(0, Math.ceil(crossings.length / PAGE) - 1)),
    );
    $("cut-list").innerHTML =
      `<table><thead><tr><th>Crossing bit driver</th><th>Loads across cut</th></tr></thead><tbody>${crossings
        .slice(cutPage * PAGE, (cutPage + 1) * PAGE)
        .map(
          (r) =>
            `<tr><td><button type="button" class="sink-name" data-cut-pin="${r.fromPin}" aria-pressed="${cutPin === r.fromPin}" title="${esc(r.name)}">${esc(short(r.name))}${r.requiresRegister === false ? " · constant" : r.alignmentSource ? " · bypass" : ""}</button></td><td>${r.toPins.length}</td></tr>`,
        )
        .join("")}</tbody></table>`;
    $("cut-page").textContent =
      `${crossings.length} crossing signals · page ${cutPage + 1} / ${Math.max(1, Math.ceil(crossings.length / PAGE))}`;
    $("cut-prev").disabled = cutPage === 0;
    $("cut-next").disabled = (cutPage + 1) * PAGE >= crossings.length;
  }
  return {
    update(index, layers, sink, { scope, mode: nextMode, enabled = true }) {
      mode = enabled ? nextMode : "all";
      $("path-neighborhood").hidden = mode !== "neighborhood";
      $("path-cut").hidden = mode !== "cut";
      const key = `${scope}/${sink?.key ?? "none"}`;
      if (index !== contextIndex || key !== contextKey) {
        contextIndex = index;
        contextKey = key;
        thresholdNs = null;
        cutPin = null;
        driverPin = null;
        page = 0;
        cutPage = 0;
      }
      neighborhood =
        mode === "neighborhood"
          ? pathNeighborhood(index, layers, sink, {
              scope,
              marginNs,
              paddingTiles,
            })
          : null;
      const maximum = sink?.status === "known" ? sink.delayNs : 0;
      const threshold = Math.min(thresholdNs ?? maximum / 2, maximum);
      $("cut-threshold").max = String(maximum);
      $("cut-time").max = String(maximum);
      $("cut-threshold").value = String(threshold);
      $("cut-time").value = String(Number(threshold.toFixed(6)));
      $("cut-threshold").disabled = $("cut-time").disabled = !maximum;
      cut =
        mode === "cut" && sink
          ? candidateCut(index, layers, sink, { scope, thresholdNs: threshold })
          : null;
      cutSelection =
        mode === "cut" && sink
          ? fullGraph
            ? cut.selection
            : sinkSelections(index, layers, { scope, mode: "selected", sink })
          : new Map();
      if (mode === "neighborhood") familyDetails();
      if (mode === "cut") cutDetails();
    },
    shade(row, fallback) {
      if (mode !== "cut" || cut?.status !== "known") return fallback;
      const early = row.arcIds?.some((a) => before.has(a)),
        late = row.arcIds?.some((a) => after.has(a));
      return early && late
        ? CUT_COLORS.mixed
        : early
          ? CUT_COLORS.before
          : late
            ? CUT_COLORS.after
            : fallback;
    },
    get selection() {
      return mode === "neighborhood"
        ? (neighborhood?.selection ?? new Map())
        : mode === "cut"
          ? cutSelection
          : null;
    },
    get neighborhood() {
      return neighborhood;
    },
    get cut() {
      return cut;
    },
    get driverPin() {
      return driverPin;
    },
    get cutPin() {
      return cutPin;
    },
    get showContext() {
      return showContext;
    },
    get mode() {
      return mode;
    },
  };
}
