import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";
import { prepareRender, parseArguments } from "../scripts/prepare-render.mjs";
import { loadPreparedRender } from "../web/prepared-loader.js";
import {
  createPreparedComputations,
  preparedComputationLayers,
} from "../web/prepared-computations.js";
import { createModel } from "../web/model.js";

/** A single real-shaped FF write exercises file publication and loader closure. */
async function sourceFixture(t) {
  const root = await mkdtemp(join(tmpdir(), "spacetime-render-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const input = join(root, "source"),
    output = join(root, "prepared");
  await mkdir(join(input, "computations"), { recursive: true });
  const save = async (file, value) => {
    const b = Buffer.from(JSON.stringify(value));
    await writeFile(join(input, file), b);
    return {
      file,
      bytes: b.length,
      sha256: createHash("sha256").update(b).digest("hex"),
    };
  };
  const build = {
      source: "a".repeat(64),
      rtl: "b".repeat(64),
      observation: "c".repeat(64),
    },
    checkpoint = "d".repeat(64);
  const event = {
    id: "w",
    cycle: 0,
    sequence: 0,
    observer: "o",
    incarnation: "i",
    actor: "a",
    operation: "register_write",
    inputs: ["root"],
    outputs: ["value"],
    access: {
      resource: "word",
      kind: "write",
      before: "root",
      after_version: "value",
      mask: "0x1",
    },
  };
  const cells = [{ id: "ff", kind: "FDRE", boundary: "sequential" }],
    bindings = [
      { resource: "word", bits: [{ bit: 0, status: "supported", q: 0, d: 1 }] },
    ];
  const view = {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        complete: true,
        first_cycle: 0,
        end_cycle: 2,
        observers: [{ id: "o", gaps: [] }],
        incarnations: [{ id: "i", first_cycle: 0, end_cycle: 2 }],
      },
      resources: [{ id: "word", kind: "ff", width: 1, depth: 1 }],
      events: [event],
      relations: [],
      versions: [
        {
          id: "root",
          producer: "root",
          origin: "unknown",
          incarnation: "i",
          storage: { resource: "word", address: 0 },
        },
        {
          id: "value",
          producer: "w",
          origin: "event",
          incarnation: "i",
          storage: { resource: "word", address: 0 },
        },
      ],
    },
    catalogue: {
      build,
      checkpoint,
      cells: [{ ...cells[0], x: 10, y: 20 }],
      bindings: [{ resource: "word", bits: [] }],
    },
  };
  const recording = await save("recording.json", view);
  const tables = {
    cells,
    pins: [
      { id: "ff/Q", cell: 0, pin: "Q", direction: "OUT", net: 0 },
      { id: "ff/D", cell: 0, pin: "D", direction: "IN", net: 0 },
    ],
    nets: [{ id: "feedback" }],
    arcs: [
      {
        id: "a",
        kind: "net",
        from: 0,
        to: 1,
        net: 0,
        timing: { fast: [{ maxPs: 10 }], slow: [{ maxPs: 20 }] },
      },
    ],
    bindings,
    operations: [
      {
        event: "w",
        applicability: "storage_write",
        status: "located",
        targets: [{ resource: "word", mask: "0x1" }],
        sources: [],
        unknowns: [],
        writes: [],
      },
    ],
    routeNets: [
      {
        id: "feedback",
        status: "complete",
        route_status: "ROUTED",
        nodes: [],
        pips: [],
        issues: [],
        pin_attachments: [],
      },
    ],
  };
  const parts = [];
  for (const [table, rows] of Object.entries(tables)) {
    const p = await save(`computations/${table}.json`, rows);
    parts.push({ ...p, file: `${table}.json`, table, rows: rows.length });
  }
  const computations = await save("computations/manifest.json", {
    format: "spacetime-computations-manifest",
    schema: 1,
    view: { bytes: recording.bytes, sha256: recording.sha256 },
    build,
    checkpoint,
    parts,
    totals: Object.fromEntries(
      Object.entries(tables).map(([k, v]) => [k, v.length]),
    ),
    attachment: {
      schema: 1,
      scope: "structural_native_connectivity",
      build,
      nativeBuild: build,
      checkpoint,
      routingComplete: true,
    },
  });
  await save("index.json", {
    format: "spacetime-view-index",
    schema: 1,
    examples: [{ ...recording, title: "Synthetic", computations }],
  });
  return { input, output, view, recording, computations };
}

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
  assert.deepEqual(
    gunzipSync(await readFile(join(f.output, "recording.json.gz"))),
    await readFile(join(f.output, "recording.json")),
  );
  const renderManifest = JSON.parse(
    await readFile(join(f.output, entry.render.file)),
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
