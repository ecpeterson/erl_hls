import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  loadPreparedRender,
  loadPreparedRenderWorker,
} from "../web/prepared-loader.js";

function fixture() {
  const files = new Map(),
    requested = [];
  const save = (path, value) => {
    const b = Buffer.from(JSON.stringify(value));
    files.set(`https://example.test/data/${path}`, b);
    return {
      file: path,
      bytes: b.length,
      sha256: createHash("sha256").update(b).digest("hex"),
    };
  };
  const view = { bytes: 22, sha256: "a".repeat(64) },
    names = ["operations", "writes", "cones", "routes", "primitives"];
  const parts = names.map((table) => ({
    ...save(
      `render/${table}.json`,
      table === "primitives" ? [[0, 0, 1, 2, 0]] : [{ id: table }],
    ),
    file: `${table}.json`,
    table,
    encoding: table === "primitives" ? "geometry-tuples-v1" : "json-rows-v1",
    rows: 1,
  }));
  const manifest = {
    format: "spacetime-render-manifest",
    schema: 1,
    algorithm: 1,
    view,
    source: {
      file: "computations/manifest.json",
      bytes: 200,
      sha256: "b".repeat(64),
    },
    parts,
    totals: Object.fromEntries(names.map((n) => [n, 1])),
    render: { build: { source: "s", rtl: "r", observation: "o" } },
  };
  const publish = () => save("render/manifest.json", manifest);
  const fetcher = async (url) => {
    requested.push(url);
    return new Response(files.get(url), { status: files.has(url) ? 200 : 404 });
  };
  const source = { ...manifest.source };
  const options = () => ({
    entry: publish(),
    view,
    source,
    baseUrl: "https://example.test/data/",
    fetcher,
  });
  return { files, manifest, view, options, requested };
}
test("render loading checks all derivative parts without fetching full native source", async () => {
  const f = fixture(),
    result = await loadPreparedRenderWorker(f.options());
  assert.equal(result.operations[0].id, "operations");
  assert.equal(result.source.sha256, "b".repeat(64));
  assert.equal(f.requested.length, 6);
  assert(f.requested.every((p) => p.includes("/render/")));
  assert.equal(await loadPreparedRender({ entry: null }), null);
});
test("stale recording, changed bytes, paths and incomplete inventories reject", async () => {
  for (const mutate of [
    (f) => (f.manifest.view = { ...f.view, bytes: 23 }),
    (f) => (f.manifest.parts[0].file = "../elsewhere.json"),
    (f) => f.manifest.parts.push(f.manifest.parts[0]),
    (f) => (f.manifest.totals.operations = 2),
    (f) => (f.manifest.parts[0].bytes = 33 * 1024 * 1024),
    (f) => (f.manifest.source.sha256 = "not a digest"),
    (f) => (f.manifest.source.sha256 = "f".repeat(64)),
    (f) => (f.manifest.parts[4].encoding = "invented"),
    (f) => {
      const key = "https://example.test/data/render/operations.json",
        b = Buffer.from(f.files.get(key));
      b[8] = 120;
      f.files.set(key, b);
    },
  ]) {
    const f = fixture();
    mutate(f);
    await assert.rejects(loadPreparedRender(f.options()));
  }
});
