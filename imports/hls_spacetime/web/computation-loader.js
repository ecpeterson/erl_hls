/** Load complete, hash-bound shared native tables. Parts limit transfer size;
 * they never select a prefix of the computation or routing population. */
const TABLES = [
  "cells",
  "pins",
  "nets",
  "arcs",
  "bindings",
  "operations",
  "routeNets",
];
const MiB = 1024 * 1024;

/** Resolve a normalized relative JSON publication path. Used by capture indexes
 * and native attachments; schemes, traversal and encoded/empty segments reject. */
export function publicationUrl(file, base) {
  if (
    typeof file !== "string" ||
    !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file)
  )
    throw Error("Unsafe publication path");
  return new URL(file, base).href;
}

/** Read a bounded stream before decoding, then require the advertised bytes and
 * digest. A partial response cannot become a successfully loaded table. */
async function checkedJson(url, expected, limit, fetcher, signal) {
  if (
    !expected ||
    !Number.isSafeInteger(expected.bytes) ||
    expected.bytes < 2 ||
    expected.bytes > limit ||
    !/^[a-f0-9]{64}$/.test(expected.sha256)
  )
    throw Error("Invalid computation part descriptor");
  const response = await fetcher(url, { signal });
  if (!response.ok)
    throw Error(`Computation fetch failed (${response.status})`);
  const reader = response.body.getReader();
  const bytes = new Uint8Array(expected.bytes);
  let offset = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (offset + value.length > bytes.length)
        throw Error("Computation part exceeds declared bytes");
      bytes.set(value, offset);
      offset += value.length;
    }
  } catch (error) {
    await reader.cancel();
    throw error;
  }
  if (offset !== bytes.length) throw Error("Computation part length mismatch");
  const digest = [
    ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  ]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  if (digest !== expected.sha256)
    throw Error("Computation part digest mismatch");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

/** Verify a complete attachment before returning it. The view descriptor is the
 * exact recording already checked by the caller; no file-name association is
 * sufficient. Fetches are serial to bound transfer/parse memory. */
export async function loadComputations({
  entry,
  view,
  baseUrl,
  fetcher = fetch,
  signal,
  progress = () => {},
}) {
  if (!entry) return null;
  const url = publicationUrl(entry.file, baseUrl);
  const manifest = await checkedJson(url, entry, 4 * MiB, fetcher, signal);
  if (
    manifest.format !== "spacetime-computations-manifest" ||
    manifest.schema !== 1 ||
    manifest.view?.sha256 !== view.sha256 ||
    manifest.view?.bytes !== view.bytes
  )
    throw Error("Computation manifest does not bind this recording");
  if (
    !manifest.attachment ||
    manifest.attachment.schema !== 1 ||
    manifest.checkpoint !== manifest.attachment.checkpoint ||
    ["source", "rtl", "observation"].some(
      (key) => manifest.build?.[key] !== manifest.attachment.build?.[key],
    )
  )
    throw Error("Computation manifest identity mismatch");
  if (
    !Array.isArray(manifest.parts) ||
    manifest.parts.length > 1024 ||
    !manifest.totals ||
    Object.keys(manifest.totals).sort().join() !== [...TABLES].sort().join()
  )
    throw Error("Invalid computation table inventory");
  const tables = Object.fromEntries(TABLES.map((table) => [table, []]));
  let totalBytes = 0;
  const paths = new Set();
  for (const part of manifest.parts) {
    if (
      !TABLES.includes(part.table) ||
      paths.has(part.file) ||
      !Number.isSafeInteger(part.rows) ||
      part.rows < 0 ||
      !Number.isSafeInteger(part.bytes) ||
      part.bytes < 2 ||
      part.bytes > 32 * MiB
    )
      throw Error("Invalid computation table part");
    paths.add(part.file);
    totalBytes += part.bytes;
    if (totalBytes > 512 * MiB)
      throw Error("Computation attachment exceeds 512 MiB");
  }
  for (const [i, part] of manifest.parts.entries()) {
    progress(
      `Reading computation circuits (${i + 1}/${manifest.parts.length})…`,
    );
    const rows = await checkedJson(
      publicationUrl(part.file, url),
      part,
      32 * MiB,
      fetcher,
      signal,
    );
    if (!Array.isArray(rows) || rows.length !== part.rows)
      throw Error("Computation table row count mismatch");
    for (const row of rows) tables[part.table].push(row);
  }
  for (const table of TABLES)
    if (
      !Number.isSafeInteger(manifest.totals[table]) ||
      manifest.totals[table] !== tables[table].length
    )
      throw Error(`Incomplete computation table: ${table}`);
  const { routeNets, ...graph } = tables;
  return { attachment: { ...manifest.attachment, ...graph }, routeNets };
}
