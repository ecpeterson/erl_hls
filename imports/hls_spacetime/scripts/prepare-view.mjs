#!/usr/bin/env node
/** Project any validated execution bundle for the browser. No archive layout,
 * application name, compiler checkout, simulation or vendor tool is assumed. */
import { createHash } from "node:crypto";
import { readFile, stat, mkdir, writeFile } from "node:fs/promises";
import { resolve, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { projectBundle, checkExamples } from "./prepare-example.mjs";
import { parseTimingPaths } from "./timing-paths.mjs";
import { createModel } from "../web/model.js";
import { nativePaths } from "../web/native-paths.js";

/** Reject malformed local evidence with the failed boundary in the diagnostic. */
function check(condition, reason) {
  if (!condition) throw Error(`Prepare view: ${reason}`);
}

/** Exact byte identities accompany each independently supplied source file. */
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Bound both compressed input and decoded allocation before parsing JSON. */
async function input(path, limit) {
  const info = await stat(path);
  check(
    info.isFile() && info.size <= limit,
    `input exceeds ${limit} bytes: ${path}`,
  );
  const packed = await readFile(path);
  const bytes = path.endsWith(".gz")
    ? gunzipSync(packed, { maxOutputLength: limit })
    : packed;
  check(bytes.length <= limit, `decoded input exceeds ${limit} bytes: ${path}`);
  return {
    bytes,
    identity: {
      file: basename(path),
      packed_bytes: packed.length,
      packed_sha256: sha256(packed),
      raw_bytes: bytes.length,
      raw_sha256: sha256(bytes),
    },
  };
}

/** Metadata carries navigation/context only; it cannot replace execution,
 * placement or provenance. Missing native evidence gets logical resource lanes. */
export function prepareView(bundle, metadata = {}) {
  const allowed = new Set([
    "title",
    "selection",
    "annotations",
    "examples",
    "chains",
    "scope",
    "coverage",
    "measurement",
  ]);
  check(
    metadata && !Array.isArray(metadata) && typeof metadata === "object",
    "metadata must be an object",
  );
  check(
    Object.keys(metadata).every((key) => allowed.has(key)),
    "unknown metadata field",
  );
  const capture = bundle.capture;
  const document = {
    format: "spacetime-view",
    schema: 1,
    title: "Execution recording",
    ...projectBundle(bundle),
    annotations: { public: [], boundaries: [] },
    examples: [],
    selection: { firstCycle: capture.first_cycle, endCycle: capture.end_cycle },
    scope: [
      "Saved execution evidence; unavailable physical correspondence and causality remain unknown.",
    ],
    ...metadata,
  };
  check(
    typeof document.title === "string" && document.title.length > 0,
    "missing title",
  );
  const { firstCycle, endCycle } = document.selection;
  check(
    Number.isSafeInteger(firstCycle) &&
      Number.isSafeInteger(endCycle) &&
      firstCycle >= capture.first_cycle &&
      firstCycle < endCycle &&
      endCycle <= capture.end_cycle,
    "selection outside capture",
  );
  check(
    Array.isArray(document.examples) && Array.isArray(document.scope),
    "invalid examples/scope",
  );
  if (!document.catalogue)
    document.layout = {
      coordinate_unit: "logical_address",
      physical: false,
      resources: bundle.resources.map((resource, lane) => ({
        resource: resource.id,
        lane,
        addresses: resource.depth ?? 1,
      })),
      scope: "Logical resource/address lanes; no native placement supplied",
    };
  createModel(document);
  checkExamples(document);
  return document;
}

/** Write a new served directory with one portable projection and an exact-byte
 * index. The producer must run its full validator; browser checks do not replace
 * native collection or claim qualification. Timing report provenance is explicit. */
export async function writeView({
  bundle: bundlePath,
  metadata,
  timingReport,
  timingIdentity,
  output,
}) {
  check(bundlePath && output, "--bundle and --output are required");
  const source = await input(resolve(bundlePath), 256 * 1024 * 1024);
  const context = metadata
    ? await input(resolve(metadata), 4 * 1024 * 1024)
    : null;
  const bundle = JSON.parse(source.bytes);
  const document = prepareView(
    bundle,
    context ? JSON.parse(context.bytes) : {},
  );
  document.provenance = {
    sources: [source.identity, ...(context ? [context.identity] : [])],
    integrity:
      "Exact local input byte identities; producer validation and native claim authenticity remain upstream responsibilities.",
  };
  check(
    Boolean(timingReport) === Boolean(timingIdentity),
    "timing report and its verified identity must be supplied together",
  );
  if (timingReport) {
    check(
      document.catalogue,
      "timing report requires a joined native catalogue",
    );
    const report = await input(resolve(timingReport), 4 * 1024 * 1024);
    const identity = await input(resolve(timingIdentity), 65536);
    verifyTimingIdentity(
      JSON.parse(identity.bytes),
      bundle.build,
      document.catalogue.checkpoint,
      report.identity.raw_sha256,
    );
    document.provenance.sources.push(identity.identity);
    document.nativePaths = {
      build: bundle.build,
      checkpoint: document.catalogue.checkpoint,
      scope: "static_timing",
      wireGeometry: false,
      report: report.identity.file,
      report_sha256: report.identity.raw_sha256,
      paths: parseTimingPaths(report.bytes.toString("utf8"), {
        cells: bundle.physical.cells,
      }),
    };
    document.provenance.sources.push(report.identity);
    nativePaths(createModel(document));
  }
  const bytes = Buffer.from(JSON.stringify(document));
  check(
    bytes.length <= 128 * 1024 * 1024,
    "projection exceeds browser's 128 MiB input limit",
  );
  await mkdir(resolve(output));
  await writeFile(join(output, "recording.json"), bytes, { flag: "wx" });
  const entry = {
    file: "recording.json",
    title: document.title,
    bytes: bytes.length,
    sha256: sha256(bytes),
  };
  await writeFile(
    join(output, "index.json"),
    JSON.stringify(
      { format: "spacetime-view-index", schema: 1, examples: [entry] },
      null,
      2,
    ),
    { flag: "wx" },
  );
  return {
    ...entry,
    events: bundle.events.length,
    versions: bundle.versions.length,
    physical: document.catalogue !== null,
  };
}

/** Require an independently retained extraction identity before copying native
 * labels onto a report. The inventory is trusted evidence, not a signature. */
export function verifyTimingIdentity(
  identity,
  build,
  checkpoint,
  reportSha256,
) {
  check(
    identity &&
      ["source", "rtl", "observation"].every(
        (key) => identity.build?.[key] === build[key],
      ),
    "timing identity build mismatch",
  );
  check(
    identity.checkpoint === checkpoint,
    "timing identity checkpoint mismatch",
  );
  check(
    /^[a-f0-9]{64}$/.test(identity.report_sha256 ?? "") &&
      identity.report_sha256 === reportSha256,
    "timing report hash mismatch",
  );
}

/** Later repeated scalar options take precedence, matching composed commands. */
export function parseArguments(args) {
  const names = {
    "--bundle": "bundle",
    "--metadata": "metadata",
    "--timing-report": "timingReport",
    "--timing-identity": "timingIdentity",
    "--output": "output",
  };
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help") return { help: true };
    check(
      names[args[i]] && args[i + 1] && !args[i + 1].startsWith("--"),
      `unknown/incomplete option ${args[i]}`,
    );
    options[names[args[i]]] = args[++i];
  }
  return options;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help)
      console.log(
        "node scripts/prepare-view.mjs --bundle BUNDLE.json[.gz] [--metadata CONTEXT.json] [--timing-report REPORT.rpt[.gz] --timing-identity VERIFIED.json] --output FRESH_DIRECTORY",
      );
    else console.log(JSON.stringify(await writeView(options), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
