/** Exhaustively check the frozen interval and compare overlapping routes to the independent selected-net export. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import {
  createNativeRouting,
  nativeConnection,
} from "../../../../web/native-routes.js";

const [base, capture] = process.argv.slice(2);
const entry = JSON.parse(await readFile(join(base, "index.json"))).examples[0];
async function verified(dir, ref) {
  const bytes = await readFile(join(dir, ref.file));
  assert.equal(bytes.length, ref.bytes);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), ref.sha256);
  return JSON.parse(bytes);
}
const m = await verified(base, entry.geometry),
  view = await verified(base, entry),
  g = await verified(base, entry.computations);
const nativeManifest = await verified(capture, {
  file: "manifest.json",
  bytes: (await readFile(join(capture, "manifest.json"))).length,
  sha256: g.build.implementation,
});
const { cells } = await verified(capture, {
  ...nativeManifest.files["timing.json"],
  file: "timing.json",
});
assert.equal(m.checkpoint, nativeManifest.files["routed.json"].sha256);
assert.equal(m.render, entry.render.sha256);
assert.equal(m.view, entry.sha256);
assert.equal(m.source, entry.computations.sha256);
async function table(parts, dir) {
  const rows = [];
  for (const p of parts) {
    const data = await verified(dir, p);
    assert.equal(data.length, p.rows);
    for (const row of data) rows.push(row);
  }
  return rows;
}
const loadTable = (name) =>
  table(
    g.parts.filter((p) => p.table === name),
    join(base, dirname(entry.computations.file)),
  );
const arcs = await loadTable("arcs"),
  pins = await loadTable("pins"),
  nets = await loadTable("nets");
const render = await verified(base, entry.render),
  renderDir = join(base, dirname(entry.render.file));
const events = new Set(
  view.bundle.events
    .filter(
      (e) =>
        e.cycle >= m.selection.firstCycle &&
        e.cycle < m.selection.endCycle &&
        e.access?.kind === "write",
    )
    .map((e) => e.id),
);
const writes = (
  await table(
    render.parts.filter((p) => p.table === "writes"),
    renderDir,
  )
).filter((w) => events.has(w.event));
const cones = await table(
  render.parts.filter((p) => p.table === "cones"),
  renderDir,
);
const required = new Set();
for (const i of new Set(writes.flatMap((w) => w.cones)))
  for (const arc of cones[i].arcIndices)
    if (arcs[arc].kind === "net") required.add(arc);
const geometryDir = join(base, dirname(entry.geometry.file));
const nodes = await table(m.parts.nodes, geometryDir),
  pips = await table(m.parts.pips, geometryDir);
const branches = await table(m.parts.branches, geometryDir);
const selected = createNativeRouting(view.openxc7Routes.nets);
const port = (name) => {
  const i = name.lastIndexOf("/");
  return cells[name.slice(0, i)].ports[name.slice(i + 1)];
};
let overlapping = 0;
const counts = {},
  ties = new Set(),
  usedPips = new Set(),
  usedNodes = new Set();
for (const [arc, from, to, status, start, edges, physical, cut] of branches) {
  assert.ok(required.delete(arc));
  const a = arcs[arc],
    net = nets[a.net].id,
    src = pins[from].id,
    dst = pins[to].id;
  assert.deepEqual([a.from, a.to, a.kind], [from, to, "net"]);
  const s = port(src),
    d = port(dst);
  assert.deepEqual(
    [s.net, d.net, s.direction, d.direction],
    [net, net, "OUT", "IN"],
  );
  counts[status] = (counts[status] ?? 0) + 1;
  if (status === "disconnected_constant") {
    assert.deepEqual(edges, []);
    assert.equal(start, null);
    assert.ok(
      ["GND", "VCC"].some(
        (k) => src === `$PACKER_${k}_DRV/Y` && cut.endsWith(`/${k}_WIRE`),
      ),
    );
    ties.add(cut);
    continue;
  }
  assert.equal(cut, null);
  assert.equal(nodes[start][1], s.wire);
  let end = start;
  const ordered = [start];
  for (const id of edges) {
    const [key, from, to] = pips[id];
    assert.equal(id, key);
    assert.equal(from, end);
    usedPips.add(id);
    end = to;
    ordered.push(end);
  }
  for (const i of ordered) {
    assert.equal(nodes[i][0], i);
    usedNodes.add(i);
  }
  if (status === "direct") assert.equal(nodes[end][1], d.wire);
  else {
    assert.equal(status, "lut_permutation");
    assert.equal(physical, d.wire);
    assert.ok(edges.length);
    assert.equal(nodes[end][1].slice(0, -1), physical.slice(0, -1));
  }
  if (selected.nets.has(net)) {
    const r = nativeConnection(selected, net, src, dst);
    assert.equal(r.disposition, "resolved");
    assert.deepEqual(
      r.pips.map((p) => [p.native_switch, p.id]),
      edges.map((id) => pips[id].slice(4)),
    );
    assert.deepEqual(
      r.nodes.map((n) => [n.id, n.wires.map((w) => w.id)]),
      ordered.map((i) => [nodes[i][1], nodes[i][2].map((w) => w[1])]),
    );
    overlapping++;
  }
}
assert.equal(required.size, 0);
assert.equal(usedNodes.size, nodes.length);
assert.equal(usedPips.size, pips.length);
assert.deepEqual(counts, m.counts);
assert.deepEqual(
  [writes.length, branches.length, overlapping],
  [468, 109591, 988],
);
console.log(
  JSON.stringify({
    counts,
    overlapping,
    localTies: ties.size,
    nodes: nodes.length,
    pips: pips.length,
    branches: branches.length,
    writes: writes.length,
  }),
);
