/** Parse/index off the UI thread. Bytes are transferred, never cloned. A
 * superseded load is terminated and cannot install a stale recording. */
export function loadRecording(
  bytes,
  {
    signal,
    workerFactory = () =>
      new Worker(new URL("./recording-worker.js", import.meta.url), {
        type: "module",
      }),
  } = {},
) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Load cancelled", "AbortError"));
      return;
    }
    const worker = workerFactory();
    let done = false;
    const finish = (error, result) => {
      if (done) return;
      done = true;
      signal?.removeEventListener("abort", abort);
      worker.terminate();
      error ? reject(error) : resolve(result);
    };
    const abort = () =>
      finish(new DOMException("Load cancelled", "AbortError"));
    signal?.addEventListener("abort", abort, { once: true });
    worker.onmessage = ({ data }) =>
      data.error ? finish(new Error(data.error)) : finish(null, data.result);
    worker.onerror = (event) =>
      finish(new Error(event.message || "Recording worker failed"));
    worker.postMessage(bytes, [bytes]);
  });
}
