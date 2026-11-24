import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  selectRoutes,
  writeSelection,
  parseArguments,
} from "../scripts/select-routes.mjs";

const bytes = (value) => Buffer.from(JSON.stringify(value));
const hash = (value) => createHash("sha256").update(value).digest("hex");

/** One static path resolves through a different canonical-net name, without hardware. */
function fixture() {
  const build = {
    source: "1".repeat(64),
    rtl: "2".repeat(64),
    observation: "3".repeat(64),
  };
  const checkpoint = "4".repeat(64),
    report = "5".repeat(64);
  const cells = [
    { id: "ff0", kind: "FDRE", x: 1, y: 2 },
    { id: "ff1", kind: "FDRE", x: 4, y: 2 },
  ];
  const physical = {
    build,
    checkpoint,
    coordinate_unit: "tile_grid",
    bindings: [],
    cells,
    nets: [
      {
        id: "canonical",
        pins: [
          { native: "ff0/Q", cell: "ff0", pin: "Q", direction: "output" },
          { native: "ff1/D", cell: "ff1", pin: "D", direction: "input" },
        ],
      },
    ],
    native: { aliases: [{ id: "reported", net: "canonical" }] },
  };
  const bundle = {
    format: "spacetime",
    schema: 1,
    unit: "cycle",
    build,
    physical,
    resources: [],
    events: [],
    versions: [],
    relations: [],
    capture: {
      first_cycle: 0,
      end_cycle: 2,
      complete: true,
      observers: [],
      incarnations: [{ id: "epoch", first_cycle: 0, end_cycle: 2 }],
    },
  };
  const path = {
    id: "max/0",
    source: "ff0/C",
    endpoint: "ff1/D",
    launchPin: "ff0/Q",
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
        net: "reported",
        fanout: 1,
        delayNs: 0.5,
        arrivalNs: 0.6,
      },
    ],
  };
  const view = {
    format: "spacetime-view",
    schema: 1,
    bundle: { ...bundle, physical: null },
    catalogue: {
      build,
      checkpoint,
      coordinate_unit: "tile_grid",
      bindings: [],
      cells: structuredClone(cells),
    },
    nativePaths: {
      build,
      checkpoint,
      scope: "static_timing",
      wireGeometry: false,
      report: "timing.rpt",
      report_sha256: report,
      paths: [path],
    },
    provenance: { sources: [{ file: "timing.rpt", raw_sha256: report }] },
  };
  return { view, bundle };
}

/** Byte conversion occurs after fixture mutations so each invocation models independent inputs. */
function select(input) {
  return selectRoutes({
    viewBytes: bytes(input.view),
    bundleBytes: bytes(input.bundle),
  });
}

test("selection resolves aliases and both native pins and binds exact input bytes", () => {
  const input = fixture(),
    result = select(input);
  assert.equal(result.nets, 1);
  assert.deepEqual(result.arcs, [
    {
      path_id: "max/0",
      arc_index: 0,
      report_net: "reported",
      canonical_net: "canonical",
      source_pin: "ff0/Q",
      target_pin: "ff1/D",
    },
  ]);
  assert.equal(result.selection.projectionSha256, hash(bytes(input.view)));
  assert.equal(
    result.selection.catalogueBundle.sha256,
    hash(bytes(input.bundle)),
  );
  assert.deepEqual(result.selection.paths, input.view.nativePaths.paths);
  assert.match(result.selectionTcl, new RegExp(hash(result.selectionBytes)));
});

test("stale build, report, placement and endpoint membership cannot select a route", () => {
  for (const [change, expected] of [
    [(x) => (x.bundle.physical.checkpoint = "6".repeat(64)), /checkpoint/],
    [
      (x) => (x.view.provenance.sources[0].raw_sha256 = "6".repeat(64)),
      /provenance/,
    ],
    [(x) => x.bundle.physical.cells[0].x++, /placement/],
    [(x) => x.bundle.physical.nets[0].pins.pop(), /pin\/net/],
    [
      (x) => (x.bundle.physical.nets[0].pins[0].direction = "input"),
      /pin\/net/,
    ],
    [(x) => (x.bundle.physical.native.aliases[0].id = "not-reported"), /alias/],
    [
      (x) =>
        x.bundle.physical.native.aliases.push(
          x.bundle.physical.native.aliases[0],
        ),
      /duplicate/,
    ],
    [(x) => (x.view.nativeRoutes = {}), /already/],
    [(x) => (x.view.nativePaths.paths = []), /one and fifty/],
  ]) {
    const input = fixture();
    change(input);
    assert.throws(() => select(input), expected);
  }
});

test("generated Tcl round-trips metacharacters without evaluating native names", async () => {
  const input = fixture(),
    name = 'n$[puts UNEXPECTED]{unclosed\\"tail';
  input.view.nativePaths.paths[0].arcs[0].net = name;
  input.bundle.physical.native.aliases[0].id = name;
  const result = select(input),
    root = await mkdtemp(join(tmpdir(), "spacetime-route-tcl-"));
  try {
    const selection = join(root, "selection.tcl"),
      driver = join(root, "check.tcl");
    await writeFile(selection, result.selectionTcl);
    await writeFile(
      driver,
      "source [lindex $argv 0]\nsource [lindex $argv 1]\nputs [dict get [lindex [::hls_spacetime_routes::selection $selection] 0] report_net]\n",
    );
    const exporter = fileURLToPath(
      new URL("../../hls_target/priv/tools/export_routes.tcl", import.meta.url),
    );
    assert.equal(
      execFileSync("tclsh", [driver, exporter, selection], {
        encoding: "utf8",
      }),
      name + "\n",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("portable controls use explicit native argv paths and refuse output reuse", async () => {
  const input = fixture(),
    root = await mkdtemp(join(tmpdir(), "spacetime-route-select-"));
  try {
    const view = join(root, "view.json"),
      bundle = join(root, "bundle.json"),
      output = join(root, "control");
    await writeFile(view, bytes(input.view));
    await writeFile(bundle, bytes(input.bundle));
    const result = await writeSelection({ view, bundle, output });
    assert.equal(result.arcs, 1);
    const manifest = JSON.parse(await readFile(join(output, "manifest.json")));
    assert.equal(manifest.complete, true);
    const driver = await readFile(join(output, "run.tcl"), "utf8");
    assert.match(driver, /lassign \$argv checkpoint exporter output/);
    assert.match(driver, /seconds 600 records 200000 bytes 33554432 nets 1000/);
    for (const entry of manifest.files)
      assert.equal(
        hash(await readFile(join(output, entry.file))),
        entry.sha256,
      );
    await assert.rejects(writeSelection({ view, bundle, output }), /EEXIST/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("repeated scalar options take the last value", () => {
  assert.deepEqual(
    parseArguments([
      "--view",
      "old",
      "--view",
      "new",
      "--bundle",
      "full",
      "--output",
      "out",
    ]),
    { view: "new", bundle: "full", output: "out" },
  );
  assert.throws(() => parseArguments(["--view"]), /incomplete/);
});
