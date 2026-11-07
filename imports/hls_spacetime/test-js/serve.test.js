import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createViewerServer, parseArguments } from "../scripts/serve.mjs";

test("fresh view directory is independent of repository web/data", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-server-"));
  const server = createViewerServer(root);
  try {
    await writeFile(join(root, "index.json"), '{"fresh":true}');
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const data = await fetch(base + "/data/index.json");
    assert.deepEqual(await data.json(), { fresh: true });
    assert.equal((await fetch(base + "/")).status, 200);
    assert.equal((await fetch(base + "/data/..%2f..%2fsecret")).status, 404);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});

test("server option precedence and port validation", () => {
  assert.equal(parseArguments(["--port", "12", "--port", "34"]).port, 34);
  assert.throws(() => parseArguments(["--port", "70000"]), /Invalid port/);
});
