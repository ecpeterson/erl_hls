/** Adapt one verified nextpnr timing model to the ordinary computation-cone renderer. */
import { operations, physicalBindings } from "./prepare-computations.mjs";

/** Reconcile original packed-port annotations with the actual connected net at that port. */
function originAt(cell, port, actual) {
  const attrs = cell.attributes,
    origin = attrs.SPACETIME_CELL;
  if (!origin) return null;
  const retained = attrs["X_ORIG_PORT_" + port];
  if (!retained) return null;
  const originals = retained
    .trim()
    .split(/\s+/)
    .map((p) =>
      p === "O" && attrs.SPACETIME_OUTPUT ? attrs.SPACETIME_OUTPUT : p,
    );
  return originals.every(
    (p) =>
      actual.net_origin && attrs["SPACETIME_PORT_" + p] === actual.net_origin,
  )
    ? { cell: origin, ports: originals }
    : null;
}

/** The XC7 packer shares a LUT cell type between logic, shift registers and distributed RAM. */
function boundary({ type, attributes }) {
  if (type === "CARRY4" && attributes.X_ORIG_TYPE === "CARRY4")
    return "combinational";
  if (
    type === "SELMUX2_1" &&
    ["MUXF7", "MUXF8"].includes(attributes.X_ORIG_TYPE)
  )
    return "combinational";
  if (
    /^IOB(18|33)_INBUF(_DCIEN)?$/.test(type) &&
    attributes.X_ORIG_TYPE === "IBUF"
  )
    return "external";
  if (type === "SLICE_FFX") return "sequential";
  if (type === "PSEUDO_GND" || type === "PSEUDO_VCC") return "constant";
  if (
    type === "SLICE_LUTX" &&
    /^LUT[1-6]$/.test(attributes.X_ORIG_TYPE) &&
    !Object.hasOwn(attributes, "X_LUT_AS_SRL") &&
    !Object.hasOwn(attributes, "X_LUT_AS_DRAM")
  )
    return "combinational";
  return "unsupported";
}

/** The carry mux selects DI[i] or the previous carry. XOR output O[i] uses the incoming carry. */
function carryDependency(input, output) {
  const target = /^(CO|O)([0-3])$/.exec(output);
  if (!target) return false;
  if (input === "CIN" || input === "CYINIT") return true;
  const source = /^(DI|S)([0-3])$/.exec(input);
  return Boolean(
    source &&
      (+source[2] < +target[2] ||
        (source[2] === target[2] && (source[1] === "S" || target[1] === "CO"))),
  );
}

/** Qualify a packer-created LUT1 tied low before physical pin sharing. Check the
 * surviving output, the original driver, and the LUT6 half selected by tied-high A6.
 * With no input correspondence its configured upper half repeats INIT[0]. */
function groundedBuffer(cell, raw, drivers) {
  const buffer = raw.lut_buffer;
  if (!buffer || cell.type !== "SLICE_LUTX") return false;
  const attrs = cell.attributes,
    output = raw.ports.O6,
    source = drivers.get(buffer.input_net),
    select = drivers.get(raw.ports.A6?.net);
  return (
    attrs.X_ORIG_TYPE === "LUT1" &&
    attrs.X_ORIG_PORT_O6 === "O" &&
    /\/[^/]*6LUT$/.test(attrs.NEXTPNR_BEL) &&
    /^0*10$/.test(cell.parameters?.INIT) &&
    !Object.keys(attrs).some((key) => /^X_ORIG_PORT_A[1-6]$/.test(key)) &&
    !Object.hasOwn(attrs, "X_LUT_AS_SRL") &&
    !Object.hasOwn(attrs, "X_LUT_AS_DRAM") &&
    Object.values(raw.ports).filter((p) => p.direction === "OUT").length ===
      1 &&
    output?.bound === true &&
    output.net === buffer.output_net &&
    source?.type === "PSEUDO_GND" &&
    source.cell === buffer.driver &&
    source.port === buffer.driver_port &&
    raw.ports.A6?.bound === true &&
    select?.type === "PSEUDO_VCC"
  );
}

/** Build only measured net arcs and LUT inputs, preserving missing delays and unqualified bits. */
export function openxc7Computations(
  view,
  packed,
  timing,
  words,
  modelInfo,
  packedNets = [],
) {
  const cells = [],
    pins = [],
    nets = [],
    arcs = [],
    pinIndex = new Map(),
    netIndex = new Map();
  const cellNames = Object.keys(packed).sort();
  const constants = new Map();
  for (const [cell, raw] of Object.entries(timing.cells)) {
    if (!["PSEUDO_GND", "PSEUDO_VCC"].includes(raw.type)) continue;
    for (const [port, p] of Object.entries(raw.ports)) {
      if (p.direction !== "OUT" || !p.bound) continue;
      if (constants.has(p.net))
        throw Error("Conflicting native constant drivers");
      constants.set(p.net, { cell, port, type: raw.type });
    }
  }
  const roots = timing.roots ?? [];
  if (
    Object.keys(timing.cells).some((id) => !Object.hasOwn(packed, id)) ||
    roots.some((id) => timing.cells[id]?.type !== "SLICE_FFX")
  )
    throw Error("Foreign timing cell or missing focus root");
  function netId(net) {
    if (!netIndex.has(net)) {
      netIndex.set(net, nets.length);
      nets.push({ id: net, type: "signal" });
    }
    return netIndex.get(net);
  }
  function arc(kind, from, to, ps, basis, net) {
    if (from === undefined || to === undefined)
      throw Error("Uncatalogued nextpnr arc endpoint");
    arcs.push({
      id: JSON.stringify([kind, from, to]),
      kind,
      from,
      to,
      net,
      timing: { model: "nextpnr-xilinx", basis, delayPs: ps },
      timingStatus: ps === null ? "missing" : "available",
    });
  }
  for (const net of packedNets) netId(net);
  for (const id of cellNames) {
    const raw = timing.cells[id],
      cell = packed[id];
    if (!raw && roots.length) {
      cells.push({ id, kind: cell.type, boundary: "unsupported" });
      continue;
    }
    if (!raw || raw.type !== cell.type)
      throw Error("Packed timing cell mismatch");
    const kind = cell.type;
    const cellBoundary =
      modelInfo.bram_model_sha256 &&
      /^(RAMB18E1_RAMB18E1|RAMB36E1_RAMB36E1)$/.test(kind)
        ? "hard_block"
        : groundedBuffer(cell, raw, constants)
          ? "constant"
          : boundary(cell);
    const index = cells.length;
    cells.push({ id, kind, boundary: cellBoundary });
    for (const [port, p] of Object.entries(raw.ports)) {
      const name = id + "/" + port;
      if (pinIndex.has(name)) throw Error("Duplicate nextpnr pin");
      pinIndex.set(name, pins.length);
      pins.push({
        id: name,
        pin: port,
        cell: index,
        net: netId(p.net),
        direction: p.direction,
        origin: originAt(cell, port, p),
        clocks: p.clocks,
        timingClass: p.class,
      });
    }
    if (cellBoundary !== "combinational") continue;
    const delays = new Map(
      raw.arcs.map((row) => [JSON.stringify([row.from, row.to]), row]),
    );
    for (const [input, p] of Object.entries(raw.ports)) {
      if (p.class !== "comb_input") continue;
      for (const [output, q] of Object.entries(raw.ports)) {
        if (q.class !== "comb_output") continue;
        const row = delays.get(JSON.stringify([input, output])),
          ps = row?.delay_ps ?? null;
        // A shared physical LUT pin can have no logical role in this half.
        if (kind === "CARRY4" && !carryDependency(input, output)) continue;
        if (
          kind === "SELMUX2_1" &&
          (!["0", "1", "S0"].includes(input) || output !== "OUT")
        )
          continue;
        if (
          kind === "SLICE_LUTX" &&
          ps === null &&
          !cell.attributes["X_ORIG_PORT_" + input]
        )
          continue;
        arc(
          "logic",
          pinIndex.get(id + "/" + input),
          pinIndex.get(id + "/" + output),
          ps,
          kind === "CARRY4" &&
            input.startsWith("DI") &&
            modelInfo.carry_di_model &&
            ps !== null
            ? "chipdb_CARRY4_variant_envelope"
            : (row?.model ?? "unavailable"),
        );
      }
    }
  }
  for (const row of timing.sinks) {
    if (row.source === null) continue;
    arc(
      "net",
      pinIndex.get(row.source + "/" + row.output),
      pinIndex.get(row.sink + "/" + row.input),
      row.delay_ps,
      row.model,
      netId(row.net),
    );
  }
  const bindings = physicalBindings(view, { cells, pins, pinIndex });
  const byResource = new Map(
    words.map((w) => [w.resource, new Map(w.bits.map((b) => [b.bit, b]))]),
  );
  for (const binding of bindings) {
    binding.bits = binding.bits.map((bit) => {
      const qualified = byResource.get(binding.resource)?.get(bit.bit);
      if (
        bit.status !== "supported" ||
        qualified?.status !== "supported" ||
        pins[bit.q].id !== qualified.cell + "/Q"
      )
        return {
          bit: bit.bit,
          status: "unknown",
          reason: "Missing matching original and packed bit qualification",
        };
      const reset = pinIndex.get(qualified.cell + "/" + qualified.roles.reset);
      if (reset === undefined && qualified.local_controls?.SR !== 0)
        throw Error("Qualified packed reset pin absent");
      return {
        ...bit,
        reset,
        localControls: qualified.local_controls,
        packedPrimitive: "FDRE",
        initial: qualified.initial,
        edge: qualified.edge,
      };
    });
  }
  return {
    schema: 1,
    scope: "structural_native_connectivity",
    build: view.bundle.build,
    checkpoint: view.catalogue.checkpoint,
    cells,
    pins,
    nets,
    arcs,
    bindings,
    operations: operations(view, null, bindings),
    timingModel: modelInfo,
  };
}
