#!/usr/bin/env node
/** Join an existing recording to complete saved native connectivity and SDF.
 * This offline preparation never invokes synthesis, routing or a simulator.
 * The output is a complete chunked attachment, not a selected-path sample. */
import { createHash } from "node:crypto";
import { readFile, stat, mkdir, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { gunzipSync } from "node:zlib";
import { openArchive, readVerifiedBytes } from "./prepare-example.mjs";
import { createModel } from "../web/model.js";
import { validateObservationRevisionOrigin } from "./observation-revision.mjs";

const MAX_INPUT = 256 * 1024 * 1024;
const MAX_PART = 32 * 1024 * 1024;
const MAX_TOTAL = 512 * 1024 * 1024;
const TABLES = ["cells", "pins", "nets", "arcs", "bindings", "operations"];
const SEQUENTIAL = new Set(["FDRE", "FDSE", "FDCE", "FDPE"]);

/** Reject incomplete joins; a successful artifact never contains a clipped prefix. */
function check(condition, reason) {
  if (!condition) throw Error(`Prepare computations: ${reason}`);
}

/** Exact byte receipts bind each local input independently of semantic equality. */
function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
function sameBuild(a, b) {
  return ["source", "rtl", "observation", "implementation"].every(
    (key) => a?.[key] === b?.[key],
  );
}

/** TSV is the exporter's escaped cell format; decode only its documented escapes. */
export function table(bytes, columns) {
  const lines = new TextDecoder("utf-8", { fatal: true })
    .decode(bytes)
    .split("\n");
  if (lines.at(-1) === "") lines.pop();
  check(lines.shift() === columns.join("\t"), `wrong TSV columns ${columns}`);
  return lines.map((line) => {
    const values = line.split("\t");
    check(values.length === columns.length, "TSV field count");
    check(
      values.every((value) => /^(?:[^\\]|\\[\\tnr])*$/.test(value)),
      "invalid TSV escape",
    );
    return Object.fromEntries(
      columns.map((column, i) => [
        column,
        values[i].replace(
          /\\([\\tnr])/g,
          (_, c) => ({ "\\": "\\", t: "\t", n: "\n", r: "\r" })[c],
        ),
      ]),
    );
  });
}

/** Native catalogue references must stay unique and exact. */
function index(rows, key, label) {
  const result = new Map();
  rows.forEach((row, i) => {
    check(
      typeof row[key] === "string" && row[key] && !result.has(row[key]),
      `duplicate ${label}`,
    );
    result.set(row[key], i);
  });
  return result;
}

/** Observation extensions retain the original finite-Q correspondence chain. */
function originalBuild(view, build, checkpoint) {
  check(view.catalogue?.checkpoint === checkpoint, "checkpoint mismatch");
  check(
    ["source", "rtl"].every((k) => view.bundle.build[k] === build[k]),
    "source/RTL mismatch",
  );
  if (sameBuild(view.catalogue.build, build)) return;
  let origin = view.catalogue.correspondence_origin,
    newerBuild = view.catalogue.build;
  for (
    let i = 0;
    origin && i < 64;
    i++, origin = origin.previous_correspondence
  ) {
    check(
      origin.checkpoint === checkpoint &&
        ["source", "rtl"].every((k) => origin.build?.[k] === build[k]),
      "invalid correspondence chain",
    );
    if (origin.kind === "observation-reinterpretation") {
      validateObservationRevisionOrigin(
        origin,
        newerBuild,
        view.bundle.capture,
        checkpoint,
      );
    }
    if (sameBuild(origin.build, build)) return;
    newerBuild = origin.build;
  }
  throw Error(
    "Prepare computations: original native build absent from correspondence chain",
  );
}

/** The graph distinguishes cuts at sequential state, constants and unsupported primitives. */
function boundary(kind) {
  if (SEQUENTIAL.has(kind)) return "sequential";
  if (kind === "GND" || kind === "VCC") return "constant";
  if (
    /^LUT[1-6]$/.test(kind) ||
    ["CARRY4", "CARRY8", "MUXF7", "MUXF8", "MUXF9"].includes(kind)
  )
    return "combinational";
  return "unsupported";
}

/** Top-level input ports drive nets; primitive output pins drive nets. */
function driver(pin) {
  return pin.cell === null ? pin.direction === "IN" : pin.direction === "OUT";
}
function sink(pin) {
  return pin.cell === null ? pin.direction === "OUT" : pin.direction === "IN";
}

/** All connectivity arcs are retained. SDF contributes exact primitive timing arcs;
 * absent net timing remains unknown rather than deleting native connectivity. */
export function nativeGraph({
  view,
  manifest,
  cells: cellRows,
  nets: netRows,
  pins: pinRows,
  ports: portRows,
  fast,
  slow,
}) {
  check(manifest.complete === true, "incomplete native export");
  originalBuild(view, manifest.build, manifest.checkpoint.sha256);
  check(
    cellRows.length <= 100000 &&
      netRows.length <= 100000 &&
      pinRows.length + portRows.length <= 1000000,
    "native population limit",
  );
  const cells = cellRows.map((row) => ({
    id: row.name,
    kind: row.ref,
    boundary: boundary(row.ref),
  }));
  const cellIndex = index(cells, "id", "cell");
  const viewCells = new Map(view.catalogue.cells.map((c) => [c.id, c]));
  check(
    viewCells.size === cells.length &&
      cells.every((c) => viewCells.get(c.id)?.kind === c.kind),
    "view/native cells differ",
  );
  const nets = netRows.map((row) => ({
    id: row.name,
    type: row.type,
    routeStatus: row.route_status,
    timingStatus: row.timing_status,
  }));
  const netIndex = index(nets, "id", "net");
  const pins = pinRows.map((row) => {
    check(
      cellIndex.has(row.cell) && netIndex.has(row.net),
      "unknown pin cell/net",
    );
    check(
      row.pin === `${row.cell}/${row.ref_pin}`,
      "native pin spelling mismatch",
    );
    return {
      id: row.pin,
      cell: cellIndex.get(row.cell),
      pin: row.ref_pin,
      direction: row.direction,
      net: netIndex.get(row.net),
      kind: "pin",
    };
  });
  pins.push(
    ...portRows.map((row) => {
      check(netIndex.has(row.net), "unknown port net");
      return {
        id: row.port,
        cell: null,
        pin: row.port,
        direction: row.direction,
        net: netIndex.get(row.net),
        kind: "port",
      };
    }),
  );
  const pinIndex = index(pins, "id", "pin");
  const netPins = Array.from({ length: nets.length }, () => []);
  pins.forEach((pin, i) => {
    check(
      ["IN", "OUT", "INOUT"].includes(pin.direction),
      "unknown native direction",
    );
    netPins[pin.net].push(i);
  });
  const arcs = [],
    arcIndex = new Map(),
    issues = [];
  function edge(kind, from, to, net) {
    const key = `${kind}/${from}/${to}`;
    if (arcIndex.has(key)) return arcs[arcIndex.get(key)];
    check(arcs.length < 2000000, "native arc population limit");
    const arc = {
      id: key,
      kind,
      from,
      to,
      timing: { fast: [], slow: [] },
      timingStatus: "missing",
    };
    if (net !== undefined) arc.net = net;
    arcIndex.set(key, arcs.length);
    arcs.push(arc);
    return arc;
  }
  netPins.forEach((members, net) => {
    const drivers = members.filter((i) => driver(pins[i])),
      sinks = members.filter((i) => sink(pins[i]));
    if (
      members.some((i) => pins[i].direction === "INOUT") ||
      drivers.length !== 1
    )
      issues.push({
        kind: "net_direction",
        net: nets[net].id,
        drivers: drivers.length,
        inout: members.filter((i) => pins[i].direction === "INOUT").length,
      });
    for (const from of drivers)
      for (const to of sinks) edge("net", from, to, net);
  });
  for (const [corner, projection] of [
    ["fast", fast],
    ["slow", slow],
  ]) {
    check(
      projection.schema === 1 &&
        projection.source?.corner === corner &&
        projection.source?.mode === "sta",
      "SDF projection provenance",
    );
    check(
      projection.source.sha256 === manifest.sdf[corner].sha256 &&
        projection.source.bytes === manifest.sdf[corner].bytes,
      "SDF source identity mismatch",
    );
    check(
      Array.isArray(projection.arcs) &&
        projection.arcs.length <= 2000000 &&
        Array.isArray(projection.issues),
      "SDF population limit",
    );
    check(
      projection.issues.length === 0,
      `SDF ${corner} projection has uninterpreted delay forms (${projection.issues.length})`,
    );
    for (const source of projection.arcs) {
      check(
        ["iopath", "interconnect"].includes(source.kind),
        "unsupported projected arc",
      );
      const fromName =
        source.kind === "iopath"
          ? `${source.cell}/${source.from}`
          : source.cell
            ? `${source.cell}/${source.from}`
            : source.from;
      const toName =
        source.kind === "iopath"
          ? `${source.cell}/${source.to}`
          : source.cell
            ? `${source.cell}/${source.to}`
            : source.to;
      check(
        pinIndex.has(fromName) && pinIndex.has(toName),
        `unresolved SDF endpoint ${fromName} -> ${toName}`,
      );
      const from = pinIndex.get(fromName),
        to = pinIndex.get(toName),
        a = pins[from],
        b = pins[to];
      let arc;
      if (source.kind === "interconnect") {
        check(
          a.net === b.net && driver(a) && sink(b),
          "SDF net endpoint mismatch",
        );
        check(
          arcIndex.has(`net/${from}/${to}`),
          "SDF interconnect absent from connectivity",
        );
        arc = edge("net", from, to, a.net);
      } else {
        check(
          a.cell !== null &&
            a.cell === b.cell &&
            a.direction === "IN" &&
            b.direction === "OUT",
          "SDF primitive endpoint mismatch",
        );
        arc = edge("logic", from, to);
      }
      check(
        Array.isArray(source.guards) &&
          Array.isArray(source.delay) &&
          (source.max_ps === null || Number.isFinite(source.max_ps)),
        "SDF timing shape",
      );
      arc.timing[corner].push({
        transition: source.transition,
        guards: source.guards,
        delay: source.delay,
        maxPs: source.max_ps,
      });
    }
  }
  for (const arc of arcs)
    arc.timingStatus =
      arc.timing.fast.length && arc.timing.slow.length
        ? "available"
        : arc.timing.fast.length || arc.timing.slow.length
          ? "partial"
          : "missing";
  return { cells, pins, nets, arcs, issues, cellIndex, pinIndex, netPins };
}

/** Width/mask operations never pass through imprecise JavaScript numbers. */
function encodedMask(value, width) {
  check(
    typeof value === "string" && /^0x[0-9a-f]+$/i.test(value),
    "invalid encoded mask",
  );
  const mask = BigInt(value);
  check(mask > 0n && mask < 1n << BigInt(width), "mask outside encoded width");
  return `0x${mask.toString(16)}`;
}

/** A qualified Q identifies its actual primitive; D/control association comes
 * from that cell's exact native pin catalogue, not a guessed RTL register name. */
export function physicalBindings(view, graph) {
  const resources = new Map(view.bundle.resources.map((r) => [r.id, r]));
  const bindings = [];
  const originals = new Map(
    view.catalogue.bindings.map((binding) => [binding.resource, binding]),
  );
  const storageIds = new Set(
    view.bundle.resources
      .filter((r) => r.kind !== "logic" && Number.isSafeInteger(r.width))
      .map((r) => r.id),
  );
  for (const event of view.bundle.events)
    if (event.access) storageIds.add(event.access.resource);
  for (const id of storageIds) {
    const binding = originals.get(id) ?? {
      resource: id,
      bits: [],
      evidence: "No original physical binding for this storage resource",
    };
    const resource = resources.get(binding.resource);
    check(
      resource && Number.isSafeInteger(resource.width) && resource.width > 0,
      "binding resource width",
    );
    const byBit = new Map((binding.bits ?? []).map((b) => [b.bit, b]));
    check(byBit.size === (binding.bits ?? []).length, "duplicate bound bit");
    const bits = Array.from({ length: resource.width }, (_, bit) => {
      const original = byBit.get(bit);
      if (!original || original.status !== "supported")
        return {
          bit,
          status: "unknown",
          reason:
            original?.evidence ??
            "No qualified original native Q correspondence",
        };
      const q = graph.pinIndex.get(`${original.cell}/${original.pin}`);
      check(q !== undefined, "qualified Q absent from complete native pins");
      const qp = graph.pins[q],
        cell = graph.cells[qp.cell];
      check(
        qp.direction === "OUT" &&
          qp.pin === "Q" &&
          cell?.boundary === "sequential",
        "qualified bit is not native FF Q",
      );
      const row = {
        bit,
        status: "supported",
        q,
        evidence: original.evidence ?? binding.evidence,
      };
      for (const [key, names] of [
        ["d", ["D"]],
        ["ce", ["CE"]],
        ["reset", ["R", "CLR"]],
        ["set", ["S", "PRE"]],
      ]) {
        const candidates = names
          .map((name) => graph.pinIndex.get(`${cell.id}/${name}`))
          .filter((i) => i !== undefined);
        check(candidates.length <= 1, `ambiguous ${key} pin`);
        if (candidates.length) {
          check(
            graph.pins[candidates[0]].direction === "IN",
            `invalid ${key} direction`,
          );
          row[key] = candidates[0];
        }
      }
      if (row.d === undefined)
        row.reason = "Qualified Q has no catalogued D pin";
      return row;
    });
    bindings.push({
      resource: resource.id,
      width: resource.width,
      evidence: binding.evidence,
      bits,
    });
  }
  return bindings;
}

/** Producer sidecar roles identify the selected bits of recorded operand
 * reads. Reconcile their union with those exact reads, not with a same-shaped
 * register elsewhere. This checks saved source consistency, not gate activity. */
function operandReads(model, row, computation) {
  const declared = new Map();
  for (const field of ["data_masks", "control_masks"]) {
    const masks = row[field];
    check(
      masks && typeof masks === "object" && !Array.isArray(masks),
      "ancestry mask table",
    );
    for (const [name, mask] of Object.entries(masks)) {
      const resource = `register/${name}`,
        r = model.resources.get(resource);
      if (!r || !Number.isSafeInteger(r.width)) continue;
      const bits = BigInt(encodedMask(mask, r.width));
      declared.set(resource, (declared.get(resource) ?? 0n) | bits);
    }
  }
  check(
    Array.isArray(row.unknown) &&
      row.unknown.every((item) => typeof item === "string") &&
      typeof row.value_checked === "boolean",
    "ancestry evidence fields",
  );
  const reads = new Map();
  check(
    new Set(computation.inputs).size === computation.inputs.length,
    "duplicate ancestry operand input",
  );
  for (const id of computation.inputs) {
    const version = model.versions.get(id);
    if (version.producer === "root") {
      check(
        version.origin === "unknown" && version.storage === null,
        "ancestry operand is not a transient unknown root",
      );
      continue;
    }
    const result = model.events.get(version.producer),
      access = result?.access;
    check(
      version.storage === null && access?.kind === "read_result",
      "ancestry operand lacks recorded read result",
    );
    const request = model.events.get(access.request),
      requested = request?.access;
    check(
      requested?.kind === "read_request",
      "ancestry operand lacks recorded read request",
    );
    check(
      [result, request].every(
        (event) =>
          event.cycle === computation.cycle &&
          event.incarnation === computation.incarnation,
      ),
      "ancestry operand occurrence mismatch",
    );
    check(
      access.resource === requested.resource &&
        access.version === requested.version &&
        (access.address ?? 0) === (requested.address ?? 0) &&
        access.port === requested.port,
      "ancestry operand request/result identity mismatch",
    );
    const stored = model.versions.get(access.version),
      resource = model.resources.get(access.resource);
    check(
      stored?.storage?.resource === access.resource &&
        (stored.storage.address ?? 0) === (access.address ?? 0) &&
        [result, request].every(
          (event) =>
            event.inputs.length === 1 && event.inputs[0] === access.version,
        ),
      "ancestry operand stored-version mismatch",
    );
    check(
      resource && Number.isSafeInteger(resource.width),
      "ancestry operand resource width",
    );
    const mask = encodedMask(access.read_mask, resource.width);
    check(
      mask === encodedMask(requested.read_mask, resource.width),
      "ancestry operand request/result mask mismatch",
    );
    check(!reads.has(access.resource), "duplicate ancestry operand resource");
    reads.set(access.resource, BigInt(mask));
  }
  check(
    declared.size === reads.size &&
      [...declared].every(([resource, bits]) => reads.get(resource) === bits),
    "ancestry source masks differ from recorded operand reads",
  );
}

/** Every event receives a disposition, including writes whose transient producer
 * is publication logic rather than a register_compute event. Operational masks
 * annotate source boundaries; they never prune a structural native cone. */
export function operations(view, ancestry, bindings) {
  const model = createModel(view),
    byBinding = new Map(bindings.map((b) => [b.resource, b]));
  check(
    ancestry === null ||
      (ancestry?.schema === 1 && Array.isArray(ancestry.operands)),
    "ancestry schema",
  );
  const operands = new Map();
  for (const row of ancestry?.operands ?? []) {
    const computation = model.events.get(row.event),
      write = model.events.get(row.write);
    check(
      computation &&
        write?.access?.kind === "write" &&
        !operands.has(row.write),
      "ancestry event/write identity",
    );
    check(
      computation.cycle === write.cycle &&
        computation.incarnation === write.incarnation,
      "ancestry occurrence mismatch",
    );
    check(
      computation.outputs.some((v) => write.inputs.includes(v)),
      "ancestry producer does not feed write",
    );
    operandReads(model, row, computation);
    operands.set(row.write, row);
  }
  const rows = new Map(
    [...model.events.values()].map((event) => [
      event.id,
      {
        event: event.id,
        kind: event.operation,
        role: "context",
        applicability: "semantic_context",
        status: "not_applicable",
        targets: [],
        sources: [],
        writes: [],
        producers: [],
        unknowns: [],
      },
    ]),
  );
  function source(row, resource, mask, kind) {
    const r = model.resources.get(resource);
    if (!r || !Number.isSafeInteger(r.width)) {
      row.unknowns.push(`Unrepresented ${kind} source ${resource}`);
      return;
    }
    const normalized = mask === null ? null : encodedMask(mask, r.width);
    if (
      !row.sources.some(
        (s) =>
          s.resource === resource && s.mask === normalized && s.kind === kind,
      )
    )
      row.sources.push({ resource, mask: normalized, kind });
  }
  function classify(targets, sources) {
    let known = 0,
      unknown = 0;
    for (const entry of [...targets, ...sources]) {
      const binding = byBinding.get(entry.resource);
      if (entry.mask === null) {
        unknown++;
        continue;
      }
      const mask = BigInt(entry.mask),
        width = model.resources.get(entry.resource)?.width;
      for (let i = 0; i < width; i++)
        if (mask & (1n << BigInt(i))) {
          if (
            binding?.bits[i]?.status === "supported" &&
            (!targets.includes(entry) || binding.bits[i].d !== undefined)
          )
            known++;
          else unknown++;
        }
    }
    return known ? (unknown ? "partial" : "located") : "unlocated";
  }
  for (const event of model.events.values()) {
    const row = rows.get(event.id),
      access = event.access;
    if (access?.kind === "write") {
      const resource = model.resources.get(access.resource);
      check(
        resource && Number.isSafeInteger(resource.width),
        "write resource width",
      );
      row.role = "write";
      row.applicability = "storage_write";
      row.writes = [event.id];
      row.targets = [
        {
          resource: access.resource,
          mask: encodedMask(access.mask, resource.width),
        },
      ];
      row.producers = [
        ...new Set(
          event.inputs
            .map((id) => model.versions.get(id))
            .filter((v) => v && v.storage === null && v.producer !== "root")
            .map((v) => v.producer),
        ),
      ];
      const operand = operands.get(event.id);
      if (operand) {
        for (const [kind, field] of [
          ["data", "data_masks"],
          ["control", "control_masks"],
        ])
          for (const [name, mask] of Object.entries(operand[field]))
            source(row, `register/${name}`, mask, kind);
        row.unknowns.push(...operand.unknown);
        row.valueChecked = operand.value_checked;
      } else {
        row.unknowns.push(
          "No selected scalar operand masks; recorded producer lineage retained",
        );
        for (const id of event.inputs) {
          const version = model.versions.get(id);
          if (version?.storage)
            source(row, version.storage.resource, null, "unclassified");
        }
      }
      row.status = classify(row.targets, row.sources);
    } else if (
      access &&
      ["read_request", "read_result"].includes(access.kind)
    ) {
      row.role = "read";
      row.applicability = "storage_read";
      source(row, access.resource, access.read_mask ?? null, "unclassified");
      if (access.read_mask === undefined)
        row.unknowns.push("Read subset not observed");
      row.status = classify([], row.sources);
    } else if (access?.kind === "hold") {
      row.role = "hold";
      row.applicability = "storage_hold";
      row.status = "not_applicable";
      row.unknowns.push(
        "Residence observation is not a new combinational write",
      );
    } else if (access) {
      row.applicability = "unsupported";
      row.status = "unlocated";
      row.unknowns.push(`Unsupported access ${access.kind}`);
    }
  }
  for (const row of rows.values())
    if (row.role === "write") {
      for (const id of row.producers) {
        const producer = rows.get(id);
        check(producer, "write producer absent");
        if (producer.role !== "context" && producer.role !== "producer")
          continue;
        producer.role = "producer";
        producer.applicability = "producer";
        producer.writes.push(row.event);
        for (const target of row.targets)
          if (
            !producer.targets.some(
              (t) => t.resource === target.resource && t.mask === target.mask,
            )
          )
            producer.targets.push({ ...target });
        for (const s of row.sources)
          source(producer, s.resource, s.mask, s.kind);
        producer.unknowns.push(...row.unknowns);
        producer.status = classify(producer.targets, producer.sources);
      }
    }
  return [...rows.values()];
}

/** Deterministic inspectable demand contains every canonical net and native endpoint. */
export function routeDemand(graph, manifest, catalogueSha256) {
  return {
    schema_version: 1,
    build: manifest.build,
    checkpoint_sha256: manifest.checkpoint.sha256,
    catalogue_sha256: catalogueSha256,
    nets: graph.nets
      .map((net, i) => ({
        id: net.id,
        type: net.type,
        route_status: net.routeStatus,
        pins: graph.netPins[i]
          .map((p) => ({
            pin: graph.pins[p].id,
            kind: graph.pins[p].kind,
            direction: graph.pins[p].direction,
          }))
          .sort((a, b) => a.pin.localeCompare(b.pin)),
      }))
      .sort((a, b) => a.id.localeCompare(b.id)),
  };
}

/** Tcl list elements use double-quoted literals with all substitutions escaped. */
function tcl(value) {
  return (
    '"' +
    String(value).replace(
      /[\\"$\[\]\n\r]/g,
      (c) => ({ "\n": "\\n", "\r": "\\r" })[c] ?? `\\${c}`,
    ) +
    '"'
  );
}
export function demandTcl(demand, sha256) {
  const build = Object.entries(demand.build)
    .map(([k, v]) => `${tcl(k)} ${tcl(v)}`)
    .join(" ");
  const nets = demand.nets
    .map(
      (net) =>
        `[dict create id ${tcl(net.id)} type ${tcl(net.type)} route_status ${tcl(net.route_status)} pins [list ${net.pins.map((pin) => `[dict create pin ${tcl(pin.pin)} kind ${tcl(pin.kind)} direction ${tcl(pin.direction)}]`).join(" ")}]]`,
    )
    .join(" ");
  return `return [dict create schema_version 1 build [dict create ${build}] checkpoint_sha256 ${tcl(demand.checkpoint_sha256)} catalogue_sha256 ${tcl(demand.catalogue_sha256)} demand_sha256 ${tcl(sha256)} nets [list ${nets}]]\n`;
}

/** Bound both packed and decoded bytes before allocating local evidence. */
async function input(path, limit = MAX_INPUT) {
  const info = await stat(path);
  check(info.isFile() && info.size <= limit, "input size/type");
  const packed = await readFile(path),
    bytes = path.endsWith(".gz")
      ? gunzipSync(packed, { maxOutputLength: limit })
      : packed;
  check(bytes.length <= limit, "decoded input limit");
  return {
    bytes,
    identity: {
      file: basename(path),
      bytes: bytes.length,
      sha256: digest(bytes),
      packedBytes: packed.length,
      packedSha256: digest(packed),
    },
  };
}

/** Streaming table chunks bound every JSON part without truncating table rows. */
export async function publish(out, attachment, viewIdentity) {
  await mkdir(out, { recursive: false });
  const parts = [],
    totals = {};
  let total = 0;
  for (const name of TABLES) {
    const rows = attachment[name];
    totals[name] = rows.length;
    let items = [],
      bytes = 2,
      number = 0;
    async function flush() {
      if (!items.length) return;
      const data = Buffer.from(`[${items.join(",")}]\n`),
        file = `${name}-${number++}.json`;
      check(
        data.length <= MAX_PART && (total += data.length) <= MAX_TOTAL,
        "output retention limit",
      );
      await writeFile(join(out, file), data, { flag: "wx" });
      parts.push({
        file,
        table: name,
        bytes: data.length,
        sha256: digest(data),
        rows: items.length,
      });
      items = [];
      bytes = 2;
    }
    for (const row of rows) {
      const encoded = JSON.stringify(row),
        size = Buffer.byteLength(encoded) + 1;
      check(size + 3 <= MAX_PART, "single row exceeds chunk limit");
      if (bytes + size + 1 > MAX_PART) await flush();
      items.push(encoded);
      bytes += size;
    }
    await flush();
  }
  const scalar = Object.fromEntries(
    Object.entries(attachment).filter(([k]) => !TABLES.includes(k)),
  );
  const result = {
    format: "spacetime-computations-manifest",
    schema: 1,
    view: { bytes: viewIdentity.bytes, sha256: viewIdentity.sha256 },
    build: attachment.build,
    checkpoint: attachment.checkpoint,
    parts,
    totals,
    attachment: scalar,
  };
  await writeFile(join(out, "manifest.json"), JSON.stringify(result) + "\n", {
    flag: "wx",
  });
  return result;
}

/** Read only the native tables needed for the graph. An ordinary exporter
 * manifest declares row/byte counts; older exports do not declare table hashes.
 * Such inputs retain computed receipts and explicitly weaker verification.
 * Caller-owned terminal collection verification remains required. A retained
 * archive additionally checks each requested file against its archive manifest. */
export async function readNative(directory) {
  const root = resolve(directory);
  const outer = await input(join(root, "manifest.json"), 1024 * 1024);
  const description = JSON.parse(outer.bytes);
  const raw = description?.format === "spacetime_physical_export";
  let archive = null,
    manifestBytes,
    manifest;
  if (raw) {
    check(outer.bytes.length <= 65536, "native manifest limit");
    manifestBytes = outer.bytes;
    manifest = description;
  } else {
    archive = await openArchive(root, "native");
    check(
      archive.manifest_sha256 === outer.identity.sha256,
      "archive manifest changed",
    );
    manifestBytes = await readVerifiedBytes(
      archive,
      "catalogue/manifest.json.gz",
    );
    manifest = JSON.parse(manifestBytes);
  }
  check(
    manifest?.format === "spacetime_physical_export" &&
      manifest.schema === 1 &&
      manifest.complete === true,
    "incomplete or unsupported native export",
  );
  const columns = {
    cells: [
      "name",
      "ref",
      "site",
      "bel",
      "tile",
      "x",
      "y",
      "clock_region",
      "placement",
    ],
    nets: ["name", "route_status", "type", "flat_pin_count", "timing_status"],
    pins: ["net", "pin", "cell", "ref_pin", "direction"],
    ports: ["net", "port", "direction"],
  };
  const tables = {},
    rawSources = [],
    tableVerification = [];
  for (const [name, header] of Object.entries(columns)) {
    const file = `${name}.tsv`,
      meta = manifest.tables?.[file];
    check(
      meta &&
        Number.isSafeInteger(meta.rows) &&
        meta.rows >= 0 &&
        meta.rows <= 2000000 &&
        Number.isSafeInteger(meta.bytes) &&
        meta.bytes >= 0 &&
        meta.bytes <= MAX_INPUT,
      `invalid ${name} table inventory`,
    );
    const local = raw ? await input(join(root, file)) : null;
    const bytes = raw
      ? local.bytes
      : await readVerifiedBytes(archive, `catalogue/${file}.gz`);
    check(bytes.length === meta.bytes, `${name} byte count mismatch`);
    const declaredHash = Object.hasOwn(meta, "sha256");
    if (declaredHash) {
      check(
        typeof meta.sha256 === "string" && /^[a-f0-9]{64}$/.test(meta.sha256),
        `invalid ${name} table hash`,
      );
      check(digest(bytes) === meta.sha256, `${name} declared hash mismatch`);
    }
    tables[name] = table(bytes, header);
    check(tables[name].length === meta.rows, `${name} population mismatch`);
    const verification = declaredHash
      ? "declared_hash_bytes_and_rows"
      : "declared_bytes_and_rows";
    tableVerification.push(verification);
    if (raw)
      rawSources.push({
        file,
        raw_bytes: bytes.length,
        raw_sha256: local.identity.sha256,
        verification,
      });
  }
  return {
    manifest,
    manifestBytes,
    tables,
    provenance: {
      format: raw ? "native_export" : "retained_archive",
      verification: raw
        ? tableVerification.every((v) => v === "declared_hash_bytes_and_rows")
          ? "declared_hash_bytes_and_rows"
          : "declared_bytes_and_rows"
        : "archive_manifest_hashes",
      manifest: outer.identity,
      scope:
        "Only required graph tables are read here. The caller verifies terminal collection/checkpoint integrity; computed receipts do not authenticate measurements.",
    },
    sources: raw ? rawSources : archive.sources,
  };
}

/** Explicit ordinary-export or retained-archive input; no native tool is invoked. */
export async function prepare(options) {
  const [v, a, f, s] = await Promise.all([
    input(options.view),
    options.ancestry ? input(options.ancestry) : null,
    input(options.fast),
    input(options.slow),
  ]);
  const view = JSON.parse(v.bytes),
    ancestry = a ? JSON.parse(a.bytes) : null,
    fast = JSON.parse(f.bytes),
    slow = JSON.parse(s.bytes);
  const native = await readNative(options.native);
  const { manifest, manifestBytes, tables } = native;
  const graph = nativeGraph({ view, manifest, ...tables, fast, slow });
  const bindings = physicalBindings(view, graph),
    rows = operations(view, ancestry, bindings);
  const coverage = {
    events: rows.length,
    writes: rows.filter((r) => r.applicability === "storage_write").length,
    applicability: Object.fromEntries(
      [...new Set(rows.map((r) => r.applicability))]
        .sort()
        .map((k) => [k, rows.filter((r) => r.applicability === k).length]),
    ),
    status: Object.fromEntries(
      [...new Set(rows.map((r) => r.status))]
        .sort()
        .map((k) => [k, rows.filter((r) => r.status === k).length]),
    ),
    nativeIssues: graph.issues,
    operandEvidence: ancestry ? "supplied_producer_sidecar" : "not_supplied",
  };
  const attachment = {
    schema: 1,
    scope: "structural_native_connectivity",
    build: view.bundle.build,
    checkpoint: manifest.checkpoint.sha256,
    nativeBuild: manifest.build,
    inputs: {
      view: v.identity,
      ancestry: a?.identity ?? null,
      fast: f.identity,
      slow: s.identity,
      catalogueManifestSha256: digest(manifestBytes),
      native: native.provenance,
      sources: native.sources,
    },
    evidence:
      "Complete saved native connectivity associated through retained finite-Q correspondence. Native D/CE/reset activity and gate sensitization are unmeasured. Selected source masks annotate, never prune, structural cones.",
    coverage,
    cells: graph.cells,
    pins: graph.pins,
    nets: graph.nets,
    arcs: graph.arcs,
    bindings,
    operations: rows,
  };
  const result = await publish(resolve(options.out), attachment, v.identity);
  const demand = routeDemand(graph, manifest, digest(manifestBytes)),
    demandBytes = Buffer.from(JSON.stringify(demand) + "\n");
  await writeFile(join(options.out, "demand.json"), demandBytes, {
    flag: "wx",
  });
  await writeFile(
    join(options.out, "demand.tcl"),
    demandTcl(demand, digest(demandBytes)),
    { flag: "wx" },
  );
  return {
    manifest: result,
    coverage,
    demand: {
      nets: demand.nets.length,
      pins: demand.nets.reduce((n, r) => n + r.pins.length, 0),
      sha256: digest(demandBytes),
    },
  };
}

/** Explicit paths avoid dependence on campaign names or private checkout layout. */
async function main(args) {
  if (args.length === 1 && args[0] === "--help") {
    process.stdout.write(
      "Usage: prepare-computations.mjs --view VIEW [--ancestry ANCESTRY] --native NATIVE_EXPORT_OR_ARCHIVE --fast FAST_ARCS --slow SLOW_ARCS --out NEW_DIRECTORY\n",
    );
    return;
  }
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    check(
      [
        "--view",
        "--ancestry",
        "--native",
        "--fast",
        "--slow",
        "--out",
      ].includes(args[i]) && args[i + 1],
      "invalid option",
    );
    options[args[i].slice(2)] = args[i + 1];
  }
  check(
    ["view", "native", "fast", "slow", "out"].every((k) => options[k]),
    "missing option",
  );
  process.stdout.write(JSON.stringify(await prepare(options)) + "\n");
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
)
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
