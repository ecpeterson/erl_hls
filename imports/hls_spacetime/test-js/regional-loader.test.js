import test from "node:test";
import assert from "node:assert/strict";
import { loadRegionalWorker } from "../web/regional-loader.js";

function worker(t) {
  const original = globalThis.Worker;
  let instance;
  globalThis.Worker = class {
    constructor() {
      instance = this;
      this.terminated = 0;
    }
    postMessage(value) {
      this.request = value;
    }
    terminate() {
      this.terminated++;
    }
  };
  t.after(() => {
    globalThis.Worker = original;
  });
  return () => instance;
}
test("regional worker releases resources after success and forwards only provenance inputs", async (t) => {
  const current = worker(t),
    abort = new AbortController(),
    updates = [];
  const pending = loadRegionalWorker({
    entry: { file: "manifest.json" },
    view: { sha256: "a" },
    source: { sha256: "b" },
    baseUrl: "https://example.test/",
    signal: abort.signal,
    progress: (m) => updates.push(m),
  });
  const w = current();
  assert.equal(w.request.signal, undefined);
  w.onmessage({ data: { progress: "hashing" } });
  w.onmessage({ data: { result: { complete: true } } });
  assert.deepEqual(await pending, { complete: true });
  assert.deepEqual(updates, ["hashing"]);
  abort.abort();
  assert.equal(w.terminated, 1);
});
test("regional worker abort prevents stale result installation", async (t) => {
  const current = worker(t),
    abort = new AbortController();
  const pending = loadRegionalWorker({
    entry: { file: "manifest.json" },
    signal: abort.signal,
  });
  const w = current();
  abort.abort();
  w.onmessage({ data: { result: { stale: true } } });
  await assert.rejects(pending, { name: "AbortError" });
  assert.equal(w.terminated, 1);
});
test("absent regional data does not create a worker", async (t) => {
  const current = worker(t);
  assert.equal(await loadRegionalWorker({ entry: null }), null);
  assert.equal(current(), undefined);
});
