import test from "node:test";
import assert from "node:assert/strict";
import {
  createModel,
  resourcePlacement,
  storageSegments,
  traceDependencies,
} from "../web/model.js";

/** Small synthetic storage history, including equal writes, read-first reuse,
 * response after replacement, a reset-retired request and an unobserved last Q. */
function fixture() {
  const build = {
    source: "source",
    rtl: "rtl",
    observation: "observer",
    implementation: "implementation",
  };
  const storage = { resource: "word", address: 0 };
  const versions = [
    {
      id: "initial",
      producer: "root",
      origin: "unknown",
      incarnation: "before-reset",
      storage,
      evidence: "unknown initial word",
    },
    {
      id: "carry",
      producer: "root",
      origin: "carry_in",
      incarnation: "after-reset",
      storage,
      evidence: "retained contents; provenance stops at reset",
    },
  ];
  const events = [];
  const add = (
    id,
    cycle,
    actor,
    inputs,
    output,
    access,
    incarnation = "before-reset",
  ) => {
    events.push({
      id,
      cycle,
      sequence: events.length,
      actor,
      task: "synthetic",
      activation: id,
      operation: access?.kind ?? "consume",
      observer: "observer",
      incarnation,
      inputs,
      outputs: output ? [output] : [],
      ...(access ? { access: { ...storage, ...access } } : {}),
      evidence: "synthetic observation",
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation,
        storage: access?.kind === "write" ? storage : null,
        evidence: "synthetic output",
      });
  };
  add("first-write", 1, "writer", [], "one", {
    port: "w",
    kind: "write",
    before: "initial",
    after_version: "one",
    mask: "0xFF",
  });
  add("equal-write", 2, "writer", [], "two", {
    port: "w",
    kind: "write",
    before: "one",
    after_version: "two",
    mask: "0xFF",
  });
  add("hold", 3, "writer", ["two"], null, {
    port: "w",
    kind: "hold",
    version: "two",
  });
  add("read", 4, "reader", ["two"], null, {
    port: "r",
    kind: "read_request",
    version: "two",
  });
  add("masked-write", 4, "writer", ["two"], "three", {
    port: "w",
    kind: "write",
    before: "two",
    after_version: "three",
    mask: "0x0F",
  });
  add("response", 6, "reader", ["two"], "result", {
    port: "r",
    kind: "read_result",
    version: "two",
    request: "read",
  });
  add("pending", 7, "reader", ["three"], null, {
    port: "r",
    kind: "read_request",
    version: "three",
  });
  add(
    "consume-carry",
    9,
    "consumer",
    ["carry"],
    "used",
    undefined,
    "after-reset",
  );
  add(
    "final-write",
    11,
    "writer",
    [],
    "last",
    {
      port: "w",
      kind: "write",
      before: "carry",
      after_version: "last",
      mask: "0xFF",
    },
    "after-reset",
  );
  return {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        complete: true,
        observers: [
          {
            id: "observer",
            first_sequence: 0,
            next_sequence: events.length,
            gaps: [],
            scope: "synthetic storage operations",
          },
        ],
        first_cycle: 0,
        end_cycle: 12,
        incarnations: [
          { id: "before-reset", first_cycle: 0, end_cycle: 8 },
          { id: "after-reset", first_cycle: 8, end_cycle: 12 },
        ],
      },
      events,
      versions,
      relations: [],
      resources: [
        {
          id: "word",
          kind: "bram",
          width: 8,
          depth: 1,
          read_latency: 2,
          ports: { r: "read", w: "write" },
          reset: "retained",
          collision: "read_first",
          evidence: "synthetic memory",
        },
      ],
    },
  };
}

/** Compare semantic endpoints independently of optional presentation metadata. */
function endpoints(segments) {
  return segments.map(({ kind, version, fromCycle, toCycle }) => [
    kind,
    version,
    fromCycle,
    toCycle,
  ]);
}

test("storage connections exist without selecting an event or causal path", () => {
  const model = createModel(fixture());
  assert.deepEqual(endpoints(storageSegments(model)), [
    ["hold", "initial", 0, 1],
    ["hold", "carry", 8, 11],
    ["write", "one", 1, 2],
    ["write", "two", 2, 3],
    ["hold", "two", 3, 4],
    ["write", "three", 4, 5],
    ["hold", "three", 5, 7],
  ]);
  assert.equal(model.edges.length, createModel(fixture()).edges.length);
});

test("a single-sample word retains its load bridge and equal writes keep distinct versions", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model, {
    versions: new Set(["one", "two"]),
  });
  assert.deepEqual(endpoints(segments), [
    ["write", "one", 1, 2],
    ["write", "two", 2, 3],
    ["hold", "two", 3, 4],
  ]);
  assert.equal(model.lifetimes.get("one").firstCycle, 2);
  assert.equal(model.lifetimes.get("one").endCycle, 3);
  assert.strictEqual(segments[0].lifetime, model.lifetimes.get("one"));
  assert.deepEqual(
    traceDependencies(model, "equal-write").events.map(({ id }) => id),
    ["equal-write"],
  );
});

test("half-open windows clip inclusive sample endpoints without changing lifetime evidence", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model, {
    firstCycle: 4,
    endCycle: 7,
    version: "three",
  });
  assert.deepEqual(
    segments.map((s) => [
      s.kind,
      s.fromCycle,
      s.toCycle,
      s.visibleFromCycle,
      s.visibleToCycle,
      s.beforeWindow,
      s.afterWindow,
    ]),
    [
      ["write", 4, 5, 4, 5, false, false],
      ["hold", 5, 7, 5, 6, false, true],
    ],
  );
  const carried = storageSegments(model, {
    firstCycle: 6,
    endCycle: 8,
    version: "three",
  });
  assert.deepEqual(endpoints(carried), [["hold", "three", 5, 7]]);
  assert.equal(carried[0].visibleFromCycle, 6);
  assert.equal(carried[0].beforeWindow, true);
  assert.equal(carried[0].lifetime.producer, "masked-write");
  assert.deepEqual(storageSegments(model, { firstCycle: 5, endCycle: 6 }), []);
});

test("residence survives windows with no selected word operations", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model, {
    firstCycle: 5,
    endCycle: 7,
    version: "three",
  });
  assert.deepEqual(
    segments.map((s) => [s.kind, s.visibleFromCycle, s.visibleToCycle]),
    [["hold", 5, 6]],
  );
  assert.ok(
    !model.orderedEvents.some(
      (e) =>
        e.cycle >= 5 &&
        e.cycle < 7 &&
        (e.inputs.includes("three") || e.outputs.includes("three")),
    ),
  );
});

test("read-first response latency does not prolong the replaced address version", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model, { version: "two" });
  assert.equal(Math.max(...segments.map((s) => s.toCycle)), 4);
  assert.equal(model.events.get("response").cycle, 6);
  assert.deepEqual(segments[0].lifetime.responses, ["response"]);
  assert.ok(
    traceDependencies(model, "response").events.some(
      (e) => e.id === "equal-write",
    ),
  );
});

test("reset and capture ends supply no invented transfer or write to a root", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model);
  assert.ok(segments.every((s) => s.toCycle < 8 || s.fromCycle >= 8));
  assert.ok(!segments.some((s) => s.version === "last"));
  assert.deepEqual(
    endpoints(storageSegments(model, { incarnation: "after-reset" })),
    [["hold", "carry", 8, 11]],
  );
  assert.equal(model.lifetimes.get("last").firstCycle, 12);
  assert.equal(model.lifetimes.get("last").endCycle, 12);
  assert.equal(model.lifetimes.get("three").pending[0].status, "reset_retired");
  const atReset = fixture();
  const final = atReset.bundle.events.find((e) => e.id === "final-write");
  final.cycle = 7;
  final.incarnation = "before-reset";
  final.access.before = "three";
  const last = atReset.bundle.versions.find((v) => v.id === "last");
  last.incarnation = "before-reset";
  assert.deepEqual(
    storageSegments(createModel(atReset), { version: "last" }),
    [],
  );
});

test("incomplete capture retains uncertain continuity on every presented connection", () => {
  const document = fixture();
  document.bundle.capture.complete = false;
  const segments = storageSegments(createModel(document));
  assert.ok(segments.length > 0);
  assert.ok(
    segments.every((s) => s.lifetime.continuity === "uncertain_capture"),
  );
});

test("filters select explicit associations, including off-window consumers, without assigning ownership", () => {
  const model = createModel(fixture());
  const segments = storageSegments(model, {
    firstCycle: 2,
    endCycle: 4,
    resource: "word",
    version: "two",
    actor: "reader",
    activation: "read",
    operation: "read_request",
    task: "synthetic",
  });
  assert.deepEqual(endpoints(segments), [["write", "two", 2, 3]]);
  assert.equal(model.events.get("read").cycle, 4);
  assert.ok(!Object.hasOwn(segments[0], "actor"));
  assert.deepEqual(
    storageSegments(model, { actor: "writer", operation: "read_request" }),
    [],
  );
  assert.deepEqual(
    storageSegments(model, { version: "initial", actor: "writer" }),
    [],
  );
  assert.deepEqual(storageSegments(model, { versions: [] }), []);
  assert.deepEqual(storageSegments(model, { resource: "unknown" }), []);
});

test("long residence remains a bounded interval instead of expanding one row per clock", () => {
  const document = fixture();
  document.bundle.capture.end_cycle = 1_000_000_000;
  document.bundle.capture.incarnations[1].end_cycle = 1_000_000_000;
  const segments = storageSegments(createModel(document));
  assert.equal(segments.length, 9);
  assert.deepEqual(endpoints(segments).at(-1), [
    "hold",
    "last",
    12,
    999_999_999,
  ]);
});

test("invalid windows and inconsistent stored transfers reject instead of drawing plausible bridges", () => {
  const model = createModel(fixture());
  assert.throws(
    () => storageSegments(model, { firstCycle: 3, endCycle: 3 }),
    /display window/,
  );
  const crossReset = fixture();
  crossReset.bundle.events.find((e) => e.id === "final-write").access.before =
    "three";
  assert.throws(
    () => storageSegments(createModel(crossReset)),
    /crosses reset/,
  );
  const wrongOutput = fixture();
  wrongOutput.bundle.events.find(
    (e) => e.id === "equal-write",
  ).access.after_version = "one";
  assert.throws(
    () => storageSegments(createModel(wrongOutput)),
    /matching write/,
  );
});

test("folded bits share installed cells, partial candidates remain separate and replicas stay distinct", () => {
  const document = fixture();
  document.catalogue = {
    build: document.bundle.build,
    cells: [
      { id: "shared", kind: "FDRE", x: 1, y: 2 },
      { id: "replica", kind: "FDRE", x: 4, y: 5 },
    ],
    bindings: [
      {
        resource: "word",
        disposition: "folded",
        cells: ["shared", "replica"],
        bits: [
          { bit: 0, status: "supported", cell: "shared", pin: "Q" },
          { bit: 1, status: "supported", cell: "shared", pin: "Q" },
          { bit: 2, status: "unknown" },
        ],
        evidence: "synthetic folded partial mapping",
      },
    ],
  };
  const model = createModel(document);
  const placement = resourcePlacement(model, "word");
  assert.deepEqual(
    placement.cells.map((c) => c.id),
    ["shared"],
  );
  assert.deepEqual(
    placement.candidateCells.map((c) => c.id),
    ["replica"],
  );
  assert.equal(placement.supportedBits, 2);
  assert.equal(placement.unknownBits, 1);
  storageSegments(model);
  assert.equal(model.cells.size, 2);
  delete document.catalogue.bindings[0].bits;
  document.catalogue.bindings[0].disposition = "replicated";
  const replicated = resourcePlacement(createModel(document), "word");
  assert.deepEqual(
    replicated.cells.map((c) => c.id),
    ["shared", "replica"],
  );
});

test("declared observer loss cannot masquerade as complete storage continuity", () => {
  const document = fixture();
  document.bundle.capture.observers[0].gaps = [
    { first_sequence: 1, next_sequence: 2, cause: "dropped" },
  ];
  assert.throws(
    () => createModel(document),
    /Complete capture declares observer loss/,
  );
  document.bundle.capture.complete = false;
  assert.ok(
    storageSegments(createModel(document)).every(
      (s) => s.lifetime.continuity === "uncertain_capture",
    ),
  );
  document.bundle.capture.complete = "true";
  assert.throws(() => createModel(document), /capture bounds/);
  document.bundle.capture.complete = true;
  document.bundle.capture.observers = [];
  assert.throws(() => createModel(document), /Missing event observer/);
});

test("used-only storage omits unread loads and trims residence to the last use", () => {
  const model = createModel(fixture());
  const full = endpoints(storageSegments(model));
  assert.deepEqual(endpoints(storageSegments(model, { usedOnly: true })), [
    ["hold", "carry", 8, 9],
    ["write", "two", 2, 3],
    ["hold", "two", 3, 4],
    ["write", "three", 4, 5],
    ["hold", "three", 5, 7],
  ]);
  assert.equal(model.lifetimes.get("one").lastUseCycle, null);
  assert.equal(model.lifetimes.get("carry").endCycle, 12);
  assert.deepEqual(endpoints(storageSegments(model)), full);
});

test("hold-only versions do not count as used; masked writes retain actual old-value inputs", () => {
  const document = fixture();
  document.bundle.events = document.bundle.events.filter(
    (event) => !["read", "response"].includes(event.id),
  );
  document.bundle.versions = document.bundle.versions.filter(
    (version) => version.id !== "result",
  );
  const options = { version: "two", usedOnly: true };
  assert.deepEqual(endpoints(storageSegments(createModel(document), options)), [
    ["write", "two", 2, 3],
    ["hold", "two", 3, 4],
  ]);
  document.bundle.events.find((event) => event.id === "masked-write").inputs =
    [];
  document.bundle.events.find(
    (event) => event.id === "masked-write",
  ).access.mask = "0xFF";
  const model = createModel(document);
  assert.equal(model.lifetimes.get("two").holds.length, 1);
  assert.equal(model.lifetimes.get("two").replacement, "masked-write");
  assert.deepEqual(storageSegments(model, options), []);
});

test("read-first use at replacement survives; delayed response does not extend residence", () => {
  const model = createModel(fixture());
  const life = model.lifetimes.get("two");
  assert.deepEqual(life.uses, ["read", "masked-write"]);
  assert.equal(life.lastUseCycle, 4);
  assert.equal(model.events.get(life.responses[0]).cycle, 6);
  assert.equal(
    storageSegments(model, { version: "two", usedOnly: true }).at(-1).toCycle,
    4,
  );
  assert.ok(
    traceDependencies(model, "response").events.some((e) => e.id === "read"),
  );
});

test("use outside the window preserves earlier storage without restoring the unused tail", () => {
  const model = createModel(fixture());
  const options = {
    version: "three",
    usedOnly: true,
    firstCycle: 5,
    endCycle: 7,
  };
  const [segment] = storageSegments(model, options);
  assert.equal(segment.toCycle, 7);
  assert.equal(segment.visibleToCycle, 6);
  assert.equal(segment.afterWindow, true);
  assert.deepEqual(
    storageSegments(model, {
      version: "carry",
      usedOnly: true,
      firstCycle: 10,
      endCycle: 12,
    }),
    [],
  );
});

test("reset-retired requests still count as recorded use; roots gain no invented load", () => {
  const model = createModel(fixture());
  assert.equal(model.lifetimes.get("three").pending[0].status, "reset_retired");
  const segments = storageSegments(model, { usedOnly: true });
  assert.equal(
    segments.find((s) => s.version === "three" && s.kind === "hold").toCycle,
    7,
  );
  assert.deepEqual(
    segments.filter((s) => s.version === "carry").map((s) => s.kind),
    ["hold"],
  );
  assert.ok(segments.every((s) => s.version !== "last"));
});

test("hold/response exclusion applies only to the referenced stored version", () => {
  const document = fixture();
  document.bundle.resources.push({
    ...document.bundle.resources[0],
    id: "control",
  });
  document.bundle.versions.push({
    ...document.bundle.versions[0],
    id: "control-root",
    storage: { resource: "control", address: 0 },
  });
  for (const event of document.bundle.events)
    if (["hold", "response"].includes(event.id))
      event.inputs.push("control-root");
  const model = createModel(document);
  assert.deepEqual(model.lifetimes.get("control-root").uses, [
    "hold",
    "response",
  ]);
  assert.deepEqual(
    endpoints(
      storageSegments(model, { version: "control-root", usedOnly: true }),
    ),
    [["hold", "control-root", 0, 6]],
  );
});

test("incomplete capture stays uncertain in used-only view and full history remains available", () => {
  const document = fixture();
  document.bundle.capture.complete = false;
  const model = createModel(document);
  const focused = storageSegments(model, { usedOnly: true });
  assert.ok(
    focused.every((s) => s.lifetime.continuity === "uncertain_capture"),
  );
  assert.ok(storageSegments(model).some((s) => s.version === "one"));
  assert.ok(focused.every((s) => s.version !== "one"));
});

test("write-first forwarding before the next Q sample does not invent storage use", () => {
  const document = fixture();
  document.bundle.resources[0].collision = "write_first";
  document.bundle.events.find((e) => e.id === "read").cycle = 2;
  document.bundle.events.find((e) => e.id === "response").cycle = 4;
  const replacement = document.bundle.events.find(
    (e) => e.id === "masked-write",
  );
  replacement.inputs = [];
  replacement.access.mask = "0xFF";
  const model = createModel(document);
  assert.equal(model.lifetimes.get("two").lastUseCycle, 2);
  assert.deepEqual(
    storageSegments(model, { version: "two", usedOnly: true }),
    [],
  );
  assert.equal(storageSegments(model, { version: "two" }).length, 2);
  assert.ok(
    traceDependencies(model, "read").events.some((e) => e.id === "equal-write"),
  );
});
