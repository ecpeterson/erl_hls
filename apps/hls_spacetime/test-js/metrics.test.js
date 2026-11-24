import test from "node:test";
import assert from "node:assert/strict";
import { createModel } from "../web/model.js";
import { windowMetrics } from "../web/metrics.js";

/** Two overlapping stored words, a masked replacement, reset and an independent
 * computation with optional observed waits. Native aliases share one FF. */
function fixture({ stalled = false, physical = true, complete = true } = {}) {
  const build = {
    source: "synthetic",
    rtl: "r",
    observation: "o",
    implementation: "i",
  };
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
            coordinate_unit: "tile_grid",
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

/** Distribution counts physical identities once even when logical words alias. */
test("tile bins separate installed concentration from windowed operation samples", () => {
  const model = createModel(fixture());
  const all = windowMetrics(model);
  assert.deepEqual(all.spatial, {
    status: "tile_grid",
    coordinateUnit: "tile_grid",
    binSizeTiles: 16,
    cells: 3,
    placedCells: 2,
    unplacedCells: 1,
    unknownKindCells: 0,
    occupiedTiles: 2,
    occupiedBins: 2,
    peakBinCells: 1,
    bins: [
      { x: 0, y: 0, installedCells: 1, byKind: { FDRE: 1 } },
      { x: 80, y: 16, installedCells: 1, byKind: { LUT6: 1 } },
    ],
    scope: "unique_installed_cells_not_capacity_or_switching",
  });
  const empty = windowMetrics(model, { firstCycle: 9, endCycle: 10 });
  assert.deepEqual(empty.spatial, all.spatial);
  assert.equal(empty.activity.eventSamples, 0);
  assert.equal(empty.activity.clocksWithEvents, 0);
  assert.equal(empty.activity.peakEventsPerClock, 0);
  const reader = windowMetrics(model, { actor: "reader" });
  assert.deepEqual(reader.spatial, all.spatial);
  assert.deepEqual(reader.activity.byClock, [{ cycle: 6, eventSamples: 2 }]);
  assert.equal(reader.activity.peakEventsPerClock, 2);
  assert.deepEqual(reader.activity.byOperation, { read: 1, result: 1 });
});

/** Moving an installed cell changes distribution without inventing activity. */
test("changed placement and unknown metadata remain explicit in spatial metrics", () => {
  const document = fixture();
  document.catalogue.cells[1].x = 4;
  document.catalogue.cells[1].y = 6;
  document.catalogue.cells[2].kind = null;
  const changed = windowMetrics(createModel(document));
  assert.equal(changed.spatial.cells, 3);
  assert.equal(changed.spatial.occupiedBins, 1);
  assert.equal(changed.spatial.occupiedTiles, 2);
  assert.equal(changed.spatial.peakBinCells, 2);
  assert.equal(changed.spatial.unplacedCells, 1);
  assert.equal(changed.spatial.unknownKindCells, 1);
  assert.deepEqual(changed.spatial.bins[0].byKind, { FDRE: 1, LUT6: 1 });
  assert.deepEqual(
    changed.activity,
    windowMetrics(createModel(fixture())).activity,
  );
  delete document.catalogue.coordinate_unit;
  const unknown = windowMetrics(createModel(document)).spatial;
  assert.equal(unknown.status, "unknown_coordinate_unit");
  assert.equal(unknown.occupiedBins, null);
  assert.equal(unknown.peakBinCells, null);
  assert.deepEqual(unknown.bins, []);
  assert.equal(
    windowMetrics(createModel(fixture({ physical: false }))).spatial,
    null,
  );
});

/** Explicit stalls change observed timing and concurrency, never installed area. */
test("stalled recording changes temporal samples independently of installed bins", () => {
  const normal = windowMetrics(createModel(fixture()), {
    firstCycle: 2,
    endCycle: 6,
  });
  const stalled = windowMetrics(createModel(fixture({ stalled: true })), {
    firstCycle: 2,
    endCycle: 8,
  });
  assert.deepEqual(normal.spatial, stalled.spatial);
  assert.equal(normal.activity.eventSamples, 3);
  assert.equal(normal.activity.clocksWithEvents, 3);
  assert.equal(normal.activity.peakEventsPerClock, 1);
  assert.equal(stalled.activity.eventSamples, 8);
  assert.equal(stalled.activity.clocksWithEvents, 5);
  assert.equal(stalled.activity.peakEventsPerClock, 3);
  assert.equal(stalled.activity.byOperation.entry_wait, 3);
  assert.equal(
    stalled.activity.scope,
    "recorded_operations_not_electrical_activity_or_idle_time",
  );
});

test("spatial bin widths and qualified tile coordinates reject invalid arithmetic", () => {
  const model = createModel(fixture());
  for (const tileBinSize of [0, -1, 1.5, Infinity, Number.MAX_SAFE_INTEGER + 1])
    assert.throws(() => windowMetrics(model, { tileBinSize }), /tile bin size/);
  const smaller = windowMetrics(model, { tileBinSize: 2 }).spatial;
  assert.deepEqual(
    smaller.bins.map(({ x, y }) => [x, y]),
    [
      [0, 2],
      [90, 30],
    ],
  );
  const invalid = fixture();
  invalid.catalogue.cells[0].x = 0.5;
  assert.throws(() => windowMetrics(createModel(invalid)), /tile X coordinate/);
});

/** The same clocks may be explored at an assumed period, never promoted to measured time. */
test("failed target and static delays remain distinct from hypothetical elapsed time", () => {
  const document = fixture();
  document.measurement = {
    target_met: false,
    target_period_ns: 5,
    constraint_equivalent_period_ns: 8.997,
    worst_data_delay_ns: 8.808,
  };
  const model = createModel(document);
  const unknown = windowMetrics(model);
  assert.equal(unknown.timing.execution, null);
  assert.equal(unknown.timing.whatIf, null);
  assert.equal(unknown.timing.reason, "failed_target_is_not_execution_period");
  const assumed = windowMetrics(model, { whatIfPeriodNs: 5, usedOnly: false });
  assert.equal(assumed.interval.elapsedClocks, 12);
  assert.equal(assumed.storage.totalWordClocks, 20);
  assert.deepEqual(assumed.timing.whatIf, {
    periodNs: 5,
    elapsedClocks: 12,
    elapsedNs: 60,
    scope: "hypothetical_clock_period_not_execution_measurement",
  });
  assert.equal(assumed.timing.execution, null);
  assert.equal(
    assumed.timing.scope,
    "elapsed_clocks_times_period_without_adding_static_path_delay",
  );
  document.measurement.target_met = true;
  assert.equal(
    windowMetrics(createModel(document)).timing.reason,
    "no_qualified_execution_period",
  );
  assert.equal(windowMetrics(createModel(document)).timing.execution, null);
});

/** A longer observed interval changes assumed time once; waits and storage do not add again. */
test("stalled interval scales hypothetical time without adding waits or storage", () => {
  const normal = windowMetrics(createModel(fixture()), {
    firstCycle: 2,
    endCycle: 6,
    whatIfPeriodNs: 2.5,
    waitOperations: ["entry_wait"],
  });
  const stalled = windowMetrics(createModel(fixture({ stalled: true })), {
    firstCycle: 2,
    endCycle: 8,
    whatIfPeriodNs: 2.5,
    waitOperations: ["entry_wait"],
  });
  assert.equal(normal.timing.whatIf.elapsedNs, 10);
  assert.equal(stalled.timing.whatIf.elapsedNs, 15);
  assert.equal(stalled.waits.clockSamples, 2);
  assert.equal(stalled.timing.execution, null);
  assert.deepEqual(normal.spatial, stalled.spatial);
});

test("hypothetical periods and elapsed products reject nonfinite or excessive values", () => {
  const model = createModel(fixture());
  for (const whatIfPeriodNs of [
    0,
    -1,
    "5",
    NaN,
    Infinity,
    Number.MAX_SAFE_INTEGER + 1,
  ])
    assert.throws(
      () => windowMetrics(model, { whatIfPeriodNs }),
      /hypothetical clock period/,
    );
  assert.throws(
    () => windowMetrics(model, { whatIfPeriodNs: Number.MAX_SAFE_INTEGER }),
    /hypothetical elapsed time/,
  );
});
