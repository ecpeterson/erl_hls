import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile, stat, symlink } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { reportTiming, parseArguments } from "../scripts/report-timing.mjs";
import { sourceFixture } from "./fixtures/computation-publication.js";

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const read = async (path) => JSON.parse(await readFile(path));

/** Fixture mutations must rebind both levels, exactly as a fresh publication
 * would. This deliberately does not bypass the report's hash checks. */
async function replacePart(f, table, mutate) {
  const manifestPath = join(f.input, "computations/manifest.json");
  const m = await read(manifestPath),
    part = m.parts.find((p) => p.table === table),
    p = join(f.input, "computations", part.file);
  const value = await read(p);
  mutate(value);
  const b = Buffer.from(JSON.stringify(value));
  await writeFile(p, b);
  Object.assign(part, { bytes: b.length, sha256: hash(b), rows: value.length });
  m.totals[table] = value.length;
  const mb = Buffer.from(JSON.stringify(m));
  await writeFile(manifestPath, mb);
  const ip = join(f.input, "index.json"),
    i = await read(ip);
  Object.assign(i.examples[0].computations, {
    bytes: mb.length,
    sha256: hash(mb),
  });
  await writeFile(ip, JSON.stringify(i));
}

test("saved reconvergent graph produces complete ordered chain and verified output manifest", async (t) => {
  const f = await sourceFixture(t, true);
  const before = await readFile(join(f.input, "recording.json"));
  const result = await reportTiming(f),
    r = await read(join(f.output, "report.json"));
  assert.equal(result.writes, 1);
  assert.equal(r.summary.maximumKnownPathNs, 8);
  const c = r.cones[0];
  assert.deepEqual(
    c.path.map((a) => a.id),
    ["long-in", "long-logic", "shared-out"],
  );
  assert.deepEqual(
    c.path.map((a) => a.arrivalToNs),
    [3, 7, 8],
  );
  assert.equal(c.netDelayNs, 4);
  assert.equal(c.logicDelayNs, 4);
  assert.equal(c.occurrences.writes, 1);
  assert.equal(c.path[0].nativeNetSinkPins, 1);
  assert.equal(c.path[0].route.disposition, "unavailable");
  assert.equal(c.status, "known"); // Missing route geometry does not erase SDF timing.
  assert.deepEqual(c.path[1].timing.slow, [{ maxPs: 4000 }]);
  assert.deepEqual(r.writes[0].cones, [c.id]);
  const m = await read(join(f.output, "manifest.json"));
  for (const part of m.files) {
    const b = await readFile(join(f.output, part.file));
    assert.equal(b.length, part.bytes);
    assert.equal(hash(b), part.sha256);
  }
  assert.deepEqual(await readFile(join(f.input, "recording.json")), before);
  assert.match(
    await readFile(join(f.output, "report.md"), "utf8"),
    /not STA slack/,
  );
  await assert.rejects(reportTiming(f), /EEXIST/);
});

test("unknown competing timing is retained rather than ranking only a finite alternative", async (t) => {
  const f = await sourceFixture(t, true);
  await replacePart(f, "arcs", (rows) => {
    rows[0].timing.fast = [];
  });
  await reportTiming(f);
  const r = await read(join(f.output, "report.json"));
  assert.equal(r.summary.maximumKnownPathNs, null);
  assert.equal(r.cones[0].status, "unknown");
  assert.deepEqual(r.cones[0].path, []);
  assert.equal(r.writes.length, 1);
});

test("unknown binding remains an explicit write without a cone", async (t) => {
  const f = await sourceFixture(t);
  await replacePart(f, "bindings", (rows) => {
    rows[0].bits = [{ bit: 0, status: "unknown" }];
  });
  await reportTiming(f);
  const r = await read(join(f.output, "report.json"));
  assert.equal(r.summary.writesWithoutNativeCones, 1);
  assert.equal(r.summary.writesWithUnknownTargetBits, 1);
  assert.equal(r.summary.unknownBitOccurrences, 1);
  assert.equal(r.summary.sharedCones, 0);
});

test("event/window filters are explicit, empty windows of writes still report and invalid selectors reject", async (t) => {
  const f = await sourceFixture(t);
  await reportTiming({ ...f, event: "w", firstCycle: 1, endCycle: 2 });
  const r = await read(join(f.output, "report.json"));
  assert.equal(r.summary.writes, 0);
  assert.equal(r.summary.maximumKnownPathNs, null);
  await assert.rejects(
    reportTiming({ ...f, event: "absent" }),
    /unknown selected event/,
  );
  await assert.rejects(
    reportTiming({ ...f, firstCycle: 2, endCycle: 1 }),
    /cycle window/,
  );
});

test("corrupt source is rejected before creating any output", async (t) => {
  const f = await sourceFixture(t);
  await writeFile(join(f.input, "computations/arcs.json"), "[]");
  await assert.rejects(reportTiming(f), /length mismatch|digest mismatch/);
  await assert.rejects(stat(f.output), /ENOENT/);
});

test("options follow last-wins precedence and retain exact cycle bounds", () => {
  assert.deepEqual(
    parseArguments([
      "--scope",
      "static",
      "--scope",
      "registered",
      "--first-cycle",
      "3",
      "--first-cycle",
      "4",
    ]),
    { scope: "registered", firstCycle: 4 },
  );
  for (const args of [
    ["--first-cycle", "1.5"],
    ["--end-cycle", "-1"],
    ["--first-cycle", "9007199254740992"],
    ["--bogus", "x"],
    ["--input"],
  ])
    assert.throws(() => parseArguments(args), /Report timing:/);
});

test("producer references select unique write occurrences and preserve incarnation", async (t) => {
  const f = await sourceFixture(t),
    view = structuredClone(f.view);
  view.bundle.events.push({
    id: "p",
    cycle: 0,
    sequence: 1,
    observer: "o",
    incarnation: "i",
    actor: "a",
    operation: "register_compute",
    inputs: [],
    outputs: [],
  });
  const { attachment } = await read(
    join(f.input, "computations/manifest.json"),
  );
  for (const table of [
    "cells",
    "pins",
    "nets",
    "arcs",
    "bindings",
    "operations",
  ])
    attachment[table] = await read(join(f.input, `computations/${table}.json`));
  attachment.operations.push({
    event: "p",
    kind: "register_compute",
    applicability: "producer",
    status: "located",
    targets: [],
    sources: [],
    unknowns: [],
    writes: ["w", "w"],
  });
  const { createModel } = await import("../web/model.js"),
    { createComputations } = await import("../web/computation-routes.js"),
    { timingReport } = await import("../web/timing-report.js");
  const graph = createComputations(
    createModel(view),
    attachment,
    await read(join(f.input, "computations/routeNets.json")),
  );
  const report = timingReport(graph, { event: "p" });
  assert.equal(report.summary.writes, 1);
  assert.equal(report.summary.requestedBitOccurrences, 1);
  assert.equal(report.cones[0].occurrences.writes, 1);
  assert.equal(report.writes[0].incarnation, "i");
});

test("a source-part symlink cannot read outside the publication", async (t) => {
  const f = await sourceFixture(t);
  const external = join(f.input, "..", "outside.json");
  const arcs = await readFile(join(f.input, "computations/arcs.json"));
  await writeFile(external, arcs);
  await replacePart(f, "arcs", (rows) => rows); // Keep the descriptors authoritative.
  const { unlink } = await import("node:fs/promises");
  await unlink(join(f.input, "computations/arcs.json"));
  await symlink(external, join(f.input, "computations/arcs.json"));
  await assert.rejects(reportTiming(f), /symlink escapes publication/);
  await assert.rejects(stat(f.output), /ENOENT/);
});

test("human report escapes native identifiers without breaking table structure", async (t) => {
  const f = await sourceFixture(t);
  await reportTiming(f);
  const r = await read(join(f.output, "report.json"));
  r.cones[0].source.id = "a`|<script>\nnext";
  const { timingReportMarkdown } = await import("../web/timing-report.js");
  const md = timingReportMarkdown(r);
  assert.match(md, /a&#96;&#124;&lt;script&gt; next/);
  assert(!md.includes("<script>"));
});
