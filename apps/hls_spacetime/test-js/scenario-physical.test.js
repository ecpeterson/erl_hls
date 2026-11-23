import test from "node:test";
import assert from "node:assert/strict";
import { scenarioPhysical } from "../web/scenario-physical.js";

/** Synthetic prepared indexes supply independent per-root arrivals. No routing,
 * simulation or compiler is involved in this census fixture. */
function fixture(rows, { unmappedWrite = false } = {}) {
  const cones = [],
    pinGeometry = [],
    operations = new Map(),
    writes = new Map(),
    events = new Map(),
    resources = new Map();
  for (const [pin, row] of rows.entries()) {
    pinGeometry.push([pin, pin, 0, row.name ?? `state${pin}/D`]);
    const coneIds = (row.values ?? [row.delay]).map((value, part) => {
      const id = cones.length;
      cones.push({
        id: `${row.role ?? "data"}/${pin}/${part}`,
        role: row.role ?? "data",
        rootPins: [pin],
        pinIndices: [pin],
        pinArrivals: { registered: [value] },
        coverage: { cyclic: false, unsupportedFrontiers: 0 },
      });
      return id;
    });
    for (const resource of row.resources ?? [`word${pin}`]) {
      resources.set(resource, { id: resource });
      for (const cycle of row.cycles ?? [pin + 1]) {
        const event = {
          id: `write${events.size}`,
          cycle,
          access: { kind: "write", resource },
        };
        events.set(event.id, event);
        operations.set(event.id, {
          event: event.id,
          applicability: "storage_write",
          writes: [],
        });
        writes.set(event.id, {
          cones: [...coneIds],
          coverage: { requestedBits: 1, mappedBits: 1, unknownBits: 0 },
        });
      }
    }
  }
  if (unmappedWrite) {
    resources.set("unmapped", { id: "unmapped" });
    events.set("unmapped", {
      id: "unmapped",
      cycle: 99,
      access: { kind: "write", resource: "unmapped" },
    });
    operations.set("unmapped", {
      event: "unmapped",
      applicability: "storage_write",
      writes: [],
    });
    writes.set("unmapped", {
      cones: [],
      coverage: { requestedBits: 2, mappedBits: 0, unknownBits: 2 },
    });
  }
  return {
    prepared: true,
    cones,
    pinGeometry,
    writes,
    operations,
    model: { resources, events },
  };
}
const cut = {
  status: "known",
  sink: { pin: 0, role: "data", name: "changed/D" },
  stage1DelayNs: 4,
  stage2DelayNs: 4,
  signalBits: 7,
  alignmentComplete: false,
};

test("a separate recorded 9ns target survives an 8ns target's 4+4 cut", () => {
  const index = fixture([
    { name: "changed/D", delay: 8, resources: ["changed"], cycles: [1, 20] },
    { name: "other/CE", role: "enable", delay: 9, resources: ["other"] },
  ]);
  const original = structuredClone(index);
  const result = scenarioPhysical(index, {
    changedResources: ["changed"],
    cut,
    candidatePeriodNs: 5,
    // A caller's view selection cannot narrow the complete recording census.
    firstCycle: 1,
    endCycle: 2,
    roles: ["data"],
  });
  assert.equal(result.coverage.total, 2);
  assert.equal(result.coverage.recordedWrites, 3);
  assert.equal(result.coverage.aboveCandidatePeriod, 2);
  assert.equal(result.groups.targeted.largestKnown.pinName, "changed/D");
  assert.equal(result.groups.targeted.largestKnown.writeAssociations, 2);
  assert.equal(result.groups.notTargeted.largestKnown.pinName, "other/CE");
  assert.equal(result.groups.notTargeted.largestKnown.delayNs, 9);
  assert.equal(result.groups.notTargeted.counts.aboveCandidatePeriod, 1);
  assert.equal(result.largestKnownRecordedTarget.delayNs, 9);
  assert.deepEqual(result.cut, {
    status: "known",
    sink: cut.sink,
    matchesTargetedSink: true,
    stage1DelayNs: 4,
    stage2DelayNs: 4,
    registerBitsLowerBound: 7,
    alignmentComplete: false,
    scope: "single_sink_retained_delay_anchor",
  });
  assert.equal(result.globalClockForecastNs, null);
  assert.deepEqual(index, original);
  assert.deepEqual(
    result,
    scenarioPhysical(index, {
      changedResources: ["changed"],
      cut,
      candidatePeriodNs: 5,
    }),
  );
});

test("unknown partial maxima and outside-scope roots stay outside numerical counts", () => {
  const index = fixture(
    [
      { name: "partial/D", values: [20, null] },
      { name: "outside/R", delay: "not_applicable", role: "reset" },
      { name: "known/D", delay: 5 },
    ],
    { unmappedWrite: true },
  );
  const result = scenarioPhysical(index, { candidatePeriodNs: 5 });
  assert.deepEqual(result.groups.notTargeted.counts, {
    total: 3,
    known: 1,
    unknown: 1,
    notApplicable: 1,
    aboveCandidatePeriod: 0,
  });
  const partial = result.targets.find((row) => row.pinName === "partial/D");
  assert.equal(partial.delayNs, null);
  assert.equal(partial.knownDelayNs, 20);
  assert.deepEqual(partial.reasons, ["unknown_sink_arrival"]);
  assert.equal(result.largestKnownRecordedTarget.pinName, "known/D");
  assert.equal(result.coverage.writesWithoutCones, 1);
  assert.deepEqual(result.coverage.writeBitOccurrences, {
    requested: 5,
    mapped: 3,
    unknown: 2,
  });
  assert.equal(result.globalClockForecastNs, null);
});

test("aliases are touched by any selected resource and retain ambiguity", () => {
  const index = fixture([
    { name: "shared/D", delay: 3, resources: ["a", "b"] },
    { name: "alone/D", delay: 3, resources: ["c"] },
  ]);
  const result = scenarioPhysical(index, { changedResources: new Set(["a"]) });
  const shared = result.groups.targeted.largestKnown;
  assert.deepEqual(shared.resources, ["a", "b"]);
  assert.deepEqual(shared.changedResources, ["a"]);
  assert.equal(shared.ambiguousResourceAssociation, true);
  assert.equal(shared.mixedResourceSelection, true);
  assert.equal(result.coverage.total, 2);
  assert.equal(result.coverage.ambiguousResourceTargets, 1);
  assert.equal(result.groups.notTargeted.counts.total, 1);
  assert.equal(result.coverage.aboveCandidatePeriod, null);
  const all = scenarioPhysical(index, { changedResources: ["b", "a"] });
  assert.equal(all.groups.targeted.largestKnown.mixedResourceSelection, false);
  assert.equal(
    all.groups.targeted.largestKnown.ambiguousResourceAssociation,
    true,
  );
});

test("ties, exact threshold equality, changed periods and result mutation stay honest", () => {
  const index = fixture([
    { name: "z/D", delay: 6 },
    { name: "a/D", delay: 6 },
  ]);
  const first = scenarioPhysical(index, { candidatePeriodNs: 6 });
  assert.deepEqual(
    first.groups.notTargeted.largestKnownTargets.map((row) => row.pinName),
    ["a/D", "z/D"],
  );
  assert.equal(first.coverage.aboveCandidatePeriod, 0);
  first.targets[0].resources.length = 0;
  first.coverage.writeBitOccurrences.requested = 0;
  const second = scenarioPhysical(index, {
    changedResources: ["word1"],
    candidatePeriodNs: 5,
  });
  assert.equal(second.coverage.aboveCandidatePeriod, 2);
  assert.equal(second.coverage.writeBitOccurrences.requested, 2);
  assert.equal(second.groups.targeted.largestKnown.pinName, "a/D");
  assert.equal(second.globalClockForecastNs, null);
});

test("empty, all-unknown and unavailable cuts never invent a period or ranking", () => {
  const empty = scenarioPhysical(fixture([]), { cut: null });
  assert.equal(empty.largestKnownRecordedTarget, null);
  assert.equal(empty.cut, null);
  const unknown = scenarioPhysical(fixture([{ delay: null }]), {
    cut: { status: "unknown", reason: "unknown_eligible_timing" },
  });
  assert.equal(unknown.groups.notTargeted.largestKnown, null);
  assert.deepEqual(unknown.cut, {
    status: "unknown",
    reason: "unknown_eligible_timing",
  });
  assert.equal(unknown.candidatePeriodNs, null);
  assert.equal(unknown.globalClockForecastNs, null);
});

test("invalid hypotheses reject without deriving alternatives from cut stages", () => {
  const index = fixture([{ delay: 8, resources: ["changed"] }]);
  for (const period of [0, -1, Infinity, NaN, "5"])
    assert.throws(
      () => scenarioPhysical(index, { candidatePeriodNs: period }),
      /candidate period/,
    );
  assert.throws(
    () => scenarioPhysical(index, { changedResources: ["invented"] }),
    /unknown changed resource/,
  );
  assert.throws(
    () => scenarioPhysical(index, { cut: { ...cut, stage2DelayNs: null } }),
    /known cut/,
  );
  const result = scenarioPhysical(index, { cut });
  assert.equal(result.cut.matchesTargetedSink, false);
  assert.equal(result.candidatePeriodNs, null);
  assert.equal(result.globalClockForecastNs, null);
});
