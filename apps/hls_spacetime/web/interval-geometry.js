/** Demand-load frozen openXC7 branches by prepared arc ID. Each shard binds exact decoded bytes. */
import { checkedJson, publicationUrl } from "./computation-loader.js";

const MiB = 1024 * 1024;
const integer = (v) => Number.isSafeInteger(v) && v >= 0;
const check = (v, reason) => {
  if (!v) throw Error("Interval geometry: " + reason);
};
const resolved = (status) => ["direct", "lut_permutation"].includes(status);

/** Bind the geometry inventory to all three loaded publications and their native checkpoint. */
export async function openIntervalGeometry({
  entry,
  baseUrl,
  model,
  fetcher = fetch,
  signal,
}) {
  const url = publicationUrl(entry.geometry.file, baseUrl);
  const m = await checkedJson(url, entry.geometry, 4 * MiB, fetcher, signal);
  const selection = model.document.selection;
  check(
    m.format === "spacetime-openxc7-geometry" &&
      m.schema === 1 &&
      m.view === entry.sha256 &&
      m.source === entry.computations.sha256 &&
      m.render === entry.render.sha256 &&
      m.checkpoint === model.catalogue.checkpoint &&
      Object.keys(model.bundle.build).every(
        (k) => m.build?.[k] === model.bundle.build[k],
      ) &&
      ["firstCycle", "endCycle"].every(
        (k) => integer(selection?.[k]) && m.selection?.[k] === selection[k],
      ),
    "recording, interval or checkpoint mismatch",
  );
  check(
    integer(m.tiles) &&
      integer(m.width) &&
      m.width > 0 &&
      m.tiles >= m.width &&
      integer(m.branches) &&
      m.branches <= 1_000_000 &&
      Object.values(m.counts).every(integer) &&
      Object.values(m.counts).reduce((a, b) => a + b, 0) === m.branches,
    "invalid census",
  );
  const inventory = new Set();
  for (const table of ["branches", "nodes", "pips"]) {
    let last = -1,
      rows = 0;
    check(
      Array.isArray(m.parts?.[table]) && m.parts[table].length <= 32768,
      "invalid inventory",
    );
    for (const part of m.parts[table]) {
      check(
        integer(part.first) &&
          integer(part.last) &&
          part.first > last &&
          part.last >= part.first &&
          integer(part.rows) &&
          part.rows > 0 &&
          part.rows <= 1024 &&
          part.rows <= part.last - part.first + 1 &&
          integer(part.bytes) &&
          part.bytes <= MiB &&
          !inventory.has(part.file),
        "invalid shard range",
      );
      publicationUrl(part.file, url);
      inventory.add(part.file);
      last = part.last;
      rows += part.rows;
    }
    if (table === "branches")
      check(rows === m.branches, "incomplete branch inventory");
  }
  const cache = new Map();
  let cachedBytes = 0;

  /** Group requested IDs into ordered ranges. Out-of-interval arc IDs are legitimate holes. */
  async function records(table, ids, request) {
    const pending = new Map(),
      result = new Map(),
      parts = m.parts[table];
    for (const id of ids) {
      check(integer(id), "invalid native ID");
      let lo = 0,
        hi = parts.length;
      while (lo < hi) {
        const mid = Math.floor((lo + hi) / 2);
        if (parts[mid].last < id) lo = mid + 1;
        else hi = mid;
      }
      const part = parts[lo];
      if (!part || part.first > id) {
        check(table === "branches", "reference outside inventory");
        continue;
      }
      if (!pending.has(part)) pending.set(part, new Set());
      pending.get(part).add(id);
    }
    for (const [part, wanted] of pending) {
      request.signal?.throwIfAborted();
      request.bytes += part.bytes;
      check(
        request.bytes <= 32 * MiB,
        "selection exceeds 32 MiB; inspect one branch",
      );
      let rows = cache.get(part);
      if (!rows) {
        const data = await checkedJson(
          publicationUrl(part.file, url),
          part,
          MiB,
          fetcher,
          request.signal,
        );
        request.signal?.throwIfAborted();
        check(
          Array.isArray(data) &&
            data.length === part.rows &&
            data[0]?.[0] === part.first &&
            data.at(-1)?.[0] === part.last &&
            data.every(
              (r, i) =>
                Array.isArray(r) &&
                integer(r[0]) &&
                (!i || data[i - 1][0] < r[0]),
            ),
          "shard row IDs disagree with inventory",
        );
        rows = new Map(data.map((row) => [row[0], row]));
        while (cache.size && cachedBytes + part.bytes > 16 * MiB) {
          const oldest = cache.keys().next().value;
          cache.delete(oldest);
          cachedBytes -= oldest.bytes;
        }
        cachedBytes += part.bytes;
      }
      cache.delete(part);
      cache.set(part, rows);
      for (const id of wanted) {
        if (rows.has(id)) result.set(id, rows.get(id));
        else check(table === "branches", "missing native reference");
      }
    }
    return result;
  }

  /** Return complete ordered native witnesses for the selected arcs, or an explicit missing status. */
  async function load(ids, index, signal) {
    check(ids.length <= 1024, "select at most 1024 net arcs");
    const request = { bytes: 0, signal };
    const branches = await records("branches", ids, request);
    const pipIds = new Set(),
      nodeIds = new Set();
    for (const [
      arc,
      [, from, to, status, start, edges, physical, localTie],
    ] of branches) {
      const ref = index.arcGeometry[arc];
      check(
        ref?.[2] === 0 && ref[0] === from && ref[1] === to,
        "arc endpoint mismatch",
      );
      check(
        Array.isArray(edges) &&
          edges.length <= 4096 &&
          edges.every(integer) &&
          new Set(edges).size === edges.length &&
          (resolved(status)
            ? integer(start)
            : [
                "disconnected_constant",
                "missing_endpoint",
                "unavailable",
              ].includes(status) &&
              start === null &&
              !edges.length) &&
          (status === "lut_permutation"
            ? typeof physical === "string" && edges.length
            : physical === null) &&
          (status === "disconnected_constant"
            ? typeof localTie === "string" && /\/(GND|VCC)_WIRE$/.test(localTie)
            : localTie === null),
        "invalid branch disposition",
      );
      for (const id of edges) pipIds.add(id);
      if (start !== null) nodeIds.add(start);
    }
    const pips = await records("pips", pipIds, request);
    const tile = (id) => integer(id) && id < m.tiles;
    const point = (id) => ({ x: id % m.width, y: Math.floor(id / m.width) });
    for (const [, from, to, at, numeric, native] of pips.values()) {
      check(
        integer(from) &&
          integer(to) &&
          tile(at) &&
          typeof numeric === "string" &&
          typeof native === "string",
        "invalid native PIP",
      );
      nodeIds.add(from);
      nodeIds.add(to);
    }
    const nodes = await records("nodes", nodeIds, request);
    for (const [, wire, members] of nodes.values())
      check(
        typeof wire === "string" &&
          Array.isArray(members) &&
          members.length > 0 &&
          members.every(([at, id]) => tile(at) && typeof id === "string"),
        "invalid wire footprint",
      );
    const result = new Map();
    for (const [
      arc,
      [, from, to, status, start, edges, physical, localTie],
    ] of branches) {
      const switches = edges.map((id) => pips.get(id));
      let cursor = start;
      const footprint = start === null ? [] : [nodes.get(start)];
      for (const [, a, b] of switches) {
        check(cursor === a, "disconnected fixed PIP chain");
        cursor = b;
        footprint.push(nodes.get(b));
      }
      if (status === "lut_permutation") {
        const router = footprint.at(-1)[1];
        check(
          /^SITEWIRE\/SLICE_X\d+Y\d+\/[ABCD][1-6]$/.test(physical) &&
            physical.slice(0, -1) === router.slice(0, -1) &&
            /^[1-6]$/.test(router.slice(-1)),
          "permuted LUT endpoint mismatch",
        );
      }
      const pin = (id) => {
        const [, x, y] = index.pinGeometry[id];
        return Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
      };
      const points = [pin(from), ...switches.map((p) => point(p[3])), pin(to)];
      const segments =
        resolved(status) && points.every(Boolean)
          ? points.slice(1).map((to, i) => ({
              from: points[i],
              to,
              kind: i === 0 || i === points.length - 2 ? "site" : "node",
            }))
          : [];
      result.set(arc, {
        status,
        physical,
        localTie,
        switches,
        footprint,
        segments,
        disposition: resolved(status) ? "resolved" : "unavailable",
      });
    }
    return result;
  }
  return { manifest: m, load };
}
