import test from "node:test";
import assert from "node:assert/strict";
import {
  auditStorageView,
  parseArguments,
} from "../scripts/check-storage-view.mjs";

/** One word: full replacements, read-first overwrite, delayed response, reset,
 * and a final write without a next sample. Values never identify versions. */
function fixture() {
  const storage = { resource: "word", address: 0 };
  const versions = [
    {
      id: "root",
      producer: "root",
      origin: "unknown",
      incarnation: "a",
      storage,
    },
    {
      id: "carry",
      producer: "root",
      origin: "carry_in",
      incarnation: "b",
      storage,
    },
  ];
  const events = [];
  const add = (id, cycle, inputs, output, access, incarnation = "a") => {
    events.push({
      id,
      cycle,
      inputs,
      outputs: output ? [output] : [],
      incarnation,
      observer: "observer",
      sequence: events.length,
      actor: "synthetic",
      activation: id,
      task: "fixture",
      operation: access.kind,
      access: { ...storage, ...access },
      evidence: "synthetic storage record",
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation,
        storage: access.kind === "write" ? storage : null,
      });
  };
  add("write", 1, [], "one", {
    kind: "write",
    port: "w",
    before: "root",
    after_version: "one",
    mask: "0xFF",
  });
  add("equal-write", 2, [], "two", {
    kind: "write",
    port: "w",
    before: "one",
    after_version: "two",
    mask: "0xFF",
  });
  add("read", 3, ["two"], null, {
    kind: "read_request",
    port: "r",
    version: "two",
  });
  add("masked", 3, ["two"], "three", {
    kind: "write",
    port: "w",
    before: "two",
    after_version: "three",
    mask: "0x0F",
  });
  add("response", 5, ["two"], "result", {
    kind: "read_result",
    port: "r",
    version: "two",
    request: "read",
  });
  add("pending", 6, ["three"], null, {
    kind: "read_request",
    port: "r",
    version: "three",
  });
  add(
    "final",
    9,
    [],
    "last",
    {
      kind: "write",
      port: "w",
      before: "carry",
      after_version: "last",
      mask: "0xFF",
    },
    "b",
  );
  return {
    format: "spacetime-view",
    schema: 1,
    catalogue: null,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      events,
      versions,
      relations: [],
      resources: [
        {
          id: "word",
          kind: "register",
          width: 8,
          depth: 1,
          read_latency: 2,
          collision: "read_first",
          reset: "retained",
        },
      ],
      capture: {
        first_cycle: 0,
        end_cycle: 10,
        complete: true,
        incarnations: [
          { id: "a", first_cycle: 0, end_cycle: 7 },
          { id: "b", first_cycle: 7, end_cycle: 10 },
        ],
        observers: [
          {
            id: "observer",
            first_sequence: 0,
            next_sequence: events.length,
            gaps: [],
          },
        ],
      },
    },
  };
}

/** Select a synthetic access without coupling tests to array order. */
function event(document, id) {
  return document.bundle.events.find((item) => item.id === id);
}

test("independent replay checks full writes, retained clocks and delayed read identity", () => {
  const result = auditStorageView(fixture());
  assert.equal(result.qualified_storage_edges, true);
  assert.equal(result.comparisons, 8);
  assert.equal(result.write_bridges, 3);
  assert.equal(result.hold_bridges, 5);
  assert.equal(result.committed_writes, 4);
  assert.equal(result.full_writes, 3);
  assert.equal(result.masked_writes, 1);
  assert.equal(result.responses_after_replacement, 1);
  assert.equal(result.reset_retired_requests, 1);
  assert.equal(result.terminal_writes_without_next_sample, 1);
  assert.equal(result.unknown_storage_roots, 1);
});

test("a wrong write-before identity rejects independently of output identity", () => {
  const doc = fixture();
  event(doc, "equal-write").access.before = "three";
  assert.throws(() => auditStorageView(doc), /Stale write before-version/);
});

test("read-first selection rejects an overwritten older version", () => {
  const doc = fixture(),
    read = event(doc, "read");
  read.access.version = "one";
  read.inputs = ["one"];
  assert.throws(() => auditStorageView(doc), /Wrong selected read version/);
});

test("a delayed response must use its request rather than the newer stored word", () => {
  const doc = fixture(),
    response = event(doc, "response");
  response.access.version = "three";
  response.inputs = ["three"];
  assert.throws(() => auditStorageView(doc), /Read response\/request mismatch/);
});

test("reset requires the new incarnation's root instead of the old word", () => {
  const doc = fixture();
  event(doc, "final").access.before = "three";
  assert.throws(() => auditStorageView(doc), /Stale write before-version/);
});

test("incomplete or gapped records leave storage continuity unqualified", () => {
  const incomplete = fixture();
  incomplete.bundle.capture.complete = false;
  assert.equal(auditStorageView(incomplete).qualified_storage_edges, false);
  const gapped = fixture();
  gapped.bundle.capture.complete = false;
  gapped.bundle.capture.observers[0].gaps = [
    { first_sequence: 0, next_sequence: 1 },
  ];
  assert.equal(auditStorageView(gapped).qualified_storage_edges, false);
  gapped.bundle.capture.complete = true;
  assert.throws(
    () => auditStorageView(gapped),
    /Complete capture declares observer loss/,
  );
});

test("the comparison budget rejects before expanding compressed residence", () => {
  assert.throws(
    () => auditStorageView(fixture(), { maxComparisons: 7 }),
    /comparison budget exceeded/,
  );
});

test("a response already due before reset cannot be labelled reset-retired", () => {
  const doc = fixture();
  doc.bundle.events = doc.bundle.events.filter(
    (item) => item.id !== "response",
  );
  doc.bundle.versions = doc.bundle.versions.filter(
    (item) => item.id !== "result",
  );
  doc.bundle.events.forEach((item, index) => {
    item.sequence = index;
  });
  doc.bundle.capture.observers[0].next_sequence = doc.bundle.events.length;
  assert.throws(() => auditStorageView(doc), /Missing due read response/);
});

test("later comparison limits override earlier command prefixes", () => {
  assert.deepEqual(
    parseArguments([
      "capture.json",
      "--max-comparisons",
      "1",
      "--max-comparisons",
      "20",
    ]),
    { path: "capture.json", maxComparisons: 20 },
  );
});
