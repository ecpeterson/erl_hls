import assert from "node:assert/strict";
import test from "node:test";
import {
  arrivalEventAnchor,
  arrivalEventConnection,
} from "../web/arrival-events.js";

/** A scalar register, a synchronous RAM and two nonoverlapping reset epochs. */
function fixture() {
  return {
    events: new Map(),
    resources: new Map([
      [
        "state",
        {
          kind: "register",
          depth: 1,
          read_latency: 0,
          collision: "read_first",
        },
      ],
      ["ram", { kind: "bram", depth: 64, read_latency: 1 }],
    ]),
    epochs: new Map([
      ["first", { first_cycle: 0, end_cycle: 10 }],
      ["second", { first_cycle: 10, end_cycle: 20 }],
    ]),
  };
}

/** An access remains an event at its recorded cycle, regardless of layout. */
function event(kind, cycle = 4, resource = "state", incarnation = "first") {
  return Object.freeze({
    cycle,
    incarnation,
    access: Object.freeze({ kind, resource }),
  });
}

/** A zero-latency response carries the exact word sampled by its request. */
function readPair(model) {
  const request = Object.freeze({
    ...event("read_request"),
    id: "request",
    access: Object.freeze({
      kind: "read_request",
      resource: "state",
      address: 0,
      port: "read",
      version: "word0",
      read_mask: "0xf",
    }),
  });
  const result = Object.freeze({
    ...request,
    id: "response",
    access: Object.freeze({
      ...request.access,
      kind: "read_result",
      request: request.id,
    }),
  });
  model.events.set(request.id, request);
  model.events.set(result.id, result);
  return { request, result };
}

test("semantic events with located resources never inherit zero arrival", () => {
  const model = fixture();
  for (const operation of [
    "register_compute",
    "selected_operand_value",
    "publication",
    "reset",
  ]) {
    const semantic = Object.freeze({
      cycle: 4,
      incarnation: "first",
      operation,
      resources: Object.freeze(["state"]),
    });
    assert.deepEqual(arrivalEventAnchor(model, semantic), {
      kind: "unknown",
      coordinate: null,
      reason: "operation_has_no_boundary_anchor",
    });
    assert.equal(
      arrivalEventConnection(model, event("read_request"), semantic),
      null,
    );
    assert.equal(arrivalEventConnection(model, semantic, event("write")), null);
    assert.equal(semantic.cycle, 4);
  }
});

test("explicit register samples and captures keep their boundary semantics", () => {
  const model = fixture();
  for (const kind of ["read_request", "hold"])
    assert.deepEqual(arrivalEventAnchor(model, event(kind)), {
      kind: "register_q_sample",
      coordinate: 4,
    });
  const write = event("write");
  assert.deepEqual(arrivalEventAnchor(model, write), {
    kind: "register_capture",
    coordinate: 5,
  });
  assert.deepEqual(
    arrivalEventConnection(model, event("read_request"), write),
    { from: 4, to: 5 },
  );
  assert.deepEqual(
    arrivalEventConnection(model, write, event("read_request", 7)),
    { from: 5, to: 7 },
  );
  assert.equal(write.cycle, 4);
});

test("zero-latency register results share their qualified request boundary", () => {
  const model = fixture(),
    { request, result } = readPair(model);
  for (const collision of ["read_first", "forbidden"]) {
    model.resources.get("state").collision = collision;
    assert.deepEqual(arrivalEventAnchor(model, result), {
      kind: "register_q_sample",
      coordinate: 4,
    });
    assert.deepEqual(arrivalEventConnection(model, request, result), {
      from: 4,
      to: 4,
    });
    assert.deepEqual(arrivalEventConnection(model, result, event("write")), {
      from: 4,
      to: 5,
    });
  }
  assert.equal(result.cycle, 4);
  assert.equal(result.access.request, "request");
});

test("responses without matching sampled-Q requests remain untimed", () => {
  const model = fixture(),
    { request, result } = readPair(model);
  for (const access of [
    { request: undefined },
    { request: "absent" },
    { address: 1 },
    { port: "other" },
    { version: "word1" },
    { read_mask: "0x1" },
  ]) {
    const mismatch = { ...result, access: { ...result.access, ...access } };
    assert.equal(arrivalEventAnchor(model, mismatch).coordinate, null);
    assert.equal(arrivalEventConnection(model, request, mismatch), null);
  }
  for (const change of [{ cycle: 5 }, { incarnation: "second" }])
    assert.equal(
      arrivalEventAnchor(model, { ...result, ...change }).coordinate,
      null,
    );
  model.events.set(request.id, { ...request, access: result.access });
  assert.equal(arrivalEventAnchor(model, result).coordinate, null);
  model.events.set(request.id, request);
  model.resources.get("state").read_latency = 1;
  assert.equal(
    arrivalEventAnchor(model, { ...result, cycle: 5 }).coordinate,
    null,
  );
  model.resources.get("state").read_latency = 0;
  model.resources.get("state").collision = "write_first";
  assert.equal(arrivalEventAnchor(model, result).coordinate, null);
  assert.equal(arrivalEventConnection(model, request, result), null);
});

test("response latency and forwarding cannot masquerade as sampled old Q", () => {
  const model = fixture();
  for (const kind of ["read_request", "read_result", "write", "hold"])
    assert.equal(
      arrivalEventAnchor(model, event(kind, 4, "ram")).coordinate,
      null,
    );
  assert.equal(
    arrivalEventAnchor(model, event("read_result")).coordinate,
    null,
  );
  for (const read_latency of [undefined, 1]) {
    model.resources.get("state").read_latency = read_latency;
    assert.equal(
      arrivalEventAnchor(model, event("read_request")).coordinate,
      null,
    );
  }
  model.resources.get("state").read_latency = 0;
  for (const collision of [undefined, "write_first"]) {
    model.resources.get("state").collision = collision;
    assert.equal(
      arrivalEventAnchor(model, event("read_request")).coordinate,
      null,
    );
  }
});

test("tail and reset boundaries do not create an unobserved next Q", () => {
  const model = fixture();
  assert.equal(arrivalEventAnchor(model, event("write", 9)).coordinate, null);
  assert.equal(
    arrivalEventAnchor(model, event("write", 19, "state", "second")).coordinate,
    null,
  );
  assert.equal(
    arrivalEventConnection(
      model,
      event("write", 8),
      event("read_request", 10, "state", "second"),
    ),
    null,
  );
  assert.equal(
    arrivalEventConnection(model, event("write"), event("read_request")),
    null,
  );
});
