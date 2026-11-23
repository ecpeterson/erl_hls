import test from "node:test";
import assert from "node:assert/strict";
import { nativeRoutes } from "../web/native-routes.js";

/** Distinct digests make each attachment identity independently corruptible. */
const hash = (digit) => digit.repeat(64);

/** A native node can span distant tiles; wire order is deliberately nongeometric. */
function node(id, x) {
  return { id, wires: [{ id: `${id}/wire`, tile: `tile/${x}`, x, y: 2 }] };
}

/** Native PIP coordinates are independent of the coordinates of attached cells. */
function pip(id, from, to, x, direction = "directional") {
  return {
    id,
    from_node: from,
    to_node: to,
    direction_status: direction,
    tile: `tile/${x}`,
    x,
    y: 2,
  };
}

/** Exact native pin/site/node correspondence retains an explicit intra-site gap. */
function pin(id, direction, nodeId) {
  return {
    pin: id,
    direction,
    status: "resolved",
    routing_node: nodeId,
    bel_pins: [`bel/${id}`],
    site_pins: [{ id: `site/${id}`, node: nodeId }],
  };
}

/** One selected branch shares a prefix with a distinct unselected fanout sink. */
function fixture() {
  const build = { source: hash("1"), rtl: hash("2"), observation: hash("3") };
  const path = {
    id: "max/0",
    source: "ff/C",
    launchPin: "ff/Q",
    endpoint: "lut/I5",
    slackNs: 0.5,
    dataDelayNs: 0.6,
    logicDelayNs: 0.1,
    routeDelayNs: 0.5,
    logicLevels: 0,
    steps: [
      { cell: "ff", pin: "ff/Q", incrementNs: 0.1, arrivalNs: 0.1 },
      { cell: "lut", pin: "lut/I5", incrementNs: null, arrivalNs: null },
    ],
    arcs: [
      {
        kind: "net",
        net: "alias",
        source: "ff/Q",
        target: "lut/I5",
        fanout: 2,
        delayNs: 0.5,
        arrivalNs: 0.6,
      },
    ],
  };
  return {
    bundle: { build },
    catalogue: { build, checkpoint: hash("4") },
    cells: new Map([
      ["ff", { id: "ff", x: 1, y: 2 }],
      ["lut", { id: "lut", x: 90, y: 2 }],
    ]),
    document: {
      nativePaths: {
        build,
        checkpoint: hash("4"),
        scope: "static_timing",
        wireGeometry: false,
        report_sha256: hash("5"),
        route_selection_sha256: hash("6"),
        paths: [path],
      },
      nativeRoutes: {
        schema_version: 1,
        complete: true,
        scope: "static_route_topology",
        coordinate_unit: "tile_grid",
        build,
        checkpoint_sha256: hash("4"),
        report_sha256: hash("5"),
        selection_sha256: hash("6"),
        paths: [
          {
            path_id: "max/0",
            arc_index: 0,
            report_net: "alias",
            canonical_net: "net",
            source_pin: "ff/Q",
            target_pin: "lut/I5",
          },
        ],
        nets: [
          {
            id: "net",
            route_status: "ROUTED",
            status: "complete",
            issues: [],
            nodes: [
              node("start", 1),
              node("fork", 10),
              node("sink", 90),
              node("other", 200),
            ],
            pips: [
              pip("a", "start", "fork", 3),
              pip("b", "fork", "sink", 30),
              pip("off", "fork", "other", 100),
            ],
            pin_attachments: [
              pin("ff/Q", "OUT", "start"),
              pin("lut/I5", "IN", "sink"),
              pin("other/I", "IN", "other"),
            ],
          },
        ],
      },
    },
  };
}

/** Obtain the only graph in these intentionally localized fixtures. */
function graph(model) {
  return model.document.nativeRoutes.nets[0];
}

test("selected routed branch preserves native order and excludes another fanout", () => {
  const model = fixture(),
    before = structuredClone(model);
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "resolved");
  assert.deepEqual(
    route.nodes.map((n) => n.id),
    ["start", "fork", "sink"],
  );
  assert.deepEqual(
    route.pips.map((p) => p.id),
    ["a", "b"],
  );
  assert.equal(route.excludedNodes, 1);
  assert.equal(route.excludedPips, 1);
  assert.equal(route.nodes.at(-1).wires[0].x, 90);
  assert.deepEqual(
    route.gaps.map((gap) => gap.kind),
    ["intrasite", "intrasite"],
  );
  assert.deepEqual(model, before);
  assert.deepEqual(nativeRoutes({ document: {} }), []);
});

test("unordered native wire tile footprints remain unordered, without centroid reduction", () => {
  const model = fixture();
  graph(model).nodes[1].wires.push({
    id: "fork/far",
    tile: "tile/400",
    x: 400,
    y: 2,
  });
  graph(model).nodes[1].wires.reverse();
  assert.deepEqual(
    nativeRoutes(model)[0].nodes[1].wires.map((w) => w.x),
    [400, 10],
  );
});

test("repeated static references reuse the same branch geometry", () => {
  const model = fixture();
  model.document.nativePaths.paths.push({
    ...structuredClone(model.document.nativePaths.paths[0]),
    id: "max/1",
  });
  model.document.nativeRoutes.paths.push({
    ...model.document.nativeRoutes.paths[0],
    path_id: "max/1",
  });
  const routes = nativeRoutes(model);
  assert.equal(routes[0].nodes, routes[1].nodes);
  assert.equal(routes[0].pips, routes[1].pips);
  assert.notEqual(routes[0].pathId, routes[1].pathId);
});

test("dangling bidirectional fanout does not masquerade as a selected corridor", () => {
  const model = fixture();
  graph(model).pips[2].direction_status = "bidirectional";
  assert.equal(nativeRoutes(model)[0].disposition, "resolved");
  graph(model).pips[1].direction_status = "bidirectional";
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "ambiguous");
  assert.deepEqual(route.nodes, []);
  assert.deepEqual(route.pips, []);
});

test("reconvergent alternatives and corridor cycles remain ambiguous", () => {
  for (const extra of [
    pip("alternate", "start", "sink", 4),
    pip("cycle", "sink", "start", 4),
  ]) {
    const model = fixture();
    graph(model).pips.push(extra);
    const [route] = nativeRoutes(model);
    assert.equal(route.disposition, "ambiguous");
    assert.deepEqual(route.nodes, []);
  }
});

test("missing path, unavailable PIP direction and intra-site-only endpoints stay explicit", () => {
  const missing = fixture();
  graph(missing).pips.splice(1, 1);
  assert.equal(nativeRoutes(missing)[0].disposition, "missing");
  const unknown = fixture();
  Object.assign(graph(unknown).pips[1], {
    direction_status: "unavailable",
    to_node: null,
  });
  assert.equal(nativeRoutes(unknown)[0].disposition, "ambiguous");
  const local = fixture();
  Object.assign(graph(local).pin_attachments[1], {
    status: "intrasite",
    routing_node: null,
    site_pins: [],
  });
  assert.equal(nativeRoutes(local)[0].disposition, "intrasite");
});

test("same routing node retains its wire footprint without inventing a PIP or zero length", () => {
  const model = fixture();
  Object.assign(graph(model).pin_attachments[1], {
    routing_node: "start",
    site_pins: [{ id: "site/sink", node: "start" }],
  });
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "resolved");
  assert.deepEqual(
    route.nodes.map((n) => n.id),
    ["start"],
  );
  assert.deepEqual(route.pips, []);
  assert.equal(route.gaps.length, 2);
});

test("missing coordinates remain explicit gaps; malformed or conflicting coordinates reject", () => {
  const model = fixture();
  Object.assign(graph(model).nodes[1].wires[0], { x: null, y: null });
  assert(
    nativeRoutes(model)[0].gaps.some((gap) => gap.kind === "wire_location"),
  );
  for (const corrupt of [
    (m) => (graph(m).nodes[0].wires[0].x = Infinity),
    (m) => (graph(m).pips[0].tile = "tile/1"),
    (m) => (graph(m).nodes[0].wires[0].y = null),
  ]) {
    const m = fixture();
    corrupt(m);
    assert.throws(() => nativeRoutes(m));
  }
});

test("foreign identities, stale static arcs and corrupted graph references reject", () => {
  for (const corrupt of [
    (m) =>
      (m.document.nativeRoutes.build = {
        ...m.bundle.build,
        observation: hash("9"),
      }),
    (m) => (m.document.nativeRoutes.checkpoint_sha256 = hash("9")),
    (m) => (m.document.nativeRoutes.report_sha256 = hash("9")),
    (m) => (m.document.nativeRoutes.selection_sha256 = hash("9")),
    (m) => (m.document.nativeRoutes.paths[0].source_pin = "other/I"),
    (m) => (m.document.nativeRoutes.paths[0].report_net = "other"),
    (m) => (m.document.nativeRoutes.paths[0].arc_index = 1),
    (m) =>
      m.document.nativeRoutes.paths.push({
        ...m.document.nativeRoutes.paths[0],
      }),
    (m) => (graph(m).pips[0].to_node = "foreign"),
    (m) => (graph(m).nodes[1].wires[0].id = "start/wire"),
    (m) => (graph(m).pin_attachments[0].direction = "IN"),
    (m) =>
      graph(m).pin_attachments[0].site_pins.push({
        id: "second",
        node: "fork",
      }),
    (m) =>
      graph(m).pin_attachments[0].site_pins.push({
        id: "unresolved",
        node: null,
      }),
    (m) => (m.document.nativeRoutes.paths = []),
  ]) {
    const m = fixture();
    corrupt(m);
    assert.throws(() => nativeRoutes(m));
  }
});

test("original native build is accepted only through matching qualified capture origins", () => {
  const model = fixture(),
    nativeBuild = model.bundle.build;
  const current = { ...nativeBuild, observation: hash("7") };
  const origin = {
    build: nativeBuild,
    checkpoint: hash("4"),
    previous_correspondence: null,
    base_projection_sha256: hash("8"),
    original_trace_sha256: hash("9"),
    extended_trace_sha256: hash("a"),
    simulator_sha256: hash("b"),
    comparison: {
      old_taps_equal: true,
      public_fields_equal: true,
      original_taps: 3,
      first_cycle: 0,
      end_cycle: 10,
      compared_cycles: 10,
    },
  };
  model.bundle.build = current;
  Object.assign(model.catalogue, {
    build: current,
    correspondence_origin: structuredClone(origin),
  });
  Object.assign(model.document.nativePaths, {
    build: current,
    correspondence_origin: structuredClone(origin),
  });
  assert.equal(nativeRoutes(model)[0].disposition, "resolved");
  model.document.nativePaths.correspondence_origin.original_trace_sha256 =
    hash("c");
  assert.throws(() => nativeRoutes(model));
});

test("same-node native site aliases and unavailable pin direction preserve valid evidence", () => {
  const same = fixture();
  graph(same).pin_attachments[0].site_pins.push({
    id: "alias/site",
    node: "start",
  });
  assert.equal(nativeRoutes(same)[0].disposition, "resolved");
  const unavailable = fixture();
  Object.assign(graph(unavailable).pin_attachments[0], {
    direction: null,
    status: "unavailable",
    routing_node: null,
    site_pins: [],
  });
  assert.equal(nativeRoutes(unavailable)[0].disposition, "unavailable");
});

test("one located candidate plus null alternatives shows a partial native branch", () => {
  const model = fixture(),
    source = graph(model).pin_attachments[0];
  Object.assign(source, { status: "ambiguous", routing_node: null });
  source.site_pins.push({ id: "unlocated/site", node: null });
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "partial");
  assert.deepEqual(
    route.pips.map((p) => p.id),
    ["a", "b"],
  );
  assert.deepEqual(route.gaps[0].unresolvedSitePins, ["unlocated/site"]);
  assert.equal(route.gaps[0].observedStatus, "ambiguous");
});

test("an interior source candidate cannot shorten the actual driver-root branch", () => {
  const model = fixture(),
    source = graph(model).pin_attachments[0];
  Object.assign(source, { status: "ambiguous", routing_node: null });
  source.site_pins.push({ id: "interior/site", node: "fork" });
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "resolved");
  assert.deepEqual(
    route.nodes.map((n) => n.id),
    ["start", "fork", "sink"],
  );
  assert.deepEqual(route.gaps[0].locatedCandidates, ["start", "fork"]);
});

test("two actual driver candidates reaching the sink remain ambiguous", () => {
  const model = fixture(),
    net = graph(model),
    source = net.pin_attachments[0];
  net.nodes.push(node("second_root", 300));
  net.pips.push(pip("second_driver", "second_root", "sink", 250));
  Object.assign(source, { status: "ambiguous", routing_node: null });
  source.site_pins.push({ id: "second/site", node: "second_root" });
  const [route] = nativeRoutes(model);
  assert.equal(route.disposition, "ambiguous");
  assert.deepEqual(route.nodes, []);
});
