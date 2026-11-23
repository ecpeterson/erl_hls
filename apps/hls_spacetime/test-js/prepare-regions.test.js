import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile, symlink, unlink, stat } from "node:fs/promises";
import { join, dirname } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { prepareRegions, parseArguments } from "../scripts/prepare-regions.mjs";
import { loadRegionalData, createRegionalData } from "../web/regional-data.js";
import { createModel } from "../web/model.js";
import { sourceFixture } from "./fixtures/computation-publication.js";
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");

/** Rehash a tiny publication after explicitly declaring native tile units and
 * installing full-net geometry including a branch absent from the timing path.
 * These synthetic records test preservation, not native hardware correctness. */
async function fixture(t, change = () => {}) {
  const f = await sourceFixture(t, true);
  const manifest = JSON.parse(
      await readFile(join(f.input, "computations/manifest.json")),
    ),
    tables = {};
  for (const part of manifest.parts)
    tables[part.table] = JSON.parse(
      await readFile(join(f.input, "computations", part.file)),
    );
  const view = structuredClone(f.view);
  view.catalogue.coordinate_unit = "tile_grid";
  view.catalogue.cells[2].x = null;
  view.catalogue.cells[2].y = null;
  tables.routeNets[0].nodes = [
    { id: "a", wires: [{ id: "wire-a", tile: "T1", x: 1, y: 2 }] },
    { id: "b", wires: [{ id: "wire-b", tile: "T17", x: 17, y: 2 }] },
    {
      id: "spare",
      wires: [{ id: "wire-outside-path", tile: "T200", x: 200, y: 2 }],
    },
    {
      id: "unknown",
      wires: [{ id: "wire-unknown", tile: null, x: null, y: null }],
    },
  ];
  tables.routeNets[0].pips = [
    {
      id: "exact-native-pip",
      from_node: "a",
      to_node: "b",
      direction_status: "directional",
      tile: "T16",
      x: 16,
      y: 2,
    },
    {
      id: "unknown-native-pip",
      from_node: null,
      to_node: null,
      direction_status: "unavailable",
      tile: null,
      x: null,
      y: null,
    },
  ];
  change({ view, tables });
  const save = async (file, value) => {
    const bytes = Buffer.from(JSON.stringify(value));
    await writeFile(join(f.input, file), bytes);
    return { file, bytes: bytes.length, sha256: sha(bytes) };
  };
  for (const part of manifest.parts) {
    const descriptor = await save(
      `computations/${part.file}`,
      tables[part.table],
    );
    Object.assign(part, descriptor, {
      file: part.file,
      rows: tables[part.table].length,
    });
  }
  manifest.totals = Object.fromEntries(
    Object.entries(tables).map(([key, rows]) => [key, rows.length]),
  );
  const recording = await save("recording.json", view);
  manifest.view = { bytes: recording.bytes, sha256: recording.sha256 };
  const computations = await save("computations/manifest.json", manifest);
  await save("index.json", {
    format: "spacetime-view-index",
    schema: 1,
    examples: [{ ...recording, title: "Synthetic", computations }],
  });
  return { ...f, view, recording, computations, tables };
}
async function load(f, result) {
  const data = await loadRegionalData({
    entry: result.regions,
    view: f.recording,
    source: f.computations,
    baseUrl: pathToFileURL(f.output + "/").href,
    fetcher: async (url) => new Response(await readFile(fileURLToPath(url))),
  });
  return createRegionalData(createModel(f.view), data);
}

test("sidecar counts complete native resources and preserves source/render publication", async (t) => {
  const f = await fixture(t),
    before = await readFile(join(f.input, "index.json")),
    result = await prepareRegions(f),
    data = await load(f, result);
  assert.equal(data.cells.length, 3);
  assert.equal(data.nets.length, 3);
  assert.equal(data.pips.length, 2);
  assert.equal(data.summary.unknownCellPositions, 1);
  assert.equal(data.summary.unknownPipPositions, 1);
  assert.equal(data.summary.wireMemberships, 4);
  assert.equal(data.summary.unknownWireMemberships, 1);
  assert.equal(data.summary.netsWithoutLocatedResources, 2);
  assert(
    data.nets[0].bins.some((bin) => data.bins[bin].x === 12),
    "unselected branch is retained",
  );
  assert.deepEqual(data.arcNets, [0, 1, null, null, 2]);
  assert.deepEqual(data.nets[0].unknownWires, ["wire-unknown"]);
  assert.equal(data.pips[0].id, "exact-native-pip");
  assert.deepEqual(await readFile(join(f.input, "index.json")), before);
  await assert.rejects(stat(join(f.output, "index.json")), { code: "ENOENT" });
  assert.deepEqual(
    JSON.parse(await readFile(join(f.output, "descriptor.json"))),
    result.regions,
  );
  const manifest = JSON.parse(await readFile(join(f.output, "manifest.json")));
  assert.equal(manifest.algorithm, 1);
  assert.equal(manifest.regions.coordinateUnit, "tile_grid");
  for (const descriptor of [...manifest.parts, result.regions]) {
    const raw = await readFile(join(f.output, descriptor.file));
    const decoded = gunzipSync(
      await readFile(join(f.output, `${descriptor.file}.gz`)),
      { maxOutputLength: descriptor.bytes },
    );
    assert.deepEqual(decoded, raw);
    assert.equal(decoded.length, descriptor.bytes);
    assert.equal(sha(decoded), descriptor.sha256);
  }
  assert(manifest.parts.every((part) => part.bytes <= 8 * 1024 * 1024));
  assert(result.decodedBytes <= 64 * 1024 * 1024);
  await assert.rejects(prepareRegions(f), /output already exists/);
});

test("repeated global PIP identities count once while preserving every canonical owner", async (t) => {
  const f = await fixture(t, ({ tables }) => {
    tables.routeNets[1] = {
      ...structuredClone(tables.routeNets[0]),
      id: tables.nets[1].id,
    };
  });
  const data = await load(f, await prepareRegions(f));
  assert.equal(data.pips.length, 2);
  assert.equal(data.summary.pipNetIncidences, 4);
  assert.deepEqual(data.pips[0].nets, [0, 1]);
  assert.equal(data.summary.wireMemberships, 8);
  const pipBin = data.bins.find((bin) => bin.pips.includes(0));
  assert.equal(pipBin.counts.pips, 1);
  assert.deepEqual(pipBin.nets, [0, 1]);
});

test("conflicting repeated native identity and unqualified coordinate units reject", async (t) => {
  const f = await fixture(t, ({ tables }) => {
    tables.routeNets[1] = {
      ...structuredClone(tables.routeNets[0]),
      id: tables.nets[1].id,
    };
    tables.routeNets[1].pips[0].x = 32;
    tables.routeNets[1].pips[0].tile = "T32";
  });
  await assert.rejects(prepareRegions(f), /conflicting shared PIP/);
  const unknown = await fixture(t, ({ view }) => {
    delete view.catalogue.coordinate_unit;
  });
  await assert.rejects(prepareRegions(unknown), /explicit tile_grid/);
});

test("changed source hashes and escaping symlinks fail before a valid sidecar is published", async (t) => {
  const f = await fixture(t);
  await writeFile(join(f.input, "computations/arcs.json"), "[]");
  await assert.rejects(prepareRegions(f), /length mismatch/);
  const linked = await fixture(t),
    source = join(linked.input, "computations/arcs.json"),
    outside = join(dirname(linked.input), "outside.json");
  await writeFile(outside, await readFile(source));
  await unlink(source);
  await symlink(outside, source);
  await assert.rejects(prepareRegions(linked), /symlink escapes/);
  await assert.rejects(stat(join(linked.output, "manifest.json")), {
    code: "ENOENT",
  });
});

test("CLI options are explicit and last-wins without changing render algorithm", () => {
  assert.deepEqual(
    parseArguments([
      "--input",
      "old",
      "--input",
      "new",
      "--output",
      "regions",
      "--bin-size",
      "8",
      "--bin-size",
      "16",
    ]),
    { input: "new", output: "regions", binSize: 16 },
  );
  for (const value of ["0", "-1", "1.5", "NaN", "4097"])
    assert.throws(
      () => parseArguments(["--bin-size", value]),
      /option|bin size/,
    );
  assert.throws(() => parseArguments(["--unknown", "x"]), /option/);
});
