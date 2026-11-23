import test from "node:test";
import assert from "node:assert/strict";
import { cachePaint } from "../web/paint-cache.js";

function paint(tiles = 0, pips = 0, cells = 0, segments = 0) {
  return Object.fromEntries(
    Object.entries({ tiles, pips, cells, segments }).map(([name, size]) => [
      name,
      new Array(size).fill({}),
    ]),
  );
}

test("cache budgets count all primitive categories and evict complete oldest entries", () => {
  const cache = new Map(),
    limits = { maxRows: 7, maxEntries: 3 };
  const first = paint(1, 1, 1, 1),
    second = paint(0, 0, 1, 1),
    third = paint(2);
  assert.equal(cachePaint(cache, "first", first, limits), first);
  cachePaint(cache, "second", second, limits);
  cachePaint(cache, "third", third, limits);
  assert.deepEqual([...cache.keys()], ["second", "third"]);
  assert.equal(cache.get("second"), second);
  assert.equal(cache.get("third"), third);
  cachePaint(cache, "fourth", paint(1), { maxRows: 7, maxEntries: 2 });
  assert.deepEqual([...cache.keys()], ["third", "fourth"]);
});

test("oversized paint is returned complete without displacing unrelated entries", () => {
  const cache = new Map(),
    limits = { maxRows: 2, maxEntries: 2 };
  const small = paint(1),
    large = paint(0, 0, 0, 3);
  cachePaint(cache, "small", small, limits);
  assert.equal(cachePaint(cache, "large", large, limits), large);
  assert.equal(large.segments.length, 3);
  assert.deepEqual([...cache.keys()], ["small"]);
  assert.equal(cachePaint(cache, "small", large, limits), large);
  assert.equal(cache.size, 0);
});

test("replacement, explicit clear, zero limits and empty paints keep budgets accurate", () => {
  const cache = new Map(),
    limits = { maxRows: 3, maxEntries: 2 };
  cachePaint(cache, "a", paint(2), limits);
  cachePaint(cache, "b", paint(1), limits);
  cachePaint(cache, "a", paint(1), limits);
  assert.deepEqual([...cache.keys()], ["b", "a"]);
  cache.clear();
  cachePaint(cache, "c", paint(3), limits);
  assert.deepEqual([...cache.keys()], ["c"]);
  const disabled = new Map(),
    value = paint(1);
  assert.equal(cachePaint(disabled, "x", value, { maxRows: 0 }), value);
  assert.equal(
    cachePaint(disabled, "x", paint(), { maxEntries: 0 }).tiles.length,
    0,
  );
  assert.equal(disabled.size, 0);
  cachePaint(disabled, "empty", paint(), { maxRows: 0, maxEntries: 1 });
  assert.equal(disabled.size, 1);
  assert.throws(
    () => cachePaint(disabled, "x", value, { maxRows: -1 }),
    /budget/,
  );
});
