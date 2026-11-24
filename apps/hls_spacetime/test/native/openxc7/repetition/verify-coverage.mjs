/** Cross-check the published N2 regional map, ranked paths and logical sidecars
 * against their independent native and producer populations. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createModel } from "../../../../web/model.js";
import {
  createRegionalData,
  loadRegionalData,
} from "../../../../web/regional-data.js";
import { nativeRoutes } from "../../../../web/native-routes.js";
import { validateLatencyProfile } from "../../../../web/recorded-scenario.js";

const [published, capture] = process.argv.slice(2),
  baseUrl = pathToFileURL(resolve(published) + "/").href;
/** Check exact bytes before borrowing event, net or region identities. */
async function verified(root, ref) {
  const bytes = await readFile(join(root, ref.file));
  assert.equal(bytes.length, ref.bytes);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), ref.sha256);
  return JSON.parse(bytes);
}
const [entry] = JSON.parse(
  await readFile(join(published, "index.json")),
).examples;
const view = await verified(published, entry),
  model = createModel(view);
const source = entry.computations;
const map = createRegionalData(
  model,
  await loadRegionalData({
    entry: entry.regions,
    view: entry,
    source,
    baseUrl,
    fetcher: async (url) => new Response(await readFile(fileURLToPath(url))),
  }),
);
const ids = new Map(map.nets.map((n, i) => [n.id, i]));
// Reconcile every source row exactly once against its numeric switch and owning net.
const fixed = await readFile(join(capture, "fixed-routes.txt"), "utf8");
const expected = new Set(fixed.trimEnd().split("\n").slice(1));
const fixedCount = expected.size;
for (const pip of map.pips)
  for (const owner of pip.nets)
    assert.ok(expected.delete(map.nets[owner].id + " " + pip.id));
assert.equal(expected.size, 0);
assert.equal(fixedCount, map.sourceCounts.pipMemberships);
for (const route of view.openxc7Routes.nets) {
  const net = map.nets[ids.get(route.id)],
    counts = new Map();
  for (const node of route.nodes)
    for (const wire of node.wires) {
      const key = [
        Math.floor(wire.x / map.binSize),
        Math.floor(wire.y / map.binSize),
      ].join("/");
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  assert.deepEqual(
    counts,
    new Map(
      net.wireBins.map(({ bin, count }) => [
        [map.bins[bin].x, map.bins[bin].y].join("/"),
        count,
      ]),
    ),
  );
}
const profile = await verified(published, entry.latencyProfile);
validateLatencyProfile(model, profile, entry);
const operations = {};
for (const e of view.bundle.events)
  operations[e.operation] = (operations[e.operation] ?? 0) + 1;
assert.equal(operations.selected_operand_read, 19228);
assert.equal(operations.selected_operand_value, 19228);
assert.equal(operations.register_compute, 6929);
assert.equal(view.annotations.boundaries.length, 10);
const ranking = view.nativePaths.ranking;
assert.equal(ranking.retained, 50);
assert.equal(view.nativePaths.paths.length, 50);
assert.equal(view.nativePaths.paths[0].slackNs, -48.723);
const dispositions = {};
for (const branch of nativeRoutes(model))
  dispositions[branch.disposition] =
    (dispositions[branch.disposition] ?? 0) + 1;
assert.equal(
  dispositions.resolved,
  view.nativePaths.paths.reduce(
    (n, p) => n + p.arcs.filter((a) => a.kind === "net").length,
    0,
  ),
);
console.log(
  JSON.stringify(
    {
      checkpoint: view.catalogue.checkpoint,
      events: view.bundle.events.length,
      operations,
      versions: view.bundle.versions.length,
      boundaries: view.annotations.boundaries.length,
      profile: {
        groups: profile.groups.length,
        edges: profile.edges.length,
        choices: profile.choices.length,
      },
      ranking,
      lastSlackNs: view.nativePaths.paths.at(-1).slackNs,
      staGeometry: dispositions,
      regional: map.summary,
      selectedNetWireHistograms: view.openxc7Routes.nets.length,
    },
    null,
    2,
  ),
);
