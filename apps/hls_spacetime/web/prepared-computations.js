/** Compact, derived rendering indexes. The authoritative graph and native records
 * remain hash-bound source attachments; these tables do not replace that evidence. */
import { chainTargetMasks } from "./action-chain.js";
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
/** Costs align with their source rows; null is eligible but unknown, whereas
 * not_applicable excludes a primitive or registered-launch arc from that scope. */
function pathCosts(values, length, allowOutside, name) {
  check(
    Array.isArray(values) &&
      values.length === length &&
      Array.from(values).every(
        (value) =>
          finite(value) || (allowOutside && value === "not_applicable"),
      ),
    `invalid ${name} path costs`,
  );
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
      data.algorithm === 4,
    "unsupported format",
  );
  check(
    model.catalogue &&
      data.checkpoint === model.catalogue.checkpoint &&
      ["source", "rtl", "observation", "implementation"].every(
        (k) => data.build?.[k] === model.bundle.build[k],
      ),
    "build/checkpoint mismatch",
  );
  for (const key of [
    "operations",
    "writes",
    "cones",
    "routes",
    "primitives",
    "pinGeometry",
    "arcGeometry",
  ])
    check(Array.isArray(data[key]), `missing ${key} table`);
  const {
    operations,
    writes,
    cones,
    routes,
    primitives,
    pinGeometry,
    arcGeometry,
  } = data;
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
  check(
    pinGeometry.length === counts.pins && arcGeometry.length === counts.arcs,
    "incomplete pin/arc geometry population",
  );
  const pinNames = new Set();
  for (const row of pinGeometry) {
    check(
      Array.isArray(row) &&
        row.length === 4 &&
        (row[0] === null || (count(row[0]) && row[0] < counts.cells)) &&
        ((row[1] === null && row[2] === null) ||
          (Number.isFinite(row[1]) && Number.isFinite(row[2]))) &&
        typeof row[3] === "string" &&
        row[3].length > 0 &&
        !pinNames.has(row[3]),
      "invalid or duplicate pin geometry/name",
    );
    pinNames.add(row[3]);
  }
  for (const row of arcGeometry)
    check(
      Array.isArray(row) &&
        row.length === 4 &&
        count(row[0]) &&
        row[0] < counts.pins &&
        count(row[1]) &&
        row[1] < counts.pins &&
        (row[2] === 0 || row[2] === 1) &&
        finite(row[3]),
      "invalid arc geometry",
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
    for (const [table, length] of [
      ["pathDelays", cone.arcIndices.length],
      ["primitivePathDelays", cone.primitives.length],
    ]) {
      pathCosts(cone[table]?.registered, length, true, `${table} registered`);
      pathCosts(
        cone[table]?.static,
        length,
        table === "primitivePathDelays",
        `${table} static`,
      );
    }
    for (const scope of ["registered", "static"])
      pathCosts(
        cone.pinArrivals?.[scope],
        cone.pinIndices.length,
        true,
        `pinArrivals ${scope}`,
      );
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
    const selectionMasks = new Set();
    check(Array.isArray(write.selections ?? []), "invalid target selections");
    for (const selected of write.selections ?? []) {
      const requested = popcount(selected.mask),
        selectedMask = BigInt(selected.mask);
      const selectedCoverage = selected.coverage;
      check(
        requested > 0 &&
          !selectionMasks.has(selectedMask.toString()) &&
          (selectedMask & BigInt(event.access.mask)) === selectedMask &&
          selectedCoverage &&
          selectedCoverage.requestedBits === requested &&
          [selectedCoverage.mappedBits, selectedCoverage.unknownBits].every(
            count,
          ) &&
          selectedCoverage.mappedBits + selectedCoverage.unknownBits ===
            requested,
        "invalid target selection coverage",
      );
      selectionMasks.add(selectedMask.toString());
      unique(selected.cones, "target selection cone");
      check(
        (selectedCoverage.mappedBits === 0) === (selected.cones.length === 0),
        "target selection geometry disagrees with mapped coverage",
      );
      for (const id of selected.cones) {
        const subset = ref(id, cones, "cone");
        const parents = write.cones
          .map((parent) => cones[parent])
          .filter((cone) => cone.role === subset.role);
        for (const field of [
          "rootPins",
          "arcIndices",
          "pinIndices",
          "cellIndices",
        ]) {
          const allowed = new Set(parents.flatMap((cone) => cone[field]));
          check(
            subset[field].every((value) => allowed.has(value)),
            `target selection exceeds original ${field}`,
          );
        }
      }
    }
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
  const maxima = (scope) => {
    let maximum = null;
    for (const cone of cones)
      for (const value of cone.primitivePathDelays[scope])
        if (typeof value === "number") maximum = Math.max(maximum ?? 0, value);
    return maximum;
  };
  const maxDelays = {
    registered: maxima("registered"),
    static: maxima("static"),
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
    pinGeometry,
    arcGeometry,
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
    targetMasks = new Map(),
  } = {},
) {
  if (!index) return [];
  if (!(targetMasks instanceof Map)) throw Error("Invalid target masks");
  targetMasks = chainTargetMasks(index.model, {
    targets: [...targetMasks].map(([event, mask]) => ({ event, mask })),
  });
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
      const mask = targetMasks.get(id);
      const displayed =
        mask === undefined
          ? write
          : write.selections?.find((row) => BigInt(row.mask) === BigInt(mask));
      check(
        displayed,
        "target selection is not prepared; prepare rendering indexes again",
      );
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
      layer.operations.push({
        ...index.operations.get(id),
        selectedCones: displayed.cones,
      });
      for (const key of ["requestedBits", "mappedBits", "unknownBits"])
        layer.coverage[key] += displayed.coverage[key];
      for (const coneId of displayed.cones) {
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

/** A cone can feed several logical destinations, including aliased words. Only
 * displayed writes contribute memberships, and only their selected cones count. */
function paintMemberships(index, layer) {
  const memberships = new Map(layer.cones.map((cone) => [cone.id, new Set()]));
  for (const operation of layer.operations ?? []) {
    const write = index.writes.get(operation.event);
    const event = index.model.events.get(operation.event);
    check(
      write && typeof event?.access?.resource === "string",
      "missing paint destination",
    );
    for (const coneId of operation.selectedCones ?? write.cones) {
      const members = memberships.get(index.cones[coneId].id);
      if (members) members.add(event.access.resource);
    }
  }
  return [...memberships]
    .map(([id, members]) => [id, [...members].sort()])
    .sort(([left], [right]) => left.localeCompare(right));
}

/** Union shared raw tile geometry only; camera/normalization remain renderer work.
 * A primitive's color cost is the maximum eligible path through that primitive
 * across contributing cones. Unknown eligible paths remain flagged; paths outside
 * a timing scope do not contribute. Whole-cone bounds are used only by filters.
 * Missing destination membership dominates known owners of a shared primitive. */
export function preparedCircuitPaint(index, layer) {
  const membershipRows = paintMemberships(index, layer);
  const key = JSON.stringify(membershipRows);
  if (index.paints.has(key)) return index.paints.get(key);
  const memberships = new Map(membershipRows);
  const chosen = new Map(),
    routeIds = new Set();
  for (const cone of layer.cones) {
    const members = memberships.get(cone.id);
    for (const id of cone.routes) routeIds.add(id);
    for (const [primitiveIndex, id] of cone.primitives.entries()) {
      if (!chosen.has(id))
        chosen.set(id, {
          ...index.primitives[id],
          roles: new Set(),
          computationKey: null,
          computationShared: false,
          computationUnknown: false,
          registeredPathDelayNs: null,
          staticPathDelayNs: null,
          registeredPathTimingUnknown: false,
          staticPathTimingUnknown: false,
          registeredPathApplicable: false,
          staticPathApplicable: false,
        });
      const row = chosen.get(id);
      row.roles.add(cone.role);
      if (members.length === 0) {
        row.computationUnknown = true;
        row.computationKey = null;
        row.computationShared = false;
      } else if (!row.computationUnknown) {
        if (
          members.length > 1 ||
          (row.computationKey !== null && row.computationKey !== members[0])
        ) {
          row.computationKey = null;
          row.computationShared = true;
        } else if (!row.computationShared) {
          row.computationKey = members[0];
        }
      }
      for (const scope of ["registered", "static"]) {
        const cost = cone.primitivePathDelays[scope][primitiveIndex];
        if (cost === "not_applicable") continue;
        row[`${scope}PathApplicable`] = true;
        if (cost === null) row[`${scope}PathTimingUnknown`] = true;
        else {
          const value = `${scope}PathDelayNs`;
          row[value] = Math.max(row[value] ?? 0, cost);
        }
      }
    }
  }
  const result = {
    cacheKey: key,
    computations: [
      ...new Set(membershipRows.flatMap(([, members]) => members)),
    ].sort(),
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
    result[row.type].push(row);
  }
  return cachePaint(index.paints, key, result);
}
