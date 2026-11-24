/** Retained native correspondence may be reused after a checked interpretation
 * revision of the exact same recording. These local receipts are evidence
 * inventories, not signatures or native equivalence proofs. */
import { isDeepStrictEqual } from "node:util";

const BUILD_KEYS = ["source", "rtl", "observation", "implementation"];

/** Missing identities and undeclared changes stop publication. */
function check(condition, reason) {
  if (!condition) throw Error(`Observation reinterpretation: ${reason}`);
}

/** Identities are exact saved digests, never inferred from names or values. */
function digest(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

/** Compare all producer build identities. */
function sameBuild(a, b) {
  return BUILD_KEYS.every((key) => digest(a?.[key]) && a[key] === b?.[key]);
}

/** Only the named observation-binding table may change. */
function planObject(object) {
  check(
    object && typeof object === "object" && !Array.isArray(object),
    "missing plan object",
  );
  return object;
}

/** JSON numeric tokens above the safe integer range may already be rounded.
 * Require a producer's lossless tagged decimal encoding for those plan values;
 * plain-object comparison must not silently declare different integers equal. */
function checkLosslessPlan(value) {
  if (typeof value === "number") {
    check(
      Number.isFinite(value) &&
        (!Number.isInteger(value) || Number.isSafeInteger(value)),
      "unsafe integer plan value; use a lossless tagged decimal representation",
    );
  } else if (Array.isArray(value)) {
    for (const item of value) checkLosslessPlan(item);
  } else if (value && typeof value === "object") {
    if (Object.hasOwn(value, "$erlang_integer")) {
      check(
        Object.keys(value).length === 1 &&
          typeof value.$erlang_integer === "string" &&
          /^(?:0|-?[1-9][0-9]*)$/.test(value.$erlang_integer),
        "invalid tagged integer plan value",
      );
    }
    for (const item of Object.values(value)) checkLosslessPlan(item);
  }
}

/** Preserve every unnamed plan field, including future producer additions. */
function without(object, key) {
  planObject(object);
  return Object.fromEntries(
    Object.entries(object).filter(([name]) => name !== key),
  );
}

/** The dependency observer can gain events after interpretation improves. Its
 * declared finite sequence must still exactly cover its actual event population. */
function checkObserverSequence(bundle, observer) {
  const sequences = bundle.events
    .filter((event) => event.observer === observer.id)
    .map((event) => event.sequence);
  check(
    Number.isSafeInteger(observer.first_sequence) &&
      observer.first_sequence >= 0 &&
      Number.isSafeInteger(observer.next_sequence) &&
      observer.next_sequence >= observer.first_sequence &&
      observer.gaps?.length === 0 &&
      sequences.length === observer.next_sequence - observer.first_sequence &&
      new Set(sequences).size === sequences.length &&
      sequences.every(
        (sequence) =>
          Number.isSafeInteger(sequence) &&
          sequence >= observer.first_sequence &&
          sequence < observer.next_sequence,
      ),
    "dependency observer sequence does not match recorded events",
  );
}

/** Capture time, reset and sampled observers stay fixed. Only the declared
 * interpretation observer's event-count bound may grow or shrink. */
function checkCaptureRevision(base, bundle, observerId) {
  check(
    typeof observerId === "string" && observerId.length > 0,
    "missing dependency observer identity",
  );
  check(
    isDeepStrictEqual(
      without(base.capture, "observers"),
      without(bundle.capture, "observers"),
    ),
    "changed capture bounds or reset incarnations",
  );
  const oldObservers = base.capture.observers,
    newObservers = bundle.capture.observers;
  check(
    Array.isArray(oldObservers) &&
      Array.isArray(newObservers) &&
      oldObservers.length === newObservers.length &&
      oldObservers.filter((observer) => observer.id === observerId).length ===
        1 &&
      newObservers.filter((observer) => observer.id === observerId).length ===
        1,
    "changed capture observers",
  );
  for (let i = 0; i < oldObservers.length; i++) {
    const before = oldObservers[i],
      after = newObservers[i];
    if (before.id !== observerId)
      check(isDeepStrictEqual(before, after), "changed sampled observer");
    else {
      check(
        isDeepStrictEqual(
          without(before, "next_sequence"),
          without(after, "next_sequence"),
        ),
        "changed dependency observer scope",
      );
      checkObserverSequence(base, before);
      checkObserverSequence(bundle, after);
    }
  }
}

/** Added logical read lanes name newly resolved operands, not hardware ports.
 * Every physical resource property and existing port remains unchanged. */
function checkResources(before, after) {
  check(
    Array.isArray(before) &&
      Array.isArray(after) &&
      before.length === after.length,
    "changed resource declarations",
  );
  const rows = new Map(after.map((row) => [row.id, row]));
  check(rows.size === after.length, "duplicate resource declarations");
  for (const original of before) {
    const revised = rows.get(original.id);
    check(
      revised &&
        isDeepStrictEqual(
          without(original, "ports"),
          without(revised, "ports"),
        ),
      "changed resource declarations",
    );
    if (isDeepStrictEqual(original.ports, revised.ports)) continue;
    const oldPorts = planObject(original.ports),
      newPorts = planObject(revised.ports);
    check(
      Object.entries(oldPorts).every(
        ([port, kind]) =>
          Object.hasOwn(newPorts, port) && newPorts[port] === kind,
      ) &&
        Object.entries(newPorts).every(
          ([port, kind]) =>
            Object.hasOwn(oldPorts, port) ||
            (port.length > 0 && kind === "read"),
        ),
      "changed existing resource port or added nonread port",
    );
  }
}

/** Check the serialized origin wherever a saved native attachment is consumed.
 * The caller supplies the newer build and exact finite capture bounds. */
export function validateObservationRevisionOrigin(
  origin,
  current,
  capture,
  checkpoint,
) {
  const comparison = origin?.comparison;
  check(
    origin?.kind === "observation-reinterpretation" && origin.schema === 1,
    "unsupported origin kind",
  );
  check(
    sameBuild(origin.revised_build, current) &&
      BUILD_KEYS.every((key) => digest(origin.build?.[key])) &&
      origin.build.source === current.source &&
      origin.build.rtl === current.rtl &&
      origin.build.implementation === current.implementation &&
      origin.build.observation !== current.observation &&
      digest(checkpoint) &&
      origin.checkpoint === checkpoint &&
      [
        "base_projection_sha256",
        "original_trace_sha256",
        "extended_trace_sha256",
        "original_plan_sha256",
        "revised_plan_sha256",
        "review_sha256",
      ].every((key) => digest(origin[key])),
    "build/checkpoint/review identity mismatch",
  );
  check(
    origin.original_trace_sha256 === origin.extended_trace_sha256 &&
      Number.isSafeInteger(origin.capture_bytes) &&
      origin.capture_bytes > 0 &&
      capture?.complete === true &&
      Number.isSafeInteger(capture.first_cycle) &&
      capture.first_cycle >= 0 &&
      Number.isSafeInteger(capture.end_cycle) &&
      capture.end_cycle > capture.first_cycle &&
      typeof origin.dependency_observer === "string" &&
      origin.dependency_observer.length > 0 &&
      comparison?.same_capture_bytes === true &&
      comparison.source_rtl_unchanged === true &&
      comparison.declarations_unchanged === true &&
      comparison.old_dependency_bindings_retained === true &&
      comparison.only_equivalent_state_bindings_added === true &&
      Number.isSafeInteger(comparison.added_bindings) &&
      comparison.added_bindings > 0 &&
      comparison.first_cycle === capture.first_cycle &&
      comparison.end_cycle === capture.end_cycle &&
      comparison.compared_cycles === capture.end_cycle - capture.first_cycle,
    "unqualified same-capture plan comparison",
  );
}

/** Construct one provenance link from an explicitly reviewed producer-plan
 * revision. All declarations and dependency-program fields stay byte-value
 * identical after JSON decoding; only absent equivalent-state bindings may be
 * added. Their recurrence justification belongs to the producer's hash-bound
 * review, not this format checker. The caller verifies the exact bytes named
 * by the review and separately checks new graph storage chronology. */
export function createObservationRevisionOrigin(
  base,
  bundle,
  oldPlan,
  newPlan,
  review,
) {
  check(
    review?.format === "spacetime-observation-reinterpretation-review" &&
      review.schema === 1,
    "unsupported review",
  );
  check(
    base?.format === "spacetime-view" &&
      base.schema === 1 &&
      sameBuild(base.bundle?.build, base.catalogue?.build) &&
      sameBuild(base.bundle.build, review.base_build) &&
      sameBuild(bundle?.build, review.revised_build) &&
      base.catalogue.checkpoint === review.checkpoint_sha256,
    "base/bundle/review identity mismatch",
  );
  checkLosslessPlan(oldPlan);
  checkLosslessPlan(newPlan);
  check(
    isDeepStrictEqual(
      without(oldPlan, "dependencies"),
      without(newPlan, "dependencies"),
    ) &&
      isDeepStrictEqual(
        without(oldPlan.dependencies, "bindings"),
        without(newPlan.dependencies, "bindings"),
      ),
    "changed declarations or dependency program",
  );
  const oldBindings = oldPlan.dependencies.bindings,
    newBindings = newPlan.dependencies.bindings;
  planObject(oldBindings);
  planObject(newBindings);
  check(
    Object.entries(oldBindings).every(([name, binding]) =>
      isDeepStrictEqual(binding, newBindings[name]),
    ),
    "changed or removed original dependency binding",
  );
  const added = Object.entries(newBindings).filter(
    ([name]) => !Object.hasOwn(oldBindings, name),
  );
  check(
    added.length > 0 &&
      added.every(([name, binding]) => {
        const representatives = new Map(
          Object.values(oldBindings)
            .filter(
              (row) =>
                row.state_element === binding?.equivalent_state &&
                row.signal === binding?.signal &&
                row.width === binding?.width &&
                row.kind === "state",
            )
            .map((row) => [
              JSON.stringify([row.signal, row.state_element, row.width]),
              row,
            ]),
        );
        const representative = representatives.values().next().value,
          node = oldPlan.dependencies.nodes?.[name];
        return (
          binding?.kind === "state" &&
          typeof binding.equivalent_state === "string" &&
          binding.equivalent_state.length > 0 &&
          typeof binding.signal === "string" &&
          binding.signal.length > 0 &&
          Number.isSafeInteger(binding.width) &&
          binding.width > 0 &&
          typeof binding.state_element === "string" &&
          binding.state_element.length > 0 &&
          node?.op === "state_read" &&
          node.width === binding.width &&
          node.attrs?.state_element === binding.state_element &&
          representatives.size === 1 &&
          representative?.kind === "state" &&
          representative.state_element === binding.equivalent_state &&
          representative.signal === binding.signal &&
          representative.width === binding.width
        );
      }),
    "unqualified added dependency binding",
  );
  checkCaptureRevision(base.bundle, bundle, review.dependency_observer);
  checkResources(base.bundle.resources, bundle.resources);
  check(!bundle.physical, "replacement physical evidence forbidden");
  check(
    oldPlan.inputs?.source_build === review.base_build.source &&
      oldPlan.inputs.rtl === review.base_build.rtl &&
      oldPlan.inputs.implementation === review.base_build.implementation &&
      review.comparison?.added_bindings === added.length,
    "plan input or binding-count mismatch",
  );
  const preceding = base.catalogue.correspondence_origin;
  check(
    !preceding ||
      preceding.extended_trace_sha256 === review.original_trace_sha256,
    "preceding recording identity mismatch",
  );
  const origin = {
    kind: "observation-reinterpretation",
    schema: 1,
    build: base.bundle.build,
    revised_build: bundle.build,
    previous_correspondence: preceding ?? null,
    checkpoint: base.catalogue.checkpoint,
    base_projection_sha256: review.base_projection_sha256,
    original_trace_sha256: review.original_trace_sha256,
    extended_trace_sha256: review.extended_trace_sha256,
    capture_bytes: review.capture_bytes,
    dependency_observer: review.dependency_observer,
    original_plan_sha256: review.original_plan_sha256,
    revised_plan_sha256: review.revised_plan_sha256,
    review_sha256: review.review_sha256,
    comparison: review.comparison,
    scope:
      "The exact same capture is reinterpreted after checked additions to dependency bindings. Original native correspondence/static timing is retained; no new simulator/native run, gate-activity attribution or native equivalence claim.",
  };
  validateObservationRevisionOrigin(
    origin,
    bundle.build,
    bundle.capture,
    base.catalogue.checkpoint,
  );
  return origin;
}
