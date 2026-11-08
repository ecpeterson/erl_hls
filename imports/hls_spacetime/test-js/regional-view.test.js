import assert from "node:assert/strict";
import test from "node:test";
import {
  regionalView,
  regionalScene,
  regionalBinAt,
  regionalCountColor,
  REGIONAL_COLORS,
} from "../web/regional-view.js";
import { UNKNOWN_COLOR } from "../web/perceptual-color.js";

function fixture() {
  const bounds = (x, y) => ({
    minX: x * 16,
    maxX: (x + 1) * 16,
    minY: y * 16,
    maxY: (y + 1) * 16,
  });
  return {
    binSize: 16,
    cells: [
      { id: "a", kind: "LUT6", x: 1, y: 2, bin: 0 },
      { id: "b", kind: "FDRE", x: 1, y: 2, bin: 0 },
      { id: "c", kind: "LUT6", x: 33, y: 2, bin: 1 },
      { id: "unplaced", kind: "LUT6", x: null, y: null, bin: null },
    ],
    pips: [
      { id: "p0", x: 2, y: 3, nets: [0] },
      { id: "p1", x: 34, y: 3, nets: [0, 1] },
      { id: "p2", x: 35, y: 3, nets: [1] },
    ],
    nets: [
      { id: "n0", bins: [0, 1], pips: [0, 1], unknownWires: ["w-unknown"] },
      { id: "n1", bins: [1], pips: [1, 2], unknownWires: [] },
    ],
    arcNets: [0, null, 1],
    bins: [
      {
        x: 0,
        y: 0,
        bounds: bounds(0, 0),
        cells: [0, 1],
        pips: [0],
        nets: [0],
        counts: { cells: 2, pips: 1, nets: 1 },
        primitiveKinds: { LUT6: 1, FDRE: 1 },
      },
      {
        x: 2,
        y: 0,
        bounds: bounds(2, 0),
        cells: [2],
        pips: [1, 2],
        nets: [0, 1],
        counts: { cells: 1, pips: 2, nets: 2 },
        primitiveKinds: { LUT6: 1 },
      },
    ],
    maxima: {
      cells: 2,
      pips: 2,
      nets: 2,
      primitiveKinds: { LUT6: 1, FDRE: 1 },
    },
    summary: { unknownWirePositions: 1, unlocatedCells: 1 },
  };
}
function neighborhood() {
  const native = fixture().cells;
  const catalogue = [native[1], native[2], native[3], native[0]];
  return {
    cells: [
      { index: 3, cell: catalogue[3], kind: "family" },
      { index: 0, cell: catalogue[0], kind: "context" },
    ],
    selection: new Map([
      [2, { arcIds: new Set([0, 1]) }],
      [3, { arcIds: new Set([0]) }],
    ]),
  };
}
const computationIndex = {
  arcGeometry: [
    [0, 1, 0],
    [1, 2, 1],
    [2, 3, 0],
  ],
  pinGeometry: [
    [0, 1, 2, "a/O"],
    [2, 33, 2, "c/I"],
    [2, 33, 2, "c/O"],
    [null, null, null, "port"],
  ],
};
const sceneOptions = {
  cycle: 12,
  point: ({ x, y }) => ({ x: x / 100, y: y / 100 }),
  world: ({ x, y }, cycle) => [x, -cycle, y],
};

test("regional values use a fixed full-capture domain across selections", () => {
  const data = fixture();
  const before = structuredClone(data);
  const all = regionalView(data);
  const selected = regionalView(data, { selectedBin: 0, selectedNet: 0 });
  assert.deepEqual(all.domain, { min: 0, max: 2, label: "Distinct used PIPs" });
  assert.deepEqual(
    all.bins.map((row) => row.color),
    selected.bins.map((row) => row.color),
  );
  assert.deepEqual(
    all.bins.map((row) => row.value),
    [1, 2],
  );
  assert.equal(all.summary.total, 3);
  assert.deepEqual(data, before);
});

test("native identity deduplicates family arcs, nets and shared PIPs", () => {
  const result = regionalView(fixture(), {
    neighborhood: neighborhood(),
    computationIndex,
  });
  assert.deepEqual([...result.family.nets], [0]);
  assert.deepEqual([...result.family.pips], [0, 1]);
  assert.deepEqual([...result.family.sharedPips], [1]);
  assert.deepEqual([...result.family.cells], [0, 2]);
  assert.equal(result.family.cellCoverage, "selected-arcs");
  assert.deepEqual(
    result.bins.map((row) => row.familyValue),
    [1, 1],
  );
  assert.deepEqual(
    result.bins.map((row) => row.otherValue),
    [0, 1],
  );
  assert.equal(result.bins[1].family.sharedPips, 1);
  assert.equal(result.summary.familyPips, 2);
  assert.equal(result.summary.familyCells, 2);
});

test("reordered catalogue cells join by native ID rather than catalogue position", () => {
  const family = neighborhood();
  const view = regionalView(fixture(), {
    neighborhood: family,
    selectedBin: 0,
  });
  assert.equal(family.cells[0].index, 3);
  assert.equal(family.cells[0].cell.id, "a");
  assert.deepEqual([...view.family.cells], [0]);
  assert.deepEqual(
    view.details.cells.map((row) => [row.cell.id, row.family]),
    [
      ["a", true],
      ["b", false],
    ],
  );
  const invalid = neighborhood();
  invalid.cells[0].cell = { id: "not-native" };
  assert.throws(
    () => regionalView(fixture(), { neighborhood: invalid }),
    /lacks native identity/,
  );
});

test("family cell coverage remains explicit when only neighborhood cells are available", () => {
  const data = fixture();
  const family = neighborhood();
  const limited = regionalView(data, { neighborhood: family });
  const full = regionalView(data, { neighborhood: family, computationIndex });
  assert.equal(limited.family.cellCoverage, "neighborhood-region");
  assert.deepEqual([...limited.family.cells], [0]);
  assert.deepEqual([...full.family.cells], [0, 2]);
  assert.notEqual(limited.family, full.family);
  assert.equal(
    regionalView(data, { neighborhood: family }).family,
    limited.family,
  );
});

test("selected-bin contributors preserve every identity and shared ownership", () => {
  const result = regionalView(fixture(), {
    neighborhood: neighborhood(),
    selectedBin: 1,
    selectedNet: 0,
  });
  assert.deepEqual(
    result.details.pips.map((row) => [row.index, row.family, row.shared]),
    [
      [1, true, true],
      [2, false, false],
    ],
  );
  assert.deepEqual(
    result.details.nets.map((row) => [row.index, row.family]),
    [
      [0, true],
      [1, false],
    ],
  );
  assert.deepEqual(result.selectedNet.bins, [0, 1]);
  assert.deepEqual(
    result.bins.map((row) => row.selectedNet),
    [true, true],
  );
  assert.deepEqual(result.selectedNet.net.unknownWires, ["w-unknown"]);
  assert.equal(result.summary.coverage.unknownWirePositions, 1);
});

test("cell-kind filtering changes only cell values and uses its global maximum", () => {
  const data = fixture();
  const result = regionalView(data, {
    metric: "cells",
    primitiveKind: "FDRE",
    neighborhood: neighborhood(),
    selectedBin: 0,
  });
  assert.equal(result.domain.max, 1);
  assert.deepEqual(
    result.bins.map((row) => row.value),
    [1, 0],
  );
  assert.deepEqual(
    result.bins.map((row) => row.familyValue),
    [0, 0],
  );
  assert.equal(result.details.cells.length, 2);
  assert.deepEqual(
    regionalView(data, { metric: "cells", primitiveKind: "DSP" }).bins.map(
      (row) => row.value,
    ),
    [0, 0],
  );
  assert.throws(
    () => regionalView(data, { metric: "pips", primitiveKind: "LUT6" }),
    TypeError,
  );
});

test("bin hit testing has exact half-open bounds and does not invent empty bins", () => {
  const data = fixture();
  assert.equal(regionalBinAt(data, { x: 0, y: 0 }), 0);
  assert.equal(regionalBinAt(data, { x: 15.999, y: 15.999 }), 0);
  assert.equal(regionalBinAt(data, { x: 16, y: 1 }), null);
  assert.equal(regionalBinAt(data, { x: 32, y: 1 }), 1);
  assert.equal(regionalBinAt(data, { x: 48, y: 1 }), null);
  assert.equal(regionalBinAt(data, { x: -0.1, y: 1 }), null);
  assert.equal(regionalBinAt(data, { x: null, y: 1 }), null);
});

test("reference-plane scene preserves counts and complete selected-net footprint", () => {
  const result = regionalScene(
    regionalView(fixture(), {
      selectedBin: 0,
      selectedNet: 0,
      neighborhood: neighborhood(),
    }),
    { ...sceneOptions, showCells: true },
  );
  assert.equal(result.surfaces.length, 2);
  assert.ok(
    result.surfaces
      .flatMap((row) => row.vertices)
      .every((point) => point[1] === -12),
  );
  assert.equal(result.segments.length, 8);
  assert.equal(result.markers.length, 2);
  assert.notEqual(result.markers[0].cellIndex, result.markers[1].cellIndex);
  assert.deepEqual(result.markers[0].position, result.markers[1].position);
  assert.notEqual(result.markers[0].color, result.markers[1].color);
  assert.equal(result.segments[0].color, REGIONAL_COLORS.selected);
  assert.equal(result.segments[4].color, REGIONAL_COLORS.net);
  assert.ok(result.segments.every((row) => row.kind === "regional-outline"));
});

test("background and family geometry do not expand explicit selection bounds", () => {
  const data = fixture();
  const background = regionalScene(
    regionalView(data, {
      neighborhood: neighborhood(),
    }),
    sceneOptions,
  );
  assert.equal(background.focus.length, 8);
  assert.deepEqual(background.selection, []);
  const bin = regionalScene(
    regionalView(data, { selectedBin: 0 }),
    sceneOptions,
  );
  assert.deepEqual(bin.selection, bin.surfaces[0].vertices);
  assert.equal(bin.focus.length, 8);
  const net = regionalScene(
    regionalView(data, { selectedNet: 0 }),
    sceneOptions,
  );
  assert.deepEqual(
    net.selection,
    net.surfaces.flatMap((row) => row.vertices),
  );
  const cell = regionalScene(
    regionalView(data, { selectedCell: 2 }),
    sceneOptions,
  );
  assert.deepEqual(cell.selection, [[0.33, -12, 0.02]]);
});

test("explicit scene subset does not rescale or silently include other bins", () => {
  const view = regionalView(fixture(), { selectedNet: 0 });
  const full = regionalScene(view, sceneOptions);
  const subset = regionalScene(view, { ...sceneOptions, binIndices: [1, 1] });
  assert.equal(subset.surfaces.length, 1);
  assert.equal(subset.surfaces[0].color, full.surfaces[1].color);
  assert.deepEqual(subset.focus, full.surfaces[1].vertices);
  assert.deepEqual(subset.selection, full.surfaces[1].vertices);
  assert.equal(
    regionalScene(view, { ...sceneOptions, binIndices: [] }).focus.length,
    0,
  );
  assert.throws(
    () => regionalScene(view, { ...sceneOptions, binIndices: [99] }),
    RangeError,
  );
});

test("selected cells remain individual native points and unknown locations stay absent", () => {
  const known = regionalScene(regionalView(fixture(), { selectedCell: 2 }), {
    ...sceneOptions,
    binIndices: [],
  });
  assert.equal(known.surfaces.length, 0);
  assert.equal(known.markers.length, 1);
  assert.deepEqual(known.markers[0].position, [0.33, -12, 0.02]);
  assert.equal(known.markers[0].color, REGIONAL_COLORS.selected);
  const unknown = regionalScene(regionalView(fixture(), { selectedCell: 3 }), {
    ...sceneOptions,
    binIndices: [],
  });
  assert.equal(unknown.markers.length, 0);
  assert.deepEqual(unknown.selection, []);
  assert.equal(unknown.summary.unlocatedCells, 1);
});

test("full contributor lists have no hidden rendering or list limit", () => {
  const data = fixture();
  data.cells = Array.from({ length: 4097 }, (_, index) => ({
    id: `c${index}`,
    kind: "LUT6",
    x: 1,
    y: 2,
    bin: 0,
  }));
  data.bins[0].cells = data.cells.map((_, index) => index);
  data.bins[0].counts.cells = 4097;
  data.bins[0].primitiveKinds = { LUT6: 4097 };
  data.bins[1].cells = [];
  data.bins[1].counts.cells = 0;
  data.bins[1].primitiveKinds = {};
  data.maxima.cells = 4097;
  data.maxima.primitiveKinds = { LUT6: 4097 };
  const view = regionalView(data, { selectedBin: 0, metric: "cells" });
  assert.equal(view.details.cells.length, 4097);
  assert.equal(
    regionalScene(view, { ...sceneOptions, showCells: true }).markers.length,
    4097,
  );
});

test("zero domains, absent evidence and invalid scalar options stay distinct", () => {
  assert.equal(regionalCountColor(null, 10), UNKNOWN_COLOR);
  assert.equal(regionalCountColor(0, 0), regionalCountColor(0, 10));
  assert.notEqual(regionalCountColor(0, 10), regionalCountColor(10, 10));
  assert.throws(() => regionalCountColor(11, 10), RangeError);
  assert.throws(() => regionalCountColor(-1, 10), RangeError);
  assert.throws(
    () => regionalView(fixture(), { metric: "congestion" }),
    RangeError,
  );
  assert.throws(() => regionalView(fixture(), { selectedNet: 99 }), RangeError);
  assert.throws(
    () =>
      regionalScene(regionalView(fixture()), { ...sceneOptions, cycle: NaN }),
    TypeError,
  );
});
