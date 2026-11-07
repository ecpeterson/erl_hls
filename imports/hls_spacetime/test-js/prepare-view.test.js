import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  prepareView,
  writeView,
  parseArguments,
  verifyTimingIdentity,
} from "../scripts/prepare-view.mjs";

/** A finite empty observation still has an explicit scope and capture interval. */
function bundle() {
  return {
    format: "spacetime",
    schema: 1,
    unit: "cycle",
    evidence: "synthetic_fixture",
    build: { source: "s", rtl: "r", observation: "o" },
    capture: {
      device: "synthetic",
      clock: "clk",
      first_cycle: 0,
      end_cycle: 2,
      complete: true,
      evidence: "synthetic empty capture",
      incarnations: [{ id: "i", first_cycle: 0, end_cycle: 2 }],
      observers: [
        {
          id: "o",
          first_sequence: 0,
          next_sequence: 0,
          gaps: [],
          scope: "empty fixture",
        },
      ],
    },
    resources: [],
    events: [],
    versions: [],
    relations: [],
    activity: [],
    physical: null,
  };
}

test("fresh bundles need neither application IDs nor native placement", () => {
  const original = bundle();
  const view = prepareView(original, {
    title: "New workload",
    selection: { firstCycle: 0, endCycle: 1 },
  });
  assert.deepEqual(view.bundle, original);
  assert.equal(view.catalogue, null);
  assert.equal(view.layout.physical, false);
  assert.equal(view.title, "New workload");
});

test("metadata cannot replace evidence or select outside the capture", () => {
  assert.throws(
    () => prepareView(bundle(), { bundle: bundle() }),
    /unknown metadata/,
  );
  assert.throws(
    () => prepareView(bundle(), { selection: { firstCycle: 0, endCycle: 3 } }),
    /outside capture/,
  );
  assert.throws(
    () =>
      prepareView(bundle(), { examples: [{ event: "missing", events: [] }] }),
    /Missing example/,
  );
});

test("documented writer creates a portable fresh view and refuses reuse", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-view-"));
  try {
    const input = join(root, "capture.json"),
      output = join(root, "viewer");
    await writeFile(input, JSON.stringify(bundle()));
    const result = await writeView({ bundle: input, output });
    const index = JSON.parse(await readFile(join(output, "index.json")));
    assert.equal(index.examples[0].sha256, result.sha256);
    const view = JSON.parse(await readFile(join(output, "recording.json")));
    assert.equal(view.provenance.sources[0].file, "capture.json");
    assert.equal(result.physical, false);
    await assert.rejects(writeView({ bundle: input, output }), /EEXIST/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("later options override earlier command prefixes", () => {
  assert.deepEqual(
    parseArguments(["--bundle", "old", "--bundle", "new", "--output", "view"]),
    { bundle: "new", output: "view" },
  );
  assert.throws(() => parseArguments(["--bundle"]), /incomplete/);
});

test("a same-hierarchy timing report must still match its independent native identity", () => {
  const build = bundle().build,
    checkpoint = "c",
    digest = "a".repeat(64);
  const identity = { build, checkpoint, report_sha256: digest };
  verifyTimingIdentity(identity, build, checkpoint, digest);
  assert.throws(
    () => verifyTimingIdentity(identity, build, "another-checkpoint", digest),
    /checkpoint mismatch/,
  );
  assert.throws(
    () => verifyTimingIdentity(identity, build, checkpoint, "b".repeat(64)),
    /hash mismatch/,
  );
  assert.throws(
    () =>
      verifyTimingIdentity(
        identity,
        { ...build, rtl: "another-RTL" },
        checkpoint,
        digest,
      ),
    /build mismatch/,
  );
});
