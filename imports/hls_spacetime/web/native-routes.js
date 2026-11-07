import { nativePaths } from "./native-paths.js";

/** Validate a hash-bound native routing attachment and select only each static
 * timing arc's source-to-sink branch. Wire rows are unordered tile footprints,
 * not metal-track polylines or evidence of dynamic sensitization. */
const LIMITS = {
  branches: 51200,
  nets: 4096,
  nodes: 131072,
  pips: 262144,
  wires: 524288,
  attachments: 262144,
  work: 8_000_000,
};

/** Reject inconsistent evidence instead of manufacturing a plausible route. */
function requireValue(condition, message) {
  if (!condition) throw Error(`Native routes: ${message}`);
}

/** Native identities remain exact strings; no hierarchy or coordinate inference. */
function text(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 4096;
}

/** Digests refer to exact external bytes, authenticated by the attachment loader. */
function digest(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

/** Compare all compiler/capture identities without depending on object key order. */
function buildKey(build) {
  requireValue(
    build &&
      ["source", "rtl", "observation"].every((key) => digest(build[key])),
    "invalid build identity",
  );
  return [build.source, build.rtl, build.observation].join("/");
}

/** Collect bounded, explicitly reviewed capture-origin links while retaining the
 * original native observation identity rather than rebinding the route file. */
function origins(detail, current, checkpoint) {
  requireValue(
    buildKey(detail.build) === buildKey(current),
    "current build mismatch",
  );
  const result = [{ build: buildKey(current), witness: "current" }];
  let origin = detail.correspondence_origin;
  while (origin) {
    requireValue(result.length <= 16, "correspondence chain too deep");
    const comparison = origin.comparison;
    requireValue(
      origin.checkpoint === checkpoint &&
        origin.build?.source === current.source &&
        origin.build?.rtl === current.rtl &&
        [
          "base_projection_sha256",
          "original_trace_sha256",
          "extended_trace_sha256",
          "simulator_sha256",
        ].every((key) => digest(origin[key])) &&
        comparison?.old_taps_equal === true &&
        comparison.public_fields_equal === true &&
        Number.isSafeInteger(comparison.original_taps) &&
        comparison.original_taps > 0 &&
        Number.isSafeInteger(comparison.first_cycle) &&
        Number.isSafeInteger(comparison.end_cycle) &&
        comparison.end_cycle > comparison.first_cycle &&
        comparison.compared_cycles ===
          comparison.end_cycle - comparison.first_cycle,
      "unqualified correspondence origin",
    );
    const build = buildKey(origin.build);
    result.push({
      build,
      witness: JSON.stringify([
        build,
        origin.checkpoint,
        origin.base_projection_sha256,
        origin.original_trace_sha256,
        origin.extended_trace_sha256,
        origin.simulator_sha256,
        comparison.original_taps,
        comparison.first_cycle,
        comparison.end_cycle,
        comparison.compared_cycles,
      ]),
    });
    origin = origin.previous_correspondence;
  }
  return result;
}

/** Bound aggregate graph records and traversal work, not just each individual net. */
function spend(budget, kind, count = 1) {
  budget[kind] = (budget[kind] ?? 0) + count;
  requireValue(budget[kind] <= LIMITS[kind], `${kind} limit exceeded`);
}

/** A tile has one native grid coordinate everywhere; unavailable locations stay null. */
function location(row, tiles) {
  if (row.x === null && row.y === null) {
    requireValue(
      row.tile === null || text(row.tile),
      "invalid unavailable tile",
    );
    return;
  }
  requireValue(
    text(row.tile) &&
      [row.x, row.y].every(
        (v) => Number.isSafeInteger(v) && v >= 0 && v <= 1_000_000,
      ),
    "invalid native tile coordinate",
  );
  const previous = tiles.get(row.tile);
  requireValue(
    !previous || (previous.x === row.x && previous.y === row.y),
    "tile coordinate disagreement",
  );
  tiles.set(row.tile, { x: row.x, y: row.y });
}

/** Native pin direction is recorded independently of static-path branch selection. */
function direction(value) {
  return ["IN", "OUT", "INOUT"].includes(value);
}

/** Validate one used-net graph once; repeated timing paths reuse these indexes. */
function netGraph(net, budget, tiles) {
  requireValue(
    text(net.id) && text(net.status) && text(net.route_status),
    "invalid net identity/status",
  );
  requireValue(
    Array.isArray(net.nodes) &&
      Array.isArray(net.pips) &&
      Array.isArray(net.pin_attachments) &&
      Array.isArray(net.issues),
    "missing net graph tables",
  );
  spend(budget, "nodes", net.nodes.length);
  spend(budget, "pips", net.pips.length);
  spend(budget, "attachments", net.pin_attachments.length);
  const nodes = new Map(),
    pips = new Map(),
    pins = new Map(),
    wires = new Set();
  for (const node of net.nodes) {
    requireValue(
      text(node.id) && !nodes.has(node.id) && Array.isArray(node.wires),
      "duplicate/invalid routing node",
    );
    spend(budget, "wires", node.wires.length);
    for (const wire of node.wires) {
      requireValue(
        text(wire.id) && !wires.has(wire.id),
        "duplicate/invalid native wire",
      );
      wires.add(wire.id);
      location(wire, tiles);
    }
    nodes.set(node.id, node);
  }
  const forward = new Map(),
    backward = new Map();
  let unknownEndpoints = false;
  const edge = (from, to, pip) => {
    const item = { from, to, pip };
    if (!forward.has(from)) forward.set(from, []);
    if (!backward.has(to)) backward.set(to, []);
    forward.get(from).push(item);
    backward.get(to).push(item);
  };
  for (const pip of net.pips) {
    requireValue(text(pip.id) && !pips.has(pip.id), "duplicate/invalid PIP");
    requireValue(
      ["directional", "bidirectional", "unavailable"].includes(
        pip.direction_status,
      ),
      "invalid PIP direction disposition",
    );
    location(pip, tiles);
    for (const endpoint of [pip.from_node, pip.to_node])
      requireValue(
        endpoint === null || nodes.has(endpoint),
        "PIP endpoint outside used net",
      );
    if (pip.from_node === null || pip.to_node === null) {
      requireValue(
        pip.direction_status === "unavailable",
        "directed PIP lacks endpoints",
      );
      unknownEndpoints = true;
    } else {
      edge(pip.from_node, pip.to_node, pip);
      if (pip.direction_status !== "directional")
        edge(pip.to_node, pip.from_node, pip);
    }
    pips.set(pip.id, pip);
  }
  for (const pin of net.pin_attachments) {
    requireValue(
      text(pin.pin) &&
        !pins.has(pin.pin) &&
        (direction(pin.direction) ||
          (pin.status === "unavailable" && pin.direction === null)),
      "duplicate/invalid native pin attachment",
    );
    requireValue(
      ["resolved", "intrasite", "unavailable", "ambiguous"].includes(
        pin.status,
      ),
      "invalid pin attachment disposition",
    );
    requireValue(
      Array.isArray(pin.bel_pins) &&
        pin.bel_pins.every(text) &&
        new Set(pin.bel_pins).size === pin.bel_pins.length,
      "invalid BEL pin mapping",
    );
    requireValue(Array.isArray(pin.site_pins), "missing site pin mappings");
    const siteIds = new Set();
    for (const site of pin.site_pins) {
      requireValue(
        text(site.id) && !siteIds.has(site.id),
        "duplicate/invalid site pin",
      );
      requireValue(
        site.node === null || nodes.has(site.node),
        "site pin node outside used net",
      );
      siteIds.add(site.id);
    }
    requireValue(
      pin.routing_node === null || nodes.has(pin.routing_node),
      "pin routing node outside used net",
    );
    if (pin.status === "resolved")
      requireValue(
        pin.routing_node !== null &&
          pin.site_pins.every((site) => site.node !== null) &&
          new Set(pin.site_pins.map((site) => site.node)).size === 1 &&
          pin.site_pins.some((site) => site.node === pin.routing_node),
        "resolved pin lacks unique native site/node mapping",
      );
    else
      requireValue(
        pin.routing_node === null,
        "unresolved pin invents routing node",
      );
    pins.set(pin.pin, pin);
  }
  for (const issue of net.issues)
    requireValue(
      [issue.stage, issue.object, issue.reason].every(text),
      "invalid native route issue",
    );
  return { net, nodes, pips, pins, forward, backward, unknownEndpoints };
}

/** Traverse the possible native graph without recursion or choosing a shortest path. */
function reachable(start, adjacency, reverse, budget, allowed) {
  const seen = new Set([start]),
    queue = [start];
  for (let index = 0; index < queue.length; index++) {
    for (const edge of adjacency.get(queue[index]) ?? []) {
      spend(budget, "work");
      const next = reverse ? edge.from : edge.to;
      if (allowed.has(next) && !seen.has(next)) {
        seen.add(next);
        queue.push(next);
      }
    }
  }
  return seen;
}

/** Remove nonterminal leaves before directional reachability. This excludes
 * dangling fanout even when a bidirectional PIP would permit an artificial
 * out-and-back walk; no simple source-to-sink path can use such a leaf. */
function corridorNodes(graph, start, end, budget) {
  const incident = new Map([...graph.nodes.keys()].map((id) => [id, []]));
  for (const pip of graph.pips.values()) {
    incident.get(pip.from_node).push(pip);
    incident.get(pip.to_node).push(pip);
  }
  const degree = new Map(
    [...incident].map(([id, edges]) => [id, edges.length]),
  );
  const remaining = new Set(graph.nodes.keys());
  const queue = [...remaining].filter(
    (id) => id !== start && id !== end && degree.get(id) <= 1,
  );
  for (let i = 0; i < queue.length; i++) {
    const id = queue[i];
    if (!remaining.delete(id)) continue;
    for (const pip of incident.get(id)) {
      spend(budget, "work");
      const neighbour = pip.from_node === id ? pip.to_node : pip.from_node;
      if (!remaining.has(neighbour)) continue;
      degree.set(neighbour, degree.get(neighbour) - 1);
      if (
        neighbour !== start &&
        neighbour !== end &&
        degree.get(neighbour) <= 1
      )
        queue.push(neighbour);
    }
  }
  return remaining;
}

/** Native site/node attachment establishes identity, not the intra-site wire shape. */
function pinGap(pin, end) {
  return {
    kind: "intrasite",
    end,
    pin: pin.pin,
    node: pin.routing_node,
    belPins: pin.bel_pins,
    sitePins: pin.site_pins,
    reason:
      pin.status === "resolved"
        ? "Native pin/site/node correspondence is known; intra-site wire geometry is not supplied"
        : `Native pin attachment ${pin.status}`,
  };
}

/** Unresolved branches contain no guessed geometry, even when a full net is present. */
function unresolved(graph, disposition, reason, gaps) {
  return {
    disposition,
    nodes: [],
    pips: [],
    gaps: [...gaps, { kind: "route", reason }],
    excludedNodes: graph.nodes.size,
    excludedPips: graph.pips.size,
    geometry: "native_wire_tiles_and_pip_locations",
  };
}

/** Resolve only a unique directed used-PIP branch. Relevant reverse-capable or
 * unknown edges, reconvergence and cycles stay explicit rather than guessed. */
function branchBetween(graph, source, target, budget) {
  requireValue(
    (source.direction === null ||
      ["OUT", "INOUT"].includes(source.direction)) &&
      (target.direction === null || ["IN", "INOUT"].includes(target.direction)),
    "timing endpoint direction mismatch",
  );
  const gaps = [pinGap(source, "source"), pinGap(target, "target")];
  if (source.status !== "resolved" || target.status !== "resolved") {
    const disposition = [source.status, target.status].includes("ambiguous")
      ? "ambiguous"
      : [source.status, target.status].includes("intrasite")
        ? "intrasite"
        : "unavailable";
    return unresolved(
      graph,
      disposition,
      "Native endpoint route-node correspondence is incomplete",
      gaps,
    );
  }
  const start = source.routing_node,
    end = target.routing_node;
  if (graph.unknownEndpoints)
    return unresolved(
      graph,
      "ambiguous",
      "A used PIP has unknown endpoints; branch uniqueness is unproven",
      gaps,
    );
  let orderedNodes = [graph.nodes.get(start)],
    orderedPips = [];
  if (start !== end) {
    const possible = corridorNodes(graph, start, end, budget);
    const fromSource = reachable(start, graph.forward, false, budget, possible);
    if (!fromSource.has(end))
      return unresolved(
        graph,
        "missing",
        "No supplied used-PIP path reaches the selected sink",
        gaps,
      );
    const toTarget = reachable(end, graph.backward, true, budget, possible);
    const relevant = new Set([...fromSource].filter((id) => toTarget.has(id)));
    const edges = [...graph.pips.values()].filter(
      (pip) => relevant.has(pip.from_node) && relevant.has(pip.to_node),
    );
    if (edges.some((pip) => pip.direction_status !== "directional"))
      return unresolved(
        graph,
        "ambiguous",
        "Selected corridor contains a PIP without qualified direction",
        gaps,
      );
    const indegree = new Map([...relevant].map((id) => [id, 0]));
    for (const pip of edges)
      indegree.set(pip.to_node, indegree.get(pip.to_node) + 1);
    const queue = [...relevant].filter((id) => indegree.get(id) === 0),
      counts = new Map([[start, 1]]);
    for (let i = 0; i < queue.length; i++) {
      for (const edge of graph.forward.get(queue[i]) ?? []) {
        spend(budget, "work");
        if (!relevant.has(edge.to)) continue;
        counts.set(
          edge.to,
          Math.min(
            2,
            (counts.get(edge.to) ?? 0) + (counts.get(edge.from) ?? 0),
          ),
        );
        indegree.set(edge.to, indegree.get(edge.to) - 1);
        if (indegree.get(edge.to) === 0) queue.push(edge.to);
      }
    }
    if (queue.length !== relevant.size || counts.get(end) !== 1)
      return unresolved(
        graph,
        "ambiguous",
        "Selected corridor has a cycle or multiple native branches",
        gaps,
      );
    let current = start;
    while (current !== end) {
      const next = (graph.forward.get(current) ?? []).filter((edge) =>
        relevant.has(edge.to),
      );
      requireValue(next.length === 1, "unique branch reconstruction disagrees");
      orderedPips.push(next[0].pip);
      current = next[0].to;
      orderedNodes.push(graph.nodes.get(current));
    }
  }
  for (const node of orderedNodes) {
    if (!node.wires.length || node.wires.some((wire) => wire.x === null))
      gaps.push({
        kind: "wire_location",
        node: node.id,
        reason: "Some native wire tile coordinates are unavailable",
      });
  }
  for (const pip of orderedPips)
    if (pip.x === null)
      gaps.push({
        kind: "pip_location",
        pip: pip.id,
        reason: "Native PIP tile coordinates are unavailable",
      });
  return {
    disposition: "resolved",
    nodes: orderedNodes,
    pips: orderedPips,
    gaps,
    excludedNodes: graph.nodes.size - orderedNodes.length,
    excludedPips: graph.pips.size - orderedPips.length,
    geometry: "native_wire_tiles_and_pip_locations",
  };
}

/** Preserve every native mapping while considering only explicitly located
 * candidates. Null site-node mappings are unresolved, never proven unused. */
function candidates(pin) {
  if (!["resolved", "ambiguous"].includes(pin.status)) return [];
  return [
    ...new Set(
      pin.site_pins.map((site) => site.node).filter((node) => node !== null),
    ),
  ];
}

/** Select a unique admissible located attachment pair. A source candidate with
 * incoming directed used routing is an interior shortcut, not a driver root.
 * Unlocated site alternatives retain a partial disposition and explicit gap. */
function branch(graph, sourcePin, targetPin, budget) {
  const source = graph.pins.get(sourcePin),
    target = graph.pins.get(targetPin);
  requireValue(source && target, "timing endpoint missing native attachment");
  const sourceNodes = candidates(source),
    targetNodes = candidates(target);
  const roots = sourceNodes.filter(
    (id) =>
      !(graph.backward.get(id) ?? []).some(
        (edge) =>
          edge.pip.direction_status === "directional" && edge.from !== id,
      ),
  );
  const gaps = [pinGap(source, "source"), pinGap(target, "target")];
  if (!sourceNodes.length || !targetNodes.length) {
    if (graph.net.route_status === "INTRASITE")
      return unresolved(
        graph,
        "intrasite",
        "Native net has no exported inter-site routing branch",
        gaps,
      );
    return branchBetween(graph, source, target, budget);
  }
  if (!roots.length)
    return unresolved(
      graph,
      "ambiguous",
      "Every located source candidate is interior to directed used routing",
      gaps,
    );
  if (roots.length * targetNodes.length > 64)
    return unresolved(
      graph,
      "ambiguous",
      "Native attachment candidate-pair limit exceeded",
      gaps,
    );
  const alternatives = [];
  for (const start of roots)
    for (const end of targetNodes) {
      const locatedSource = {
        ...source,
        status: "resolved",
        routing_node: start,
      };
      const locatedTarget = {
        ...target,
        status: "resolved",
        routing_node: end,
      };
      alternatives.push({
        start,
        end,
        result: branchBetween(graph, locatedSource, locatedTarget, budget),
      });
    }
  const found = alternatives.filter(
    (candidate) => candidate.result.disposition === "resolved",
  );
  if (
    found.length !== 1 ||
    alternatives.some(
      (candidate) =>
        !["resolved", "missing"].includes(candidate.result.disposition),
    )
  )
    return unresolved(
      graph,
      found.length === 0 &&
        alternatives.every(
          (candidate) => candidate.result.disposition === "missing",
        )
        ? "missing"
        : "ambiguous",
      "Native attachment candidates do not identify exactly one admissible branch",
      gaps,
    );
  const selected = found[0],
    unlocated = [source, target].some((pin) =>
      pin.site_pins.some((site) => site.node === null),
    );
  const endpointGaps = [
    [source, "source", selected.start, sourceNodes],
    [target, "target", selected.end, targetNodes],
  ].map(([pin, end, chosen, known]) => ({
    ...pinGap(pin, end),
    node: chosen,
    observedStatus: pin.status,
    locatedCandidates: known,
    unresolvedSitePins: pin.site_pins
      .filter((site) => site.node === null)
      .map((site) => site.id),
    reason:
      "Unique branch among explicitly located admissible native attachments; intra-site wire geometry remains unavailable" +
      (pin.site_pins.some((site) => site.node === null)
        ? "; additional site-node mappings are unresolved, not proven unused"
        : ""),
  }));
  return {
    ...selected.result,
    disposition: unlocated ? "partial" : "resolved",
    gaps: [
      ...endpointGaps,
      ...selected.result.gaps.filter((gap) => gap.kind !== "intrasite"),
    ],
  };
}

/** Return canonical per-static-path-arc route records, with ordered native nodes
 * and PIPs plus unordered wire tile rows per node. Missing attachments/branches
 * and ambiguity produce explicit dispositions without guessed geometry. A unique
 * located branch with unresolved site alternatives remains explicitly partial.
 *
 * The loader must verify exact input bytes. This function checks build and
 * reviewed capture-origin correspondence, checkpoint, report/selection digests,
 * saved arc identity and bounded graph structure. It adds no execution edges,
 * never attributes activity to a clock, and never sorts wire tiles into a fake
 * polyline. Repeated references share one cached branch reconstruction. */
export function nativeRoutes(model, detail = model.document.nativeRoutes) {
  if (!detail) return [];
  const timing = model.document.nativePaths,
    catalogue = model.catalogue;
  requireValue(
    detail.schema_version === 1 &&
      detail.complete === true &&
      detail.scope === "static_route_topology" &&
      detail.coordinate_unit === "tile_grid",
    "unsupported route attachment",
  );
  requireValue(
    catalogue && timing && timing.scope === "static_timing",
    "missing physical/static timing source",
  );
  requireValue(
    digest(detail.checkpoint_sha256) &&
      detail.checkpoint_sha256 === catalogue.checkpoint &&
      timing.checkpoint === catalogue.checkpoint,
    "checkpoint mismatch",
  );
  requireValue(
    digest(detail.report_sha256) &&
      detail.report_sha256 === timing.report_sha256,
    "saved report digest mismatch",
  );
  requireValue(
    digest(detail.selection_sha256) &&
      detail.selection_sha256 === timing.route_selection_sha256,
    "selection digest mismatch",
  );
  const current = model.bundle.build;
  const physicalOrigins = origins(catalogue, current, catalogue.checkpoint);
  const timingOrigins = origins(timing, current, catalogue.checkpoint);
  requireValue(
    JSON.stringify(physicalOrigins) === JSON.stringify(timingOrigins),
    "physical/static timing origin disagreement",
  );
  requireValue(
    physicalOrigins.some((origin) => origin.build === buildKey(detail.build)),
    "native build absent from qualified origin chain",
  );
  requireValue(
    Array.isArray(detail.nets) &&
      detail.nets.length <= LIMITS.nets &&
      Array.isArray(detail.paths) &&
      detail.paths.length <= LIMITS.branches,
    "route attachment limit exceeded",
  );
  const budget = {},
    tiles = new Map(),
    nets = new Map();
  for (const net of detail.nets) {
    requireValue(!nets.has(net.id), "duplicate canonical net");
    nets.set(net.id, netGraph(net, budget, tiles));
  }
  const checkedPaths = nativePaths(model);
  const paths = new Map(checkedPaths.map((path) => [path.id, path]));
  requireValue(
    paths.size === timing.paths.length,
    "duplicate static path identity",
  );
  const expected = new Set();
  for (const path of checkedPaths)
    path.arcs.forEach((arc, index) => {
      if (arc.kind === "net") expected.add(`${path.id}/${index}`);
    });
  requireValue(
    detail.paths.length === expected.size,
    "incomplete selected route arc coverage",
  );
  const seen = new Set(),
    cache = new Map();
  const routes = detail.paths.map((row) => {
    const path = paths.get(row.path_id),
      index = row.arc_index;
    requireValue(
      path &&
        Number.isSafeInteger(index) &&
        index >= 0 &&
        index < 512 &&
        Array.isArray(path.arcs),
      "missing static timing arc",
    );
    const arc = path.arcs[index],
      key = `${row.path_id}/${index}`;
    requireValue(
      expected.has(key) && !seen.has(key),
      "duplicate or unselected static arc",
    );
    seen.add(key);
    requireValue(
      arc?.kind === "net" &&
        arc.net === row.report_net &&
        arc.source === row.source_pin &&
        arc.target === row.target_pin &&
        path.steps[index]?.pin === row.source_pin &&
        path.steps[index + 1]?.pin === row.target_pin,
      "static timing arc identity mismatch",
    );
    const graph = nets.get(row.canonical_net);
    requireValue(graph, "selected canonical net missing");
    const cacheKey = JSON.stringify([
      row.canonical_net,
      row.source_pin,
      row.target_pin,
    ]);
    if (!cache.has(cacheKey))
      cache.set(
        cacheKey,
        branch(graph, row.source_pin, row.target_pin, budget),
      );
    return {
      pathId: row.path_id,
      arcIndex: index,
      reportNet: row.report_net,
      canonicalNet: row.canonical_net,
      sourcePin: row.source_pin,
      targetPin: row.target_pin,
      ...cache.get(cacheKey),
    };
  });
  requireValue(
    seen.size === expected.size,
    "incomplete selected route arc coverage",
  );
  return routes;
}
