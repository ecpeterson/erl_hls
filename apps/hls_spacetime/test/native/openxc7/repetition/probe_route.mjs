/** Verify the directed on-path geometry of the reconvergent fixture against native BEL wires. */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { openxc7Paths } from "../../../../scripts/openxc7-sta.mjs";
import {
  createNativeRouting,
  nativeConnection,
} from "../../../../web/native-routes.js";
const read = async (file) =>
  JSON.parse(await readFile(join(process.argv[2], file)));
const {
  modules: { top },
} = await read("routed.json");
const {
  paths: [path],
} = openxc7Paths(await read("sta.json"), top);
const { nets } = await read("routes.json");
const routing = createNativeRouting(nets);
const endpoints = await read("native-pins.json");
const result = [];
for (const arc of path.arcs.filter((a) => a.kind === "net")) {
  const branch = nativeConnection(routing, arc.net, arc.source, arc.target);
  if (branch.disposition === "resolved") {
    const pins = endpoints[arc.net].pins;
    const wire = (pin) =>
      pins.find((row) => row.cell + "/" + row.port === pin).wire;
    assert.equal(branch.nodes[0].id, wire(arc.source));
    assert.equal(branch.nodes.at(-1).id, wire(arc.target));
  } else assert.equal(branch.nodes.length, 0);
  result.push({
    net: arc.net,
    source: arc.source,
    target: arc.target,
    disposition: branch.disposition,
    pips: branch.pips.length,
  });
}
assert.ok(result.some((row) => row.disposition === "resolved" && row.pips > 0));
console.log(JSON.stringify(result));
