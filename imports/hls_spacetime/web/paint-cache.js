/** Cache complete paint unions by primitive count, not just entry count. Eviction
 * discards reusable work only; oversized paints are returned whole and uncached. */
const TABLES = ["tiles", "pips", "cells", "segments"];

function primitiveCount(paint) {
  return TABLES.reduce((sum, name) => sum + paint[name].length, 0);
}

/** Store under both budgets, evicting the oldest entries first. The Map is the
 * sole cache authority, so caller clear/delete operations cannot stale a counter.
 * Limits are nonnegative integers; zero disables storage under that limit. */
export function cachePaint(
  cache,
  key,
  paint,
  { maxRows = 1_000_000, maxEntries = 64 } = {},
) {
  if (![maxRows, maxEntries].every((n) => Number.isSafeInteger(n) && n >= 0))
    throw Error("Invalid paint cache budget");
  const rows = primitiveCount(paint);
  cache.delete(key);
  if (!maxEntries || rows > maxRows) return paint;
  let total = rows;
  for (const value of cache.values()) total += primitiveCount(value);
  while (cache.size && (cache.size >= maxEntries || total > maxRows)) {
    const oldest = cache.keys().next().value;
    total -= primitiveCount(cache.get(oldest));
    cache.delete(oldest);
  }
  cache.set(key, paint);
  return paint;
}
