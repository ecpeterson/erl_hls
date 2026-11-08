import { createNativeRouting, nativeConnection } from "./native-routes.js";

/** Structural native cones associated with recorded writes. Static graph and
 * routing rows are shared across events/clocks; association is not sensitization
 * or electrical activity. The caller verifies the manifest and every part hash. */
const ROUTE_LIMITS = {
  nets: 100000,
  nodes: 4000000,
  pips: 8000000,
  wires: 16000000,
  attachments: 2000000,
  work: 200000000,
};
const ROLES = new Set(["data", "enable", "reset"]);

/** Invalid complete attachments reject rather than quietly losing coverage. */
function requireValue(condition, reason) {
  if (!condition) throw Error(`Computation routes: ${reason}`);
}

/** Array positions are compact immutable identities, never native-name guesses. */
function reference(value, rows, label) {
  requireValue(
    Number.isSafeInteger(value) && value >= 0 && value < rows.length,
    `invalid ${label} reference: ${value}`,
  );
  return rows[value];
}

/** Native IDs remain exact; repeated identities would merge distinct evidence. */
function identities(rows, label) {
  requireValue(Array.isArray(rows), `missing ${label} table`);
  const seen = new Set();
  for (const row of rows) {
    requireValue(
      row &&
        typeof row.id === "string" &&
        row.id.length > 0 &&
        !seen.has(row.id),
      `duplicate/invalid ${label} identity`,
    );
    seen.add(row.id);
  }
}

/** Port directions are relative to the design, primitive directions to the cell. */
function output(pin) {
  return ["OUT", "output", "INOUT", "inout"].includes(pin.direction);
}
function input(pin) {
  return ["IN", "input", "INOUT", "inout"].includes(pin.direction);
}

/** Wide encoded masks never pass through floating-point browser numbers. */
function mask(value, width) {
  requireValue(
    typeof value === "string" && /^0x[0-9a-f]+$/i.test(value),
    "invalid encoded mask",
  );
  const bits = BigInt(value);
  requireValue(
    bits > 0n && bits < 1n << BigInt(width),
    "mask outside resource width",
  );
  return bits;
}

/** All corners/conditions remain available; the display bound conservatively
 * takes the largest supplied static delay. Missing corners or slots stay unknown.
 * It is not a path slack, a calibrated period, or a dynamically selected delay. */
function arcDelay(arc) {
  const corners = [arc.timing?.fast, arc.timing?.slow];
  for (const rows of corners) {
    requireValue(
      rows === undefined || Array.isArray(rows),
      "invalid corner timing table",
    );
    for (const row of rows ?? [])
      requireValue(
        row &&
          (row.maxPs === null ||
            (Number.isFinite(row.maxPs) && row.maxPs >= 0)),
        "invalid static delay annotation",
      );
  }
  if (corners.some((rows) => !Array.isArray(rows) || rows.length === 0))
    return null;
  const values = corners.flat().map((row) => row.maxPs);
  if (values.some((value) => !Number.isFinite(value) || value < 0)) return null;
  return Math.max(...values) / 1000;
}

/** Validate complete population coverage and construct shared graph indexes.
 * No execution edges or native-to-source bindings are inferred by this reader. */
export function createComputations(model, attachment, routeNets = []) {
  if (!attachment) return null;
  requireValue(
    attachment.schema === 1 &&
      attachment.scope === "structural_native_connectivity",
    "unsupported attachment",
  );
  requireValue(
    model.catalogue &&
      attachment.checkpoint === model.catalogue.checkpoint &&
      ["source", "rtl", "observation"].every(
        (key) => attachment.build?.[key] === model.bundle.build[key],
      ),
    "build/checkpoint mismatch",
  );
  const { cells, pins, nets, arcs, bindings, operations } = attachment;
  for (const [rows, name] of [
    [cells, "cell"],
    [pins, "pin"],
    [nets, "net"],
    [arcs, "arc"],
  ])
    identities(rows, name);
  requireValue(
    cells.length === model.cells.size,
    "incomplete native cell population",
  );
  for (const cell of cells) {
    requireValue(
      model.cells.get(cell.id)?.kind === cell.kind,
      "native cell identity/type mismatch",
    );
    requireValue(
      ["sequential", "constant", "combinational", "unsupported"].includes(
        cell.boundary,
      ),
      "invalid cell boundary",
    );
  }
  for (const pin of pins) {
    if (pin.cell !== null) reference(pin.cell, cells, "cell");
    if (pin.net !== null) reference(pin.net, nets, "net");
    requireValue(
      ["IN", "OUT", "INOUT", "input", "output", "inout"].includes(
        pin.direction,
      ),
      "invalid pin direction",
    );
  }
  const incoming = Array.from({ length: pins.length }, () => []);
  const delays = [];
  for (const [i, arc] of arcs.entries()) {
    const from = reference(arc.from, pins, "source pin"),
      to = reference(arc.to, pins, "target pin");
    requireValue(
      arc.kind === "net" || arc.kind === "logic",
      "invalid arc kind",
    );
    if (arc.kind === "net") {
      reference(arc.net, nets, "arc net");
      requireValue(
        from.net === arc.net && to.net === arc.net,
        "net arc/pin membership mismatch",
      );
      requireValue(
        (from.cell === null ? input(from) : output(from)) &&
          (to.cell === null ? output(to) : input(to)),
        "net arc direction mismatch",
      );
    } else
      requireValue(
        from.cell !== null &&
          from.cell === to.cell &&
          input(from) &&
          output(to),
        "logic arc crosses cells or has invalid direction",
      );
    incoming[arc.to].push(i);
    delays.push(arcDelay(arc));
  }
  requireValue(Array.isArray(bindings), "missing bindings");
  const bindingIndex = new Map();
  for (const binding of bindings) {
    const resource = model.resources.get(binding.resource);
    requireValue(
      resource &&
        !bindingIndex.has(binding.resource) &&
        Array.isArray(binding.bits),
      "invalid/duplicate resource binding",
    );
    const bits = new Map();
    for (const bit of binding.bits) {
      requireValue(
        Number.isSafeInteger(bit.bit) &&
          bit.bit >= 0 &&
          bit.bit < resource.width &&
          !bits.has(bit.bit),
        "invalid/duplicate binding bit",
      );
      for (const key of ["q", "d", "ce", "reset", "set"])
        if (bit[key] !== undefined && bit[key] !== null)
          reference(bit[key], pins, "bound pin");
      for (const control of bit.controls ?? []) {
        reference(control.pin, pins, "control pin");
        requireValue(
          ROLES.has(control.role) && control.role !== "data",
          "invalid control role",
        );
      }
      if (bit.status === "supported") {
        const q = reference(bit.q, pins, "qualified output pin");
        requireValue(
          q.cell !== null &&
            output(q) &&
            cells[q.cell].boundary === "sequential",
          "qualified output is not sequential",
        );
        for (const [field, names] of [
          ["d", ["D"]],
          ["ce", ["CE"]],
          ["reset", ["R", "CLR"]],
          ["set", ["S", "PRE"]],
        ]) {
          if (bit[field] === undefined || bit[field] === null) continue;
          const pin = pins[bit[field]];
          requireValue(
            pin.cell === q.cell && input(pin) && names.includes(pin.pin),
            "bound input role/cell mismatch",
          );
        }
        for (const control of bit.controls ?? []) {
          const pin = pins[control.pin];
          const names =
            control.role === "enable" ? ["CE"] : ["R", "CLR", "S", "PRE"];
          requireValue(
            pin.cell === q.cell && input(pin) && names.includes(pin.pin),
            "bound control role/cell mismatch",
          );
        }
      } else
        requireValue(
          ["q", "d", "ce", "reset", "set"].every(
            (field) => bit[field] === undefined || bit[field] === null,
          ) && !bit.controls?.length,
          "unqualified bit claims native pins",
        );
      bits.set(bit.bit, bit);
    }
    requireValue(
      bits.size === resource.width,
      "incomplete stored-word bit coverage",
    );
    bindingIndex.set(binding.resource, bits);
  }
  requireValue(
    Array.isArray(operations) && operations.length === model.events.size,
    "incomplete event coverage",
  );
  const operationIndex = new Map();
  for (const op of operations) {
    const event = model.events.get(op.event);
    requireValue(
      event && !operationIndex.has(op.event),
      "duplicate/unknown operation event",
    );
    requireValue(
      typeof op.applicability === "string" &&
        typeof op.status === "string" &&
        Array.isArray(op.targets) &&
        Array.isArray(op.sources) &&
        Array.isArray(op.unknowns),
      "invalid event coverage row",
    );
    for (const target of op.targets) {
      const resource = model.resources.get(target.resource);
      requireValue(
        resource && Number.isSafeInteger(resource.width),
        "unknown target resource",
      );
      requireValue(
        bindingIndex.has(target.resource),
        "missing target word bindings",
      );
      mask(target.mask, resource.width);
    }
    for (const source of op.sources) {
      const resource = model.resources.get(source.resource);
      requireValue(
        resource && ["data", "control", "unclassified"].includes(source.kind),
        "unknown source resource/role",
      );
      if (source.mask !== null) mask(source.mask, resource.width);
    }
    for (const id of op.producers ?? [])
      requireValue(model.events.has(id), "unknown producer event");
    for (const id of op.writes ?? [])
      requireValue(
        model.events.get(id)?.access?.kind === "write",
        "unknown associated write",
      );
    if (event.access?.kind === "write") {
      requireValue(
        op.applicability === "storage_write" &&
          op.targets.length === 1 &&
          op.targets.some(
            (target) =>
              target.resource === event.access.resource &&
              mask(target.mask, model.resources.get(target.resource).width) ===
                mask(
                  event.access.mask,
                  model.resources.get(target.resource).width,
                ),
          ),
        "write target coverage mismatch",
      );
    } else
      requireValue(
        op.applicability !== "storage_write",
        "nonwrite claims a write occurrence",
      );
    operationIndex.set(op.event, op);
  }
  const knownNets = new Set(nets.map((net) => net.id));
  for (const net of routeNets)
    requireValue(knownNets.has(net.id), "routing net absent from native graph");
  const routing = createNativeRouting(routeNets, ROUTE_LIMITS);
  if (attachment.routingComplete)
    requireValue(
      routing.nets.size === nets.length,
      "incomplete native route population",
    );
  return {
    model,
    attachment,
    cells,
    pins,
    nets,
    arcs,
    incoming,
    delays,
    bindings: bindingIndex,
    operations: operationIndex,
    routing,
    cones: new Map(),
    writeCones: new Map(),
  };
}

/** Only a sequential output ends the current clock's combinational traversal.
 * Sink D/CE/reset inputs still admit their incoming physical nets. */
function frontier(index, pinIndex) {
  const pin = index.pins[pinIndex];
  if (pin.cell === null) return "external";
  const cell = index.cells[pin.cell];
  if (["constant", "unsupported"].includes(cell.boundary)) return cell.boundary;
  if (
    cell.boundary === "sequential" &&
    ["OUT", "output", "INOUT", "inout"].includes(pin.direction)
  )
    return "sequential";
  if (!index.incoming[pinIndex].length) return "missing_connectivity";
  return null;
}

/** Bound only paths launched from sequential outputs. External/constant paths
 * remain in the cone but are outside this metric; their missing delays are never
 * replaced by zero. Reachability is independent of timing, so an untimed arc on
 * any registered path poisons the bound even when another path is fully timed.
 * Unsupported frontiers and cycles also block a finite result. */
function registeredBound(
  index,
  roots,
  frontiers,
  outgoing,
  order,
  cyclic,
  unsupported,
) {
  const launches = frontiers
    .filter((item) => item.kind === "sequential")
    .map((item) => item.pin);
  const reachable = new Set(launches),
    queue = [...launches];
  let reachableArcs = 0,
    missingTiming = 0;
  for (let i = 0; i < queue.length; i++) {
    for (const arcIndex of outgoing.get(queue[i]) ?? []) {
      reachableArcs++;
      if (index.delays[arcIndex] === null) missingTiming++;
      const target = index.arcs[arcIndex].to;
      if (!reachable.has(target)) {
        reachable.add(target);
        queue.push(target);
      }
    }
  }
  const targets = roots.filter((pin) => reachable.has(pin));
  const reasons = [];
  if (missingTiming) reasons.push("missing_registered_path_timing");
  if (unsupported) reasons.push("unsupported_or_missing_frontier");
  if (cyclic) reasons.push("cycle");
  if (!targets.length) reasons.push("no_registered_launch_path");
  let delayNs = null;
  if (reasons.length === 0) {
    const arrival = new Map(launches.map((pin) => [pin, 0]));
    for (const pin of order) {
      if (!arrival.has(pin)) continue;
      for (const arcIndex of outgoing.get(pin) ?? []) {
        const arc = index.arcs[arcIndex],
          delay = index.delays[arcIndex];
        // The preceding reachability check established every used delay.
        requireValue(
          delay !== null,
          "registered timing completeness disagrees",
        );
        arrival.set(
          arc.to,
          Math.max(arrival.get(arc.to) ?? 0, arrival.get(pin) + delay),
        );
      }
    }
    delayNs = Math.max(...targets.map((pin) => arrival.get(pin)));
  }
  return {
    delayNs,
    description: {
      status:
        reasons.length === 0
          ? "known"
          : reasons.length === 1 && reasons[0] === "no_registered_launch_path"
            ? "not_applicable"
            : "unknown",
      reasons,
      launchPins: launches.length,
      reachedTargets: targets.length,
      excludedTargets: roots.length - targets.length,
      reachableArcs,
      missingTiming,
    },
  };
}

/** Merge alternative path prefixes/suffixes without losing an untimed path.
 * A finite alternative cannot establish the maximum while another is unknown. */
function mergeDistance(distances, pin, distance) {
  const previous = distances.get(pin);
  if (!previous) distances.set(pin, distance);
  else {
    previous.unknown ||= distance.unknown;
    if (distance.known !== null)
      previous.known = Math.max(previous.known ?? 0, distance.known);
  }
}

/** Extend one reachable prefix/suffix; an absent annotation is not zero delay. */
function extendDistance(distance, delay) {
  const total =
    distance.known !== null && delay !== null ? distance.known + delay : null;
  const known = Number.isFinite(total) ? total : null;
  return {
    known,
    unknown: distance.unknown || delay === null || known === null,
  };
}

/** Longest eligible prefixes at pins and complete through-path costs at arcs.
 * Arrays follow the supplied pin/arc orders. Forward/backward DAG passes are
 * linear in this cone, without enumerating paths.
 * Prefix/suffix unknowns affect only arcs whose through-path can include them.
 * Values use the same conservative SDF envelope as the existing cone bounds;
 * they omit endpoint timing checks, clock effects and sensitization. */
function pathTiming(
  index,
  roots,
  frontiers,
  outgoing,
  order,
  arcIndices,
  pinIndices,
  cyclic,
  unsupported,
) {
  if (cyclic || unsupported)
    return {
      pathDelays: {
        registered: arcIndices.map(() => null),
        static: arcIndices.map(() => null),
      },
      pinArrivals: {
        registered: pinIndices.map(() => null),
        static: pinIndices.map(() => null),
      },
    };
  const suffix = new Map(
    roots.map((pin) => [pin, { known: 0, unknown: false }]),
  );
  for (let i = order.length - 1; i >= 0; i--) {
    const pin = order[i];
    for (const arcIndex of outgoing.get(pin) ?? []) {
      const tail = suffix.get(index.arcs[arcIndex].to);
      if (tail)
        mergeDistance(
          suffix,
          pin,
          extendDistance(tail, index.delays[arcIndex]),
        );
    }
  }
  const costs = (registered) => {
    const prefix = new Map(
      frontiers
        .filter((item) => !registered || item.kind === "sequential")
        .map((item) => [item.pin, { known: 0, unknown: false }]),
    );
    for (const pin of order) {
      const head = prefix.get(pin);
      if (!head) continue;
      for (const arcIndex of outgoing.get(pin) ?? [])
        mergeDistance(
          prefix,
          index.arcs[arcIndex].to,
          extendDistance(head, index.delays[arcIndex]),
        );
    }
    const paths = arcIndices.map((arcIndex) => {
      const arc = index.arcs[arcIndex],
        delay = index.delays[arcIndex];
      const head = prefix.get(arc.from),
        tail = suffix.get(arc.to);
      if (!head || !tail) return registered ? "not_applicable" : null;
      if (head.unknown || tail.unknown || delay === null) return null;
      const cost = head.known + delay + tail.known;
      return Number.isFinite(cost) ? cost : null;
    });
    const arrivals = pinIndices.map((pin) => {
      const head = prefix.get(pin);
      if (!head) return "not_applicable";
      return head.unknown ? null : head.known;
    });
    return { paths, arrivals };
  };
  const registered = costs(true),
    whole = costs(false);
  return {
    pathDelays: { registered: registered.paths, static: whole.paths },
    pinArrivals: { registered: registered.arrivals, static: whole.arrivals },
  };
}

/** Build a backward graph cone once, then compute a conservative longest static
 * data delay with Kahn's algorithm. Reconvergence shares nodes, never paths.
 * Unsupported frontiers, cycles or any untimed required arc leave delay unknown. */
function cone(index, roots, role) {
  const rootPins = [...new Set(roots)].sort((a, b) => a - b);
  const key = `${rootPins.join(",")}/${role}`;
  if (index.cones.has(key)) return index.cones.get(key);
  const pinSet = new Set(rootPins),
    arcSet = new Set(),
    frontiers = [];
  const queue = [...rootPins];
  for (let i = 0; i < queue.length; i++) {
    const pin = queue[i],
      stop = frontier(index, pin);
    if (stop) {
      frontiers.push({ pin, kind: stop });
      continue;
    }
    for (const arcIndex of index.incoming[pin]) {
      arcSet.add(arcIndex);
      const from = index.arcs[arcIndex].from;
      if (!pinSet.has(from)) {
        pinSet.add(from);
        queue.push(from);
      }
    }
  }
  const indegree = new Map([...pinSet].map((pin) => [pin, 0])),
    outgoing = new Map();
  let missingTiming = 0;
  for (const arcIndex of arcSet) {
    const arc = index.arcs[arcIndex];
    indegree.set(arc.to, indegree.get(arc.to) + 1);
    if (!outgoing.has(arc.from)) outgoing.set(arc.from, []);
    outgoing.get(arc.from).push(arcIndex);
    if (index.delays[arcIndex] === null) missingTiming++;
  }
  const ready = [...pinSet].filter((pin) => indegree.get(pin) === 0),
    arrival = new Map();
  for (const pin of ready) arrival.set(pin, 0);
  for (let i = 0; i < ready.length; i++) {
    for (const arcIndex of outgoing.get(ready[i]) ?? []) {
      const arc = index.arcs[arcIndex];
      const delay = index.delays[arcIndex];
      arrival.set(
        arc.to,
        Math.max(
          arrival.get(arc.to) ?? 0,
          (arrival.get(arc.from) ?? 0) + (delay ?? 0),
        ),
      );
      indegree.set(arc.to, indegree.get(arc.to) - 1);
      if (indegree.get(arc.to) === 0) ready.push(arc.to);
    }
  }
  const cyclic = ready.length !== pinSet.size;
  const unsupported = frontiers.filter((item) =>
    ["unsupported", "missing_connectivity"].includes(item.kind),
  ).length;
  const registered = registeredBound(
    index,
    rootPins,
    frontiers,
    outgoing,
    ready,
    cyclic,
    unsupported,
  );
  const arcIndices = [...arcSet],
    pinIndices = [...pinSet];
  const timing = pathTiming(
    index,
    rootPins,
    frontiers,
    outgoing,
    ready,
    arcIndices,
    pinIndices,
    cyclic,
    unsupported,
  );
  const result = {
    id: key,
    rootPins,
    role,
    pinIndices,
    arcIndices,
    ...timing,
    frontiers,
    cellIndices: [
      ...new Set(
        [...pinSet]
          .map((pin) => index.pins[pin].cell)
          .filter((cell) => cell !== null),
      ),
    ],
    coverage: {
      pins: pinSet.size,
      arcs: arcSet.size,
      missingTiming,
      unsupportedFrontiers: unsupported,
      cyclic,
    },
    registeredDelayNs: registered.delayNs,
    registeredTiming: registered.description,
    staticDelayNs:
      !missingTiming && !unsupported && !cyclic
        ? Math.max(...rootPins.map((pin) => arrival.get(pin) ?? 0))
        : null,
  };
  index.cones.set(key, result);
  return result;
}

/** Masks select declared destination bits, while each physical sink/root is
 * shared. Unknown bindings remain counted; a neighboring mapped bit cannot fill them. */
function writeCones(index, operation) {
  if (index.writeCones.has(operation.event))
    return index.writeCones.get(operation.event);
  const roots = new Map();
  let requestedBits = 0,
    mappedBits = 0;
  for (const target of operation.targets) {
    const resource = index.model.resources.get(target.resource),
      selected = mask(target.mask, resource.width);
    const bits = index.bindings.get(target.resource);
    for (let bitIndex = 0; bitIndex < resource.width; bitIndex++) {
      if (!(selected & (1n << BigInt(bitIndex)))) continue;
      requestedBits++;
      const bit = bits?.get(bitIndex);
      if (
        bit?.status !== "supported" ||
        bit.q === undefined ||
        bit.q === null ||
        bit.d === undefined ||
        bit.d === null
      )
        continue;
      mappedBits++;
      roots.set(`${bit.d}/data`, { pin: bit.d, role: "data" });
      for (const [field, role] of [
        ["ce", "enable"],
        ["reset", "reset"],
        ["set", "reset"],
      ])
        if (bit[field] !== undefined && bit[field] !== null)
          roots.set(`${bit[field]}/${role}`, { pin: bit[field], role });
      for (const control of bit.controls ?? [])
        roots.set(`${control.pin}/${control.role}`, control);
    }
  }
  const result = {
    cones: [...ROLES].flatMap((role) => {
      const pins = [...roots.values()]
        .filter((item) => item.role === role)
        .map((item) => item.pin);
      return pins.length ? [cone(index, pins, role)] : [];
    }),
    coverage: {
      requestedBits,
      mappedBits,
      unknownBits: requestedBits - mappedBits,
    },
  };
  index.writeCones.set(operation.event, result);
  return result;
}

/** Return unions only for the caller's visible event set; the retained tables and
 * complete event coverage never change. Producer selection follows its explicit
 * writes. One static arc is drawn once per clock, with every occurrence retained.
 * Whole-cone timing is the default; registered_launch filters only the separate
 * sequential-Q-launched bound. Neither choice removes topology from a cone. */
export function computationLayers(
  index,
  visibleEvents,
  {
    roles = ["data", "enable", "reset"],
    minimumDelayNs = 0,
    includeUnknownTiming = true,
    timingMetric = "whole_cone",
  } = {},
) {
  if (!index) return [];
  requireValue(
    Array.isArray(roles) &&
      roles.every((role) => ROLES.has(role)) &&
      Number.isFinite(minimumDelayNs) &&
      minimumDelayNs >= 0 &&
      ["whole_cone", "registered_launch"].includes(timingMetric),
    "invalid display filter",
  );
  const allowedRoles = new Set(roles),
    layers = new Map(),
    seenWrites = new Set();
  for (const supplied of visibleEvents) {
    const id = typeof supplied === "string" ? supplied : supplied.id;
    const operation = index.operations.get(id);
    if (!operation) continue;
    const writes =
      operation.applicability === "storage_write"
        ? [id]
        : (operation.writes ?? []);
    for (const write of writes) {
      if (seenWrites.has(write)) continue;
      seenWrites.add(write);
      const event = index.model.events.get(write),
        op = index.operations.get(write);
      const geometry = writeCones(index, op);
      const selected = geometry.cones.filter((item) => {
        const delay =
          timingMetric === "registered_launch"
            ? item.registeredDelayNs
            : item.staticDelayNs;
        return (
          allowedRoles.has(item.role) &&
          (delay === null ? includeUnknownTiming : delay >= minimumDelayNs)
        );
      });
      if (!layers.has(event.cycle))
        layers.set(event.cycle, {
          cycle: event.cycle,
          timingMetric,
          operations: [],
          cones: new Map(),
          cells: new Set(),
          pins: new Set(),
          arcs: new Set(),
          coverage: {
            requestedBits: 0,
            mappedBits: 0,
            unknownBits: 0,
            filteredCones: 0,
          },
        });
      const layer = layers.get(event.cycle);
      layer.operations.push(op);
      for (const field of ["requestedBits", "mappedBits", "unknownBits"])
        layer.coverage[field] += geometry.coverage[field];
      layer.coverage.filteredCones += geometry.cones.length - selected.length;
      for (const item of selected) {
        if (layer.cones.has(item.id)) continue;
        layer.cones.set(item.id, item);
        for (const cell of item.cellIndices) layer.cells.add(cell);
        for (const pin of item.pinIndices) layer.pins.add(pin);
        for (const arc of item.arcIndices) layer.arcs.add(arc);
      }
    }
  }
  return [...layers.values()]
    .sort((a, b) => a.cycle - b.cycle)
    .map((layer) => ({
      ...layer,
      cones: [...layer.cones.values()],
      cells: [...layer.cells],
      pins: [...layer.pins],
      arcs: [...layer.arcs],
    }));
}

/** A routed branch is independent of the number of execution occurrences.
 * Logic arcs retain native cell connectivity; only net arcs request wire geometry. */
export function computationConnection(index, arcIndex) {
  const arc = reference(arcIndex, index.arcs, "arc");
  if (arc.kind !== "net") return null;
  return nativeConnection(
    index.routing,
    index.nets[arc.net].id,
    index.pins[arc.from].id,
    index.pins[arc.to].id,
  );
}
