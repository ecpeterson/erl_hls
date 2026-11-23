import assert from "node:assert/strict";
import test from "node:test";
import {
  arrivalCoordinate,
  captureDisposition,
  eventCoordinate,
} from "../web/arrival-layout.js";

test("pre-edge feedback goes from old Q through D to the next Q boundary", () => {
  const write = Object.freeze({
    cycle: 7,
    access: Object.freeze({ kind: "write" }),
  });
  const read = Object.freeze({
    cycle: 7,
    access: Object.freeze({ kind: "read" }),
  });
  assert.equal(arrivalCoordinate(7, 0, 4), 7);
  assert.equal(eventCoordinate(read), 7);
  assert.equal(arrivalCoordinate(7, 3, 4), 7.75);
  assert.equal(eventCoordinate(write), 8);
  assert.equal(arrivalCoordinate(8, 0, 4), eventCoordinate(write));
  assert.equal(write.cycle, 7);
  assert.equal(read.cycle, 7);
});

test("only writes move to the next display boundary", () => {
  for (const kind of ["read", "read_result", "hold"])
    assert.equal(eventCoordinate({ cycle: 12, access: { kind } }), 12);
  assert.equal(eventCoordinate({ cycle: 12, operation: "reset" }), 12);
  assert.equal(eventCoordinate({ cycle: 0, access: { kind: "write" } }), 1);
});

test("capture equality is ready and overrun stays visible", () => {
  assert.deepEqual(captureDisposition(0, 5), { kind: "ready", marginNs: 5 });
  assert.deepEqual(captureDisposition(5, 5), { kind: "ready", marginNs: 0 });
  assert.deepEqual(captureDisposition(6, 5), { kind: "late", marginNs: -1 });
  assert.equal(arrivalCoordinate(12, 5, 5), 13);
  assert.equal(arrivalCoordinate(12, 12.5, 5), 14.5);
});

test("one common budget preserves relative arrival instead of rescaling cones", () => {
  assert.equal(arrivalCoordinate(20, 1, 8), 20.125);
  assert.equal(arrivalCoordinate(20, 6, 8), 20.75);
  assert.equal(arrivalCoordinate(21, 6, 8), 21.75);
  assert.equal(arrivalCoordinate(20, 6, 4), 21.5);
});

test("unknown and outside-scope timing remain distinct without coordinates", () => {
  for (const [arrival, kind] of [
    [null, "unknown"],
    ["not_applicable", "not_applicable"],
  ]) {
    assert.equal(arrivalCoordinate(2, arrival, 5), null);
    assert.deepEqual(captureDisposition(arrival, 5), { kind, marginNs: null });
  }
});

test("invalid budgets reject even when arrival is unknown", () => {
  for (const budget of [
    undefined,
    null,
    NaN,
    Infinity,
    -Infinity,
    -1,
    0,
    "5",
  ]) {
    for (const arrival of [0, null, "not_applicable"]) {
      assert.throws(() => arrivalCoordinate(2, arrival, budget), RangeError);
      assert.throws(() => captureDisposition(arrival, budget), RangeError);
    }
  }
});

test("invalid timing is not silently converted into missing evidence", () => {
  for (const arrival of [
    undefined,
    NaN,
    Infinity,
    -Infinity,
    -1,
    "unknown",
    "2",
    false,
  ]) {
    assert.throws(() => arrivalCoordinate(2, arrival, 5), RangeError);
    assert.throws(() => captureDisposition(arrival, 5), RangeError);
  }
});

test("invalid cycles and coordinate overflow reject without clamping", () => {
  for (const cycle of [
    undefined,
    null,
    NaN,
    Infinity,
    -1,
    1.5,
    Number.MAX_SAFE_INTEGER + 1,
  ]) {
    assert.throws(() => arrivalCoordinate(cycle, 0, 5), RangeError);
    assert.throws(() => eventCoordinate({ cycle }), RangeError);
  }
  assert.throws(() => eventCoordinate(null), RangeError);
  assert.throws(
    () =>
      eventCoordinate({
        cycle: Number.MAX_SAFE_INTEGER,
        access: { kind: "write" },
      }),
    RangeError,
  );
  assert.throws(
    () => arrivalCoordinate(0, Number.MAX_VALUE, Number.MIN_VALUE),
    RangeError,
  );
});
