import { loadRegionalData } from "./regional-data.js";

/** Explicitly requested regional loading; no background fetch at import time.
 * Abort terminates the worker, and every completion releases its resources. */
export function loadRegionalWorker(options) {
  if (!options.entry) return Promise.resolve(null);
  if (typeof Worker === "undefined" || options.fetcher)
    return loadRegionalData(options);
  return new Promise((resolve, reject) => {
    const worker = new Worker(
      new URL("./regional-worker.js", import.meta.url),
      { type: "module" },
    );
    let finished = false;
    const finish = (error, data) => {
      if (finished) return;
      finished = true;
      options.signal?.removeEventListener("abort", abort);
      worker.terminate();
      if (error) reject(error);
      else resolve(data);
    };
    const abort = () => finish(new DOMException("Aborted", "AbortError"));
    if (options.signal?.aborted) return abort();
    options.signal?.addEventListener("abort", abort, { once: true });
    worker.onerror = (event) => finish(Error(event.message));
    worker.onmessage = ({ data }) => {
      if (finished) return;
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
