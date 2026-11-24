import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { openIntervalGeometry } from "../web/interval-geometry.js";

/** Two branches share a fixed PIP and one disconnected tie has no drawable geometry. */
function fixture(edit = () => {}) {
  const rows = {
    branches: [
      [0, 0, 1, "lut_permutation", 1, [7], "SITEWIRE/SLICE_X0Y0/A1", null],
      [2, 0, 2, "direct", 1, [7], null, null],
      [3, 3, 4, "disconnected_constant", null, [], null, "INT_L_X0Y0/GND_WIRE"],
    ],
    nodes: [
      [1, "tile/driver", [[1, "tile/0"]]],
      [2, "SITEWIRE/SLICE_X0Y0/A2", [[2, "CLB/2"]]],
    ],
    pips: [[7, 1, 2, 2, "CLB/1.2", "tile/driver->SITEWIRE/SLICE_X0Y0/A2"]],
  };
  edit(rows);
  const files = new Map(),
    reads = [];
  function store(file, obj) {
    const body = JSON.stringify(obj);
    files.set(file, body);
    return {
      file,
      bytes: Buffer.byteLength(body),
      sha256: createHash("sha256").update(body).digest("hex"),
    };
  }
  const parts = Object.fromEntries(
    Object.entries(rows).map(([k, data]) => [
      k,
      [
        {
          ...store(k + ".json", data),
          first: data[0][0],
          last: data.at(-1)[0],
          rows: data.length,
        },
      ],
    ]),
  );
  const selection = { firstCycle: 1, endCycle: 3 },
    build = { implementation: "i" };
  const manifest = {
    format: "spacetime-openxc7-geometry",
    schema: 1,
    parts,
    selection,
    build,
    checkpoint: "c",
    view: "v",
    source: "s",
    render: "r",
    width: 5,
    tiles: 10,
    counts: { direct: 1, lut_permutation: 1, disconnected_constant: 1 },
    branches: 3,
  };
  const options = {
    entry: {
      geometry: store("manifest.json", manifest),
      sha256: "v",
      computations: { sha256: "s" },
      render: { sha256: "r" },
    },
    model: {
      catalogue: { checkpoint: "c" },
      bundle: { build },
      document: { selection },
    },
    baseUrl: "https://geometry.test/",
    fetcher: async (url) => {
      const name = new URL(url).pathname.slice(1);
      reads.push(name);
      return new Response(files.get(name));
    },
  };
  const index = {
    arcGeometry: [
      [0, 1, 0, 4],
      [0, 1, 0, 4],
      [0, 2, 0, 4],
      [3, 4, 0, 1],
    ],
    pinGeometry: Array.from({ length: 5 }, (_, i) => [i, i, 0, "p" + i]),
  };
  return { options, index, files, reads };
}

test("inventory loads alone, shared pages load once and missing arcs remain absent", async () => {
  const { options, index, reads } = fixture();
  const g = await openIntervalGeometry(options);
  assert.deepEqual(reads, ["manifest.json"]);
  const rows = await g.load([0, 1, 2, 3], index);
  assert.deepEqual([...rows.keys()], [0, 2, 3]);
  assert.equal(rows.get(0).segments.length, 2);
  assert.equal(rows.get(0).physical, "SITEWIRE/SLICE_X0Y0/A1");
  assert.strictEqual(rows.get(0).switches[0], rows.get(2).switches[0]);
  assert.deepEqual(rows.get(3).segments, []);
  assert.equal(rows.get(3).localTie, "INT_L_X0Y0/GND_WIRE");
  await g.load([2], index);
  assert.deepEqual(reads, [
    "manifest.json",
    "branches.json",
    "pips.json",
    "nodes.json",
  ]);
});

test("reject stale publications, corrupted parts, discontinuities and mismatched pin IDs", async () => {
  const f = fixture();
  await assert.rejects(
    openIntervalGeometry({
      ...f.options,
      entry: { ...f.options.entry, sha256: "wrong" },
    }),
    /mismatch/,
  );
  const g = await openIntervalGeometry(f.options);
  f.files.set(
    "nodes.json",
    f.files.get("nodes.json").replace("driver", "drives"),
  );
  await assert.rejects(g.load([0], f.index), /digest/);
  for (const [alter, pattern] of [
    [
      (r) => {
        r.pips[0][1] = 2;
      },
      /disconnected/,
    ],
    [
      (r) => {
        r.branches[0][1] = 1;
      },
      /endpoint/,
    ],
  ]) {
    const { options, index } = fixture(alter);
    await assert.rejects(
      (await openIntervalGeometry(options)).load([0], index),
      pattern,
    );
  }
  await assert.rejects(g.load([0], f.index, AbortSignal.abort()), {
    name: "AbortError",
  });
});
