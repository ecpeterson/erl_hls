import test from "node:test";
import assert from "node:assert/strict";
import { createPathExplorer, CUT_COLORS } from "../web/path-explorer.js";
import { sinkRows } from "../web/sink-paths.js";

// Only the DOM surface used by controller transitions; geometry is tested separately.
function controls(t) {
  const previous = globalThis.document;
  const nodes = new Map();
  const node = (id) => {
    if (!nodes.has(id))
      nodes.set(id, {
        value: "",
        max: "",
        checked: id != "cut-full-graph",
        innerHTML: "",
        textContent: "",
        hidden: false,
        disabled: false,
        reported: false,
        checkValidity() {
          const value = Number(this.value);
          return (
            this.value !== "" &&
            Number.isFinite(value) &&
            value >= 0 &&
            (this.max === "" || value <= Number(this.max))
          );
        },
        reportValidity() {
          this.reported = true;
          return false;
        },
      });
    return nodes.get(id);
  };
  globalThis.document = { getElementById: node };
  t.after(() => {
    globalThis.document = previous;
  });
  return node;
}

/** Two sinks share a reconvergent prefix; remote/unlocated fanout remains outside
 * the visible cones. Arrivals are hand-calculated for this small native graph. */
function fixture({
  scale = 1,
  sideKind = "sequential",
  constantSide = false,
  alternate = false,
} = {}) {
  const pinGeometry = [
    [0, 0, 0, "launch/Q"],
    [1, 1, 0, "a/I"],
    [1, 2, 0, "a/O"],
    [2, 3, 0, "b/I0"],
    [2, 3, 1, "b/I1"],
    [2, 4, 0, "b/O"],
    [3, 5, 0, "sink-a/D"],
    [4, 0, 1, "side/Q"],
    [5, 5, 1, "sink-b/D"],
    [6, 90, 0, "remote/D"],
    [7, null, null, "unlocated/D"],
  ];
  const arcGeometry = [
    [0, 1, 0, 0.2],
    [1, 2, 1, 1],
    [2, 3, 0, 0.3],
    [7, 4, 0, 1],
    [3, 5, 1, 0.8],
    [4, 5, 1, 0.4],
    [5, 6, 0, 0.2],
    [5, 8, 0, 0.15],
    [5, 9, 0, 0.1],
    [5, 10, 0, null],
  ].map(([from, to, kind, cost]) => [
    from,
    to,
    kind,
    cost === null ? null : cost * scale,
  ]);
  const values = [0, 0.2, 1.2, 1.5, 1, 2.3, 2.5, 0, 2.45].map((n) => n * scale);
  const cone = {
    id: "data/6,8",
    role: "data",
    rootPins: [6, 8],
    pinIndices: Array.from({ length: 9 }, (_, i) => i),
    arcIndices: Array.from({ length: 8 }, (_, i) => i),
    frontiers: [
      { pin: 0, kind: "sequential" },
      { pin: 7, kind: sideKind },
    ],
    pinArrivals: { registered: [...values], static: [...values] },
    coverage: { cyclic: false, unsupportedFrontiers: 0, missingTiming: 0 },
  };
  if (sideKind !== "sequential")
    for (const pin of [4, 7])
      cone.pinArrivals.registered[pin] = "not_applicable";
  if (constantSide) {
    pinGeometry.push([8, 2, 1, "constant/P"], [2, 3, 2, "b/I2"]);
    cone.pinIndices.push(11, 12);
    cone.arcIndices.push(arcGeometry.length, arcGeometry.length + 1);
    arcGeometry.push([11, 12, 0, 0.1 * scale], [12, 5, 1, 0.2 * scale]);
    cone.frontiers.push({ pin: 11, kind: "constant" });
    cone.pinArrivals.registered.push("not_applicable", "not_applicable");
    cone.pinArrivals.static.push(0, 0.1 * scale);
  }
  const cells = [
    ["launch", 0, 0],
    ["a", 1, 0],
    ["b", 3, 0],
    ["sink-a", 5, 0],
    ["side", 0, 1],
    ["sink-b", 5, 1],
    ["remote", 90, 0],
    ["unlocated", null, null],
    ["constant", 2, 1],
    ["context", 4, 1],
  ].map(([id, x, y]) => ({
    id,
    x,
    y,
    kind: ["a", "b"].includes(id) ? "LUT2" : "FDRE",
  }));
  const index = {
    pinGeometry,
    arcGeometry,
    cones: [cone],
    writes: new Map(),
    model: { catalogue: { cells }, events: new Map() },
  };
  const layers = [{ cycle: 3, cones: [cone], operations: [] }];
  let alternateLayers = null;
  if (alternate) {
    const id = arcGeometry.length;
    arcGeometry.push([0, 6, 0, 2.5 * scale]);
    const other = {
      ...cone,
      id: "alternate",
      rootPins: [6],
      pinIndices: [0, 6],
      arcIndices: [id],
      frontiers: [{ pin: 0, kind: "sequential" }],
      pinArrivals: { registered: [0, 2.5 * scale], static: [0, 2.5 * scale] },
    };
    index.cones.push(other);
    alternateLayers = [{ cycle: 4, cones: [other], operations: [] }];
  }
  const sink = sinkRows(index, layers).find((row) => row.pin === 6);
  return { index, layers, sink, alternateLayers };
}
const update = (panel, f, mode, extra = {}) =>
  panel.update(f.index, f.layers, f.sink, {
    scope: "registered",
    mode,
    ...extra,
  });
const clickData = (data, selector) => ({
  target: {
    closest: (query) => (query === selector ? { dataset: data } : null),
  },
});

test("view modes and removed sinks cannot leak analysis selection into other scenes", (t) => {
  const node = controls(t),
    f = fixture();
  const panel = createPathExplorer(
    () => {},
    () => {},
  );
  update(panel, f, "neighborhood");
  assert.equal(node("path-neighborhood").hidden, false);
  assert.equal(node("path-cut").hidden, true);
  assert.ok(panel.selection.size > 0);
  node("family-driver").value = "5";
  node("family-driver").onchange();
  update(panel, f, "neighborhood");
  assert.equal(panel.driverPin, 5);
  update(panel, f, "cut");
  assert.equal(panel.neighborhood, null);
  assert.equal(node("path-neighborhood").hidden, true);
  assert.equal(node("path-cut").hidden, false);
  assert.equal(panel.cut.status, "known");
  update(panel, f, "cut", { enabled: false });
  assert.equal(panel.mode, "all");
  assert.equal(panel.selection, null);
  assert.equal(panel.cut, null);
  assert.equal(panel.shade({ arcIds: [0] }, "fallback"), "fallback");
  panel.update(f.index, [], null, {
    scope: "registered",
    mode: "neighborhood",
  });
  assert.equal(panel.selection.size, 0);
  assert.equal(panel.driverPin, null);
  assert.equal(panel.cutPin, null);
  assert.match(node("family-summary").textContent, /known selected path/);
});

test("the full graph toggle changes display selection without narrowing the cut analysis", (t) => {
  const node = controls(t),
    f = fixture();
  let changes = 0;
  const panel = createPathExplorer(
    () => changes++,
    () => {},
  );
  update(panel, f, "cut");
  const cut = panel.cut;
  const displayed = () =>
    [...panel.selection.values()].flatMap((row) => [...row.arcIds]);
  assert.equal(node("cut-full-graph").checked, false);
  assert.equal(
    displayed().includes(3),
    false,
    "side launch is off the representative chain",
  );
  assert.equal(
    cut.selection.get("data/6,8").arcIds.has(3),
    true,
    "analysis includes the side launch",
  );
  node("cut-full-graph").checked = true;
  node("cut-full-graph").onchange();
  update(panel, f, "cut");
  assert.equal(changes, 1);
  assert.equal(panel.cut, cut);
  assert.deepEqual(panel.selection, cut.selection);
  node("cut-full-graph").checked = false;
  node("cut-full-graph").onchange();
  update(panel, f, "cut");
  assert.equal(displayed().includes(3), false);
  assert.equal(panel.cut, cut);
});

test("a new index resets proposed threshold and pin even when the sink key is equal", (t) => {
  const node = controls(t),
    f = fixture(),
    replacement = fixture({ scale: 2 });
  const panel = createPathExplorer(
    () => {},
    () => {},
  );
  assert.equal(f.sink.key, replacement.sink.key);
  update(panel, f, "cut");
  node("cut-time").value = "1.9";
  node("cut-time").onchange();
  update(panel, f, "cut");
  node("cut-list").onclick(clickData({ cutPin: "2" }, "[data-cut-pin]"));
  update(panel, f, "cut");
  assert.equal(panel.cutPin, 2);
  assert.equal(panel.cut.thresholdNs, 1.9);
  update(panel, replacement, "cut");
  assert.equal(panel.cutPin, null);
  assert.equal(panel.cut.thresholdNs, 2.5);
  assert.equal(node("cut-time").value, "2.5");
  update(panel, replacement, "neighborhood");
  node("family-driver").value = "5";
  node("family-driver").onchange();
  update(panel, replacement, "neighborhood");
  update(panel, f, "neighborhood");
  assert.equal(panel.driverPin, null);
});

test("invalid numeric edits keep the prior model and do not request recomputation", (t) => {
  const node = controls(t),
    f = fixture();
  let changes = 0;
  const panel = createPathExplorer(
    () => changes++,
    () => {},
  );
  update(panel, f, "cut");
  const original = panel.cut;
  for (const [id, value] of [
    ["cut-time", "-1"],
    ["cut-time", "3"],
    ["family-margin", ""],
    ["family-padding", "bad"],
  ]) {
    node(id).value = value;
    node(id).onchange();
    assert.equal(node(id).reported, true);
    assert.equal(changes, 0);
    update(panel, f, "cut");
    assert.equal(panel.cut, original);
  }
  node("cut-time").value = "0.5";
  node("cut-time").onchange();
  assert.equal(changes, 1);
  update(panel, f, "cut");
  assert.equal(panel.cut.thresholdNs, 0.5);
  assert.notEqual(panel.cut, original);
});

test("cut shading uses native arc membership and exposes side-input limits", (t) => {
  const node = controls(t),
    f = fixture({ sideKind: "external", constantSide: true });
  const panel = createPathExplorer(
    () => {},
    () => {},
  );
  update(panel, f, "cut");
  assert.equal(panel.cut.status, "known");
  assert.equal(panel.shade({ arcIds: [1] }, "fallback"), CUT_COLORS.before);
  assert.equal(panel.shade({ arcIds: [2] }, "fallback"), CUT_COLORS.after);
  assert.equal(panel.shade({ arcIds: [1, 2] }, "fallback"), CUT_COLORS.mixed);
  assert.equal(panel.shade({ arcIds: [999] }, "fallback"), "fallback");
  assert.match(
    node("cut-side-inputs").textContent,
    /1 external and 1 constant/,
  );
  assert.match(
    node("cut-side-inputs").textContent,
    /1 external inputs feeding stage 2 still need alignment/,
  );
  assert.match(
    node("cut-limits").textContent,
    /achieved clock period are unknown/,
  );
  assert.match(node("cut-summary").textContent, /register|storage/);
  assert.match(node("cut-bars").innerHTML, /Stage 1/);
  update(panel, f, "all");
  assert.equal(panel.shade({ arcIds: [1] }, "fallback"), "fallback");
});

test("family fanout selection clears when the visible path population changes", (t) => {
  const node = controls(t),
    f = fixture({ alternate: true });
  const selected = [];
  let changes = 0;
  const panel = createPathExplorer(
    () => changes++,
    (key) => selected.push(key),
  );
  update(panel, f, "neighborhood");
  assert.equal(panel.neighborhood.members.length, 2);
  node("family-driver").value = "5";
  node("family-driver").onchange();
  update(panel, f, "neighborhood");
  assert.equal(panel.driverPin, 5);
  assert.match(
    node("family-driver-summary").textContent,
    /4 represented sink pins/,
  );
  assert.match(
    node("family-driver-summary").textContent,
    /1 outside the region, 1 unlocated/,
  );
  node("family-list").onclick(clickData({ sink: "data/8" }, "[data-sink]"));
  assert.deepEqual(selected, ["data/8"]);
  node("family-context").checked = false;
  node("family-context").onchange();
  assert.equal(panel.showContext, false);
  assert.equal(changes, 2);
  const sink = sinkRows(f.index, f.alternateLayers).find(
    (row) => row.pin === 6,
  );
  assert.equal(sink.key, f.sink.key);
  panel.update(f.index, f.alternateLayers, sink, {
    scope: "registered",
    mode: "neighborhood",
  });
  assert.equal(panel.driverPin, null);
  assert.equal(node("family-driver").value, "");
  assert.equal(panel.neighborhood.members.length, 1);
  assert.match(node("family-driver-summary").textContent, /Choose a driver/);
});

test("cut pin selection toggles and unknown estimates do not retain stage shading", (t) => {
  const node = controls(t),
    f = fixture();
  const panel = createPathExplorer(
    () => {},
    () => {},
  );
  update(panel, f, "cut");
  node("cut-list").onclick(clickData({ cutPin: "2" }, "[data-cut-pin]"));
  update(panel, f, "cut");
  assert.equal(panel.cutPin, 2);
  assert.match(node("cut-list").innerHTML, /aria-pressed="true"/);
  node("cut-list").onclick(clickData({ cutPin: "2" }, "[data-cut-pin]"));
  update(panel, f, "cut");
  assert.equal(panel.cutPin, null);
  const unknown = fixture();
  unknown.index.arcGeometry[0][3] = null;
  unknown.index.cones[0].pinArrivals.registered[6] = null;
  unknown.sink = sinkRows(unknown.index, unknown.layers).find(
    (row) => row.pin === 6,
  );
  update(panel, unknown, "cut");
  assert.equal(panel.cut.status, "unknown");
  assert.equal(panel.shade({ arcIds: [1] }, "fallback"), "fallback");
  assert.equal(node("cut-bars").innerHTML, "");
  assert.equal(node("cut-time").disabled, true);
  assert.match(node("cut-summary").textContent, /unavailable/);
});
