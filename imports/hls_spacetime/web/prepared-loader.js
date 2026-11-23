/** Prepared rendering tables are independent, hash-bound derivatives. Their full
 * native source stays referenced; loading them does not claim to load that source. */
import { decodePrimitive } from "./prepared-format.js";
const TABLES = [
  "operations",
  "writes",
  "cones",
  "routes",
  "primitives",
  "pinGeometry",
  "arcGeometry",
];
const MiB = 1024 * 1024;

function check(ok, reason) {
  if (!ok) throw Error(`Prepared render: ${reason}`);
}
function url(file, base) {
  check(
    typeof file === "string" &&
      /^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(file),
    "unsafe part path",
  );
  return new URL(file, base).href;
}
/** Hash every received part before decoding it; memory bounds apply before reads. */
async function json(path, descriptor, limit, fetcher, signal) {
  check(
    descriptor &&
      Number.isSafeInteger(descriptor.bytes) &&
      descriptor.bytes >= 2 &&
      descriptor.bytes <= limit &&
      /^[0-9a-f]{64}$/.test(descriptor.sha256),
    "invalid descriptor",
  );
  const response = await fetcher(path, { signal });
  check(response.ok, `fetch failed (${response.status})`);
  const reader = response.body.getReader(),
    buffer = new Uint8Array(descriptor.bytes);
  let offset = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      check(
        offset + value.length <= buffer.length,
        "part exceeds declared bytes",
      );
      buffer.set(value, offset);
      offset += value.length;
    }
  } catch (error) {
    await reader.cancel();
    throw error;
  }
  check(offset === buffer.length, "part length mismatch");
  const digest = [
    ...new Uint8Array(await crypto.subtle.digest("SHA-256", buffer)),
  ]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  check(digest === descriptor.sha256, "part digest mismatch");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
}

/** Load the complete render derivative, without fetching the full source graph.
 * All requested parts are validated before returning; no partial success state. */
export async function loadPreparedRender({
  entry,
  view,
  source,
  baseUrl,
  fetcher = fetch,
  signal,
  progress = () => {},
}) {
  if (!entry) return null;
  const manifestUrl = url(entry.file, baseUrl),
    manifest = await json(manifestUrl, entry, 4 * MiB, fetcher, signal);
  check(
    manifest.format === "spacetime-render-manifest" &&
      manifest.schema === 1 &&
      manifest.algorithm === 4,
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
        (k) => source[k] === manifest.source?.[k],
      ) &&
      /^[0-9a-f]{64}$/.test(source.sha256) &&
      Number.isSafeInteger(source.bytes) &&
      source.bytes >= 2 &&
      source.bytes <= 4 * MiB,
    "source identity mismatch",
  );
  url(source.file, baseUrl);
  check(
    Array.isArray(manifest.parts) &&
      manifest.parts.length <= 1024 &&
      manifest.totals &&
      Object.keys(manifest.totals).sort().join() === [...TABLES].sort().join(),
    "invalid table inventory",
  );
  let total = 0;
  const paths = new Set();
  for (const part of manifest.parts) {
    check(
      (part.table === "primitives"
        ? part.encoding === "geometry-tuples-v1"
        : part.encoding === "json-rows-v1") &&
        TABLES.includes(part.table) &&
        !paths.has(part.file) &&
        Number.isSafeInteger(part.rows) &&
        part.rows >= 0 &&
        Number.isSafeInteger(part.bytes) &&
        part.bytes >= 2 &&
        part.bytes <= 32 * MiB,
      "invalid part",
    );
    paths.add(part.file);
    total += part.bytes;
  }
  check(total <= 256 * MiB, "render derivative exceeds 256 MiB");
  const tables = Object.fromEntries(TABLES.map((t) => [t, []]));
  for (const [i, part] of manifest.parts.entries()) {
    progress(`Reading prepared circuits (${i + 1}/${manifest.parts.length})…`);
    const rows = await json(
      url(part.file, manifestUrl),
      part,
      32 * MiB,
      fetcher,
      signal,
    );
    check(
      Array.isArray(rows) && rows.length === part.rows,
      "part row count mismatch",
    );
    for (const row of rows)
      tables[part.table].push(
        part.table === "primitives" ? decodePrimitive(row) : row,
      );
  }
  for (const name of TABLES)
    check(
      Number.isSafeInteger(manifest.totals[name]) &&
        tables[name].length === manifest.totals[name],
      `incomplete ${name}`,
    );
  return {
    ...manifest.render,
    format: "spacetime-prepared-render",
    schema: 1,
    algorithm: 4,
    source: manifest.source,
    view: manifest.view,
    ...tables,
  };
}

/** Browsers parse the derivative away from the UI thread. Older non-worker
 * environments use the same bounded reader; abort always invalidates the request. */
export function loadPreparedRenderWorker(options) {
  if (!options.entry) return Promise.resolve(null);
  if (typeof Worker === "undefined" || options.fetcher)
    return loadPreparedRender(options);
  return new Promise((resolve, reject) => {
    const worker = new Worker(
      new URL("./prepared-worker.js", import.meta.url),
      { type: "module" },
    );
    const finish = (error, data) => {
      options.signal?.removeEventListener("abort", abort);
      worker.terminate();
      if (error) reject(error);
      else resolve(data);
    };
    const abort = () => finish(new DOMException("Aborted", "AbortError"));
    if (options.signal?.aborted) {
      abort();
      return;
    }
    options.signal?.addEventListener("abort", abort, { once: true });
    worker.onerror = (e) => finish(Error(e.message));
    worker.onmessage = ({ data }) => {
      if (data.progress) options.progress?.(data.progress);
      else finish(data.error ? Error(data.error) : null, data.result);
    };
    worker.postMessage({
      entry: options.entry,
      view: options.view,
      source: options.source,
      baseUrl: options.baseUrl,
    });
  });
}
