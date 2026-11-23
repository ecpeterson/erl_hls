import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  attachComputations,
  parseArguments,
} from "../scripts/attach-computations.mjs";

/** Tiny complete native graph plus independent hash-bound source artifacts. */
async function fixture(t, mutate = () => {}) {
  const root = await mkdtemp(join(tmpdir(), "spacetime-computations-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const digest = (data) => createHash("sha256").update(data).digest("hex");
  const write = async (file, value) => {
    const data = Buffer.from(JSON.stringify(value));
    await writeFile(join(root, file), data);
    return {
      path: `/native/${file}`,
      bytes: data.length,
      sha256: digest(data),
    };
  };
  const build = {
    source: "a".repeat(64),
    rtl: "b".repeat(64),
    observation: "c".repeat(64),
  };
  const checkpoint = "d".repeat(64);
  const recording = {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      build: { ...build },
      capture: { complete: true, first_cycle: 0, end_cycle: 3 },
    },
    catalogue: { build: { ...build }, checkpoint },
  };
  const parts = [],
    totals = {};
  const rows = {
    cells: [],
    pins: [
      { id: "source/Q", cell: 0, net: 0, direction: "OUT" },
      { id: "sink/D", cell: 1, net: 0, direction: "IN" },
    ],
    nets: [{ id: "net" }],
    arcs: [],
    bindings: [],
    operations: [],
  };
  for (const [table, data] of Object.entries(rows)) {
    const descriptor = await write(`${table}.json`, data);
    parts.push({
      file: `${table}.json`,
      table,
      rows: data.length,
      bytes: descriptor.bytes,
      sha256: descriptor.sha256,
    });
    totals[table] = data.length;
  }
  const geometry = await write("geometry.json", {
    id: "net",
    status: "complete",
    route_status: "ROUTED",
    nodes: [],
    pips: [],
    issues: [],
    pin_attachments: [],
  });
  const attachments = [
    { pin: "source/Q", direction: "OUT", status: "unavailable" },
    { pin: "sink/D", direction: "IN", status: "unavailable" },
  ];
  const attachment = await write("attachments.json", {
    id: "net",
    pin_attachments: attachments,
  });
  const index = {
    id: "net",
    complete: true,
    type: "SIGNAL",
    route_status: "ROUTED",
    geometry,
    attachments: [
      { file: attachment, pins: attachments.map((pin) => pin.pin) },
    ],
    endpoints: attachments.map((pin) => ({
      pin: pin.pin,
      kind: "pin",
      direction: pin.direction,
    })),
  };
  const graph = {
    format: "spacetime-computations-manifest",
    schema: 1,
    build: { ...build },
    checkpoint,
    parts,
    totals,
    attachment: {
      schema: 1,
      scope: "structural_native_connectivity",
      build: { ...build },
      nativeBuild: { ...build },
      checkpoint,
    },
  };
  const native = {
    schema_version: 1,
    complete: true,
    scope: "static_route_graph",
    coordinate_unit: "tile_grid",
    build: { ...build },
    checkpoint_sha256: checkpoint,
    requested_nets: 1,
    requested_endpoints: 2,
  };
  mutate({ graph, index, rows, recording, native });
  const view = await write("view.json", recording);
  graph.view = { bytes: view.bytes, sha256: view.sha256 };
  const net = await write("net.json", index);
  native.nets = [{ id: "net", file: net }];
  await write("graph.json", graph);
  await write("routes.json", native);
  await write(
    "map.json",
    Object.fromEntries(
      ["geometry.json", "attachments.json", "net.json"].map((file) => [
        `/native/${file}`,
        join(root, file),
      ]),
    ),
  );
  return {
    root,
    options: {
      view: join(root, "view.json"),
      computations: join(root, "graph.json"),
      routes: join(root, "routes.json"),
      routeFiles: join(root, "map.json"),
      output: join(root, "published"),
    },
  };
}

/** A local review inventory binds one finite extension; it is not native evidence. */
function extend({ graph, recording }, observation = "e".repeat(64)) {
  const previous = recording.catalogue.correspondence_origin ?? null;
  const origin = {
    build: { ...recording.bundle.build },
    previous_correspondence: previous,
    checkpoint: graph.checkpoint,
    base_projection_sha256: "1".repeat(64),
    original_trace_sha256: previous?.extended_trace_sha256 ?? "2".repeat(64),
    extended_trace_sha256: observation,
    simulator_sha256: "3".repeat(64),
    comparison: {
      old_taps_equal: true,
      public_fields_equal: true,
      original_taps: 2,
      first_cycle: 0,
      end_cycle: 3,
      compared_cycles: 3,
    },
  };
  const build = { ...graph.build, observation };
  graph.build = { ...build };
  graph.attachment.build = { ...build };
  recording.bundle.build = { ...build };
  recording.catalogue.build = { ...build };
  recording.catalogue.correspondence_origin = origin;
}

test("complete publication preserves recording bytes and independently checked table hashes", async (t) => {
  const { root, options } = await fixture(t);
  const result = await attachComputations(options);
  assert.equal(result.nets, 1);
  assert.equal(result.endpoints, 2);
  assert.deepEqual(
    await readFile(join(options.output, "recording.json")),
    await readFile(options.view),
  );
  const index = JSON.parse(await readFile(join(options.output, "index.json")));
  const manifestBytes = await readFile(
    join(options.output, index.examples[0].computations.file),
  );
  assert.equal(
    createHash("sha256").update(manifestBytes).digest("hex"),
    index.examples[0].computations.sha256,
  );
  const manifest = JSON.parse(manifestBytes);
  assert.equal(manifest.attachment.routingComplete, true);
  assert.equal(manifest.totals.routeNets, 1);
  const part = manifest.parts.find((part) => part.table === "routeNets");
  const routes = JSON.parse(
    await readFile(join(options.output, "computations", part.file)),
  );
  assert.equal(routes[0].pin_attachments.length, 2);
  await assert.rejects(() => attachComputations(options), /EEXIST/);
});

test("missing or foreign native endpoints reject instead of publishing a subset", async (t) => {
  for (const mutate of [
    ({ index }) => {
      index.attachments[0].pins.pop();
    },
    ({ index }) => {
      index.endpoints[1].pin = "wrong/D";
    },
    ({ index }) => {
      index.attachments[0].pins.push("source/Q");
    },
  ]) {
    const { options } = await fixture(t, mutate);
    await assert.rejects(
      () => attachComputations(options),
      /endpoint|attachment/,
    );
    await assert.rejects(
      () => readFile(join(options.output, "computations", "manifest.json")),
      /ENOENT/,
    );
  }
});

test("stale bytes and escaping graph part paths reject at the saved-file boundary", async (t) => {
  const one = await fixture(t);
  await writeFile(join(one.root, "attachments.json"), "{}");
  await assert.rejects(
    () => attachComputations(one.options),
    /identity mismatch/,
  );
  const two = await fixture(t, ({ graph }) => {
    graph.parts[0].file = "../elsewhere.json";
  });
  await assert.rejects(() => attachComputations(two.options), /escapes/);
});

test("later scalar CLI arguments win", () => {
  assert.deepEqual(
    parseArguments(["--view", "old", "--view", "new", "--output", "out"]),
    { view: "new", output: "out" },
  );
  assert.throws(() => parseArguments(["--routes"]), /invalid option/);
});

test("finite observation extensions retain the original native identity and exact recording bytes", async (t) => {
  for (const count of [1, 2]) {
    const { options } = await fixture(t, (state) => {
      extend(state);
      if (count === 2) extend(state, "f".repeat(64));
    });
    await attachComputations(options);
    const manifest = JSON.parse(
      await readFile(join(options.output, "computations", "manifest.json")),
    );
    assert.equal(manifest.attachment.nativeBuild.observation, "c".repeat(64));
    assert.equal(
      manifest.build.observation,
      (count === 1 ? "e" : "f").repeat(64),
    );
    assert.deepEqual(
      await readFile(join(options.output, "recording.json")),
      await readFile(options.view),
    );
  }
});

test("observation skew requires exact identity, receipts, equality and finite horizon", async (t) => {
  for (const change of [
    ({ recording }) => {
      delete recording.catalogue.correspondence_origin;
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.comparison.old_taps_equal = false;
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.comparison.public_fields_equal = false;
    },
    ({ recording }) => {
      delete recording.catalogue.correspondence_origin.base_projection_sha256;
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.comparison.compared_cycles = 2;
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.comparison.end_cycle = 4;
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.comparison.original_taps = 0;
    },
    ({ recording }) => {
      recording.bundle.capture.complete = false;
    },
    ({ graph, native }) => {
      graph.attachment.nativeBuild.observation = native.build.observation =
        "9".repeat(64);
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.build.source = "9".repeat(64);
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.build.rtl = "9".repeat(64);
    },
    ({ recording }) => {
      recording.catalogue.correspondence_origin.checkpoint = "9".repeat(64);
    },
    ({ recording }) => {
      recording.bundle.build.observation = "9".repeat(64);
    },
    ({ recording }) => {
      recording.catalogue.build.observation = "9".repeat(64);
    },
    ({ recording }) => {
      recording.catalogue.checkpoint = "9".repeat(64);
    },
    ({ graph }) => {
      graph.attachment.build.observation = "9".repeat(64);
    },
    ({ graph }) => {
      graph.attachment.nativeBuild.observation = "9".repeat(64);
    },
    ({ native }) => {
      native.build.source = "9".repeat(64);
    },
    ({ native }) => {
      native.build.rtl = "9".repeat(64);
    },
    ({ native }) => {
      native.checkpoint_sha256 = "9".repeat(64);
    },
  ]) {
    const { options } = await fixture(t, (state) => {
      extend(state);
      change(state);
    });
    await assert.rejects(
      () => attachComputations(options),
      /identity|correspondence/,
    );
    await assert.rejects(
      () => readFile(join(options.output, "computations", "manifest.json")),
      /ENOENT/,
    );
  }
});

test("multi-extension evidence must retain preceding trace and simulator continuity", async (t) => {
  for (const key of ["original_trace_sha256", "simulator_sha256"]) {
    const { options } = await fixture(t, (state) => {
      extend(state);
      extend(state, "f".repeat(64));
      state.recording.catalogue.correspondence_origin[key] = "9".repeat(64);
    });
    await assert.rejects(
      () => attachComputations(options),
      /preceding trace\/simulator/,
    );
  }
  const { options } = await fixture(t, (state) => {
    for (let i = 0; i < 17; i++) extend(state, String(i).padStart(64, "0"));
  });
  await assert.rejects(() => attachComputations(options), /chain too deep/);
});

test("a changed recording cannot reuse an earlier exact-byte binding", async (t) => {
  const { options } = await fixture(t, extend);
  await writeFile(options.view, "{}");
  await assert.rejects(() => attachComputations(options), /identity mismatch/);
});

/** A same-capture revision has no new simulator identity or tap population. */
function reinterpret({ graph, recording }, observation = "f".repeat(64)) {
  const previous = recording.catalogue.correspondence_origin ?? null,
    current = recording.bundle.build;
  const build = { ...current, observation };
  const trace = previous?.extended_trace_sha256 ?? "2".repeat(64);
  recording.catalogue.correspondence_origin = {
    kind: "observation-reinterpretation",
    schema: 1,
    build: { ...current },
    revised_build: build,
    previous_correspondence: previous,
    checkpoint: graph.checkpoint,
    base_projection_sha256: "1".repeat(64),
    original_trace_sha256: trace,
    extended_trace_sha256: trace,
    capture_bytes: 100,
    dependency_observer: "dependencies",
    original_plan_sha256: "4".repeat(64),
    revised_plan_sha256: "5".repeat(64),
    review_sha256: "6".repeat(64),
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
  graph.build = { ...build };
  graph.attachment.build = { ...build };
  recording.bundle.build = { ...build };
  recording.catalogue.build = { ...build };
}

test("same-capture revisions compose with existing native correspondence without fabricated simulator receipts", async (t) => {
  for (const setup of [
    reinterpret,
    (s) => {
      extend(s);
      reinterpret(s);
    },
    (s) => {
      reinterpret(s);
      extend(s, "9".repeat(64));
    },
    (s) => {
      extend(s);
      reinterpret(s);
      extend(s, "9".repeat(64));
    },
  ]) {
    const { options } = await fixture(t, setup);
    await attachComputations(options);
    const manifest = JSON.parse(
      await readFile(join(options.output, "computations", "manifest.json")),
    );
    assert.equal(manifest.attachment.nativeBuild.observation, "c".repeat(64));
  }
});

test("reinterpretation cannot bypass trace, plan, build, bounds or legacy simulator continuity checks", async (t) => {
  for (const change of [
    (s) =>
      (s.recording.catalogue.correspondence_origin.extended_trace_sha256 =
        "9".repeat(64)),
    (s) =>
      delete s.recording.catalogue.correspondence_origin.original_plan_sha256,
    (s) => delete s.recording.catalogue.correspondence_origin.review_sha256,
    (s) =>
      (s.recording.catalogue.correspondence_origin.revised_build.observation =
        "9".repeat(64)),
    (s) =>
      (s.recording.catalogue.correspondence_origin.comparison.old_dependency_bindings_retained = false),
    (s) =>
      (s.recording.catalogue.correspondence_origin.comparison.end_cycle = 4),
    (s) =>
      (s.recording.catalogue.correspondence_origin.kind =
        "unreviewed-revision"),
    (s) => {
      extend(s, "9".repeat(64));
      s.recording.catalogue.correspondence_origin.simulator_sha256 = "8".repeat(
        64,
      );
    },
  ]) {
    const { options } = await fixture(t, (s) => {
      extend(s);
      reinterpret(s);
      change(s);
    });
    await assert.rejects(
      () => attachComputations(options),
      /identity|comparison|correspondence/,
    );
  }
});
