/** Versioned tuple encoding removes repeated property names and native name strings
 * from derived geometry. Exact native identity remains in the retained source. */
const TYPES = ["tiles", "pips", "cells", "segments"];
const BOUNDARIES = [
  "sequential",
  "constant",
  "combinational",
  "unsupported",
  "external",
  "hard_block",
];
const SPANS = ["unresolved", "site", "node"];
function check(ok) {
  if (!ok) throw Error("Prepared geometry: invalid encoded primitive");
}
function integer(n) {
  return Number.isSafeInteger(n) && n >= 0;
}
function coordinate(n) {
  return Number.isFinite(n);
}
function point(x, y) {
  check(coordinate(x) && coordinate(y));
  return { x, y, physical: true };
}

/** Encode one complete raw-tile primitive; no geometry is rounded or sampled. */
export function encodePrimitive(row) {
  const code = TYPES.indexOf(row.type);
  if (code === 3)
    return [
      code,
      row.id,
      row.from.x,
      row.from.y,
      row.to.x,
      row.to.y,
      SPANS.indexOf(row.kind),
      row.sourceNet,
    ];
  return code === 2
    ? [
        code,
        row.id,
        row.point.x,
        row.point.y,
        row.sourceCell,
        BOUNDARIES.indexOf(row.boundary),
      ]
    : [code, row.id, row.point.x, row.point.y, row.sourceNet];
}

/** Decode exact fields; unknown encodings reject instead of guessing their role. */
export function decodePrimitive(row) {
  check(Array.isArray(row) && integer(row[0]) && row[0] < 4 && integer(row[1]));
  const [code, id] = row,
    type = TYPES[code];
  if (code === 3) {
    check(
      row.length === 8 &&
        integer(row[6]) &&
        row[6] < SPANS.length &&
        integer(row[7]),
    );
    return {
      type,
      id,
      from: point(row[2], row[3]),
      to: point(row[4], row[5]),
      kind: SPANS[row[6]],
      sourceNet: row[7],
    };
  }
  if (code === 2) {
    check(
      row.length === 6 &&
        integer(row[4]) &&
        integer(row[5]) &&
        row[5] < BOUNDARIES.length,
    );
    return {
      type,
      id,
      point: point(row[2], row[3]),
      sourceCell: row[4],
      boundary: BOUNDARIES[row[5]],
    };
  }
  check(row.length === 5 && integer(row[4]));
  return { type, id, point: point(row[2], row[3]), sourceNet: row[4] };
}
