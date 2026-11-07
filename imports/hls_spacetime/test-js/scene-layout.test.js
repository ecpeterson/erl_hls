import test from "node:test";
import assert from "node:assert/strict";
import { clockPoint, sceneBounds, occupiedBins } from "../web/scene-layout.js";
import { loadRecording } from "../web/recording-loader.js";
test("time is an independent signed coordinate", () => {
  assert.deepEqual(clockPoint({ x: 4, y: 7 }, 12, 10, 5, 8), [4, 7, 0]);
  assert.deepEqual(clockPoint({ x: 4, y: 7 }, 13, 10, 5, 16), [4, 7, 0.2]);
});
test("overview preserves empty spatial gaps and clock separation", () => {
  const marks = [
    { position: [0, 0, 0] },
    { position: [0.001, 0.001, 0] },
    { position: [1, 1, 0] },
    { position: [0, 0, 1] },
  ];
  const bins = occupiedBins(marks, 0.1);
  assert.equal(bins.length, 3);
  assert.equal(bins[0].count, 2);
  assert.equal(
    bins.some((x) => x.position[0] > 0.2 && x.position[0] < 0.9),
    false,
  );
  assert.throws(() => occupiedBins(marks, 0));
});
test("fit bounds retain excursions and ignore missing coordinates", () => {
  const bounds = sceneBounds([
    [1, 2, 3],
    [-2, -5, 9],
    [NaN, 0, 0],
  ]);
  assert.deepEqual(bounds, { min: [-2, -5, 3], max: [1, 2, 9] });
  assert.ok(sceneBounds([]).min.every(Number.isFinite));
});
test("cancelled worker cannot replace the active capture", async () => {
  const controller = new AbortController();
  let terminated = 0,
    worker;
  const promise = loadRecording(new ArrayBuffer(4), {
    signal: controller.signal,
    workerFactory: () =>
      (worker = {
        terminate() {
          terminated++;
        },
        postMessage() {},
      }),
  });
  controller.abort();
  await assert.rejects(promise, { name: "AbortError" });
  worker.onmessage({ data: { result: { model: "stale" } } });
  assert.ok(terminated >= 1);
});

test("overview combines roles and delay bounds independently of input order or precolored marks", () => {
  const marks = [
    {
      position: [0.001, 0.001, 0],
      role: "data",
      delayNs: 1,
      timingUnknown: false,
      color: "#123456",
    },
    {
      position: [0.002, 0.002, 0],
      role: "enable",
      delayNs: 4,
      timingUnknown: false,
      color: "#abcdef",
    },
  ];
  const [bin] = occupiedBins(marks, 0.1),
    [reversed] = occupiedBins([...marks].reverse(), 0.1);
  assert.deepEqual(bin, reversed);
  assert.equal(bin.role, "mixed");
  assert.equal(bin.delayNs, 4);
  assert.equal(bin.timingUnknown, false);
  assert.equal(bin.count, 2);
  assert.equal(Object.hasOwn(bin, "color"), false);
  assert.equal(marks[0].color, "#123456");
});

test("overview retains unknown contributors alongside a known maximum, including a flagged partial bound", () => {
  for (const extra of [
    { delayNs: null },
    { delayNs: NaN },
    { delayNs: Infinity },
    { delayNs: 3, timingUnknown: true },
  ]) {
    const [bin] = occupiedBins([
      { position: [0, 0, 0], role: "data", delayNs: 2 },
      { position: [0.001, 0, 0], role: "data", ...extra },
    ]);
    assert.equal(bin.role, "data");
    assert.equal(bin.timingUnknown, true);
    assert.equal(bin.delayNs, Number.isFinite(extra.delayNs) ? 3 : 2);
  }
  const [zero] = occupiedBins([
    { position: [0, 0, 0], role: "data", delayNs: 0 },
  ]);
  assert.equal(zero.delayNs, 0);
  assert.equal(zero.timingUnknown, false);
  const [unannotated] = occupiedBins([{ position: [0, 0, 0] }]);
  assert.equal(unannotated.count, 1);
  assert.equal(unannotated.delayNs, null);
  assert.equal(unannotated.timingUnknown, true);
});
