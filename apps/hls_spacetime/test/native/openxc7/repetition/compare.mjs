/** Compare the same step-4 write IDs, masks and cycles in two independently hashed render publications. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const digest = (data) => createHash("sha256").update(data).digest("hex");
const count = (map, key) => (map[key] = (map[key] ?? 0) + 1);

/** Read the published, uncompressed artifact only when its descriptor matches exactly. */
async function verified(root, ref) {
  const raw = await readFile(join(root, ref.file));
  assert.equal(raw.length, ref.bytes);
  assert.equal(digest(raw), ref.sha256);
  return JSON.parse(raw);
}

/** Count distinct branches separately from write-cone occurrences and retain every disposition. */
async function ledger(root) {
  const idx = JSON.parse(await readFile(join(root, "index.json")));
  const entry = idx.examples.find((e) => e.render);
  const view = await verified(root, entry),
    render = await verified(root, entry.render);
  assert.equal(render.view.sha256, entry.sha256);
  assert.equal(render.source.sha256, entry.computations.sha256);
  const tables = {};
  for (const name of [
    "writes",
    "cones",
    "routes",
    "pinGeometry",
    "arcGeometry",
  ]) {
    tables[name] = [];
    for (const part of render.parts.filter((p) => p.table === name)) {
      const rows = await verified(join(root, dirname(entry.render.file)), part);
      assert.equal(rows.length, part.rows);
      tables[name] = tables[name].concat(rows);
    }
    assert.equal(tables[name].length, render.totals[name]);
  }
  const events = new Map(view.bundle.events.map((e) => [e.id, e])),
    writes = [],
    resources = new Set();
  const roles = { data: {}, enable: {}, reset: {} },
    mapping = { zero: 0, partial: 0, full: 0 };
  const active = new Set(),
    uniqueBits = new Map(),
    boundBits = new Set();
  const bindings = new Map(view.catalogue.bindings.map((b) => [b.resource, b]));
  let requested = 0,
    mapped = 0;
  for (const w of tables.writes) {
    const e = events.get(w.event);
    if (e.cycle <= 1774 || e.cycle > 1873) continue;
    const { requestedBits: r, mappedBits: m } = w.coverage,
      a = e.access;
    writes.push([e.id, e.cycle, a.resource, a.address, a.mask]);
    resources.add(a.resource);
    requested += r;
    mapped += m;
    count(mapping, m === 0 ? "zero" : m === r ? "full" : "partial");
    const mask = BigInt(a.mask);
    uniqueBits.set(a.resource, (uniqueBits.get(a.resource) ?? 0n) | mask);
    for (const b of bindings.get(a.resource)?.bits ?? [])
      if (b.status === "supported" && mask & (1n << BigInt(b.bit)))
        boundBits.add(a.resource + "/" + b.bit);
    const present = new Set();
    for (const i of w.cones) {
      active.add(i);
      const c = tables.cones[i];
      present.add(c.role);
      count(roles[c.role], c.registeredTiming.status);
    }
    for (const role of Object.keys(roles))
      if (!present.has(role)) count(roles[role], "no_mapped_pin");
  }
  const branches = new Set(),
    arcs = new Set(),
    dispositions = {},
    timing = {};
  for (const i of active) {
    for (const r of tables.cones[i].routes) branches.add(r);
    for (const a of tables.cones[i].arcIndices) arcs.add(a);
  }
  for (const r of branches) {
    const row = tables.routes[r];
    count(
      dispositions,
      row.requested === false ? "not_requested" : row.disposition,
    );
  }
  for (const i of arcs) {
    const [, , kind, delay] = tables.arcGeometry[i];
    count(
      timing,
      (kind === 0 ? "net" : "logic") + (delay === null ? "_missing" : "_known"),
    );
  }
  let intervalGeometry;
  if (entry.geometry) {
    const m = await verified(root, entry.geometry);
    assert.equal(m.render, entry.render.sha256);
    assert.equal(m.view, entry.sha256);
    assert.equal(m.checkpoint, view.catalogue.checkpoint);
    assert.equal(m.source, entry.computations.sha256);
    assert.deepEqual(
      [m.selection.firstCycle, m.selection.endCycle, m.branches, m.writes],
      [1775, 1874, branches.size, writes.length],
    );
    intervalGeometry = {
      sha256: entry.geometry.sha256,
      counts: m.counts,
      unavailableByNet: m.unavailableByNet,
    };
  }
  const selected = tables.writes.find((w) => w.event === "e/25066");
  const details = selected.cones.map((i) => {
    const c = tables.cones[i];
    return {
      role: c.role,
      roots: c.rootPins.length,
      registeredNs: c.registeredDelayNs,
      registeredStatus: c.registeredTiming.status,
      reasons: c.registeredTiming.reasons,
      missing: c.coverage.missingTiming,
      frontiers: c.coverage.unsupportedFrontiers,
    };
  });
  const distinct = [...uniqueBits.values()].reduce(
    (n, m) => n + m.toString(2).replaceAll("0", "").length,
    0,
  );
  return {
    writes,
    summary: {
      recording: entry.sha256,
      prepared: entry.render.sha256,
      build: view.bundle.build,
      checkpoint: view.catalogue.checkpoint,
      window: "1774 < cycle <= 1873",
      writes: writes.length,
      resources: resources.size,
      requested,
      mapped,
      distinctRequested: distinct,
      distinctBound: boundBits.size,
      mapping,
      registeredConeOccurrences: roles,
      uniqueCones: active.size,
      uniqueBranches: branches.size,
      dispositions,
      intervalGeometry,
      uniqueArcDelays: timing,
      sourceCounts: render.render.sourceCounts,
      selected: {
        event: selected.event,
        coverage: selected.coverage,
        cones: details,
      },
      sta: (view.nativePaths?.paths ?? [])
        .map((p) => ({
          source: p.source,
          endpoint: p.endpoint,
          slackNs: p.slackNs,
          dataDelayNs: p.dataDelayNs,
          logicDelayNs: p.logicDelayNs,
          routeDelayNs: p.routeDelayNs,
          setupNs: p.setupNs,
          requiredNs: p.requiredNs,
          netArcs: p.arcs.filter((a) => a.kind === "net").length,
        }))
        .slice(0, 1),
    },
  };
}
const runs = [];
for (const directory of process.argv.slice(2))
  runs.push(await ledger(directory));
assert.ok(runs.length >= 2);
for (const run of runs.slice(1)) assert.deepEqual(run.writes, runs[0].writes);
console.log(
  JSON.stringify(
    {
      matchedWritesSha256: digest(JSON.stringify(runs[0].writes)),
      runs: runs.map((r) => r.summary),
    },
    null,
    2,
  ),
);
