/** Join a recorded completion interval and reviewed control explanation to global
 * STA. Chronology alone creates no dependency; supplied explanation rows retain
 * their evidence class and unknowns. This module runs no new scheduling model. */
import {
  validateClockReference,
  selectClockPeriod,
  stepElapsed,
} from "./clock-reference.js";
const digest = /^[0-9a-f]{64}$/;
const cycle = (n) => Number.isSafeInteger(n) && n >= 0;
const text = (s) => typeof s === "string" && s.trim().length > 0;
const sameBuild = (a, b) =>
  ["source", "rtl", "observation"].every((k) => a?.[k] === b?.[k]);
function check(ok, message) {
  if (!ok) throw Error(`Step comparison: ${message}`);
}
function evidence(rows) {
  check(
    Array.isArray(rows) &&
      rows.length > 0 &&
      rows.every(
        (r) => r && text(r.file) && digest.test(r.sha256) && text(r.scope),
      ),
    "missing evidence identity/scope",
  );
}
/** A boundary may be an externally witnessed frame without graph taps. Never
 * synthesize a graph anchor for it; any supplied anchors must match this cycle. */
function boundary(model, row, epoch) {
  check(
    row &&
      text(row.id) &&
      text(row.label) &&
      cycle(row.cycle) &&
      row.cycle >= epoch.first_cycle &&
      row.cycle < epoch.end_cycle,
    "invalid boundary",
  );
  check(
    Array.isArray(row.eventIds) &&
      new Set(row.eventIds).size === row.eventIds.length,
    "invalid boundary anchors",
  );
  for (const id of row.eventIds) {
    const event = model.events.get(id);
    check(
      event && event.cycle === row.cycle && event.incarnation === epoch.id,
      "foreign or stale boundary anchor",
    );
  }
  evidence(row.evidence);
}
/** Peer records supply their own reviewed STA and cycle evidence. Validate each
 * independently; native geometry is not loaded for a peer. It cannot borrow this
 * capture's period, checkpoint, or endpoints merely because labels match. */
function peerReference(peer) {
  const ref = peer.clockReference;
  check(
    ref &&
      Array.isArray(ref.limitingPaths) &&
      !ref.limitingPaths.some((p) => p?.nativePathId !== undefined),
    "peer requires self-contained STA identity",
  );
  return validateClockReference({
    document: { clockReference: ref },
    bundle: {
      build: ref.build,
      capture: { clock: ref.clock, device: ref.device },
    },
    catalogue: { build: ref.build, checkpoint: ref.checkpoint },
  });
}
/** Validate an explicitly ordered before/after pair, real capture boundaries and
 * reviewed model milestones. The shared comparisonKey declares producer-reviewed
 * correspondence; labels or cycle numbers alone cannot establish matched work.
 * Counts derive from endpoints. Ordered milestones explain the retained tail;
 * they do not claim to exhaust a unique critical path through the whole step. */
export function validateStepComparison(model) {
  const value = model.document.stepComparison;
  if (value === undefined || value === null) return null;
  check(
    value.schema === 1 &&
      text(value.id) &&
      text(value.label) &&
      text(value.current) &&
      text(value.comparisonKey),
    "invalid descriptor or comparison key",
  );
  check(sameBuild(value.build, model.bundle.build), "build mismatch");
  const epoch = model.epochs.get(value.incarnation);
  check(epoch, "missing incarnation");
  boundary(model, value.start, epoch);
  boundary(model, value.end, epoch);
  check(
    value.start.cycle < value.end.cycle,
    "empty or backward completion interval",
  );
  check(
    Array.isArray(value.variants) && value.variants.length === 2,
    "comparison requires exactly two ordered variants",
  );
  const ids = new Set();
  const variants = value.variants.map((peer) => {
    check(
      peer &&
        text(peer.id) &&
        text(peer.label) &&
        !ids.has(peer.id) &&
        cycle(peer.startCycle) &&
        cycle(peer.endCycle) &&
        peer.startCycle < peer.endCycle,
      "invalid or duplicate variant",
    );
    ids.add(peer.id);
    evidence(peer.evidence);
    return { ...peer, reference: peerReference(peer) };
  });
  const current = variants.find((peer) => peer.id === value.current);
  const clock = model.clockReference ?? validateClockReference(model);
  check(
    current &&
      clock &&
      sameBuild(current.reference.build, model.bundle.build) &&
      sameBuild(current.reference.build, clock.build) &&
      current.reference.checkpoint === clock.checkpoint &&
      current.reference.clock === clock.clock &&
      current.reference.device === clock.device &&
      current.reference.targetPeriodNs === clock.targetPeriodNs &&
      current.reference.setupWnsNs === clock.setupWnsNs &&
      current.reference.summary.sha256 === clock.summary.sha256 &&
      current.reference.summary.file === clock.summary.file,
    "current variant STA mismatch",
  );
  check(
    current.startCycle === value.start.cycle &&
      current.endCycle === value.end.cycle,
    "current variant interval mismatch",
  );
  check(
    Array.isArray(value.milestones) && value.milestones.length <= 256,
    "invalid milestone list",
  );
  const nodes = new Map([
    [value.start.id, value.start],
    [value.end.id, value.end],
  ]);
  check(nodes.size === 2, "duplicate boundary identity");
  let previousCycle = value.start.cycle;
  for (const row of value.milestones) {
    boundary(model, row, epoch);
    check(
      !nodes.has(row.id) &&
        row.cycle >= previousCycle &&
        row.cycle <= value.end.cycle,
      "duplicate, unordered or outside milestone",
    );
    check(
      ["recorded", "validated_control_replay"].includes(row.basis),
      "unknown milestone basis",
    );
    previousCycle = row.cycle;
    nodes.set(row.id, row);
  }
  check(
    Array.isArray(value.links) && value.links.length <= 512,
    "invalid explanation links",
  );
  for (const link of value.links) {
    const from = nodes.get(link?.from),
      to = nodes.get(link?.to);
    check(
      from &&
        to &&
        from.id !== to.id &&
        from.cycle <= to.cycle &&
        text(link.label) &&
        [
          "model_dependency",
          "recorded_interval",
          "unresolved_interval",
        ].includes(link.basis),
      "invalid explanation link",
    );
    evidence(link.evidence);
  }
  check(
    Array.isArray(value.assumptions) &&
      value.assumptions.every(text) &&
      Array.isArray(value.unknowns) &&
      value.unknowns.every(text),
    "missing scope",
  );
  return { ...value, variants, nodes };
}
/** Apply an independently hash-checked companion to an ephemeral loaded model.
 * Validate a temporary view first so a bad sidecar leaves no partially installed
 * timing reference. Original recording bytes and prepared circuit hashes remain
 * untouched; embedded metadata is also accepted through normal model creation. */
export function installStepEvidence(model, payload) {
  if (!payload) return;
  check(
    !model.document.clockReference && !model.document.stepComparison,
    "companion would replace embedded evidence",
  );
  const candidate = {
    ...model,
    document: {
      ...model.document,
      clockReference: payload.clockReference,
      stepComparison: payload.stepComparison,
    },
  };
  candidate.clockReference = validateClockReference(candidate);
  candidate.stepComparison = validateStepComparison(candidate);
  model.document = candidate.document;
  model.clockReference = candidate.clockReference;
  model.stepComparison = candidate.stepComparison;
}
/** Compare a validated before/after pair under each variant's own global STA,
 * its original target, or one shared manual period. Physical delays are never
 * added again. The decomposition first changes cycles at the baseline period,
 * then changes period at the candidate cycle count. The two terms sum to the
 * total estimate change, up to floating-point rounding; neither assigns cause. */
export function stepComparisonMetrics(
  comparison,
  { mode = "auto", manualPeriodNs } = {},
) {
  const rows = comparison.variants.map((v) => ({
    id: v.id,
    label: v.label,
    current: v.id === comparison.current,
    ...stepElapsed(
      v.startCycle,
      v.endCycle,
      selectClockPeriod(v.reference, { mode, manualPeriodNs }),
    ),
  }));
  const [before, after] = rows;
  const cycleContributionNs =
    (after.elapsedCycles - before.elapsedCycles) * before.periodNs;
  const clockContributionNs =
    after.elapsedCycles * (after.periodNs - before.periodNs);
  const elapsedNs = after.elapsedNs - before.elapsedNs;
  const percentReduction = 100 * (1 - after.elapsedNs / before.elapsedNs);
  check(
    [
      cycleContributionNs,
      clockContributionNs,
      elapsedNs,
      percentReduction,
    ].every(Number.isFinite),
    "comparison arithmetic exceeds finite range",
  );
  return {
    rows,
    change: {
      before: before.id,
      after: after.id,
      elapsedNs,
      percentReduction,
      cycleContributionNs,
      clockContributionNs,
    },
    mode,
  };
}
