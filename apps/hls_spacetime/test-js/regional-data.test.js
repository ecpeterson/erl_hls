import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRegionalData, loadRegionalData } from "../web/regional-data.js";
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const tables = ["cells", "pips", "nets", "arcNets", "bins"];
function fixture() {
  const build = {
      source: "a".repeat(64),
      rtl: "b".repeat(64),
      observation: "c".repeat(64),
      implementation: "f".repeat(64),
    },
    checkpoint = "d".repeat(64);
  const cells = [
    { id: "ff0", kind: "FDRE", x: 1, y: 2, bin: 0 },
    { id: "ff1", kind: "FDRE", x: 2, y: 2, bin: 0 },
    { id: "unknown", kind: null, x: null, y: null, bin: null },
  ];
  const model = {
    catalogue: { coordinate_unit: "tile_grid", checkpoint },
    bundle: { build },
    cells: new Map(cells.map((row) => [row.id, { ...row }])),
  };
  const data = {
    format: "spacetime-regions",
    schema: 1,
    algorithm: 1,
    coordinateUnit: "tile_grid",
    binSize: 16,
    build,
    checkpoint,
    sourceCounts: {
      cells: 3,
      pins: 0,
      nets: 2,
      arcs: 3,
      routeNets: 2,
      pipMemberships: 4,
      wireMemberships: 3,
    },
    cells,
    pips: [
      {
        id: "pip-shared",
        tile: "T0",
        x: 1,
        y: 2,
        directionStatus: "directional",
        nets: [0, 1],
      },
      {
        id: "pip-other",
        tile: "T1",
        x: 17,
        y: 2,
        directionStatus: "directional",
        nets: [0],
      },
      {
        id: "pip-unknown",
        tile: null,
        x: null,
        y: null,
        directionStatus: "unavailable",
        nets: [1],
      },
    ],
    nets: [
      {
        id: "net0",
        bins: [0, 1],
        pips: [0, 1],
        wireBins: [
          { bin: 0, count: 1 },
          { bin: 1, count: 1 },
        ],
        wireCount: 3,
        locatedWireCount: 2,
        unknownWires: ["wire-unlocated"],
        status: "complete",
        routeStatus: "ROUTED",
      },
      {
        id: "net1",
        bins: [0],
        pips: [0, 2],
        wireBins: [],
        wireCount: 0,
        locatedWireCount: 0,
        unknownWires: [],
        status: "complete",
        routeStatus: "ROUTED",
      },
    ],
    arcNets: [0, 0, null],
    bins: [
      { x: 0, y: 0, cells: [0, 1], pips: [0], nets: [0, 1] },
      { x: 1, y: 0, cells: [], pips: [1], nets: [0] },
    ],
  };
  return { model, data };
}
function publication(data) {
  const bodies = new Map(),
    parts = [];
  for (const table of tables) {
    const bytes = Buffer.from(JSON.stringify(data[table])),
      file = `${table}.json`;
    bodies.set(file, bytes);
    parts.push({
      file,
      table,
      rows: data[table].length,
      bytes: bytes.length,
      sha256: sha(bytes),
    });
  }
  const view = { bytes: 2, sha256: "e".repeat(64) },
    source = {
      file: "computations/manifest.json",
      bytes: 2,
      sha256: "f".repeat(64),
    };
  const manifest = {
    format: "spacetime-regions-manifest",
    schema: 1,
    algorithm: 1,
    view,
    source,
    regions: Object.fromEntries(
      Object.entries(data).filter(([key]) => !tables.includes(key)),
    ),
    parts,
    totals: Object.fromEntries(
      tables.map((table) => [table, data[table].length]),
    ),
  };
  const save = () => {
    const bytes = Buffer.from(JSON.stringify(manifest));
    bodies.set("manifest.json", bytes);
    return { file: "manifest.json", bytes: bytes.length, sha256: sha(bytes) };
  };
  const requested = [];
  return {
    manifest,
    bodies,
    save,
    view,
    source,
    requested,
    fetcher: async (url) => {
      const file = new URL(url).pathname.split("/").at(-1);
      requested.push(file);
      return new Response(bodies.get(file), {
        status: bodies.has(file) ? 200 : 404,
      });
    },
  };
}

test("native contributors reconcile without branch, sink or clock double counting", () => {
  const { model, data } = fixture(),
    snapshot = structuredClone(data),
    index = createRegionalData(model, data);
  assert.deepEqual(index.bins[0].counts, { cells: 2, pips: 1, nets: 2 });
  assert.equal(index.maxima.primitiveKinds.FDRE, 2);
  assert.deepEqual(index.bins[1].bounds, {
    minX: 16,
    minY: 0,
    maxX: 32,
    maxY: 16,
  });
  assert.equal(index.summary.pips, 3);
  assert.equal(index.summary.pipNetIncidences, 4);
  assert.equal(index.summary.netBinIncidences, 3);
  assert.equal(index.summary.unknownCellKinds, 1);
  assert.equal(index.summary.unknownCellPositions, 1);
  assert.equal(index.summary.unknownPipPositions, 1);
  assert.equal(index.summary.unknownPipDirections, 1);
  assert.equal(index.summary.unknownWireMemberships, 1);
  assert.equal(index.summary.netsWithUnknownPositions, 2);
  assert.deepEqual(data, snapshot);
});

test("coincident distinct PIPs remain distinct physical resource contributors", () => {
  const { model, data } = fixture();
  data.pips.push({ ...data.pips[0], id: "another-pip", nets: [0] });
  data.nets[0].pips.push(3);
  data.bins[0].pips.push(3);
  data.sourceCounts.pipMemberships++;
  const index = createRegionalData(model, data);
  assert.equal(index.maxima.pips, 2);
  assert.deepEqual(index.bins[0].pips, [0, 3]);
});

test("omissions, duplicate identities, wrong footprint and unknown-count drift reject", () => {
  const mutations = [
    (d) => d.bins[0].cells.pop(),
    (d) => d.bins[0].nets.pop(),
    (d) => d.pips[0].nets.pop(),
    (d) => d.nets[0].wireBins.pop(),
    (d) => d.nets[0].unknownWires.push("extra"),
    (d) => d.nets[0].bins.pop(),
    (d) => (d.pips[1].id = d.pips[0].id),
    (d) => (d.arcNets[0] = 2),
    (d) => (d.cells[0].bin = 1),
    (d) => d.sourceCounts.pipMemberships++,
    (d) => (d.coordinateUnit = "micrometres"),
    (d) => (d.cells[0].x = null),
    (d) => (d.build.source = "0".repeat(64)),
    (d) => (d.checkpoint = "0".repeat(64)),
  ];
  for (const mutate of mutations) {
    const { model, data } = fixture();
    data.build = { ...data.build };
    mutate(data);
    assert.throws(() => createRegionalData(model, data), /Regional data:/);
  }
  const { model, data } = fixture();
  delete model.catalogue.coordinate_unit;
  assert.throws(() => createRegionalData(model, data), /coordinate/);
});

test("optional loader verifies complete sidecar without fetching native source", async () => {
  const { model, data } = fixture(),
    f = publication(data);
  assert.equal(await loadRegionalData({ entry: null }), null);
  assert.equal(f.requested.length, 0);
  const loaded = await loadRegionalData({
    ...f,
    entry: f.save(),
    baseUrl: "https://local.example/regions/",
  });
  assert.deepEqual(loaded, data);
  assert.equal(createRegionalData(model, loaded).summary.pips, 3);
  assert.equal(f.requested.length, 6);
  assert(!f.requested.some((file) => file.includes("computation")));
});

test("hash, bounds, path and identity failures reject before exposing any prefix", async () => {
  const { data } = fixture();
  for (const mutate of [
    (f) => (f.manifest.parts[0].file = "../outside.json"),
    (f) => (f.manifest.view.sha256 = "0".repeat(64)),
    (f) => (f.manifest.source = { ...f.source, sha256: "0".repeat(64) }),
    (f) => (f.manifest.parts[0].bytes = 8 * 1024 * 1024 + 1),
    (f) => f.manifest.parts.push({ ...f.manifest.parts[0] }),
    (f) => f.manifest.totals.cells++,
  ]) {
    const f = publication(data),
      expectedView = { ...f.view },
      expectedSource = { ...f.source };
    mutate(f);
    await assert.rejects(
      loadRegionalData({
        ...f,
        view: expectedView,
        source: expectedSource,
        entry: f.save(),
        baseUrl: "https://local.example/regions/",
      }),
      /Regional data:/,
    );
    assert.equal(f.requested.length, 1);
  }
  const hashFailure = publication(data),
    entry = hashFailure.save();
  hashFailure.bodies.set("cells.json", Buffer.from("[]"));
  await assert.rejects(
    loadRegionalData({
      ...hashFailure,
      entry,
      baseUrl: "https://local.example/regions/",
    }),
    /length mismatch/,
  );
  const overflow = publication(data),
    overflowEntry = overflow.save();
  overflow.bodies.set(
    "cells.json",
    Buffer.concat([overflow.bodies.get("cells.json"), Buffer.from(" ")]),
  );
  await assert.rejects(
    loadRegionalData({
      ...overflow,
      entry: overflowEntry,
      baseUrl: "https://local.example/regions/",
    }),
    /exceeds declared/,
  );
  const total = publication(data);
  total.manifest.parts = [];
  total.manifest.totals = Object.fromEntries(tables.map((table) => [table, 0]));
  for (let n = 0; n < 9; n++)
    total.manifest.parts.push({
      file: `large-${n}.json`,
      table: "cells",
      rows: 0,
      bytes: 8 * 1024 * 1024,
      sha256: "0".repeat(64),
    });
  await assert.rejects(
    loadRegionalData({
      ...total,
      entry: total.save(),
      baseUrl: "https://local.example/regions/",
    }),
    /64 MiB/,
  );
  assert.equal(total.requested.length, 1);
});
