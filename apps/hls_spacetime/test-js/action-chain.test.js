import test from "node:test";
import assert from "node:assert/strict";
import { createModel, storageSegments } from "../web/model.js";
import {
  traceChain,
  matchingChain,
  chainDisplayBounds,
  chainTargetMasks,
  chainCircuitSelection,
  chainStorageSegments,
} from "../web/action-chain.js";
import { prepareView } from "../scripts/prepare-view.mjs";

/** Small independently named actions share a stored intermediate, with an
 * outside control input, a dead consumer, hold chronology and reset boundary. */
function fixture() {
  const events = [],
    versions = [];
  const add = (id, cycle, inputs, output, access, incarnation = "i") => {
    events.push({
      id,
      cycle,
      sequence: events.length,
      observer: "o",
      actor: "a",
      activation: "action",
      task: "test",
      incarnation,
      operation: access?.kind ?? "compute",
      inputs,
      outputs: output ? [output] : [],
      ...(access ? { access } : {}),
      evidence: "synthetic",
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation,
        storage:
          access?.kind === "write" ? { resource: "word", address: 0 } : null,
        evidence: "synthetic",
      });
  };
  versions.push({
    id: "initial",
    producer: "root",
    origin: "unknown",
    incarnation: "i",
    storage: { resource: "word", address: 0 },
    evidence: "capture root",
  });
  add("operand", 1, [], "a");
  add("control", 1, [], "c");
  add("partial", 2, ["a", "c"], "p", {
    kind: "write",
    resource: "word",
    address: 0,
    port: "w",
    before: "initial",
    after_version: "p",
    mask: "0xff",
  });
  add("hold", 3, ["p"], null, {
    kind: "hold",
    resource: "word",
    address: 0,
    port: "w",
    version: "p",
  });
  add("read", 4, ["p"], null, {
    kind: "read_request",
    resource: "word",
    address: 0,
    port: "r",
    version: "p",
  });
  add("value", 4, ["p"], "r", {
    kind: "read_result",
    resource: "word",
    address: 0,
    port: "r",
    version: "p",
    request: "read",
  });
  add("finish", 4, ["r"], "f");
  add("commit", 5, ["f"], "q", {
    kind: "write",
    resource: "word",
    address: 0,
    port: "w",
    before: "p",
    after_version: "q",
    mask: "0xff",
  });
  add("dead", 6, ["a"], "unused");
  add("unrelated", 6, [], "other");
  add("after-reset", 10, [], "new", undefined, "j");
  const bundle = {
    format: "spacetime",
    schema: 1,
    unit: "cycle",
    evidence: "synthetic",
    build: { source: "s", rtl: "r", observation: "o", implementation: "i" },
    capture: {
      first_cycle: 0,
      end_cycle: 12,
      complete: true,
      incarnations: [
        { id: "i", first_cycle: 0, end_cycle: 9 },
        { id: "j", first_cycle: 9, end_cycle: 12 },
      ],
      observers: [{ id: "o", gaps: [], scope: "synthetic" }],
    },
    events,
    versions,
    resources: [
      {
        id: "word",
        kind: "register",
        width: 8,
        depth: 1,
        read_latency: 0,
        ports: { r: "read", w: "write" },
        reset: "clear",
        collision: "read_first",
        evidence: "synthetic",
      },
    ],
    relations: [
      {
        source: "hold",
        target: "commit",
        kind: "resource_order",
        resource: "word",
        evidence: "observed order only",
      },
    ],
    activity: [],
    physical: null,
  };
  const chain = {
    id: "action",
    title: "One action",
    comparisonKey: "actor/action/7",
    firstCycle: 1,
    endCycle: 7,
    sources: ["operand"],
    sinks: ["commit"],
    milestones: [
      { event: "partial", label: "Store partial" },
      { event: "commit", label: "Commit" },
    ],
    versions: ["p"],
  };
  return { format: "spacetime-view", schema: 1, bundle, chains: [chain] };
}

test("corridor retains storage/read paths and separates outside controls and dead work", () => {
  const document = fixture(),
    model = createModel(document);
  const trace = traceChain(model, document.chains[0]);
  assert.deepEqual(
    trace.events.map((e) => e.id),
    ["operand", "partial", "read", "value", "finish", "commit"],
  );
  assert.equal(trace.connected, true);
  assert.equal(trace.truncated, false);
  assert.ok(trace.versions.includes("p"));
  assert.deepEqual(
    trace.boundaryInputs.map((e) => e.source),
    ["control"],
  );
  assert.ok(trace.boundaryOutputs.some((e) => e.target === "dead"));
  assert.ok(!trace.edges.some((e) => e.kind === "resource_order"));
  assert.ok(model.lifetimes.get("p").holds.includes("hold"));
});

test("missing paths retain explicit unresolved anchors without inventing edges", () => {
  const document = fixture(),
    model = createModel(document);
  const chain = {
    ...document.chains[0],
    sinks: ["unrelated"],
    milestones: [],
    versions: [],
  };
  const trace = traceChain(model, chain);
  assert.equal(trace.connected, false);
  assert.deepEqual(
    trace.events.map((e) => e.id),
    ["operand", "unrelated"],
  );
  assert.equal(trace.edges.length, 0);
  assert.deepEqual(trace.unresolved.sinks, ["unrelated"]);
});

test("metadata cannot join resets, unknown versions, duplicate keys or out-of-window events", () => {
  const mutate = (change) => {
    const document = fixture();
    change(document);
    return () => createModel(document);
  };
  assert.throws(
    mutate((d) => {
      d.chains[0].sinks = ["after-reset"];
    }),
    /cross-reset/,
  );
  assert.throws(
    mutate((d) => {
      d.chains[0].sources = ["missing"];
    }),
    /unknown source/,
  );
  assert.throws(
    mutate((d) => {
      d.chains[0].versions = ["missing"];
    }),
    /unknown.*version/,
  );
  assert.throws(
    mutate((d) => {
      d.chains[0].endCycle = 5;
    }),
    /outside window/,
  );
  assert.throws(
    mutate((d) => {
      d.chains.push({ ...d.chains[0], id: "other" });
    }),
    /comparison key/,
  );
  const document = fixture(),
    model = createModel(document);
  assert.throws(
    () => traceChain(model, { ...document.chains[0], versions: ["unused"] }),
    /outside chain/,
  );
});

test("chain metadata is accepted by generic preparation and matches semantic keys only", () => {
  const document = fixture();
  const projection = prepareView(document.bundle, { chains: document.chains });
  const model = createModel(projection);
  assert.equal(matchingChain(model, "actor/action/7").id, "action");
  assert.equal(matchingChain(model, "action"), null);
  assert.equal(matchingChain(model, null), null);
});

test("full action paths are not truncated by the broad traversal's 1000-event default", () => {
  const document = fixture();
  document.bundle.events = [];
  document.bundle.versions = [];
  document.bundle.relations = [];
  for (let i = 0; i < 1100; i++) {
    const id = `e${i}`,
      out = `v${i}`;
    document.bundle.events.push({
      id,
      cycle: 2,
      sequence: i,
      observer: "o",
      actor: "a",
      incarnation: "i",
      operation: "compute",
      inputs: i ? [`v${i - 1}`] : [],
      outputs: [out],
    });
    document.bundle.versions.push({
      id: out,
      producer: id,
      origin: "event",
      incarnation: "i",
      storage: null,
      evidence: "synthetic",
    });
  }
  document.chains[0] = {
    ...document.chains[0],
    sources: ["e0"],
    sinks: ["e1099"],
    milestones: [],
    versions: [],
  };
  const model = createModel(document),
    trace = traceChain(model, document.chains[0]);
  assert.equal(trace.events.length, 1100);
  assert.equal(trace.edges.length, 1099);
  assert.equal(trace.connected, true);
});

test("common display bounds preserve coordinates and reject clipping route excursions", () => {
  const bounds = { minX: 0, maxX: 100, minY: 0, maxY: 200 };
  const chain = { ...fixture().chains[0], spatialBounds: bounds };
  const native = { minX: 10, maxX: 90, minY: 20, maxY: 190 };
  assert.deepEqual(chainDisplayBounds(chain, native), bounds);
  assert.notEqual(chainDisplayBounds(chain, native), bounds);
  assert.deepEqual(native, { minX: 10, maxX: 90, minY: 20, maxY: 190 });
  assert.equal(chainDisplayBounds(null, native), native);
  assert.throws(
    () => chainDisplayBounds(chain, { ...native, maxX: 101 }),
    /exclude native/,
  );
  const document = fixture();
  document.chains[0].spatialBounds = { ...bounds, maxX: NaN };
  assert.throws(() => createModel(document), /invalid shared/);
});

test("destination subsets preserve actual writes and reject empty, wider or unrelated targets", () => {
  const document = fixture();
  document.chains[0].targets = [{ event: "partial", mask: "0x0f" }];
  const model = createModel(document),
    chain = document.chains[0];
  assert.equal(chainTargetMasks(model, chain).get("partial"), "0xF");
  assert.equal(model.events.get("partial").access.mask, "0xff");
  assert.deepEqual(traceChain(model, chain).focusVersions, ["p"]);
  for (const mask of ["0x0", "0x100", "broken"])
    assert.throws(
      () => chainTargetMasks(model, { targets: [{ event: "partial", mask }] }),
      /mask/,
    );
  assert.throws(
    () =>
      chainTargetMasks(model, { targets: [{ event: "finish", mask: "0x1" }] }),
    /not a write/,
  );
  assert.throws(
    () =>
      chainTargetMasks(model, {
        targets: [chain.targets[0], chain.targets[0]],
      }),
    /duplicate target/,
  );
});

test("primary destination circuitry excludes other whole-word control cones only under explicit focus", () => {
  const events = [
    { id: "partial", operation: "write" },
    { id: "control", operation: "write" },
    { id: "commit", operation: "write" },
    { id: "operand", operation: "read" },
  ];
  const chain = {
    targets: [
      { event: "partial", mask: "0xff" },
      { event: "commit", mask: "0xff" },
    ],
  };
  const before = structuredClone(events);
  assert.deepEqual(chainCircuitSelection(chain, events), [
    events[0],
    events[2],
  ]);
  assert.equal(
    chainCircuitSelection(chain, events, { includeContext: true }),
    events,
  );
  assert.equal(
    chainCircuitSelection(chain, events, { onlyChain: false }),
    events,
  );
  assert.equal(chainCircuitSelection({ targets: [] }, events), events);
  assert.equal(chainCircuitSelection(null, events), events);
  assert.deepEqual(chainCircuitSelection(chain, [events[1]]), []);
  assert.deepEqual(events, before);
});

test("clearing an action retains its explicit frame while newly loaded geometry remains validated", () => {
  const retained = { minX: 0, maxX: 20, minY: 0, maxY: 20 };
  const native = { minX: 1, maxX: 15, minY: 2, maxY: 17 };
  const frame = chainDisplayBounds(null, native, retained);
  assert.deepEqual(frame, retained);
  assert.notEqual(frame, retained);
  frame.maxX = 99;
  assert.equal(retained.maxX, 20);
  assert.throws(
    () => chainDisplayBounds(null, { ...native, maxX: 21 }, retained),
    /exclude native geometry/,
  );
  assert.equal(chainDisplayBounds(null, native, null), native);
});

/** A later control read belongs to the action but consumes another field;
 * a still later read belongs to another action and must not lengthen this one. */
function residenceFixture() {
  const document = fixture();
  const chain = document.chains[0];
  chain.endCycle = 9;
  chain.targets = [{ event: "partial", mask: "0x0f" }];
  document.bundle.events.find((event) => event.id === "commit").cycle = 8;
  const read = document.bundle.events.find((event) => event.id === "read");
  read.access.read_mask = "0x0f";
  for (const [id, cycle, mask] of [
    ["control-read", 6, "0xf0"],
    ["other-action-read", 7, "0x0f"],
  ])
    document.bundle.events.push({
      ...read,
      id,
      cycle,
      sequence: document.bundle.events.length,
      access: { ...read.access, read_mask: mask },
    });
  document.bundle.relations.push({
    source: "control-read",
    target: "commit",
    kind: "required",
    evidence: "synthetic control input",
  });
  const model = createModel(document),
    trace = traceChain(model, chain);
  return { model, trace, chain };
}

test("action residence ignores unrelated and field-disjoint later reads without editing history", () => {
  const { model, trace, chain } = residenceFixture();
  assert.ok(trace.events.some((event) => event.id === "control-read"));
  assert.ok(!trace.events.some((event) => event.id === "other-action-read"));
  const segments = storageSegments(model, { usedOnly: true });
  const original = JSON.stringify(segments);
  const scoped = chainStorageSegments(model, chain, trace, segments);
  assert.equal(model.lifetimes.get("p").lastUseCycle, 7);
  assert.equal(scoped.lastUses.get("p"), 4);
  assert.deepEqual(
    scoped.segments.map((segment) => [
      segment.kind,
      segment.fromCycle,
      segment.toCycle,
    ]),
    [
      ["write", 2, 3],
      ["hold", 3, 4],
    ],
  );
  assert.deepEqual(scoped.excludedReads, [
    { version: "p", event: "control-read" },
  ]);
  assert.deepEqual(scoped.unresolved, []);
  assert.equal(JSON.stringify(segments), original);
  assert.equal(scoped.segments[1].lifetime, model.lifetimes.get("p"));
});

test("unknown action read masks retain possible residence and disclose the unresolved field use", () => {
  const { model, trace, chain } = residenceFixture();
  delete model.events.get("control-read").access.read_mask;
  const scoped = chainStorageSegments(
    model,
    chain,
    trace,
    storageSegments(model, { usedOnly: true }),
  );
  assert.equal(scoped.lastUses.get("p"), 6);
  assert.equal(scoped.segments.at(-1).toCycle, 6);
  assert.deepEqual(scoped.unresolved, [
    { version: "p", event: "control-read", reason: "unknown_consumed_bits" },
  ]);
  assert.equal(model.lifetimes.get("p").lastUseCycle, 7);
});

test("action storage with no matching recorded field use gets no invented bridge", () => {
  const { model, trace, chain } = residenceFixture();
  chain.targets[0].mask = "0x80";
  model.events.get("control-read").access.read_mask = "0x10";
  const scoped = chainStorageSegments(
    model,
    chain,
    trace,
    storageSegments(model),
  );
  assert.equal(scoped.lastUses.get("p"), null);
  assert.deepEqual(scoped.segments, []);
  assert.deepEqual(scoped.unusedVersions, ["p"]);
});
