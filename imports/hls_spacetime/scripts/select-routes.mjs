#!/usr/bin/env node
/** Prepare exact route queries from a saved view and its full joined catalogue.
 * No native tool runs here, and no cell/net correspondence is guessed. */
import { createHash } from "node:crypto";
import { readFile, stat, mkdir, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { createModel } from "../web/model.js";
import { nativePaths } from "../web/native-paths.js";

const LIMITS = { view: 128 * 1024 * 1024, bundle: 256 * 1024 * 1024 };

/** Contradictory saved evidence cannot become an executable native selection. */
function check(condition, message) {
  if (!condition) throw Error(`Route selection: ${message}`);
}

/** Digests identify exact input/control bytes, including whitespace. */
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Every generated native identity is a bounded scalar, not Tcl program text. */
function text(value) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 4096 &&
    !/[\x00-\x1f\x7f]/.test(value)
  );
}

/** Escape Tcl substitution characters inside one quoted word. Braces remain
 * literal in quotes; dollars, brackets, quotes and backslashes never execute. */
function tclWord(value) {
  check(text(value), "invalid Tcl identity");
  return `"${value.replace(/[\\$\[\]"]/g, "\\$&")}"`;
}

/** Reject non-UTF8, oversized or unsupported saved JSON before indexing it. */
function decode(bytes, role) {
  check(
    bytes instanceof Uint8Array && bytes.byteLength <= LIMITS[role],
    `${role} byte limit`,
  );
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

/** Index exact identities once; duplicates are evidence errors, not last-wins options. */
function index(rows, key, label) {
  check(
    Array.isArray(rows) && rows.length <= 2_000_000,
    `${label} table limit`,
  );
  const result = new Map();
  for (const row of rows) {
    check(
      text(row?.[key]) && !result.has(row[key]),
      `duplicate/invalid ${label} identity`,
    );
    result.set(row[key], row);
  }
  return result;
}

/** Select every saved timing path (at most fifty) and resolve each net arc by
 * exact report-net alias plus native source/target pin membership. The full
 * joined bundle must have the same build/checkpoint as the view. Historical
 * capture-extension rebinding is deliberately not inferred by this command.
 * The caller still owns full bundle validation and native evidence authenticity. */
export function selectRoutes({ viewBytes, bundleBytes }) {
  const view = decode(viewBytes, "view"),
    bundle = decode(bundleBytes, "bundle");
  check(
    bundle?.format === "spacetime" &&
      bundle.schema === 1 &&
      bundle.unit === "cycle",
    "unsupported joined bundle",
  );
  check(
    !view.nativeRoutes && !view.provenance?.route_attachment,
    "view already has routes",
  );
  const model = createModel(view),
    detail = view.nativePaths,
    physical = bundle.physical;
  check(
    physical &&
      model.catalogue &&
      isDeepStrictEqual(bundle.build, model.bundle.build) &&
      isDeepStrictEqual(physical.build, bundle.build) &&
      physical.checkpoint === model.catalogue.checkpoint,
    "bundle/view build or checkpoint mismatch",
  );
  for (const digest of [
    ...["source", "rtl", "observation"].map((key) => bundle.build[key]),
    physical.checkpoint,
  ])
    check(
      typeof digest === "string" && /^[a-f0-9]{64}$/.test(digest),
      "invalid build/checkpoint digest",
    );
  const paths = nativePaths(model);
  check(
    paths.length > 0 && paths.length <= 50,
    "select between one and fifty saved paths",
  );
  const reports = (view.provenance?.sources ?? []).filter(
    (source) => source.file === detail.report,
  );
  check(
    text(detail.report) &&
      /^[a-f0-9]{64}$/.test(detail.report_sha256 ?? "") &&
      reports.length > 0 &&
      reports.every((source) => source.raw_sha256 === detail.report_sha256),
    "timing report provenance mismatch",
  );
  const cells = index(physical.cells, "id", "cell"),
    nets = index(physical.nets, "id", "net");
  const aliases = index(physical.native?.aliases, "id", "alias"),
    pins = new Map();
  let records = cells.size + nets.size + aliases.size;
  for (const alias of aliases.values())
    check(nets.has(alias.net), "alias references absent canonical net");
  for (const net of nets.values()) {
    check(Array.isArray(net.pins), "missing native net pins");
    records += net.pins.length;
    check(records <= 2_000_000, "native record limit");
    for (const pin of net.pins) {
      const name = pin.native;
      check(
        text(name) && text(pin.pin) && cells.has(pin.cell) && !pins.has(name),
        "duplicate/invalid native pin identity",
      );
      check(
        ["input", "output", "inout"].includes(pin.direction),
        "invalid native pin direction",
      );
      pins.set(name, { ...pin, net: net.id });
    }
  }
  const arcs = [],
    selectedNets = new Set();
  for (const path of paths) {
    for (const step of path.steps) {
      const full = cells.get(step.cell),
        projected = model.cells.get(step.cell);
      check(
        full && ["kind", "x", "y"].every((key) => full[key] === projected[key]),
        `selected cell placement mismatch: ${step.cell}`,
      );
    }
    for (const [arcIndex, arc] of path.arcs.entries()) {
      if (arc.kind !== "net") continue;
      const net = aliases.get(arc.net)?.net;
      check(net, `missing exact report-net alias: ${arc.net}`);
      const source = pins.get(arc.source),
        target = pins.get(arc.target);
      check(
        source?.net === net &&
          target?.net === net &&
          source.cell === arc.source.slice(0, arc.source.lastIndexOf("/")) &&
          target.cell === arc.target.slice(0, arc.target.lastIndexOf("/")) &&
          ["output", "inout"].includes(source.direction) &&
          ["input", "inout"].includes(target.direction),
        `selected pin/net mismatch: ${arc.net}`,
      );
      arcs.push({
        path_id: path.id,
        arc_index: arcIndex,
        report_net: arc.net,
        canonical_net: net,
        source_pin: arc.source,
        target_pin: arc.target,
      });
      selectedNets.add(net);
    }
  }
  check(
    arcs.length > 0 && arcs.length <= 10_000 && selectedNets.size <= 1000,
    "selected arc/net limit",
  );
  const selection = {
    schema: 1,
    checkpoint: physical.checkpoint,
    build: bundle.build,
    reportSha256: detail.report_sha256,
    projectionSha256: sha256(viewBytes),
    paths,
    catalogueBundle: {
      sha256: sha256(bundleBytes),
      bytes: bundleBytes.byteLength,
    },
  };
  const selectionBytes = Buffer.from(JSON.stringify(selection, null, 2) + "\n");
  check(selectionBytes.length <= 4 * 1024 * 1024, "selection exceeds 4 MiB");
  const fields = ["source", "rtl", "observation"]
    .map((key) => `${tclWord(key)} ${tclWord(bundle.build[key])}`)
    .join(" ");
  const rows = arcs.map(
    (arc) =>
      "[dict create " +
      Object.entries(arc)
        .map(
          ([key, value]) =>
            `${tclWord(key)} ${key === "arc_index" ? value : tclWord(value)}`,
        )
        .join(" ") +
      "]",
  );
  const selectionTcl = `set selection [dict create build [dict create ${fields}] checkpoint_sha256 ${tclWord(physical.checkpoint)} report_sha256 ${tclWord(detail.report_sha256)} selection_sha256 ${tclWord(sha256(selectionBytes))} paths [list \\\n  ${rows.join(" \\\n  ")}]]\n`;
  check(
    Buffer.byteLength(selectionTcl) <= 4 * 1024 * 1024,
    "Tcl selection exceeds 4 MiB",
  );
  return {
    selection,
    selectionBytes,
    selectionTcl,
    arcs,
    nets: selectedNets.size,
  };
}

/** Explicit argv paths keep host-specific paths out of the saved driver. The
 * export itself is read-only and bounded; its caller must supply the process
 * memory/wall-time guard and verify terminal completion before collection. */
export const routeDriver = `# vivado -mode batch -source run.tcl -tclargs CHECKPOINT EXPORT_ROUTES_TCL FRESH_OUTPUT
if {$argc != 3} {error "expected checkpoint, exporter and fresh output paths"}
lassign $argv checkpoint exporter output
source $exporter
source [file join [file dirname [info script]] selection.tcl]
::hls_spacetime_routes::run $checkpoint $output $selection [dict create seconds 600 records 200000 bytes 33554432 nets 1000]
exit
`;

/** Recheck actual bytes after stat; the bounded decoded form is checked again. */
async function readBounded(path, role) {
  const info = await stat(path);
  check(info.isFile() && info.size <= LIMITS[role], `${role} file limit`);
  const bytes = await readFile(path);
  check(
    bytes.length === info.size && bytes.length <= LIMITS[role],
    `${role} changed size`,
  );
  return bytes;
}

/** Publish reviewable controls into a fresh directory; a complete inventory is
 * written last. Existing output paths reject and failed prefixes are retained. */
export async function writeSelection({ view, bundle, output }) {
  check(
    [view, bundle, output].every(text),
    "--view, --bundle and --output are required",
  );
  const [viewBytes, bundleBytes] = await Promise.all([
    readBounded(resolve(view), "view"),
    readBounded(resolve(bundle), "bundle"),
  ]);
  const result = selectRoutes({ viewBytes, bundleBytes });
  const files = [
    ["selection.json", result.selectionBytes],
    ["selection.tcl", result.selectionTcl],
    ["run.tcl", routeDriver],
  ];
  await mkdir(resolve(output));
  const entries = [];
  for (const [name, data] of files) {
    const bytes = Buffer.from(data);
    await writeFile(join(output, name), bytes, { flag: "wx" });
    entries.push({ file: name, bytes: bytes.length, sha256: sha256(bytes) });
  }
  await writeFile(
    join(output, "manifest.json"),
    JSON.stringify(
      {
        schema: 1,
        format: "spacetime_route_controls",
        complete: true,
        files: entries,
      },
      null,
      2,
    ) + "\n",
    { flag: "wx" },
  );
  return {
    paths: result.selection.paths.length,
    arcs: result.arcs.length,
    nets: result.nets,
    files: entries,
  };
}

/** Later scalar options override earlier composed command prefixes. */
export function parseArguments(args) {
  const names = {
      "--view": "view",
      "--bundle": "bundle",
      "--output": "output",
    },
    options = {};
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
        "node scripts/select-routes.mjs --view VIEW.json --bundle JOINED_BUNDLE.json --output FRESH_DIRECTORY",
      );
    else console.log(JSON.stringify(await writeSelection(options), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
