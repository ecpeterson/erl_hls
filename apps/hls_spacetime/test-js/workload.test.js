import assert from "node:assert/strict";
import test from "node:test";
import { probeState, windowStart, unionMasks } from "../web/workload-model.js";

test("a known inactive valid is idle even when ready is unknown", () => {
  const bits = Uint8Array.from([0b1011, 0b0111, 0b1001, 0b0011]);
  assert.deepEqual(
    [0, 1, 2, 3].map((i) => probeState(bits, 4, 0, i)),
    [1, 2, 0, 3],
  );
});
test("an eight-clock history at reset has a baseline only until the second clock", () => {
  assert.deepEqual(
    [0, 1, 7, 8, 9].map((c) => windowStart(c, 8)),
    [0, 1, 1, 1, 2],
  );
});
test("unions spanning chunks preserve overlaps, skip unrelated rows and reject truncation", () => {
  const chunks = [
    Uint8Array.from([1, 0, 2, 2]),
    Uint8Array.from([4, 8, 16, 0]),
  ];
  assert.deepEqual(Array.from(unionMasks(chunks, 1, 2, 2, 1)), [6, 10]);
  assert.throws(() => unionMasks(chunks.slice(0, 1), 1, 2, 2, 1), /Incomplete/);
});
