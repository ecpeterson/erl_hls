/** Select exact net names on the longest qualified step-4 correction path of a frozen render. */
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import assert from "node:assert/strict";
import { loadComputations } from "../../../../web/computation-loader.js";
import { loadPreparedRender } from "../../../../web/prepared-loader.js";
import {
  createNativeRouting,
  nativeConnection,
  nativeRoutes,
} from "../../../../web/native-routes.js";
import { createModel } from "../../../../web/model.js";
import { createHash } from "node:crypto";
import { sinkPath } from "../../../../web/sink-paths.js";

const root = resolve(process.argv[2]);
const entry = JSON.parse(await readFile(join(root, "index.json"))).examples[0];
const options = {
  baseUrl: pathToFileURL(root + "/").href,
  view: entry,
  fetcher: async (url) => new Response(await readFile(fileURLToPath(url))),
};
const prepared = await loadPreparedRender({
  ...options,
  entry: entry.render,
  source: entry.computations,
});
const { attachment, routeNets } = await loadComputations({
  ...options,
  entry: entry.computations,
});
const w = prepared.writes.find((w) => w.event === "e/25066");
const c = w.cones.map((i) => prepared.cones[i]).find((c) => c.role === "data");
const positions = new Map(c.pinIndices.map((p, i) => [p, i]));
const known = c.rootPins
  .map((pin) => ({ pin, ns: c.pinArrivals.registered[positions.get(pin)] }))
  .filter((p) => Number.isFinite(p.ns));
known.sort((a, b) => b.ns - a.ns || a.pin - b.pin);
assert.ok(known.length);
const chosen = sinkPath(prepared, c, known[0].pin);
const binding = attachment.bindings.find(
  (b) => b.resource === "register/____state_154",
);
const nets = [],
  branches = [];
for (const i of chosen.arcIndices) {
  const a = attachment.arcs[i];
  if (a.kind !== "net") continue;
  const net = attachment.nets[a.net].id;
  nets.push(net);
  branches.push({
    net,
    from: attachment.pins[a.from].id,
    to: attachment.pins[a.to].id,
  });
}
const raw = await readFile(join(root, entry.file));
assert.equal(createHash("sha256").update(raw).digest("hex"), entry.sha256);
const model = createModel(JSON.parse(raw));
const graph = createNativeRouting(routeNets);
const statuses = (rows) =>
  rows.reduce((counts, { disposition }) => {
    counts[disposition] = (counts[disposition] ?? 0) + 1;
    return counts;
  }, {});
const geometry = branches.map(({ net, from, to }) =>
  nativeConnection(graph, net, from, to),
);
const staticBranches = nativeRoutes(model);
// Stop at the first formerly unsupported primitive on each fan-in branch.
// Counts overlap when several branches of one destination meet different cuts.
const incoming = Array.from({ length: attachment.pins.length }, () => []);
for (const a of attachment.arcs) incoming[a.to].push(a.from);
const memo = new Map();
const categories = ["CARRY4", "SELMUX2_1", "external_input", "unqualified_lut"];
function previousCuts(pin) {
  if (memo.has(pin)) return memo.get(pin);
  const p = attachment.pins[pin],
    cell = attachment.cells[p.cell];
  let flags = 0;
  if (p.direction === "OUT" && p.timingClass !== "register_output") {
    let kind = cell.kind;
    if (cell.boundary === "external") kind = "external_input";
    if (kind === "SLICE_LUTX" && !incoming[pin].length)
      kind = "unqualified_lut";
    const cat = categories.indexOf(kind);
    if (cat >= 0) flags = 1 << cat;
  }
  if (!flags) for (const source of incoming[pin]) flags |= previousCuts(source);
  memo.set(pin, flags);
  return flags;
}
const previousBoundaryBits = {},
  localControls = {};
for (const word of attachment.bindings)
  for (const b of word.bits) {
    if (b.status !== "supported") continue;
    for (const k of Object.keys(b.localControls ?? {}))
      localControls[k] = (localControls[k] ?? 0) + 1;
    for (const role of ["d", "ce", "reset"]) {
      if (!Number.isInteger(b[role])) continue;
      const flags = previousCuts(b[role]);
      const counts = (previousBoundaryBits[role] ??= Object.fromEntries(
        categories.map((c) => [c, 0]),
      ));
      categories.forEach((c, i) => {
        if (flags & (1 << i)) counts[c]++;
      });
    }
  }
console.log(
  JSON.stringify(
    {
      checkpoint: prepared.checkpoint,
      render: entry.render.sha256,
      event: w.event,
      resource: binding.resource,
      bit: binding.bits.find((b) => b.d === chosen.targetPin).bit,
      registeredNs: chosen.delayNs,
      sink: attachment.pins[chosen.targetPin].id,
      eligible: known.length,
      total: c.rootPins.length,
      previousBoundaryBits,
      localControls,
      capturedNets: graph.nets.size,
      supplied: nets.filter((n) => graph.nets.has(n)).length,
      branchDispositions: statuses(geometry),
      staDispositions: statuses(staticBranches),
      nets: [...new Set(nets)],
      branches,
    },
    null,
    2,
  ),
);
