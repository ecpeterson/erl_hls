import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createModel } from "../web/model.js";
import {
  createComputations,
  computationLayers,
} from "../web/computation-routes.js";
import { openxc7Computations } from "../scripts/openxc7-computations.mjs";

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
