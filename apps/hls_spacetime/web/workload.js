import { probeState, windowStart, unionMasks } from "./workload-model.js";
/** Replay paired cycle-end primitive masks and pre-edge RTL controls from a published four-Phi witness. */
const byId = (id) => document.getElementById(id);
const colors = { vivado: [255, 181, 109], openxc7: [99, 218, 203] };
const backends = Object.keys(colors);
const fmt = (n) => n.toLocaleString("en-US");
let flow,
  replay,
  logic,
  cycle,
  unit,
  generation = 0,
  timer,
  selectedTile,
  zoomCenter,
  bounds;
const catalogs = {},
  chunks = new Map(),
  maps = {};

/** Verify the compressed bytes before decompressing the producer's little-endian masks. */
async function asset(ref) {
  const res = await fetch("data/" + ref.file);
  if (!res.ok) throw Error("Missing " + ref.file);
  const bytes = await res.arrayBuffer();
  const digest = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
  if (digest !== ref.sha256)
    throw Error("Content hash mismatch for " + ref.file);
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Size a canvas to its CSS box and use CSS pixels for subsequent drawing. */
function surface(canvas) {
  const w = canvas.clientWidth,
    h = canvas.clientHeight,
    s = window.devicePixelRatio || 1;
  canvas.width = Math.round(w * s);
  canvas.height = Math.round(h * s);
  const ctx = canvas.getContext("2d");
  ctx.scale(s, s);
  return { ctx, w, h };
}

/** Display full-horizon peaks per screen column on the same primitive-count scale. */
function history() {
  const { ctx, w, h } = surface(byId("history"));
  const max = Math.max(
    ...backends.map((b) => Math.max(...replay.backends[b].changed)),
  );
  for (const b of backends) {
    const ys = replay.backends[b].changed;
    ctx.strokeStyle = "rgb(" + colors[b] + ")";
    ctx.beginPath();
    for (let x = 0; x < w; x++) {
      const start = Math.floor((x * ys.length) / w),
        end = Math.max(start + 1, Math.ceil(((x + 1) * ys.length) / w));
      let peak = 0;
      for (let i = start; i < end; i++) peak = Math.max(peak, ys[i]);
      const y = h - 2 - ((h - 4) * peak) / Math.max(1, max);
      if (x === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  const pos = (cycle * (w - 1)) / (replay.cycles - 1);
  ctx.fillStyle = "#ffe19a";
  ctx.fillRect(pos, 0, 2, h);
}

/** Share one pending chunk per backend and bound the number retained while scrubbing. */
function chunk(backend, ordinal) {
  const key = backend + "-" + ordinal;
  if (!chunks.has(key)) {
    if (chunks.size >= 8) chunks.delete(chunks.keys().next().value);
    chunks.set(key, asset(replay.backends[backend].chunks[ordinal]));
  }
  return chunks.get(key);
}

/** Combine distinct changing and unknown primitive masks across this window, including chunk boundaries. */
async function windowMasks(backend, end, span) {
  const info = replay.backends[backend],
    length = 2 * Math.ceil(info.cells / 8);
  if (span === "all") {
    catalogs[backend].entire ??= asset(info.entire);
    const bytes = await catalogs[backend].entire;
    if (bytes.length !== length) throw Error("Incomplete whole-replay mask");
    return bytes;
  }
  const first = windowStart(end, Number(span)),
    low = Math.floor(first / replay.chunk),
    high = Math.floor(end / replay.chunk);
  const blocks = await Promise.all(
    Array.from({ length: high - low + 1 }, (_, i) => chunk(backend, low + i)),
  );
  return unionMasks(blocks, first, end, replay.chunk, length / 2);
}

/** Index every measured site and retain type-filtered occupancy, known changes and unknown comparisons per tile. */
function aggregate(backend, bytes) {
  const b = replay.backends[backend],
    stride = Math.ceil(b.cells / 8);
  const { tile, type } = catalogs[backend],
    filter = byId("family").value,
    scoped = byId("scoped").checked,
    all = filter === "All types" && !scoped;
  const size = replay.width * replay.height;
  const active = new Uint16Array(size),
    unknown = new Uint16Array(size),
    occupied = new Uint16Array(size);
  if (all) for (const [t, n] of b.occupancy) occupied[t] = n;
  let changes = 0,
    unknowns = 0,
    unlocated = 0;
  for (let i = 0; i < b.cells; i++) {
    if (
      (filter !== "All types" && b.kinds[type[i]] !== filter) ||
      (scoped && catalogs[backend].scope[i] !== unit.index)
    )
      continue;
    const t = tile[i],
      m = 1 << i % 8,
      ix = i >> 3;
    if (!all && t >= 0) occupied[t]++;
    if (bytes[ix] & m) {
      changes++;
      if (t >= 0) active[t]++;
      else unlocated++;
    }
    if (bytes[ix + stride] & m) {
      unknowns++;
      if (t >= 0) unknown[t]++;
    }
  }
  const article = byId(backend);
  article.querySelector(".stat").textContent =
    windowLabel() +
    " · " +
    fmt(changes) +
    " changing · " +
    fmt(unknowns) +
    " with unknowns" +
    (unlocated ? " · " + fmt(unlocated) + " changes unlocated" : "") +
    (scoped ? " · " + unit.label : "");
  maps[backend] = {
    active,
    unknown,
    occupied,
    bytes,
    stride,
    filter,
    scoped,
  };
  drawMap(backend);
}

/** Draw both floorplans on identical axes. The background includes placement-only cells in the all-types view. */
function drawMap(backend) {
  const map = maps[backend];
  if (!map) return;
  const article = byId(backend),
    canvas = article.querySelector("canvas");
  const { ctx, w, h } = surface(canvas),
    [x0, x1, y0, y1] = bounds;
  const zoom = Number(byId("zoom").value);
  const scale =
    zoom * Math.min((w - 12) / (x1 - x0 + 1), (h - 10) / (y1 - y0 + 1));
  const cx =
      zoom > 1 && zoomCenter != null
        ? zoomCenter % replay.width
        : (x0 + x1) / 2,
    cy =
      zoom > 1 && zoomCenter != null
        ? Math.floor(zoomCenter / replay.width)
        : (y0 + y1) / 2;
  const left = w / 2 - (cx - x0 + 0.5) * scale,
    top = h / 2 - (cy - y0 + 0.5) * scale;
  const rect = (tile) => [
    left + ((tile % replay.width) - x0) * scale,
    top + (Math.floor(tile / replay.width) - y0) * scale,
  ];
  map.tileAt = (x, y) => {
    const tx = Math.floor((x - left) / scale) + x0,
      ty = Math.floor((y - top) / scale) + y0;
    return tx < x0 || tx > x1 || ty < y0 || ty > y1
      ? null
      : ty * replay.width + tx;
  };
  ctx.fillStyle = "#172935";
  ctx.fillRect(left, top, (x1 - x0 + 1) * scale, (y1 - y0 + 1) * scale);
  const rgb = colors[backend];
  for (const [t] of replay.backends[backend].occupancy) {
    if (!map.occupied[t]) continue;
    const n = map.active[t],
      q = Math.min(1, 0.48 + Math.log2(1 + n) * 0.13);
    ctx.fillStyle = n ? `rgb(${rgb.map((c) => Math.round(c * q))})` : "#465964";
    const [x, y] = rect(t);
    ctx.fillRect(x, y, Math.max(1, scale), Math.max(1, scale));
  }
  if (selectedTile != null) {
    const [x, y] = rect(selectedTile);
    ctx.strokeStyle = "#fff2a4";
    ctx.lineWidth = 1.5;
    ctx.strokeRect(x - 2, y - 2, scale + 4, scale + 4);
  }
  article.querySelector(".inspect").textContent =
    selectedTile == null
      ? ""
      : (replay.tiles[selectedTile] ?? "Unoccupied tile") +
        " · " +
        fmt(map.occupied[selectedTile]) +
        " placed · " +
        fmt(map.active[selectedTile]) +
        " changing · " +
        fmt(map.unknown[selectedTile]) +
        " with unknowns";
  tileCells(backend);
}

/** Inspect the exact synthesized instance names at the selected coordinate, prioritizing changing outputs. */
async function tileCells(backend) {
  const el = byId(backend).querySelector(".cells"),
    map = maps[backend],
    cat = catalogs[backend],
    tile = selectedTile;
  el.replaceChildren();
  if (tile == null || !map.occupied[tile]) return;
  try {
    cat.names ??= asset(replay.backends[backend].names).then((bytes) =>
      new TextDecoder().decode(bytes).split("\n"),
    );
    const names = await cat.names;
    if (map !== maps[backend] || tile !== selectedTile) return;
    const rows = [];
    for (let i = 0; i < cat.tile.length; i++) {
      const type = replay.backends[backend].kinds[cat.type[i]];
      if (
        cat.tile[i] !== tile ||
        (map.filter !== "All types" && map.filter !== type) ||
        (map.scoped && cat.scope[i] !== unit.index)
      )
        continue;
      const pos = i >> 3,
        mask = 1 << i % 8,
        changed = !!(map.bytes[pos] & mask),
        unknown = !!(map.bytes[pos + map.stride] & mask);
      rows.push({ i, type, changed, unknown });
    }
    rows.sort(
      (a, b) =>
        Number(b.changed) - Number(a.changed) ||
        Number(b.unknown) - Number(a.unknown),
    );
    for (const { i, type, changed, unknown } of rows) {
      const p = document.createElement("div");
      p.textContent =
        type +
        " · " +
        (changed ? "changed" : unknown ? "unknown" : "stable") +
        (changed && unknown ? " / unknown" : "") +
        " · " +
        names[i];
      el.append(p);
    }
  } catch (e) {
    fault(e);
  }
}

/** Decode a pre-edge probe as idle, accepted/enabled, backpressured, or unknown during startup. */
function signal(clock, index) {
  return probeState(logic, replay.logical.probes, clock, index);
}

/** Show every named signal of the selected source instance, including addressed RAM enables. */
function detail() {
  byId("unit-title").textContent = unit.label;
  byId("unit-clock").textContent =
    "C" + cycle + (cycle < 4 ? " · reset asserted" : "");
  const list = byId("signals");
  list.replaceChildren();
  for (const [i, [label, , ready]] of unit.signals.entries()) {
    const state = signal(cycle, unit.offset + i),
      item = document.createElement("li");
    const addr = replay.logical.ram.find(
      ([c, b]) => c === cycle && b === unit.offset + i,
    );
    item.textContent =
      label +
      " · " +
      ["idle", ready ? "accepted" : "enabled", "backpressured", "unknown"][
        state
      ] +
      (addr ? " · address " + addr[2] : "");
    list.append(item);
  }
  if (unit.kind === "Output") {
    for (const frame of replay.logical.frames.filter(
      (f) => f.cycle === cycle,
    )) {
      const item = document.createElement("li");
      item.textContent =
        frame.plane + " " + frame.kind.toLowerCase() + " · 0x" + frame.hex;
      list.append(item);
    }
  }
}

/** Show a 65-clock window centered on the playhead and select any source unit or clock. */
function raster() {
  const units = replay.logical.units.filter(
    (u) => u.kind === byId("group").value,
  );
  if (!units.includes(unit)) unit = units[0];
  const start = Math.max(0, Math.min(cycle - 32, replay.cycles - 65)),
    end = start + 64;
  const root = byId("raster");
  root.replaceChildren();
  const axis = document.createElement("div");
  axis.className = "axis";
  axis.innerHTML =
    "<span>Instance</span><div><span>C" +
    start +
    "</span><span>C" +
    end +
    "</span></div>";
  root.append(axis);
  for (const u of units) {
    const row = document.createElement("button");
    row.className = "lane";
    row.setAttribute("aria-pressed", String(unit === u));
    row.title = u.path || u.label;
    const label = document.createElement("span");
    label.textContent = u.label;
    const canvas = document.createElement("canvas");
    row.append(label, canvas);
    root.append(row);
    const { ctx, w, h } = surface(canvas),
      dx = w / 65;
    for (let c = start; c <= end; c++) {
      let active = 0,
        stall = 0,
        unknown = 0;
      for (let i = 0; i < u.signals.length; i++) {
        const s = signal(c, u.offset + i);
        active += s === 1;
        stall += s === 2;
        unknown += s === 3;
      }
      const x = (c - start) * dx;
      ctx.fillStyle = active ? "#7fcbbd" : unknown ? "#a696af" : "#324450";
      ctx.fillRect(x, 1, Math.max(1, dx - 0.6), h - 2);
      if (stall) {
        ctx.fillStyle = "#ecab70";
        ctx.fillRect(x, h - 4, Math.max(1, dx - 0.6), 3);
      }
      if (c === cycle) {
        ctx.strokeStyle = "#ffe19a";
        ctx.strokeRect(x, 0, dx, h);
      }
    }
    row.onclick = (e) => {
      unit = u;
      if (e.target === canvas)
        select(start + Math.min(64, Math.floor(e.offsetX / dx)));
      else select(cycle);
    };
  }
  detail();
}

/** Label the inclusive interval used for both maps. C0 initializes the observer. */
function windowLabel() {
  const span = byId("window").value;
  if (span === "all") return "C1–" + (replay.cycles - 1);
  const start = windowStart(cycle, Number(span));
  return start === cycle ? "C" + cycle : "C" + start + "–" + cycle;
}

/** Move all layers to one cycle and discard late responses from earlier selections. */
async function select(value) {
  const request = ++generation;
  cycle = Math.max(0, Math.min(replay.cycles - 1, Math.round(value) || 0));
  byId("cycle").value = byId("scrub").value = cycle;
  const link = byId("other-view");
  link.href = "workload.html?cycle=" + cycle + (flow ? "" : "&view=flow");
  const frames = replay.logical.frames.filter((f) => f.cycle === cycle);
  byId("current-frame").textContent = frames
    .map(
      (f) =>
        f.plane +
        " " +
        f.kind.toLowerCase() +
        " (" +
        f.x +
        ", " +
        f.y +
        ") · step " +
        f.step +
        " · value " +
        f.value,
    )
    .join("  /  ");
  byId("jump").value = frames.length ? String(cycle) : "";
  history();
  raster();
  try {
    const bytes = await Promise.all(
      backends.map((b) =>
        windowMasks(b, cycle, flow ? 1 : byId("window").value),
      ),
    );
    if (request !== generation) return;
    if (flow) flow.update(cycle, bytes, byId("flow-filter").value);
    else backends.forEach((b, i) => aggregate(b, bytes[i]));
  } catch (e) {
    if (request === generation) fault(e);
  }
}

/** Stop playback when unavailable evidence or a corrupt asset prevents an honest display. */
function fault(e) {
  clearInterval(timer);
  timer = null;
  byId("play").textContent = "Play";
  byId("error").hidden = false;
  byId("error").textContent = e.message;
}

/** Load both syntheses, verify physical catalogs, and open on the first accepted public output. */
async function init() {
  const res = await fetch("data/workload.json");
  if (!res.ok) throw Error("This gallery has no paired four-Phi workload.");
  replay = await res.json();
  if (replay.schema !== 1) throw Error("Unsupported four-Phi workload format.");
  logic = await asset(replay.logical.streams);
  if (logic.length !== replay.cycles * 4 * Math.ceil(replay.logical.probes / 8))
    throw Error("Incomplete source probe stream");
  let offset = 0;
  for (const u of replay.logical.units) {
    u.index = replay.logical.units.indexOf(u);
    u.offset = offset;
    offset += u.signals.length;
  }
  if (offset !== replay.logical.probes) throw Error("Probe catalogue width");
  await Promise.all(
    backends.map(async (b) => {
      const info = replay.backends[b],
        bytes = await asset(info.catalogue),
        dv = new DataView(bytes.buffer);
      if (bytes.length !== info.cells * 7)
        throw Error("Incomplete " + b + " cell inventory");
      const tile = new Int32Array(info.cells),
        type = new Uint8Array(info.cells),
        scope = new Int16Array(info.cells);
      for (let i = 0; i < info.cells; i++) {
        tile[i] = dv.getInt32(i * 7, true);
        type[i] = bytes[i * 7 + 4];
        scope[i] = dv.getInt16(i * 7 + 5, true);
      }
      catalogs[b] = { tile, type, scope };
      const entries = (obj) =>
        Object.entries(obj)
          .map(([k, n]) => fmt(n) + " " + k)
          .join(", ");
      byId(b).querySelector(".coverage").textContent =
        fmt(info.mapped) +
        " of " +
        fmt(info.cells) +
        " simulated cells located. " +
        (entries(info.unplaced)
          ? "Unlocated cells include " + entries(info.unplaced) + ". "
          : "") +
        (entries(info.placementOnly)
          ? "Additional checkpoint entries include " +
            entries(info.placementOnly) +
            ". "
          : "") +
        fmt(info.scoped) +
        " cells link to a source instance by hierarchy or a uniquely scoped named output.";
      byId(b).querySelector("canvas").onclick = (e) => {
        const m = maps[b];
        if (m) {
          selectedTile = m.tileAt(e.offsetX, e.offsetY);
          backends.forEach(drawMap);
        }
      };
    }),
  );
  const tiles = Object.keys(replay.tiles).map(Number),
    xs = tiles.map((t) => t % replay.width),
    ys = tiles.map((t) => Math.floor(t / replay.width));
  bounds = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  byId("subtitle").textContent =
    "X and Z planes · 2 × 1 cells per plane · " +
    replay.part +
    " · " +
    replay.period +
    " ns target";
  byId("cycle").max = byId("scrub").max = replay.cycles - 1;
  byId("end").textContent =
    "C" +
    (replay.cycles - 1) +
    " · " +
    fmt(replay.logical.frames.length) +
    " accepted frames";
  for (const k of [
    ...new Set(backends.flatMap((b) => replay.backends[b].kinds)),
  ].sort())
    byId("family").add(new Option(k, k));
  const jumps = byId("jump");
  jumps.options[0].value = "";
  for (const c of new Set(replay.logical.frames.map((f) => f.cycle))) {
    const fs = replay.logical.frames.filter((f) => f.cycle === c);
    jumps.add(
      new Option(
        "C" +
          c +
          " · " +
          fs.map((f) => f.plane + "(" + f.x + "," + f.y + ")").join(" / ") +
          " · step " +
          fs[0].step,
        c,
      ),
    );
  }
  jumps.onchange = () => {
    if (jumps.value) select(+jumps.value);
  };
  byId("prev").onclick = () => select(cycle - 1);
  byId("next").onclick = () => select(cycle + 1);
  byId("scrub").oninput = (e) => select(+e.target.value);
  byId("cycle").onchange = (e) => select(+e.target.value);
  byId("history").onclick = (e) =>
    select(((replay.cycles - 1) * e.offsetX) / e.currentTarget.clientWidth);
  byId("group").onchange = () => select(cycle);
  byId("scoped").onchange = () => select(cycle);
  byId("family").onchange = byId("window").onchange = () => select(cycle);
  byId("zoom").onchange = () => {
    zoomCenter = selectedTile;
    backends.forEach(drawMap);
  };
  byId("play").onclick = () => {
    if (timer) {
      clearInterval(timer);
      timer = null;
    } else {
      if (cycle === replay.cycles - 1) select(0);
      timer = setInterval(() => {
        if (cycle === replay.cycles - 1) byId("play").click();
        else select(cycle + 1);
      }, 200);
    }
    byId("play").textContent = timer ? "Pause" : "Play";
  };
  const query = new URLSearchParams(location.search);
  const inFlow = query.get("view") === "flow";
  byId("other-view").hidden = !replay.flow;
  byId("other-view").textContent = inFlow ? "2D placement" : "3D signal flow";
  if (inFlow) {
    if (replay.flow?.schema !== 1)
      throw Error("This gallery has no four-Phi flow capture.");
    byId("placement-section").hidden = true;
    byId("flow-section").hidden = false;
    for (const b of backends)
      byId(b + "-flow").querySelector(".stat").textContent =
        "Loading connections…";
    const { createFlow } = await import("./workload-flow.js");
    flow = await createFlow(replay, catalogs, asset);
    byId("flow-filter").onchange = () => select(cycle);
  }
  const initial = query.get("cycle");
  unit = replay.logical.units.find((u) => u.label === "X reduction");
  await select(
    initial === null
      ? flow
        ? 32
        : replay.logical.frames[0].cycle
      : Number(initial),
  );
  window.addEventListener("resize", () => {
    history();
    raster();
    if (flow) flow.resize();
    else backends.forEach(drawMap);
  });
}
init().catch(fault);
