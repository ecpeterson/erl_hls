import test from "node:test";
import assert from "node:assert/strict";
import { spatialPoints, spatialPairs } from "../web/visibility.js";
import { accessConnections } from "../web/footprint.js";

const near = { physical: true, x: 0, y: 0 };
const far = { physical: true, x: 1, y: 1 };
const unknown = { physical: false, x: 2, y: 2 };

test("hide unknown portions without removing placed bits or changing source geometry", () => {
  const points = [near, unknown, far];
  assert.deepEqual(spatialPoints(points, true), [near, far]);
  assert.strictEqual(spatialPoints(points, false), points);
  assert.equal(points.length, 3);
});

test("logical layouts and the all-participants view retain unknown-endpoint links", () => {
  const pairs = [
    [near, unknown],
    [unknown, far],
  ];
  assert.strictEqual(
    spatialPairs(pairs, [near, unknown], [unknown, far], false),
    pairs,
  );
  assert.deepEqual(
    spatialPairs(pairs, [near, unknown], [unknown, far], true),
    [],
  );
});

test("an aggregate word position cannot locate an access selecting only unknown bits", () => {
  assert.deepEqual(spatialPairs([[near, far]], [unknown], [far], true), []);
  assert.deepEqual(spatialPairs([[near, far]], [near], [unknown], true), []);
  assert.deepEqual(spatialPairs([[near, far]], [near, unknown], [far], true), [
    [near, far],
  ]);
});

test("filtering a same-word dependency preserves established tile pairs, never fans", () => {
  const from = { access: { resource: "word" } };
  const to = { access: { kind: "read_request", resource: "word" } };
  const sources = [near, unknown],
    targets = [near, far, unknown];
  const connection = accessConnections(from, to, sources, targets);
  assert.equal(connection.aggregate, false);
  assert.deepEqual(spatialPairs(connection.pairs, sources, targets, true), [
    [near, near],
  ]);
});
