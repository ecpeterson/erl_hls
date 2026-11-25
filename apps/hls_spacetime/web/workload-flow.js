import {
  cameraMatrices,
  createCamera,
  fitCamera,
  orbitCamera,
  projectPoint,
  zoomCamera,
} from "./camera3d.js";

const format = (n) => n.toLocaleString("en-US");
const changed = (mask, i) => (mask[i >> 3] & (1 << i % 8)) !== 0;

/** Bind optional row-to-output mappings to their own settled replay and timing checkpoint. */
export function decodeOutputActivity(rows, changes, count, edges, cycles) {
  const stride = Math.ceil(count / 8);
  if (
    !Number.isInteger(count) ||
    count <= 0 ||
    count > 32767 ||
    rows.length !== edges * 2 ||
    changes.length !== cycles * stride
  )
    throw Error("Incomplete output activity");
  const lanes = new Int16Array(rows.buffer, rows.byteOffset, edges);
  if (lanes.some((lane) => lane < -1 || lane >= count))
    throw Error("Invalid output lane");
  return { lanes, changes, stride };
}

/** Validate the fixed-width edge rows and variable-length switch-tile lists before drawing. */
export function decodeFlow(
  bytes,
  cells,
  routes,
  count,
  tiles,
  pins,
  ports,
  physicalRoutes,
) {
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
  // The primary branch is packed with ordinary rows. Extra terminals share its logical SDF increment.
  const branches = new Map();
  for (const [key, paths] of Object.entries(physicalRoutes ?? {})) {
    const row = Number(key),
      offset = offsets[row],
      length = words[offset];
    if (
      String(row) !== key ||
      offset === undefined ||
      length === 65535 ||
      !Array.isArray(paths) ||
      !paths.length
    )
      throw Error("Invalid physical route row");
    const seen = new Set();
    branches.set(
      row,
      paths.map(({ sink, via, tiles: extra }, index) => {
        if (
          typeof sink !== "string" ||
          !sink ||
          seen.has(sink) ||
          (via !== undefined && typeof via !== "string")
        )
          throw Error("Invalid physical sink");
        seen.add(sink);
        const primary = index === 0;
        if (
          primary
            ? extra !== undefined
            : !Array.isArray(extra) ||
              extra.some((t) => !Number.isInteger(t) || t < 0 || t >= tiles)
        )
          throw Error("Invalid physical switch tiles");
        return {
          sink,
          via,
          tiles: primary
            ? words.subarray(offset + 1, offset + 1 + length)
            : extra,
        };
      }),
    );
  }
  return { ...model, offsets, words, branches };
}

/** Group observed changes with no outgoing timed net in this capture, before cycle filters. */
export function missingFlowDrivers(model, types, kinds, names, entire) {
  if (entire.length !== 2 * Math.ceil(types.length / 8))
    throw Error("Incomplete whole-replay mask");
  const drives = new Uint8Array(types.length);
  for (let i = 0; i < model.nets; i++)
    drives[model.data.getUint32(i * 16, true)] = 1;
  const groups = new Map();
  for (let i = 0; i < types.length; i++) {
    if (drives[i] || !changed(entire, i)) continue;
    const kind = kinds[types[i]];
    if (!groups.has(kind))
      groups.set(kind, { kind, count: 0, example: names[i] });
    groups.get(kind).count++;
  }
  return [...groups.values()].sort((a, b) => a.kind.localeCompare(b.kind));
}

/** Explain the captured timing population independently of the current clock and display filters. */
function showFlowCoverage(article, backend, timing, model, groups) {
  const details = article.querySelector(".flow-coverage"),
    summary = details.querySelector("summary");
  const note = (message) => {
    const p = document.createElement("p");
    p.textContent = message;
    details.append(p);
  };
  if (!timing) {
    summary.textContent = "Coverage · pin timing unavailable";
    note("This capture supplies placement and cell-pair logic depth.");
    return;
  }
  const total = timing.nonclockConnections ?? timing.dataConnections;
  summary.textContent =
    Number.isSafeInteger(total) && Number.isSafeInteger(model.nets)
      ? `Capture coverage · ${format(model.nets)} of ${format(total)} data connections timed`
      : "Coverage · total data connections unreported";
  if (backend === "openxc7") {
    note(
      model.offsets
        ? "One nextpnr delay estimate per timed connection. Independent fast and slow corners are unavailable."
        : "One placement-based delay estimate per timed connection. Routed switch geometry and independent timing corners are unavailable.",
    );
    if (timing.unreachedConnections !== undefined)
      note(
        `${format(timing.unreachedConnections)} connections lack a modeled launch.`,
      );
    if (timing.unobservedConnections !== undefined)
      note(
        `${format(timing.unobservedConnections)} additional connections lack a replay endpoint.`,
      );
  } else {
    note("Height uses the maximum delay in the captured Vivado SDF.");
    const omitted = total - model.nets;
    if (omitted > 0)
      note(`Connections without a modeled launch · ${format(omitted)}`);
  }
  if (model.offsets) {
    let missing = 0;
    for (const at of model.offsets) if (model.words[at] === 65535) missing++;
    note(
      `Of the timed connections, ${format(missing)} lack resolved branch geometry.`,
    );
  }
  note(
    timing.outputActivity
      ? `Activity is sampled on ${format(timing.outputActivity.count)} named output bits. Other rows use primitive-level changes.`
      : "Rows use whole-primitive changes. This capture has no per-output-bit activity masks.",
  );
  if (groups?.length) {
    note(
      "Changed primitives with no outgoing timed connection in this capture, including unconsumed outputs. One instance per type is listed.",
    );
    const list = document.createElement("ul");
    for (const { kind, count, example } of groups) {
      const item = document.createElement("li");
      item.textContent = `${kind} × ${format(count)} · ${example}`;
      list.append(item);
    }
    details.append(list);
  } else if (!groups) {
    note(
      "The capture lacks the data to compare timed drivers with whole-replay changes.",
    );
  }
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
  const backends = ["vivado", "openxc7"].filter((b) => replay.backends[b]);
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
  const routed = replay.flow.openxc7.routed;
  const nativeTiming = routed ?? replay.flow.openxc7.estimate;
  if (nativeTiming && nativeTiming.checkpoint !== replay.checkpoints.openxc7)
    throw Error("Native timing belongs to a different checkpoint");
  document.getElementById("native-modes").hidden = !nativeTiming;
  document.getElementById("shared-scale").hidden =
    !nativeTiming || !replay.backends.vivado;
  for (const option of mode.options) {
    option.hidden =
      option.value === "routes"
        ? !routed
        : !!routed && option.value !== "depth";
    option.disabled = option.hidden;
  }
  mode.value = routed ? "routes" : nativeTiming ? "pins" : "depth";
  if (routed) {
    document.getElementById("native-flow-guide").textContent =
      "openXC7 lines follow each sink’s switch tiles on the routed checkpoint. Select a line for its pins and delay source. " +
      (routed.routedLutTiming
        ? "Height accumulates nextpnr’s post-route SDF using the bound switches for resolved LUT input permutations."
        : "Height accumulates nextpnr’s post-route SDF, including placement estimates for permuted LUT inputs.");
  }
  const vendorLane = replay.flow.vivado?.stateLane;
  if (replay.selectedPath && routed && (backends.length === 1 || vendorLane)) {
    const filter = document.getElementById("flow-filter");
    filter.add(new Option("State RAM → capture D", "ram-stage"));
    filter.add(new Option("Capture Q → DSP input", "dsp-stage"));
  }
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
        info.physicalRoutes,
      );
      let pinModel;
      if (b === "openxc7" && nativeTiming) {
        const [timed, pins, routeBytes, classes] = await Promise.all([
          asset(nativeTiming.edges),
          asset(nativeTiming.pins),
          routed && asset(routed.routes),
          routed && asset(routed.delayClass),
        ]);
        pinModel = decodeFlow(
          timed,
          catalogs[b].tile.length,
          routeBytes,
          nativeTiming.timedConnections,
          w * h,
          pins,
          nativeTiming.ports,
        );
        if (
          pinModel.rows !==
          nativeTiming.timedConnections + nativeTiming.timedCellArcs
        )
          throw Error("Incomplete native timing inventory");
        pinModel.registeredProducts = new Set(nativeTiming.registeredProducts);
        if (routed) {
          if (
            classes.length !== pinModel.nets ||
            classes.some(
              (v, i) =>
                v > 2 ||
                (v === 2) !== (pinModel.words[pinModel.offsets[i]] === 65535),
            )
          )
            throw Error("Route classes disagree with native geometry");
          pinModel.classes = classes;
          if (routed.switchSumPs) {
            const bytes = await asset(routed.switchSumPs);
            if (bytes.length !== 4 * pinModel.nets)
              throw Error("Incomplete native switch-delay sums");
            pinModel.switchPs = new DataView(
              bytes.buffer,
              bytes.byteOffset,
              bytes.byteLength,
            );
          }
        }
      }
      const timing = b === "vivado" ? info : nativeTiming;
      const activity = timing?.outputActivity;
      if (activity) {
        if (activity.checkpoint !== replay.checkpoints[b])
          throw Error("Output activity belongs to a different checkpoint");
        const [rows, changes] = await Promise.all([
          asset(activity.rows),
          asset(activity.changes),
        ]);
        const selected = b === "vivado" ? model : pinModel;
        selected.activity = decodeOutputActivity(
          rows,
          changes,
          activity.count,
          selected.rows,
          replay.cycles,
        );
      }
      const cellNames = new TextDecoder().decode(names).split("\n");
      const timedModel = b === "vivado" ? model : pinModel;
      let groups;
      if (timedModel?.pairs && replay.backends[b].entire) {
        catalogs[b].entire ??= asset(replay.backends[b].entire);
        groups = missingFlowDrivers(
          timedModel,
          catalogs[b].type,
          replay.backends[b].kinds,
          cellNames,
          await catalogs[b].entire,
        );
      }
      showFlowCoverage(article, b, timing, timedModel, groups);
      if (info.siteMuxes) model.siteMuxes = info.siteMuxes;
      const top =
        b === "vivado"
          ? Math.ceil(Math.max(model.top, replay.period) / 5) * 5
          : Math.ceil(model.top / 5) * 5;
      panels[b] = {
        article,
        canvas: article.querySelector("canvas"),
        model,
        base: model,
        pinModel,
        baseTop: top,
        top,
        names: cellNames,
        paths: [],
        selection: null,
        active: new Set(),
      };
    }),
  );

  /** Fit against the shared chip box; changes of clock preserve the camera. */
  function fit() {
    const cv = panels[backends[0]].canvas;
    camera = fitCamera(
      createCamera({ yaw: 0.84, pitch: 0.41 }),
      bounds,
      { width: cv.clientWidth, height: cv.clientHeight },
      { padding: 1.07 },
    );
  }

  /** Interpolate modeled pin times along the occupied tiles on one directed branch. */
  function projectTimes(t, start, end, top) {
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
      points[k][2] = (-(start + f * (end - start)) * height) / top;
    }
    return points;
  }

  /** Draw the selected state lane up to a register or from that register's clock pin to the DSP. */
  function showStage(panel, key, cycle) {
    const { steps } = replay.selectedPath,
      branches = routed.selected;
    const boundary = steps.findIndex((s) => s.kind === "SLICE_FFX");
    const first = key === "ram-stage" ? 0 : boundary;
    const last = key === "ram-stage" ? boundary : branches.length;
    const durationPs = branches
      .slice(first, last)
      .reduce((ps, b) => ps + b.cellPs + b.netPs, 0);
    panel.top = Math.max(1, Math.ceil(durationPs / 1000));
    let ns = 0,
      visits = 0;
    for (let j = first; j < last; j++) {
      const a = steps[j],
        d = steps[j + 1],
        branch = branches[j];
      const output = ns + branch.cellPs / 1000,
        end = output + branch.netPs / 1000;
      const line = (tiles, start, end, local, label) => ({
        points: projectTimes(tiles, start, end, panel.top),
        local,
        start,
        end,
        label,
        sourceTile: a.tile,
        dash: !local && branch.tiles === null,
      });
      panel.active.add(a.tile);
      panel.active.add(d.tile);
      panel.paths.push(
        line(
          [a.tile, a.tile],
          ns,
          output,
          true,
          a.cell + "/" + branch.cellInput + " → " + a.cell + "/" + a.output,
        ),
      );
      const tiles = [a.tile, ...(branch.tiles ?? []), d.tile].filter(
        (v, i, all) => !i || v !== all[i - 1],
      );
      if (tiles.length === 1) tiles.push(d.tile);
      visits += branch.tiles?.length ?? 0;
      panel.paths.push(
        line(
          tiles,
          output,
          end,
          false,
          a.cell +
            "/" +
            a.output +
            " → " +
            d.cell +
            "/" +
            d.input +
            " · " +
            branch.status +
            " · " +
            (branch.tiles?.length ?? 0) +
            " switch visits",
        ),
      );
      ns = end;
    }
    const name =
      key === "ram-stage"
        ? "RAM clock → capture D"
        : "Capture clock → DSP operand";
    panel.article.querySelector(".stat").textContent =
      name + " · " + ns.toFixed(3) + " ns · " + visits + " switch visits";
    stageActivity(panel, cycle, replay.selectedPath.transitions);
  }

  /** Report only observed known-to-known changes at the three individually sampled pins. */
  function stageActivity(panel, cycle, transitions) {
    const labels = { ram: "RAM output", q: "capture Q", dsp: "DSP operand" };
    const changed = Object.entries(transitions)
      .filter(([, clocks]) => clocks.includes(cycle))
      .map(([pin]) => labels[pin]);
    panel.article.querySelector(".flow-selection").textContent =
      "Static bit-" +
      replay.selectedPath.bit +
      " path · C" +
      cycle +
      (changed.length
        ? " changed at " + changed.join(", ")
        : " had no known change at the three probed pins") +
      ".";
  }

  /** Project each physical sink branch with the one logical SDF row's start and end times. */
  function paths(b, i, a, d, start, end) {
    const p = panels[b],
      m = p.model,
      tile = catalogs[b].tile;
    const local = m.nets !== undefined && i >= m.nets;
    const at = m.offsets && !local ? m.offsets[i] : undefined;
    const count = at === undefined ? undefined : m.words[at];
    const branches = m.branches?.get(i);
    function project(switches, physical) {
      const t = [tile[a]];
      for (const v of switches ?? []) if (v !== t.at(-1)) t.push(v);
      if (t.at(-1) !== tile[d] || t.length === 1) t.push(tile[d]);
      return {
        i,
        a,
        d,
        start,
        end,
        points: projectTimes(t, start, end, p.top),
        dash: !local && switches === undefined,
        pinsOnly: b === "openxc7" && !local && mode.value === "pins",
        local,
        switches: switches?.length ?? null,
        physical,
      };
    }
    if (branches) {
      // Distinct physical pins can occupy the same tile sequence at this zoom level.
      const groups = new Map();
      for (const branch of branches) {
        const key = branch.tiles.join(" ");
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(branch);
      }
      return [...groups.values()].map((group) =>
        project(group[0].tiles, group),
      );
    }
    return [
      project(
        count === undefined || count === 65535
          ? undefined
          : m.words.subarray(at + 1, at + 1 + count),
      ),
    ];
  }

  /** Draw one Vivado clock segment from the indexed SDF arcs and its own routed switch list. */
  function showVendorStage(panel, rows, cycle) {
    const m = panel.model;
    let elapsed = 0,
      visits = 0,
      missing = 0,
      muxes = 0;
    const delays = rows.map(
      (i) =>
        m.data.getFloat32(i * 16 + 12, true) -
        m.data.getFloat32(i * 16 + 8, true),
    );
    panel.top = Math.max(1, Math.ceil(delays.reduce((a, b) => a + b, 0)));
    for (const [j, i] of rows.entries()) {
      const a = m.data.getUint32(i * 16, true),
        d = m.data.getUint32(i * 16 + 4, true);
      const edges = paths("vivado", i, a, d, elapsed, elapsed + delays[j]);
      panel.active.add(catalogs.vivado.tile[a]);
      panel.active.add(catalogs.vivado.tile[d]);
      if (edges[0].dash) missing++;
      if (m.siteMuxes?.[i]) muxes++;
      for (const edge of edges) visits += edge.switches ?? 0;
      panel.paths.push(...edges);
      elapsed += delays[j];
    }
    const name =
      rows === vendorLane.segments[0]
        ? "RAM clock → capture D"
        : "Capture clock → DSP operand";
    panel.article.querySelector(".stat").textContent =
      name +
      " · " +
      elapsed.toFixed(3) +
      " ns · " +
      visits +
      " switch-tile visits" +
      (muxes ? ` · ${muxes} site mux${muxes === 1 ? "" : "es"}` : "") +
      (missing
        ? ` · ${missing} unresolved branch${missing === 1 ? "" : "es"}`
        : "");
    stageActivity(panel, cycle, vendorLane.transitions);
  }

  /** Join the one-clock known-change bits to both endpoints or to the driver alone. */
  function update(cycle, masks, filter) {
    current = [cycle, masks, filter];
    const stage = filter === "ram-stage" || filter === "dsp-stage";
    mode.disabled = stage;
    if (stage) mode.value = "routes";
    const timed = !!nativeTiming && mode.value !== "depth";
    shared.disabled = !timed;
    const vendor = panels.vivado,
      native = panels.openxc7;
    native.model = timed ? native.pinModel : native.base;
    native.top = timed
      ? 5 * Math.ceil(Math.max(native.model.top, replay.period) / 5)
      : native.baseTop;
    if (vendor) {
      vendor.top = vendor.baseTop;
      if (timed && !stage && shared.checked)
        native.top = vendor.top = Math.max(native.top, vendor.top);
    }
    native.article.querySelector(".map-head span").textContent = timed
      ? routed
        ? "Routed SDF · single delay estimate · ns"
        : "Placement estimate · ns"
      : "Placed · logic depth";
    for (const [index, b] of backends.entries()) {
      const p = panels[b],
        m = p.model,
        tile = catalogs[b].tile,
        mask = masks[index];
      p.active = new Set();
      p.paths = [];
      p.selection = null;
      if (stage) {
        if (b === "vivado")
          showVendorStage(
            p,
            vendorLane.segments[filter === "ram-stage" ? 0 : 1],
            cycle,
          );
        else showStage(p, filter, cycle);
        continue;
      }
      for (let i = 0; i < tile.length; i++)
        if (tile[i] >= 0 && changed(mask, i)) p.active.add(tile[i]);
      let nets = 0,
        local = 0;
      const activity = m.activity;
      const laneMask = activity?.changes.subarray(
        cycle * activity.stride,
        (cycle + 1) * activity.stride,
      );
      for (let i = 0; i < m.rows; i++) {
        const a = m.data.getUint32(i * 16, true),
          d = m.data.getUint32(i * 16 + 4, true);
        if (
          !changed(mask, a) ||
          (activity &&
            activity.lanes[i] >= 0 &&
            !changed(laneMask, activity.lanes[i])) ||
          (filter === "both" && !changed(mask, d)) ||
          tile[a] < 0 ||
          tile[d] < 0
        )
          continue;
        const edges = paths(
          b,
          i,
          a,
          d,
          m.data.getFloat32(i * 16 + 8, true),
          m.data.getFloat32(i * 16 + 12, true),
        );
        p.paths.push(...edges);
        if (edges[0].local) local++;
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
            ? (routed
                ? " pin connections · "
                : " estimated pin connections · ") +
              format(local) +
              " cell arcs"
            : " connected cell pairs") +
        (activity ? " · observed output bits where available" : "");
      p.article.querySelector(".flow-selection").textContent =
        nets || local
          ? b === "vivado" || (routed && timed)
            ? "Switch tiles and primitive arcs · height in nanoseconds"
            : timed
              ? mode.value === "pins"
                ? "Select a placed pin to reveal its endpoint connection."
                : "Dashed spans connect placed pins. Wire routes are unknown."
              : "Schematic cell pairs · height in combinational levels"
          : "No connections match the activity filter at this clock.";
    }
    if (stage && vendor && shared.checked) {
      const top = Math.max(native.top, vendor.top);
      for (const panel of [native, vendor]) {
        for (const edge of panel.paths)
          for (const point of edge.points) point[2] *= panel.top / top;
        panel.top = top;
      }
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
          (edge.sourceTile ?? catalogs[b].tile[edge.a]) +
          "/" +
          edge.start +
          "/" +
          edge.end;
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
    if (found.label) {
      p.article.querySelector(".flow-selection").textContent =
        found.start.toFixed(3) +
        " → " +
        found.end.toFixed(3) +
        " ns · " +
        found.label;
      redraw();
      return;
    }
    const { a, d, i, start, end } = found;
    const pair = p.model.pairs && p.model.ports[p.model.pairs[i]];
    const timing = p.model.pairs
      ? (b === "openxc7" && !routed ? "Estimated " : "") +
        start.toFixed(3) +
        " → " +
        end.toFixed(3) +
        " ns · " +
        (found.local
          ? p.model.registeredProducts?.has(a) && pair[0] === "CLK"
            ? "PREG launch · MREG feeds PREG across a clock edge"
            : "primitive arc"
          : found.dash
            ? b === "openxc7" && !routed
              ? "unrouted endpoint span"
              : "endpoint span"
            : found.switches
              ? found.switches + " switch-tile visits"
              : (p.model.siteMuxes?.[i] ?? "direct connection"))
      : "Depth " + start + " → " + end;
    p.article.querySelector(".flow-selection").textContent =
      timing +
      (found.physical
        ? " · " +
          found.physical
            .map(({ sink, via }) => sink + (via ? " via " + via : ""))
            .join(", ") +
          (p.model.branches.get(i).length > 1
            ? " · one logical SDF delay for " +
              p.model.branches.get(i).length +
              " physical pins"
            : "")
        : "") +
      (p.model.classes && !found.local
        ? " · " +
          [
            "routed wire delay",
            routed.routedLutTiming
              ? "permuted LUT input · routed wire delay"
              : "permuted LUT input · predicted wire delay",
            "unresolved wire delay",
          ][p.model.classes[i]]
        : "") +
      (p.model.switchPs && !found.local
        ? " · SDF " +
          (end - start).toFixed(3) +
          " ns · traced switch sum " +
          (p.model.switchPs.getUint32(i * 4, true) / 1000).toFixed(3) +
          " ns"
        : "") +
      " · " +
      p.names[a] +
      (pair ? "/" + pair[0] : "") +
      " → " +
      p.names[d] +
      (pair ? "/" + pair[1] : "") +
      (p.model.activity?.lanes[i] >= 0
        ? " · sampled output bit changed"
        : " · primitive-level activity");
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
