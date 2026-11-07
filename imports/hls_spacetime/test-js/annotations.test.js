import test from "node:test";
import assert from "node:assert/strict";
import {
  annotationEvents,
  createModel,
  traceDependencies,
} from "../web/model.js";

/** Two accepted words share one observed producer; an unrelated event and a
 * later reset make chronology and cross-incarnation guesses detectable. */
function fixture() {
  const event = (
    id,
    cycle,
    inputs = [],
    outputs = [],
    incarnation = "epoch0",
  ) => ({
    id,
    cycle,
    sequence: cycle,
    observer: "observer",
    incarnation,
    inputs,
    outputs,
    evidence: "synthetic fixture",
  });
  return {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      capture: {
        complete: true,
        first_cycle: 0,
        end_cycle: 12,
        observers: [{ id: "observer", gaps: [] }],
        incarnations: [
          { id: "epoch0", first_cycle: 0, end_cycle: 8 },
          { id: "epoch1", first_cycle: 8, end_cycle: 12 },
        ],
      },
      events: [
        event("producer", 1, ["initial"], ["value"]),
        event("unrelated", 2),
        event("first_word", 4, ["value"]),
        event("last_word", 5, ["value"]),
        event("after_reset", 8, [], [], "epoch1"),
      ],
      versions: [
        { id: "initial", producer: "root", incarnation: "epoch0" },
        { id: "value", producer: "producer", incarnation: "epoch0" },
      ],
      resources: [],
      relations: [
        { source: "unrelated", target: "first_word", kind: "resource_order" },
      ],
    },
    annotations: { public: [], boundaries: [] },
  };
}

function completion(overrides = {}) {
  return {
    id: "completion",
    cycle: 5,
    graph_events: ["first_word", "last_word"],
    graph_incarnation: "epoch0",
    dependency_endpoint: true,
    ...overrides,
  };
}

test("two-contributor completion selects existing events without inventing edges", () => {
  const document = fixture();
  const original = createModel(document);
  const annotation = completion();
  document.annotations.boundaries.push(annotation);
  document.annotations.public.push(completion({ id: "reply" }));
  const model = createModel(document);
  const contributors = annotationEvents(model, annotation);
  assert.deepEqual(
    contributors.map((event) => event.id),
    ["first_word", "last_word"],
  );
  assert.equal(contributors[0], model.events.get("first_word"));
  assert.deepEqual(model.edges, original.edges);
  assert.deepEqual([...model.events.keys()], [...original.events.keys()]);
  assert.equal(model.events.has(annotation.id), false);
});

test("multiple seeds visit shared ancestry and its root stop once", () => {
  const model = createModel(fixture());
  const trace = traceDependencies(model, [
    "first_word",
    "last_word",
    "first_word",
  ]);
  assert.deepEqual(
    trace.events.map((event) => event.id),
    ["first_word", "last_word", "producer"],
  );
  assert.equal(trace.edges.length, 2);
  assert.deepEqual(
    trace.roots.map(({ version, consumer }) => [version.id, consumer]),
    [["initial", "producer"]],
  );
  assert.equal(trace.truncated, false);
  assert.ok(!trace.events.some((event) => event.id === "unrelated"));
});

test("contextual annotations remain context with no graph contributor or edge", () => {
  const document = fixture();
  const original = createModel(document);
  const contextual = { id: "context", cycle: 5, dependency_endpoint: false };
  document.annotations.public.push(contextual);
  document.annotations.boundaries.push({ id: "old_boundary", cycle: 5 });
  const model = createModel(document);
  assert.deepEqual(annotationEvents(model, contextual), []);
  assert.deepEqual(
    annotationEvents(model, document.annotations.boundaries[0]),
    [],
  );
  assert.deepEqual(model.edges, original.edges);
  assert.throws(() => traceDependencies(model, contextual.id), /Unknown event/);
});

test("public and boundary anchors reject unknown, future and cross-reset contributors", () => {
  const invalid = [
    [completion({ graph_events: ["missing"] }), /Unknown annotation event/],
    [
      completion({ graph_events: ["producer", "last_word"], cycle: 4 }),
      /in the future/,
    ],
    [
      completion({ graph_events: ["first_word", "after_reset"], cycle: 8 }),
      /crosses reset/,
    ],
    [completion({ graph_incarnation: "epoch1" }), /crosses reset/],
    [completion({ cycle: 6 }), /not its final contributor/],
  ];
  for (const table of ["public", "boundaries"])
    for (const [annotation, reason] of invalid) {
      const document = fixture();
      document.annotations[table].push(annotation);
      assert.throws(() => createModel(document), reason);
    }
});

test("anchors reject partial metadata, duplicate IDs and empty contributor sets", () => {
  const invalid = [
    completion({ graph_events: [] }),
    completion({ graph_events: "last_word" }),
    completion({ graph_events: ["last_word", "last_word"] }),
    completion({ graph_events: undefined }),
    completion({ graph_incarnation: undefined }),
    completion({ graph_incarnation: "missing" }),
    completion({ dependency_endpoint: undefined }),
    completion({ dependency_endpoint: false }),
    completion({ dependency_endpoint: "true" }),
    completion({ cycle: 5.5 }),
    { id: "missing_anchors", cycle: 5, dependency_endpoint: true },
    { id: "orphan_incarnation", cycle: 5, graph_incarnation: "epoch0" },
  ];
  for (const annotation of invalid) {
    const document = fixture();
    document.annotations.public.push(annotation);
    assert.throws(() => createModel(document), /annotation/i);
  }
});

test("multi-seed traversal shares one bound and preserves root and order semantics", () => {
  const model = createModel(fixture());
  const seeds = ["first_word", "last_word"];
  assert.throws(
    () => traceDependencies(model, seeds, { maxEvents: 1 }),
    /seeds exceed/,
  );
  assert.throws(() => traceDependencies(model, []), /Empty traversal seeds/);
  assert.throws(
    () => traceDependencies(model, ["last_word", "missing"]),
    /Unknown event/,
  );
  const bounded = traceDependencies(model, seeds, { maxEvents: 2 });
  assert.deepEqual(
    bounded.events.map((event) => event.id),
    seeds,
  );
  assert.deepEqual(bounded.edges, []);
  assert.deepEqual(bounded.roots, []);
  assert.equal(bounded.truncated, true);
  const complete = traceDependencies(model, seeds, { maxEvents: 3 });
  assert.equal(complete.events.length, 3);
  assert.equal(complete.roots.length, 1);
  assert.equal(complete.truncated, false);
  const duplicate = traceDependencies(model, ["last_word", "last_word"], {
    maxEvents: 1,
  });
  assert.equal(duplicate.events.length, 1);
  assert.equal(duplicate.truncated, true);
  const ordered = traceDependencies(model, seeds, {
    includeOrder: true,
    maxEvents: 4,
  });
  assert.equal(ordered.events.length, 4);
  assert.equal(ordered.edges.length, 3);
  assert.equal(ordered.truncated, false);
  const forward = traceDependencies(model, ["producer", "first_word"], {
    direction: "forward",
    maxEvents: 3,
  });
  assert.deepEqual(
    forward.events.map((event) => event.id),
    ["producer", "first_word", "last_word"],
  );
  assert.equal(forward.edges.length, 2);
  assert.deepEqual(forward.roots, []);
  assert.equal(forward.truncated, false);
});
