/** Regional native-resource counts and selection on a spatial reference plane.
 * Counts describe installed placement and saved routing, never capacity, activity
 * or congestion. Bins and contributors retain their source identities; sharing
 * tile space does not connect electrical nets. Inputs and returned cached sets
 * are read-only, and display selections never alter the capture-wide domain.
 */
import { UNKNOWN_COLOR } from "./perceptual-color.js";

export const REGIONAL_METRICS = Object.freeze({
  cells: "Installed cells",
  pips: "Distinct used PIPs",
  nets: "Canonical net incidence",
});
export const REGIONAL_COLORS = Object.freeze({
  family: "#89c7c0",
  context: "#697580",
  selected: "#f4d77f",
  net: "#d9e5ef",
});

const emptyNeighborhood = {};
const absentIndex = {};
const familyCache = new WeakMap();
const binCache = new WeakMap();
const cellCache = new WeakMap();
const located = (value) =>
  value && Number.isFinite(value.x) && Number.isFinite(value.y);

function selectedIndex(index, rows, name) {
  if (index === null) return null;
  if (!Number.isSafeInteger(index) || index < 0 || index >= rows.length)
    throw new RangeError(`Invalid regional ${name} index`);
  return index;
}

/** Linear zero-to-maximum color with a fixed full-capture count domain. Unknown
 * counts are distinct; a known all-zero domain uses the low endpoint. */
export function regionalCountColor(value, maximum) {
  if (value === null || maximum === null) return UNKNOWN_COLOR;
  if (
    !Number.isSafeInteger(value) ||
    !Number.isSafeInteger(maximum) ||
    value < 0 ||
    maximum < value
  )
    throw new RangeError("Regional counts require 0 <= value <= maximum");
  const stops = [
    [32, 55, 70],
    [68, 143, 153],
    [245, 214, 141],
  ];
  const position = maximum === 0 ? 0 : (2 * value) / maximum;
  const low = Math.min(1, Math.floor(position));
  const part = position - low;
  return `#${stops[low]
    .map((channel, i) =>
      Math.round(channel + (stops[low + 1][i] - channel) * part)
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")}`;
}

/** Hit-test half-open native tile-grid bounds. Only recorded bins are returned;
 * an unrepresented/unknown position does not acquire an invented empty bin. */
export function regionalBinAt(data, position) {
  if (!located(position)) return null;
  let lookup = binCache.get(data);
  if (!lookup) {
    lookup = new Map(
      data.bins.map((bin, index) => [`${bin.x}/${bin.y}`, index]),
    );
    binCache.set(data, lookup);
  }
  const x = Math.floor(position.x / data.binSize);
  const y = Math.floor(position.y / data.binSize);
  return lookup.get(`${x}/${y}`) ?? null;
}

function families(data, neighborhood, computationIndex) {
  let neighborhoods = familyCache.get(data);
  if (!neighborhoods) familyCache.set(data, (neighborhoods = new WeakMap()));
  const owner = neighborhood ?? emptyNeighborhood;
  let indices = neighborhoods.get(owner);
  if (!indices) neighborhoods.set(owner, (indices = new WeakMap()));
  const indexKey = computationIndex ?? absentIndex;
  if (indices.has(indexKey)) return indices.get(indexKey);
  const cells = new Set();
  const nets = new Set();
  const pips = new Set();
  const sharedPips = new Set();
  const arcs = new Set();
  let nativeCells = cellCache.get(data);
  if (!nativeCells) {
    nativeCells = new Map(data.cells.map((cell, index) => [cell.id, index]));
    cellCache.set(data, nativeCells);
  }
  for (const row of neighborhood?.cells ?? []) {
    if (row.kind !== "family") continue;
    // Neighborhood row indices address the catalogue, whose order need not
    // match the native graph. Only the exact cell identity crosses that boundary.
    const cell = nativeCells.get(row.cell?.id);
    if (cell === undefined)
      throw new RangeError("Neighborhood family cell lacks native identity");
    cells.add(cell);
  }
  for (const selection of neighborhood?.selection?.values() ?? []) {
    for (const arc of selection.arcIds) arcs.add(arc);
  }
  for (const arc of arcs) {
    const net = data.arcNets[arc];
    if (net !== null && net !== undefined) nets.add(net);
    if (computationIndex) {
      const geometry = computationIndex.arcGeometry[arc];
      for (const pin of geometry.slice(0, 2)) {
        const cell = computationIndex.pinGeometry[pin][0];
        if (cell !== null) cells.add(cell);
      }
    }
  }
  for (const net of nets) {
    for (const pip of data.nets[net].pips) pips.add(pip);
  }
  for (const pip of pips) {
    if (data.pips[pip].nets.some((net) => !nets.has(net))) sharedPips.add(pip);
  }
  const result = {
    cells,
    nets,
    pips,
    sharedPips,
    cellCoverage: computationIndex ? "selected-arcs" : "neighborhood-region",
  };
  const binCounts = data.bins.map((bin) => {
    const family = {
      cells: bin.cells.filter((index) => cells.has(index)).length,
      pips: bin.pips.filter((index) => pips.has(index)).length,
      nets: bin.nets.filter((index) => nets.has(index)).length,
      sharedPips: bin.pips.filter((index) => sharedPips.has(index)).length,
    };
    return {
      family,
      other: {
        cells: bin.counts.cells - family.cells,
        pips: bin.counts.pips - family.pips,
        nets: bin.counts.nets - family.nets,
      },
    };
  });
  const cached = { family: result, binCounts };
  indices.set(indexKey, cached);
  return cached;
}

/** Select from createRegionalData's validated full tables. Metric keys are
 * cells/pips/nets; primitiveKind optionally narrows only the cell metric.
 * Every bin and every selected-bin contributor is returned, with no display cap.
 * Family net membership comes from canonical arc-to-net identity. Supplying the
 * matching computationIndex includes all selected arc endpoint cells, including
 * cells outside the neighborhood region; otherwise cell membership is limited
 * to the neighborhood's known family cells, joined by exact ID rather than
 * catalogue array position. Shared PIPs are counted once and
 * marked explicitly when both family and other nets reference that resource.
 */
export function regionalView(
  data,
  {
    metric = "pips",
    primitiveKind = null,
    neighborhood = null,
    computationIndex = null,
    selectedBin = null,
    selectedNet = null,
    selectedCell = null,
  } = {},
) {
  if (!Object.hasOwn(REGIONAL_METRICS, metric))
    throw new RangeError("Unknown regional metric");
  if (
    primitiveKind !== null &&
    (metric !== "cells" ||
      typeof primitiveKind !== "string" ||
      primitiveKind.length === 0)
  )
    throw new TypeError("A primitive kind applies only to the cell metric");
  selectedIndex(selectedBin, data.bins, "bin");
  selectedIndex(selectedNet, data.nets, "net");
  selectedIndex(selectedCell, data.cells, "cell");
  const { family, binCounts } = families(data, neighborhood, computationIndex);
  const maximum =
    primitiveKind === null
      ? data.maxima[metric]
      : (data.maxima.primitiveKinds[primitiveKind] ?? 0);
  const label =
    primitiveKind === null
      ? REGIONAL_METRICS[metric]
      : `${primitiveKind} cells`;
  const netBins = new Set(
    selectedNet === null ? [] : data.nets[selectedNet].bins,
  );
  const bins = data.bins.map((bin, index) => {
    const value =
      primitiveKind === null
        ? bin.counts[metric]
        : (bin.primitiveKinds[primitiveKind] ?? 0);
    const familyValue =
      primitiveKind === null
        ? binCounts[index].family[metric]
        : bin.cells.filter(
            (cell) =>
              family.cells.has(cell) && data.cells[cell].kind === primitiveKind,
          ).length;
    return {
      index,
      x: bin.x,
      y: bin.y,
      bounds: bin.bounds,
      counts: bin.counts,
      primitiveKinds: bin.primitiveKinds,
      value,
      color: regionalCountColor(value, maximum),
      ...binCounts[index],
      familyValue,
      otherValue: value - familyValue,
      selected: index === selectedBin,
      selectedNet: netBins.has(index),
    };
  });
  const cellRow = (index) => ({
    index,
    cell: data.cells[index],
    family: family.cells.has(index),
  });
  const netRow = (index) => ({
    index,
    net: data.nets[index],
    family: family.nets.has(index),
  });
  const details =
    selectedBin === null
      ? null
      : {
          index: selectedBin,
          bin: bins[selectedBin],
          cells: data.bins[selectedBin].cells.map(cellRow),
          pips: data.bins[selectedBin].pips.map((index) => ({
            index,
            pip: data.pips[index],
            family: family.pips.has(index),
            shared: family.sharedPips.has(index),
          })),
          nets: data.bins[selectedBin].nets.map(netRow),
        };
  return {
    metric,
    primitiveKind,
    domain: { min: 0, max: maximum, label },
    bins,
    details,
    family,
    selectedBin,
    selectedNet:
      selectedNet === null
        ? null
        : { ...netRow(selectedNet), bins: data.nets[selectedNet].bins },
    selectedCell: selectedCell === null ? null : cellRow(selectedCell),
    summary: {
      bins: bins.length,
      total: bins.reduce((sum, bin) => sum + bin.value, 0),
      familyTotal: bins.reduce((sum, bin) => sum + bin.familyValue, 0),
      familyCells: family.cells.size,
      familyNets: family.nets.size,
      familyPips: family.pips.size,
      sharedPips: family.sharedPips.size,
      coverage: data.summary,
    },
  };
}

/** Draw an optional opaque regional count plane. binIndices is an explicit
 * display subset; null includes all bins, without changing data or color scales.
 * Known selected-net footprints are outlined wherever included, and the selected
 * bin's cells appear only when showCells is true. An individually selected cell
 * is always marked if located. No line connects collocated cells or route bins.
 * Focus spans all displayed geometry; selection spans only explicitly chosen
 * bins, net-footprint bins and located cells. Background does not become a
 * selection. The cycle is a layout reference, not an activity/arrival timestamp.
 */
export function regionalScene(
  view,
  { cycle, point, world, showCells = false, binIndices = null } = {},
) {
  if (
    !view ||
    !Number.isFinite(cycle) ||
    typeof point !== "function" ||
    typeof world !== "function" ||
    typeof showCells !== "boolean"
  )
    throw new TypeError(
      "Regional scene requires a reference plane and coordinate functions",
    );
  const included = binIndices === null ? null : new Set(binIndices);
  if (included)
    for (const index of included)
      selectedIndex(index, view.bins, "display bin");
  const result = {
    surfaces: [],
    segments: [],
    markers: [],
    focus: [],
    selection: [],
    labels: [],
    summary: {},
  };
  const position = (raw) => world(point(raw), cycle);
  for (const bin of view.bins) {
    if (included && !included.has(bin.index)) continue;
    const { minX, maxX, minY, maxY } = bin.bounds;
    const vertices = [
      { x: minX, y: minY },
      { x: maxX, y: minY },
      { x: maxX, y: maxY },
      { x: minX, y: maxY },
    ].map(position);
    result.surfaces.push({
      vertices,
      color: bin.color,
      kind: "regional-bin",
      binIndex: bin.index,
      value: bin.value,
    });
    result.focus.push(...vertices);
    if (bin.selected || bin.selectedNet) result.selection.push(...vertices);
    if (bin.selected || bin.selectedNet || bin.familyValue > 0) {
      const color = bin.selected
        ? REGIONAL_COLORS.selected
        : bin.selectedNet
          ? REGIONAL_COLORS.net
          : REGIONAL_COLORS.family;
      for (let edge = 0; edge < 4; edge++)
        result.segments.push({
          from: vertices[edge],
          to: vertices[(edge + 1) % 4],
          color,
          radius: bin.selected ? 0.0011 : 0.0007,
          dash: 0,
          kind: "regional-outline",
          binIndex: bin.index,
          family: bin.familyValue > 0,
          selectedNet: bin.selectedNet,
        });
    }
  }
  const cells = new Map();
  if (
    showCells &&
    view.details &&
    (!included || included.has(view.selectedBin))
  )
    for (const row of view.details.cells) cells.set(row.index, row);
  if (view.selectedCell) cells.set(view.selectedCell.index, view.selectedCell);
  let unlocatedCells = 0;
  for (const row of cells.values()) {
    if (!located(row.cell)) {
      unlocatedCells++;
      continue;
    }
    const at = position(row.cell);
    const selected = row.index === view.selectedCell?.index;
    result.markers.push({
      position: at,
      color: selected
        ? REGIONAL_COLORS.selected
        : row.family
          ? REGIONAL_COLORS.family
          : REGIONAL_COLORS.context,
      size: selected ? 0.006 : 0.0035,
      priority: selected ? 5 : 1,
      kind: "regional-cell",
      cellIndex: row.index,
      cellId: row.cell.id,
      family: row.family,
    });
    result.focus.push(at);
    if (selected) result.selection.push(at);
  }
  if (result.focus.length)
    result.labels.push({
      text: "Regional native counts · placement and routing, not congestion",
      position: result.focus[0],
    });
  result.summary = {
    bins: result.surfaces.length,
    cells: result.markers.length,
    unlocatedCells,
  };
  return result;
}
