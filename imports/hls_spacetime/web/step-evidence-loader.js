/** Load a small, independently published evidence sidecar without rewriting the
 * recording or its prepared tables. Hashes bind bytes and recording identity;
 * substantive STA and step validation remains the model's responsibility. */
import { publicationUrl } from "./computation-loader.js";

const MAX_BYTES = 1024 * 1024;
const FIELDS = new Set([
  "format",
  "schema",
  "recording",
  "clockReference",
  "stepComparison",
]);

function check(condition, reason) {
  if (!condition) throw Error(`Step evidence: ${reason}`);
}
function identity(value) {
  return (
    value &&
    Number.isSafeInteger(value.bytes) &&
    value.bytes >= 2 &&
    /^[0-9a-f]{64}$/.test(value.sha256)
  );
}

/** Read exactly the bounded descriptor, rejecting redirects and foreign response
 * origins. No response is decoded before its full byte count and hash match.
 * Cancelling the caller's load also cancels the active stream reader. */
async function readPayload(path, entry, fetcher, signal) {
  signal?.throwIfAborted();
  const response = await fetcher(path, { signal, redirect: "error" });
  if (signal?.aborted) {
    await response.body?.cancel().catch(() => {});
    signal.throwIfAborted();
  }
  check(response.ok, `fetch failed (${response.status})`);
  check(
    !response.url || new URL(response.url).origin === new URL(path).origin,
    "cross-origin response",
  );
  check(response.body?.getReader, "response has no readable body");
  const reader = response.body.getReader(),
    bytes = new Uint8Array(entry.bytes);
  let offset = 0;
  const abort = () => {
    void reader.cancel(signal.reason).catch(() => {});
  };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    for (;;) {
      signal?.throwIfAborted();
      const { done, value } = await reader.read();
      signal?.throwIfAborted();
      if (done) break;
      check(value instanceof Uint8Array, "invalid response chunk");
      check(
        offset + value.length <= bytes.length,
        "response exceeds declared bytes",
      );
      bytes.set(value, offset);
      offset += value.length;
    }
    check(offset === bytes.length, "response length mismatch");
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    signal?.removeEventListener("abort", abort);
    reader.releaseLock();
  }
  const digest = [
    ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  ]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  signal?.throwIfAborted();
  check(digest === entry.sha256, "response digest mismatch");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

/** Return null for an absent descriptor or a completely verified sidecar.
 * The supplied recording identity must describe bytes already loaded/verified by
 * the caller. A safe relative JSON path stays on that publication's origin;
 * payloads are at most 1 MiB and may not replace arbitrary recording fields.
 * Invalid evidence rejects as a whole; no partial clock or step data is returned. */
export async function loadStepEvidence({
  entry,
  recording,
  baseUrl,
  fetcher = fetch,
  signal,
}) {
  if (entry === undefined || entry === null) return null;
  check(identity(entry) && entry.bytes <= MAX_BYTES, "invalid descriptor");
  check(identity(recording), "invalid loaded recording identity");
  const path = publicationUrl(entry.file, baseUrl);
  check(
    ["http:", "https:"].includes(new URL(path).protocol),
    "unsupported publication scheme",
  );
  const payload = await readPayload(path, entry, fetcher, signal);
  check(
    payload &&
      !Array.isArray(payload) &&
      typeof payload === "object" &&
      payload.format === "spacetime-step-evidence" &&
      payload.schema === 1,
    "unsupported payload",
  );
  check(
    Object.keys(payload).every((key) => FIELDS.has(key)),
    "unknown payload field",
  );
  check(
    identity(payload.recording) &&
      payload.recording.bytes === recording.bytes &&
      payload.recording.sha256 === recording.sha256,
    "recording identity mismatch",
  );
  return payload;
}
