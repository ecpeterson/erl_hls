import assert from "node:assert/strict";
import test from "node:test";
import { clockSink } from "../web/clock-sink.js";

function fixture() {
  const events = new Map([
    ["outside", { id: "outside", cycle: 2 }],
    ["inside", { id: "inside", cycle: 12 }],
    ["later", { id: "later", cycle: 16 }],
  ]);
  return {
    prepared: true,
    model: { events },
    pinGeometry: [[0, 0, 0, "actor/state[1]/D"]],
    cones: [{ rootPins: [0], role: "data" }],
    writes: new Map([...events.keys()].map((id) => [id, { cones: [0] }])),
  };
}

test("limiting sink chooses an exact associated write inside the full step", () => {
  const index = fixture();
  const match = clockSink(index, "actor/state[1]/D", {
    firstCycle: 10,
    endCycle: 15,
  });
  assert.equal(match.status, "available");
  assert.equal(match.event.id, "inside");
  assert.equal(match.key, "data/0");
  assert.equal(match.withinStep, true);
  const outside = clockSink(index, "actor/state[1]/D", {
    firstCycle: 20,
    endCycle: 25,
  });
  assert.equal(outside.event.id, "outside");
  assert.equal(outside.withinStep, false);
});

test("similar pin names, ambiguous identities and unassociated roots stay unavailable", () => {
  const index = fixture();
  assert.equal(clockSink(index, "state[1]/D").status, "unavailable");
  assert.equal(clockSink(index, "actor/state[1]/Q").status, "unavailable");
  index.pinGeometry.push([...index.pinGeometry[0]]);
  assert.equal(clockSink(index, "actor/state[1]/D").status, "unavailable");
  index.pinGeometry.pop();
  index.writes.clear();
  assert.equal(clockSink(index, "actor/state[1]/D").status, "unavailable");
  assert.equal(clockSink(null, "actor/state[1]/D").status, "unavailable");
});
