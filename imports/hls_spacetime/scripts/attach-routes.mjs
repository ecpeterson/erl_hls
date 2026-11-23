#!/usr/bin/env node
/** Attach one saved native-route sidecar to its exact selected browser view.
 * This command reads local evidence only; it never invokes native tools,
 * regenerates the graph or replaces an existing output file. */
import { createHash } from "node:crypto";
import { readFile, stat, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { createModel } from "../web/model.js";
import { nativePaths } from "../web/native-paths.js";
import { nativeRoutes } from "../web/native-routes.js";

const LIMITS = {
  view: 128 * 1024 * 1024,
  selection: 4 * 1024 * 1024,
  routes: 32 * 1024 * 1024,
};

/** Identity covers exact file bytes, including whitespace. */
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Reject contradictory identities before constructing a new presentation. */
function check(condition, message) {
  if (!condition) throw Error(`Route attachment: ${message}`);
}

/** Parse only bounded UTF-8 JSON, retaining each input's exact byte identity. */
function decode(bytes, role) {
  check(
    bytes instanceof Uint8Array && bytes.byteLength <= LIMITS[role],
    `${role} exceeds its byte limit or is not a byte buffer`,
  );
  return {
    value: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    identity: { bytes: bytes.byteLength, sha256: sha256(bytes) },
  };
}

/** Return a new projection after checking exact selection/view/route identities,
 * selected path content and retained report provenance. The route validator
 * checks endpoint topology and original native-build correspondence separately.
 * The execution graph and capture are retained without interpretation changes.
 * Inventories are trusted local annotations, not signatures or authentication
 * of the exporter/checkpoint. Input byte buffers are never modified. */
export function attachRoutes({ viewBytes, selectionBytes, routesBytes }) {
  const viewInput = decode(viewBytes, "view"),
    selectionInput = decode(selectionBytes, "selection"),
    routeInput = decode(routesBytes, "routes");
  const view = viewInput.value,
    selection = selectionInput.value,
    routes = routeInput.value;
  check(
    view?.format === "spacetime-view" && view.schema === 1,
    "unsupported browser projection",
  );
  check(
    !view.nativeRoutes && !view.provenance?.route_attachment,
    "projection already has a route attachment",
  );
  check(selection?.schema === 1, "unsupported route selection");
  for (const key of ["projectionSha256", "reportSha256", "checkpoint"])
    check(
      /^[a-f0-9]{64}$/.test(selection[key] ?? ""),
      `invalid selection ${key}`,
    );
  check(
    selection.projectionSha256 === viewInput.identity.sha256,
    "selected projection hash mismatch",
  );
  const detail = view.nativePaths;
  check(
    detail &&
      view.catalogue &&
      detail.checkpoint === selection.checkpoint &&
      view.catalogue.checkpoint === selection.checkpoint,
    "selected checkpoint mismatch",
  );
  check(
    isDeepStrictEqual(selection.paths, detail.paths),
    "selected paths changed",
  );
  check(
    routes && isDeepStrictEqual(selection.build, routes.build),
    "selected/exported build mismatch",
  );
  check(
    routes.selection_sha256 === selectionInput.identity.sha256,
    "exported selection hash mismatch",
  );
  check(
    routes.checkpoint_sha256 === selection.checkpoint &&
      routes.report_sha256 === selection.reportSha256,
    "exported checkpoint/report mismatch",
  );
  check(
    typeof detail.report === "string" && detail.report.length > 0,
    "missing original timing report name",
  );
  const reports = (view.provenance?.sources ?? []).filter(
    (source) => source.file === detail.report,
  );
  check(
    reports.length > 0 &&
      reports.every((source) => source.raw_sha256 === selection.reportSha256),
    "original timing report provenance mismatch",
  );
  check(
    detail.report_sha256 === undefined ||
      detail.report_sha256 === selection.reportSha256,
    "existing timing report identity mismatch",
  );
  check(
    detail.route_selection_sha256 === undefined ||
      detail.route_selection_sha256 === selectionInput.identity.sha256,
    "existing route selection identity mismatch",
  );
  const document = {
    ...view,
    nativePaths: {
      ...detail,
      report_sha256: selection.reportSha256,
      route_selection_sha256: selectionInput.identity.sha256,
    },
    nativeRoutes: routes,
    provenance: {
      ...view.provenance,
      route_attachment: {
        schema: 1,
        inputs: {
          view: viewInput.identity,
          selection: selectionInput.identity,
          routes: routeInput.identity,
        },
        integrity:
          "Exact input bytes and selected path/report identities checked; source inventories are trusted annotations, not signatures.",
        scope:
          "Static native route topology at tile resolution; no new execution edges, dynamic activity or sub-tile wire geometry.",
      },
    },
  };
  const model = createModel(document);
  nativePaths(model);
  nativeRoutes(model);
  return document;
}

/** Bound local reads before allocation, then recheck the received byte count. */
async function readBounded(path, role) {
  const info = await stat(path);
  check(
    info.isFile() && info.size <= LIMITS[role],
    `${role} exceeds its byte limit or is not a regular file`,
  );
  const bytes = await readFile(path);
  check(bytes.byteLength <= LIMITS[role], `${role} exceeds its byte limit`);
  return bytes;
}

/** Write an exclusively created derivative, leaving the inputs and view index
 * unchanged. The returned output hash can be used by a separately reviewed
 * index update; opening the new file directly requires no index mutation. */
export async function attachRouteFiles({ view, selection, routes, out }) {
  check(
    [view, selection, routes, out].every(
      (path) => typeof path === "string" && path.length,
    ),
    "--view, --selection, --routes and --out are required",
  );
  const [viewBytes, selectionBytes, routesBytes] = await Promise.all([
    readBounded(resolve(view), "view"),
    readBounded(resolve(selection), "selection"),
    readBounded(resolve(routes), "routes"),
  ]);
  const document = attachRoutes({ viewBytes, selectionBytes, routesBytes });
  const bytes = Buffer.from(JSON.stringify(document));
  check(bytes.byteLength <= LIMITS.view, "derived view exceeds 128 MiB");
  await writeFile(resolve(out), bytes, { flag: "wx" });
  return {
    output: resolve(out),
    bytes: bytes.byteLength,
    sha256: sha256(bytes),
    selectedPaths: document.nativePaths.paths.length,
    routeNets: document.nativeRoutes.nets.length,
    scope: document.provenance.route_attachment.scope,
  };
}

/** Later repeated options win, matching other toolchain command interfaces. */
export function parseArguments(args) {
  const options = {},
    names = {
      "--view": "view",
      "--selection": "selection",
      "--routes": "routes",
      "--out": "out",
    };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help") return { help: true };
    check(
      names[args[i]] && args[i + 1] && !args[i + 1].startsWith("--"),
      `unknown or incomplete argument: ${args[i]}`,
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
        "node scripts/attach-routes.mjs --view VIEW.json --selection selection.json --routes routes.json --out NEW_VIEW.json",
      );
    else console.log(JSON.stringify(await attachRouteFiles(options), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
