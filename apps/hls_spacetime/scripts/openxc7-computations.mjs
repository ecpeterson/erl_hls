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

/** Build only measured net arcs and LUT inputs, preserving missing delays and unqualified bits. */
export function openxc7Computations(view, packed, timing, words, modelInfo) {
  const cells = [],
    pins = [],
    nets = [],
    arcs = [],
    pinIndex = new Map(),
    netIndex = new Map();
  const cellNames = Object.keys(timing.cells).sort();
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
  for (const id of cellNames) {
    const raw = timing.cells[id],
      cell = packed[id];
    if (!cell || raw.type !== cell.type)
      throw Error("Packed timing cell mismatch");
    const kind = cell.type;
    const boundary =
      kind === "SLICE_FFX"
        ? "sequential"
        : kind === "SLICE_LUTX"
          ? "combinational"
          : ["PSEUDO_GND", "PSEUDO_VCC"].includes(kind)
            ? "constant"
            : "unsupported";
    const index = cells.length;
    cells.push({ id, kind, boundary });
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
    if (boundary !== "combinational") continue;
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
        if (ps === null && !cell.attributes["X_ORIG_PORT_" + input]) continue;
        arc(
          "logic",
          pinIndex.get(id + "/" + input),
          pinIndex.get(id + "/" + output),
          ps,
          row?.model ?? "unavailable",
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
      if (reset === undefined) throw Error("Qualified packed reset pin absent");
      return {
        ...bit,
        reset,
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
