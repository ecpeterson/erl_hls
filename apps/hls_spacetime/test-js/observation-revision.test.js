import test from "node:test";
import assert from "node:assert/strict";
import {
  createObservationRevisionOrigin,
  validateObservationRevisionOrigin,
} from "../scripts/observation-revision.mjs";

const id = (digit) => digit.repeat(64);

/** A small producer receipt describes an unchanged capture and one new alias.
 * The fixture tests the format boundary, not the producer's recurrence proof. */
function fixture() {
  const build = {
      source: id("a"),
      rtl: id("b"),
      observation: id("c"),
      implementation: id("f"),
    },
    revised = { ...build, observation: id("d") };
  const capture = {
    complete: true,
    first_cycle: 0,
    end_cycle: 3,
    incarnations: [{ id: "i", first_cycle: 0, end_cycle: 3 }],
    observers: [
      { id: "dependencies", first_sequence: 0, next_sequence: 1, gaps: [] },
    ],
  };
  const base = {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      build,
      capture,
      resources: [{ id: "r", width: 1, ports: { w: "write" } }],
      events: [{ id: "event", observer: "dependencies", sequence: 0 }],
    },
    catalogue: { build, checkpoint: id("e") },
  };
  const bundle = { ...structuredClone(base.bundle), build: revised };
  const oldPlan = {
    schema: 1,
    inputs: {
      source_build: build.source,
      rtl: build.rtl,
      implementation: build.implementation,
    },
    registers: ["r"],
    dependencies: {
      nodes: {
        alias: {
          op: "state_read",
          width: 1,
          attrs: { state_element: "alias" },
        },
      },
      bindings: {
        original: {
          kind: "state",
          state_element: "original",
          signal: "signal",
          width: 1,
        },
      },
    },
  };
  const newPlan = structuredClone(oldPlan);
  newPlan.dependencies.bindings.alias = {
    kind: "state",
    state_element: "alias",
    signal: "signal",
    width: 1,
    equivalent_state: "original",
  };
  const review = {
    format: "spacetime-observation-reinterpretation-review",
    schema: 1,
    base_build: build,
    revised_build: revised,
    checkpoint_sha256: id("e"),
    base_projection_sha256: id("f"),
    original_trace_sha256: id("1"),
    extended_trace_sha256: id("1"),
    capture_bytes: 20,
    dependency_observer: "dependencies",
    original_plan_sha256: id("2"),
    revised_plan_sha256: id("3"),
    review_sha256: id("4"),
    comparison: {
      same_capture_bytes: true,
      source_rtl_unchanged: true,
      declarations_unchanged: true,
      old_dependency_bindings_retained: true,
      only_equivalent_state_bindings_added: true,
      added_bindings: 1,
      first_cycle: 0,
      end_cycle: 3,
      compared_cycles: 3,
    },
  };
  return { base, bundle, oldPlan, newPlan, review };
}
function create(input) {
  return createObservationRevisionOrigin(
    input.base,
    input.bundle,
    input.oldPlan,
    input.newPlan,
    input.review,
  );
}

test("same-capture interpretation revision preserves native provenance without inventing a simulator", () => {
  const input = fixture(),
    before = structuredClone(input),
    origin = create(input);
  assert.deepEqual(input, before);
  assert.deepEqual(origin.build, input.base.bundle.build);
  assert.deepEqual(origin.revised_build, input.bundle.build);
  assert.equal(origin.simulator_sha256, undefined);
  assert.equal(origin.original_trace_sha256, origin.extended_trace_sha256);
  validateObservationRevisionOrigin(
    origin,
    input.bundle.build,
    input.bundle.capture,
    input.base.catalogue.checkpoint,
  );
});

test("the plan review cannot admit changed declarations, programs, existing bindings or unqualified additions", () => {
  for (const change of [
    (i) => i.newPlan.registers.push("other"),
    (i) => (i.newPlan.new_declaration = true),
    (i) => (i.newPlan.dependencies.nodes.alias.width = 2),
    (i) => (i.newPlan.dependencies.new_table = {}),
    (i) => delete i.newPlan.dependencies.bindings.original,
    (i) => (i.newPlan.dependencies.bindings.original.signal = "other"),
    (i) => delete i.newPlan.dependencies.bindings.alias.equivalent_state,
    (i) => (i.newPlan.dependencies.bindings.alias.equivalent_state = "missing"),
    (i) => (i.newPlan.dependencies.bindings.alias.width = 2),
    (i) => (i.newPlan.dependencies.bindings.alias.signal = "other"),
    (i) => (i.newPlan.dependencies.bindings.alias.state_element = "other"),
    (i) => {
      i.oldPlan.dependencies.nodes.alias.op = "add";
      i.newPlan.dependencies.nodes.alias.op = "add";
    },
    (i) => delete i.newPlan.dependencies.bindings.alias,
    (i) => (i.review.comparison.added_bindings = 2),
  ]) {
    const input = fixture();
    change(input);
    assert.throws(() => create(input), /declaration|program|binding/);
  }
});

test("exact trace identity and finite capture, resource and build receipts remain mandatory", () => {
  for (const change of [
    (i) => (i.review.extended_trace_sha256 = id("9")),
    (i) => (i.review.capture_bytes = 0),
    (i) => delete i.review.review_sha256,
    (i) => delete i.review.original_plan_sha256,
    (i) => (i.review.comparison.same_capture_bytes = false),
    (i) => (i.review.comparison.old_dependency_bindings_retained = false),
    (i) => (i.review.comparison.compared_cycles = 2),
    (i) =>
      (i.review.revised_build = { ...i.review.revised_build, rtl: id("9") }),
    (i) =>
      (i.review.revised_build = {
        ...i.review.revised_build,
        implementation: id("9"),
      }),
    (i) => (i.bundle.capture.incarnations[0].id = "other"),
    (i) => i.bundle.capture.observers.push({ id: "new", gaps: [] }),
    (i) => (i.bundle.resources[0].width = 2),
    (i) => (i.bundle.physical = {}),
    (i) => (i.base.catalogue.checkpoint = id("9")),
    (i) =>
      (i.base.catalogue.correspondence_origin = {
        extended_trace_sha256: id("9"),
      }),
  ]) {
    const input = fixture();
    change(input);
    assert.throws(
      () => create(input),
      /identity|comparison|capture|resource|physical/,
    );
  }
});

test("the serialized origin must connect to exactly its newer build", () => {
  const input = fixture(),
    origin = create(input);
  assert.throws(
    () =>
      validateObservationRevisionOrigin(
        origin,
        { ...input.bundle.build, observation: id("9") },
        input.bundle.capture,
        input.base.catalogue.checkpoint,
      ),
    /identity/,
  );
  assert.throws(
    () =>
      validateObservationRevisionOrigin(
        origin,
        { ...input.bundle.build, implementation: id("9") },
        input.bundle.capture,
        input.base.catalogue.checkpoint,
      ),
    /identity/,
  );
  assert.throws(
    () =>
      validateObservationRevisionOrigin(
        { ...origin, kind: "capture-extension" },
        input.bundle.build,
        input.bundle.capture,
        input.base.catalogue.checkpoint,
      ),
    /kind/,
  );
});

test("added interpretation events and logical read lanes preserve all physical and sampled declarations", () => {
  const input = fixture();
  input.bundle.events.push({
    id: "new",
    observer: "dependencies",
    sequence: 1,
  });
  input.bundle.capture.observers[0].next_sequence = 2;
  input.bundle.resources[0].ports["read/new-operand"] = "read";
  assert.equal(create(input).comparison.added_bindings, 1);
  for (const mutate of [
    (i) => (i.bundle.capture.observers[0].next_sequence = 3),
    (i) => (i.bundle.events[1].sequence = 0),
    (i) => i.bundle.capture.observers[0].gaps.push([0, 1]),
    (i) => (i.bundle.resources[0].ports.w = "read"),
    (i) => (i.bundle.resources[0].ports.extra = "write"),
  ]) {
    const changed = structuredClone(input);
    mutate(changed);
    assert.throws(() => create(changed), /observer|port/);
  }
});

test("plan comparison requires lossless wide integers, including nested tuple and array values", () => {
  const input = fixture();
  const original = { $erlang_tuple: [{ $erlang_integer: "9007199254740992" }] };
  input.oldPlan.wide = structuredClone(original);
  input.newPlan.wide = structuredClone(original);
  assert.equal(create(input).comparison.added_bindings, 1);
  input.newPlan.wide.$erlang_tuple[0].$erlang_integer = "9007199254740993";
  assert.throws(() => create(input), /changed declarations/);
  for (const side of ["oldPlan", "newPlan"]) {
    const unsafe = fixture();
    unsafe[side].dependencies.nodes.alias.attrs.literal = [
      { nested: JSON.parse("9007199254740993") },
    ];
    assert.throws(() => create(unsafe), /unsafe integer/);
  }
  const roundedEqual = fixture();
  roundedEqual.oldPlan.wide = JSON.parse("9007199254740992");
  roundedEqual.newPlan.wide = JSON.parse("9007199254740993");
  assert.equal(roundedEqual.oldPlan.wide, roundedEqual.newPlan.wide);
  assert.throws(() => create(roundedEqual), /unsafe integer/);
  const malformed = fixture();
  malformed.oldPlan.wide = { $erlang_integer: "09007199254740992" };
  malformed.newPlan.wide = structuredClone(malformed.oldPlan.wide);
  assert.throws(() => create(malformed), /invalid tagged integer/);
});

test("read-node names are distinct from state identity and repeated representative reads are deduplicated", () => {
  const input = fixture();
  for (const plan of [input.oldPlan, input.newPlan]) {
    plan.dependencies.nodes["renamed-read"] = plan.dependencies.nodes.alias;
    delete plan.dependencies.nodes.alias;
    plan.dependencies.bindings["second-read-of-original"] = structuredClone(
      plan.dependencies.bindings.original,
    );
  }
  input.newPlan.dependencies.bindings["renamed-read"] =
    input.newPlan.dependencies.bindings.alias;
  delete input.newPlan.dependencies.bindings.alias;
  assert.equal(create(input).comparison.added_bindings, 1);
  const mismatch = structuredClone(input);
  mismatch.newPlan.dependencies.bindings["renamed-read"].state_element =
    "different-state";
  assert.throws(() => create(mismatch), /unqualified added/);
  const missing = structuredClone(input);
  missing.newPlan.dependencies.bindings["renamed-read"].equivalent_state =
    "different-representative";
  assert.throws(() => create(missing), /unqualified added/);
});
