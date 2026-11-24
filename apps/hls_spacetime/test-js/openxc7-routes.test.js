import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { openxc7Routing } from "../web/openxc7-routes.js";
import { nativeConnection } from "../web/native-routes.js";

/** Two exact packed endpoints share a tile. Only a supplied directed PIP connects them. */
function fixture() {
  const node = (id) => ({ id, wires: [{ id, tile: "CLB", x: 1, y: 2 }] });
  const pin = (cell, port, direction, wire) => ({
    pin: cell + "/" + port,
    cell,
    port,
    direction,
    status: "resolved",
    bel_pins: [cell + "/bel/" + port],
    site_pins: [],
    bel_wire: wire,
    routing_node: wire,
  });
  const net = {
    id: "d",
    aliases: ["d"],
    status: "complete",
    route_status: "ROUTED",
    nodes: [node("out"), node("mux")],
    issues: [],
    pin_attachments: [
      pin("lut", "O6", "OUT", "out"),
      pin("ff", "D", "IN", "mux"),
    ],
    pips: [
      {
        id: "MUX",
        tile: "CLB",
        x: 1,
        y: 2,
        from_node: "out",
        to_node: "mux",
        direction_status: "directional",
      },
    ],
  };
  const model = {
    bundle: { build: { implementation: "i" } },
    catalogue: { checkpoint: "r" },
    cells: new Set(["ff", "lut"]),
  };
  return {
    model,
    detail: { implementation: "i", checkpoint: "r", nets: [net] },
    net,
  };
}

test("exact BEL wires support an intrasite branch; an unknown switch leaves a visible gap", () => {
  const { model, detail, net } = fixture();
  const route = () =>
    nativeConnection(openxc7Routing(model, detail), "d", "lut/O6", "ff/D");
  const missing = structuredClone(model);
  delete missing.bundle.build.implementation;
  assert.throws(
    () => openxc7Routing(missing, { ...detail, implementation: undefined }),
    /mismatch/,
  );
  assert.deepEqual(
    route().pips.map((p) => p.id),
    ["MUX"],
  );
  assert.deepEqual(route().gaps, []);
  Object.assign(net.pips[0], {
    from_node: null,
    direction_status: "unavailable",
  });
  assert.notEqual(route().disposition, "resolved");
  assert.ok(route().gaps.length);
  assert.deepEqual(route().pips, []);
  assert.deepEqual(route().nodes, []);
  assert.throws(
    () => openxc7Routing(model, { ...detail, implementation: "other" }),
    /mismatch/,
  );
});

const dir = process.env.OPENXC7_ROUTING_FIXTURE;
test(
  "native branched fixture reaches both register D pins over their recorded PIPs",
  { skip: !dir },
  () => {
    const bytes = (file) => readFileSync(join(dir, file));
    const json = (file) => JSON.parse(bytes(file));
    const sha = (file) =>
      createHash("sha256").update(bytes(file)).digest("hex");
    const meta = json("manifest.json"),
      { nets } = json("routes.json"),
      { d } = json("native-pins.json");
    for (const file of Object.keys(meta.files))
      assert.equal(sha(file), meta.files[file].sha256);
    const implementation = sha("manifest.json"),
      checkpoint = sha("routed.json");
    const cells = new Set(Object.keys(json("routed.json").modules.top.cells));
    const index = openxc7Routing(
      {
        bundle: { build: { implementation } },
        catalogue: { checkpoint },
        cells,
      },
      { implementation, checkpoint, nets },
    );
    assert.deepEqual(nets[0].aliases, ["d", "d_alias"]);
    const nativeSwitches = new Set(
      bytes("fixed-routes.txt")
        .toString()
        .split("\n")
        .filter((line) => line.startsWith("d "))
        .map((line) => line.slice(2)),
    );
    for (const sink of ["first", "second"]) {
      const branch = nativeConnection(index, "d", "invert/O6", sink + "/D");
      assert.equal(branch.disposition, "resolved");
      assert.deepEqual(branch.gaps, []);
      assert.equal(
        branch.nodes[0].id,
        d.pins.find((p) => p.cell === "invert").wire,
      );
      assert.equal(
        branch.nodes.at(-1).id,
        d.pins.find((p) => p.cell === sink).wire,
      );
      assert.ok(branch.pips.some((p) => p.id.startsWith("SITEPIP/")));
      for (const [i, pip] of branch.pips.entries()) {
        assert.ok(nativeSwitches.has(pip.native_switch));
        assert.equal(pip.from_node, branch.nodes[i].id);
        assert.equal(pip.to_node, branch.nodes[i + 1].id);
        assert.equal(d.wires[pip.to_node].incoming, pip.id);
      }
    }
  },
);

test("a permuted input retains its physical BEL pin and the net-owned incoming switch", () => {
  const { model, detail, net } = fixture();
  const physical = "SITEWIRE/SLICE_X1Y2/B2",
    router = "SITEWIRE/SLICE_X1Y2/B3";
  Object.assign(net.nodes[1], { id: router });
  Object.assign(net.pips[0], { to_node: router, native_switch: "CLB/1.4" });
  const pin = net.pin_attachments[1];
  Object.assign(pin, {
    pin: "ff/A2",
    port: "A2",
    bel_pins: ["SLICE_X1Y2/B5LUT/A2"],
    bel_wire: physical,
    routing_node: router,
    lut_permutation_pip: "MUX",
  });
  assert.equal(
    nativeConnection(openxc7Routing(model, detail), "d", "lut/O6", "ff/A2")
      .disposition,
    "resolved",
  );
  for (const [key, value] of [
    ["lut_permutation_pip", "other"],
    ["bel_wire", router],
    ["bel_pins", ["SLICE_X1Y2/C5LUT/A2"]],
  ]) {
    const old = pin[key];
    pin[key] = value;
    assert.throws(() => openxc7Routing(model, detail), /permutation/);
    pin[key] = old;
  }
});
