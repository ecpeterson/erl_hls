import { createModel } from "./model.js";

/** Decode and validate one complete saved recording. This runs in a worker in
 * the browser; the pure entrypoint also supports bounded local fixtures. */
export function prepareRecording(bytes) {
  if (!(bytes instanceof ArrayBuffer) || bytes.byteLength > 128 * 1024 * 1024)
    throw Error("Recording exceeds 128 MiB or has invalid bytes");
  const started = performance.now();
  const document = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  const parsed = performance.now();
  const model = createModel(document);
  return {
    model,
    timings: { parseMs: parsed - started, indexMs: performance.now() - parsed },
  };
}
