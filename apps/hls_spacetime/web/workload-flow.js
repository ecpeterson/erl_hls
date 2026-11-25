import {
  cameraMatrices,
  createCamera,
  fitCamera,
  orbitCamera,
  projectPoint,
  zoomCamera,
} from "./camera3d.js";

const backends = ["vivado", "openxc7"];
const format = (n) => n.toLocaleString("en-US");
const changed = (mask, i) => (mask[i >> 3] & (1 << i % 8)) !== 0;

/** Validate the fixed-width edge rows and variable-length switch-tile lists before drawing. */
export function decodeFlow(bytes, cells, routes, count, tiles, pins, ports) {
  if (bytes.length % 16) throw Error("Incomplete flow edge record");
  const data = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const rows = bytes.length / 16;
  let top = 0;
  for (let i = 0; i < rows; i++) {
    const a = data.getFloat32(16 * i + 8, true),
      b = data.getFloat32(16 * i + 12, true);
    if (
      !(0 <= a && a <= b && Number.isFinite(b)) ||
      data.getUint32(16 * i, true) >= cells ||
      data.getUint32(16 * i + 4, true) >= cells
    )
      throw Error("Invalid flow endpoint or arrival");
    top = Math.max(top, b);
  }
  if (!pins && !routes) return { data, rows, top };
  if (
    !Number.isInteger(count) ||
    count < 0 ||
    count > rows ||
    pins?.length !== rows * 2
  )
    throw Error("Incomplete pin inventory");
  const pairs = new Uint16Array(pins.buffer, pins.byteOffset, rows);
  if (!ports || pairs.some((p) => p >= ports.length))
    throw Error("Invalid flow port pair");
  const model = { data, rows, top, pairs, ports, nets: count };
  if (!routes) return model;
  if (routes.length % 2) throw Error("Incomplete switch list");
  const words = new Uint16Array(
    routes.buffer,
    routes.byteOffset,
    routes.length / 2,
  );
  const offsets = new Uint32Array(count);
  let at = 0;
  for (let i = 0; i < count; i++) {
    offsets[i] = at;
    const n = words[at++];
    if (n === undefined) throw Error("Missing route");
    if (n === 65535) continue;
    if (at + n > words.length) throw Error("Incomplete switch list");
    for (let k = 0; k < n; k++)
      if (words[at++] >= tiles) throw Error("Invalid switch tile");
  }
  if (at !== words.length) throw Error("Flow inventory mismatch");
  return { ...model, offsets, words };
}

/** Orthographic projection is affine; cache the four basis projections for these chip coordinates. */
function projection(camera, viewport) {
  const matrix = cameraMatrices(camera, viewport).matrix;
  const p = (x, y, z) => projectPoint([x, y, z], matrix, viewport);
  const o = p(0, 0, 0),
    a = p(1, 0, 0),
    b = p(0, 1, 0),
    c = p(0, 0, 1);
  return (x, y, z) => [
    o.x + x * (a.x - o.x) + y * (b.x - o.x) + z * (c.x - o.x),
    o.y + x * (a.y - o.y) + y * (b.y - o.y) + z * (c.y - o.y),
  ];
}

/** Load whole-implementation connectivity once; clock changes select from the verified replay masks. */
export async function createFlow(replay, catalogs, asset) {
  const panels = {};
  const w = replay.width,
    h = replay.height;
  const tiles = Object.keys(replay.tiles).map(Number);
  const xs = tiles.map((t) => t % w),
    ys = tiles.map((t) => Math.floor(t / w));
  const x0 = Math.min(...xs),
    x1 = Math.max(...xs),
    y0 = Math.min(...ys),
    y1 = Math.max(...ys);
  const height = 0.78 * Math.max(x1 - x0, y1 - y0);
  const bounds = { min: [x0, y0, -height], max: [x1, y1, 0] };
  let camera, frame, current;
  const mode = document.getElementById("native-geometry");
  const shared = document.getElementById("flow-shared");
  const estimate = replay.flow.openxc7.estimate;
  if (estimate && estimate.checkpoint !== replay.checkpoints.openxc7)
    throw Error("Placement timing belongs to a different checkpoint");
  document.getElementById("native-modes").hidden = !estimate;
  document.getElementById("shared-scale").hidden = !estimate;
  if (!estimate) mode.value = "depth";
  await Promise.all(
    backends.map(async (b) => {
      const info = replay.flow[b],
        article = document.getElementById(b + "-flow");
      const [edges, routes, pins, names] = await Promise.all([
        asset(info.edges),
        info.routes && asset(info.routes),
        info.pins && asset(info.pins),
        asset(replay.backends[b].names),
      ]);
      const model = decodeFlow(
        edges,
        catalogs[b].tile.length,
        routes,
        info.timedConnections,
        w * h,
        pins,
        info.ports,
      );
      let estimated;
      if (b === "openxc7" && estimate) {
        const [timed, pins] = await Promise.all([
          asset(estimate.edges),
          asset(estimate.pins),
        ]);
        estimated = decodeFlow(
          timed,
          catalogs[b].tile.length,
          null,
          estimate.timedConnections,
          w * h,
          pins,
          estimate.ports,
        );
        if (
          estimated.rows !==
          estimate.timedConnections + estimate.timedCellArcs
        )
          throw Error("Incomplete placement timing inventory");
      }
      const top =
        b === "vivado"
          ? Math.ceil(Math.max(model.top, replay.period) / 5) * 5
          : Math.ceil(model.top / 5) * 5;
      panels[b] = {
        article,
        canvas: article.querySelector("canvas"),
        model,
        base: model,
        estimated,
        baseTop: top,
        top,
        names: new TextDecoder().decode(names).split("\n"),
        paths: [],
        selection: null,
        active: new Set(),
      };
    }),
  );

  /** Fit against the shared chip box; changes of clock preserve the camera. */
  function fit() {
    const cv = panels.vivado.canvas;
    camera = fitCamera(
      createCamera({ yaw: 0.84, pitch: 0.41 }),
      bounds,
      { width: cv.clientWidth, height: cv.clientHeight },
      { padding: 1.07 },
    );
  }

  /** Build the visible net polyline in chip/time space. SDF supplies times only at its endpoints. */
  function path(b, i, a, d, start, end) {
    const p = panels[b],
      m = p.model,
      tile = catalogs[b].tile;
    const t = [tile[a]];
    const local = m.nets !== undefined && i >= m.nets;
    const routed = !!m.offsets && !local;
    const at = routed ? m.offsets[i] : 0,
      n = routed ? m.words[at] : 0;
    if (routed && n !== 65535) {
      for (let j = 0; j < n; j++)
        if (m.words[at + 1 + j] !== t.at(-1)) t.push(m.words[at + 1 + j]);
    }
    if (t.at(-1) !== tile[d] || t.length === 1) t.push(tile[d]);
    const points = t.map((v) => [v % w, Math.floor(v / w), 0]);
    let distance = 0;
    for (let k = 1; k < points.length; k++) {
      distance += Math.hypot(
        points[k][0] - points[k - 1][0],
        points[k][1] - points[k - 1][1],
      );
      points[k][2] = distance;
    }
    for (let k = 0; k < points.length; k++) {
      const f = distance ? points[k][2] / distance : k / (points.length - 1);
      points[k][2] = (-(start + f * (end - start)) * height) / p.top;
    }
    return {
      i,
      a,
      d,
      start,
      end,
      points,
      dash: !local && (!routed || n === 65535),
      pinsOnly: b === "openxc7" && !local && mode.value === "pins",
      local,
      switches: n === 65535 ? null : n,
    };
  }

  /** Join the one-clock known-change bits to both endpoints or to the driver alone. */
  function update(cycle, masks, filter) {
    current = [cycle, masks, filter];
    const timed = !!estimate && mode.value !== "depth";
    shared.disabled = !timed;
    const vendor = panels.vivado,
      native = panels.openxc7;
    native.model = timed ? native.estimated : native.base;
    native.top = timed
      ? 5 * Math.ceil(Math.max(native.model.top, replay.period) / 5)
      : native.baseTop;
    vendor.top = vendor.baseTop;
    if (timed && shared.checked)
      native.top = vendor.top = Math.max(native.top, vendor.top);
    native.article.querySelector(".map-head span").textContent = timed
      ? "Placement estimate · ns"
      : "Placed · logic depth";
    for (const [index, b] of backends.entries()) {
      const p = panels[b],
        m = p.model,
        tile = catalogs[b].tile,
        mask = masks[index];
      p.active = new Set();
      for (let i = 0; i < tile.length; i++)
        if (tile[i] >= 0 && changed(mask, i)) p.active.add(tile[i]);
      p.paths = [];
      p.selection = null;
      let nets = 0,
        local = 0;
      for (let i = 0; i < m.rows; i++) {
        const a = m.data.getUint32(i * 16, true),
          d = m.data.getUint32(i * 16 + 4, true);
        if (
          !changed(mask, a) ||
          (filter === "both" && !changed(mask, d)) ||
          tile[a] < 0 ||
          tile[d] < 0
        )
          continue;
        const edge = path(
          b,
          i,
          a,
          d,
          m.data.getFloat32(i * 16 + 8, true),
          m.data.getFloat32(i * 16 + 12, true),
        );
        p.paths.push(edge);
        if (edge.local) local++;
        else nets++;
      }
      p.article.querySelector(".stat").textContent =
        "C" +
        cycle +
        " · " +
        format(nets) +
        (b === "vivado"
          ? " net connections · " + format(local) + " cell arcs"
          : timed
            ? " estimated pin connections · " + format(local) + " cell arcs"
            : " connected cell pairs");
      p.article.querySelector(".flow-selection").textContent =
        nets || local
          ? b === "vivado"
            ? "Switch tiles and primitive arcs · height in nanoseconds"
            : timed
              ? mode.value === "pins"
                ? "Select a placed pin to reveal its endpoint connection."
                : "Dashed spans connect placed pins. Wire routes are unknown."
              : "Schematic cell pairs · height in combinational levels"
          : "No connections match the activity filter at this clock.";
    }
    redraw();
  }

  /** Paint projected route polylines, floor occupancy and the labeled vertical axis. */
  function draw(b) {
    const p = panels[b],
      cv = p.canvas,
      width = cv.clientWidth,
      pixels = cv.clientHeight;
    if (!width || !pixels) return;
    const ratio = devicePixelRatio || 1;
    if (
      cv.width !== Math.round(width * ratio) ||
      cv.height !== Math.round(pixels * ratio)
    ) {
      cv.width = Math.round(width * ratio);
      cv.height = Math.round(pixels * ratio);
    }
    const ctx = cv.getContext("2d");
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, width, pixels);
    const xy = projection(camera, { width, height: pixels }),
      floor = (x, y) => xy(x, y, 0);
    const line = (a, d) => {
      ctx.moveTo(...a);
      ctx.lineTo(...d);
    };
    ctx.beginPath();
    for (const [i, v] of [
      [x0, y0],
      [x1, y0],
      [x1, y1],
      [x0, y1],
    ].entries())
      if (i === 0) ctx.moveTo(...floor(...v));
      else ctx.lineTo(...floor(...v));
    ctx.closePath();
    ctx.fillStyle = "#1c303e";
    ctx.fill();
    ctx.lineWidth = 1;
    ctx.strokeStyle = "#506674";
    ctx.stroke();
    for (const [tile] of replay.backends[b].occupancy) {
      const [x, y] = floor(tile % w, Math.floor(tile / w)),
        on = p.active.has(tile);
      ctx.fillStyle = on ? (b === "vivado" ? "#dba56d" : "#69bcba") : "#465a67";
      ctx.fillRect(x, y, on ? 2.3 : 1.15, on ? 2.3 : 1.15);
    }
    // Bus-wide DSP arcs can share a tile and times. Retain their pin records and
    // paint their common span once.
    const localGeometry = new Map();
    function stroke(edge, selected) {
      if (b === "openxc7" && edge.local && !selected) {
        const key =
          catalogs[b].tile[edge.a] + "/" + edge.start + "/" + edge.end;
        const existing = localGeometry.get(key);
        if (existing) {
          edge.screen = existing;
          return;
        }
        edge.screen = edge.points.map((q) => xy(...q));
        localGeometry.set(key, edge.screen);
      } else edge.screen = edge.points.map((q) => xy(...q));
      const late = Math.min(1, edge.end / p.top);
      ctx.strokeStyle = selected
        ? "#ffffff"
        : edge.local
          ? b === "vivado"
            ? "#ffe2b0"
            : "#a0f4e1"
          : b === "vivado"
            ? `hsl(${39 - 24 * late} 92% ${64 - 8 * late}%)`
            : `hsl(${172 + 31 * late} 71% ${66 - 8 * late}%)`;
      ctx.globalAlpha = selected ? 1 : edge.local ? 0.58 : 0.75;
      ctx.lineWidth = selected ? 3.4 : edge.local ? 1.05 : 1.25;
      if (
        edge.pinsOnly ||
        (b === "openxc7" && edge.dash && mode.value === "spans")
      ) {
        ctx.fillStyle = ctx.strokeStyle;
        for (const [x, y] of edge.screen)
          ctx.fillRect(x - 1.15, y - 1.15, 2.3, 2.3);
        if (edge.pinsOnly && !selected) return;
        if (!selected) ctx.globalAlpha = 0.28;
      }
      ctx.setLineDash(edge.dash ? [2.5, 2.5] : []);
      ctx.beginPath();
      edge.screen.forEach(([x, y], i) =>
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y),
      );
      ctx.stroke();
    }
    for (const edge of p.paths) stroke(edge, false);
    if (p.selection) stroke(p.selection, true);
    ctx.globalAlpha = 1;
    ctx.setLineDash([]);
    ctx.strokeStyle = "#a1bac8";
    ctx.fillStyle = "#d7e6ed";
    ctx.font = "11px ui-monospace, monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 1;
    const left = [
      [x0, y0],
      [x0, y1],
      [x1, y0],
      [x1, y1],
    ].sort((a, d) => floor(...a)[0] - floor(...d)[0])[0];
    ctx.beginPath();
    line(floor(...left), xy(...left, -height));
    const ticks = b === "vivado" ? 4 : 5;
    for (let i = 0; i <= ticks; i++) {
      const [x, y] = xy(...left, (-height * i) / ticks);
      line([x - 4, y], [x, y]);
      ctx.fillText(
        +((p.top * i) / ticks).toFixed(2) + (p.model.pairs ? " ns" : ""),
        x - 6,
        y,
      );
    }
    ctx.stroke();
  }

  /** Coalesce camera moves and paint the same orientation in both panels. */
  function redraw() {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = null;
      backends.forEach(draw);
    });
  }

  /** Inspect the closest visible line segment in CSS pixels. */
  function pick(b, x, y) {
    const p = panels[b];
    let best = 36,
      found = null;
    for (const edge of p.paths) {
      const points = edge.screen;
      if (!points) continue;
      if (edge.pinsOnly) {
        for (const [px, py] of points) {
          const distance = (px - x) ** 2 + (py - y) ** 2;
          if (distance < best) {
            best = distance;
            found = edge;
          }
        }
        continue;
      }
      for (let i = 1; i < points.length; i++) {
        const [ax, ay] = points[i - 1],
          dx = points[i][0] - ax,
          dy = points[i][1] - ay;
        const t = Math.max(
          0,
          Math.min(
            1,
            ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1),
          ),
        );
        const d = (x - ax - t * dx) ** 2 + (y - ay - t * dy) ** 2;
        if (d < best) {
          best = d;
          found = edge;
        }
      }
    }
    if (!found) return;
    p.selection = found;
    const { a, d, i, start, end } = found;
    const pair = p.model.pairs && p.model.ports[p.model.pairs[i]];
    const timing = p.model.pairs
      ? (b === "openxc7" ? "Estimated " : "") +
        start.toFixed(3) +
        " → " +
        end.toFixed(3) +
        " ns · " +
        (found.local
          ? "primitive arc"
          : found.dash
            ? b === "openxc7"
              ? "unrouted endpoint span"
              : "endpoint span"
            : found.switches
              ? found.switches + " switch-tile visits"
              : "direct connection")
      : "Depth " + start + " → " + end;
    p.article.querySelector(".flow-selection").textContent =
      timing +
      " · " +
      p.names[a] +
      (pair ? "/" + pair[0] : "") +
      " → " +
      p.names[d] +
      (pair ? "/" + pair[1] : "");
    redraw();
  }

  for (const b of backends) {
    const cv = panels[b].canvas;
    let drag;
    cv.onpointerdown = (e) => {
      cv.setPointerCapture(e.pointerId);
      drag = { x: e.clientX, y: e.clientY, distance: 0 };
    };
    cv.onpointermove = (e) => {
      if (!drag) return;
      const dx = e.clientX - drag.x,
        dy = e.clientY - drag.y;
      drag.distance += Math.hypot(dx, dy);
      drag.x = e.clientX;
      drag.y = e.clientY;
      camera = orbitCamera(camera, dx * 0.009, dy * 0.009);
      redraw();
    };
    cv.onpointerup = (e) => {
      if (drag && drag.distance < 4) pick(b, e.offsetX, e.offsetY);
      drag = null;
    };
    cv.onpointercancel = () => {
      drag = null;
    };
    cv.onwheel = (e) => {
      e.preventDefault();
      camera = zoomCamera(camera, Math.exp(-Math.sign(e.deltaY) * 0.12));
      redraw();
    };
    cv.onkeydown = (e) => {
      const moves = {
        ArrowLeft: [-0.1, 0],
        ArrowRight: [0.1, 0],
        ArrowUp: [0, 0.1],
        ArrowDown: [0, -0.1],
      };
      if (moves[e.key]) camera = orbitCamera(camera, ...moves[e.key]);
      else if (["+", "=", "-"].includes(e.key))
        camera = zoomCamera(camera, e.key === "-" ? 0.85 : 1.17);
      else return;
      e.preventDefault();
      redraw();
    };
  }
  mode.onchange = shared.onchange = () => {
    if (current) update(...current);
  };
  fit();
  document.getElementById("flow-fit").onclick = () => {
    fit();
    redraw();
  };
  return {
    update,
    resize: () => {
      fit();
      redraw();
    },
  };
}
