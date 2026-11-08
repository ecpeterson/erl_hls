import test from "node:test";
import assert from "node:assert/strict";
import { createRegionalControls } from "../web/regional-controls.js";

/** Small DOM boundary; no browser or network is needed to test stale loads. */
function controls(t) {
  const original = globalThis.document,
    nodes = new Map();
  const node = (id) => {
    if (!nodes.has(id))
      nodes.set(id, {
        value: "",
        checked: false,
        disabled: false,
        hidden: false,
        innerHTML: "",
        textContent: "",
      });
    return nodes.get(id);
  };
  globalThis.document = { getElementById: node };
  t.after(() => {
    globalThis.document = original;
  });
  return node;
}
const result = () => ({
  cells: [{ id: "c", kind: "LUT6" }],
  pips: [],
  nets: [],
});

test("regional data stays lazy, loads once and resets on capture replacement", async (t) => {
  const node = controls(t);
  let calls = 0,
    repaints = 0;
  const panel = createRegionalControls(() => repaints++, {
    load: async () => {
      calls++;
      return result();
    },
    validate: (_, raw) => raw,
  });
  panel.configure({ id: "one" }, { entry: { file: "regional.json" } });
  assert.equal(calls, 0);
  assert.equal(node("region-load").disabled, false);
  await node("region-load").onclick();
  assert.equal(calls, 1);
  assert.equal(repaints, 1);
  assert.equal(node("region-content").hidden, false);
  await node("region-load").onclick();
  assert.equal(calls, 1);
  panel.configure({ id: "two" }, null);
  assert.equal(node("region-load").disabled, true);
  assert.equal(node("region-content").hidden, true);
  assert.equal(panel.view, null);
});

test("replacing the capture aborts a pending load and discards late progress/results", async (t) => {
  const node = controls(t);
  let options,
    resolve,
    validated = 0;
  const panel = createRegionalControls(() => {}, {
    load: (o) => {
      options = o;
      return new Promise((r) => {
        resolve = r;
      });
    },
    validate: () => {
      validated++;
      return result();
    },
  });
  panel.configure({}, { entry: { file: "first.json" } });
  const pending = node("region-load").onclick();
  panel.configure({}, { entry: { file: "second.json" } });
  assert.equal(options.signal.aborted, true);
  const message = node("region-status").textContent;
  options.progress("stale load");
  resolve(result());
  await pending;
  assert.equal(validated, 0);
  assert.equal(node("region-status").textContent, message);
  assert.equal(node("region-load").disabled, false);
  assert.equal(node("region-content").hidden, true);
});

test("failed validation remains visible, permits retry, and never installs partial data", async (t) => {
  const node = controls(t);
  let attempts = 0;
  const panel = createRegionalControls(() => {}, {
    load: async () => result(),
    validate: (_, raw) => {
      if (++attempts === 1) throw Error("checkpoint mismatch");
      return raw;
    },
  });
  panel.configure({}, { entry: { file: "regional.json" } });
  await node("region-load").onclick();
  assert.match(node("region-status").textContent, /checkpoint mismatch/);
  assert.equal(panel.view, null);
  assert.equal(node("region-load").disabled, false);
  assert.equal(node("region-content").hidden, true);
  await node("region-load").onclick();
  assert.equal(node("region-content").hidden, false);
});

test("metric changes preserve fixed counts, unknown kinds, full paging and selection reset", async (t) => {
  const node = controls(t);
  const cells = Array.from({ length: 13 }, (_, i) => ({
    id: `cell/${i}`,
    kind: i === 12 ? null : "LUT6",
    x: i,
    y: 0,
    bin: 0,
  }));
  const raw = {
    cells,
    pips: [],
    nets: [],
    arcNets: [],
    binSize: 16,
    bins: [
      {
        x: 0,
        y: 0,
        bounds: { minX: 0, maxX: 16, minY: 0, maxY: 16 },
        cells: cells.map((_, i) => i),
        pips: [],
        nets: [],
        counts: { cells: 13, pips: 0, nets: 0 },
        primitiveKinds: { LUT6: 12 },
        unknownKinds: 1,
      },
    ],
    maxima: { cells: 13, pips: 0, nets: 0, primitiveKinds: { LUT6: 12 } },
    summary: { unknownCellKinds: 1 },
  };
  let panel;
  panel = createRegionalControls(() => panel.update(null, null), {
    load: async () => raw,
    validate: (_, data) => data,
  });
  panel.configure({}, { entry: { file: "regional.json" } });
  await node("region-load").onclick();
  node("region-metric").value = "cells";
  node("region-kind").value = "LUT6";
  node("region-metric").onchange();
  assert.equal(panel.view.domain.max, 12);
  node("region-metric").value = "pips";
  node("region-metric").onchange();
  assert.equal(panel.view.domain.max, 0);
  assert.equal(panel.view.primitiveKind, null);
  assert.doesNotMatch(node("region-kind").innerHTML, /unknown/);
  assert.match(node("region-coverage").textContent, /1 lack primitive kinds/);
  node("region-bin").value = "0";
  node("region-bin").onchange();
  node("region-population").value = "cells";
  node("region-population").onchange();
  assert.match(node("region-page").textContent, /13 of 13 cells.*1\/2/);
  node("region-next").onclick();
  assert.match(node("region-list").innerHTML, /cell\/12/);
  node("region-list").onclick({
    target: { closest: () => ({ dataset: { regionCell: "12" } }) },
  });
  assert.equal(panel.view.selectedCell.cell.id, "cell/12");
  node("region-search").value = "cell/12";
  node("region-search").oninput();
  assert.match(node("region-page").textContent, /1 of 13 cells/);
  assert.equal(panel.view.details.cells.length, 13);
  node("region-family-only").checked = true;
  node("region-family-only").onchange();
  assert.match(node("region-page").textContent, /0 of 13 cells/);
  node("region-clear").onclick();
  assert.equal(panel.view.selectedCell, null);
  assert.equal(panel.view.details, null);
  panel.configure();
  assert.equal(panel.view, null);
  assert.equal(node("region-content").hidden, true);
});
