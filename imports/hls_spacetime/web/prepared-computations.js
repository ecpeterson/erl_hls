/** Compact, derived rendering indexes. The authoritative graph and native records
 * remain hash-bound source attachments; these tables do not replace that evidence. */
import { cachePaint } from "./paint-cache.js";
const ROLES = new Set(["data", "enable", "reset"]);
const TYPES = new Set(["tiles", "pips", "cells", "segments"]);

/** Invalid references reject a whole attachment, never a successfully loaded prefix. */
function check(ok, message) {
  if (!ok) throw Error(`Prepared computations: ${message}`);
}
function ref(id, rows, name) {
  check(
    Number.isSafeInteger(id) && id >= 0 && id < rows.length,
    `invalid ${name} reference`,
  );
  return rows[id];
}
function count(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
function finite(value) {
  return value === null || (Number.isFinite(value) && value >= 0);
}
function point(value) {
  return (
    value &&
    Number.isFinite(value.x) &&
    Number.isFinite(value.y) &&
    value.physical === true
  );
}
function unique(values, name) {
  check(
    Array.isArray(values) && new Set(values).size === values.length,
    `duplicate ${name}`,
  );
}
function popcount(mask) {
  check(
    typeof mask === "string" && /^0x[0-9a-f]+$/i.test(mask),
    "invalid write mask",
  );
  let bits = BigInt(mask),
    n = 0;
  while (bits) {
    bits &= bits - 1n;
    n++;
  }
  return n;
}

/** Check the prepared table closure against the exact loaded recording. Expensive
 * graph traversal belongs to the hash-bound preparation, not each browser load. */
export function createPreparedComputations(model, data) {
  if (!data) return null;
  check(
    data.format === "spacetime-prepared-render" &&
      data.schema === 1 &&
      data.algorithm === 1,
    "unsupported format",
  );
  check(
    model.catalogue &&
      data.checkpoint === model.catalogue.checkpoint &&
      ["source", "rtl", "observation"].every(
        (k) => data.build?.[k] === model.bundle.build[k],
      ),
    "build/checkpoint mismatch",
  );
  for (const key of ["operations", "writes", "cones", "routes", "primitives"])
    check(Array.isArray(data[key]), `missing ${key} table`);
  const { operations, writes, cones, routes, primitives } = data;
  const counts = data.sourceCounts;
  check(
    counts &&
      ["events", "writes", "cells", "pins", "nets", "arcs", "routeNets"].every(
        (k) => count(counts[k]),
      ) &&
      counts.events === model.events.size &&
      counts.cells === model.cells.size &&
      counts.routeNets === counts.nets,
    "invalid source population counts",
  );
  const primitiveIds = new Set();
  for (const row of primitives) {
    check(
      count(row.id) &&
        row.id === primitiveIds.size &&
        !primitiveIds.has(row.id) &&
        TYPES.has(row.type),
      "invalid primitive",
    );
    primitiveIds.add(row.id);
    check(
      row.type === "cells"
        ? count(row.sourceCell) && row.sourceCell < counts.cells
        : count(row.sourceNet) && row.sourceNet < counts.nets,
      "primitive source reference outside population",
    );
    check(
      row.type === "segments"
        ? point(row.from) && point(row.to)
        : point(row.point),
      "invalid coordinates",
    );
    if (row.type === "segments")
      check(
        ["unresolved", "site", "node"].includes(row.kind),
        "invalid span kind",
      );
  }
  const routeArcs = new Set();
  for (const route of routes) {
    check(
      count(route.arc) &&
        route.arc < counts.arcs &&
        !routeArcs.has(route.arc) &&
        typeof route.disposition === "string",
      "invalid route",
    );
    routeArcs.add(route.arc);
    unique(route.primitives, "route primitive");
    for (const id of route.primitives) ref(id, primitives, "primitive");
  }
  const coneIds = new Set();
  for (const cone of cones) {
    check(
      typeof cone.id === "string" &&
        !coneIds.has(cone.id) &&
        ROLES.has(cone.role),
      "invalid cone",
    );
    coneIds.add(cone.id);
    check(
      finite(cone.registeredDelayNs) && finite(cone.staticDelayNs),
      "invalid timing bound",
    );
    for (const key of [
      "rootPins",
      "arcIndices",
      "pinIndices",
      "cellIndices",
      "primitives",
      "routes",
    ])
      unique(cone[key], `cone ${key}`);
    for (const id of cone.primitives) ref(id, primitives, "primitive");
    const arcSet = new Set(cone.arcIndices),
      geometry = new Set(cone.primitives);
    for (const id of cone.routes) {
      const route = ref(id, routes, "route");
      check(arcSet.has(route.arc), "cone route outside arc population");
      check(
        route.primitives.every((p) => geometry.has(p)),
        "cone omits routed geometry",
      );
    }
    for (const [key, limit] of [
      ["rootPins", counts.pins],
      ["pinIndices", counts.pins],
      ["arcIndices", counts.arcs],
      ["cellIndices", counts.cells],
    ])
      check(
        cone[key].every((id) => count(id) && id < limit),
        "invalid source graph reference",
      );
    const pinSet = new Set(cone.pinIndices);
    check(
      cone.rootPins.every((id) => pinSet.has(id)),
      "root outside cone pins",
    );
    check(
      cone.registeredTiming &&
        ["known", "unknown", "not_applicable"].includes(
          cone.registeredTiming.status,
        ),
      "missing registered timing status",
    );
  }
  const operationIndex = new Map();
  check(operations.length === model.events.size, "incomplete event coverage");
  for (const op of operations) {
    check(
      model.events.has(op.event) &&
        !operationIndex.has(op.event) &&
        typeof op.status === "string" &&
        typeof op.applicability === "string",
      "invalid operation",
    );
    unique(op.writes, "associated write");
    for (const id of op.writes)
      check(
        model.events.get(id)?.access?.kind === "write",
        "unknown associated write",
      );
    operationIndex.set(op.event, op);
  }
  const writeIndex = new Map();
  for (const write of writes) {
    const event = model.events.get(write.event),
      op = operationIndex.get(write.event),
      c = write.coverage;
    check(
      event?.access?.kind === "write" &&
        op?.applicability === "storage_write" &&
        !writeIndex.has(write.event),
      "invalid write occurrence",
    );
    check(
      c &&
        [c.requestedBits, c.mappedBits, c.unknownBits].every(count) &&
        c.requestedBits === popcount(event.access.mask) &&
        c.mappedBits + c.unknownBits === c.requestedBits,
      "write bit coverage mismatch",
    );
    unique(write.cones, "write cone");
    for (const id of write.cones) ref(id, cones, "cone");
    writeIndex.set(write.event, write);
  }
  check(writes.length === counts.writes, "source write population mismatch");
  for (const event of model.events.values()) {
    check(
      (event.access?.kind === "write") === writeIndex.has(event.id),
      "incomplete write coverage",
    );
    check(
      (event.access?.kind === "write") ===
        (operationIndex.get(event.id).applicability === "storage_write"),
      "write applicability mismatch",
    );
  }
  const maxima = (key) =>
    cones.reduce(
      (max, cone) => (cone[key] === null ? max : Math.max(max ?? 0, cone[key])),
      null,
    );
  const maxDelays = {
    registered: maxima("registeredDelayNs"),
    static: maxima("staticDelayNs"),
  };
  check(
    data.maxDelays?.registered === maxDelays.registered &&
      data.maxDelays?.static === maxDelays.static,
    "global timing summary mismatch",
  );
  check(
    data.bounds &&
      ["minX", "maxX", "minY", "maxY"].every((k) =>
        Number.isFinite(data.bounds[k]),
      ) &&
      data.bounds.minX <= data.bounds.maxX &&
      data.bounds.minY <= data.bounds.maxY,
    "invalid geometry bounds",
  );
  return {
    prepared: true,
    model,
    data,
    operations: operationIndex,
    writes: writeIndex,
    cones,
    routes,
    primitives,
    bounds: data.bounds,
    maxDelays,
    paints: new Map(),
  };
}

/** Apply the same event-to-write, role and delay selection as the original graph
 * reader. All occurrences stay counted even when a filter hides their cones. */
export function preparedComputationLayers(
  index,
  events,
  {
    roles = ["data", "enable", "reset"],
    minimumDelayNs = 0,
    includeUnknownTiming = true,
    timingMetric = "whole_cone",
  } = {},
) {
  if (!index) return [];
  check(
    Array.isArray(roles) &&
      roles.every((r) => ROLES.has(r)) &&
      Number.isFinite(minimumDelayNs) &&
      minimumDelayNs >= 0 &&
      ["whole_cone", "registered_launch"].includes(timingMetric),
    "invalid display filter",
  );
  const layers = new Map(),
    seen = new Set();
  for (const supplied of events) {
    const op = index.operations.get(
      typeof supplied === "string" ? supplied : supplied.id,
    );
    if (!op) continue;
    for (const id of op.applicability === "storage_write"
      ? [op.event]
      : op.writes) {
      if (seen.has(id)) continue;
      seen.add(id);
      const write = index.writes.get(id),
        event = index.model.events.get(id);
      check(write, "missing selected write");
      if (!layers.has(event.cycle))
        layers.set(event.cycle, {
          cycle: event.cycle,
          timingMetric,
          operations: [],
          cones: new Map(),
          arcs: new Set(),
          cells: new Set(),
          pins: new Set(),
          coverage: {
            requestedBits: 0,
            mappedBits: 0,
            unknownBits: 0,
            filteredCones: 0,
          },
        });
      const layer = layers.get(event.cycle);
      layer.operations.push(index.operations.get(id));
      for (const key of ["requestedBits", "mappedBits", "unknownBits"])
        layer.coverage[key] += write.coverage[key];
      for (const coneId of write.cones) {
        const cone = index.cones[coneId],
          delay =
            timingMetric === "registered_launch"
              ? cone.registeredDelayNs
              : cone.staticDelayNs;
        if (
          !roles.includes(cone.role) ||
          (delay === null ? !includeUnknownTiming : delay < minimumDelayNs)
        ) {
          layer.coverage.filteredCones++;
          continue;
        }
        if (layer.cones.has(cone.id)) continue;
        layer.cones.set(cone.id, cone);
        for (const id of cone.arcIndices) layer.arcs.add(id);
        for (const id of cone.cellIndices) layer.cells.add(id);
        for (const id of cone.pinIndices) layer.pins.add(id);
      }
    }
  }
  return [...layers.values()]
    .sort((a, b) => a.cycle - b.cycle)
    .map((layer) => ({
      ...layer,
      cones: [...layer.cones.values()],
      arcs: [...layer.arcs],
      cells: [...layer.cells],
      pins: [...layer.pins],
    }));
}

/** Union shared raw tile geometry only; camera/normalization remain renderer work.
 * A primitive's color bound is the maximum contributing cone bound, not its own
 * delay. Mixed known/unknown contributors retain explicit flags in both scopes. */
export function preparedCircuitPaint(index, layer) {
  const key = layer.cones
    .map((c) => c.id)
    .sort()
    .join("|");
  if (index.paints.has(key)) return index.paints.get(key);
  const chosen = new Map(),
    routeIds = new Set();
  for (const cone of layer.cones) {
    for (const id of cone.routes) routeIds.add(id);
    for (const id of cone.primitives) {
      if (!chosen.has(id))
        chosen.set(id, {
          ...index.primitives[id],
          roles: new Set(),
          registeredDelayNs: null,
          staticDelayNs: null,
          registeredTimingUnknown: false,
          staticTimingUnknown: false,
        });
      const row = chosen.get(id);
      row.roles.add(cone.role);
      for (const [value, unknown] of [
        ["registeredDelayNs", "registeredTimingUnknown"],
        ["staticDelayNs", "staticTimingUnknown"],
      ]) {
        if (cone[value] === null) row[unknown] = true;
        else row[value] = Math.max(row[value] ?? 0, cone[value]);
      }
    }
  }
  const result = {
    tiles: [],
    pips: [],
    cells: [],
    segments: [],
    dispositions: {},
  };
  for (const id of routeIds) {
    const value = index.routes[id].disposition;
    result.dispositions[value] = (result.dispositions[value] ?? 0) + 1;
  }
  for (const row of chosen.values()) {
    row.role = row.roles.size === 1 ? [...row.roles][0] : "mixed";
    delete row.roles;
    row.timingUnknown = row.registeredTimingUnknown || row.staticTimingUnknown;
    result[row.type].push(row);
  }
  return cachePaint(index.paints, key, result);
}
