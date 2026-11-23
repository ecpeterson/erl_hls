import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadStepEvidence } from "../web/step-evidence-loader.js";

/** Exact descriptors bind one small sidecar to an already loaded recording. */
function fixture() {
  const recording = { bytes: 123, sha256: "a".repeat(64) },
    payload = {
      format: "spacetime-step-evidence",
      schema: 1,
      recording,
      clockReference: { validation: "deferred to model" },
      stepComparison: { validation: "deferred to model" },
    },
    calls = [];
  const options = (value = payload) => {
    const bytes = Buffer.isBuffer(value)
      ? value
      : Buffer.from(JSON.stringify(value));
    return {
      entry: {
        file: "evidence/step-1.json",
        bytes: bytes.length,
        sha256: createHash("sha256").update(bytes).digest("hex"),
      },
      recording,
      baseUrl: "https://example.test/data/",
      fetcher: async (url, options) => {
        calls.push({ url, options });
        return new Response(bytes);
      },
    };
  };
  return { recording, payload, calls, options };
}

test("sidecar verifies nested relative publication and recording identity before returning", async () => {
  const f = fixture(),
    controller = new AbortController();
  const result = await loadStepEvidence({
    ...f.options(),
    signal: controller.signal,
  });
  assert.deepEqual(result, f.payload);
  assert.equal(f.calls.length, 1);
  assert.equal(
    f.calls[0].url,
    "https://example.test/data/evidence/step-1.json",
  );
  assert.equal(f.calls[0].options.redirect, "error");
  assert.equal(f.calls[0].options.signal, controller.signal);
  assert.equal(await loadStepEvidence({ entry: null }), null);
  assert.equal(await loadStepEvidence({}), null);
});

test("unsafe paths, oversized descriptors and invalid loaded identities reject before fetch", async () => {
  for (const file of [
    "../outside.json",
    "/outside.json",
    "//other.test/a.json",
    "https://other.test/a.json",
    "data/%2e%2e/a.json",
    "a\\b.json",
    "a//b.json",
    "a.json?redirect=1",
    "a.json#other",
  ]) {
    const f = fixture(),
      options = f.options();
    options.entry.file = file;
    await assert.rejects(loadStepEvidence(options), /path/);
    assert.equal(f.calls.length, 0);
  }
  for (const change of [
    { bytes: 1 },
    { bytes: 1024 * 1024 + 1 },
    { bytes: 2.5 },
    { sha256: "unknown" },
  ]) {
    const f = fixture(),
      options = f.options();
    Object.assign(options.entry, change);
    await assert.rejects(loadStepEvidence(options), /descriptor/);
    assert.equal(f.calls.length, 0);
  }
  const f = fixture(),
    options = f.options();
  options.recording = { bytes: 123, sha256: "unknown" };
  await assert.rejects(loadStepEvidence(options), /recording identity/);
  assert.equal(f.calls.length, 0);
});

test("foreign recordings, unexpected fields and malformed envelopes reject", async () => {
  for (const mutate of [
    (p) => {
      p.format = "other";
    },
    (p) => {
      p.schema = 2;
    },
    (p) => {
      p.recording = { ...p.recording, bytes: 124 };
    },
    (p) => {
      p.recording = { ...p.recording, sha256: "b".repeat(64) };
    },
    (p) => {
      p.bundle = {};
    },
    (p) => {
      delete p.recording;
    },
  ]) {
    const f = fixture(),
      payload = structuredClone(f.payload);
    mutate(payload);
    await assert.rejects(
      loadStepEvidence(f.options(payload)),
      /Step evidence:/,
    );
  }
  for (const value of [[], null, 2])
    await assert.rejects(
      loadStepEvidence(fixture().options(value)),
      /unsupported payload|descriptor/,
    );
});

test("size and digest precede UTF-8 and JSON decoding", async () => {
  const f = fixture(),
    wrongHash = f.options(Buffer.from([0xff, 0xff]));
  wrongHash.entry.sha256 = "f".repeat(64);
  await assert.rejects(loadStepEvidence(wrongHash), /digest mismatch/);
  await assert.rejects(
    loadStepEvidence(f.options(Buffer.from([0xff, 0xff]))),
    /encoded data/,
  );
  await assert.rejects(
    loadStepEvidence(f.options(Buffer.from("no-json"))),
    SyntaxError,
  );
  const short = f.options();
  short.entry.bytes++;
  await assert.rejects(loadStepEvidence(short), /length mismatch/);
  let cancelled = false;
  const long = f.options();
  long.fetcher = async () =>
    new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(new Uint8Array(long.entry.bytes + 1));
        },
        cancel() {
          cancelled = true;
        },
      }),
    );
  await assert.rejects(loadStepEvidence(long), /exceeds declared bytes/);
  assert.equal(cancelled, true);
});

test("HTTP errors, redirected origins and absent bodies cannot supply evidence", async () => {
  const f = fixture();
  for (const response of [
    new Response("failed", { status: 404 }),
    new Response(null),
    Object.defineProperty(new Response("ignored"), "url", {
      value: "https://other.test/a.json",
    }),
  ])
    await assert.rejects(
      loadStepEvidence({ ...f.options(), fetcher: async () => response }),
      /Step evidence:/,
    );
});

test("aborted loads reject and cancel the active bounded reader", async () => {
  const f = fixture(),
    before = new AbortController();
  before.abort();
  await assert.rejects(
    loadStepEvidence({ ...f.options(), signal: before.signal }),
    { name: "AbortError" },
  );
  assert.equal(f.calls.length, 0);
  const during = new AbortController();
  let cancelled = false;
  const fetcher = async () =>
    new Response(
      new ReadableStream(
        {
          pull(controller) {
            controller.enqueue(new Uint8Array([123]));
            during.abort();
          },
          cancel() {
            cancelled = true;
          },
        },
        { highWaterMark: 0 },
      ),
    );
  await assert.rejects(
    loadStepEvidence({ ...f.options(), fetcher, signal: during.signal }),
    { name: "AbortError" },
  );
  assert.equal(cancelled, true);
});
