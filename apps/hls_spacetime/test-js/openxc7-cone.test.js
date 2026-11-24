import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createModel } from "../web/model.js";
import {
  createComputations,
  computationConnection,
  computationLayers,
} from "../web/computation-routes.js";
import { openxc7Computations } from "../scripts/openxc7-computations.mjs";
import { sourceFixture } from "./fixtures/computation-publication.js";

test("packed shift registers and LUT RAM stop combinational traversal", async (t) => {
  const { view } = await sourceFixture(t);
  const type = "SLICE_LUTX";
  view.catalogue.cells[0].kind = type;
  const ports = {
    A1: { net: "a", class: "comb_input", direction: "IN" },
    O6: { net: "q", class: "comb_output", direction: "OUT" },
  };
  const raw = { type, ports, arcs: [{ from: "A1", to: "O6", delay_ps: 200 }] };
  for (const [attrs, expected] of [
    [{ X_ORIG_TYPE: "LUT1" }, "combinational"],
    [{ X_ORIG_TYPE: "SRL16E", X_LUT_AS_SRL: "1" }, "unsupported"],
    [{ X_ORIG_TYPE: "RAMD64E", X_LUT_AS_DRAM: "1" }, "unsupported"],
    [{ X_ORIG_TYPE: "LUT6", X_LUT_AS_DRAM: "1" }, "unsupported"],
    [{}, "unsupported"],
  ]) {
    const result = openxc7Computations(
      view,
      { ff: { type, attributes: attrs } },
      { cells: { ff: raw }, sinks: [] },
      [],
      {},
    );
    assert.equal(result.cells[0].boundary, expected);
    assert.equal(result.arcs.length, expected === "combinational" ? 1 : 0);
  }
});

const dir = process.env.OPENXC7_CONE_FIXTURE;
test(
  "replayed write renders single-model routed data/control cones and preserves missing evidence",
  { skip: !dir },
  () => {
    const json = (name) => JSON.parse(readFileSync(join(dir, name)));
    const document = json("view/recording.json"),
      packed = json("cone/routed.json").modules.top.cells;
    const timing = json("cone/timing.json"),
      words = json("cone/storage.json"),
      model = createModel(document);
    const routes = document.openxc7Routes.nets;
    const load = (attachment) => createComputations(model, attachment, routes);
    const cones = (index) => computationLayers(index, ["edge/2"])[0].cones;
    const checked = load(document.openxc7Computations);
    assert.equal(checked.model.events.size, 8);
    if (json("cone/route-request.json").all) {
      const netIds = Object.keys(
        json("cone/routed.json").modules.top.netnames,
      ).sort();
      assert.deepEqual(routes.map((r) => r.id).sort(), netIds);
      assert.equal(document.openxc7Routes.packedNetCount, netIds.length);
      const selected = createComputations(
        model,
        { ...document.openxc7Computations, routingComplete: false },
        routes.filter((r) => ["d[0]", "d[1]"].includes(r.id)),
      );
      const outcomes = (index, ids) =>
        ids
          .map((id) => computationConnection(index, id))
          .filter(Boolean)
          .map((r) => r.disposition);
      const { arcs, cones: writeCones } = computationLayers(checked, [
        "edge/2",
      ])[0];
      assert.equal(
        outcomes(selected, arcs).filter((d) => d === "resolved").length,
        2,
      );
      const all = outcomes(checked, arcs);
      assert.equal(all.length, 12);
      const permutations = routes.flatMap((n) =>
        n.pin_attachments.filter((p) => p.lut_permutation_pip),
      );
      // Older captured graphs retain the original four missing attachments.
      if (permutations.length || process.env.OPENXC7_EXPECT_PERMUTATIONS) {
        assert.equal(permutations.length, 4);
        assert.ok(permutations.some((p) => p.bel_pins[0].includes("5LUT/A5")));
        assert.ok(permutations.some((p) => p.bel_pins[0].includes("6LUT/A5")));
        const missing = arcs.filter(
          (i) =>
            computationConnection(checked, i)?.disposition === "unavailable",
        );
        assert.equal(all.filter((d) => d === "resolved").length, 10);
        assert.deepEqual(
          missing.map((i) => checked.pins[checked.arcs[i].from].id),
          Array(2).fill("$PACKER_GND_DRV/Y"),
        );
      } else {
        assert.equal(all.filter((d) => d === "resolved").length, 8);
        assert.equal(all.filter((d) => d === "unavailable").length, 4);
      }
      for (const control of writeCones.filter((c) => c.role !== "data")) {
        assert.deepEqual(outcomes(checked, control.arcIndices), [
          "resolved",
          "resolved",
        ]);
        assert.equal(control.registeredDelayNs, null);
      }
    }
    assert.deepEqual(
      cones(checked)
        .map((c) => c.role)
        .sort(),
      ["data", "enable", "reset"],
    );
    const data = cones(checked).find((c) => c.role === "data");
    assert.ok(data.registeredDelayNs > 0);
    assert.ok(data.arcIndices.some((i) => checked.arcs[i].kind === "logic"));
    const halves = checked.pins.filter(
      (p) => p.origin?.cell === "functions" && p.direction === "OUT",
    );
    assert.deepEqual(halves.map((p) => p.origin.ports[0]).sort(), ["O5", "O6"]);
    assert.ok(
      checked.arcs.every(
        (arc) => !("fast" in arc.timing || "slow" in arc.timing),
      ),
    );
    const half = Object.keys(packed).find(
      (id) => packed[id].attributes.SPACETIME_OUTPUT === "O6",
    );
    const launched = Object.keys(timing.cells[half].ports).find(
      (p) => timing.cells[half].ports[p].net_origin === "q[1]",
    );
    const rows = timing.cells[half].arcs;
    const removed = rows.findIndex((a) => a.from === launched && a.to === "O6");
    assert.ok(removed >= 0);
    rows.splice(removed, 1);
    const incomplete = load(
      openxc7Computations(
        document,
        packed,
        timing,
        words,
        document.openxc7Computations.timingModel,
      ),
    );
    const gap = cones(incomplete).find((c) => c.role === "data");
    assert.equal(gap.registeredDelayNs, null);
    assert.ok(gap.coverage.missingTiming > data.coverage.missingTiming);
    words[0].bits[0] = { bit: 0, status: "unknown" };
    const unbound = load(
      openxc7Computations(
        document,
        packed,
        timing,
        words,
        document.openxc7Computations.timingModel,
      ),
    );
    assert.equal(unbound.bindings.get("q").get(0).status, "unknown");
    assert.equal(unbound.bindings.get("q").get(1).status, "supported");
  },
);

test("XC7 carry and mux dependencies require the original primitive and correct port direction", async (t) => {
  const { view } = await sourceFixture(t);
  for (const [type, orig, inputs, outputs, expected] of [
    [
      "CARRY4",
      "CARRY4",
      ["DI1", "S1"],
      ["O0", "O1", "CO1", "O2"],
      ["DI1/CO1", "DI1/O2", "S1/CO1", "S1/O1", "S1/O2"],
    ],
    [
      "SELMUX2_1",
      "MUXF8",
      ["0", "1", "S0", "X"],
      ["OUT"],
      ["0/OUT", "1/OUT", "S0/OUT"],
    ],
    ["SELMUX2_1", "unrecognized", ["0", "1", "S0"], ["OUT"], []],
  ]) {
    const ports = Object.fromEntries(
      [...inputs, ...outputs].map((pin) => [
        pin,
        {
          net: pin,
          direction: inputs.includes(pin) ? "IN" : "OUT",
          class: inputs.includes(pin) ? "comb_input" : "comb_output",
        },
      ]),
    );
    const result = openxc7Computations(
      view,
      { ff: { type, attributes: { X_ORIG_TYPE: orig } } },
      { cells: { ff: { type, ports, arcs: [] } }, sinks: [] },
      [],
      {},
    );
    assert.deepEqual(
      result.arcs
        .map((a) => [a.from, a.to].map((i) => result.pins[i].pin).join("/"))
        .sort(),
      expected.sort(),
    );
    assert.ok(result.arcs.every((a) => a.timing.delayPs === null));
  }
});
