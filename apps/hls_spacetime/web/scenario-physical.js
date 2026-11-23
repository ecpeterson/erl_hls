/** Saved registered-launch bounds for all recorded mapped targets. Display
 * filters never define this population; a period is an explicit hypothesis. */
import { sinkRows } from "./sink-paths.js";
const censuses = new WeakMap();
const finite = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;
const count = (value) => Number.isSafeInteger(value) && value >= 0;
const lexical = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
function check(ok, reason) {
  if (!ok) throw Error(`Scenario physical: ${reason}`);
}

/** One aggregate layer retains every write/cone association without duplicating
 * arc/pin/cell unions for each clock. Indexes are validated and immutable. */
function census(index) {
  if (!censuses.has(index)) {
    const operations = [];
    const bits = { requested: 0, mapped: 0, unknown: 0 };
    let writesWithoutCones = 0;
    for (const [id, write] of index.writes) {
      operations.push(index.operations.get(id));
      bits.requested += write.coverage.requestedBits;
      bits.mapped += write.coverage.mappedBits;
      bits.unknown += write.coverage.unknownBits;
      if (!write.cones.length) writesWithoutCones++;
    }
    const rows = sinkRows(index, [{ cones: index.cones, operations }], {
      scope: "registered",
    });
    censuses.set(index, { rows, bits, writesWithoutCones });
  }
  return censuses.get(index);
}

/** Copy presentation fields so changing a result cannot corrupt cached evidence.
 * Several logical resources may alias one target; any selected association makes
 * it targeted, without claiming exclusive ownership or a complete change scope. */
function target(row, changed) {
  const changedResources = row.resources.filter((id) => changed.has(id));
  return {
    key: row.key,
    pin: row.pin,
    pinName: row.pinName,
    role: row.role,
    status: row.status,
    delayNs: row.delayNs,
    knownDelayNs: row.knownDelayNs,
    reasons: [...row.reasons],
    resources: [...row.resources],
    changedResources,
    targeted: changedResources.length > 0,
    ambiguousResourceAssociation: row.resources.length > 1,
    mixedResourceSelection:
      changedResources.length > 0 &&
      changedResources.length < row.resources.length,
    writeAssociations: row.occurrences,
    coneIds: [...row.coneIds],
  };
}

/** Only complete known bounds enter numeric rankings; a partial known maximum
 * on an unknown target remains descriptive evidence, never a qualified bound. */
function group(rows, period) {
  const known = rows.filter((row) => row.status === "known");
  const maximum = known.reduce(
    (value, row) => Math.max(value ?? 0, row.delayNs),
    null,
  );
  const largestKnownTargets =
    maximum === null ? [] : known.filter((row) => row.delayNs === maximum);
  return {
    counts: {
      total: rows.length,
      known: known.length,
      unknown: rows.filter((row) => row.status === "unknown").length,
      notApplicable: rows.filter((row) => row.status === "not_applicable")
        .length,
      aboveCandidatePeriod:
        period === null
          ? null
          : known.filter((row) => row.delayNs > period).length,
    },
    largestKnown: largestKnownTargets[0] ?? null,
    largestKnownTargets,
  };
}

/** A single-sink cut is an anchor only. Its stages do not replace other targets,
 * infer a period, or qualify coupled-output latency or architectural legality. */
function cutSummary(cut, targets) {
  if (cut === undefined || cut === null) return null;
  check(
    ["known", "unknown", "not_applicable"].includes(cut.status),
    "invalid cut status",
  );
  if (cut.status !== "known")
    return { status: cut.status, reason: cut.reason ?? null };
  check(
    finite(cut.stage1DelayNs) &&
      finite(cut.stage2DelayNs) &&
      count(cut.signalBits) &&
      cut.sink &&
      Number.isSafeInteger(cut.sink.pin),
    "invalid known cut",
  );
  const matchesTargetedSink = targets.some(
    (row) =>
      row.targeted && row.pin === cut.sink.pin && row.role === cut.sink.role,
  );
  return {
    status: "known",
    sink: {
      pin: cut.sink.pin,
      role: cut.sink.role,
      name: cut.sink.name ?? null,
    },
    matchesTargetedSink,
    stage1DelayNs: cut.stage1DelayNs,
    stage2DelayNs: cut.stage2DelayNs,
    registerBitsLowerBound: cut.signalBits,
    alignmentComplete: cut.alignmentComplete === true,
    scope: "single_sink_retained_delay_anchor",
  };
}

/** Census the entire validated prepared recording, irrespective of viewer
 * filters. changedResources is an array/Set of exact logical resource IDs;
 * unknown IDs and nonpositive/nonfinite period hypotheses throw. Empty changes
 * are allowed. One native pin/role counts once, regardless of writes/clocks.
 *
 * Return named largest known targeted/not-targeted bounds, complete status and
 * bit-coverage counts, every target association and an optional cut anchor.
 * Above-period counts use strict > and remain null without an assumed period.
 * Unknown contributors never become numeric bounds. Not-targeted means outside
 * the declared resource set, not physically unchanged after an implementation.
 * All maxima exclude unrecorded/unmapped endpoints and clock/endpoint checks;
 * globalClockForecastNs is always null, even when known target bounds fit. */
export function scenarioPhysical(
  index,
  { changedResources = [], cut = null, candidatePeriodNs = null } = {},
) {
  check(
    index?.prepared === true &&
      index.model?.resources instanceof Map &&
      index.writes instanceof Map &&
      index.operations instanceof Map,
    "validated prepared index required",
  );
  check(
    Array.isArray(changedResources) || changedResources instanceof Set,
    "changed resources must be an array or Set",
  );
  const changed = new Set(changedResources);
  for (const id of changed)
    check(
      typeof id === "string" && index.model.resources.has(id),
      `unknown changed resource ${String(id)}`,
    );
  check(
    candidatePeriodNs === null ||
      (finite(candidatePeriodNs) &&
        candidatePeriodNs > 0 &&
        candidatePeriodNs <= Number.MAX_SAFE_INTEGER),
    "invalid candidate period",
  );
  const saved = census(index);
  const targets = saved.rows
    .map((row) => target(row, changed))
    .sort(
      (a, b) =>
        (b.delayNs ?? -1) - (a.delayNs ?? -1) ||
        lexical(a.pinName, b.pinName) ||
        lexical(a.role, b.role),
    );
  const all = group(targets, candidatePeriodNs);
  return {
    kind: "recorded_target_period_sensitivity",
    scope: "complete_recorded_mapped_registered_targets",
    changedResources: [...changed].sort(lexical),
    candidatePeriodNs,
    globalClockForecastNs: null,
    coverage: {
      ...all.counts,
      recordedWrites: index.writes.size,
      writesWithoutCones: saved.writesWithoutCones,
      writeBitOccurrences: { ...saved.bits },
      targetsWithoutResource: targets.filter((row) => !row.resources.length)
        .length,
      ambiguousResourceTargets: targets.filter(
        (row) => row.ambiguousResourceAssociation,
      ).length,
    },
    largestKnownRecordedTarget: all.largestKnown,
    groups: {
      targeted: group(
        targets.filter((row) => row.targeted),
        candidatePeriodNs,
      ),
      notTargeted: group(
        targets.filter((row) => !row.targeted),
        candidatePeriodNs,
      ),
    },
    targets,
    cut: cutSummary(cut, targets),
    exclusions: [
      "unrecorded_or_unmapped_native_endpoints",
      "clock_to_q_setup_skew_constraints_and_exceptions",
      "new_register_and_changed_placement_routing_cost",
      "coupled_output_alignment_and_functional_retiming_legality",
      "actor_reissue_interval_and_step_latency",
      "runtime_sensitization",
    ],
  };
}
