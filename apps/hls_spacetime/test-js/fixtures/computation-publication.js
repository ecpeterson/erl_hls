import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";

/** A single real-shaped FF write exercises file publication and loader closure. */
export async function sourceFixture(t, fork = false) {
  const root = await mkdtemp(join(tmpdir(), "spacetime-render-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const input = join(root, "source"),
    output = join(root, "prepared");
  await mkdir(join(input, "computations"), { recursive: true });
  const save = async (file, value) => {
    const b = Buffer.from(JSON.stringify(value));
    await writeFile(join(input, file), b);
    return {
      file,
      bytes: b.length,
      sha256: createHash("sha256").update(b).digest("hex"),
    };
  };
  const build = {
      source: "a".repeat(64),
      rtl: "b".repeat(64),
      observation: "c".repeat(64),
      implementation: "f".repeat(64),
    },
    checkpoint = "d".repeat(64);
  const event = {
    id: "w",
    cycle: 0,
    sequence: 0,
    observer: "o",
    incarnation: "i",
    actor: "a",
    operation: "register_write",
    inputs: ["root"],
    outputs: ["value"],
    access: {
      resource: "word",
      kind: "write",
      before: "root",
      after_version: "value",
      mask: "0x1",
    },
  };
  const cells = [{ id: "ff", kind: "FDRE", boundary: "sequential" }],
    bindings = [
      { resource: "word", bits: [{ bit: 0, status: "supported", q: 0, d: 1 }] },
    ];
  if (fork)
    cells.push(
      { id: "slow-ff", kind: "FDRE", boundary: "sequential" },
      { id: "join", kind: "LUT2", boundary: "combinational" },
    );
  const view = {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      capture: {
        complete: true,
        first_cycle: 0,
        end_cycle: 2,
        observers: [{ id: "o", gaps: [] }],
        incarnations: [{ id: "i", first_cycle: 0, end_cycle: 2 }],
      },
      resources: [{ id: "word", kind: "ff", width: 1, depth: 1 }],
      events: [event],
      relations: [],
      versions: [
        {
          id: "root",
          producer: "root",
          origin: "unknown",
          incarnation: "i",
          storage: { resource: "word", address: 0 },
        },
        {
          id: "value",
          producer: "w",
          origin: "event",
          incarnation: "i",
          storage: { resource: "word", address: 0 },
        },
      ],
    },
    catalogue: {
      build,
      checkpoint,
      cells: cells.map((cell, i) => ({ ...cell, x: 10 + i * 10, y: 20 })),
      bindings: [{ resource: "word", bits: [] }],
    },
  };
  const recording = await save("recording.json", view);
  const tables = {
    cells,
    pins: [
      { id: "ff/Q", cell: 0, pin: "Q", direction: "OUT", net: 0 },
      { id: "ff/D", cell: 0, pin: "D", direction: "IN", net: 0 },
    ],
    nets: [{ id: "feedback" }],
    arcs: [
      {
        id: "a",
        kind: "net",
        from: 0,
        to: 1,
        net: 0,
        timing: { fast: [{ maxPs: 10 }], slow: [{ maxPs: 20 }] },
      },
    ],
    bindings,
    operations: [
      {
        event: "w",
        applicability: "storage_write",
        status: "located",
        targets: [{ resource: "word", mask: "0x1" }],
        sources: [],
        unknowns: [],
        writes: [],
      },
    ],
    routeNets: [
      {
        id: "feedback",
        status: "complete",
        route_status: "ROUTED",
        nodes: [],
        pips: [],
        issues: [],
        pin_attachments: [],
      },
    ],
  };
  if (fork) {
    tables.pins = [
      { id: "ff/Q", cell: 0, pin: "Q", direction: "OUT", net: 0 },
      { id: "ff/D", cell: 0, pin: "D", direction: "IN", net: 2 },
      { id: "slow-ff/Q", cell: 1, pin: "Q", direction: "OUT", net: 1 },
      { id: "join/I0", cell: 2, pin: "I0", direction: "IN", net: 0 },
      { id: "join/I1", cell: 2, pin: "I1", direction: "IN", net: 1 },
      { id: "join/O", cell: 2, pin: "O", direction: "OUT", net: 2 },
    ];
    tables.nets = [{ id: "short" }, { id: "long" }, { id: "shared" }];
    tables.arcs = [
      { id: "short-in", kind: "net", from: 0, to: 3, net: 0, ns: 1 },
      { id: "long-in", kind: "net", from: 2, to: 4, net: 1, ns: 3 },
      { id: "short-logic", kind: "logic", from: 3, to: 5, cell: 2, ns: 2 },
      { id: "long-logic", kind: "logic", from: 4, to: 5, cell: 2, ns: 4 },
      { id: "shared-out", kind: "net", from: 5, to: 1, net: 2, ns: 1 },
    ].map(({ ns, ...arc }) => ({
      ...arc,
      timing: { fast: [{ maxPs: ns * 1000 }], slow: [{ maxPs: ns * 1000 }] },
    }));
    tables.routeNets = tables.nets.map(({ id }) => ({
      ...tables.routeNets[0],
      id,
    }));
  }
  const parts = [];
  for (const [table, rows] of Object.entries(tables)) {
    const p = await save(`computations/${table}.json`, rows);
    parts.push({ ...p, file: `${table}.json`, table, rows: rows.length });
  }
  const computations = await save("computations/manifest.json", {
    format: "spacetime-computations-manifest",
    schema: 1,
    view: { bytes: recording.bytes, sha256: recording.sha256 },
    build,
    checkpoint,
    parts,
    totals: Object.fromEntries(
      Object.entries(tables).map(([k, v]) => [k, v.length]),
    ),
    attachment: {
      schema: 1,
      scope: "structural_native_connectivity",
      build,
      nativeBuild: build,
      checkpoint,
      routingComplete: true,
    },
  });
  await save("index.json", {
    format: "spacetime-view-index",
    schema: 1,
    examples: [{ ...recording, title: "Synthetic", computations }],
  });
  return { input, output, view, recording, computations };
}
