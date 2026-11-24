import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadComputations, publicationUrl } from "../web/computation-loader.js";

const tables = [
  "cells",
  "pins",
  "nets",
  "arcs",
  "bindings",
  "operations",
  "routeNets",
];
function fixture() {
  const files = new Map();
  function save(path, value) {
    const bytes = Buffer.from(JSON.stringify(value));
    files.set(`https://example.test/data/${path}`, bytes);
    return {
      file: path,
      bytes: bytes.length,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    };
  }
  const view = { bytes: 200, sha256: "a".repeat(64) };
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" };
  const parts = tables.map((table) => ({
    ...save(`computations/${table}.json`, [{ id: table }]),
    file: `${table}.json`,
    table,
    rows: 1,
  }));
  const manifest = {
    format: "spacetime-computations-manifest",
    schema: 1,
    view,
    build,
    checkpoint: "dcp",
    attachment: {
      schema: 1,
      build,
      checkpoint: "dcp",
      scope: "structural_native_connectivity",
    },
    parts,
    totals: Object.fromEntries(tables.map((table) => [table, 1])),
  };
  const publish = () => save("computations/manifest.json", manifest);
  const fetcher = async (url) =>
    new Response(files.get(url), { status: files.has(url) ? 200 : 404 });
  const load = (entry = publish()) =>
    loadComputations({
      entry,
      view,
      baseUrl: "https://example.test/data/",
      fetcher,
    });
  return { files, view, manifest, publish, load };
}

test("loads every shared table after checking recording and part hashes", async () => {
  const f = fixture();
  const result = await f.load();
  assert.equal(result.attachment.operations[0].id, "operations");
  assert.equal(result.routeNets[0].id, "routeNets");
  assert.equal(result.attachment.routeNets, undefined);
});

test("rejects mismatched recording and truncated or changed parts", async () => {
  const f = fixture();
  f.manifest.view = { ...f.view, bytes: 201 };
  await assert.rejects(f.load(), /bind this recording/);
  f.manifest.view = f.view;
  const key = "https://example.test/data/arcs.json";
  const actual = "https://example.test/data/computations/arcs.json";
  f.files.set(key, Buffer.from("[]"));
  f.files.set(actual, Buffer.from("[]"));
  await assert.rejects(f.load(), /length mismatch/);
  const g = fixture();
  const bytes = Buffer.from(g.files.get(actual));
  bytes[8] = 120;
  g.files.set(actual, bytes);
  await assert.rejects(g.load(), /digest mismatch/);
});

test("rejects escaped paths, duplicate shards, missing rows and unknown tables", async () => {
  for (const mutate of [
    (m) => {
      m.parts[0].file = "../cells.json";
    },
    (m) => {
      m.parts.push(m.parts[0]);
    },
    (m) => {
      m.totals.cells = 2;
    },
    (m) => {
      m.parts[0].table = "other";
    },
    (m) => {
      m.parts[0].bytes = 33 * 1024 * 1024;
    },
  ]) {
    const f = fixture();
    mutate(f.manifest);
    await assert.rejects(f.load());
  }
  const f = fixture();
  const entry = f.publish();
  entry.file = "https://other.test/manifest.json";
  await assert.rejects(f.load(entry), /Unsafe/);
});

test("an unattached recording stays usable", async () => {
  assert.equal(await loadComputations({ entry: null }), null);
});

test("capture and computation publications accept normalized subdirectories without URL escape", () => {
  const base = "http://127.0.0.1:4177/data/";
  for (const file of [
    "recording.json",
    "baseline/recording.json",
    "candidate/render/manifest.json",
    "run_1/part-0001.json",
  ]) {
    assert.equal(publicationUrl(file, base), base + file);
  }
  for (const file of [
    undefined,
    null,
    "",
    "/recording.json",
    "//other.test/recording.json",
    "../recording.json",
    "base/../recording.json",
    "./recording.json",
    "base/./recording.json",
    "base//recording.json",
    "base\\recording.json",
    "https://other.test/recording.json",
    "file:///recording.json",
    "C:/recording.json",
    "base/%2e%2e/recording.json",
    "recording.json?other",
    "recording.json#fragment",
    "base/",
    "base /recording.json",
  ]) {
    assert.throws(() => publicationUrl(file, base), /Unsafe publication path/);
  }
});
