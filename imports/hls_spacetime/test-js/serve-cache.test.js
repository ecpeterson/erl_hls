import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm, utimes } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { createViewerServer } from "../scripts/serve.mjs";

test("prepared gzip and cache revalidation preserve the exact decoded artifact", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-cache-"));
  const file = join(root, "capture.json"),
    body = JSON.stringify({ value: "complete evidence" });
  await writeFile(file, body);
  await writeFile(file + ".gz", gzipSync(body));
  const server = createViewerServer(root);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}/data/capture.json`;
  try {
    const response = await fetch(url, {
      headers: { "accept-encoding": "gzip" },
    });
    assert.equal(response.headers.get("content-encoding"), "gzip");
    assert.equal(await response.text(), body);
    const plain = await fetch(url, {
      headers: { "accept-encoding": "gzip;q=0, *;q=1" },
    });
    assert.equal(plain.headers.get("content-encoding"), null);
    assert.equal(await plain.text(), body);
    const cached = await fetch(url, {
      headers: {
        "accept-encoding": "gzip",
        "if-none-match": response.headers.get("etag"),
      },
    });
    assert.equal(cached.status, 304);
    assert.equal(await cached.text(), "");
    const changed = JSON.stringify({ value: "changed source" });
    await writeFile(file, changed);
    const future = new Date(Date.now() + 2000);
    await utimes(file, future, future);
    const updated = await fetch(url, {
      headers: {
        "accept-encoding": "gzip",
        "if-none-match": response.headers.get("etag"),
      },
    });
    assert.equal(updated.status, 200);
    assert.equal(updated.headers.get("content-encoding"), null);
    assert.equal(await updated.text(), changed);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});
