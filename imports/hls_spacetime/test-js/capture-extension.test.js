import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  applyCaptureExtension,
  graphRecordSha256,
  parseArguments,
  prepareCaptureExtension,
} from "../scripts/prepare-example.mjs";
import { createModel, annotationEvents } from "../web/model.js";

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const identity = (digit) => digit.repeat(64);

/** Tiny retained presentation plus one newly observed accepted public word.
 * The fixture asserts preservation contracts, not a simulator/native witness. */
function fixture() {
  const build = {
    source: identity("1"),
    rtl: identity("2"),
    observation: identity("3"),
  };
  const extendedBuild = { ...build, observation: identity("6") };
  const event = {
    id: "old",
    cycle: 1,
    sequence: 0,
    observer: "o",
    incarnation: "epoch",
    inputs: [],
    outputs: ["value"],
    resources: ["register/R"],
  };
  const base = {
    format: "spacetime-view",
    schema: 1,
    title: "synthetic step",
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        first_cycle: 0,
        end_cycle: 5,
        complete: true,
        incarnations: [{ id: "epoch", first_cycle: 0, end_cycle: 5 }],
        observers: [{ id: "o", gaps: [] }],
      },
      resources: [{ id: "register/R", kind: "register", width: 8, depth: 1 }],
      events: [event],
      versions: [{ id: "value", producer: "old", incarnation: "epoch" }],
      relations: [],
      physical: null,
    },
    catalogue: {
      build,
      checkpoint: identity("5"),
      cells: [{ id: "cell", kind: "FDRE", x: 1, y: 2 }],
      bindings: [{ resource: "register/R", cells: ["cell"] }],
    },
    nativePaths: {
      build,
      checkpoint: identity("5"),
      paths: [],
      scope: "static_timing",
      wireGeometry: false,
    },
    coverage: {
      counts: { events: 1 },
      resource_associations: [
        { resource: "register/R", status: "value_correspondence_only" },
      ],
    },
    selection: { step: 1, completionCycle: 3, firstCycle: 1, endCycle: 4 },
    annotations: {
      public: [],
      boundaries: [{ id: "old-boundary", step: 1, cycle: 3 }],
    },
    examples: [{ id: "old-example", event: "old", events: ["old"] }],
    provenance: { archives: [], sources: [] },
    measurement: { scope: "retained synthetic static result" },
    scope: [
      "Original observations have no attributed public completion endpoint",
    ],
  };
  const bundle = structuredClone(base.bundle);
  bundle.build = extendedBuild;
  bundle.resources.push({ id: "stream/reply", kind: "logic" });
  bundle.events.push({
    id: "word",
    cycle: 3,
    sequence: 1,
    observer: "o",
    incarnation: "epoch",
    inputs: ["value"],
    outputs: [],
    resources: ["stream/reply"],
  });
  const anchors = { graph_events: ["word"], graph_incarnation: "epoch" };
  const summary = {
    events: [{ cycle: 3, stream: "reply", event: ["done", 1], ...anchors }],
    boundaries: [{ step: 1, cycle: 3, ...anchors }],
    input_stalls: [],
    output_stalls: [],
  };
  const review = {
    format: "spacetime-capture-extension-review",
    schema: 1,
    base_projection_sha256: identity("7"),
    original_trace_sha256: identity("8"),
    extended_trace_sha256: identity("9"),
    bundle_sha256: identity("a"),
    public_sha256: identity("b"),
    original_simulator_sha256: identity("4"),
    extended_simulator_sha256: identity("4"),
    checkpoint_sha256: identity("5"),
    base_build: build,
    extended_build: extendedBuild,
    comparison: {
      old_taps_equal: true,
      public_fields_equal: true,
      original_taps: 2,
      compared_cycles: 5,
      first_cycle: 0,
      end_cycle: 5,
    },
    wait_operations: ["entry_wait"],
  };
  return { base, bundle, summary, review };
}

function apply({ base, bundle, summary, review }) {
  return applyCaptureExtension(base, bundle, summary, review);
}

test("capture extension preserves original physical provenance and marks new streams unmapped", () => {
  const input = fixture(),
    before = structuredClone(input);
  const document = apply(input);
  assert.deepEqual(input, before);
  assert.equal(document.catalogue.build.observation, identity("6"));
  assert.equal(
    document.catalogue.correspondence_origin.build.observation,
    identity("3"),
  );
  assert.equal(document.nativePaths.build.observation, identity("6"));
  assert.equal(
    document.nativePaths.correspondence_origin.checkpoint,
    identity("5"),
  );
  assert.deepEqual(document.catalogue.bindings, input.base.catalogue.bindings);
  assert.equal(document.coverage.counts, undefined);
  assert.deepEqual(
    document.provenance.capture_extension.original_coverage.counts,
    { events: 1 },
  );
  assert.equal(
    document.coverage.resource_associations.find(
      (row) => row.resource === "stream/reply",
    ).status,
    "unmapped",
  );
  assert.deepEqual(document.metric_hints.wait_operations, ["entry_wait"]);
  assert.deepEqual(
    document.examples.map((example) => example.id),
    ["old-example", "completion-ancestry"],
  );
  const model = createModel(document);
  assert.deepEqual(
    annotationEvents(model, document.annotations.boundaries[0]).map(
      (event) => event.id,
    ),
    ["word"],
  );
  assert.equal(document.annotations.public[0].dependency_endpoint, true);
  assert.equal(model.edges.length, 1);
});

test("completion navigation carries every anchor while preserved storage examples remain available", () => {
  const input = fixture();
  input.summary.boundaries[0].graph_events = ["old", "word"];
  input.base.examples[0].version = "value";
  input.base.examples.push({
    id: "completion-context",
    event: "old",
    events: ["old"],
  });
  const document = apply(input);
  const completion = document.examples.find(
    (example) => example.id === "completion-ancestry",
  );
  assert.equal(completion.annotation, document.annotations.boundaries[0]);
  assert.deepEqual(completion.annotation.graph_events, ["old", "word"]);
  assert.equal(completion.annotation.graph_incarnation, "epoch");
  assert.deepEqual(completion.events, ["old", "word"]);
  assert.equal(document.examples[0], input.base.examples[0]);
  assert.equal(
    document.examples.some((example) => example.id === "completion-context"),
    false,
  );
});

test("capture extension rejects changed identity, incomplete comparisons and rewritten original graph", () => {
  const changes = [
    (x) => {
      x.bundle.build.rtl = identity("c");
    },
    (x) => {
      x.review.extended_simulator_sha256 = identity("c");
    },
    (x) => {
      x.review.checkpoint_sha256 = identity("c");
    },
    (x) => {
      x.review.comparison.old_taps_equal = false;
    },
    (x) => {
      x.review.comparison.public_fields_equal = false;
    },
    (x) => {
      x.review.comparison.compared_cycles = 4;
    },
    (x) => {
      x.bundle.capture.incarnations[0].id = "different-reset";
    },
    (x) => {
      x.bundle.events[0].cycle = 2;
    },
    (x) => {
      x.bundle.versions[0].producer = "word";
    },
    (x) => {
      x.bundle.resources[0].width = 9;
    },
    (x) => {
      x.review.wait_operations = ["unclassified_gap"];
    },
    (x) => {
      x.summary.boundaries[0].graph_events = ["missing"];
    },
    (x) => {
      x.summary.boundaries[0].graph_incarnation = "other-reset";
    },
  ];
  for (const change of changes) {
    const input = fixture();
    change(input);
    assert.throws(() => apply(input));
  }
  const input = fixture();
  input.base.bundle.relations.push({
    source: "old",
    target: "old",
    kind: "resource_order",
  });
  assert.throws(() => apply(input), /original relation/);
});

test("unanchored public observations remain contextual and unclassified waits stay explicit", () => {
  const input = fixture();
  for (const row of [...input.summary.events, ...input.summary.boundaries]) {
    delete row.graph_events;
    delete row.graph_incarnation;
  }
  delete input.review.wait_operations;
  const document = apply(input);
  assert.equal(document.annotations.public[0].dependency_endpoint, false);
  assert.deepEqual(document.examples, input.base.examples);
  assert.deepEqual(document.metric_hints.wait_operations, []);
});

test("extension preparation verifies files and preserves the unrelated memory example/index entry", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-extension-"));
  try {
    const baseDir = join(root, "base"),
      extension = join(root, "extension"),
      output = join(root, "output");
    await mkdir(baseDir);
    await mkdir(extension);
    const input = fixture();
    const baseBytes = Buffer.from(JSON.stringify(input.base));
    const bundleBytes = Buffer.from(JSON.stringify(input.bundle));
    const publicBytes = Buffer.from(JSON.stringify(input.summary));
    input.review.base_projection_sha256 = digest(baseBytes);
    input.review.bundle_sha256 = digest(bundleBytes);
    input.review.public_sha256 = digest(publicBytes);
    const memory = Buffer.from('{"format":"synthetic-memory-example"}');
    const entry = (file, bytes, title) => ({
      file,
      title,
      bytes: bytes.length,
      sha256: digest(bytes),
    });
    const memoryEntry = entry("memory.json", memory, "Existing memory example");
    await writeFile(join(baseDir, "live-1.json"), baseBytes);
    await writeFile(join(baseDir, "memory.json"), memory);
    await writeFile(
      join(baseDir, "index.json"),
      JSON.stringify({
        format: "spacetime-view-index",
        schema: 1,
        examples: [entry("live-1.json", baseBytes, "Base"), memoryEntry],
      }),
    );
    const files = [];
    for (const [file, bytes] of [
      ["bundle.json", bundleBytes],
      ["public.json", publicBytes],
      ["review.json", Buffer.from(JSON.stringify(input.review))],
    ]) {
      await writeFile(join(extension, file), bytes);
      files.push(entry(file, bytes, file));
    }
    await writeFile(
      join(extension, "manifest.json"),
      JSON.stringify({ schema: 1, files }),
    );
    const options = {
      captureExtension: extension,
      baseProjection: join(baseDir, "live-1.json"),
      output,
    };
    const result = await prepareCaptureExtension(options);
    assert.equal(result.addedResources, 1);
    assert.deepEqual(await readFile(join(output, "memory.json")), memory);
    const index = JSON.parse(await readFile(join(output, "index.json")));
    assert.deepEqual(
      index.examples.find((row) => row.file === "memory.json"),
      memoryEntry,
    );
    const document = JSON.parse(await readFile(join(output, "live-1.json")));
    assert.equal(document.provenance.archives.at(-1).name, "capture-extension");
    assert.equal(document.provenance.sources.length, 3);
    await writeFile(join(extension, "public.json"), `${publicBytes} `);
    await assert.rejects(
      () => prepareCaptureExtension(options),
      /hash\/length mismatch/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

/** Keep the archived interpretation intact while the new bundle resolves one
 * unknown nonstorage operand and adds a second explicitly recorded dependency. */
function refinementFixture() {
  const input = fixture();
  const unknown = {
    id: "unknown",
    producer: "root",
    origin: "unknown",
    storage: null,
    incarnation: "epoch",
    evidence: "Unresolved operand",
  };
  for (const graph of [input.base.bundle, input.bundle]) {
    graph.events[0].inputs = ["unknown"];
    graph.events[0].sequence = 1;
    graph.events[0].evidence = "Original actor observation";
    graph.versions.push(structuredClone(unknown));
  }
  input.bundle.events[1].sequence = 3;
  input.bundle.events.push({
    id: "producer",
    cycle: 0,
    sequence: 0,
    observer: "o",
    incarnation: "epoch",
    inputs: [],
    outputs: ["unknown"],
    evidence: "Observed operand result",
  });
  input.bundle.versions.push({
    id: "additional",
    producer: "root",
    origin: "unknown",
    storage: null,
    incarnation: "epoch",
    evidence: "Additional unresolved operand",
  });
  const refined = input.bundle.versions.find((row) => row.id === "unknown");
  Object.assign(refined, {
    producer: "producer",
    origin: "event",
    evidence: "Exact observed result identity in this capture",
  });
  input.bundle.events[0].inputs.push("additional");
  input.bundle.events[0].evidence = "Observed operand results supplied";
  return input;
}

/** Inventory the exact synthetic records, independently of the allowed-change
 * checks. A correct digest never authorizes a forbidden kind of mutation. */
function inventory(
  input,
  entries = [
    ["events", "old"],
    ["versions", "unknown"],
  ],
) {
  input.review.graph_refinements = entries.map(([table, id]) => ({
    table,
    id,
    before_sha256: graphRecordSha256(
      input.base.bundle[table].find((row) => row.id === id),
    ),
    after_sha256: graphRecordSha256(
      input.bundle[table].find((row) => row.id === id),
    ),
  }));
  return input;
}

test("graph record digests sort nested keys while preserving array order", () => {
  assert.equal(
    graphRecordSha256({ z: true, a: { y: [2, 1], x: 1 } }),
    digest('{"a":{"x":1,"y":[2,1]},"z":true}'),
  );
  assert.notEqual(
    graphRecordSha256({ a: [1, 2] }),
    graphRecordSha256({ a: [2, 1] }),
  );
});

test("reviewed ancestry refinement changes only the new interpretation", () => {
  const input = inventory(refinementFixture()),
    before = structuredClone(input);
  const document = apply(input);
  assert.deepEqual(input, before);
  assert.equal(
    input.base.bundle.versions.find((row) => row.id === "unknown").producer,
    "root",
  );
  assert.equal(
    document.bundle.versions.find((row) => row.id === "unknown").producer,
    "producer",
  );
  assert.deepEqual(
    document.provenance.capture_extension.review.graph_refinements,
    input.review.graph_refinements,
  );
  assert.deepEqual(document.catalogue.bindings, input.base.catalogue.bindings);
  assert.deepEqual(document.measurement, input.base.measurement);
  assert.equal(createModel(document).incoming.get("old")[0].source, "producer");
});

test("refinement inventory rejects wrong hashes, unlisted changes, duplicates and unused rows", () => {
  for (const field of ["before_sha256", "after_sha256"]) {
    const input = inventory(refinementFixture());
    input.review.graph_refinements[0][field] = identity("d");
    assert.throws(() => apply(input), /digest mismatch/);
  }
  const unlisted = inventory(refinementFixture(), [["versions", "unknown"]]);
  assert.throws(() => apply(unlisted), /Unreviewed original graph change/);
  const absent = refinementFixture();
  assert.throws(() => apply(absent), /Unreviewed original graph change/);
  const duplicate = inventory(refinementFixture());
  duplicate.review.graph_refinements.push({
    ...duplicate.review.graph_refinements[0],
  });
  assert.throws(() => apply(duplicate), /Duplicate graph refinement/);
  const unused = inventory(refinementFixture(), [
    ["events", "old"],
    ["versions", "unknown"],
    ["versions", "value"],
  ]);
  assert.throws(() => apply(unused), /Unused graph refinements/);
});

test("correct digests cannot authorize immutable event changes or dependency deletion", () => {
  const changes = [
    (event) => {
      event.cycle = 2;
    },
    (event) => {
      event.actor = "different-actor";
    },
    (event) => {
      event.resources = ["stream/reply"];
    },
    (event) => {
      event.access = {
        kind: "read_result",
        resource: "register/R",
        address: 0,
      };
    },
    (event) => {
      event.inputs = ["additional"];
    },
    (event) => {
      event.outputs = [];
    },
    (event) => {
      event.evidence = "";
    },
  ];
  for (const change of changes) {
    const input = refinementFixture();
    change(input.bundle.events[0]);
    inventory(input);
    assert.throws(
      () => apply(input),
      /immutable event|Removed original event|refinement evidence/,
    );
  }
});

test("root refinement rejects stored words, changed bit metadata and unsupported origins", () => {
  const changes = [
    (before, after) => {
      before.storage = after.storage = { resource: "register/R", address: 0 };
    },
    (_before, after) => {
      after.storage = { resource: "register/R", address: 0 };
    },
    (before, after) => {
      before.width = 8;
      after.width = 9;
    },
    (before) => {
      before.origin = "carry_in";
    },
    (_before, after) => {
      after.incarnation = "different-reset";
    },
    (_before, after) => {
      after.evidence = "";
    },
  ];
  for (const change of changes) {
    const input = refinementFixture();
    change(
      input.base.bundle.versions.find((row) => row.id === "unknown"),
      input.bundle.versions.find((row) => row.id === "unknown"),
    );
    inventory(input);
    assert.throws(
      () => apply(input),
      /unknown-root|immutable version|refinement evidence/,
    );
  }
});

test("resolved producers still obey reset and dependency time checks", () => {
  const future = inventory(refinementFixture());
  future.bundle.events.find((row) => row.id === "producer").cycle = 2;
  assert.throws(() => apply(future), /runs backward/);
  const crossReset = inventory(refinementFixture());
  crossReset.bundle.events.find((row) => row.id === "producer").incarnation =
    "other-reset";
  assert.throws(() => apply(crossReset), /cross-reset refinement producer/);
  const absent = inventory(refinementFixture());
  absent.bundle.events = absent.bundle.events.filter(
    (row) => row.id !== "producer",
  );
  assert.throws(() => apply(absent), /refinement producer/);
});

test("reviewed resource refinement permits only additional observation read lanes", () => {
  const input = fixture();
  input.base.bundle.resources[0].ports = { existing: "read", w: "write" };
  input.bundle.resources[0].ports = {
    existing: "read",
    w: "write",
    operand: "read",
  };
  inventory(input, [["resources", "register/R"]]);
  const document = apply(input);
  assert.equal(document.bundle.resources[0].ports.operand, "read");
  assert.deepEqual(document.catalogue.bindings, input.base.catalogue.bindings);
  for (const mutate of [
    (resource) => {
      resource.ports.w = "read";
    },
    (resource) => {
      resource.ports.extra = "write";
    },
    (resource) => {
      delete resource.ports.existing;
    },
    (resource) => {
      resource.width = 9;
    },
    (resource) => {
      resource.evidence = "rewritten storage evidence";
    },
  ]) {
    const changed = structuredClone(input);
    mutate(changed.bundle.resources[0]);
    inventory(changed, [["resources", "register/R"]]);
    assert.throws(
      () => apply(changed),
      /read-lane refinement|immutable resource/,
    );
  }
});

test("capture-extension command options compose with later precedence", () => {
  assert.deepEqual(
    parseArguments([
      "--capture-extension",
      "first",
      "--base-projection",
      "base.json",
      "--capture-extension",
      "last",
      "--output",
      "out",
    ]),
    { captureExtension: "last", baseProjection: "base.json", output: "out" },
  );
});

/** A later ancestry refinement must not duplicate navigation or erase the earlier native provenance. */
test("successive extensions retain provenance and replace the completion shortcut", () => {
  const input = fixture();
  const first = apply(input);
  const bundle = structuredClone(first.bundle);
  bundle.build.observation = identity("d");
  const review = {
    ...input.review,
    base_build: first.bundle.build,
    extended_build: bundle.build,
    original_trace_sha256: input.review.extended_trace_sha256,
    extended_trace_sha256: identity("e"),
  };
  assert.throws(
    () =>
      applyCaptureExtension(first, bundle, input.summary, {
        ...review,
        original_trace_sha256: identity("f"),
      }),
    /Extension preceding trace\/simulator mismatch/,
  );
  assert.throws(
    () =>
      applyCaptureExtension(first, bundle, input.summary, {
        ...review,
        original_simulator_sha256: identity("f"),
        extended_simulator_sha256: identity("f"),
      }),
    /Extension preceding trace\/simulator mismatch/,
  );
  const second = applyCaptureExtension(first, bundle, input.summary, review);
  assert.equal(second.title, first.title);
  const previous = second.provenance.capture_extension.previous_extension;
  assert.deepEqual(previous, first.provenance.capture_extension);
  assert.deepEqual(previous.review, input.review);
  assert.deepEqual(previous.original_scope, input.base.scope);
  assert.deepEqual(previous.original_coverage, input.base.coverage ?? null);
  assert.equal(previous.previous_extension, null);
  assert.equal(
    second.examples.filter((x) => x.id === "completion-ancestry").length,
    1,
  );
  assert.deepEqual(
    second.catalogue.correspondence_origin.previous_correspondence,
    first.catalogue.correspondence_origin,
  );
  assert.equal(
    second.catalogue.correspondence_origin.previous_correspondence.build
      .observation,
    identity("3"),
  );
});
