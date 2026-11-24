/** Inspect a selected sink path or one indexed net arc without loading the whole interval. */
import { openIntervalGeometry } from "./interval-geometry.js";
import { setInspectedRoutes } from "./arrival-circuits.js";

const $ = (id) => document.getElementById(id);
const fmt = (n) => n.toLocaleString();

/** Couple pending shard requests to their capture and selection. Failed requests expose a retry. */
export function createIntervalInspector(repaint) {
  let source,
    index,
    controller,
    signature,
    manual,
    lastSink,
    lastActiveArc,
    result,
    displayedArc;
  const panel = $("interval-panel"),
    status = $("interval-status"),
    detail = $("interval-detail");
  const canvas = $("interval-map"),
    list = $("interval-switches");

  /** Cancel the current inspection and release its capture-specific geometry. */
  function reset() {
    controller?.abort();
    if (index) setInspectedRoutes(index, new Map());
    source = index = signature = manual = lastSink = result = null;
    panel.hidden = true;
    $("interval-arc").value = "";
    $("interval-census").textContent =
      status.textContent =
      detail.textContent =
        "";
    list.replaceChildren();
    canvas.hidden = true;
  }

  /** Open only the optional inventory once its recording and render tables are installed. */
  async function configure(options, prepared) {
    reset();
    if (!options.entry.geometry) return;
    panel.hidden = false;
    status.textContent = "Reading the interval route inventory…";
    try {
      const next = await openIntervalGeometry(options);
      options.signal.throwIfAborted();
      source = next;
      index = prepared;
      const m = source.manifest,
        qualified = (m.counts.direct ?? 0) + (m.counts.lut_permutation ?? 0);
      $("interval-census").textContent =
        `C${m.selection.firstCycle}–${m.selection.endCycle - 1} · ${fmt(qualified)} of ${fmt(m.branches)} net branches traced across ${fmt(m.nets)} nets. ${fmt(m.counts.disconnected_constant ?? 0)} constant branches end at disconnected local ties.`;
      repaint();
    } catch (error) {
      if (!options.signal.aborted) status.textContent = error.message;
    }
  }

  /** Display native footprint members and ordered fixed switches for one arc. */
  function show(arc) {
    list.replaceChildren();
    canvas.hidden = true;
    if (!Number.isInteger(arc)) {
      detail.textContent = "";
      return;
    }
    const item = result?.get(arc);
    if (!item) {
      detail.textContent = `Arc ${arc} has no interval net-branch record.`;
      return;
    }
    const [from, to] = index.arcGeometry[arc];
    detail.textContent =
      `Arc ${arc} · ${index.pinGeometry[from][3]} → ${index.pinGeometry[to][3]} · ${item.status.replaceAll("_", " ")} · ${item.switches.length} switches` +
      (item.physical
        ? ` · physical LUT input ${item.physical} · router wire ${item.footprint.at(-1)[1]}`
        : "") +
      (item.localTie ? ` · local tie ${item.localTie}` : "");
    if (!item.footprint.length) return;
    const width = source.manifest.width;
    let xmin = Infinity,
      ymin = Infinity,
      xmax = -Infinity,
      ymax = -Infinity;
    const dots = new Set();
    for (const [, , members] of item.footprint)
      for (const [tile] of members) {
        dots.add(tile);
        const x = tile % width,
          y = Math.floor(tile / width);
        xmin = Math.min(xmin, x);
        xmax = Math.max(xmax, x);
        ymin = Math.min(ymin, y);
        ymax = Math.max(ymax, y);
      }
    canvas.hidden = false;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const scale = Math.min(
      (canvas.width - 16) / Math.max(1, xmax - xmin),
      (canvas.height - 16) / Math.max(1, ymax - ymin),
    );
    function dot(tile, size) {
      ctx.fillRect(
        8 + ((tile % width) - xmin) * scale - size / 2,
        8 + (Math.floor(tile / width) - ymin) * scale - size / 2,
        size,
        size,
      );
    }
    ctx.fillStyle = "#7199bf";
    for (const tile of dots) dot(tile, 5);
    ctx.fillStyle = "#dd9f44";
    for (const [, , , tile, switchId, incoming] of item.switches) {
      dot(tile, 3);
      const li = document.createElement("li");
      li.textContent = `${switchId} · ${incoming}`;
      list.append(li);
    }
  }

  /** Replace only the inspected geometry after all requested native records pass validation. */
  function update(inspector) {
    if (!source) return;
    if (lastSink !== inspector.key || lastActiveArc !== inspector.activeArc) {
      manual = null;
      $("interval-arc").value = "";
    }
    lastSink = inspector.key;
    lastActiveArc = inspector.activeArc;
    const path = inspector.focused
      ? inspector.pathArcs.filter((a) => index.arcGeometry[a][2] === 0)
      : [];
    const arc = manual ?? inspector.activeArc;
    // A manual lookup also works when the representative path exceeds the transfer budget.
    const ids = manual !== null ? [manual] : path;
    const key = JSON.stringify(ids);
    if (key === signature) {
      if (result && displayedArc !== arc) {
        show(arc);
        displayedArc = arc;
      }
      return;
    }
    signature = key;
    controller?.abort();
    const request = new AbortController();
    controller = request;
    setInspectedRoutes(index, new Map());
    result = null;
    show(null);
    if (!ids.length) {
      status.textContent =
        "Select a sink or inspect a net arc to load its native geometry.";
      return;
    }
    status.textContent = `Loading geometry for ${ids.length} net branches…`;
    source
      .load(ids, index, request.signal)
      .then((loaded) => {
        if (request.signal.aborted) return;
        result = loaded;
        setInspectedRoutes(index, loaded);
        const traced = [...loaded.values()].filter(
          (r) => r.disposition === "resolved",
        ).length;
        status.textContent = `${traced} of ${ids.length} inspected net branches traced · ${loaded.size} in the published interval.`;
        // An arc selection may have changed during the request.
        displayedArc = undefined;
        repaint();
      })
      .catch((error) => {
        if (!request.signal.aborted) status.textContent = error.message;
      });
  }

  $("interval-inspect").onclick = () => {
    const query = $("interval-arc").value.trim();
    if (!index) return;
    if (!query) manual = null;
    else if (/^\d+$/.test(query) && index.arcGeometry[Number(query)]?.[2] === 0)
      manual = Number(query);
    else {
      const pin = index.pinGeometry.findIndex((row) => row[3] === query);
      const arc = index.arcGeometry.findIndex(
        ([, to, kind]) => kind === 0 && to === pin,
      );
      if (arc < 0) {
        status.textContent = "Enter a net arc ID or its full sink pin name.";
        return;
      }
      manual = arc;
    }
    signature = null;
    repaint();
  };
  return {
    reset,
    configure,
    update,
    get available() {
      return Boolean(source);
    },
  };
}
