import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import {
  createModel,
  eventsInWindow,
  traceDependencies,
  storageLifetimes,
  eventPlacement,
  resourcePlacement,
  eventDetails,
} from "../web/model.js";
import {
  projectBundle,
  openArchive,
  readVerifiedJson,
  parseArguments,
} from "../scripts/prepare-example.mjs";

/** Deliberately small synthetic graph: equal full writes, a read-first masked
 * overwrite, response after replacement, independent resource order and reset. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o" };
  const events = [];
  const versions = [
    {
      id: "root",
      producer: "root",
      origin: "unknown",
      incarnation: "epoch0",
      storage: { resource: "ram", address: 0 },
      evidence: "unknown initial word",
    },
    {
      id: "carry",
      producer: "root",
      origin: "carry_in",
      incarnation: "epoch1",
      storage: { resource: "ram", address: 0 },
      evidence: "retained word, ancestry ends at reset",
    },
  ];
  const add = (id, cycle, inputs, output, access, incarnation = "epoch0") => {
    events.push({
      id,
      cycle,
      sequence: events.length,
      observer: "o",
      actor: "actor",
      task: "synthetic",
      activation: id,
      incarnation,
      operation: access?.kind ?? "compute",
      inputs,
      outputs: output ? [output] : [],
      ...(access ? { access } : {}),
      evidence: "synthetic observation",
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation,
        storage:
          access?.kind === "write" ? { resource: "ram", address: 0 } : null,
        evidence: "synthetic result",
      });
  };
  add("write1", 1, [], "v1", {
    resource: "ram",
    address: 0,
    port: "w",
    kind: "write",
    before: "root",
    after_version: "v1",
    mask: "0xFF",
  });
  add("equalWrite", 2, [], "v2", {
    resource: "ram",
    address: 0,
    port: "w",
    kind: "write",
    before: "v1",
    after_version: "v2",
    mask: "0xFF",
  });
  add("hold", 3, ["v2"], null, {
    resource: "ram",
    address: 0,
    port: "w",
    kind: "hold",
    version: "v2",
  });
  add("read", 4, ["v2"], null, {
    resource: "ram",
    address: 0,
    port: "r",
    kind: "read_request",
    version: "v2",
  });
  add("masked", 4, ["v2"], "v3", {
    resource: "ram",
    address: 0,
    port: "w",
    kind: "write",
    before: "v2",
    after_version: "v3",
    mask: "0xF",
  });
  add("response", 6, ["v2"], "result", {
    resource: "ram",
    address: 0,
    port: "r",
    kind: "read_result",
    version: "v2",
    request: "read",
  });
  add("consume", 6, ["result"], "done");
  add("pending", 7, ["v3"], null, {
    resource: "ram",
    address: 0,
    port: "r",
    kind: "read_request",
    version: "v3",
  });
  add("afterReset", 9, ["carry"], "after", undefined, "epoch1");
  const resources = [
    {
      id: "ram",
      kind: "bram",
      width: 8,
      depth: 1,
      read_latency: 2,
      ports: { r: "read", w: "write" },
      reset: "retained",
      collision: "read_first",
      evidence: "synthetic memory",
    },
  ];
  const bundle = {
    format: "spacetime",
    schema: 1,
    unit: "cycle",
    evidence: "synthetic_fixture",
    build,
    capture: {
      complete: true,
      first_cycle: 0,
      end_cycle: 12,
      incarnations: [
        { id: "epoch0", first_cycle: 0, end_cycle: 8 },
        { id: "epoch1", first_cycle: 8, end_cycle: 12 },
      ],
      observers: [
        {
          id: "o",
          first_sequence: 0,
          next_sequence: events.length,
          gaps: [],
          scope: "synthetic fixture",
        },
      ],
    },
    events,
    versions,
    resources,
    relations: [
      {
        source: "write1",
        target: "equalWrite",
        kind: "resource_order",
        resource: "ram",
        evidence: "observed order, not required data",
      },
    ],
    activity: [],
    physical: null,
  };
  return {
    format: "spacetime-view",
    schema: 1,
    bundle,
    catalogue: null,
    examples: [],
    annotations: {
      public: [
        {
          id: "public/0",
          cycle: 6,
          label: "completion",
          dependency_endpoint: false,
        },
      ],
      boundaries: [],
    },
  };
}

test("same-cycle chronology and public completion create no dependency", () => {
  const model = createModel(fixture());
  const trace = traceDependencies(model, "consume");
  assert.deepEqual(
    new Set(trace.events.map((e) => e.id)),
    new Set(["consume", "response", "read", "equalWrite"]),
  );
  assert.ok(
    !trace.events.some((e) =>
      ["write1", "masked", "hold", "public/0"].includes(e.id),
    ),
  );
  assert.equal(
    eventDetails(model, "consume").annotations[0].label,
    "completion",
  );
  assert.match(
    eventDetails(model, "consume").annotationScope,
    /not dependency endpoints/,
  );
});

test("equal full overwrite is a new version without old-value ancestry", () => {
  const model = createModel(fixture());
  assert.equal(traceDependencies(model, "equalWrite").events.length, 1);
  assert.deepEqual(
    traceDependencies(model, "equalWrite", { includeOrder: true }).events.map(
      (e) => e.id,
    ),
    ["equalWrite", "write1"],
  );
  assert.equal(model.lifetimes.get("v1").endCycle, 3);
  assert.equal(model.lifetimes.get("v2").firstCycle, 3);
});

test("masked writes retain their recorded old-word dependency", () => {
  const trace = traceDependencies(createModel(fixture()), "masked");
  assert.ok(
    trace.edges.some(
      (edge) => edge.version === "v2" && edge.source === "equalWrite",
    ),
  );
});

test("read-first response keeps the selected version after the address changes", () => {
  const model = createModel(fixture());
  const life = model.lifetimes.get("v2");
  assert.equal(life.firstCycle, 3);
  assert.equal(life.endCycle, 5);
  assert.deepEqual(life.holds, ["hold"]);
  assert.deepEqual(life.requests, ["read"]);
  assert.deepEqual(life.responses, ["response"]);
  assert.equal(model.events.get("response").cycle, 6);
  assert.ok(
    traceDependencies(model, "response").edges.some(
      (edge) => edge.kind === "read_request" && edge.source === "read",
    ),
  );
});

test("reset retires requests and carry-in roots stop traversal", () => {
  const model = createModel(fixture());
  assert.deepEqual(model.lifetimes.get("v3").pending, [
    { event: "pending", cycle: 7, dueCycle: 9, status: "reset_retired" },
  ]);
  const trace = traceDependencies(model, "afterReset");
  assert.equal(trace.events.length, 1);
  assert.equal(trace.roots[0].version.origin, "carry_in");
  assert.equal(trace.roots[0].consumer, "afterReset");
});

test("presentation windows preserve off-window identity and exact filters", () => {
  const model = createModel(fixture());
  assert.deepEqual(
    eventsInWindow(model, { firstCycle: 4, endCycle: 6 }).map((e) => e.id),
    ["read", "masked"],
  );
  assert.deepEqual(
    eventsInWindow(model, {
      operation: "read_request",
      incarnation: "epoch0",
    }).map((e) => e.id),
    ["read", "pending"],
  );
  const life = storageLifetimes(model, { firstCycle: 4, endCycle: 5 }).find(
    (item) => item.version === "v2",
  );
  assert.equal(life.producer, "equalWrite");
  assert.equal(life.beforeWindow, true);
  assert.equal(life.visibleFirstCycle, 4);
  assert.equal(life.firstCycle, 3);
});

test("forward traversal is bounded explicitly, without silently claiming complete ancestry", () => {
  const model = createModel(fixture());
  const trace = traceDependencies(model, "equalWrite", {
    direction: "forward",
    maxEvents: 2,
  });
  assert.equal(trace.truncated, true);
  assert.equal(trace.events.length, 2);
  assert.ok(trace.events.every((e) => e.incarnation === "epoch0"));
});

test("partial physical bits map only supported cells and preserve unknowns", () => {
  const document = fixture();
  document.catalogue = {
    build: document.bundle.build,
    checkpoint: "native-synthetic",
    coordinate_unit: "tile_grid",
    cells: [
      { id: "a", kind: "FDRE", x: 3, y: 4, site: "s", bel: "b" },
      { id: "candidate", kind: "FDRE", x: 8, y: 9, site: "s2", bel: "b2" },
    ],
    bindings: [
      {
        resource: "ram",
        disposition: "ambiguous",
        cells: ["a", "candidate"],
        generated: [],
        evidence: "partial witness",
        bits: [
          {
            bit: 0,
            status: "supported",
            cell: "a",
            pin: "Q",
            evidence: "witness",
          },
          { bit: 1, status: "unknown", evidence: "unmapped" },
        ],
      },
    ],
  };
  const model = createModel(document);
  const placement = resourcePlacement(model, "ram");
  assert.deepEqual(
    placement.cells.map((cell) => cell.id),
    ["a"],
  );
  assert.deepEqual(
    placement.candidateCells.map((cell) => cell.id),
    ["candidate"],
  );
  assert.equal(placement.unknownBits, 1);
  assert.equal(placement.coverage.status, "ambiguous");
  assert.equal(eventPlacement(model, "read").cells.length, 1);
  assert.equal(model.cells.size, 2);
  assert.equal(eventPlacement(model, "consume").cells.length, 0);
});

test("missing catalogue gives no invented physical position or installed zero-area claim", () => {
  const model = createModel(fixture());
  assert.equal(model.geometryBounds, null);
  assert.equal(resourcePlacement(model, "ram").coverage.status, "unmeasured");
  assert.equal(model.catalogue, null);
});

test("malformed duplicate identities, cross-reset inputs and build mismatch reject", () => {
  const duplicate = fixture();
  duplicate.bundle.events.push(duplicate.bundle.events[0]);
  assert.throws(() => createModel(duplicate), /duplicate event/);
  const reset = fixture();
  reset.bundle.events.at(-1).inputs = ["v3"];
  assert.throws(() => createModel(reset), /cross-reset input/);
  const identity = fixture();
  identity.catalogue = {
    build: { source: "different", rtl: "r", observation: "o" },
  };
  assert.throws(() => createModel(identity), /build mismatch/);
});

test("incomplete capture keeps storage continuity explicitly uncertain", () => {
  const document = fixture();
  document.bundle.capture.complete = false;
  assert.equal(
    createModel(document).lifetimes.get("v2").continuity,
    "uncertain_capture",
  );
});

test("browser projection preserves graph/masks, omits heavy detail explicitly and does not mutate its source", () => {
  const { bundle } = fixture();
  bundle.physical = {
    build: bundle.build,
    cells: [{ id: "a", x: 1, y: 2, properties: { large: "property" } }],
    nets: [{ id: "n" }],
    bindings: [],
    generated: [],
    native: { sdf: [] },
  };
  const projected = projectBundle(bundle);
  assert.equal(projected.bundle.events, bundle.events);
  assert.equal(projected.bundle.events[0].access.mask, "0xFF");
  assert.equal(projected.bundle.physical, null);
  assert.equal(projected.catalogue.cells[0].properties, undefined);
  assert.ok(projected.catalogue.omitted.includes("nets"));
  assert.equal(bundle.physical.cells[0].properties.large, "property");
});

test("archive reader verifies saved packed/raw hashes and rejects modified bytes", async () => {
  const directory = await mkdtemp(join(tmpdir(), "spacetime-projection-"));
  try {
    const raw = Buffer.from('{"small":"synthetic"}');
    const packed = gzipSync(raw);
    const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
    await writeFile(join(directory, "small.json.gz"), packed);
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify({
        schema: 1,
        files: [
          { file: "small.json.gz", bytes: packed.length, sha256: hash(packed) },
        ],
      }),
    );
    const archive = await openArchive(directory, "fixture");
    assert.deepEqual(
      await readVerifiedJson(archive, "small.json.gz", hash(raw)),
      { small: "synthetic" },
    );
    await assert.rejects(
      readVerifiedJson(archive, "small.json.gz", "wrong"),
      /Decoded source hash mismatch/,
    );
    await writeFile(
      join(directory, "small.json.gz"),
      Buffer.from(packed).fill(0, 0, 1),
    );
    await assert.rejects(
      readVerifiedJson(archive, "small.json.gz"),
      /Source hash\/length mismatch/,
    );
    await assert.rejects(
      readVerifiedJson(archive, "missing"),
      /Unmanifested source/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("later repeated command-line options win", () => {
  assert.equal(
    parseArguments(["--output", "first", "--output", "last"]).output,
    "last",
  );
  assert.throws(() => parseArguments(["--output"]), /incomplete argument/);
});

test("same-cycle mixed version/control cycles are rejected", () => {
  const document = fixture();
  // response -> consume already exists through version 'result'.
  document.bundle.relations.push({
    source: "consume",
    target: "response",
    kind: "required",
    evidence: "invalid cycle",
  });
  assert.throws(
    () => createModel(document),
    /Dependency graph contains a cycle/,
  );
});

test("resource-order and read-request self-loops are rejected", () => {
  const ordered = fixture();
  ordered.bundle.relations.push({
    source: "consume",
    target: "consume",
    kind: "resource_order",
    resource: "ram",
    evidence: "invalid self-loop",
  });
  assert.throws(
    () => createModel(ordered),
    /Dependency graph contains a cycle/,
  );
  const read = fixture();
  read.bundle.events.find((event) => event.id === "response").access.request =
    "response";
  assert.throws(() => createModel(read), /Dependency graph contains a cycle/);
});

test("invalid capture arithmetic and out-of-capture incarnations reject", () => {
  const unsafe = fixture();
  unsafe.bundle.capture.end_cycle = Number.MAX_SAFE_INTEGER + 1;
  assert.throws(() => createModel(unsafe), /Invalid capture bounds/);
  const outside = fixture();
  outside.bundle.capture.incarnations[0].first_cycle = -1;
  assert.throws(() => createModel(outside), /Invalid incarnation bounds/);
  const sequence = fixture();
  sequence.bundle.events[0].sequence = NaN;
  assert.throws(
    () => createModel(sequence),
    /Invalid event cycle\/incarnation/,
  );
});

test("long repeated-write history retains distinct lifetimes without resource-history rescans", () => {
  const document = fixture();
  const count = 10000;
  document.bundle.capture.end_cycle = count + 2;
  document.bundle.capture.incarnations = [
    { id: "epoch0", first_cycle: 0, end_cycle: count + 2 },
  ];
  document.bundle.events = [];
  document.bundle.versions = [document.bundle.versions[0]];
  document.bundle.relations = [];
  for (let i = 1; i <= count; i++) {
    const id = `write-${i}`,
      version = `word-${i}`;
    document.bundle.events.push({
      id,
      cycle: i,
      sequence: i - 1,
      incarnation: "epoch0",
      observer: "o",
      actor: "actor",
      task: "synthetic",
      activation: id,
      operation: "write",
      inputs: [],
      outputs: [version],
      evidence: "synthetic write",
      access: {
        kind: "write",
        resource: "ram",
        address: 0,
        port: "w",
        before: i === 1 ? "root" : `word-${i - 1}`,
        after_version: version,
        mask: "0xFF",
      },
    });
    document.bundle.versions.push({
      id: version,
      producer: id,
      origin: "event",
      incarnation: "epoch0",
      storage: { resource: "ram", address: 0 },
      evidence: "synthetic word",
    });
  }
  document.bundle.capture.observers[0].next_sequence = count;
  const model = createModel(document);
  assert.equal(model.lifetimes.size, count + 1);
  assert.equal(model.lifetimes.get("word-5000").firstCycle, 5001);
  assert.equal(model.lifetimes.get("word-5000").endCycle, 5002);
  assert.equal(model.lifetimes.get(`word-${count}`).endCycle, count + 2);
});
