import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  attachRoutes,
  attachRouteFiles,
  parseArguments,
} from "../scripts/attach-routes.mjs";

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const identity = (digit) => digit.repeat(64);
const bytes = (value) => Buffer.from(JSON.stringify(value));

/** One native-shaped route, independent of any simulation or vendor witness. */
function fixture() {
  const build = {
    source: identity("1"),
    rtl: identity("2"),
    observation: identity("3"),
  };
  const checkpoint = identity("4"),
    report = identity("5");
  const path = {
    id: "max/0",
    source: "ff0/C",
    launchPin: "ff0/Q",
    endpoint: "ff1/D",
    slackNs: 4.5,
    dataDelayNs: 0.5,
    logicDelayNs: 0,
    routeDelayNs: 0.5,
    logicLevels: 0,
    steps: [
      { cell: "ff0", pin: "ff0/Q", incrementNs: 0.1, arrivalNs: 0.1 },
      { cell: "ff1", pin: "ff1/D", incrementNs: null, arrivalNs: null },
    ],
    arcs: [
      {
        kind: "net",
        source: "ff0/Q",
        target: "ff1/D",
        net: "n",
        fanout: 1,
        delayNs: 0.5,
        arrivalNs: 0.6,
      },
    ],
  };
  const view = {
    format: "spacetime-view",
    schema: 1,
    title: "synthetic route attachment",
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        first_cycle: 0,
        end_cycle: 3,
        complete: true,
        observers: [],
        incarnations: [{ id: "epoch", first_cycle: 0, end_cycle: 3 }],
      },
      resources: [],
      events: [],
      versions: [],
      relations: [],
      physical: null,
    },
    catalogue: {
      build,
      checkpoint,
      coordinate_unit: "tile_grid",
      cells: [
        { id: "ff0", kind: "FDRE", x: 1, y: 2 },
        { id: "ff1", kind: "FDRE", x: 3, y: 2 },
      ],
      bindings: [],
    },
    nativePaths: {
      build,
      checkpoint,
      scope: "static_timing",
      wireGeometry: false,
      report: "catalogue/timing.rpt.gz",
      paths: [path],
    },
    provenance: {
      sources: [
        {
          archive: "physical",
          file: "catalogue/timing.rpt.gz",
          raw_sha256: report,
        },
      ],
    },
    annotations: { public: [], boundaries: [] },
    scope: ["synthetic evidence only"],
  };
  const selection = {
    schema: 1,
    checkpoint,
    build,
    reportSha256: report,
    paths: structuredClone(view.nativePaths.paths),
  };
  const attachment = (pin, direction, node) => ({
    pin,
    direction,
    bel_pins: [`bel/${pin}`],
    site_pins: [{ id: `site/${pin}`, node }],
    routing_node: node,
    status: "resolved",
  });
  const routes = {
    schema_version: 1,
    complete: true,
    build,
    checkpoint_sha256: checkpoint,
    report_sha256: report,
    scope: "static_route_topology",
    coordinate_unit: "tile_grid",
    paths: [
      {
        path_id: "max/0",
        arc_index: 0,
        report_net: "n",
        canonical_net: "n",
        source_pin: "ff0/Q",
        target_pin: "ff1/D",
      },
    ],
    nets: [
      {
        id: "n",
        route_status: "ROUTED",
        status: "available",
        nodes: [
          { id: "a", wires: [{ id: "w-a", tile: "T_X1Y2", x: 1, y: 2 }] },
          { id: "b", wires: [{ id: "w-b", tile: "T_X3Y2", x: 3, y: 2 }] },
        ],
        pips: [
          {
            id: "p",
            tile: "T_X1Y2",
            x: 1,
            y: 2,
            from_node: "a",
            to_node: "b",
            direction_status: "directional",
          },
        ],
        pin_attachments: [
          attachment("ff0/Q", "OUT", "a"),
          attachment("ff1/D", "IN", "b"),
        ],
        issues: [],
      },
    ],
  };
  return { view, selection, routes };
}

/** Freeze selection and route identities after choosing the exact base bytes. */
function encoded(input = fixture()) {
  const viewBytes = bytes(input.view);
  const selectionBytes = bytes({
    ...input.selection,
    projectionSha256: hash(viewBytes),
  });
  const routesBytes = bytes({
    ...input.routes,
    selection_sha256: hash(selectionBytes),
  });
  return { viewBytes, selectionBytes, routesBytes };
}

/** Change one already-bound input to exercise byte-identity validation. */
function mutate(input, name, change) {
  const value = JSON.parse(input[name]);
  change(value);
  return { ...input, [name]: bytes(value) };
}

test("route attachment preserves graph/capture and records every exact input identity", () => {
  const input = fixture(),
    bound = encoded(input);
  const originals = Object.fromEntries(
    Object.entries(bound).map(([key, value]) => [key, Buffer.from(value)]),
  );
  const result = attachRoutes(bound);
  assert.deepEqual(result.bundle, input.view.bundle);
  assert.deepEqual(result.catalogue, input.view.catalogue);
  assert.deepEqual(result.annotations, input.view.annotations);
  assert.deepEqual(result.scope, input.view.scope);
  assert.deepEqual(result.nativePaths.paths, input.view.nativePaths.paths);
  assert.deepEqual(result.nativeRoutes, JSON.parse(bound.routesBytes));
  assert.equal(result.nativePaths.report_sha256, input.selection.reportSha256);
  assert.equal(
    result.nativePaths.route_selection_sha256,
    hash(bound.selectionBytes),
  );
  for (const role of ["view", "selection", "routes"])
    assert.deepEqual(result.provenance.route_attachment.inputs[role], {
      bytes: bound[`${role}Bytes`].length,
      sha256: hash(bound[`${role}Bytes`]),
    });
  assert.deepEqual(bound, originals);
});

test("original native build is retained through explicit capture-extension provenance", () => {
  const input = fixture(),
    original = input.selection.build;
  const extended = { ...original, observation: identity("6") };
  input.view.bundle.build = extended;
  for (const detail of [input.view.catalogue, input.view.nativePaths]) {
    detail.build = extended;
    detail.correspondence_origin = {
      build: original,
      checkpoint: input.selection.checkpoint,
      previous_correspondence: null,
      base_projection_sha256: identity("7"),
      original_trace_sha256: identity("8"),
      extended_trace_sha256: identity("9"),
      simulator_sha256: identity("a"),
      comparison: {
        old_taps_equal: true,
        public_fields_equal: true,
        original_taps: 1,
        first_cycle: 0,
        end_cycle: 3,
        compared_cycles: 3,
      },
    };
  }
  const result = attachRoutes(encoded(input));
  assert.deepEqual(result.nativeRoutes.build, original);
  assert.deepEqual(result.bundle.build, extended);
  delete input.view.catalogue.correspondence_origin;
  assert.throws(
    () => attachRoutes(encoded(input)),
    /build|correspondence|origin/,
  );
});

test("mismatched selected view/export bytes and checkpoint/report identities reject", () => {
  const bound = encoded();
  assert.throws(
    () =>
      attachRoutes(
        mutate(bound, "viewBytes", (v) => {
          v.title += " changed";
        }),
      ),
    /projection hash/,
  );
  assert.throws(
    () =>
      attachRoutes(
        mutate(bound, "routesBytes", (r) => {
          r.selection_sha256 = identity("9");
        }),
      ),
    /selection hash/,
  );
  for (const field of ["checkpoint_sha256", "report_sha256"])
    assert.throws(
      () =>
        attachRoutes(
          mutate(bound, "routesBytes", (r) => {
            r[field] = identity("9");
          }),
        ),
      /checkpoint\/report/,
    );
  assert.throws(
    () =>
      attachRoutes(
        mutate(bound, "routesBytes", (r) => {
          r.build.observation = identity("9");
        }),
      ),
    /build mismatch/,
  );
});

test("selected paths and original report provenance cannot be silently replaced", () => {
  for (const corrupt of [
    (x) => {
      x.selection.paths[0].slackNs = 1;
    },
    (x) => {
      x.view.provenance.sources[0].raw_sha256 = identity("9");
    },
    (x) => {
      x.view.provenance.sources = [];
    },
    (x) => {
      x.view.nativePaths.report_sha256 = identity("9");
    },
    (x) => {
      x.view.nativePaths.route_selection_sha256 = identity("9");
    },
    (x) => {
      x.view.nativePaths.checkpoint = identity("9");
    },
  ]) {
    const input = fixture();
    corrupt(input);
    assert.throws(
      () => attachRoutes(encoded(input)),
      /paths changed|provenance|identity|checkpoint/,
    );
  }
});

test("invalid route topology and already attached views reject", () => {
  const invalid = fixture();
  invalid.routes.paths[0].target_pin = "ff0/D";
  assert.throws(() => attachRoutes(encoded(invalid)));
  const input = fixture();
  input.view.nativeRoutes = {};
  assert.throws(() => attachRoutes(encoded(input)), /already has/);
  input.view.nativeRoutes = null;
  input.view.provenance.route_attachment = {};
  assert.throws(() => attachRoutes(encoded(input)), /already has/);
});

test("bounded byte inputs reject oversized selection and invalid UTF-8", () => {
  const bound = encoded();
  assert.throws(
    () =>
      attachRoutes({
        ...bound,
        selectionBytes: new Uint8Array(4 * 1024 * 1024 + 1),
      }),
    /byte limit/,
  );
  assert.throws(() =>
    attachRoutes({ ...bound, routesBytes: Uint8Array.from([0xff]) }),
  );
});

test("file command creates a new projection without modifying inputs or replacing outputs", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "spacetime-route-attach-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const input = encoded(),
    paths = {};
  for (const role of ["view", "selection", "routes"]) {
    paths[role] = join(directory, `${role}.json`);
    await writeFile(paths[role], input[`${role}Bytes`]);
  }
  paths.out = join(directory, "attached.json");
  const result = await attachRouteFiles(paths),
    output = await readFile(paths.out);
  assert.equal(result.bytes, output.length);
  assert.equal(result.sha256, hash(output));
  assert.equal(result.selectedPaths, 1);
  assert.equal(result.routeNets, 1);
  for (const role of ["view", "selection", "routes"])
    assert.deepEqual(await readFile(paths[role]), input[`${role}Bytes`]);
  await assert.rejects(attachRouteFiles(paths), { code: "EEXIST" });
  assert.deepEqual(await readFile(paths.out), output);
  await assert.rejects(attachRouteFiles({ ...paths, out: paths.view }), {
    code: "EEXIST",
  });
  assert.deepEqual(await readFile(paths.view), input.viewBytes);
});

test("route command options compose with later precedence and reject unknown arguments", () => {
  assert.deepEqual(
    parseArguments([
      "--view",
      "old",
      "--view",
      "new",
      "--selection",
      "s",
      "--routes",
      "r",
      "--out",
      "o",
    ]),
    { view: "new", selection: "s", routes: "r", out: "o" },
  );
  assert.deepEqual(parseArguments(["--help"]), { help: true });
  assert.throws(() => parseArguments(["--other", "x"]));
  assert.throws(() => parseArguments(["--view"]));
});
