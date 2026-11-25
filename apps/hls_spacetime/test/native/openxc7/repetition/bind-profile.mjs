/** Bind the N2 producer's reviewed scheduling obligations to a complete replay of
 * the same logical graph. The two implementations supply independent physical data. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { gunzipSync } from "node:zlib";
import { createModel } from "../../../../web/model.js";
import { validateLatencyProfile } from "../../../../web/recorded-scenario.js";

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const [directory, archive, profileFile] = process.argv.slice(2);
const indexFile = join(directory, "index.json");
const index = JSON.parse(await readFile(indexFile));
assert.equal(index.examples.length, 1);
const [entry] = index.examples;
assert.equal(entry.file, "recording.json");
const bytes = await readFile(join(directory, entry.file));
assert.equal(hash(bytes), entry.sha256);
assert.equal(bytes.length, entry.bytes);
const recording = { bytes: entry.bytes, sha256: entry.sha256 };
const view = JSON.parse(bytes);
const raw = await readFile(profileFile);
assert.equal(
  hash(raw),
  "079a9eaed37a74f4a298825229994a3f6550cd837fbb2f5f1880131e52d96164",
);
const profile = JSON.parse(raw);
const source = await readFile(
  join(archive, "capture-ancestry-1/live-2/bundle.json.gz"),
);
assert.equal(
  hash(source),
  profile.evidence.find((e) => e.description === "bundle").sha256,
);
const original = JSON.parse(gunzipSync(source, { maxOutputLength: 96 << 20 }));
assert.deepEqual(original.build, profile.build);
assert.equal(view.bundle.build.source, original.build.source);
const replay = await readFile(join(directory, "../replay/result.json"));
assert.equal(hash(replay), view.bundle.build.observation);
const receipt = JSON.parse(replay);
assert.equal(
  receipt.trace_sha256,
  "587435348ca6201ebb1e32a1b9e772e07b7af0ee3572edf27d09e388281aa8f2",
);
assert.equal(receipt.rtl_sha256[0], original.build.rtl);
// A checked ID at the same cycle is insufficient. Compare every event, version,
// mask, dependency, resource, incarnation and the capture horizon before rebinding.
assert.ok(
  isDeepStrictEqual({ ...view.bundle, build: original.build }, original),
  "replayed logical graph differs from the profile source",
);
profile.build = view.bundle.build;
profile.recording = recording;
profile.evidence.push(
  {
    path: "source-profile-2.json",
    sha256: hash(raw),
    description: "Reviewed owner scheduling obligations",
  },
  {
    path: "replay/result.json",
    sha256: hash(replay),
    description: "Full 592-tap N2 replay",
  },
  {
    path: entry.file,
    sha256: entry.sha256,
    description: "Current graph and implementation",
  },
);
for (const row of profile.unknowns) {
  if (row.kind === "physical")
    row.disposition = "A changed schedule requires new implementation timing.";
}
validateLatencyProfile(createModel(view), profile, recording);
const file = "latency-profile.json",
  body = Buffer.from(JSON.stringify(profile));
assert.equal(entry.latencyProfile, undefined);
await writeFile(join(directory, file), body, { flag: "wx" });
entry.latencyProfile = { file, bytes: body.length, sha256: hash(body) };
await writeFile(indexFile + ".tmp", JSON.stringify(index), { flag: "wx" });
await rename(indexFile + ".tmp", indexFile);
