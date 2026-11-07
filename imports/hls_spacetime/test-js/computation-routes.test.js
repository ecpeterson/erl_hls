import test from "node:test";
import assert from "node:assert/strict";
import {
  createComputations,
  computationLayers,
  computationConnection,
} from "../web/computation-routes.js";

/** Reconvergent two-input logic, three writes, one semantic producer and a read.
 * Only one of two logical bits has a qualified native destination. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o" };
  const cells = [
    { id: "source", kind: "FDRE", boundary: "sequential" },
    { id: "lut", kind: "LUT2", boundary: "combinational" },
    { id: "sink", kind: "FDRE", boundary: "sequential" },
    { id: "constant", kind: "VCC", boundary: "constant" },
  ];
  const pins = [
    { id: "source/Q", cell: 0, pin: "Q", direction: "OUT", net: 0 },
    { id: "lut/I0", cell: 1, pin: "I0", direction: "IN", net: 0 },
    { id: "lut/I1", cell: 1, pin: "I1", direction: "IN", net: 0 },
    { id: "lut/O", cell: 1, pin: "O", direction: "OUT", net: 1 },
    { id: "sink/D", cell: 2, pin: "D", direction: "IN", net: 1 },
    { id: "sink/CE", cell: 2, pin: "CE", direction: "IN", net: 2 },
    { id: "constant/P", cell: 3, pin: "P", direction: "OUT", net: 2 },
    { id: "sink/R", cell: 2, pin: "R", direction: "IN", net: 2 },
    { id: "sink/Q", cell: 2, pin: "Q", direction: "OUT", net: 3 },
  ];
  const timing = (ps) => ({
    fast: [{ maxPs: ps / 2, guards: [] }],
    slow: [{ maxPs: ps, guards: [] }],
  });
  const arcs = [
    { id: "n0a", kind: "net", from: 0, to: 1, net: 0, timing: timing(100) },
    { id: "n0b", kind: "net", from: 0, to: 2, net: 0, timing: timing(100) },
    { id: "logic0", kind: "logic", from: 1, to: 3, timing: timing(300) },
    { id: "logic1", kind: "logic", from: 2, to: 3, timing: timing(500) },
    { id: "n1", kind: "net", from: 3, to: 4, net: 1, timing: timing(400) },
    { id: "enable", kind: "net", from: 6, to: 5, net: 2, timing: timing(200) },
    { id: "reset", kind: "net", from: 6, to: 7, net: 2, timing: timing(200) },
  ];
  const events = new Map([
    ...["w0", "w1", "w2"].map((id, i) => [
      id,
      {
        id,
        cycle: i === 2 ? 6 : 5,
        access: { kind: "write", resource: "word", mask: "0x3" },
      },
    ]),
    ["producer", { id: "producer", cycle: 5 }],
    ["read", { id: "read", cycle: 4 }],
  ]);
  const operations = [...events.values()].map((event) => ({
    event: event.id,
    kind: event.access ? "register_write" : event.id,
    applicability: event.access ? "storage_write" : "semantic_context",
    status: "partial",
    targets: event.access ? [{ resource: "word", mask: "0x3" }] : [],
    sources: [],
    unknowns: [],
    writes: event.id === "producer" ? ["w0", "w1"] : [],
  }));
  const attachment = {
    schema: 1,
    scope: "structural_native_connectivity",
    build,
    checkpoint: "c",
    cells,
    pins,
    nets: [0, 1, 2, 3].map((n) => ({ id: `n${n}` })),
    arcs,
    bindings: [
      {
        resource: "word",
        bits: [
          { bit: 0, status: "supported", q: 8, d: 4, ce: 5, reset: 7 },
          { bit: 1, status: "unknown" },
        ],
      },
    ],
    operations,
  };
  const model = {
    bundle: { build },
    catalogue: { checkpoint: "c" },
    cells: new Map(cells.map((cell) => [cell.id, cell])),
    resources: new Map([["word", { id: "word", width: 2 }]]),
    events,
  };
  return { model, attachment };
}

/** A native branch uses explicit assigned PIPs and exact endpoint attachment. */
function route() {
  return {
    id: "n1",
    status: "complete",
    route_status: "ROUTED",
    issues: [],
    nodes: ["a", "b"].map((id, i) => ({
      id,
      wires: [{ id: `wire-${id}`, tile: `tile-${i}`, x: i, y: 0 }],
    })),
    pips: [
      {
        id: "pip",
        tile: "tile-0",
        x: 0,
        y: 0,
        from_node: "a",
        to_node: "b",
        direction_status: "directional",
      },
    ],
    pin_attachments: [
      ["lut/O", "OUT", "a"],
      ["sink/D", "IN", "b"],
    ].map(([pin, direction, node]) => ({
      pin,
      direction,
      status: "resolved",
      bel_pins: [pin],
      routing_node: node,
      site_pins: [{ id: `site-${node}`, node }],
    })),
  };
}

test("full event coverage and write destinations reconcile before any drawing", () => {
  const { model, attachment } = fixture();
  assert.equal(createComputations(model, attachment).operations.size, 5);
  for (const mutate of [
    (a) => a.operations.pop(),
    (a) => {
      a.operations[0].event = "read";
    },
    (a) => {
      a.operations[0].targets[0].mask = "0x1";
    },
    (a) => {
      a.build.rtl = "stale";
    },
    (a) => {
      a.arcs[0].net = 3;
    },
    (a) => {
      a.pins[0].cell = 999;
    },
    (a) => {
      a.bindings[0].bits[0].d = 1;
    },
    (a) => {
      a.bindings[0].bits.pop();
    },
    (a) => {
      a.arcs[0].from = 1;
    },
  ]) {
    const copy = structuredClone(attachment);
    mutate(copy);
    assert.throws(() => createComputations(model, copy), /Computation routes:/);
  }
});

test("reconvergent cones and clock unions share geometry without path enumeration", () => {
  const { model, attachment } = fixture(),
    index = createComputations(model, attachment);
  const layers = computationLayers(index, [...model.events.values()], {
    roles: ["data"],
  });
  assert.deepEqual(
    layers.map((layer) => layer.cycle),
    [5, 6],
  );
  assert.equal(layers[0].operations.length, 2);
  assert.equal(layers[0].cones.length, 1);
  assert.equal(layers[0].arcs.length, 5);
  assert.equal(layers[0].cones[0].staticDelayNs, 1);
  assert.equal(layers[0].cones[0], layers[1].cones[0]);
  assert.equal(index.cones.size, 3);
  assert.deepEqual(layers[0].coverage, {
    requestedBits: 4,
    mappedBits: 2,
    unknownBits: 2,
    filteredCones: 4,
  });
  assert.equal(attachment.operations.length, 5);
});

test("explicit semantic producers reach their writes and roles filter references only", () => {
  const { model, attachment } = fixture(),
    index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["producer", "w0"], {
    roles: ["enable", "reset"],
  });
  assert.equal(layer.operations.length, 2);
  assert.deepEqual(
    layer.cones.map((cone) => cone.role),
    ["enable", "reset"],
  );
  assert.deepEqual(layer.arcs.sort(), [5, 6]);
  assert.deepEqual(computationLayers(index, ["read"]), []);
});

test("untimed arcs, cycles and unsupported frontiers never acquire a finite cone delay", () => {
  for (const mutate of [
    (a) => {
      a.arcs[4].timing.slow[0].maxPs = null;
    },
    (a) => {
      a.pins.push({
        id: "lut/I2",
        cell: 1,
        pin: "I2",
        direction: "IN",
        net: 1,
      });
      a.arcs.push({
        id: "cycle-net",
        kind: "net",
        from: 3,
        to: 9,
        net: 1,
        timing: a.arcs[2].timing,
      });
      a.arcs.push({
        id: "cycle",
        kind: "logic",
        from: 9,
        to: 3,
        timing: a.arcs[2].timing,
      });
    },
    (a) => {
      a.cells[0].boundary = "unsupported";
    },
  ]) {
    const { model, attachment } = fixture();
    mutate(attachment);
    const index = createComputations(model, attachment);
    const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
    assert.equal(layer.cones[0].staticDelayNs, null);
    assert.equal(layer.cones[0].registeredDelayNs, null);
    assert.notEqual(layer.cones[0].registeredTiming.status, "known");
    const [hidden] = computationLayers(index, ["w0"], {
      roles: ["data"],
      includeUnknownTiming: false,
    });
    assert.equal(hidden.arcs.length, 0);
    assert.equal(hidden.operations.length, 1);
  }
});

test("static delay threshold retains occurrence coverage and source recording", () => {
  const { model, attachment } = fixture(),
    index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"], {
    roles: ["data"],
    minimumDelayNs: 1.1,
  });
  assert.equal(layer.cones.length, 0);
  assert.equal(layer.coverage.unknownBits, 1);
  assert.equal(index.operations.size, 5);
});

test("routing is resolved once independently of any sampled timing path", () => {
  const { model, attachment } = fixture(),
    index = createComputations(model, attachment, [route()]);
  const connection = computationConnection(index, 4);
  assert.equal(connection.disposition, "resolved");
  assert.equal(connection.pips.length, 1);
  assert.equal(connection, computationConnection(index, 4));
  assert.equal(computationConnection(index, 0).disposition, "unavailable");
  assert.equal(computationConnection(index, 2), null);
});

/** Add an untimed external or constant alternative feeding the same LUT. Its
 * logic arc is timed, while its incoming net has no SDF delay annotation. */
function addUntimedAlternative(attachment, kind) {
  let net = 2,
    source = 6;
  if (kind === "external") {
    net = attachment.nets.length;
    attachment.nets.push({ id: "alternative-external" });
    source = attachment.pins.length;
    attachment.pins.push({
      id: "external-input",
      cell: null,
      pin: "port",
      direction: "IN",
      net,
    });
  }
  const target = attachment.pins.length;
  attachment.pins.push({
    id: `lut/${kind}`,
    cell: 1,
    pin: kind,
    direction: "IN",
    net,
  });
  attachment.arcs.push({
    id: `alternative-net-${kind}`,
    kind: "net",
    from: source,
    to: target,
    net,
    timing: { fast: [], slow: [] },
  });
  attachment.arcs.push({
    id: `alternative-logic-${kind}`,
    kind: "logic",
    from: target,
    to: 3,
    timing: { fast: [{ maxPs: 4000 }], slow: [{ maxPs: 8000 }] },
  });
}

test("registered launch bound excludes untimed external/constant alternatives without pruning them", () => {
  const { model, attachment } = fixture();
  addUntimedAlternative(attachment, "external");
  addUntimedAlternative(attachment, "constant");
  const index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"], {
    roles: ["data"],
    timingMetric: "registered_launch",
    includeUnknownTiming: false,
  });
  const cone = layer.cones[0];
  assert.equal(cone.staticDelayNs, null);
  assert.equal(cone.registeredDelayNs, 1);
  assert.equal(cone.registeredTiming.status, "known");
  assert.equal(cone.registeredTiming.launchPins, 1);
  assert.equal(cone.registeredTiming.reachableArcs, 5);
  assert.equal(cone.registeredTiming.missingTiming, 0);
  assert.equal(cone.coverage.missingTiming, 2);
  assert.equal(layer.arcs.length, 9);
  assert.equal(layer.timingMetric, "registered_launch");
  const [whole] = computationLayers(index, ["w0"], {
    roles: ["data"],
    includeUnknownTiming: false,
  });
  assert.equal(whole.cones.length, 0);
  const [threshold] = computationLayers(index, ["w0"], {
    roles: ["data"],
    timingMetric: "registered_launch",
    minimumDelayNs: 1.1,
  });
  assert.equal(threshold.cones.length, 0);
});

test("missing delay on any registered path blocks the bound despite a known reconvergent alternative", () => {
  const { model, attachment } = fixture();
  attachment.arcs[2].timing.slow[0].maxPs = null;
  const index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
  const cone = layer.cones[0];
  assert.equal(cone.registeredDelayNs, null);
  assert.equal(cone.registeredTiming.status, "unknown");
  assert.deepEqual(cone.registeredTiming.reasons, [
    "missing_registered_path_timing",
  ]);
  assert.equal(cone.registeredTiming.missingTiming, 1);
  assert.equal(cone.registeredTiming.reachedTargets, 1);
});

test("constant-only and external-only cones have no registered launch path, never a zero delay", () => {
  const { model, attachment } = fixture();
  const index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"], {
    roles: ["enable", "reset"],
    timingMetric: "registered_launch",
  });
  for (const cone of layer.cones) {
    assert.equal(cone.staticDelayNs, 0.2);
    assert.equal(cone.registeredDelayNs, null);
    assert.equal(cone.registeredTiming.status, "not_applicable");
    assert.deepEqual(cone.registeredTiming.reasons, [
      "no_registered_launch_path",
    ]);
  }
  attachment.pins[6].cell = null;
  attachment.pins[6].direction = "IN";
  const external = createComputations(model, attachment);
  const [externalLayer] = computationLayers(external, ["w0"], {
    roles: ["enable"],
  });
  assert.equal(externalLayer.cones[0].registeredDelayNs, null);
  assert.deepEqual(externalLayer.cones[0].registeredTiming.reasons, [
    "no_registered_launch_path",
  ]);
});

test("registered paths share reconvergent arcs across writes and keep the longest path", () => {
  const { model, attachment } = fixture();
  const index = createComputations(model, attachment);
  const layers = computationLayers(index, ["w0", "w1", "w2"], {
    roles: ["data"],
    timingMetric: "registered_launch",
  });
  assert.equal(layers[0].cones.length, 1);
  assert.equal(layers[0].cones[0], layers[1].cones[0]);
  assert.equal(layers[0].cones[0].registeredDelayNs, 1);
  assert.equal(layers[0].cones[0].registeredTiming.reachableArcs, 5);
  assert.throws(
    () => computationLayers(index, ["w0"], { timingMetric: "invented" }),
    /invalid display filter/,
  );
});

/** Exhaustive oracle only for these tiny acyclic fixtures. Enumerating the few
 * complete paths independently checks both reconvergence and per-arc scope. */
function enumeratePathCosts(index, cone, registered) {
  const costs = new Map(cone.arcIndices.map((id) => [id, []]));
  const roots = new Set(cone.rootPins),
    outgoing = new Map();
  for (const id of cone.arcIndices) {
    const arc = index.arcs[id];
    if (!outgoing.has(arc.from)) outgoing.set(arc.from, []);
    outgoing.get(arc.from).push(id);
  }
  const walk = (pin, path, cost) => {
    if (roots.has(pin)) {
      for (const id of path) costs.get(id).push(cost);
      return;
    }
    assert(
      path.length <= cone.arcIndices.length,
      "oracle requires an acyclic fixture",
    );
    for (const id of outgoing.get(pin) ?? []) {
      const delay = index.delays[id];
      walk(
        index.arcs[id].to,
        [...path, id],
        cost === null || delay === null ? null : cost + delay,
      );
    }
  };
  for (const source of cone.frontiers)
    if (!registered || source.kind === "sequential") walk(source.pin, [], 0);
  return cone.arcIndices.map((id) => {
    const values = costs.get(id);
    if (!values.length) return registered ? "not_applicable" : null;
    return values.includes(null) ? null : Math.max(...values);
  });
}

function assertCosts(actual, expected) {
  assert.equal(actual.length, expected.length);
  actual.forEach((value, i) => {
    if (typeof expected[i] === "number") {
      assert.equal(typeof value, "number");
      assert(
        Math.abs(value - expected[i]) < 1e-12,
        `${value} != ${expected[i]}`,
      );
    } else assert.equal(value, expected[i]);
  });
}

function namedCosts(index, cone, scope = "registered") {
  return Object.fromEntries(
    cone.arcIndices.map((id, i) => [
      index.arcs[id].id,
      cone.pathDelays[scope][i],
    ]),
  );
}

/** The second selected FF shares the LUT output but has its own incoming arc. */
function addSecondRoot(model, attachment) {
  const cell = { id: "second", kind: "FDRE", boundary: "sequential" };
  attachment.cells.push(cell);
  model.cells.set(cell.id, cell);
  attachment.pins.push(
    { id: "second/D", cell: 4, pin: "D", direction: "IN", net: 1 },
    { id: "second/Q", cell: 4, pin: "Q", direction: "OUT", net: 3 },
  );
  attachment.bindings[0].bits[1] = { bit: 1, status: "supported", d: 9, q: 10 };
  attachment.arcs.push({
    id: "second-root",
    kind: "net",
    from: 3,
    to: 9,
    net: 1,
    timing: { fast: [{ maxPs: 700 }], slow: [{ maxPs: 1400 }] },
  });
}

test("complete path costs distinguish reconvergent branches while preserving cone bounds", () => {
  const { model, attachment } = fixture(),
    index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
  const cone = layer.cones[0],
    costs = namedCosts(index, cone);
  assertCosts(
    [costs.n0a, costs.logic0, costs.n0b, costs.logic1, costs.n1],
    [0.8, 0.8, 1, 1, 1],
  );
  assert.equal(cone.registeredDelayNs, 1);
  assert.equal(cone.staticDelayNs, 1);
  for (const scope of ["registered", "static"])
    assertCosts(
      cone.pathDelays[scope],
      enumeratePathCosts(index, cone, scope === "registered"),
    );
});

test("unknown timing affects only complete through-paths that can encounter it", () => {
  for (const missing of [0, 1, 2, 3, 4]) {
    const { model, attachment } = fixture();
    attachment.arcs[missing].timing.slow[0].maxPs = null;
    const index = createComputations(model, attachment);
    const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
    const cone = layer.cones[0],
      costs = namedCosts(index, cone);
    assert.equal(cone.registeredDelayNs, null);
    assert.equal(costs.n1, null);
    if ([0, 2].includes(missing))
      assertCosts([costs.n0b, costs.logic1], [1, 1]);
    if ([1, 3].includes(missing))
      assertCosts([costs.n0a, costs.logic0], [0.8, 0.8]);
    for (const scope of ["registered", "static"])
      assertCosts(
        cone.pathDelays[scope],
        enumeratePathCosts(index, cone, scope === "registered"),
      );
  }
});

test("multi-root suffix costs use the longest selected destination and localize unknown branches", () => {
  for (const missingSecond of [false, true]) {
    const { model, attachment } = fixture();
    addSecondRoot(model, attachment);
    if (missingSecond) attachment.arcs.at(-1).timing.fast = [];
    const index = createComputations(model, attachment);
    const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
    const cone = layer.cones[0],
      costs = namedCosts(index, cone);
    assert.equal(cone.rootPins.length, 2);
    assertCosts([costs.n1], [1]);
    if (missingSecond) {
      assert.equal(costs.n0a, null);
      assert.equal(costs.n0b, null);
      assert.equal(costs["second-root"], null);
      assert.equal(cone.registeredDelayNs, null);
    } else {
      assertCosts([costs.n0a, costs.n0b, costs["second-root"]], [1.8, 2, 2]);
      assert.equal(cone.registeredDelayNs, 2);
    }
    for (const scope of ["registered", "static"])
      assertCosts(
        cone.pathDelays[scope],
        enumeratePathCosts(index, cone, scope === "registered"),
      );
  }
});

test("registered per-arc eligibility excludes constant and external alternatives without zeroing them", () => {
  const { model, attachment } = fixture();
  addUntimedAlternative(attachment, "external");
  addUntimedAlternative(attachment, "constant");
  const index = createComputations(model, attachment);
  const [layer] = computationLayers(index, ["w0"]);
  for (const cone of layer.cones) {
    for (const scope of ["registered", "static"])
      assertCosts(
        cone.pathDelays[scope],
        enumeratePathCosts(index, cone, scope === "registered"),
      );
  }
  const data = layer.cones.find((cone) => cone.role === "data");
  const registered = namedCosts(index, data),
    whole = namedCosts(index, data, "static");
  for (const kind of ["external", "constant"]) {
    assert.equal(registered[`alternative-net-${kind}`], "not_applicable");
    assert.equal(registered[`alternative-logic-${kind}`], "not_applicable");
    assert.equal(whole[`alternative-net-${kind}`], null);
  }
  assert.equal(registered.n1, 1);
  assert.equal(whole.n1, null);
  assertCosts([whole.n0a, whole.n0b], [0.8, 1]);
  for (const cone of layer.cones.filter((cone) => cone.role !== "data"))
    assert(
      cone.pathDelays.registered.every((value) => value === "not_applicable"),
    );
});

test("unsupported frontiers and cycles keep all per-arc costs indeterminate", () => {
  for (const mode of ["unsupported", "cycle"]) {
    const { model, attachment } = fixture();
    if (mode === "unsupported") attachment.cells[0].boundary = "unsupported";
    else {
      attachment.pins.push({
        id: "lut/cycle",
        cell: 1,
        pin: "cycle",
        direction: "IN",
        net: 1,
      });
      attachment.arcs.push(
        {
          id: "cycle-net",
          kind: "net",
          from: 3,
          to: 9,
          net: 1,
          timing: attachment.arcs[0].timing,
        },
        {
          id: "cycle-logic",
          kind: "logic",
          from: 9,
          to: 3,
          timing: attachment.arcs[2].timing,
        },
      );
    }
    const index = createComputations(model, attachment);
    const [layer] = computationLayers(index, ["w0"], { roles: ["data"] });
    const cone = layer.cones[0];
    assert.equal(cone.pathDelays.registered.length, cone.arcIndices.length);
    assert(cone.pathDelays.registered.every((value) => value === null));
    assert(cone.pathDelays.static.every((value) => value === null));
  }
});
