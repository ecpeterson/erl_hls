#!/usr/bin/env node
/** Publish an optional regional sidecar from complete saved native tables. No
 * render derivative, original index, source measurement or design is changed. */
import { readFile, stat, mkdir, writeFile, realpath } from "node:fs/promises";
import { resolve, join, relative, isAbsolute } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { createModel } from "../web/model.js";
import { loadComputations } from "../web/computation-loader.js";
import { createComputations } from "../web/computation-routes.js";
import { createRegionalData } from "../web/regional-data.js";
const MiB = 1024 * 1024,
  TABLES = ["cells", "pips", "nets", "arcNets", "bins"];
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sorted = (values) => [...values].sort((a, b) => a - b);
function check(ok, reason) {
  if (!ok) throw Error(`Prepare regions: ${reason}`);
}
function coordinates(row) {
  const x = row.x ?? null,
    y = row.y ?? null;
  check(
    (x === null && y === null) ||
      [x, y].every((v) => Number.isSafeInteger(v) && v >= 0 && v <= 1000000),
    "invalid tile coordinates",
  );
  return { x, y };
}

/** Bin full used-net graphs, never selected source/sink branches. Canonical net
 * and cell indexes retain source order; PIP identity is global and independent of
 * net/branch/clock occurrence. Native wire membership counts are per net, not
 * physical lengths or a claimed inventory of available routing resources. */
export function prepareRegionalData(model, source, { binSize = 16 } = {}) {
  check(
    model.catalogue?.coordinate_unit === "tile_grid",
    "explicit tile_grid catalogue required",
  );
  check(
    Number.isSafeInteger(binSize) && binSize > 0 && binSize <= 4096,
    "invalid bin size",
  );
  const native = createComputations(model, source.attachment, source.routeNets);
  check(
    native.attachment.routingComplete === true,
    "complete native route population required",
  );
  const binMap = new Map(),
    pipMap = new Map(),
    pips = [];
  const binFor = (row) => {
    if (row.x === null) return null;
    const x = Math.floor(row.x / binSize),
      y = Math.floor(row.y / binSize),
      key = `${x}/${y}`;
    if (!binMap.has(key))
      binMap.set(key, {
        x,
        y,
        cells: new Set(),
        pips: new Set(),
        nets: new Set(),
      });
    return key;
  };
  const cells = native.cells.map((cell, id) => {
    const position = coordinates(model.cells.get(cell.id)),
      bin = binFor(position);
    if (bin !== null) binMap.get(bin).cells.add(id);
    return { id: cell.id, kind: cell.kind ?? null, ...position, bin };
  });
  const routeMap = new Map(source.routeNets.map((row) => [row.id, row]));
  const nets = native.nets.map((net, id) => {
    const route = routeMap.get(net.id);
    check(route, "canonical net lacks routing record");
    const bins = new Set(),
      netPips = new Set(),
      wireBins = new Map(),
      unknownWires = [];
    let wireCount = 0,
      locatedWireCount = 0;
    for (const node of route.nodes)
      for (const wire of node.wires) {
        wireCount++;
        const key = binFor(coordinates(wire));
        if (key === null) unknownWires.push(wire.id);
        else {
          locatedWireCount++;
          wireBins.set(key, (wireBins.get(key) ?? 0) + 1);
          bins.add(key);
          binMap.get(key).nets.add(id);
        }
      }
    for (const pip of route.pips) {
      const row = {
        id: pip.id,
        tile: pip.tile ?? null,
        ...coordinates(pip),
        directionStatus: pip.direction_status,
      };
      let pipId = pipMap.get(pip.id);
      if (pipId === undefined) {
        pipId = pips.length;
        pipMap.set(pip.id, pipId);
        pips.push({ ...row, nets: new Set() });
      } else
        check(
          ["tile", "x", "y", "directionStatus"].every(
            (key) => pips[pipId][key] === row[key],
          ),
          "conflicting shared PIP identity",
        );
      pips[pipId].nets.add(id);
      netPips.add(pipId);
      const key = binFor(row);
      if (key !== null) {
        bins.add(key);
        binMap.get(key).pips.add(pipId);
        binMap.get(key).nets.add(id);
      }
    }
    return {
      id: net.id,
      bins,
      pips: sorted(netPips),
      wireBins,
      wireCount,
      locatedWireCount,
      unknownWires: unknownWires.sort(),
      status: route.status,
      routeStatus: route.route_status,
    };
  });
  const entries = [...binMap.entries()].sort(
      ([, a], [, b]) => a.x - b.x || a.y - b.y,
    ),
    ids = new Map(entries.map(([key], i) => [key, i]));
  const bins = entries.map(([, row]) => ({
    ...row,
    cells: sorted(row.cells),
    pips: sorted(row.pips),
    nets: sorted(row.nets),
  }));
  for (const cell of cells)
    cell.bin = cell.bin === null ? null : ids.get(cell.bin);
  for (const pip of pips) pip.nets = sorted(pip.nets);
  for (const net of nets) {
    net.bins = sorted([...net.bins].map((key) => ids.get(key)));
    net.wireBins = [...net.wireBins]
      .map(([key, count]) => ({ bin: ids.get(key), count }))
      .sort((a, b) => a.bin - b.bin);
  }
  const data = {
    format: "spacetime-regions",
    schema: 1,
    algorithm: 1,
    scope: "installed_native_resource_incidence",
    coordinateUnit: "tile_grid",
    binSize,
    build: model.bundle.build,
    checkpoint: model.catalogue.checkpoint,
    sourceCounts: {
      cells: native.cells.length,
      pins: native.pins.length,
      nets: native.nets.length,
      arcs: native.arcs.length,
      routeNets: source.routeNets.length,
      pipMemberships: source.routeNets.reduce(
        (n, net) => n + net.pips.length,
        0,
      ),
      wireMemberships: source.routeNets.reduce(
        (n, net) => n + net.nodes.reduce((m, node) => m + node.wires.length, 0),
        0,
      ),
    },
    cells,
    pips,
    nets,
    arcNets: native.arcs.map((arc) => (arc.kind === "net" ? arc.net : null)),
    bins,
  };
  createRegionalData(model, data);
  return data;
}
function localPath(root, file) {
  check(
    typeof file === "string" &&
      /^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file),
    "unsafe publication path",
  );
  return resolve(root, file);
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
async function verified(path, descriptor, limit, root) {
  check(
    descriptor &&
      Number.isSafeInteger(descriptor.bytes) &&
      descriptor.bytes >= 2 &&
      descriptor.bytes <= limit &&
      /^[a-f0-9]{64}$/.test(descriptor.sha256),
    "invalid source descriptor",
  );
  const bytes = await bounded(path, limit, root);
  check(
    bytes.length === descriptor.bytes && hash(bytes) === descriptor.sha256,
    "recording hash mismatch",
  );
  return bytes;
}

/** Optional gzip transport leaves every manifest length/digest bound to the raw
 * JSON. Browser fetch verifies decoded bytes; compressed siblings are not evidence
 * tables and add no resource rows. The server may fall back to the raw file. */
async function compressed(path, body, limit) {
  const packed = gzipSync(body, { level: 6 });
  check(packed.length <= limit + 65536, "compressed sidecar exceeds bound");
  await writeFile(`${path}.gz`, packed, { flag: "wx" });
}

/** Verify original inputs and write exclusive sidecar files. Manifest and then
 * descriptor.json commit publication only after every table is complete. The
 * returned descriptor is relative to this sidecar directory; attachment to an
 * existing view index is a separate operation, never an implicit source edit. */
export async function prepareRegions({ input, output, capture, binSize = 16 }) {
  check(input && output, "input and output required");
  const root = await realpath(resolve(input)),
    out = resolve(output);
  try {
    await stat(out);
    throw Error("Prepare regions: output already exists");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const indexBytes = await bounded(join(root, "index.json"), 4 * MiB, root),
    index = JSON.parse(indexBytes);
  check(
    index.format === "spacetime-view-index" &&
      index.schema === 1 &&
      Array.isArray(index.examples),
    "invalid source index",
  );
  const candidates = index.examples.filter((entry) =>
    capture ? entry.file === capture : Boolean(entry.computations),
  );
  check(
    candidates.length === 1 && candidates[0].computations,
    "select exactly one computation capture with --capture FILE",
  );
  const entry = candidates[0],
    viewBytes = await verified(
      localPath(root, entry.file),
      entry,
      128 * MiB,
      root,
    );
  const source = await loadComputations({
    entry: entry.computations,
    view: entry,
    baseUrl: pathToFileURL(`${root}/`).href,
    fetcher: async (url) => {
      check(new URL(url).protocol === "file:", "source must be local");
      return new Response(await bounded(fileURLToPath(url), 32 * MiB, root));
    },
  });
  const data = prepareRegionalData(createModel(JSON.parse(viewBytes)), source, {
    binSize,
  });
  await mkdir(out);
  const parts = [],
    totals = {};
  let totalBytes = 0;
  for (const table of TABLES) {
    totals[table] = data[table].length;
    let rows = [],
      bytes = 2;
    const flush = async () => {
      const body = Buffer.from(`[${rows.join(",")}]`),
        file = `${table}-${String(parts.length).padStart(4, "0")}.json`;
      totalBytes += body.length;
      check(totalBytes <= 64 * MiB, "sidecar exceeds 64 MiB");
      await writeFile(join(out, file), body, { flag: "wx" });
      await compressed(join(out, file), body, 8 * MiB);
      parts.push({
        file,
        table,
        rows: rows.length,
        bytes: body.length,
        sha256: hash(body),
      });
      rows = [];
      bytes = 2;
    };
    for (const row of data[table]) {
      const json = JSON.stringify(row),
        size = Buffer.byteLength(json);
      check(size + 2 <= 8 * MiB, "single row exceeds 8 MiB");
      if (rows.length && bytes + size + 1 > 8 * MiB) await flush();
      bytes += size + (rows.length ? 1 : 0);
      rows.push(json);
    }
    if (rows.length || !data[table].length) await flush();
  }
  const metadata = Object.fromEntries(
    Object.entries(data).filter(([key]) => !TABLES.includes(key)),
  );
  const manifest = {
    format: "spacetime-regions-manifest",
    schema: 1,
    algorithm: 1,
    view: { bytes: viewBytes.length, sha256: hash(viewBytes) },
    source: entry.computations,
    sourceIndex: { bytes: indexBytes.length, sha256: hash(indexBytes) },
    regions: metadata,
    parts,
    totals,
  };
  const body = Buffer.from(JSON.stringify(manifest));
  check(
    body.length <= MiB && totalBytes + body.length <= 64 * MiB,
    "manifest/sidecar exceeds bounds",
  );
  await writeFile(join(out, "manifest.json"), body, { flag: "wx" });
  await compressed(join(out, "manifest.json"), body, MiB);
  const descriptor = {
    file: "manifest.json",
    bytes: body.length,
    sha256: hash(body),
  };
  await writeFile(
    join(out, "descriptor.json"),
    JSON.stringify(descriptor, null, 2) + "\n",
    { flag: "wx" },
  );
  return {
    output: out,
    regions: descriptor,
    decodedBytes: totalBytes + body.length,
    counts: totals,
  };
}

/** Scalar options follow last-wins precedence; bin size is an explicit native
 * tile count. No option infers a coordinate scale from the shape of a fixture. */
export function parseArguments(args) {
  const result = {};
  const names = {
    "--input": "input",
    "--output": "output",
    "--capture": "capture",
    "--bin-size": "binSize",
  };
  for (let i = 0; i < args.length; i += 2) {
    check(
      Object.hasOwn(names, args[i]) &&
        args[i + 1] &&
        !args[i + 1].startsWith("--"),
      "invalid option",
    );
    const key = names[args[i]],
      value = args[i + 1];
    if (key === "binSize") {
      check(
        /^\d+$/.test(value) &&
          Number.isSafeInteger(Number(value)) &&
          Number(value) > 0 &&
          Number(value) <= 4096,
        "invalid bin size",
      );
      result[key] = Number(value);
    } else result[key] = value;
  }
  return result;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv.includes("--help"))
    console.log(
      "Usage: prepare-regions.mjs --input COMPUTATION_PUBLICATION --output FRESH_SIDECAR [--capture FILE] [--bin-size TILES]",
    );
  else
    prepareRegions(parseArguments(process.argv.slice(2)))
      .then((result) => console.log(JSON.stringify(result)))
      .catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
      });
}
