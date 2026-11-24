import assert from "node:assert/strict";
import test from "node:test";
import { openxc7Paths } from "../scripts/openxc7-sta.mjs";

/** One same-edge launch and capture, with both pins attached to routed net ID 2. */
function fixture() {
  const top = {
    cells: {
      ff: {
        connections: { D: [2], Q: [2] },
        port_directions: { D: "input", Q: "output" },
      },
    },
    netnames: { q: { bits: [2] } },
  };
  const points = [
    ["clock_to_q", "Q", 100, 100],
    ["net", "D", 350, 450],
    ["setup", "D", 100, 550],
  ].map(([kind, port, delay_ps, arrival_ps]) => ({
    kind,
    cell: "ff",
    port,
    net: kind === "net" ? "q" : null,
    delay_ps,
    arrival_ps,
  }));
  const path = {
    points,
    launch_clock: "clk",
    capture_clock: "clk",
    launch_edge: "rising",
    capture_edge: "rising",
    path_delay_ps: 550,
    required_ps: 5000,
    slack_ps: 4450,
  };
  return { top, report: { schema: 1, unit: "ps", paths: [path] }, path };
}

test("native setup evidence requires exact ordered sums, both endpoints and a checked clock", () => {
  const { top, report, path } = fixture();
  const [actual] = openxc7Paths(report, top).paths;
  assert.deepEqual(
    [actual.dataDelayNs, actual.setupNs, actual.slackNs, actual.arcs[0].fanout],
    [0.45, 0.1, 4.45, 1],
  );
  for (const change of [
    (f) => f.path.points[1].arrival_ps++,
    (f) => (f.top.cells.ff.connections.Q = [3]),
    (f) => (f.path.capture_clock = "unrelated"),
    (f) => (f.path.launch_edge = f.path.capture_edge = "unsupported"),
    (f) => f.path.slack_ps++,
  ]) {
    const f = fixture();
    change(f);
    assert.throws(() => openxc7Paths(f.report, f.top), /critical path/);
  }
  path.capture_clock = "async";
  path.required_ps = null;
  path.slack_ps = null;
  const partial = openxc7Paths(report, top);
  assert.equal(partial.paths.length, 0);
  assert.equal(partial.unchecked[0].arrivalPs, 550);
});
