/** Lazy saved-resource inspection, separate from timing and recorded activity.
 * All contributors remain available through paging; no scene-population cap. */
import { loadRegionalWorker } from "./regional-loader.js";
import { createRegionalData } from "./regional-data.js";
import { regionalView, regionalScene } from "./regional-view.js";
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
const count = (n) => Number(n ?? 0).toLocaleString("en-US");

/** A capture replacement cancels and clears optional data. Filters change family
 * attribution only; installed-resource counts and the color scale stay fixed. */
export function createRegionalControls(
  onChange,
  { load = loadRegionalWorker, validate = createRegionalData } = {},
) {
  let options = null,
    model = null,
    data = null,
    controller = null,
    sequence = 0,
    view = null,
    index = null,
    neighborhood = null,
    selectedBin = null,
    selectedNet = null,
    selectedCell = null,
    page = 0,
    revision = 0,
    renderedKey = null;
  const invalidate = () => {
    revision++;
    onChange();
  };
  for (const id of [
    "region-metric",
    "region-kind",
    "region-population",
    "region-scope",
    "region-overlay",
  ])
    $(id).onchange = () => {
      page = 0;
      invalidate();
    };
  $("region-search").oninput = () => {
    page = 0;
    invalidate();
  };
  $("region-family-only").onchange = () => {
    page = 0;
    invalidate();
  };
  $("region-prev").onclick = () => {
    page--;
    invalidate();
  };
  $("region-next").onclick = () => {
    page++;
    invalidate();
  };
  $("region-bin").onchange = () => {
    selectedBin =
      $("region-bin").value === "" ? null : Number($("region-bin").value);
    selectedNet = selectedCell = null;
    page = 0;
    invalidate();
  };
  $("region-map").onclick = (event) => {
    const target = event.target.closest("[data-region-bin]");
    if (!target) return;
    selectedBin = Number(target.dataset.regionBin);
    selectedNet = selectedCell = null;
    page = 0;
    invalidate();
  };
  $("region-list").onclick = (event) => {
    const target = event.target.closest(
      "[data-region-net], [data-region-cell]",
    );
    if (!target) return;
    if (target.dataset.regionNet !== undefined) {
      const value = Number(target.dataset.regionNet);
      selectedNet = selectedNet === value ? null : value;
      selectedCell = null;
    } else {
      const value = Number(target.dataset.regionCell);
      selectedCell = selectedCell === value ? null : value;
      selectedNet = null;
    }
    invalidate();
  };
  $("region-clear").onclick = () => {
    selectedBin = selectedNet = selectedCell = null;
    page = 0;
    invalidate();
  };
  $("region-load").onclick = async () => {
    if (!options?.entry || data || controller) return;
    const ticket = sequence,
      request = options,
      capture = model;
    controller = new AbortController();
    const signal = controller.signal;
    $("region-load").disabled = true;
    try {
      const raw = await load({
        ...request,
        signal,
        progress: (message) => {
          if (ticket === sequence) $("region-status").textContent = message;
        },
      });
      if (ticket !== sequence) return;
      data = validate(capture, raw);
      $("region-kind").innerHTML =
        '<option value="">All primitive kinds</option>' +
        [
          ...new Set(
            data.cells.map((r) => r.kind).filter((kind) => kind !== null),
          ),
        ]
          .sort()
          .map((kind) => `<option value="${esc(kind)}">${esc(kind)}</option>`)
          .join("");
      $("region-content").hidden = false;
      $("region-status").textContent =
        `${count(data.cells.length)} installed cells · ${count(data.nets.length)} native nets · ${count(data.pips.length)} distinct used routing switches (PIPs). Verified saved evidence; counted once across clocks and branches.`;
      $("region-load").hidden = true;
      invalidate();
    } catch (error) {
      if (ticket === sequence) {
        $("region-status").textContent =
          `Regional data unavailable: ${error.message}`;
        $("region-load").disabled = false;
      }
    } finally {
      if (ticket === sequence) controller = null;
    }
  };
  function visibleBins() {
    if (!view) return [];
    const region = neighborhood?.region;
    if ($("region-scope").value !== "family" || !region) return view.bins;
    return view.bins.filter(
      ({ bounds: b, selected, selectedNet: net }) =>
        selected ||
        net ||
        (b.minX <= region.maxX &&
          b.maxX > region.minX &&
          b.minY <= region.maxY &&
          b.maxY > region.minY),
    );
  }
  function paintMap(bins) {
    if (!bins.length) {
      $("region-map").innerHTML = "No located resources.";
      return;
    }
    let loX = Infinity,
      hiX = -Infinity,
      loY = Infinity,
      hiY = -Infinity;
    for (const { bounds: b } of bins) {
      loX = Math.min(loX, b.minX);
      hiX = Math.max(hiX, b.maxX);
      loY = Math.min(loY, b.minY);
      hiY = Math.max(hiY, b.maxY);
    }
    const width = hiX - loX,
      height = hiY - loY;
    $("region-map").innerHTML =
      `<svg viewBox="${loX - 1} ${-hiY - 1} ${width + 2} ${height + 2}" role="img" aria-label="Regional installed resource map">${bins
        .map((b) => {
          const r = b.bounds;
          return `<g data-region-bin="${b.index}"><title>Tile region X${r.minX}…${r.maxX}, Y${r.minY}…${r.maxY}: ${b.value} ${esc(view.domain.label)}; ${b.familyValue} on family nets / cells</title><rect x="${r.minX}" y="${-r.maxY}" width="${r.maxX - r.minX}" height="${r.maxY - r.minY}" fill="${b.color}" stroke="${b.selected ? "#f7d687" : b.selectedNet ? "#a4d5e9" : "#17252b"}" stroke-width="${b.selected || b.selectedNet ? 0.7 : 0.18}"/>${b.familyValue ? `<circle cx="${(r.minX + r.maxX) / 2}" cy="${-(r.minY + r.maxY) / 2}" r="${data.binSize * 0.12}" fill="#d5d9ce"/>` : ""}</g>`;
        })
        .join("")}</svg>`;
  }
  function paintDetails() {
    const detail = view.details;
    const total = detail?.bin.counts;
    $("region-selection").textContent = detail
      ? `Region X${detail.bin.bounds.minX}…${detail.bin.bounds.maxX}, Y${detail.bin.bounds.minY}…${detail.bin.bounds.maxY}: ${count(total.cells)} cells, ${count(total.pips)} switches, ${count(total.nets)} nets. Family: ${count(detail.bin.family?.cells ?? view.bins[detail.index].family.cells)} cells, ${count(view.bins[detail.index].family.pips)} switches, ${count(view.bins[detail.index].family.nets)} nets.`
      : "Select a tile region to inspect its complete contributor lists.";
    const kind = $("region-population").value || "nets",
      allRows = detail?.[kind] ?? [];
    const query = $("region-search").value.trim().toLowerCase();
    const rows = allRows.filter(
      (r) =>
        (!$("region-family-only").checked || r.family) &&
        (!query || (r.net ?? r.cell ?? r.pip).id.toLowerCase().includes(query)),
    );
    page = Math.max(
      0,
      Math.min(page, Math.max(0, Math.ceil(rows.length / PAGE) - 1)),
    );
    $("region-list").innerHTML =
      `<table><thead><tr><th>${esc(kind)}</th><th>Touches family</th></tr></thead><tbody>${rows
        .slice(page * PAGE, (page + 1) * PAGE)
        .map((r) => {
          const item = r.net ?? r.cell ?? r.pip,
            key = r.net ? "net" : r.cell ? "cell" : null;
          const label = `${item.id}${r.cell ? ` · ${item.kind ?? "unknown kind"}` : ""}`;
          return `<tr><td>${key ? `<button type="button" class="sink-name" data-region-${key}="${r.index}" aria-pressed="${key === "net" ? selectedNet === r.index : selectedCell === r.index}" title="${esc(label)}">${esc(label)}</button>` : esc(label)}</td><td>${r.shared ? "Shared" : r.family ? "Family" : "Other / unattributed"}</td></tr>`;
        })
        .join("")}</tbody></table>`;
    $("region-page").textContent =
      `${count(rows.length)} of ${count(allRows.length)} ${kind} · page ${page + 1}/${Math.max(1, Math.ceil(rows.length / PAGE))}`;
    $("region-prev").disabled = page === 0;
    $("region-next").disabled = (page + 1) * PAGE >= rows.length;
    const selected = view.selectedNet;
    $("region-footprint").textContent = selected
      ? `${selected.net.id}: ${count(selected.bins.length)} occupied regions, ${count(selected.net.pips.length)} retained switches; ${count(selected.net.locatedWireCount)} / ${count(selected.net.wireCount)} wire locations known. Pale outlines show its complete known footprint, including outside the path neighborhood. Membership is not wire length or electrical activity.`
      : view.selectedCell
        ? `${view.selectedCell.cell.id} · ${view.selectedCell.cell.kind ?? "unknown primitive kind"}. Its native placement is highlighted; no functional ownership is inferred.`
        : "Choose a net to compare its complete saved footprint, or a cell to locate it in 3D.";
  }
  return {
    configure(nextModel = null, nextOptions = null) {
      sequence++;
      controller?.abort();
      controller = null;
      model = nextModel;
      options = nextOptions;
      $("region-search").value = "";
      $("region-family-only").checked = false;
      data = view = index = neighborhood = null;
      selectedBin = selectedNet = selectedCell = null;
      page = 0;
      renderedKey = null;
      $("region-content").hidden = true;
      $("region-load").hidden = false;
      $("region-load").disabled = !options?.entry;
      $("region-status").textContent = options?.entry
        ? "Optional saved routing-resource data. Load when needed; it is not fetched during initial rendering."
        : "This capture has no prepared regional-resource data.";
    },
    update(nextIndex, nextNeighborhood) {
      if (!data) return;
      if (
        index === nextIndex &&
        neighborhood === nextNeighborhood &&
        renderedKey === revision
      )
        return;
      index = nextIndex;
      neighborhood = nextNeighborhood;
      renderedKey = revision;
      view = regionalView(data, {
        metric: $("region-metric").value || "pips",
        primitiveKind:
          $("region-metric").value === "cells"
            ? $("region-kind").value || null
            : null,
        computationIndex: index,
        neighborhood,
        selectedBin,
        selectedNet,
        selectedCell,
      });
      $("region-kind").disabled = view.metric !== "cells";
      $("region-scale").textContent =
        `Color: 0…${count(view.domain.max)} ${view.domain.label} per ${data.binSize} × ${data.binSize} tile region; fixed across filtering. Pale dots mark family cells or whole nets touching family paths. Bounds are half-open. Empty bins have no retained contributors, not proven free capacity.`;
      const c = data.summary;
      $("region-coverage").textContent =
        `${count(c.unknownCellPositions)} cells lack positions; ${count(c.unknownCellKinds)} lack primitive kinds. ${count(c.unknownPipPositions)} switches lack positions; ${count(c.unknownPipDirections)} lack direction. ${count(c.locatedWireMemberships)} / ${count(c.wireMemberships)} native wire memberships have locations; ${count(c.netsWithUnknownPositions)} nets have incomplete location evidence and ${count(c.netsWithoutLocatedResources)} have no located routing resources. ${count(c.netBinIncidences)} net/region incidences count a net once in each region it visits, not once in the whole chip. “Other / unattributed” means outside the selected representative paths, not idle or unrelated. No clock/reset class or semantic owner is inferred from names.`;
      const bins = visibleBins();
      $("region-scope-note").textContent = neighborhood?.region
        ? "Pale dots identify family cells and the full routed nets touching family paths, including other fanout branches. Choosing a net includes all its located regions, even outside the neighborhood."
        : "No path neighborhood is selected, so the map shows the whole installed device. Choose Path neighborhood above to compare its paths with the surrounding resources.";
      $("region-bin").innerHTML =
        '<option value="">Select a region</option>' +
        bins
          .map(
            (b) =>
              `<option value="${b.index}">X${b.bounds.minX}…${b.bounds.maxX}, Y${b.bounds.minY}…${b.bounds.maxY} · ${b.value}</option>`,
          )
          .join("");
      $("region-bin").value = selectedBin === null ? "" : String(selectedBin);
      paintMap(bins);
      paintDetails();
    },
    scene(options) {
      if (!view || !$("region-overlay").checked) return null;
      return regionalScene(view, {
        ...options,
        binIndices: visibleBins().map((b) => b.index),
      });
    },
    get view() {
      return view;
    },
  };
}
