/** DOM controller for a paged, complete sink population and an exact path strip.
 * Paging affects the list only; scene membership is explicit in the view mode. */
import { sinkRows } from "./sink-paths.js";
import { visibleSink, selectedSinkPath, sinkSelections } from "./sink-view.js";
import { DELAY_KIND_COLORS } from "./perceptual-color.js";
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
const short = (name) => name.split("/").slice(-2).join("/");

/** Caller rebuilds geometry only after an explicit control/arc selection.
 * Camera movement never rebuilds sink indexes or resets the inspection panel. */
export function createSinkInspector(onChange) {
  let index = null,
    layers = null,
    scope = "registered",
    rows = [],
    key = null,
    activeArc = null,
    page = 0,
    selection = null,
    dirty = true,
    path = null,
    marginNs = 0.5;
  for (const kind of ["logic", "net", "mixed"])
    for (const node of document.querySelectorAll(`.sink-${kind}`))
      node.style.background = DELAY_KIND_COLORS[kind];
  let contextChanged = false,
    enabledView = false;
  const selected = () => visibleSink(rows, key);
  const invalidate = () => {
    dirty = true;
    onChange();
  };
  const matching = () => {
    const query = $("sink-search").value.trim().toLowerCase();
    return query
      ? rows.filter((r) =>
          `${r.pinName} ${r.role} ${r.resources.join(" ")}`
            .toLowerCase()
            .includes(query),
        )
      : rows;
  };
  function renderList() {
    const matches = matching(),
      pages = Math.max(1, Math.ceil(matches.length / PAGE));
    page = Math.max(0, Math.min(page, pages - 1));
    const maximum = rows.reduce(
      (n, r) => (r.status === "known" ? Math.max(n ?? 0, r.delayNs) : n),
      null,
    );
    $("sink-page").textContent =
      `${matches.length.toLocaleString()} matching / ${rows.length.toLocaleString()} sinks · page ${page + 1} of ${pages}`;
    $("sink-prev").disabled = page === 0;
    $("sink-next").disabled = page + 1 === pages;
    $("sink-population").textContent =
      `${rows.filter((r) => r.status === "known").length.toLocaleString()} known · ${rows.filter((r) => r.status === "unknown").length.toLocaleString()} unknown · ${rows.filter((r) => r.status === "not_applicable").length.toLocaleString()} outside scope. Gaps compare with the slowest known visible sink (${ns(maximum)} ns); they are not STA slack. The list is paged, not truncated.`;
    $("sink-list").innerHTML =
      `<table><thead><tr><th>Sink pin</th><th>Role</th><th>Longest ns</th><th>Gap ns</th></tr></thead><tbody>${matches
        .slice(page * PAGE, (page + 1) * PAGE)
        .map(
          (r) =>
            `<tr class="${r.key === key ? "sink-selected" : ""}"><td><button type="button" class="sink-name" data-sink="${esc(r.key)}" title="${esc(r.pinName)}" aria-pressed="${r.key === key}">${esc(short(r.pinName))}</button></td><td>${esc(r.role)}</td><td>${r.status === "known" ? ns(r.delayNs) : r.status === "not_applicable" ? "outside scope" : "unknown"}</td><td>${r.status === "known" ? ns(maximum - r.delayNs) : "—"}</td></tr>`,
        )
        .join("")}</tbody></table>`;
  }
  function renderPath() {
    const row = selected();
    path = selectedSinkPath(index, row, { scope });
    if (activeArc !== null && !path?.arcIndices.includes(activeArc))
      activeArc = null;
    $("sink-selection").textContent = row
      ? `${row.pinName} · ${row.role} · ${row.occurrences} write associations across ${row.cycles.length} clocks`
      : contextChanged
        ? "The selected sink is outside the current filters. Choose a visible sink."
        : "Choose a sink to inspect its path.";
    $("sink-strip").replaceChildren();
    $("sink-steps").replaceChildren();
    if (!path) {
      $("sink-path-summary").textContent = row
        ? `No claimed longest path: ${row.status}. ${row.reasons.join(", ")}`
        : "";
      $("sink-arc-detail").textContent = "";
      return;
    }
    $("sink-path-summary").textContent =
      `${ns(path.delayNs)} ns = ${ns(path.logicDelayNs)} logic + ${ns(path.netDelayNs)} net delay · ${path.arcIndices.length} arcs · ${path.ties.branchingEncountered ? "one of tied maximizing chains" : "one representative maximizing chain"}. Independent SDF bounds, not observed switching or a physical period.${path.delayNs === 0 ? " Zero-delay arcs use equal strip widths." : " Strip widths show each arc’s delay; zero-delay arcs remain in the ordered list."}`;
    const step = (arc) => {
      const [from, to, type, delay] = index.arcGeometry[arc];
      return { arc, from, to, kind: type === 0 ? "net" : "logic", delay };
    };
    const steps = path.arcIndices.map(step);
    let cumulative = 0;
    const labels = new Map();
    for (const s of steps) {
      const begin = cumulative;
      cumulative += s.delay;
      labels.set(
        s.arc,
        `${s.kind} +${ns(s.delay)} ns · ${ns(begin)} → ${ns(cumulative)} ns · ${index.pinGeometry[s.from][3]} → ${index.pinGeometry[s.to][3]}`,
      );
    }
    $("sink-strip").innerHTML = steps
      .map(
        (s) =>
          `<button type="button" data-arc="${s.arc}" class="sink-strip-part ${activeArc === s.arc ? "active" : ""}" style="width:${path.delayNs > 0 ? (100 * s.delay) / path.delayNs : 100 / steps.length}%;background:${DELAY_KIND_COLORS[s.kind]}" title="${esc(labels.get(s.arc))}" aria-label="${esc(labels.get(s.arc))}" aria-pressed="${activeArc === s.arc}"></button>`,
      )
      .join("");
    $("sink-steps").innerHTML =
      `<ol>${steps.map((s) => `<li><button type="button" data-arc="${s.arc}" aria-pressed="${activeArc === s.arc}">${esc(labels.get(s.arc))}</button></li>`).join("")}</ol>`;
    $("sink-arc-detail").textContent =
      activeArc === null
        ? "Click a strip segment or an ordered arc to highlight its available 3D geometry. Net height within a connection remains interpolated; unresolved geometry may lie on the shelf."
        : labels.get(activeArc);
  }
  $("sink-list").onclick = (event) => {
    const node = event.target.closest("[data-sink]");
    if (!node) return;
    key = node.dataset.sink;
    activeArc = null;
    contextChanged = false;
    if (["all", "per-sink"].includes($("sink-mode").value))
      $("sink-mode").value = "selected";
    invalidate();
  };
  const chooseArc = (event) => {
    const node = event.target.closest("[data-arc]");
    if (!node) return;
    activeArc =
      activeArc === Number(node.dataset.arc) ? null : Number(node.dataset.arc);
    if ($("sink-mode").value === "all" || $("sink-mode").value === "per-sink")
      $("sink-mode").value = "selected";
    invalidate();
  };
  $("sink-strip").onclick = chooseArc;
  $("sink-steps").onclick = chooseArc;
  $("sink-mode").onchange = () => {
    activeArc = null;
    invalidate();
  };
  $("sink-margin").onchange = () => {
    if (!$("sink-margin").checkValidity() || $("sink-margin").value === "")
      return $("sink-margin").reportValidity();
    marginNs = Number($("sink-margin").value);
    invalidate();
  };
  $("sink-search").oninput = () => {
    page = 0;
    renderList();
  };
  $("sink-prev").onclick = () => {
    page--;
    renderList();
  };
  $("sink-next").onclick = () => {
    page++;
    renderList();
  };
  return {
    update(nextIndex, nextLayers, { enabled, scope: nextScope }) {
      enabledView = enabled;
      $("sink-panel").hidden = !enabled;
      if (!enabled) {
        activeArc = null;
        selection = null;
        dirty = true;
        return;
      }
      const replaced = index !== nextIndex;
      if (replaced || layers !== nextLayers || scope !== nextScope) {
        index = nextIndex;
        layers = nextLayers;
        scope = nextScope;
        rows = sinkRows(index, layers, { scope });
        rows.sort(
          (a, b) =>
            (b.delayNs ?? -1) - (a.delayNs ?? -1) ||
            a.pinName.localeCompare(b.pinName) ||
            a.role.localeCompare(b.role),
        );
        if (replaced) {
          key =
            rows.find((r) => r.status === "known")?.key ?? rows[0]?.key ?? null;
          contextChanged = false;
        } else if (!visibleSink(rows, key)) {
          key = null;
          contextChanged = true;
        }
        activeArc = null;
        page = 0;
        dirty = true;
      }
      if (dirty) {
        renderList();
        renderPath();
        selection = sinkSelections(index, layers, {
          scope,
          mode: $("sink-mode").value,
          sink: selected(),
          marginNs,
        });
        $("sink-margin").disabled = $("sink-mode").value !== "near";
        $("sink-margin").closest("label").hidden =
          $("sink-mode").value !== "near";
        dirty = false;
      }
    },
    get selection() {
      return selection;
    },
    get activeArc() {
      return activeArc;
    },
    get focused() {
      return enabledView && ["selected", "near"].includes($("sink-mode").value);
    },
  };
}
