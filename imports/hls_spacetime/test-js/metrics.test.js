import test from "node:test";
import assert from "node:assert/strict";
import { createModel } from "../web/model.js";
import { windowMetrics } from "../web/metrics.js";

/** Two overlapping stored words, a masked replacement, reset and an independent
 * computation with optional observed waits. Native aliases share one FF. */
function fixture({ stalled = false, physical = true, complete = true } = {}) {
  const build = { source: "synthetic", rtl: "r", observation: "o" };
  const events = [],
    versions = [];
  const root = (id, origin, storage = null, incarnation = "epoch0") => {
    versions.push({
      id,
      producer: "root",
      origin,
      storage,
      incarnation,
      evidence: "synthetic root",
    });
  };
  const add = (
    id,
    cycle,
    operation,
    inputs = [],
    output = null,
    access = null,
    actor = "worker",
    incarnation = "epoch0",
  ) => {
    events.push({
      id,
      cycle,
      sequence: events.length,
      operation,
      actor,
      task: "fixture",
      activation: `${actor}/${incarnation}`,
      observer: "observer",
      incarnation,
      inputs,
      outputs: output ? [output] : [],
      evidence: "synthetic observation",
      ...(access ? { access } : {}),
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation,
        storage:
          access?.kind === "write"
            ? { resource: access.resource, address: 0 }
            : null,
        evidence: "synthetic output",
      });
  };
  const storage = (resource) => ({ resource, address: 0 });
  const write = (
    id,
    cycle,
    resource,
    before,
    after,
    mask = "0xFF",
    incarnation = "epoch0",
  ) =>
    add(
      id,
      cycle,
      "write",
      mask === "0xFF" ? [] : [before],
      after,
      {
        ...storage(resource),
        port: "w",
        kind: "write",
        before,
        after_version: after,
        mask,
      },
      "writer",
      incarnation,
    );
  root("a0", "unknown", storage("a"));
  root("b0", "unknown", storage("b"));
  root("a-carry", "carry_in", storage("a"), "epoch1");
  root("b-carry", "carry_in", storage("b"), "epoch1");
  root("opaque", "unknown");
  root("seed", "initial");
  write("write-a", 1, "a", "a0", "a1");
  write("write-b", 1, "b", "b0", "b1");
  write("masked-a", 4, "a", "a1", "a2", "0x0F");
  add(
    "read-a",
    6,
    "read",
    ["a2"],
    null,
    { ...storage("a"), port: "r", kind: "read_request", version: "a2" },
    "reader",
  );
  add(
    "result-a",
    6,
    "result",
    ["a2"],
    "read-value",
    {
      ...storage("a"),
      port: "r",
      kind: "read_result",
      version: "a2",
      request: "read-a",
    },
    "reader",
  );
  write("terminal-a", 11, "a", "a-carry", "last", "0xFF", "epoch1");
  add("start", 2, "compute", ["opaque", "seed"], "started");
  if (stalled) {
    add("wait1", 5, "entry_wait", ["started"], "waited1");
    add("wait2", 6, "entry_wait", ["waited1"], "waited2");
    add("parallel-wait", 5, "entry_wait", ["opaque"], null, null, "other");
  }
  add(
    "finish",
    stalled ? 7 : 5,
    "complete",
    [stalled ? "waited2" : "started"],
    "done",
  );
  events.sort((a, b) => a.cycle - b.cycle || a.sequence - b.sequence);
  events.forEach((event, i) => {
    event.sequence = i;
  });
  return {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        first_cycle: 0,
        end_cycle: 12,
        complete,
        evidence: "synthetic scope",
        observers: [
          {
            id: "observer",
            gaps: [],
            first_sequence: 0,
            next_sequence: events.length,
            scope: "synthetic",
          },
        ],
        incarnations: [
          { id: "epoch0", first_cycle: 0, end_cycle: 8 },
          { id: "epoch1", first_cycle: 8, end_cycle: 12 },
        ],
      },
      resources: ["a", "b"].map((id) => ({
        id,
        kind: "register",
        width: 8,
        depth: 1,
        read_latency: 0,
        ports: { r: "read", w: "write" },
        collision: "read_first",
        reset: "retained",
        evidence: "synthetic word",
      })),
      events,
      versions,
      relations: stalled
        ? [
            {
              source: "read-a",
              target: "finish",
              kind: "resource_order",
              resource: "a",
              evidence: "observed only, not required ancestry",
            },
          ]
        : [],
      activity: [],
      physical: null,
    },
    ...(physical
      ? {
          catalogue: {
            build,
            checkpoint: "synthetic-dcp",
            cells: [
              { id: "ff", kind: "FDRE", x: 1, y: 2 },
              { id: "lut", kind: "LUT6", x: 90, y: 30 },
              { id: "constant", kind: "VCC", x: null, y: null },
            ],
            bindings: ["a", "b"].map((resource) => ({
              resource,
              disposition: "merged",
              cells: ["ff"],
              evidence: "synthetic alias",
            })),
          },
        }
      : {}),
  };
}

test("overlapping words sum word-clock edges, not elapsed time or physical area", () => {
  const model = createModel(fixture()),
    original = structuredClone(model);
  const result = windowMetrics(model, { usedOnly: false });
  assert.deepEqual(result.interval, {
    firstCycle: 0,
    endCycle: 12,
    elapsedClocks: 12,
  });
  assert.equal(result.storage.loadWordClocks, 3);
  assert.equal(result.storage.holdWordClocks, 17);
  assert.equal(result.storage.totalWordClocks, 20);
  assert.equal(result.storage.wordsWithConnections, 2);
  assert.deepEqual(result.installed, {
    cells: 3,
    placedCells: 2,
    unplacedCells: 1,
    byKind: { FDRE: 1, LUT6: 1, VCC: 1 },
  });
  assert.deepEqual(model, original);
});

test("window clipping stops at reset and a single clock has no storage edge", () => {
  const model = createModel(fixture());
  const result = windowMetrics(model, {
    firstCycle: 3,
    endCycle: 10,
    usedOnly: false,
  });
  assert.equal(result.interval.elapsedClocks, 7);
  assert.equal(result.storage.loadWordClocks, 1);
  assert.equal(result.storage.holdWordClocks, 9);
  assert.deepEqual(result.coverage.incarnations, ["epoch0", "epoch1"]);
  const single = windowMetrics(model, {
    firstCycle: 8,
    endCycle: 9,
    usedOnly: false,
  });
  assert.equal(single.storage.totalWordClocks, 0);
  assert.equal(single.interval.elapsedClocks, 1);
  assert.equal(single.installed.cells, result.installed.cells);
});

test("used-only storage and event filters preserve their declared selection scope", () => {
  const model = createModel(fixture());
  const used = windowMetrics(model);
  assert.equal(used.storage.policy, "recorded_uses");
  assert.equal(used.storage.totalWordClocks, 5);
  assert.equal(used.storage.wordsWithConnections, 1);
  const reader = windowMetrics(model, {
    firstCycle: 1,
    endCycle: 4,
    actor: "reader",
  });
  assert.equal(reader.recordedEvents, 0);
  assert.equal(reader.storage.wordsWithConnections, 0);
  assert.equal(reader.installed.cells, 3);
  const broader = windowMetrics(model, { actor: "reader" });
  assert.equal(broader.recordedEvents, 2);
  assert.equal(broader.storage.totalWordClocks, 2);
});

test("explicit wait samples change with stalls; unsampled gaps are not wait time", () => {
  const normal = windowMetrics(createModel(fixture()), {
    firstCycle: 2,
    endCycle: 6,
    selectedEvent: "finish",
    waitOperations: ["entry_wait"],
  });
  const stalled = windowMetrics(createModel(fixture({ stalled: true })), {
    firstCycle: 2,
    endCycle: 8,
    selectedEvent: "finish",
    waitOperations: ["entry_wait"],
  });
  assert.equal(normal.interval.elapsedClocks, 4);
  assert.equal(stalled.interval.elapsedClocks, 6);
  assert.equal(normal.waits.status, "not_observed");
  assert.equal(normal.waits.clockSamples, 0);
  assert.equal(stalled.waits.eventSamples, 3);
  assert.equal(stalled.waits.clockSamples, 2);
  assert.equal(normal.ancestry.spanClocks, 3);
  assert.equal(stalled.ancestry.spanClocks, 5);
  assert.equal(stalled.ancestry.events, 4);
  assert.deepEqual(stalled.ancestry.rootsByOrigin, { initial: 1, unknown: 1 });
  assert.equal(stalled.ancestry.scope, "recorded_dependencies_only");
});

test("unknown evidence stays distinct from measured zero and bounded ancestry", () => {
  const model = createModel(
    fixture({ complete: false, physical: false, stalled: true }),
  );
  const result = windowMetrics(model, {
    firstCycle: 7,
    endCycle: 8,
    selectedEvent: "finish",
    maxTraceEvents: 2,
  });
  assert.equal(result.installed, null);
  assert.equal(result.coverage.completeWithinObserverScope, false);
  assert.equal(result.waits.status, "unclassified");
  assert.equal(result.waits.eventSamples, null);
  assert.equal(result.ancestry.truncated, true);
  assert.equal(result.ancestry.events, 2);
  assert.equal(result.ancestry.eventsOutsideWindow, 1);
});

test("invalid windows, bounds, classifications and unknown selections reject", () => {
  const model = createModel(fixture());
  for (const options of [
    { firstCycle: -1 },
    { endCycle: 13 },
    { firstCycle: 4, endCycle: 4 },
    { maxRecords: 1 },
    { maxTraceEvents: 0 },
    { usedOnly: "yes" },
    { waitOperations: [""] },
    { selectedEvent: "absent" },
  ])
    assert.throws(() => windowMetrics(model, options));
});
