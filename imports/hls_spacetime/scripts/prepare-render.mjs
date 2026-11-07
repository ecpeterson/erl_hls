#!/usr/bin/env node
/** Compile deterministic rendering data from a verified computation publication.
 * No native tool or simulation runs. Full source records remain in the output,
 * hardlinked when possible and copied otherwise; no input is changed. */
import {
  readFile,
  stat,
  mkdir,
  writeFile,
  link,
  copyFile,
  constants,
} from "node:fs/promises";
import { resolve, dirname, join, relative, isAbsolute } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { encodePrimitive } from "../web/prepared-format.js";
import { createModel } from "../web/model.js";
import {
  createComputations,
  computationLayers,
  computationConnection,
} from "../web/computation-routes.js";
import { createPreparedComputations } from "../web/prepared-computations.js";
import { loadComputations } from "../web/computation-loader.js";
const MiB = 1024 * 1024;
const TABLES = ["operations", "writes", "cones", "routes", "primitives"];
function check(ok, reason) {
  if (!ok) throw Error(`Prepare render: ${reason}`);
}
function hash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
function pathIn(root, file) {
  check(
    typeof file === "string" &&
      /^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file),
    "unsafe source path",
  );
  const path = resolve(root, file),
    rel = relative(root, path);
  check(
    rel && !rel.startsWith("..") && !isAbsolute(rel),
    "source escapes directory",
  );
  return path;
}
async function bytes(path, limit) {
  const before = await stat(path);
  check(before.isFile() && before.size <= limit, "input exceeds byte bound");
  const value = await readFile(path);
  check(value.length === before.size, "input changed while reading");
  return value;
}
async function verified(path, descriptor, limit) {
  check(
    descriptor &&
      Number.isSafeInteger(descriptor.bytes) &&
      descriptor.bytes >= 2 &&
      descriptor.bytes <= limit &&
      /^[0-9a-f]{64}$/.test(descriptor.sha256),
    "invalid source descriptor",
  );
  const value = await bytes(path, limit);
  check(
    value.length === descriptor.bytes && hash(value) === descriptor.sha256,
    `source hash mismatch: ${path}`,
  );
  return value;
}
function tile(value) {
  return value && Number.isFinite(value.x) && Number.isFinite(value.y)
    ? { x: value.x, y: value.y, physical: true }
    : null;
}

/** Precompute each unique cone and routed branch once. Row identities refer to
 * the complete original graph; no occurrence is sampled and no unknown is filled. */
export function prepareRenderData(model, computationData) {
  const index = createComputations(
    model,
    computationData.attachment,
    computationData.routeNets,
  );
  check(
    index.attachment.routingComplete === true,
    "source routing must be complete",
  );
  const primitives = [],
    primitiveIndex = new Map(),
    routes = [],
    routeIndex = new Map(),
    cones = [],
    coneIndex = new Map(),
    writes = [];
  const add = (id, row) => {
    if (!primitiveIndex.has(id)) {
      primitiveIndex.set(id, primitives.length);
      primitives.push({ id: primitives.length, ...row });
    }
    return primitiveIndex.get(id);
  };
  const cellPoint = (i) => tile(model.cells.get(index.cells[i]?.id));
  const routeFor = (arcId) => {
    if (routeIndex.has(arcId)) return routeIndex.get(arcId);
    const arc = index.arcs[arcId],
      route = computationConnection(index, arcId),
      ids = new Set();
    for (const node of route.nodes)
      for (const wire of node.wires) {
        const point = tile(wire);
        if (point)
          ids.add(
            add(`tile/${arc.net}/${wire.x}/${wire.y}`, {
              type: "tiles",
              point,
              sourceNet: arc.net,
            }),
          );
      }
    const switches = route.pips.map((pip) => {
      const point = tile(pip);
      if (point)
        ids.add(
          add(`pip/${arc.net}/${pip.id}`, {
            type: "pips",
            point,
            sourceNet: arc.net,
          }),
        );
      return point;
    });
    const from = cellPoint(index.pins[arc.from].cell),
      to = cellPoint(index.pins[arc.to].cell);
    if (!route.nodes.length) {
      if (from && to)
        ids.add(
          add(`unresolved/${arcId}`, {
            type: "segments",
            from,
            to,
            kind: "unresolved",
            sourceNet: arc.net,
          }),
        );
    } else {
      const ends = [from, ...switches, to],
        identities = [
          `pin/${arc.from}`,
          ...route.pips.map((p) => p.id),
          `pin/${arc.to}`,
        ];
      for (let i = 1; i < ends.length; i++)
        if (ends[i - 1] && ends[i])
          ids.add(
            add(`span/${arc.net}/${identities[i - 1]}/${identities[i]}`, {
              type: "segments",
              from: ends[i - 1],
              to: ends[i],
              kind: i === 1 || i === ends.length - 1 ? "site" : "node",
              sourceNet: arc.net,
            }),
          );
    }
    const id = routes.length;
    routeIndex.set(arcId, id);
    const gapCounts = {};
    for (const gap of route.gaps)
      gapCounts[gap.kind] = (gapCounts[gap.kind] ?? 0) + 1;
    routes.push({
      arc: arcId,
      disposition: route.disposition,
      primitives: [...ids],
      gapCounts,
    });
    return id;
  };
  const coneFor = (cone) => {
    if (coneIndex.has(cone.id)) return coneIndex.get(cone.id);
    const ids = new Set(),
      routeIds = [],
      cellIds = new Map();
    for (const c of cone.cellIndices) {
      const point = cellPoint(c);
      if (point) {
        const id = add(`cell/${c}`, {
          type: "cells",
          point,
          boundary: index.cells[c].boundary,
          sourceCell: c,
        });
        ids.add(id);
        cellIds.set(c, id);
      }
    }
    for (const arc of cone.arcIndices)
      if (index.arcs[arc].kind === "net") {
        const r = routeFor(arc);
        routeIds.push(r);
        for (const id of routes[r].primitives) ids.add(id);
      }
    const primitiveIds = [...ids];
    const positions = new Map(primitiveIds.map((id, i) => [id, i]));
    const primitivePathDelays = {
      registered: primitiveIds.map(() => "not_applicable"),
      static: primitiveIds.map(() => "not_applicable"),
    };
    // Geometry can represent several graph arcs. Its color carries the worst
    // complete through-path, retaining any applicable unknown contributor.
    const contribute = (primitive, arcPosition) => {
      const position = positions.get(primitive);
      check(position !== undefined, "path geometry outside cone");
      for (const scope of ["registered", "static"]) {
        const cost = cone.pathDelays[scope][arcPosition];
        const previous = primitivePathDelays[scope][position];
        primitivePathDelays[scope][position] =
          previous === null || cost === null
            ? null
            : cost === "not_applicable"
              ? previous
              : previous === "not_applicable"
                ? cost
                : Math.max(previous, cost);
      }
    };
    cone.arcIndices.forEach((arcId, arcPosition) => {
      const arc = index.arcs[arcId];
      for (const cell of new Set([
        index.pins[arc.from].cell,
        index.pins[arc.to].cell,
      ])) {
        if (cellIds.has(cell)) contribute(cellIds.get(cell), arcPosition);
      }
      if (arc.kind === "net") {
        for (const id of routes[routeIndex.get(arcId)].primitives)
          contribute(id, arcPosition);
      }
    });
    const id = cones.length;
    coneIndex.set(cone.id, id);
    cones.push({
      ...cone,
      primitives: primitiveIds,
      routes: routeIds,
      primitivePathDelays,
    });
    return id;
  };
  for (const event of model.events.values())
    if (event.access?.kind === "write") {
      const [layer] = computationLayers(index, [event.id]);
      check(
        layer && layer.operations.length === 1,
        "write occurrence disappeared",
      );
      const { requestedBits, mappedBits, unknownBits } = layer.coverage;
      writes.push({
        event: event.id,
        cones: layer.cones.map(coneFor),
        coverage: { requestedBits, mappedBits, unknownBits },
      });
    }
  const bounds = { ...model.geometryBounds };
  check(
    ["minX", "maxX", "minY", "maxY"].every((k) => Number.isFinite(bounds[k])),
    "missing physical bounds",
  );
  const include = (value) => {
    if (!tile(value)) return;
    bounds.minX = Math.min(bounds.minX, value.x);
    bounds.maxX = Math.max(bounds.maxX, value.x);
    bounds.minY = Math.min(bounds.minY, value.y);
    bounds.maxY = Math.max(bounds.maxY, value.y);
  };
  for (const net of computationData.routeNets) {
    for (const pip of net.pips) include(pip);
    for (const node of net.nodes) for (const wire of node.wires) include(wire);
  }
  const max = (scope) =>
    cones.reduce(
      (maximum, cone) =>
        cone.primitivePathDelays[scope].reduce(
          (value, cost) =>
            typeof cost === "number" ? Math.max(value ?? 0, cost) : value,
          maximum,
        ),
      null,
    );
  const data = {
    format: "spacetime-prepared-render",
    schema: 1,
    algorithm: 2,
    build: index.attachment.build,
    nativeBuild: index.attachment.nativeBuild,
    checkpoint: index.attachment.checkpoint,
    bounds,
    maxDelays: {
      registered: max("registered"),
      static: max("static"),
    },
    coverage: index.attachment.coverage,
    sourceCounts: {
      events: model.events.size,
      writes: writes.length,
      cells: index.cells.length,
      pins: index.pins.length,
      nets: index.nets.length,
      arcs: index.arcs.length,
      routeNets: computationData.routeNets.length,
    },
    scope:
      "Derived rendering data for every recorded write through qualified mapped targets; full native source remains separately hash-bound. SDF colors bound complete source-to-sink paths through each primitive; they are not incremental arc delay, switching, STA slack or an execution period.",
    operations: [...index.operations.values()].map((op) => ({
      event: op.event,
      applicability: op.applicability,
      status: op.status,
      writes: op.writes ?? [],
    })),
    writes,
    cones,
    routes,
    primitives,
  };
  createPreparedComputations(model, data);
  return data;
}

/** Shared JSON tables are complete and independently hashed; exceeding a bound
 * fails explicitly. A successful derivative never consists of a clipped prefix. */
async function publishTables(output, data) {
  const parts = [],
    totals = {};
  let totalBytes = 0;
  for (const table of TABLES) {
    totals[table] = data[table].length;
    let chunk = [],
      size = 2;
    const flush = async () => {
      const body = Buffer.from(`[${chunk.join(",")}]`),
        file = `${table}-${String(parts.length).padStart(5, "0")}.json`;
      totalBytes += body.length;
      check(totalBytes <= 256 * MiB, "derivative exceeds 256 MiB");
      await writeFile(join(output, file), body, { flag: "wx" });
      await compressed(join(output, file), body, 32 * MiB);
      parts.push({
        file,
        table,
        encoding:
          table === "primitives" ? "geometry-tuples-v1" : "json-rows-v1",
        rows: chunk.length,
        bytes: body.length,
        sha256: hash(body),
      });
      chunk = [];
      size = 2;
    };
    for (const row of data[table]) {
      const value = JSON.stringify(
          table === "primitives" ? encodePrimitive(row) : row,
        ),
        n = Buffer.byteLength(value);
      check(n + 2 <= 32 * MiB, "one derived row exceeds 32 MiB");
      if (chunk.length && size + n + 1 > 32 * MiB) await flush();
      size += n + (chunk.length ? 1 : 0);
      chunk.push(value);
    }
    if (chunk.length || !data[table].length) await flush();
  }
  const render = Object.fromEntries(
    Object.entries(data).filter(([k]) => !TABLES.includes(k)),
  );
  return { parts, totals, render, totalBytes };
}

/** Precompressed transport keeps raw byte/hash identities unchanged. The server
 * may select this sibling; browser fetch verifies the decoded original bytes. */
async function compressed(path, body, limit) {
  const packed = gzipSync(body, { level: 6 });
  check(packed.length <= limit + 65536, "compressed sidecar exceeds bound");
  await writeFile(`${path}.gz`, packed, { flag: "wx" });
}

/** Retain the exact source file under a new name without modifying it. The
 * descriptor is rechecked after linking/copying to detect a concurrent change. */
async function retain(from, to, descriptor, limit) {
  await mkdir(dirname(to), { recursive: true });
  try {
    await link(from, to);
  } catch (error) {
    if (error.code !== "EXDEV") throw error;
    await copyFile(from, to, constants.COPYFILE_EXCL);
  }
  await verified(to, descriptor, limit);
}

/** Compile one selected publication into a fresh portable directory. Ordinary
 * browser captures without this derivative remain supported by their old loader. */
export async function prepareRender({ input, output, capture }) {
  check(input && output, "input and output are required");
  const root = resolve(input),
    out = resolve(output),
    index = JSON.parse(await bytes(join(root, "index.json"), 4 * MiB));
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
  const viewPath = pathIn(root, entry.file),
    viewBytes = await verified(viewPath, entry, 128 * MiB);
  const graphPath = pathIn(root, entry.computations.file),
    graphBytes = await verified(graphPath, entry.computations, 4 * MiB),
    graph = JSON.parse(graphBytes);
  const graphRoot = dirname(graphPath);
  const fetcher = async (url) => {
    const path = fileURLToPath(url),
      rel = relative(root, path);
    check(
      rel && !rel.startsWith("..") && !isAbsolute(rel),
      "source fetch escapes root",
    );
    return new Response(await bytes(path, 32 * MiB));
  };
  const source = await loadComputations({
    entry: entry.computations,
    view: { bytes: viewBytes.length, sha256: hash(viewBytes) },
    baseUrl: pathToFileURL(`${root}/`).href,
    fetcher,
  });
  const model = createModel(JSON.parse(viewBytes)),
    data = prepareRenderData(model, source);
  await mkdir(out);
  const renderRoot = join(out, "render");
  await mkdir(renderRoot);
  const published = await publishTables(renderRoot, data);
  const sourceDescriptor = { ...entry.computations };
  const manifest = {
    format: "spacetime-render-manifest",
    schema: 1,
    algorithm: 2,
    view: { bytes: viewBytes.length, sha256: hash(viewBytes) },
    source: sourceDescriptor,
    parts: published.parts,
    totals: published.totals,
    render: published.render,
  };
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  check(manifestBytes.length <= 4 * MiB, "manifest exceeds 4 MiB");
  await retain(viewPath, pathIn(out, entry.file), entry, 128 * MiB);
  await compressed(pathIn(out, entry.file), viewBytes, 128 * MiB);
  await retain(
    graphPath,
    pathIn(out, entry.computations.file),
    entry.computations,
    4 * MiB,
  );
  for (const part of graph.parts)
    await retain(
      pathIn(graphRoot, part.file),
      pathIn(dirname(pathIn(out, entry.computations.file)), part.file),
      part,
      32 * MiB,
    );
  await writeFile(join(renderRoot, "manifest.json"), manifestBytes, {
    flag: "wx",
  });
  await compressed(join(renderRoot, "manifest.json"), manifestBytes, 4 * MiB);
  const render = {
    file: "render/manifest.json",
    bytes: manifestBytes.length,
    sha256: hash(manifestBytes),
  };
  await writeFile(
    join(out, "index.json"),
    JSON.stringify({
      format: "spacetime-view-index",
      schema: 1,
      examples: [{ ...entry, render }],
    }),
    { flag: "wx" },
  );
  return {
    output: out,
    render,
    decodedBytes: published.totalBytes,
    counts: published.totals,
    sourceCounts: data.sourceCounts,
  };
}

/** Repeated scalar options use the last value, matching the surrounding tools. */
export function parseArguments(args) {
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    check(
      ["--input", "--output", "--capture"].includes(args[i]) &&
        args[i + 1] &&
        !args[i + 1].startsWith("--"),
      "invalid option",
    );
    options[args[i].slice(2)] = args[i + 1];
  }
  return options;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv.includes("--help"))
    console.log(
      "Usage: prepare-render.mjs --input COMPUTATION_PUBLICATION --output FRESH_DIRECTORY [--capture RECORDING_FILE]",
    );
  else
    prepareRender(parseArguments(process.argv.slice(2)))
      .then((result) => console.log(JSON.stringify(result)))
      .catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
      });
}
