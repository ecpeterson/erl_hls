import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";
import { prepareRender, parseArguments } from "../scripts/prepare-render.mjs";
import { loadPreparedRender } from "../web/prepared-loader.js";
import {
  createPreparedComputations,
  preparedComputationLayers,
  preparedCircuitPaint,
} from "../web/prepared-computations.js";
import { createModel } from "../web/model.js";

import { sourceFixture } from "./fixtures/computation-publication.js";

test("fresh portable derivative keeps exact recording/full source and loads without raw source reads", async (t) => {
  const f = await sourceFixture(t),
    result = await prepareRender(f);
  assert.equal(result.sourceCounts.writes, 1);
  assert.equal(result.counts.cones, 1);
  const index = JSON.parse(await readFile(join(f.output, "index.json"))),
    entry = index.examples[0];
  assert.deepEqual(entry.computations, f.computations);
  assert.deepEqual(
    await readFile(join(f.input, "recording.json")),
    await readFile(join(f.output, "recording.json")),
  );
  const graph = JSON.parse(
    await readFile(join(f.output, entry.computations.file)),
  );
  for (const part of graph.parts)
    assert.deepEqual(
      await readFile(join(f.input, "computations", part.file)),
      await readFile(join(f.output, "computations", part.file)),
    );
  const requested = [];
  const data = await loadPreparedRender({
    entry: entry.render,
    view: f.recording,
    source: entry.computations,
    baseUrl: pathToFileURL(f.output + "/").href,
    fetcher: async (url) => {
      requested.push(url);
      return new Response(await readFile(fileURLToPath(url)));
    },
  });
  assert(requested.every((url) => url.includes("/render/")));
  assert.equal(data.algorithm, 3);
  assert.deepEqual(data.pinGeometry, [
    [0, 10, 20],
    [0, 10, 20],
  ]);
  assert.deepEqual(data.arcGeometry, [[0, 1, 0, 0.02]]);
  for (const scope of ["registered", "static"])
    assert.deepEqual(
      Object.fromEntries(
        data.cones[0].pinIndices.map((pin, i) => [
          pin,
          data.cones[0].pinArrivals[scope][i],
        ]),
      ),
      { 0: 0, 1: 0.02 },
    );
  assert.deepEqual(
    gunzipSync(await readFile(join(f.output, "recording.json.gz"))),
    await readFile(join(f.output, "recording.json")),
  );
  const renderManifest = JSON.parse(
    await readFile(join(f.output, entry.render.file)),
  );
  assert.equal(renderManifest.algorithm, 3);
  assert.equal(renderManifest.totals.pinGeometry, 2);
  assert.equal(renderManifest.totals.arcGeometry, 1);
  for (const table of ["pinGeometry", "arcGeometry"])
    assert(
      renderManifest.parts.some(
        (part) => part.table === table && part.encoding === "json-rows-v1",
      ),
    );
  for (const part of renderManifest.parts)
    assert.deepEqual(
      gunzipSync(await readFile(join(f.output, "render", `${part.file}.gz`))),
      await readFile(join(f.output, "render", part.file)),
    );
  const prepared = createPreparedComputations(createModel(f.view), data);
  assert.equal(
    preparedComputationLayers(prepared, ["w"])[0].cones[0].registeredDelayNs,
    0.02,
  );
  await assert.rejects(prepareRender(f), /EEXIST/);
});

test("changed source bytes reject before publication; scalar CLI values use last occurrence", async (t) => {
  const f = await sourceFixture(t);
  await writeFile(join(f.input, "computations", "arcs.json"), "[]");
  await assert.rejects(prepareRender(f), /length mismatch/);
  assert.deepEqual(
    parseArguments(["--input", "old", "--input", "new", "--output", "fresh"]),
    { input: "new", output: "fresh" },
  );
});

test("publication carries complete branch costs into shared geometry without dropping any primitives", async (t) => {
  const f = await sourceFixture(t, true);
  await prepareRender(f);
  const entry = JSON.parse(await readFile(join(f.output, "index.json")))
    .examples[0];
  const data = await loadPreparedRender({
    entry: entry.render,
    view: f.recording,
    source: entry.computations,
    baseUrl: pathToFileURL(f.output + "/").href,
    fetcher: async (url) => new Response(await readFile(fileURLToPath(url))),
  });
  const index = createPreparedComputations(createModel(f.view), data);
  const layer = preparedComputationLayers(index, ["w"])[0];
  const paint = preparedCircuitPaint(index, layer);
  assert.equal(layer.cones[0].registeredDelayNs, 8);
  assert.equal(data.algorithm, 3);
  assert.deepEqual(index.pinGeometry, [
    [0, 10, 20],
    [0, 10, 20],
    [1, 20, 20],
    [2, 30, 20],
    [2, 30, 20],
    [2, 30, 20],
  ]);
  assert.deepEqual(index.arcGeometry, [
    [0, 3, 0, 1],
    [2, 4, 0, 3],
    [3, 5, 1, 2],
    [4, 5, 1, 4],
    [5, 1, 0, 1],
  ]);
  for (const scope of ["registered", "static"])
    assert.deepEqual(
      Object.fromEntries(
        layer.cones[0].pinIndices.map((pin, i) => [
          pin,
          layer.cones[0].pinArrivals[scope][i],
        ]),
      ),
      { 0: 0, 1: 8, 2: 0, 3: 1, 4: 3, 5: 7 },
    );
  assert.deepEqual(index.maxDelays, { registered: 8, static: 8 });
  assert.equal(paint.segments.length, 3);
  for (const row of paint.segments) {
    const expected = row.sourceNet === 0 ? 4 : 8;
    assert.equal(row.registeredPathDelayNs, expected);
    assert.equal(row.staticPathDelayNs, expected);
    assert.equal(row.registeredPathTimingUnknown, false);
  }
  assert.equal(
    paint.cells.find((row) => row.sourceCell === 2).registeredPathDelayNs,
    8,
  );
  assert.equal(paint.cells.length, 3);
});
