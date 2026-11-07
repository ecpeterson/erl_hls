#!/usr/bin/env node
/** Assemble a complete saved computation recording and native route population.
 * Every input stays immutable; hashes and exact population indexes are checked
 * before publication. Native absolute paths require an explicit local file map. */
import { createHash } from "node:crypto";
import { readFile, stat, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname, join, relative, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

const PART_BYTES = 32 * 1024 * 1024;
const TOTAL_BYTES = 512 * 1024 * 1024;
const TABLES = new Set([
  "cells",
  "pins",
  "nets",
  "arcs",
  "bindings",
  "operations",
]);

/** Failure keeps the fresh diagnostic prefix; a complete manifest is written last. */
function check(condition, reason) {
  if (!condition) throw Error(`Attach computations: ${reason}`);
}

/** Digests bind exact retained bytes, independent of their local filenames. */
function hash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Bound allocations before reading, then detect concurrent length changes. */
async function bytes(path, limit) {
  const info = await stat(path);
  check(
    info.isFile() && info.size <= limit,
    `input exceeds ${limit} bytes: ${path}`,
  );
  const result = await readFile(path);
  check(result.length === info.size, `input changed while reading: ${path}`);
  return result;
}

/** Input manifests reference only descendants of their own directory. */
function partPath(root, file) {
  check(
    typeof file === "string" && file.length > 0 && !isAbsolute(file),
    "invalid relative part filename",
  );
  const path = resolve(root, file),
    rel = relative(root, path);
  check(
    rel !== "" && !rel.startsWith(`..`) && !isAbsolute(rel),
    "part escapes manifest directory",
  );
  return path;
}

/** Verify one descriptor before JSON parsing or copying its bytes. */
async function verified(path, descriptor, limit) {
  check(
    Number.isSafeInteger(descriptor.bytes) &&
      descriptor.bytes >= 0 &&
      typeof descriptor.sha256 === "string" &&
      /^[0-9a-f]{64}$/.test(descriptor.sha256),
    "invalid file descriptor",
  );
  const result = await bytes(path, limit);
  check(
    result.length === descriptor.bytes && hash(result) === descriptor.sha256,
    `input identity mismatch: ${path}`,
  );
  return result;
}

/** Native paths are identities, not local paths to guess or search for. */
async function nativeFile(descriptor, fileMap) {
  check(
    descriptor &&
      typeof descriptor.path === "string" &&
      Object.hasOwn(fileMap, descriptor.path),
    `missing retained native file: ${descriptor?.path}`,
  );
  const path = fileMap[descriptor.path];
  check(
    typeof path === "string" && isAbsolute(path),
    "retained file map requires absolute local paths",
  );
  return JSON.parse(await verified(path, descriptor, PART_BYTES));
}

/** Build identities have exactly the same meaning at both independent inputs. */
function sameBuild(a, b) {
  return ["source", "rtl", "observation"].every(
    (key) => typeof a?.[key] === "string" && a[key] === b?.[key],
  );
}

/** Identifiers are exact saved digests, never hierarchy or equality heuristics. */
function digest(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

/** Retained finite correspondence reviews permit added observation taps without
 * changing the original native build. These receipts remain evidence inventories,
 * not a new native run or an equivalence proof. */
function verifyBuilds(graph, native, recording) {
  const current = graph.build,
    nativeBuild = graph.attachment.nativeBuild,
    checkpoint = graph.checkpoint;
  check(
    [current, nativeBuild].every((build) =>
      ["source", "rtl", "observation"].every((key) => digest(build?.[key])),
    ) && digest(checkpoint),
    "invalid build/checkpoint identity",
  );
  check(
    recording?.format === "spacetime-view" &&
      recording.schema === 1 &&
      sameBuild(current, recording.bundle?.build) &&
      sameBuild(current, recording.catalogue?.build) &&
      sameBuild(current, graph.attachment.build) &&
      sameBuild(nativeBuild, native.build) &&
      current.source === nativeBuild.source &&
      current.rtl === nativeBuild.rtl &&
      checkpoint === native.checkpoint_sha256 &&
      checkpoint === graph.attachment.checkpoint &&
      checkpoint === recording.catalogue.checkpoint,
    "graph/native/recording identity mismatch",
  );
  if (sameBuild(current, nativeBuild)) return;
  const capture = recording.bundle.capture;
  check(
    capture?.complete === true &&
      Number.isSafeInteger(capture.first_cycle) &&
      capture.first_cycle >= 0 &&
      Number.isSafeInteger(capture.end_cycle) &&
      capture.end_cycle > capture.first_cycle,
    "correspondence requires complete finite recording bounds",
  );
  let origin = recording.catalogue.correspondence_origin,
    newer = null,
    found = false,
    depth = 0;
  while (origin != null) {
    check(++depth <= 16, "correspondence chain too deep");
    const comparison = origin.comparison;
    check(
      ["source", "rtl", "observation"].every((key) =>
        digest(origin.build?.[key]),
      ) &&
        origin.build.source === current.source &&
        origin.build.rtl === current.rtl &&
        origin.checkpoint === checkpoint &&
        [
          "base_projection_sha256",
          "original_trace_sha256",
          "extended_trace_sha256",
          "simulator_sha256",
        ].every((key) => digest(origin[key])) &&
        comparison?.old_taps_equal === true &&
        comparison.public_fields_equal === true &&
        Number.isSafeInteger(comparison.original_taps) &&
        comparison.original_taps > 0 &&
        comparison.first_cycle === capture.first_cycle &&
        comparison.end_cycle === capture.end_cycle &&
        comparison.compared_cycles === capture.end_cycle - capture.first_cycle,
      "unqualified correspondence origin",
    );
    check(
      newer === null ||
        (newer.original_trace_sha256 === origin.extended_trace_sha256 &&
          newer.simulator_sha256 === origin.simulator_sha256),
      "correspondence preceding trace/simulator mismatch",
    );
    found ||= sameBuild(origin.build, nativeBuild);
    newer = origin;
    origin = origin.previous_correspondence;
  }
  check(
    found,
    "native observation absent from qualified correspondence origins",
  );
}

/** Merge one whole native net without discarding supplied attachment records.
 * Attachment-index equality detects duplicated/omitted pins despite valid hashes. */
export async function assembleNet(entry, fileMap, expectedPins = null) {
  const index = await nativeFile(entry.file, fileMap);
  check(
    index.complete === true &&
      index.id === entry.id &&
      Array.isArray(index.endpoints) &&
      Array.isArray(index.attachments),
    "invalid complete net index",
  );
  const geometry = await nativeFile(index.geometry, fileMap);
  check(
    geometry.id === index.id &&
      geometry.route_status === index.route_status &&
      Array.isArray(geometry.nodes) &&
      Array.isArray(geometry.pips) &&
      Array.isArray(geometry.issues),
    "geometry/net index mismatch",
  );
  const expected = new Map();
  for (const endpoint of index.endpoints) {
    check(
      typeof endpoint.pin === "string" &&
        !expected.has(endpoint.pin) &&
        ["pin", "port"].includes(endpoint.kind),
      "invalid/duplicate demanded endpoint",
    );
    expected.set(endpoint.pin, endpoint);
  }
  if (expectedPins) {
    check(
      expected.size === expectedPins.size,
      "native/graph endpoint count mismatch",
    );
    for (const [id, endpoint] of expected) {
      const pin = expectedPins.get(id);
      check(
        pin && endpoint.kind === (pin.cell === null ? "port" : "pin"),
        "native/graph endpoint identity mismatch",
      );
    }
  }
  const attachments = new Map();
  for (const source of index.attachments) {
    check(
      Array.isArray(source.pins) &&
        new Set(source.pins).size === source.pins.length,
      "duplicate attachment index",
    );
    const record = await nativeFile(source.file, fileMap);
    check(
      record.id === index.id && Array.isArray(record.pin_attachments),
      "attachment/net identity mismatch",
    );
    const supplied = new Map();
    for (const pin of record.pin_attachments) {
      check(
        typeof pin.pin === "string" && !supplied.has(pin.pin),
        "duplicate native pin attachment",
      );
      supplied.set(pin.pin, pin);
    }
    for (const pin of source.pins) {
      const demand = expected.get(pin),
        actual = supplied.get(pin);
      check(
        demand && actual && !attachments.has(pin),
        "missing/duplicate/unrequested native attachment",
      );
      check(
        actual.direction === demand.direction || actual.direction === null,
        "native endpoint direction disagreement",
      );
      attachments.set(pin, actual);
    }
  }
  check(
    attachments.size === expected.size,
    "incomplete native endpoint coverage",
  );
  return {
    row: { ...geometry, pin_attachments: [...attachments.values()] },
    endpoints: expected.size,
  };
}

/** Publish verified graph parts and one shared routing table, preserving all events.
 * Source graph preparation and native extraction retain their own proof boundaries. */
export async function attachComputations({
  view,
  computations,
  routes,
  routeFiles,
  output,
}) {
  check(
    view && computations && routes && routeFiles && output,
    "required input missing",
  );
  const graphBytes = await bytes(resolve(computations), PART_BYTES);
  const graph = JSON.parse(graphBytes);
  check(
    graph.format === "spacetime-computations-manifest" &&
      graph.schema === 1 &&
      Array.isArray(graph.parts) &&
      graph.totals &&
      graph.attachment,
    "unsupported graph manifest",
  );
  const viewBytes = await verified(
    resolve(view),
    graph.view,
    128 * 1024 * 1024,
  );
  const routeBytes = await bytes(resolve(routes), PART_BYTES),
    native = JSON.parse(routeBytes);
  const mapBytes = await bytes(resolve(routeFiles), PART_BYTES),
    fileMap = JSON.parse(mapBytes);
  check(
    fileMap && typeof fileMap === "object" && !Array.isArray(fileMap),
    "invalid native retained-file map",
  );
  check(
    native.schema_version === 1 &&
      native.complete === true &&
      native.scope === "static_route_graph" &&
      native.coordinate_unit === "tile_grid" &&
      Array.isArray(native.nets),
    "native graph is not complete",
  );
  verifyBuilds(graph, native, JSON.parse(viewBytes));
  check(
    native.requested_nets === native.nets.length,
    "native requested-net count mismatch",
  );
  await mkdir(resolve(output));
  const destination = join(resolve(output), "computations");
  await mkdir(destination);
  const parts = [],
    totals = {},
    names = new Set();
  let totalBytes = 0;
  const record = async (table, data, rows) => {
    check(data.length <= PART_BYTES, "one part exceeds 32 MiB");
    totalBytes += data.length;
    check(totalBytes <= TOTAL_BYTES, "complete attachment exceeds 512 MiB");
    const file = `${table}-${String(parts.length).padStart(5, "0")}.json`;
    await writeFile(join(destination, file), data, { flag: "wx" });
    parts.push({ file, table, bytes: data.length, sha256: hash(data), rows });
    totals[table] = (totals[table] ?? 0) + rows;
  };
  let graphNets = null;
  const graphNetRows = [],
    graphPinRows = [];
  for (const part of graph.parts) {
    check(
      TABLES.has(part.table) &&
        !names.has(part.file) &&
        Number.isSafeInteger(part.rows) &&
        part.rows >= 0,
      "invalid graph part descriptor",
    );
    names.add(part.file);
    const data = await verified(
      partPath(dirname(resolve(computations)), part.file),
      part,
      PART_BYTES,
    );
    const rows = JSON.parse(data);
    check(
      Array.isArray(rows) && rows.length === part.rows,
      "graph part row count mismatch",
    );
    if (part.table === "nets") {
      graphNets ??= new Set();
      for (const row of rows) graphNetRows.push(row);
      for (const net of rows) {
        check(!graphNets.has(net.id), "duplicate graph net");
        graphNets.add(net.id);
      }
    }
    if (part.table === "pins") for (const row of rows) graphPinRows.push(row);
    await record(part.table, data, rows.length);
  }
  for (const table of TABLES)
    check(
      (totals[table] ?? 0) === graph.totals[table],
      `incomplete graph table: ${table}`,
    );
  check(
    graphNets && graphNets.size === native.nets.length,
    "native/graph net population mismatch",
  );
  const expectedPins = new Map(graphNetRows.map((net) => [net.id, new Map()]));
  const pinIds = new Set();
  for (const pin of graphPinRows) {
    check(
      typeof pin.id === "string" && !pinIds.has(pin.id),
      "duplicate/invalid graph pin",
    );
    pinIds.add(pin.id);
    if (pin.net === null) continue;
    check(
      Number.isSafeInteger(pin.net) &&
        pin.net >= 0 &&
        pin.net < graphNetRows.length,
      "graph pin references missing net",
    );
    expectedPins.get(graphNetRows[pin.net].id).set(pin.id, pin);
  }
  const seen = new Set();
  let endpoints = 0,
    chunk = [],
    chunkBytes = 2;
  for (const entry of native.nets) {
    check(
      graphNets.has(entry.id) && !seen.has(entry.id),
      "unrequested/duplicate native net",
    );
    seen.add(entry.id);
    const { row, endpoints: count } = await assembleNet(
      entry,
      fileMap,
      expectedPins.get(entry.id),
    );
    endpoints += count;
    const text = JSON.stringify(row),
      size = Buffer.byteLength(text);
    check(size + 2 <= PART_BYTES, "one complete native net exceeds 32 MiB");
    if (chunk.length && chunkBytes + size + 1 > PART_BYTES) {
      await record(
        "routeNets",
        Buffer.from(`[${chunk.join(",")}]`),
        chunk.length,
      );
      chunk = [];
      chunkBytes = 2;
    }
    chunkBytes += size + (chunk.length ? 1 : 0);
    chunk.push(text);
  }
  if (chunk.length)
    await record(
      "routeNets",
      Buffer.from(`[${chunk.join(",")}]`),
      chunk.length,
    );
  check(
    endpoints === native.requested_endpoints,
    "native endpoint population mismatch",
  );
  const manifest = {
    format: "spacetime-computations-manifest",
    schema: 1,
    view: graph.view,
    build: graph.build,
    checkpoint: graph.checkpoint,
    parts,
    totals,
    attachment: {
      ...graph.attachment,
      routingComplete: true,
      routingCoverage: { nets: seen.size, endpoints },
      publicationInputs: {
        graphManifest: hash(graphBytes),
        routeManifest: hash(routeBytes),
        retainedFileMap: hash(mapBytes),
      },
    },
  };
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  check(manifestBytes.length <= 4 * 1024 * 1024, "manifest exceeds 4 MiB");
  await writeFile(join(resolve(output), "recording.json"), viewBytes, {
    flag: "wx",
  });
  await writeFile(join(destination, "manifest.json"), manifestBytes, {
    flag: "wx",
  });
  const entry = {
    file: "recording.json",
    title: "Recorded computation circuits",
    bytes: viewBytes.length,
    sha256: hash(viewBytes),
    computations: {
      file: "computations/manifest.json",
      bytes: manifestBytes.length,
      sha256: hash(manifestBytes),
    },
  };
  await writeFile(
    join(resolve(output), "index.json"),
    JSON.stringify({
      format: "spacetime-view-index",
      schema: 1,
      examples: [entry],
    }),
    { flag: "wx" },
  );
  return {
    output: resolve(output),
    parts: parts.length,
    decodedBytes: totalBytes,
    nets: seen.size,
    endpoints,
  };
}

/** Later repeated scalar options take precedence, matching the compiler tools. */
export function parseArguments(args) {
  const fields = {
    "--view": "view",
    "--computations": "computations",
    "--routes": "routes",
    "--route-files": "routeFiles",
    "--output": "output",
  };
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    check(
      fields[args[i]] && args[i + 1] && !args[i + 1].startsWith("--"),
      `invalid option: ${args[i]}`,
    );
    options[fields[args[i]]] = args[i + 1];
  }
  return options;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    process.stdout.write(
      `${JSON.stringify(await attachComputations(parseArguments(process.argv.slice(2))))}\n`,
    );
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
