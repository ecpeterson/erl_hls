import test from "node:test";
import assert from "node:assert/strict";
import {
  computationSelection,
  computationWindowUnion,
} from "../web/computation-view.js";

test("multi-event selections exclude filtered seeds before resolving producer writes", () => {
  const a = { id: "producer-a", cycle: 8, actor: "a" };
  const b = { id: "producer-b", cycle: 9, actor: "b" };
  const seeds = [a, b];
  assert.deepEqual(computationSelection(seeds, [a]), [a]);
  assert.deepEqual(computationSelection(seeds, []), []);
  assert.equal(computationSelection(seeds, [a])[0], a);
  assert.deepEqual(seeds, [a, b]);
});

test("flat footprint unions repeated clocks while preserving overlapping role cones", () => {
  const data = { id: "sink/data", role: "data", arcIndices: [1, 2] };
  const enable = { id: "sink/enable", role: "enable", arcIndices: [2, 3] };
  const layers = [
    { cycle: 8, cones: [data], arcs: [1, 2], operations: [{ event: "w0" }] },
    {
      cycle: 9,
      cones: [data, enable],
      arcs: [1, 2, 3],
      operations: [{ event: "w0" }, { event: "w1" }, { event: "w2" }],
    },
    { cycle: 10, cones: [enable], arcs: [2, 3], operations: [{ event: "w3" }] },
  ];
  const before = structuredClone(layers);
  const union = computationWindowUnion(layers);
  assert.deepEqual(union.operations, [
    { event: "w0" },
    { event: "w1" },
    { event: "w2" },
    { event: "w3" },
  ]);
  assert.deepEqual(union.arcs, [1, 2, 3]);
  assert.deepEqual(union.cones, [data, enable]);
  assert.equal(union.cones[0], data);
  assert.equal(union.cones[1], enable);
  assert.deepEqual(layers, before);
  assert.deepEqual(computationWindowUnion([]), {
    cones: [],
    arcs: [],
    operations: [],
  });
});
