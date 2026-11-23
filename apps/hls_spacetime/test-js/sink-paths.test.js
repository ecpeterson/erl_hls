import test from "node:test";
import assert from "node:assert/strict";
import { sinkRows, sinkPath } from "../web/sink-paths.js";

const near = (a, b) => Math.abs(a - b) < 1e-12;
const sorted = (values) => [...values].sort((a, b) => a - b);

/** Tiny normalized prepared-graph fixture. Cached arrivals come from exhaustive
 * prefix enumeration, independently of the production predecessor/suffix passes.
 * Every edge is retained; the fixture makes no native hardware claim. */
function fixture({
  edges = [
    [0, 2, 0, 0.1],
    [1, 2, 0, 0.4],
    [2, 3, 1, 0.6],
    [3, 4, 0, 0.3],
    [3, 5, 0, 0.1],
  ],
  frontiers = [
    { pin: 0, kind: "sequential" },
    { pin: 1, kind: "sequential" },
  ],
  roots = [4, 5],
} = {}) {
  const size =
    Math.max(...edges.flatMap(([from, to]) => [from, to]), ...roots) + 1;
  const pinIndices = Array.from({ length: size }, (_, i) => i);
  const values = (scope) => {
    const paths = pinIndices.map(() => []);
    const walk = (pin, cost, depth) => {
      assert(depth <= edges.length, "fixture must be acyclic");
      paths[pin].push(cost);
      for (const [from, to, , delay] of edges)
        if (from === pin)
          walk(
            to,
            cost === null || delay === null ? null : cost + delay,
            depth + 1,
          );
    };
    for (const source of frontiers)
      if (scope === "static" || source.kind === "sequential")
        walk(source.pin, 0, 0);
    return paths.map((rows) =>
      !rows.length
        ? "not_applicable"
        : rows.includes(null)
          ? null
          : Math.max(...rows),
    );
  };
  const pinArrivals = {
    registered: values("registered"),
    static: values("static"),
  };
  const total = (scope) => {
    const rows = roots
      .map((pin) => pinArrivals[scope][pin])
      .filter((value) => value !== "not_applicable");
    return !rows.length || rows.includes(null) ? null : Math.max(...rows);
  };
  const cone = {
    id: "data/4,5",
    role: "data",
    pinIndices,
    rootPins: roots,
    frontiers,
    arcIndices: edges.map((_, i) => i),
    pinArrivals,
    coverage: {
      cyclic: false,
      unsupportedFrontiers: 0,
      missingTiming: edges.filter((row) => row[3] === null).length,
    },
    registeredDelayNs: total("registered"),
    staticDelayNs: total("static"),
    registeredTiming: {
      status: total("registered") === null ? "unknown" : "known",
      reasons:
        total("registered") === null ? ["missing_registered_path_timing"] : [],
    },
  };
  const events = [
    { id: "w0", cycle: 3, access: { kind: "write", resource: "word-a" } },
    { id: "w1", cycle: 3, access: { kind: "write", resource: "word-b" } },
    { id: "w2", cycle: 4, access: { kind: "write", resource: "word-a" } },
  ];
  const index = {
    arcGeometry: structuredClone(edges),
    pinGeometry: pinIndices.map((pin) => [
      pin,
      pin,
      0,
      ["z/Q", "a/Q", "lut/I", "lut/O", "sink-a/D", "sink-b/D"][pin] ??
        `p${pin}`,
    ]),
    cones: [cone],
    writes: new Map(events.map((event) => [event.id, { cones: [0] }])),
    model: { events: new Map(events.map((event) => [event.id, event])) },
  };
  const layers = [
    { cycle: 3, cones: [cone], operations: [{ event: "w0" }, { event: "w1" }] },
    { cycle: 4, cones: [cone], operations: [{ event: "w2" }] },
  ];
  return { index, cone, layers };
}

/** Enumerate only complete source-to-selected-sink paths in a tiny DAG. This
 * independent oracle checks both representative membership and corridor unions. */
function paths(index, cone, sink, scope) {
  const result = [];
  const walk = (pin, source, arcs, cost) => {
    assert(arcs.length <= cone.arcIndices.length);
    if (pin === sink) result.push({ source, arcs, cost });
    for (const id of cone.arcIndices) {
      const [from, to, , delay] = index.arcGeometry[id];
      if (from === pin)
        walk(
          to,
          source,
          [...arcs, id],
          cost === null || delay === null ? null : cost + delay,
        );
    }
  };
  for (const source of cone.frontiers)
    if (scope === "static" || source.kind === "sequential")
      walk(source.pin, source.pin, [], 0);
  return result;
}
function oracleCheck(index, cone, sink, scope, marginNs) {
  const expected = paths(index, cone, sink, scope);
  const report = sinkPath(index, cone, sink, {
    scope,
    marginNs,
    corridor: true,
  });
  const unknown = expected.some((path) => path.cost === null);
  const maximum =
    !expected.length || unknown
      ? null
      : Math.max(...expected.map((path) => path.cost));
  assert.equal(
    report.status,
    !expected.length ? "not_applicable" : unknown ? "unknown" : "known",
  );
  if (maximum === null) {
    assert.equal(report.delayNs, null);
    assert.deepEqual(report.arcIndices, []);
    assert.deepEqual(report.corridorArcIds, []);
  } else {
    assert(near(report.delayNs, maximum));
    assert(near(report.netDelayNs + report.logicDelayNs, maximum));
    assert(
      expected.some(
        (path) =>
          near(path.cost, maximum) &&
          path.source === report.sourcePin &&
          JSON.stringify(path.arcs) === JSON.stringify(report.arcIndices),
      ),
    );
    const corridor = new Set(
      expected
        .filter(
          (path) =>
            maximum - path.cost <= marginNs ||
            near(maximum - path.cost, marginNs),
        )
        .flatMap((path) => path.arcs),
    );
    assert.deepEqual(sorted(report.corridorArcIds), sorted(corridor));
  }
  const unknownArcs = [];
  for (const row of report.arcCosts) {
    const alternatives = expected.filter((path) => path.arcs.includes(row.arc));
    const status = !alternatives.length
      ? "not_applicable"
      : alternatives.some((path) => path.cost === null)
        ? "unknown"
        : "known";
    assert.equal(row.status, status, `arc ${row.arc}`);
    if (status === "unknown") unknownArcs.push(row.arc);
    if (status === "known") {
      assert(
        near(
          row.pathDelayNs,
          Math.max(...alternatives.map((path) => path.cost)),
        ),
      );
      assert(
        maximum === null
          ? row.marginNs === null
          : near(row.marginNs, maximum - row.pathDelayNs),
      );
    } else assert.equal(row.pathDelayNs, null);
  }
  assert.deepEqual(report.unknownArcIds, unknownArcs);
  return report;
}

test("per-sink paths and near-longest corridors match exhaustive small DAGs", () => {
  for (let bits = 0; bits < 32; bits++) {
    const f = fixture();
    const edges = f.index.arcGeometry.map((row, i) => [
      row[0],
      row[1],
      row[2],
      ((bits >> i) & 1) * 0.125,
    ]);
    const { index, cone } = fixture({ edges });
    for (const scope of ["registered", "static"])
      for (const sink of cone.rootPins) {
        oracleCheck(index, cone, sink, scope, 0);
        oracleCheck(index, cone, sink, scope, 0.125);
      }
  }
});

test("selected-sink suffixes retain reconvergent alternatives without sibling-root paths", () => {
  const { index, cone } = fixture({
    edges: [
      [0, 2, 0, 0.1],
      [1, 2, 0, 0.4],
      [2, 3, 1, 0.6],
      [3, 4, 0, 0.3],
      [3, 5, 0, 0.1],
      [3, 6, 0, 0.2],
      [2, 6, 1, 0.5],
      [6, 4, 0, 0.1],
    ],
  });
  const tight = oracleCheck(index, cone, 4, "registered", 0);
  const broad = oracleCheck(index, cone, 4, "registered", 0.31);
  assert(!tight.corridorArcIds.includes(6));
  assert(broad.corridorArcIds.includes(6));
  assert(!broad.corridorArcIds.includes(4));
  assert.equal(broad.arcCosts.length, cone.arcIndices.length);
  assert(broad.corridorArcIds.length > tight.corridorArcIds.length);
  assert(tight.ties.branchingEncountered);
});

test("unknown sibling sinks do not poison a known sink; unknown alternatives remain explicit", () => {
  const f = fixture();
  const edges = f.index.arcGeometry;
  edges[4][3] = null;
  const { index, cone, layers } = fixture({ edges });
  assert.equal(cone.registeredDelayNs, null);
  const rows = sinkRows(index, layers);
  assert.equal(rows.find((row) => row.pin === 4).status, "known");
  assert.equal(rows.find((row) => row.pin === 5).status, "unknown");
  oracleCheck(index, cone, 4, "registered", 0);
  const missing = oracleCheck(index, cone, 5, "registered", 10);
  assert(missing.unknownArcIds.includes(4));
  const branch = fixture();
  const competing = branch.index.arcGeometry;
  competing[0][3] = null;
  const mixed = fixture({ edges: competing });
  const report = oracleCheck(mixed.index, mixed.cone, 4, "registered", 100);
  assert(report.arcCosts.some((row) => row.status === "known"));
  assert(report.unknownArcIds.length);
  assert.deepEqual(report.corridorArcIds, []);
});

test("native names choose stable zero-delay ties independent of arc-table ordering", () => {
  const base = fixture();
  const edges = base.index.arcGeometry.map((row) => [
    row[0],
    row[1],
    row[2],
    0,
  ]);
  const a = fixture({ edges }),
    b = fixture({ edges: [...edges].reverse() });
  const left = sinkPath(a.index, a.cone, 4),
    right = sinkPath(b.index, b.cone, 4);
  assert.equal(left.sourcePin, 1);
  assert.equal(right.sourcePin, 1);
  assert.equal(left.delayNs, 0);
  assert(left.ties.branchingEncountered);
  assert.equal(left.ties.identityOrder, "native_pin_names");
  assert.deepEqual(
    left.arcIndices.map((id) => a.index.arcGeometry[id]),
    right.arcIndices.map((id) => b.index.arcGeometry[id]),
  );
  assert.equal(left.corridorComputed, false);
  assert.deepEqual(left.arcCosts, []);
  assert.deepEqual(left.corridorArcIds, []);
  for (const row of b.index.pinGeometry) row.pop();
  const legacy = structuredClone(b.index);
  assert.equal(
    sinkPath(legacy, legacy.cones[0], 4).ties.identityOrder,
    "numeric_pin_refs",
  );
});

test("scope eligibility retains external alternatives without assigning them zero delay", () => {
  const f = fixture();
  const edges = f.index.arcGeometry;
  edges[1][3] = null;
  const { index, cone } = fixture({
    edges,
    frontiers: [
      { pin: 0, kind: "sequential" },
      { pin: 1, kind: "external" },
    ],
  });
  const registered = oracleCheck(index, cone, 4, "registered", 10);
  assert.equal(registered.status, "known");
  assert.equal(
    registered.arcCosts.find((row) => row.arc === 1).status,
    "not_applicable",
  );
  oracleCheck(index, cone, 4, "static", 10);
  const external = fixture({
    frontiers: [
      { pin: 0, kind: "external" },
      { pin: 1, kind: "constant" },
    ],
  });
  assert.equal(
    oracleCheck(external.index, external.cone, 4, "registered", 10).status,
    "not_applicable",
  );
});

test("sink rows retain every occurrence, owner and role while deduplicating aliases", () => {
  const { index, cone, layers } = fixture();
  const rows = sinkRows(index, [...layers, layers[0]]);
  assert.equal(rows.length, 2);
  for (const row of rows) {
    assert.equal(row.occurrences, 3);
    assert.deepEqual(row.writeEvents, ["w0", "w1", "w2"]);
    assert.deepEqual(row.cycles, [3, 4]);
    assert.deepEqual(row.resources, ["word-a", "word-b"]);
    assert.deepEqual(row.coneIds, [cone.id]);
  }
  const unowned = sinkRows(index, [{ cycle: 3, cones: [cone] }]);
  assert(
    unowned.every((row) => row.occurrences === 0 && row.resources.length === 0),
  );
  const alias = structuredClone(cone);
  alias.id = "alias";
  alias.pinArrivals.registered[4] = null;
  index.cones.push(alias);
  const combined = sinkRows(index, [{ cycle: 3, cones: [cone, alias] }]).find(
    (row) => row.pin === 4,
  );
  assert.equal(combined.status, "unknown");
  assert.equal(combined.delayNs, null);
  assert(near(combined.knownDelayNs, 1.3));
  assert.equal(combined.contributions.length, 2);
  assert.equal(combined.representativeConeId, "alias");
  const control = structuredClone(cone);
  control.id = "enable";
  control.role = "enable";
  control.rootPins = [4];
  const roles = sinkRows(index, [{ cycle: 3, cones: [cone, control] }]);
  assert.equal(roles.length, 3);
  assert(roles.some((row) => row.key === "enable/4"));
});

test("cycles and unsupported frontiers remain unknown without path enumeration", () => {
  for (const mode of ["cycle", "unsupported"]) {
    const { index, cone } = fixture();
    if (mode === "cycle") {
      index.arcGeometry.push([3, 2, 1, 0]);
      cone.arcIndices.push(index.arcGeometry.length - 1);
      cone.coverage.cyclic = true;
    } else cone.coverage.unsupportedFrontiers = 1;
    const report = sinkPath(index, cone, 4, { corridor: true });
    assert.equal(report.status, "unknown");
    assert.equal(report.delayNs, null);
    assert.deepEqual(report.arcIndices, []);
    assert.deepEqual(report.corridorArcIds, []);
    assert(report.unknownArcIds.length > 0);
  }
});

test("selection options and stale cached arrivals fail explicitly", () => {
  const { index, cone } = fixture();
  const snapshot = structuredClone(index);
  sinkPath(index, cone, 4, { corridor: true });
  assert.deepEqual(index, snapshot);
  assert.throws(() => sinkPath(index, cone, 2), /not a cone sink/);
  for (const options of [
    { scope: "live" },
    { marginNs: -1 },
    { marginNs: Infinity },
    { corridor: "all" },
  ])
    assert.throws(() => sinkPath(index, cone, 4, options), /invalid/);
  const corrupt = fixture();
  corrupt.cone.pinArrivals.registered[4] += 1;
  assert.throws(() => sinkPath(corrupt.index, corrupt.cone, 4), /predecessor/);
});
