import test from "node:test";
import assert from "node:assert/strict";
import { circuitDisplay } from "../web/circuit-display.js";

const point = (x, y = 0) => ({ x, y, physical: true });
const cost = (value = 1, key = "word") => ({
  role: "data",
  computationKey: key,
  computationShared: false,
  computationUnknown: false,
  registeredPathDelayNs: value,
  staticPathDelayNs: value,
  registeredPathTimingUnknown: value === null,
  staticPathTimingUnknown: value === null,
  registeredPathApplicable: true,
  staticPathApplicable: true,
});
const segment = (from, to, metadata = {}) => ({
  from: point(...from),
  to: point(...to),
  kind: "node",
  ...cost(),
  ...metadata,
});
const paint = (tables) => ({
  tiles: [],
  pips: [],
  cells: [],
  segments: [],
  ...tables,
});

test("coincident point aggregates retain types, metadata and counts without native identity", () => {
  const input = paint({
    cells: [
      {
        id: 1,
        sourceCell: 9,
        point: point(1, 2),
        boundary: "sequential",
        ...cost(1, "a"),
      },
      {
        id: 2,
        sourceCell: 10,
        point: point(1, 2),
        boundary: "combinational",
        ...cost(3, "b"),
        role: "enable",
      },
    ],
    pips: [{ id: 3, sourceNet: 4, point: point(1, 2), ...cost(2) }],
    tiles: [{ id: 4, sourceNet: 5, point: point(1, 2), ...cost(2) }],
  });
  const before = structuredClone(input),
    output = circuitDisplay(input),
    cell = output.cells[0];
  assert.deepEqual(input, before);
  assert.equal(output.cells.length, 1);
  assert.equal(output.pips.length, 1);
  assert.equal(output.tiles.length, 1);
  assert.equal(cell.contributors, 2);
  assert.equal(cell.role, "mixed");
  assert.equal(cell.computationKey, null);
  assert.equal(cell.computationShared, true);
  assert.equal(cell.registeredPathDelayNs, 3);
  assert.equal(cell.registeredPathTimingUnknown, false);
  assert.equal(cell.boundary, "mixed");
  assert.deepEqual(cell.boundaries, ["combinational", "sequential"]);
  for (const key of ["id", "sourceCell", "sourceNet", "color"])
    assert.equal(key in cell, false);
  assert.deepEqual(output.displaySummary, {
    input: { tiles: 1, pips: 1, cells: 2, segments: 0 },
    output: { tiles: 1, pips: 1, cells: 1, segments: 0 },
    zeroLengthSegments: 0,
    filteredUnresolvedSegments: 0,
  });
  assert.equal(circuitDisplay(input), output);
  assert.notEqual(circuitDisplay(structuredClone(input)), output);
});

test("unknown contributors dominate membership and eligible timing, while outside costs are ignored", () => {
  const rows = [
    { point: point(0), ...cost(2, "known") },
    {
      point: point(0),
      ...cost(99, null),
      registeredPathApplicable: false,
      staticPathApplicable: false,
    },
    { point: point(0), ...cost(null, "known"), staticPathApplicable: false },
  ];
  const forward = circuitDisplay(paint({ cells: rows })).cells[0];
  const reverse = circuitDisplay(paint({ cells: [...rows].reverse() }))
    .cells[0];
  assert.deepEqual(forward, reverse);
  assert.equal(forward.contributors, 3);
  assert.equal(forward.computationKey, null);
  assert.equal(forward.computationShared, false);
  assert.equal(forward.computationUnknown, true);
  assert.equal(forward.registeredPathDelayNs, 2);
  assert.equal(forward.registeredPathTimingUnknown, true);
  assert.equal(forward.registeredPathApplicable, true);
  assert.equal(forward.staticPathDelayNs, 2);
  assert.equal(forward.staticPathTimingUnknown, false);
  const outside = circuitDisplay(paint({ cells: [rows[1]] })).cells[0];
  assert.equal(outside.registeredPathDelayNs, null);
  assert.equal(outside.registeredPathTimingUnknown, false);
  assert.equal(outside.registeredPathApplicable, false);
});

test("axis sweep splits partial overlap without double drawing or retaining departed costs", () => {
  const output = circuitDisplay(
    paint({
      segments: [
        segment([0, 0], [4, 0], cost(1, "a")),
        segment([2, 0], [6, 0], {
          ...cost(3, "b"),
          kind: "site",
          role: "enable",
        }),
        segment([6, 0], [7, 0], cost(0, "c")),
        segment([9, 0], [9, 0]),
      ],
    }),
  );
  assert.deepEqual(
    output.segments.map((row) => [
      row.from.x,
      row.to.x,
      row.contributors,
      row.registeredPathDelayNs,
    ]),
    [
      [0, 2, 1, 1],
      [2, 4, 2, 3],
      [4, 6, 1, 3],
      [6, 7, 1, 0],
    ],
  );
  assert.equal(output.segments[1].computationShared, true);
  assert.equal(output.segments[1].role, "mixed");
  assert.equal(output.segments[1].kind, "site");
  assert.equal(output.segments[1].schematic, true);
  assert.equal(output.segments[3].computationKey, "c");
  assert.equal(output.segments[3].schematic, true);
  assert.equal(output.displaySummary.zeroLengthSegments, 1);
});

test("source-to-sink orientation survives descending spans; conflicting directions stay explicit", () => {
  const same = circuitDisplay(
    paint({
      segments: [
        segment([2, 4], [2, 0]),
        segment([2, 4], [2, 0], { ...cost(2), kind: "unresolved" }),
      ],
    }),
  ).segments[0];
  assert.deepEqual(same.from, point(2, 4));
  assert.deepEqual(same.to, point(2, 0));
  assert.equal(same.directionUnknown, false);
  assert.equal(same.kind, "unresolved");
  assert.equal(same.schematic, true);
  const mixed = circuitDisplay(
    paint({ segments: [segment([0, 0], [3, 0]), segment([2, 0], [1, 0])] }),
  ).segments;
  assert.deepEqual(
    mixed.map((row) => [row.from.x, row.to.x, row.directionUnknown]),
    [
      [0, 1, false],
      [1, 2, true],
      [2, 3, false],
    ],
  );
  const explicit = circuitDisplay(
    paint({ segments: [segment([0, 0], [1, 0], { directionUnknown: true })] }),
  ).segments[0];
  assert.equal(explicit.directionUnknown, true);
});

test("diagonals deduplicate exact reversals only and never acquire invented bends", () => {
  const output = circuitDisplay(
    paint({
      segments: [
        segment([0, 0], [2, 2]),
        segment([2, 2], [0, 0]),
        segment([1, 1], [3, 3]),
      ],
    }),
  );
  assert.equal(output.segments.length, 2);
  assert.deepEqual(
    output.segments.map((row) => [row.from, row.to]),
    [
      [point(0, 0), point(2, 2)],
      [point(1, 1), point(3, 3)],
    ],
  );
  assert.equal(output.segments[0].contributors, 2);
  assert.equal(output.segments[0].directionUnknown, true);
  assert.equal(output.segments[1].directionUnknown, false);
  assert(output.segments.every((row) => row.schematic));
});

test("hiding unresolved spans before aggregation preserves coincident resolved evidence", () => {
  const input = paint({
    segments: [
      segment([0.125, 0.25], [1.25, 0.25], cost(2, "known")),
      segment([0.125, 0.25], [1.25, 0.25], {
        ...cost(null, null),
        kind: "unresolved",
      }),
    ],
  });
  const all = circuitDisplay(input);
  assert.equal(all.segments[0].kind, "unresolved");
  assert.equal(all.segments[0].computationUnknown, true);
  assert.equal(all.segments[0].registeredPathTimingUnknown, true);
  const visible = circuitDisplay(input, { includeUnresolved: false });
  assert.notEqual(visible, all);
  assert.equal(visible.segments.length, 1);
  assert.equal(visible.segments[0].kind, "node");
  assert.equal(visible.segments[0].contributors, 1);
  assert.equal(visible.segments[0].computationKey, "known");
  assert.equal(visible.segments[0].registeredPathDelayNs, 2);
  assert.equal(visible.segments[0].registeredPathTimingUnknown, false);
  assert.deepEqual(visible.segments[0].from, point(0.125, 0.25));
  assert.deepEqual(visible.segments[0].to, point(1.25, 0.25));
  assert.equal(visible.displaySummary.input.segments, 2);
  assert.equal(visible.displaySummary.filteredUnresolvedSegments, 1);
  assert.equal(circuitDisplay(input), all);
  assert.equal(circuitDisplay(input, { includeUnresolved: false }), visible);
});
