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

test("only a corroborated packer buffer with a constant configured LUT half stops the data cone", async (t) => {
  const { view } = await sourceFixture(t);
  const packed = {
    zero: { type: "PSEUDO_GND", attributes: {} },
    one: { type: "PSEUDO_VCC", attributes: {} },
    buffer: {
      type: "SLICE_LUTX",
      attributes: {
        X_ORIG_TYPE: "LUT1",
        X_ORIG_PORT_O6: "O",
        NEXTPNR_BEL: "SLICE_X1Y0/A6LUT",
      },
      parameters: { INIT: "0010" },
    },
  };
  const port = (net, direction, cls) => ({
    net,
    direction,
    class: cls,
    bound: true,
  });
  const cells = {
    zero: {
      type: "PSEUDO_GND",
      ports: { Y: port("low", "OUT", "ignore") },
      arcs: [],
    },
    one: {
      type: "PSEUDO_VCC",
      ports: { Y: port("high", "OUT", "ignore") },
      arcs: [],
    },
    buffer: {
      type: "SLICE_LUTX",
      ports: {
        A2: port("changing", "IN", "comb_input"),
        A6: port("high", "IN", "comb_input"),
        O6: port("forwarded", "OUT", "comb_output"),
      },
      arcs: [],
      lut_buffer: {
        input_net: "low",
        output_net: "forwarded",
        driver: "zero",
        driver_port: "Y",
      },
    },
  };
  const boundary = (p, c) =>
    openxc7Computations(view, p, { cells: c, sinks: [] }, [], {}).cells.find(
      (x) => x.id === "buffer",
    ).boundary;
  assert.equal(boundary(packed, cells), "constant");
  for (const change of [
    (p, c) => delete c.buffer.lut_buffer,
    (p, c) => (c.buffer.lut_buffer.driver = "unknown"),
    (p, c) => (c.buffer.lut_buffer.output_net = "foreign"),
    (p, c) => (c.buffer.ports.A6.bound = false),
    (p) => (p.buffer.parameters.INIT = "11"),
    (p) => (p.buffer.attributes.X_ORIG_PORT_A2 = "I0"),
  ]) {
    const p = structuredClone(packed),
      c = structuredClone(cells);
    change(p, c);
    assert.equal(boundary(p, c), "combinational");
  }
});

test("the registered DSP model exposes a clocked P frontier", async (t) => {
  const { view } = await sourceFixture(t);
  const type = "DSP48E1_DSP48E1";
  const packed = { dsp: { type, attributes: {} } };
  const clock = { port: "CLK", edge: "rising", clock_to_q_ps: 383 };
  for (const [model, enabled, expected] of [
    [{ registered_dsp_model_sha256: "test" }, true, "hard_block"],
    [{ registered_dsp_model_sha256: "test" }, false, "unsupported"],
    [{}, true, "unsupported"],
  ]) {
    const ports = {
      P0: {
        net: "product",
        direction: "OUT",
        class: enabled ? "register_output" : "ignore",
        clocks: enabled ? [clock] : [],
      },
    };
    const result = openxc7Computations(
      view,
      packed,
      { cells: { dsp: { type, ports, arcs: [] } }, sinks: [] },
      [],
      model,
    );
    assert.equal(result.cells[0].boundary, expected);
    assert.deepEqual(result.pins[0].clocks, ports.P0.clocks);
    assert.equal(result.arcs.length, 0);
  }
});

test("only a modeled SRL output ends a clocked cone", async (t) => {
  const { view } = await sourceFixture(t);
  const type = "SLICE_LUTX";
  const packed = { tap: { type, attributes: { X_LUT_AS_SRL: "1", X_ORIG_TYPE: "SRL16E" } } };
  const clock = { port: "CLK", edge: "rising", clock_to_q_ps: 1102 };
  for (const [model, portClass, expected] of [
    [{ fixed_srl_model_sha256: "test" }, "register_output", "hard_block"],
    [{ fixed_srl_model_sha256: "test" }, "comb_output", "unsupported"],
    [{}, "register_output", "unsupported"],
  ]) {
    const ports = { O6: { net: "tap", direction: "OUT", class: portClass, clocks: [clock] } };
    const timing = { cells: { tap: { type, ports, arcs: [] } }, sinks: [] };
    const result = openxc7Computations(view, packed, timing, [], model);
    assert.equal(result.cells[0].boundary, expected);
    assert.equal(result.arcs.length, 0);
  }
});
