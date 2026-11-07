import test from "node:test";
import assert from "node:assert/strict";
import { eventFootprint, accessConnections } from "../web/footprint.js";

/** Minimal normalized model with separated cells, folded bit identities, a
 * missing mapping, an unplaced FF and an unresolved whole-word candidate. */
function fixture() {
  const cells = [
    { id: "near", kind: "FDRE", x: 2, y: 3 },
    { id: "far", kind: "FDRE", x: 102, y: 203 },
    { id: "unplaced", kind: "FDRE", x: null, y: null },
    { id: "candidate", kind: "FDRE", x: 52, y: 103 },
  ];
  const bits = [
    { bit: 0, status: "supported", cell: "near", pin: "Q" },
    { bit: 1, status: "supported", cell: "near", pin: "Q" },
    { bit: 2, status: "supported", cell: "far", pin: "Q" },
    { bit: 3, status: "unknown" },
    { bit: 4, status: "supported", cell: "unplaced", pin: "Q" },
    { bit: 5, status: "supported", cell: "missing", pin: "Q" },
  ];
  return {
    catalogue: {},
    events: new Map([
      [
        "write",
        {
          id: "write",
          access: { kind: "write", resource: "word", address: 0, mask: "0xFF" },
        },
      ],
      [
        "read",
        {
          id: "read",
          access: {
            kind: "read_request",
            resource: "word",
            address: 0,
            version: "old",
          },
        },
      ],
      [
        "response",
        {
          id: "response",
          access: {
            kind: "read_result",
            resource: "word",
            version: "old",
            request: "read",
          },
        },
      ],
      ["compute", { id: "compute", resources: ["word"] }],
    ]),
    resources: new Map([["word", { id: "word", kind: "register", width: 8 }]]),
    bindings: new Map([
      [
        "word",
        {
          resource: "word",
          disposition: "ambiguous",
          cells: cells.map((c) => c.id),
          bits,
        },
      ],
    ]),
    cells: new Map(cells.map((cell) => [cell.id, cell])),
    resourceCoverage: new Map(),
  };
}

test("read context preserves distant cell coordinates and deduplicates folded bits", () => {
  const result = eventFootprint(fixture(), "read");
  assert.equal(result.mode, "word_context");
  assert.equal(result.bitSelectionKnown, false);
  assert.equal(result.selectedBits, null);
  assert.deepEqual(
    result.cells.map((c) => [c.id, c.x, c.y, c.bits]),
    [
      ["near", 2, 3, [0, 1]],
      ["far", 102, 203, [2]],
    ],
  );
  assert.ok(result.cells.every((c) => c.contextual && !c.accessed));
  assert.deepEqual(result.bounds, { minX: 2, maxX: 102, minY: 3, maxY: 203 });
  assert.equal(result.unknownBits, 4);
  assert.equal(result.unplacedBits, 1);
  assert.deepEqual(
    result.unplacedCells.map((c) => c.id),
    ["unplaced"],
  );
  assert.deepEqual(
    result.candidateCells.map((c) => c.id),
    ["candidate"],
  );
});

test("masked writes select logical bits before folding them into physical cells", () => {
  const model = fixture();
  model.events.get("write").access.mask = "0x6";
  const result = eventFootprint(model, "write");
  assert.equal(result.mode, "write_bits");
  assert.equal(result.bitSelectionKnown, true);
  assert.equal(result.selectedBits, 2);
  assert.deepEqual(
    result.cells.map((c) => [c.id, c.bits]),
    [
      ["near", [1]],
      ["far", [2]],
    ],
  );
  assert.ok(result.cells.every((c) => c.accessed && !c.contextual));
  assert.equal(result.unknownBits, 0);
  assert.equal(result.unplacedBits, 0);
  assert.match(
    result.reason,
    /native enable and switching are not established/,
  );
});

test("zero mask has no physical footprint or unresolved candidates", () => {
  const model = fixture();
  model.events.get("write").access.mask = "0x0";
  const result = eventFootprint(model, "write");
  assert.equal(result.selectedBits, 0);
  assert.deepEqual(result.cells, []);
  assert.deepEqual(result.candidateCells, []);
  assert.equal(result.bounds, null);
  assert.equal(result.unknownBits, 0);
});

test("wide masks remain exact and out-of-range or noncanonical masks reject", () => {
  const model = fixture();
  model.resources.get("word").width = 80;
  model.bindings.get("word").bits = [
    { bit: 79, status: "supported", cell: "far" },
  ];
  model.events.get("write").access.mask = "0x80000000000000000000";
  assert.equal(eventFootprint(model, "write").selectedBits, 1);
  assert.deepEqual(eventFootprint(model, "write").cells[0].bits, [79]);
  for (const mask of [
    "0x100000000000000000000",
    "0x01",
    "0xff",
    "-0x1",
    "255",
    255,
  ]) {
    model.events.get("write").access.mask = mask;
    assert.throws(() => eventFootprint(model, "write"), /mask/);
  }
});

test("whole-cell bindings without bit identities remain contextual for a masked write", () => {
  const model = fixture();
  model.bindings.set("word", {
    resource: "word",
    disposition: "distributed",
    cells: ["near", "far"],
  });
  model.events.get("write").access.mask = "0x1";
  const result = eventFootprint(model, "write");
  assert.equal(result.mode, "word_context");
  assert.equal(result.selectedBits, 1);
  assert.equal(result.unknownBits, 1);
  assert.ok(
    result.cells.every(
      (c) => c.contextual && !c.accessed && c.bits.length === 0,
    ),
  );
});

test("delayed responses and actor operations do not borrow their source register location", () => {
  const model = fixture();
  const response = eventFootprint(model, "response");
  assert.equal(response.mode, "unknown");
  assert.match(response.reason, /copy selected at its request/);
  assert.deepEqual(response.cells, []);
  assert.deepEqual(eventFootprint(model, "compute").cells, []);
});

test("unmapped words and selected unplaced bits retain explicit uncertainty", () => {
  const model = fixture();
  model.events.get("write").access.mask = "0x18";
  const partial = eventFootprint(model, "write");
  assert.equal(partial.unknownBits, 1);
  assert.equal(partial.unplacedBits, 1);
  assert.deepEqual(partial.cells, []);
  assert.equal(partial.bounds, null);
  model.bindings.clear();
  const unknown = eventFootprint(model, "read");
  assert.equal(unknown.unknownBits, 8);
  assert.deepEqual(unknown.cells, []);
});

test("malformed bit identities and unknown events cannot acquire a footprint", () => {
  const model = fixture();
  assert.throws(
    () => eventFootprint(model, "absent"),
    /Unknown footprint event/,
  );
  for (const bit of [-1, 8, 0.5, 0]) {
    model.bindings
      .get("word")
      .bits.push({ bit, status: "supported", cell: "far" });
    assert.throws(() => eventFootprint(model, "read"), /Invalid or duplicate/);
    model.bindings.get("word").bits.pop();
  }
});

test("masked-write dependencies never target the newly written-bit footprint", () => {
  const from = { access: { resource: "word", kind: "read_request" } };
  const to = { access: { resource: "word", kind: "write", mask: "0x1" } };
  const one = [{ x: 1, y: 2 }],
    many = [...one, { x: 5, y: 6 }];
  for (const sources of [one, many])
    for (const targets of [one, many])
      assert.deepEqual(accessConnections(from, to, sources, targets), {
        aggregate: true,
        pairs: [],
      });
});

test("same-word reads pair occupied tiles without inventing cross-word bit paths", () => {
  const from = { access: { resource: "word", kind: "write" } };
  const to = { access: { resource: "word", kind: "read_request" } };
  const a = { x: 1, y: 2 },
    b = { x: 3, y: 4 },
    c = { x: 5, y: 6 };
  assert.deepEqual(accessConnections(from, to, [a, b], [b, c]), {
    aggregate: false,
    pairs: [[b, b]],
  });
  for (const target of [
    to,
    { access: { resource: "other", kind: "read_request" } },
  ])
    assert.deepEqual(
      accessConnections(from, target, [a, b], [c, { x: 8, y: 9 }]),
      { aggregate: true, pairs: [] },
    );
  assert.deepEqual(accessConnections(from, to, [], [a]), {
    aggregate: true,
    pairs: [],
  });
});

test("a one-ended dependency fans across context without allocating all pairs", () => {
  const from = {},
    to = { access: { resource: "word", kind: "read_request" } };
  const a = { x: 1, y: 2 },
    b = { x: 3, y: 4 },
    c = { x: 5, y: 6 };
  assert.deepEqual(accessConnections(from, to, [a], [b, c]), {
    aggregate: false,
    pairs: [
      [a, b],
      [a, c],
    ],
  });
});

test("selected read bits retain only their actual supported locations", () => {
  const model = fixture();
  model.events.get("read").access.read_mask = "0xC";
  const footprint = eventFootprint(model, "read");
  assert.equal(footprint.mode, "read_bits");
  assert.equal(footprint.selectedBits, 2);
  assert.equal(footprint.unknownBits, 1);
  assert.deepEqual(
    footprint.cells.map((c) => [c.id, c.bits]),
    [["far", [2]]],
  );
  assert.equal(footprint.cells[0].accessed, true);
  assert.match(footprint.reason, /not sensitized gate activity/);
});

test("selected reads reject malformed or empty masks", () => {
  for (const mask of ["0x0", "0x100", "0x01", 3]) {
    const model = fixture();
    model.events.get("read").access.read_mask = mask;
    assert.throws(() => eventFootprint(model, "read"), /mask/);
  }
});
