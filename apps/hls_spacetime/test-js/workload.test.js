import assert from "node:assert/strict";
import test from "node:test";
import {
  decodeFlow,
  decodeOutputActivity,
  missingFlowDrivers,
} from "../web/workload-flow.js";
import { probeState, windowStart, unionMasks } from "../web/workload-model.js";

test("output activity validates row bindings and the complete cycle inventory", () => {
  const rows = Uint8Array.from([1, 0, 255, 255]);
  const changes = Uint8Array.from([0, 2]);
  assert.deepEqual(
    [...decodeOutputActivity(rows, changes, 2, 2, 2).lanes],
    [1, -1],
  );
  assert.throws(() => decodeOutputActivity(rows, changes, 1, 2, 2), /lane/);
  assert.throws(() => decodeOutputActivity(rows, changes, 2, 2, 3), /activity/);
});

test("coverage compares changed primitives with outgoing net rows across the replay", () => {
  const data = new DataView(new ArrayBuffer(48));
  // Cell 1 drives two nets. A local arc at cell 2 supplies no outgoing net.
  [1, 1, 2].forEach((driver, i) => data.setUint32(i * 16, driver, true));
  const types = [0, 1, 0, 1, 0];
  const names = ["ram0", "ff0", "ram1", "ff1", "ram2"];
  const compare = (mask) =>
    missingFlowDrivers(
      { nets: 2, data },
      types,
      ["RAM", "FF"],
      names,
      Uint8Array.from(mask),
    );
  // Cell 3 only had unknown comparisons. Cell 4 stayed steady.
  assert.deepEqual(compare([0b00111, 0b01000]), [
    { kind: "RAM", count: 2, example: "ram0" },
  ]);
  assert.deepEqual(compare([0, 0xff]), []);
  assert.throws(() => compare([1]), /mask/);
});

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

test("routed flow keeps an unresolved branch distinct from direct and located branches", () => {
  const bytes = new Uint8Array(48);
  const data = new DataView(bytes.buffer);
  for (let i = 0; i < 3; i++) {
    data.setUint32(i * 16 + 4, 1, true);
    data.setFloat32(i * 16 + 12, 1.5, true);
  }
  const routes = Uint8Array.from([255, 255, 0, 0, 2, 0, 6, 0, 3, 0]);
  const decode = (r) =>
    decodeFlow(bytes, 2, r, 3, 7, new Uint8Array(6), [["Q", "D"]]);
  const model = decode(routes);
  assert.deepEqual(Array.from(model.offsets), [0, 1, 2]);
  assert.deepEqual(Array.from(model.words), [65535, 0, 2, 6, 3]);
  assert.equal(model.top, 1.5);
  assert.throws(() => decode(routes.subarray(0, 8)), /Incomplete switch/);
  data.setUint32(0, 2, true);
  assert.throws(() => decode(routes), /endpoint/);
});

test("one SDF row can drive two physical RAM pins by different routes", () => {
  const decode = (paths) =>
    decodeFlow(
      new Uint8Array(16),
      1,
      Uint8Array.from([2, 0, 1, 0, 2, 0]),
      1,
      5,
      new Uint8Array(2),
      [["O", "WE"]],
      paths,
    );
  const first = { sink: "RAM/WE0" },
    second = { sink: "RAM/WE1", tiles: [1, 4] };
  const m = decode({ 0: [first, second] });
  assert.equal(m.nets, 1);
  assert.deepEqual(
    m.branches.get(0).map((b) => [...b.tiles]),
    [
      [1, 2],
      [1, 4],
    ],
  );
  assert.throws(() => decode({ 0: [first, first] }), /sink/);
  assert.throws(
    () => decode({ 0: [first, { ...second, tiles: [5] }] }),
    /tiles/,
  );
  assert.throws(() => decode({ 1: [first] }), /row/);
});

test("placement timing retains packed ports with unknown route geometry", () => {
  const bytes = new Uint8Array(32);
  const pins = Uint8Array.from([0, 0, 1, 0]);
  const ports = [
    ["Q", "A1"],
    ["A1", "O6"],
  ];
  const model = decodeFlow(bytes, 2, undefined, 1, 8, pins, ports);
  assert.equal(model.nets, 1);
  assert.deepEqual(model.ports[model.pairs[1]], ["A1", "O6"]);
  assert.equal(model.offsets, undefined);
  assert.throws(
    () => decodeFlow(bytes, 2, undefined, 3, 8, pins, ports),
    /pin inventory/,
  );
  assert.throws(
    () => decodeFlow(bytes, 2, undefined, 1, 8, pins, ports.slice(0, 1)),
    /port pair/,
  );
});
