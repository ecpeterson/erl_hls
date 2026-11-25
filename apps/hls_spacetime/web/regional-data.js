/** Optional installed-resource bins derived from complete native routing tables.
 * Counts describe observed resource use, not capacity, utilization or congestion. */
import { recordingBuildKeys } from "./recording-build.js";

const TABLES = ["cells", "pips", "nets", "arcNets", "bins"];
const MiB = 1024 * 1024;
const integer = (value) => Number.isSafeInteger(value) && value >= 0;
const text = (value) =>
  typeof value === "string" && value.length > 0 && value.length <= 4096;
const digest = (value) =>
  typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
function check(ok, message) {
  if (!ok) throw Error(`Regional data: ${message}`);
}
function location(row) {
  check(
    (row.x === null && row.y === null) ||
      (integer(row.x) &&
        integer(row.y) &&
        row.x <= 1000000 &&
        row.y <= 1000000),
    "invalid tile coordinates",
  );
  return row.x !== null;
}
function refs(rows, length, label) {
  check(
    Array.isArray(rows) &&
      rows.every(
        (id, i) => integer(id) && id < length && (!i || rows[i - 1] < id),
      ),
    `invalid ${label} references`,
  );
}
function equalRefs(a, b, label) {
  check(
    a.length === b.length && a.every((id, i) => id === b[i]),
    `${label} inventory mismatch`,
  );
}
function sameBuild(a, b) {
  return recordingBuildKeys(a, b).every(
    (key) => digest(a?.[key]) && a[key] === b?.[key],
  );
}
const sorted = (values) => [...values].sort((a, b) => a - b);

/** Validate complete contributors and reciprocal inventories, then derive counts
 * and fixed global maxima. Source-cell order matches the native graph, not an
 * assumed catalogue array order. Unknown locations/classes remain separate. */
export function createRegionalData(model, data) {
  if (!data) return null;
  check(
    data.format === "spacetime-regions" &&
      data.schema === 1 &&
      data.algorithm === 1 &&
      data.coordinateUnit === "tile_grid",
    "unsupported format/coordinates",
  );
  check(
    model?.catalogue?.coordinate_unit === "tile_grid" &&
      model.catalogue.checkpoint === data.checkpoint &&
      digest(data.checkpoint) &&
      sameBuild(data.build, model.bundle.build),
    "native identity/coordinate mismatch",
  );
  check(
    integer(data.binSize) && data.binSize > 0 && data.binSize <= 4096,
    "invalid bin size",
  );
  for (const table of TABLES)
    check(Array.isArray(data[table]), `missing ${table} table`);
  const { cells, pips, nets, arcNets, bins, sourceCounts } = data;
  check(
    sourceCounts &&
      integer(sourceCounts.pins) &&
      sourceCounts.cells === cells.length &&
      sourceCounts.nets === nets.length &&
      sourceCounts.arcs === arcNets.length &&
      sourceCounts.routeNets === nets.length &&
      cells.length === model.cells.size,
    "incomplete source population",
  );
  const binKeys = new Map(),
    cellBins = bins.map(() => []),
    pipBins = bins.map(() => []),
    netBins = bins.map(() => []),
    pipNets = pips.map(() => []);
  const binFor = (row) => {
    if (!location(row)) return null;
    const key = `${Math.floor(row.x / data.binSize)}/${Math.floor(row.y / data.binSize)}`;
    check(binKeys.has(key), "located contributor lacks bin");
    return binKeys.get(key);
  };
  for (const [id, bin] of bins.entries()) {
    check(integer(bin.x) && integer(bin.y), "invalid bin coordinate");
    const key = `${bin.x}/${bin.y}`;
    check(!binKeys.has(key), "duplicate bin");
    binKeys.set(key, id);
    refs(bin.cells, cells.length, "bin cell");
    refs(bin.pips, pips.length, "bin PIP");
    refs(bin.nets, nets.length, "bin net");
    check(
      bin.cells.length + bin.pips.length + bin.nets.length > 0,
      "empty bin",
    );
  }
  const cellIds = new Set(),
    pipIds = new Set(),
    netIds = new Set();
  let unknownCellKinds = 0,
    unknownCellPositions = 0,
    unknownPipPositions = 0,
    unknownPipDirections = 0,
    wireMemberships = 0,
    locatedWireMemberships = 0,
    unknownWireMemberships = 0,
    netsWithUnknownPositions = 0;
  for (const [id, cell] of cells.entries()) {
    check(
      text(cell.id) &&
        !cellIds.has(cell.id) &&
        (cell.kind === null || text(cell.kind)),
      "invalid/duplicate cell",
    );
    cellIds.add(cell.id);
    const source = model.cells.get(cell.id);
    check(
      source &&
        (source.kind ?? null) === cell.kind &&
        (source.x ?? null) === cell.x &&
        (source.y ?? null) === cell.y,
      "native cell mismatch",
    );
    const bin = binFor(cell);
    check(cell.bin === bin, "cell bin mismatch");
    if (bin === null) unknownCellPositions++;
    else cellBins[bin].push(id);
    if (cell.kind === null) unknownCellKinds++;
  }
  for (const [id, pip] of pips.entries()) {
    check(
      text(pip.id) &&
        !pipIds.has(pip.id) &&
        (pip.tile === null || text(pip.tile)) &&
        ["directional", "bidirectional", "unavailable"].includes(
          pip.directionStatus,
        ),
      "invalid/duplicate PIP",
    );
    pipIds.add(pip.id);
    refs(pip.nets, nets.length, "PIP net");
    check(pip.nets.length > 0, "PIP without owner net");
    const bin = binFor(pip);
    if (bin === null) unknownPipPositions++;
    else {
      check(text(pip.tile), "located PIP lacks native tile");
      pipBins[bin].push(id);
    }
    if (pip.directionStatus === "unavailable") unknownPipDirections++;
  }
  for (const [id, net] of nets.entries()) {
    check(
      text(net.id) &&
        !netIds.has(net.id) &&
        text(net.status) &&
        text(net.routeStatus),
      "invalid/duplicate canonical net",
    );
    netIds.add(net.id);
    refs(net.bins, bins.length, "net bin");
    refs(net.pips, pips.length, "net PIP");
    check(
      integer(net.wireCount) &&
        integer(net.locatedWireCount) &&
        Array.isArray(net.unknownWires) &&
        net.unknownWires.every(text) &&
        new Set(net.unknownWires).size === net.unknownWires.length &&
        net.wireCount === net.locatedWireCount + net.unknownWires.length &&
        Array.isArray(net.wireBins),
      "wire coverage mismatch",
    );
    const expected = new Set(),
      seen = new Set();
    let located = 0;
    for (const row of net.wireBins) {
      check(
        integer(row.bin) &&
          row.bin < bins.length &&
          !seen.has(row.bin) &&
          integer(row.count) &&
          row.count > 0,
        "invalid wire-bin inventory",
      );
      seen.add(row.bin);
      expected.add(row.bin);
      located += row.count;
    }
    check(located === net.locatedWireCount, "located wire coverage mismatch");
    for (const pip of net.pips) {
      pipNets[pip].push(id);
      const bin = binFor(pips[pip]);
      if (bin !== null) expected.add(bin);
    }
    equalRefs(net.bins, sorted(expected), "net footprint");
    for (const bin of net.bins) netBins[bin].push(id);
    wireMemberships += net.wireCount;
    locatedWireMemberships += located;
    unknownWireMemberships += net.unknownWires.length;
    if (net.unknownWires.length || net.pips.some((pip) => pips[pip].x === null))
      netsWithUnknownPositions++;
  }
  for (const [id, pip] of pips.entries())
    equalRefs(pip.nets, pipNets[id], "PIP ownership");
  check(
    arcNets.every((net) => net === null || (integer(net) && net < nets.length)),
    "invalid arc/net map",
  );
  const maxima = {
    cells: 0,
    pips: 0,
    nets: 0,
    primitiveKinds: Object.create(null),
  };
  const resolved = bins.map((bin, id) => {
    equalRefs(bin.cells, cellBins[id], "bin cell");
    equalRefs(bin.pips, pipBins[id], "bin PIP");
    equalRefs(bin.nets, netBins[id], "bin net");
    const primitiveKinds = Object.create(null);
    let unknownKinds = 0;
    for (const cell of bin.cells) {
      const kind = cells[cell].kind;
      if (kind === null) unknownKinds++;
      else primitiveKinds[kind] = (primitiveKinds[kind] ?? 0) + 1;
    }
    const counts = {
      cells: bin.cells.length,
      pips: bin.pips.length,
      nets: bin.nets.length,
    };
    for (const key of ["cells", "pips", "nets"])
      maxima[key] = Math.max(maxima[key], counts[key]);
    for (const [kind, count] of Object.entries(primitiveKinds))
      maxima.primitiveKinds[kind] = Math.max(
        maxima.primitiveKinds[kind] ?? 0,
        count,
      );
    return {
      ...bin,
      counts,
      primitiveKinds,
      unknownKinds,
      bounds: {
        minX: bin.x * data.binSize,
        minY: bin.y * data.binSize,
        maxX: (bin.x + 1) * data.binSize,
        maxY: (bin.y + 1) * data.binSize,
      },
    };
  });
  const summary = {
    cells: cells.length,
    pips: pips.length,
    nets: nets.length,
    bins: bins.length,
    unknownCellKinds,
    unknownCellPositions,
    unknownPipPositions,
    unknownPipDirections,
    wireMemberships,
    locatedWireMemberships,
    unknownWireMemberships,
    netsWithUnknownPositions,
    netsWithoutLocatedResources: nets.filter((net) => !net.bins.length).length,
    netBinIncidences: nets.reduce((n, net) => n + net.bins.length, 0),
    pipNetIncidences: pips.reduce((n, pip) => n + pip.nets.length, 0),
  };
  check(
    sourceCounts.pipMemberships === summary.pipNetIncidences &&
      sourceCounts.wireMemberships === summary.wireMemberships,
    "native routing population mismatch",
  );
  return { ...data, bins: resolved, maxima, summary };
}
function publicationUrl(file, base) {
  check(
    typeof file === "string" &&
      /^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file),
    "unsafe publication path",
  );
  return new URL(file, base).href;
}
function descriptor(row, limit) {
  check(
    row &&
      integer(row.bytes) &&
      row.bytes >= 2 &&
      row.bytes <= limit &&
      digest(row.sha256),
    "invalid descriptor",
  );
}
async function checkedJson(url, expected, limit, fetcher, signal) {
  descriptor(expected, limit);
  const response = await fetcher(url, { signal });
  check(response.ok, `fetch failed (${response.status})`);
  const reader = response.body.getReader(),
    bytes = new Uint8Array(expected.bytes);
  let offset = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      check(
        offset + value.length <= bytes.length,
        "part exceeds declared bytes",
      );
      bytes.set(value, offset);
      offset += value.length;
    }
  } catch (error) {
    await reader.cancel();
    throw error;
  }
  check(offset === bytes.length, "part length mismatch");
  const sha = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  check(sha === expected.sha256, "part digest mismatch");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

/** Lazily load only when called. Verify exact recording/source-manifest bindings
 * and all parts serially; no prefix succeeds. Safe in a worker: return raw data,
 * then call createRegionalData with the caller's already validated model. */
export async function loadRegionalData({
  entry,
  view,
  source,
  baseUrl,
  fetcher = fetch,
  signal,
  progress = () => {},
}) {
  if (!entry) return null;
  descriptor(view, 128 * MiB);
  descriptor(source, 4 * MiB);
  publicationUrl(source.file, baseUrl);
  const url = publicationUrl(entry.file, baseUrl),
    manifest = await checkedJson(url, entry, MiB, fetcher, signal);
  check(
    manifest.format === "spacetime-regions-manifest" &&
      manifest.schema === 1 &&
      manifest.algorithm === 1,
    "unsupported manifest",
  );
  check(
    manifest.view?.bytes === view.bytes &&
      manifest.view?.sha256 === view.sha256,
    "recording identity mismatch",
  );
  check(
    source &&
      ["file", "bytes", "sha256"].every(
        (k) => manifest.source?.[k] === source[k],
      ),
    "computation source mismatch",
  );
  const metadata = manifest.regions;
  check(
    metadata &&
      metadata.format === "spacetime-regions" &&
      metadata.schema === 1 &&
      metadata.algorithm === 1 &&
      metadata.coordinateUnit === "tile_grid" &&
      digest(metadata.checkpoint) &&
      sameBuild(metadata.build, metadata.build),
    "invalid regional identity",
  );
  check(
    Array.isArray(manifest.parts) &&
      manifest.parts.length <= 256 &&
      manifest.totals &&
      Object.keys(manifest.totals).sort().join() === [...TABLES].sort().join(),
    "invalid table inventory",
  );
  const paths = new Set(),
    counts = Object.fromEntries(TABLES.map((table) => [table, 0]));
  let total = entry.bytes;
  for (const part of manifest.parts) {
    check(
      TABLES.includes(part.table) &&
        !paths.has(part.file) &&
        integer(part.rows),
      "invalid table part",
    );
    publicationUrl(part.file, url);
    descriptor(part, 8 * MiB);
    paths.add(part.file);
    counts[part.table] += part.rows;
    total += part.bytes;
    check(total <= 64 * MiB, "regional data exceeds 64 MiB");
  }
  for (const table of TABLES)
    check(
      integer(manifest.totals[table]) &&
        manifest.totals[table] === counts[table],
      "incomplete table inventory",
    );
  const tables = Object.fromEntries(TABLES.map((table) => [table, []]));
  for (const [i, part] of manifest.parts.entries()) {
    progress(`Reading regional resources (${i + 1}/${manifest.parts.length})…`);
    const rows = await checkedJson(
      publicationUrl(part.file, url),
      part,
      8 * MiB,
      fetcher,
      signal,
    );
    check(
      Array.isArray(rows) && rows.length === part.rows,
      "part row count mismatch",
    );
    check(
      part.encoding === undefined ||
        (part.table === "pips" && part.encoding === "xc7-switch-v1"),
      "unknown table encoding",
    );
    for (const row of rows) {
      if (!part.encoding) tables[part.table].push(row);
      else {
        check(
          Array.isArray(row) &&
            row.length === 4 &&
            text(row[0]) &&
            /^[^/]+\/\d+\.\d+$/.test(row[0]),
          "invalid compact switch",
        );
        const [id, x, y, nets] = row;
        tables.pips.push({
          id,
          x,
          y,
          nets,
          tile: id.slice(0, id.indexOf("/")),
          directionStatus: "directional",
        });
      }
    }
  }
  return { ...metadata, ...tables };
}
