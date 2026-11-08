import test from "node:test";
import assert from "node:assert/strict";
import {
  createComputations,
  computationLayers,
} from "../web/computation-routes.js";
import { timingPath } from "../web/timing-paths.js";

/** Two launches reconverge in a LUT and fan out to two selected register bits.
 * Separate enable/reset roots exercise the same API outside the data role. */
function fixture(weights = [100, 200, 400, 500, 300, 100]) {
  const build = { source: "s", rtl: "r", observation: "o" };
  const cells = ["launch-a", "launch-b", "logic", "sink-a", "sink-b"].map(
    (id, i) => ({
      id,
      kind: i === 2 ? "LUT2" : "FDRE",
      boundary: i === 2 ? "combinational" : "sequential",
    }),
  );
  const pins = [
    ["launch-a/Q", 0, "Q", "OUT", 0],
    ["launch-b/Q", 1, "Q", "OUT", 1],
    ["logic/I0", 2, "I0", "IN", 0],
    ["logic/I1", 2, "I1", "IN", 1],
    ["logic/O", 2, "O", "OUT", 2],
    ["sink-a/D", 3, "D", "IN", 2],
    ["sink-a/Q", 3, "Q", "OUT", 3],
    ["sink-a/CE", 3, "CE", "IN", 0],
    ["sink-a/R", 3, "R", "IN", 1],
    ["sink-b/D", 4, "D", "IN", 2],
    ["sink-b/Q", 4, "Q", "OUT", 4],
  ].map(([id, cell, pin, direction, net]) => ({
    id,
    cell,
    pin,
    direction,
    net,
  }));
  const timing = (ps) => ({ fast: [{ maxPs: ps / 2 }], slow: [{ maxPs: ps }] });
  const arcs = [
    ["a-launch", "net", 0, 2, 0],
    ["z-launch", "net", 1, 3, 1],
    ["a-logic", "logic", 2, 4],
    ["z-logic", "logic", 3, 4],
    ["sink-a", "net", 4, 5, 2],
    ["sink-b", "net", 4, 9, 2],
    ["enable", "net", 0, 7, 0],
    ["reset", "net", 1, 8, 1],
  ].map(([id, kind, from, to, net], i) => ({
    id,
    kind,
    from,
    to,
    ...(net === undefined ? {} : { net }),
    timing: timing(weights[i] ?? 50),
  }));
  const event = {
    id: "write",
    cycle: 3,
    access: { kind: "write", resource: "word", mask: "0x3" },
  };
  const model = {
    bundle: { build },
    catalogue: { checkpoint: "c" },
    cells: new Map(cells.map((cell) => [cell.id, cell])),
    resources: new Map([["word", { id: "word", width: 2 }]]),
    events: new Map([[event.id, event]]),
  };
  const attachment = {
    schema: 1,
    scope: "structural_native_connectivity",
    build,
    checkpoint: "c",
    cells,
    pins,
    arcs,
    nets: [0, 1, 2, 3, 4].map((i) => ({ id: `n${i}` })),
    bindings: [
      {
        resource: "word",
        bits: [
          { bit: 0, status: "supported", q: 6, d: 5, ce: 7, reset: 8 },
          { bit: 1, status: "supported", q: 10, d: 9 },
        ],
      },
    ],
    operations: [
      {
        event: event.id,
        kind: "register_write",
        applicability: "storage_write",
        status: "supported",
        targets: [{ resource: "word", mask: "0x3" }],
        sources: [],
        unknowns: [],
        writes: [],
      },
    ],
  };
  return { model, attachment };
}

function prepared(f = fixture()) {
  const index = createComputations(f.model, f.attachment);
  const [layer] = computationLayers(index, ["write"]);
  return {
    index,
    cones: layer.cones,
    cone: layer.cones.find((row) => row.role === "data"),
  };
}
const close = (a, b) => assert(Math.abs(a - b) < 1e-12, `${a} != ${b}`);
const names = (index, path) => path.arcIndices.map((id) => index.arcs[id].id);

/** Enumerate complete paths only in tiny acyclic fixtures, independently of the
 * production arrival/backtrack algorithm. Unknown alternatives remain unknown. */
function paths(index, cone, scope) {
  const roots = new Set(cone.rootPins),
    result = [];
  const walk = (pin, sourcePin, arcs, cost) => {
    assert(arcs.length <= cone.arcIndices.length, "oracle requires a DAG");
    if (roots.has(pin)) result.push({ sourcePin, targetPin: pin, arcs, cost });
    for (const id of cone.arcIndices) {
      const arc = index.arcs[id];
      if (arc.from === pin)
        walk(
          arc.to,
          sourcePin,
          [...arcs, id],
          cost === null || index.delays[id] === null
            ? null
            : cost + index.delays[id],
        );
    }
  };
  for (const frontier of cone.frontiers)
    if (scope === "static" || frontier.kind === "sequential")
      walk(frontier.pin, frontier.pin, [], 0);
  return result;
}

function assertKnown(index, cone, scope) {
  const oracle = paths(index, cone, scope),
    report = timingPath(index, cone, { scope });
  assert(oracle.length && oracle.every((path) => path.cost !== null));
  const longest = Math.max(...oracle.map((path) => path.cost));
  assert.equal(report.status, "known");
  assert.deepEqual(report.reasons, []);
  close(report.delayNs, longest);
  close(report.netDelayNs + report.logicDelayNs, longest);
  assert(
    oracle.some(
      (path) =>
        path.sourcePin === report.sourcePin &&
        path.targetPin === report.targetPin &&
        Math.abs(path.cost - longest) < 1e-12 &&
        JSON.stringify(path.arcs) === JSON.stringify(report.arcIndices),
    ),
  );
  assert.equal(
    report.ties.maxSinkCount,
    new Set(
      oracle
        .filter((path) => Math.abs(path.cost - longest) < 1e-12)
        .map((path) => path.targetPin),
    ).size,
  );
  assert.equal(report.ties.representativeOnly, true);
  return report;
}

test("representative paths match an exhaustive reconvergent DAG oracle", () => {
  for (let bits = 0; bits < 64; bits++) {
    const weights = Array.from(
      { length: 6 },
      (_, i) => ((bits >> i) & 1) * 125,
    );
    const { index, cone } = prepared(fixture(weights));
    for (const scope of ["registered", "static"])
      assertKnown(index, cone, scope);
  }
  const { index, cone } = prepared();
  const report = timingPath(index, cone);
  assert.deepEqual(names(index, report), ["z-launch", "z-logic", "sink-a"]);
  close(report.netDelayNs, 0.5);
  close(report.logicDelayNs, 0.5);
  assert.equal(report.ties.branchingEncountered, false);
});

test("ties are deterministic native identities, independent of table ordering", () => {
  const f = fixture([100, 100, 400, 400, 300, 300]);
  const first = prepared(f),
    a = assertKnown(first.index, first.cone, "registered");
  assert.equal(a.ties.maxSinkCount, 2);
  assert.equal(a.ties.branchingEncountered, true);
  assert.deepEqual(names(first.index, a), ["a-launch", "a-logic", "sink-a"]);
  const shuffled = structuredClone(f);
  shuffled.attachment.arcs.reverse();
  const second = prepared(shuffled),
    b = timingPath(second.index, second.cone);
  assert.deepEqual(names(second.index, b), names(first.index, a));
  assert.equal(
    second.index.pins[b.targetPin].id,
    first.index.pins[a.targetPin].id,
  );
  assert.deepEqual(b.ties, a.ties);
});

test("an unknown competing path declines the full bound despite a finite alternative", () => {
  const f = fixture();
  f.attachment.arcs[2].timing.fast[0].maxPs = null;
  const { index, cone } = prepared(f);
  const oracle = paths(index, cone, "registered");
  assert(oracle.some((path) => path.cost === null));
  assert(oracle.some((path) => path.cost === 1));
  for (const scope of ["registered", "static"]) {
    const report = timingPath(index, cone, { scope });
    assert.equal(report.status, "unknown");
    assert.equal(report.delayNs, null);
    assert.equal(report.sourcePin, null);
    assert.equal(report.targetPin, null);
    assert.equal(report.netDelayNs, null);
    assert.equal(report.logicDelayNs, null);
    assert.deepEqual(report.arcIndices, []);
    assert(
      report.reasons.includes(
        `missing_${scope === "registered" ? "registered" : "static"}_path_timing`,
      ),
    );
  }
});

test("external-only cones are inapplicable to registered scope, not zero-delay paths", () => {
  const f = fixture();
  for (const pin of f.attachment.pins.slice(0, 2)) {
    pin.cell = null;
    pin.direction = "IN";
  }
  const { index, cone } = prepared(f);
  const report = timingPath(index, cone);
  assert.equal(report.status, "not_applicable");
  assert.deepEqual(report.reasons, ["no_registered_launch_path"]);
  assert.equal(report.delayNs, null);
  assert.deepEqual(report.arcIndices, []);
  assertKnown(index, cone, "static");
});

test("registered scope excludes a faster-ranked external alternative", () => {
  const f = fixture();
  f.attachment.pins[1].cell = null;
  f.attachment.pins[1].direction = "IN";
  const { index, cone } = prepared(f);
  const registered = assertKnown(index, cone, "registered");
  const whole = assertKnown(index, cone, "static");
  assert.equal(registered.sourcePin, 0);
  assert.equal(whole.sourcePin, 1);
  close(registered.delayNs, 0.8);
  close(whole.delayNs, 1);
});

test("zero delay and distinct data/control roots remain explainable", () => {
  const { index, cones, cone } = prepared(fixture(Array(8).fill(0)));
  const report = assertKnown(index, cone, "registered");
  assert.equal(report.delayNs, 0);
  assert.equal(report.arcIndices.length, 3);
  assert.equal(report.ties.maxSinkCount, 2);
  for (const role of ["enable", "reset"]) {
    const control = cones.find((item) => item.role === role);
    const path = assertKnown(index, control, "registered");
    assert.equal(path.role, role);
    assert.equal(path.arcIndices.length, 1);
    assert.equal(
      index.pins[path.targetPin].pin,
      role === "enable" ? "CE" : "R",
    );
  }
});

test("cycles and unsupported frontiers decline a path before backtracking", () => {
  for (const reason of ["cycle", "unsupported_or_missing_frontier"]) {
    const f = fixture();
    if (reason === "cycle") {
      f.attachment.pins.push({
        id: "logic/I2",
        cell: 2,
        pin: "I2",
        direction: "IN",
        net: 2,
      });
      f.attachment.arcs.push(
        {
          id: "cycle-net",
          kind: "net",
          from: 4,
          to: 11,
          net: 2,
          timing: f.attachment.arcs[0].timing,
        },
        {
          id: "cycle-logic",
          kind: "logic",
          from: 11,
          to: 4,
          timing: f.attachment.arcs[2].timing,
        },
      );
    } else f.attachment.cells[0].boundary = "unsupported";
    const { index, cone } = prepared(f);
    for (const scope of ["registered", "static"]) {
      const report = timingPath(index, cone, { scope });
      assert.equal(report.status, "unknown");
      assert(report.reasons.includes(reason));
      assert.deepEqual(report.arcIndices, []);
    }
  }
});

test("invalid scope or unreconciled cached timing cannot yield a plausible report", () => {
  const { index, cone } = prepared();
  assert.throws(() => timingPath(index, cone, { scope: "live" }), /scope/);
  const altered = structuredClone(cone);
  altered.pinArrivals.registered[altered.pinIndices.indexOf(5)] = 2;
  assert.throws(() => timingPath(index, altered), /bound/);
  const broken = { ...index, incoming: index.incoming.map(() => []) };
  assert.throws(() => timingPath(broken, cone), /predecessor/);
});
