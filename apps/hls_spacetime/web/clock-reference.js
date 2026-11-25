/** Global routed STA supplies a setup-period estimate, independently of displayed
 * actors, sinks or SDF cones. This module neither predicts a changed layout nor
 * qualifies a live clock. Evidence identities are trusted inventories, not signatures. */
import { nativePaths } from "./native-paths.js";
import { recordingBuildKeys } from "./recording-build.js";

// Native reports round displayed slack to picoseconds. Half a display unit may
// separate a retained higher-precision value from that report's rounded summary.
const SLACK_TOLERANCE_NS = 0.0005 + 1e-12;
const DIGEST = /^[0-9a-f]{64}$/;

function check(condition, reason) {
  if (!condition) throw Error(`Clock reference: ${reason}`);
}
function text(value) {
  return typeof value === "string" && value.length > 0;
}
function positive(value) {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}
function cycle(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
function report(value, label) {
  check(
    value && text(value.file) && DIGEST.test(value.sha256),
    `invalid ${label} report identity`,
  );
  return Object.freeze({ file: value.file, sha256: value.sha256 });
}
function sameSlack(left, right) {
  return Math.abs(left - right) <= SLACK_TOLERANCE_NS;
}
function timingFrame(periodNs, originCycle) {
  check(positive(periodNs), "period must be finite and positive");
  check(cycle(originCycle), "origin must be an exact nonnegative cycle");
}

/** Validate an optional global single-clock setup reference against this exact
 * execution build, routed checkpoint, clock and device. Supplied malformed or
 * foreign evidence rejects; absent evidence returns null. Limiting pin names do
 * not establish geometry. Optional nativePathId links must resolve to matching
 * retained native timing evidence. Target minus WNS is an estimate, not a full
 * timing-closure or minimum-safe-period claim. Returned evidence is immutable. */
export function validateClockReference(model) {
  const value = model.document.clockReference;
  if (value === undefined || value === null) return null;
  check(
    value && !Array.isArray(value) && typeof value === "object",
    "invalid metadata",
  );
  check(value.schema === 1, "unsupported schema");
  const keys = recordingBuildKeys(
    value.build,
    model.bundle.build,
    model.catalogue?.build,
  );
  check(
    model.catalogue &&
      DIGEST.test(value.checkpoint) &&
      value.checkpoint === model.catalogue.checkpoint &&
      keys.every(
        (key) =>
          text(value.build?.[key]) &&
          value.build[key] === model.bundle.build?.[key] &&
          value.build[key] === model.catalogue.build?.[key],
      ),
    "build/checkpoint mismatch",
  );
  check(
    value.clock === model.bundle.capture.clock &&
      text(value.clock) &&
      value.device === model.bundle.capture.device &&
      text(value.device),
    "clock/device mismatch",
  );
  check(
    value.stage === "routed" && value.scope === "global_single_clock_setup",
    "unsupported global STA scope",
  );
  check(
    positive(value.targetPeriodNs) && Number.isFinite(value.setupWnsNs),
    "invalid target/WNS",
  );
  const setupPeriodNs = value.targetPeriodNs - value.setupWnsNs;
  check(
    positive(setupPeriodNs),
    "target minus WNS must be finite and positive",
  );
  const summary = report(value.summary, "summary");
  check(
    Array.isArray(value.limitingPaths) &&
      value.limitingPaths.length > 0 &&
      value.limitingPaths.length <= 100,
    "missing or excessive limiting paths",
  );
  const native = value.limitingPaths.some(
    (path) => path?.nativePathId !== undefined,
  )
    ? new Map(nativePaths(model).map((path) => [path.id, path]))
    : null;
  const ids = new Set();
  const limitingPaths = value.limitingPaths.map((path) => {
    check(
      path &&
        text(path.id) &&
        !ids.has(path.id) &&
        text(path.source) &&
        text(path.endpoint) &&
        Number.isFinite(path.slackNs),
      "invalid or duplicate limiting path",
    );
    ids.add(path.id);
    check(
      path.slackNs >= value.setupWnsNs - SLACK_TOLERANCE_NS,
      "limiting path contradicts global WNS",
    );
    const evidence = report(path.report, "limiting path");
    if (path.nativePathId !== undefined) {
      const retained = native.get(path.nativePathId);
      check(
        text(path.nativePathId) &&
          retained &&
          retained.source === path.source &&
          retained.endpoint === path.endpoint &&
          sameSlack(retained.slackNs, path.slackNs) &&
          evidence.sha256 === model.document.nativePaths.report_sha256,
        "native limiting path mismatch",
      );
    }
    return Object.freeze({
      id: path.id,
      source: path.source,
      endpoint: path.endpoint,
      slackNs: path.slackNs,
      report: evidence,
      ...(path.nativePathId === undefined
        ? {}
        : { nativePathId: path.nativePathId }),
    });
  });
  check(
    limitingPaths.some((path) => sameSlack(path.slackNs, value.setupWnsNs)),
    "no limiting path matches global WNS",
  );
  return Object.freeze({
    schema: 1,
    build: Object.freeze(
      Object.fromEntries(keys.map((key) => [key, value.build[key]])),
    ),
    checkpoint: value.checkpoint,
    clock: value.clock,
    device: value.device,
    stage: value.stage,
    scope: value.scope,
    targetPeriodNs: value.targetPeriodNs,
    setupWnsNs: value.setupWnsNs,
    setupPeriodNs,
    summary,
    limitingPaths: Object.freeze(limitingPaths),
  });
}

/** Select an explicit time reference. Auto uses only the validated global STA
 * estimate; target uses its original constraint; manual is a user assumption.
 * Missing STA returns an unavailable selection, never an SDF or implicit fallback.
 * This helper consumes validateClockReference's normalized result or null. */
export function selectClockPeriod(
  reference,
  { mode = "auto", manualPeriodNs } = {},
) {
  check(
    ["auto", "target", "manual"].includes(mode),
    "unknown period selection",
  );
  if (mode === "manual") {
    check(
      positive(manualPeriodNs),
      "manual period must be finite and positive",
    );
    return Object.freeze({
      status: "available",
      mode,
      periodNs: manualPeriodNs,
      source: "manual_assumption",
      label: "Manual period assumption",
      provenance: null,
    });
  }
  if (!reference)
    return Object.freeze({
      status: "unavailable",
      mode,
      periodNs: null,
      source: "missing_global_sta",
      label: "Global STA reference unavailable",
      provenance: null,
    });
  const periodNs =
    mode === "auto" ? reference.setupPeriodNs : reference.targetPeriodNs;
  check(positive(periodNs), "invalid normalized clock reference");
  return Object.freeze({
    status: "available",
    mode,
    periodNs,
    source:
      mode === "auto" ? "global_sta_target_minus_wns" : "original_sta_target",
    label:
      mode === "auto"
        ? "Global STA setup-period estimate"
        : "Original STA target",
    provenance: reference,
  });
}

/** Convert a sampled clock plus its within-clock arrival to nanoseconds relative
 * to an explicit stable origin. Negative times before the origin are allowed;
 * unknown/outside-scope arrivals remain null. No path cost is added to this time. */
export function absoluteTimeNs(
  cycleIndex,
  arrivalNs,
  { periodNs, originCycle = 0 },
) {
  timingFrame(periodNs, originCycle);
  check(cycle(cycleIndex), "clock must be an exact nonnegative cycle");
  if (arrivalNs === null || arrivalNs === "not_applicable") return null;
  check(
    Number.isFinite(arrivalNs) && arrivalNs >= 0,
    "invalid within-clock arrival",
  );
  const elapsed = (cycleIndex - originCycle) * periodNs + arrivalNs;
  check(Number.isFinite(elapsed), "elapsed time exceeds finite range");
  return elapsed;
}

/** Map existing fractional clock coordinates onto a common nanosecond axis.
 * Callers use the same unitsPerNs and originNs across variants and select each
 * variant's matching recorded originCycle. Window size never recenters the view.
 * Arrival C+a/period consequently has height ((C-origin)*period+a-originNs)*scale. */
export function timePoint(
  point,
  coordinate,
  { periodNs, originCycle = 0, unitsPerNs, originNs = 0 },
) {
  timingFrame(periodNs, originCycle);
  check(
    Number.isFinite(coordinate) &&
      coordinate >= 0 &&
      coordinate <= Number.MAX_SAFE_INTEGER,
    "invalid fractional clock coordinate",
  );
  check(
    point && Number.isFinite(point.x) && Number.isFinite(point.y),
    "invalid spatial point",
  );
  check(
    positive(unitsPerNs) && Number.isFinite(originNs),
    "invalid common time scale",
  );
  const height =
    ((coordinate - originCycle) * periodNs - originNs) * unitsPerNs;
  check(Number.isFinite(height), "time height exceeds finite range");
  return [point.x, point.y, height];
}

/** Evaluate an explicit recorded interval under the selected global period or
 * assumption. This is clock-count scaling, not a new control replay, observed
 * wall-clock duration or a sum of clock duration and static path costs. */
export function stepElapsed(startCycle, endCycle, selection) {
  check(
    cycle(startCycle) && cycle(endCycle) && endCycle >= startCycle,
    "invalid step interval",
  );
  check(
    selection &&
      ["available", "unavailable"].includes(selection.status) &&
      (selection.status === "available"
        ? positive(selection.periodNs)
        : selection.periodNs === null),
    "invalid period selection",
  );
  const elapsedCycles = endCycle - startCycle;
  const elapsedNs =
    selection.periodNs === null ? null : elapsedCycles * selection.periodNs;
  check(
    elapsedNs === null || Number.isFinite(elapsedNs),
    "step time exceeds finite range",
  );
  return Object.freeze({
    startCycle,
    endCycle,
    elapsedCycles,
    elapsedNs,
    periodNs: selection.periodNs,
    periodSource: selection.source,
    status: selection.status,
  });
}
