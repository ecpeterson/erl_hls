#!/usr/bin/env node
/** Build a bounded offline diagnostic from complete saved graph evidence.
 * Never invokes a native tool or simulator, and never overwrites its inputs. */
import { readFile, stat, mkdir, writeFile, realpath } from "node:fs/promises";
import { resolve, join, relative, isAbsolute } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { createModel } from "../web/model.js";
import { loadComputations } from "../web/computation-loader.js";
import { createComputations } from "../web/computation-routes.js";
import { timingReport, timingReportMarkdown } from "../web/timing-report.js";
const MiB = 1024 * 1024;
function check(ok, reason) {
  if (!ok) throw Error(`Report timing: ${reason}`);
}
function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
async function bounded(path, limit, root) {
  const canonical = await realpath(path),
    rel = relative(root, canonical);
  check(
    rel && !rel.startsWith("..") && !isAbsolute(rel),
    "source symlink escapes publication",
  );
  const info = await stat(canonical);
  check(info.isFile() && info.size <= limit, "input exceeds byte bound");
  const bytes = await readFile(canonical);
  check(bytes.length === info.size, "input changed while reading");
  return bytes;
}
function localPath(root, file) {
  check(
    typeof file === "string" &&
      /^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file),
    "unsafe publication path",
  );
  return resolve(root, file);
}

/** Validate the entire publication even for a narrow report window. The complete
 * source manifest/part digests remain the authority; prepared browser caches are
 * not an analysis input. Outputs are exclusive and a manifest is written last. */
export async function reportTiming({
  input,
  output,
  capture,
  scope = "registered",
  firstCycle,
  endCycle,
  event,
}) {
  check(input && output, "input and output are required");
  const root = await realpath(resolve(input)),
    out = resolve(output);
  const indexBytes = await bounded(join(root, "index.json"), 4 * MiB, root),
    index = JSON.parse(indexBytes);
  check(
    index.format === "spacetime-view-index" &&
      index.schema === 1 &&
      Array.isArray(index.examples),
    "invalid source index",
  );
  const candidates = index.examples.filter((e) =>
    capture ? e.file === capture : Boolean(e.computations),
  );
  check(
    candidates.length === 1,
    "select exactly one computation capture with --capture FILE",
  );
  const entry = candidates[0];
  check(entry.computations, "capture lacks complete computation source");
  check(
    Number.isSafeInteger(entry.bytes) &&
      entry.bytes > 0 &&
      entry.bytes <= 128 * MiB &&
      /^[0-9a-f]{64}$/.test(entry.sha256),
    "invalid recording descriptor",
  );
  const bytes = await bounded(localPath(root, entry.file), 128 * MiB, root);
  check(
    bytes.length === entry.bytes && digest(bytes) === entry.sha256,
    "recording hash mismatch",
  );
  const source = await loadComputations({
    entry: entry.computations,
    view: entry,
    baseUrl: pathToFileURL(`${root}/`).href,
    fetcher: async (url) => {
      const parsed = new URL(url);
      check(parsed.protocol === "file:", "source must be local");
      const path = fileURLToPath(parsed),
        rel = relative(root, path);
      check(
        rel && !rel.startsWith("..") && !isAbsolute(rel),
        "source escapes publication",
      );
      return new Response(await bounded(path, 32 * MiB, root));
    },
  });
  const model = createModel(JSON.parse(bytes));
  const graph = createComputations(model, source.attachment, source.routeNets);
  const report = timingReport(graph, { scope, firstCycle, endCycle, event });
  report.inputs = {
    index: { bytes: indexBytes.length, sha256: digest(indexBytes) },
    recording: { file: entry.file, bytes: entry.bytes, sha256: entry.sha256 },
    computations: entry.computations,
  };
  const files = [
    {
      file: "report.json",
      bytes: Buffer.from(JSON.stringify(report) + "\n"),
      limit: 32 * MiB,
    },
    {
      file: "report.md",
      bytes: Buffer.from(timingReportMarkdown(report)),
      limit: 4 * MiB,
    },
  ];
  for (const f of files)
    check(f.bytes.length <= f.limit, `${f.file} exceeds output bound`);
  await mkdir(out);
  for (const f of files)
    await writeFile(join(out, f.file), f.bytes, { flag: "wx" });
  const manifest = {
    format: "spacetime-timing-report-manifest",
    schema: 1,
    algorithm: 1,
    inputs: report.inputs,
    build: report.build,
    checkpoint: report.checkpoint,
    selection: report.selection,
    summary: report.summary,
    files: files.map((f) => ({
      file: f.file,
      bytes: f.bytes.length,
      sha256: digest(f.bytes),
    })),
  };
  await writeFile(
    join(out, "manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
    { flag: "wx" },
  );
  return { output: out, ...report.summary };
}

/** Scalar options use last-wins precedence. Cycle bounds are exact nonnegative
 * integers; a window is half-open and validated against the saved capture. */
export function parseArguments(args) {
  const result = {};
  const names = {
    "--input": "input",
    "--output": "output",
    "--capture": "capture",
    "--scope": "scope",
    "--first-cycle": "firstCycle",
    "--end-cycle": "endCycle",
    "--event": "event",
  };
  for (let i = 0; i < args.length; i += 2) {
    check(
      Object.hasOwn(names, args[i]) &&
        args[i + 1] &&
        !args[i + 1].startsWith("--"),
      "invalid option",
    );
    const name = names[args[i]],
      value = args[i + 1];
    if (["firstCycle", "endCycle"].includes(name)) {
      check(
        /^\d+$/.test(value) && Number.isSafeInteger(Number(value)),
        "invalid cycle",
      );
      result[name] = Number(value);
    } else result[name] = value;
  }
  return result;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv.includes("--help"))
    console.log(
      "Usage: report-timing.mjs --input COMPUTATION_PUBLICATION --output FRESH_DIRECTORY [--capture FILE] [--scope registered|static] [--first-cycle C --end-cycle C] [--event ID]",
    );
  else
    reportTiming(parseArguments(process.argv.slice(2)))
      .then((r) => console.log(JSON.stringify(r)))
      .catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
      });
}
