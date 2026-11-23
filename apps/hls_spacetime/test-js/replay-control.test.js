import test from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdtemp, rm, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { replayControl } from "../scripts/replay-control.mjs";
const bytes = await readFile(
  new URL("./fixtures/control-profile.json", import.meta.url),
);
test("offline model reports baseline and changed clocks with exact input identity", () => {
  const r = replayControl(bytes, { actors: ["a"], extraLatency: 1 });
  assert.equal(r.baseline.completion.cycle, 11);
  assert.equal(r.candidate.completion.cycle, 13);
  assert.equal(r.cycleDelta, 2);
  assert.equal(r.input.bytes, bytes.length);
  assert.match(r.input.sha256, /^[a-f0-9]{64}$/);
});
test("invalid bounded inputs and unknown interventions cannot produce a score", () => {
  assert.throws(
    () => replayControl(new Uint8Array(16 * 1024 * 1024 + 1)),
    /limit/,
  );
  assert.throws(
    () => replayControl(bytes, { actors: ["missing"], extraLatency: 1 }),
    /identities/,
  );
  assert.throws(
    () =>
      replayControl(bytes, {
        actors: ["a"],
        extraLatency: 1,
        targets: ["unknown"],
      }),
    /identities/,
  );
  assert.throws(() => replayControl(bytes, { endCycle: 1000002 }), /bounded/);
  const p = JSON.parse(bytes);
  p.actors[0].operations[0].batch.complete = false;
  const r = replayControl(Buffer.from(JSON.stringify(p)), {
    actors: ["a"],
    extraLatency: 1,
  });
  assert.equal(r.candidate.status, "censored");
  assert.equal(r.candidate.reason.kind, "incomplete_effects");
  assert.equal(r.candidate.completion, null);
});
test("CLI applies later options and creates output exclusively", async () => {
  const dir = await mkdtemp(join(tmpdir(), "spacetime-control-"));
  try {
    const input = join(dir, "profile.json"),
      output = join(dir, "report.json");
    await writeFile(input, bytes);
    const script = new URL("../scripts/replay-control.mjs", import.meta.url)
      .pathname;
    const args = [
      script,
      "--profile",
      input,
      "--output",
      output,
      "--actors",
      "a",
      "--extra-latency",
      "0",
      "--extra-latency",
      "1",
    ];
    const result = JSON.parse(
      execFileSync(process.execPath, args, { encoding: "utf8" }),
    );
    assert.equal(result.candidate.cycle, 13);
    const saved = await readFile(output);
    assert.throws(() =>
      execFileSync(process.execPath, args, { stdio: "pipe" }),
    );
    assert.deepEqual(await readFile(output), saved);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("known commit with unresolved future deliveries does not erase a completed public target", () => {
  const p = JSON.parse(bytes);
  p.actors.push({
    id: "future",
    slots: [{ kind: "unused" }],
    operations: [],
    initial: {
      owner: {
        pending: false,
        outbox: null,
        action: {
          privateCycle: 10,
          operation: {
            id: "future-work",
            kind: "action",
            accepted: false,
            nextPending: false,
            batch: {
              id: "unknown-future-batch",
              complete: false,
              deliveries: [],
            },
            dispatched: false,
            directive: 0,
            phaseBoundary: false,
          },
        },
      },
      inbox: {
        slotCount: 1,
        cursor: 0,
        held: null,
        postponed: [],
        released: [],
      },
    },
  });
  p.publishers.push({
    actor: "future",
    state: { recipientCount: 1, batchId: null, queues: [[]] },
  });
  const r = replayControl(Buffer.from(JSON.stringify(p)), {
    actors: [],
    extraLatency: 0,
  });
  assert.equal(r.baseline.completion.cycle, 11);
  assert.equal(
    r.baseline.events.find((e) => e.id === "future-work" && e.kind === "commit")
      .cycle,
    11,
  );
  assert.equal(
    r.baseline.waiting.owners.find((o) => o.actor === "future").outbox,
    "unknown-future-batch",
  );
});
