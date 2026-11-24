import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { execFileSync } from "node:child_process";
import {
  table,
  nativeGraph,
  physicalBindings,
  operations,
  routeDemand,
  demandTcl,
  publish,
  readNative,
  prepare,
} from "../scripts/prepare-computations.mjs";

/** A real-shaped finite capture has publication and scalar producers, reads,
 * residence, semantic context and one unknown physical bit. */
function fixture() {
  const build = { source: "s", rtl: "r", observation: "o", implementation: "i" };
  const resources = [
    {
      id: "register/state",
      kind: "ff",
      width: 2,
      depth: 1,
      ports: { w: "write", r: "read" },
    },
    { id: "unmapped", kind: "register", width: 1, depth: 1 },
  ];
  const versions = [
    {
      id: "root",
      producer: "root",
      origin: "unknown",
      incarnation: "i",
      storage: { resource: "register/state", address: 0 },
    },
  ];
  const events = [];
  function add(id, cycle, operation, inputs, output, access) {
    events.push({
      id,
      cycle,
      sequence: events.length,
      observer: "o",
      incarnation: "i",
      actor: "a",
      operation,
      inputs,
      outputs: output ? [output] : [],
      ...(access ? { access } : {}),
      evidence: "synthetic",
    });
    if (output)
      versions.push({
        id: output,
        producer: id,
        origin: "event",
        incarnation: "i",
        storage:
          access?.kind === "write"
            ? { resource: access.resource, address: 0 }
            : null,
      });
  }
  add("publication", 0, "publication", [], "pub");
  add("w1", 0, "register_write", ["root", "pub"], "v1", {
    kind: "write",
    resource: "register/state",
    before: "root",
    after_version: "v1",
    mask: "0x3",
  });
  add("operand-read", 1, "selected_operand_read", ["v1"], null, {
    kind: "read_request",
    resource: "register/state",
    version: "v1",
    read_mask: "0x1",
  });
  add("operand-response", 1, "selected_operand_value", ["v1"], "operand-copy", {
    kind: "read_result",
    resource: "register/state",
    version: "v1",
    request: "operand-read",
    read_mask: "0x1",
  });
  add("compute", 1, "register_compute", ["operand-copy"], "result");
  add("w2", 1, "register_write", ["v1", "result"], "v2", {
    kind: "write",
    resource: "register/state",
    before: "v1",
    after_version: "v2",
    mask: "0x3",
  });
  add("read", 2, "selected_operand_read", ["v2"], null, {
    kind: "read_request",
    resource: "register/state",
    version: "v2",
    read_mask: "0x1",
  });
  add("response", 2, "selected_operand_value", ["v2"], "copy", {
    kind: "read_result",
    resource: "register/state",
    version: "v2",
    request: "read",
    read_mask: "0x1",
  });
  add("hold", 3, "register_hold", ["v2"], null, {
    kind: "hold",
    resource: "register/state",
    version: "v2",
  });
  add("context", 3, "reply", ["copy"], null);
  const cells = [
    { name: "ff", ref: "FDRE" },
    { name: "lut", ref: "LUT2" },
    { name: "vcc", ref: "VCC" },
  ];
  const nets = ["q", "d", "enable", "clock", "unused"].map((name) => ({
    name,
    type: "SIGNAL",
    route_status: "ROUTED",
    timing_status: "not_queried",
  }));
  const pins = [
    ["q", "ff/Q", "ff", "Q", "OUT"],
    ["q", "lut/I0", "lut", "I0", "IN"],
    ["q", "lut/I1", "lut", "I1", "IN"],
    ["d", "lut/O", "lut", "O", "OUT"],
    ["d", "ff/D", "ff", "D", "IN"],
    ["enable", "ff/CE", "ff", "CE", "IN"],
    ["enable", "ff/R", "ff", "R", "IN"],
    ["enable", "vcc/P", "vcc", "P", "OUT"],
    ["clock", "ff/C", "ff", "C", "IN"],
  ].map(([net, pin, cell, ref_pin, direction]) => ({
    net,
    pin,
    cell,
    ref_pin,
    direction,
  }));
  const view = {
    format: "spacetime-view",
    schema: 1,
    bundle: {
      format: "spacetime",
      schema: 1,
      unit: "cycle",
      build,
      resources,
      events,
      versions,
      relations: [],
      activity: [],
      physical: null,
      capture: {
        first_cycle: 0,
        end_cycle: 4,
        complete: true,
        observers: [{ id: "o", gaps: [] }],
        incarnations: [{ id: "i", first_cycle: 0, end_cycle: 4 }],
      },
    },
    catalogue: {
      build,
      checkpoint: "c",
      cells: cells.map((c) => ({ id: c.name, kind: c.ref })),
      bindings: [
        {
          resource: "register/state",
          evidence: "finite Q witness",
          bits: [
            {
              bit: 0,
              status: "supported",
              cell: "ff",
              pin: "Q",
              evidence: "finite Q",
            },
            { bit: 1, status: "unknown" },
          ],
        },
      ],
    },
  };
  const manifest = {
    complete: true,
    build,
    checkpoint: { sha256: "c" },
    sdf: { fast: { sha256: "f", bytes: 10 }, slow: { sha256: "s", bytes: 20 } },
  };
  const arc = (kind, cell, from, to, max_ps) => ({
    kind,
    cell,
    from,
    to,
    max_ps,
    transition: null,
    guards: [],
    delay: [],
  });
  const rows = [
    arc("interconnect", "", "ff/Q", "lut/I0", 20),
    arc("interconnect", "", "ff/Q", "lut/I1", 25),
    arc("interconnect", "", "lut/O", "ff/D", 30),
    arc("iopath", "lut", "I0", "O", 50),
    arc("iopath", "lut", "I1", "O", 80),
    arc("iopath", "ff", "C", "Q", 100),
  ];
  const projection = (corner) => ({
    schema: 1,
    source: { corner, mode: "sta", ...manifest.sdf[corner] },
    arcs: structuredClone(rows),
    issues: [],
  });
  const input = {
    view,
    manifest,
    cells,
    nets,
    pins,
    ports: [{ net: "clock", port: "clk", direction: "IN" }],
    fast: projection("fast"),
    slow: projection("slow"),
  };
  const ancestry = {
    schema: 1,
    operands: [
      {
        event: "compute",
        write: "w2",
        data_masks: { state: "0x1" },
        control_masks: {},
        unknown: [],
        value_checked: true,
      },
    ],
  };
  return { input, view, ancestry };
}

test("complete native graph retains unselected nets, missing timing and sequential boundaries", () => {
  const { input } = fixture(),
    graph = nativeGraph(input);
  assert.equal(graph.nets.length, 5);
  assert.equal(graph.pins.length, 10);
  assert.equal(graph.cells[0].boundary, "sequential");
  assert.equal(graph.arcs.filter((a) => a.kind === "logic").length, 3);
  const reset = graph.arcs.find((a) => graph.pins[a.to].id === "ff/R");
  assert.equal(reset.timingStatus, "missing");
  assert.deepEqual(reset.timing, { fast: [], slow: [] });
  assert(
    graph.arcs.some(
      (a) => graph.pins[a.from].id === "clk" && graph.pins[a.to].id === "ff/C",
    ),
  );
});

test("SDF digest, direction and cell crossing mismatches reject", () => {
  const { input } = fixture();
  const wrong = structuredClone(input);
  wrong.fast.source.sha256 = "wrong";
  assert.throws(() => nativeGraph(wrong), /SDF source identity/);
  const crossed = structuredClone(input);
  crossed.fast.arcs[3].to = "other";
  assert.throws(() => nativeGraph(crossed), /unresolved SDF endpoint/);
  const reverse = structuredClone(input);
  [reverse.fast.arcs[0].from, reverse.fast.arcs[0].to] = [
    reverse.fast.arcs[0].to,
    reverse.fast.arcs[0].from,
  ];
  assert.throws(() => nativeGraph(reverse), /net endpoint mismatch/);
});

test("uninterpreted delay forms reject even beside ordinary timed paths", () => {
  for (const corner of ["fast", "slow"]) {
    const { input } = fixture();
    input[corner].issues.push({
      cell: "lut",
      form: [{ kind: "symbol", lexeme: "UNFAMILIAR" }],
      reason: "uninterpreted_delay_form",
    });
    assert.throws(
      () => nativeGraph(input),
      /projection has uninterpreted delay forms/,
    );
    assert.equal(input[corner].arcs.length, 6);
    assert.equal(input[corner].issues.length, 1);
  }
});

test("same-cell D/CE/reset associates through finite Q; every missing bit remains unknown", () => {
  const { input, view } = fixture(),
    graph = nativeGraph(input),
    bindings = physicalBindings(view, graph);
  assert.equal(bindings.length, 2);
  const first = bindings[0].bits[0];
  for (const key of ["q", "d", "ce", "reset"])
    assert.equal(graph.pins[first[key]].cell, 0);
  assert.equal(bindings[0].bits[1].status, "unknown");
  assert.equal(bindings[1].bits[0].status, "unknown");
  const wrong = structuredClone(view);
  wrong.catalogue.bindings[0].bits[0] = {
    bit: 0,
    status: "supported",
    cell: "lut",
    pin: "O",
  };
  assert.throws(() => physicalBindings(wrong, graph), /not native FF Q/);
});

test("every event and every write represented including publication-owned writes", () => {
  const { input, view, ancestry } = fixture(),
    bindings = physicalBindings(view, nativeGraph(input));
  const rows = operations(view, ancestry, bindings),
    byId = new Map(rows.map((row) => [row.event, row]));
  assert.equal(rows.length, view.bundle.events.length);
  assert.equal(
    rows.filter((r) => r.applicability === "storage_write").length,
    2,
  );
  assert.deepEqual(byId.get("publication").writes, ["w1"]);
  assert.deepEqual(byId.get("compute").writes, ["w2"]);
  assert.equal(byId.get("w2").kind, "register_write");
  assert.deepEqual(byId.get("w2").sources, [
    { resource: "register/state", mask: "0x1", kind: "data" },
  ]);
  assert.equal(byId.get("read").applicability, "storage_read");
  assert.equal(byId.get("read").status, "located");
  assert.equal(byId.get("hold").applicability, "storage_hold");
  assert.equal(byId.get("context").applicability, "semantic_context");
  const bad = structuredClone(ancestry);
  bad.operands[0].write = "w1";
  assert.throws(
    () => operations(view, bad, bindings),
    /occurrence mismatch|does not feed/,
  );
});

test("ancestry data/control overlap must equal the exact recorded operand-read union", () => {
  const { input, view, ancestry } = fixture();
  ancestry.operands[0].data_masks.state = "0x3";
  ancestry.operands[0].control_masks.state = "0x1";
  for (const id of ["operand-read", "operand-response"])
    view.bundle.events.find((event) => event.id === id).access.read_mask =
      "0x3";
  const rows = operations(
    view,
    ancestry,
    physicalBindings(view, nativeGraph(input)),
  );
  assert.deepEqual(rows.find((row) => row.event === "w2").sources, [
    { resource: "register/state", mask: "0x3", kind: "data" },
    { resource: "register/state", mask: "0x1", kind: "control" },
  ]);
});

test("stale same-shaped sidecars, wrong masks and extra recorded operands reject", () => {
  for (const mutate of [
    (view) => {
      for (const id of ["operand-read", "operand-response"])
        view.bundle.events.find((event) => event.id === id).access.read_mask =
          "0x2";
    },
    (_, ancestry) => {
      ancestry.operands[0].data_masks.state = "0x2";
    },
    (view) => {
      const original = view.bundle.events.find(
        (event) => event.id === "operand-response",
      );
      view.bundle.events.push({
        ...structuredClone(original),
        id: "extra-operand",
        sequence: 20,
        outputs: ["extra-copy"],
      });
      view.bundle.versions.push({
        id: "extra-copy",
        producer: "extra-operand",
        origin: "event",
        incarnation: "i",
        storage: null,
      });
      view.bundle.events
        .find((event) => event.id === "compute")
        .inputs.push("extra-copy");
    },
  ]) {
    const { input, view, ancestry } = fixture();
    mutate(view, ancestry);
    assert.throws(
      () =>
        operations(view, ancestry, physicalBindings(view, nativeGraph(input))),
      /source masks differ|duplicate ancestry operand resource/,
    );
  }
});

test("operand read identity, selected masks and occurrence must agree through the request/result pair", () => {
  for (const mutate of [
    (events) => {
      events.find((event) => event.id === "operand-read").access.read_mask =
        "0x2";
    },
    (events) => {
      for (const id of ["operand-read", "operand-response"])
        events.find((event) => event.id === id).cycle = 0;
    },
    (events) => {
      events.find((event) => event.id === "operand-response").access.resource =
        "unmapped";
    },
    (events) => {
      events.find((event) => event.id === "operand-response").access.version =
        "root";
    },
    (events) => {
      events.find((event) => event.id === "compute").inputs = ["v1"];
    },
  ]) {
    const { input, view, ancestry } = fixture();
    mutate(view.bundle.events);
    assert.throws(
      () =>
        operations(view, ancestry, physicalBindings(view, nativeGraph(input))),
      /ancestry operand/,
    );
  }
});

test("unrepresented scalar leaves remain explicit unknown roots without guessed masks", () => {
  const { input, view, ancestry } = fixture();
  ancestry.operands[0].data_masks.external = "0x1";
  view.bundle.versions.push({
    id: "unknown-scalar",
    producer: "root",
    origin: "unknown",
    incarnation: "i",
    storage: null,
  });
  view.bundle.events
    .find((event) => event.id === "compute")
    .inputs.push("unknown-scalar");
  const rows = operations(
      view,
      ancestry,
      physicalBindings(view, nativeGraph(input)),
    ),
    write = rows.find((row) => row.event === "w2");
  assert.deepEqual(write.sources, [
    { resource: "register/state", mask: "0x1", kind: "data" },
  ]);
  assert(
    write.unknowns.includes("Unrepresented data source register/external"),
  );
  assert(
    view.bundle.events
      .find((event) => event.id === "compute")
      .inputs.includes("unknown-scalar"),
  );
});

test("native demand contains all nets/endpoints and quotes Tcl substitutions", () => {
  const { input } = fixture(),
    graph = nativeGraph(input),
    demand = routeDemand(graph, input.manifest, "m");
  assert.equal(demand.nets.length, 5);
  assert.equal(
    demand.nets.reduce((n, row) => n + row.pins.length, 0),
    10,
  );
  assert.deepEqual(demand.build, input.manifest.build);
  demand.nets[0].id = 'a[$x]"\\b';
  const script = demandTcl(demand, "h");
  assert(script.includes('a\\[\\$x\\]\\"\\\\b'));
});

test("TSV unescaping rejects unsupported escape rather than changing native identity", () => {
  assert.deepEqual(
    table(Buffer.from("a\tb\nhello\\tthere\tback\\\\slash\n"), ["a", "b"]),
    [{ a: "hello\tthere", b: "back\\slash" }],
  );
  assert.throws(
    () => table(Buffer.from("a\nwrong\\q\n"), ["a"]),
    /invalid TSV escape/,
  );
});

test("table publication records exact hashes/counts and refuses existing output", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-computations-"));
  try {
    const { input, view, ancestry } = fixture(),
      graph = nativeGraph(input),
      bindings = physicalBindings(view, graph);
    const attachment = {
      schema: 1,
      scope: "structural_native_connectivity",
      build: view.bundle.build,
      checkpoint: "c",
      coverage: {},
      cells: graph.cells,
      pins: graph.pins,
      nets: graph.nets,
      arcs: graph.arcs,
      bindings,
      operations: operations(view, ancestry, bindings),
    };
    const manifest = await publish(join(root, "out"), attachment, {
      bytes: 5,
      sha256: "v",
    });
    assert.equal(manifest.totals.operations, 10);
    for (const part of manifest.parts) {
      const bytes = await readFile(join(root, "out", part.file));
      assert.equal(bytes.length, part.bytes);
      assert.equal(
        createHash("sha256").update(bytes).digest("hex"),
        part.sha256,
      );
      assert.equal(JSON.parse(bytes).length, part.rows);
    }
    await assert.rejects(
      publish(join(root, "out"), attachment, { bytes: 5, sha256: "v" }),
      /EEXIST/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

/** Tcl executes the actual multi-net control file; native-like punctuation must stay literal. */
test("multi-net Tcl demand round trips literal native names", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-demand-"));
  try {
    const { input } = fixture(),
      graph = nativeGraph(input),
      demand = routeDemand(graph, input.manifest, "m");
    const name = 'a[$variable]"\\backslash';
    demand.nets[0].id = name;
    await writeFile(join(root, "demand.tcl"), demandTcl(demand, "h"));
    await writeFile(
      join(root, "probe.tcl"),
      "set d [source [file join [file dirname [info script]] demand.tcl]]\nputs [llength [dict get $d nets]]\nputs [dict get [lindex [dict get $d nets] 0] id]\n",
    );
    assert.deepEqual(
      execFileSync("/usr/bin/tclsh", [join(root, "probe.tcl")], {
        encoding: "utf8",
      })
        .trimEnd()
        .split("\n"),
      ["5", name],
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

/** Small native-shaped tables exercise ordinary export and retained archive IO.
 * They are synthetic fixtures, not a vendor measurement or physical proof. */
async function nativeFixture(
  directory,
  { archive = false, hashes = true } = {},
) {
  const data = fixture();
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
  const manifest = {
    ...data.input.manifest,
    format: "spacetime_physical_export",
    schema: 1,
    tables: {},
  };
  const files = {};
  const escape = (value) =>
    String(value ?? "")
      .replace(/\\/g, "\\\\")
      .replace(/\t/g, "\\t")
      .replace(/\n/g, "\\n")
      .replace(/\r/g, "\\r");
  for (const [name, header] of Object.entries(columns)) {
    const rows = data.input[name];
    const bytes = Buffer.from(
      header.join("\t") +
        "\n" +
        rows
          .map((row) => header.map((key) => escape(row[key])).join("\t"))
          .join("\n") +
        "\n",
    );
    files[`${name}.tsv`] = bytes;
    manifest.tables[`${name}.tsv`] = { rows: rows.length, bytes: bytes.length };
    if (hashes)
      manifest.tables[`${name}.tsv`].sha256 = createHash("sha256")
        .update(bytes)
        .digest("hex");
  }
  await mkdir(directory);
  if (archive) {
    await mkdir(join(directory, "catalogue"));
    files["manifest.json"] = Buffer.from(JSON.stringify(manifest));
    const entries = [];
    for (const [name, raw] of Object.entries(files)) {
      const file = `catalogue/${name}.gz`,
        packed = gzipSync(raw);
      await writeFile(join(directory, file), packed, { flag: "wx" });
      entries.push({
        file,
        bytes: packed.length,
        sha256: createHash("sha256").update(packed).digest("hex"),
      });
    }
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify({ schema: 1, files: entries }),
      { flag: "wx" },
    );
  } else {
    for (const [name, bytes] of Object.entries(files))
      await writeFile(join(directory, name), bytes, { flag: "wx" });
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify(manifest),
      { flag: "wx" },
    );
  }
  return { ...data, manifest, files };
}

test("ordinary native export verifies declared table hashes, rows and bytes", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-raw-native-"));
  try {
    const directory = join(root, "native");
    const fixture = await nativeFixture(directory);
    const native = await readNative(directory);
    assert.equal(native.provenance.format, "native_export");
    assert.equal(
      native.provenance.verification,
      "declared_hash_bytes_and_rows",
    );
    assert.equal(native.tables.cells.length, 3);
    assert.equal(native.tables.pins.length, 9);
    assert.equal(native.sources.length, 4);
    assert(
      native.sources.every(
        (row) => row.verification === "declared_hash_bytes_and_rows",
      ),
    );
    await writeFile(
      join(directory, "cells.tsv"),
      fixture.files["cells.tsv"].toString().replace("ff\t", "zz\t"),
    );
    await assert.rejects(readNative(directory), /cells declared hash mismatch/);
    await writeFile(join(directory, "cells.tsv"), fixture.files["cells.tsv"]);
    fixture.manifest.tables["cells.tsv"].bytes++;
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify(fixture.manifest),
    );
    await assert.rejects(readNative(directory), /cells byte count mismatch/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("legacy raw exports disclose missing declared hashes; computed receipts are not authentication", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-legacy-native-"));
  try {
    const directory = join(root, "native");
    const fixture = await nativeFixture(directory, { hashes: false });
    const native = await readNative(directory);
    assert.equal(native.provenance.verification, "declared_bytes_and_rows");
    assert(
      native.sources.every(
        (row) =>
          row.verification === "declared_bytes_and_rows" &&
          /^[a-f0-9]{64}$/.test(row.raw_sha256),
      ),
    );
    fixture.manifest.tables["cells.tsv"].rows++;
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify(fixture.manifest),
    );
    await assert.rejects(readNative(directory), /cells population mismatch/);
    fixture.manifest.complete = false;
    await writeFile(
      join(directory, "manifest.json"),
      JSON.stringify(fixture.manifest),
    );
    await assert.rejects(
      readNative(directory),
      /incomplete or unsupported native export/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("retained archive support verifies compressed bytes before reading native tables", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-archive-native-"));
  try {
    const directory = join(root, "native");
    await nativeFixture(directory, { archive: true, hashes: false });
    const native = await readNative(directory);
    assert.equal(native.provenance.format, "retained_archive");
    assert.equal(native.provenance.verification, "archive_manifest_hashes");
    assert.equal(native.tables.nets.length, 5);
    const path = join(directory, "catalogue/pins.tsv.gz"),
      bytes = await readFile(path);
    bytes[0] ^= 1;
    await writeFile(path, bytes);
    await assert.rejects(readNative(directory), /Source hash\/length mismatch/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("preparation without producer ancestry preserves all writes and discloses missing operand masks", async () => {
  const root = await mkdtemp(join(tmpdir(), "spacetime-generic-native-"));
  try {
    const nativePath = join(root, "native");
    const { view, input } = await nativeFixture(nativePath);
    const options = { native: nativePath, out: join(root, "output") };
    for (const [key, value] of [
      ["view", view],
      ["fast", input.fast],
      ["slow", input.slow],
    ]) {
      options[key] = join(root, `${key}.json`);
      await writeFile(options[key], JSON.stringify(value));
    }
    const result = await prepare(options);
    assert.equal(result.coverage.events, 10);
    assert.equal(result.coverage.writes, 2);
    assert.equal(result.coverage.operandEvidence, "not_supplied");
    assert.equal(result.manifest.attachment.inputs.ancestry, null);
    assert.equal(
      result.manifest.attachment.inputs.native.verification,
      "declared_hash_bytes_and_rows",
    );
    const part = result.manifest.parts.find(
      (row) => row.table === "operations",
    );
    const rows = JSON.parse(await readFile(join(options.out, part.file)));
    assert.deepEqual(rows.find((row) => row.event === "compute").writes, [
      "w2",
    ]);
    assert.deepEqual(rows.find((row) => row.event === "publication").writes, [
      "w1",
    ]);
    const write = rows.find((row) => row.event === "w2");
    assert(
      write.sources.every(
        (row) => row.kind === "unclassified" && row.mask === null,
      ),
    );
    assert(
      write.unknowns.some((reason) =>
        reason.includes("No selected scalar operand masks"),
      ),
    );
    assert.equal(
      rows.find((row) => row.event === "read").sources[0].mask,
      "0x1",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("native graph preparation recognizes only a qualified same-capture observation revision", () => {
  const { input, view } = fixture();
  const build = {
    source: "a".repeat(64),
    rtl: "b".repeat(64),
    observation: "c".repeat(64),
    implementation: "f".repeat(64),
  };
  const revised = { ...build, observation: "d".repeat(64) },
    checkpoint = "e".repeat(64);
  input.manifest.build = build;
  input.manifest.checkpoint.sha256 = checkpoint;
  view.bundle.build = revised;
  view.catalogue.build = revised;
  view.catalogue.checkpoint = checkpoint;
  const origin = {
    kind: "observation-reinterpretation",
    schema: 1,
    build,
    revised_build: revised,
    checkpoint,
    base_projection_sha256: "1".repeat(64),
    original_trace_sha256: "2".repeat(64),
    extended_trace_sha256: "2".repeat(64),
    capture_bytes: 100,
    dependency_observer: "dependencies",
    original_plan_sha256: "3".repeat(64),
    revised_plan_sha256: "4".repeat(64),
    review_sha256: "5".repeat(64),
    comparison: {
      same_capture_bytes: true,
      source_rtl_unchanged: true,
      declarations_unchanged: true,
      old_dependency_bindings_retained: true,
      only_equivalent_state_bindings_added: true,
      added_bindings: 1,
      first_cycle: 0,
      end_cycle: 4,
      compared_cycles: 4,
    },
  };
  view.catalogue.correspondence_origin = origin;
  assert.equal(nativeGraph(input).nets.length, 5);
  origin.extended_trace_sha256 = "9".repeat(64);
  assert.throws(() => nativeGraph(input), /same-capture/);
  origin.extended_trace_sha256 = origin.original_trace_sha256;
  delete origin.review_sha256;
  assert.throws(() => nativeGraph(input), /review identity/);
});
