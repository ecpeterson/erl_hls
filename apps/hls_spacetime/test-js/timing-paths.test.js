import test from "node:test";
import assert from "node:assert/strict";
import { parseTimingPaths } from "../scripts/timing-paths.mjs";

const cells = [
  { id: "top/start" },
  { id: "top/logic_with_a_long_generated_name[17]" },
  { id: "top/end" },
];
/** Native-shaped synthetic report: clock branches surround the data section;
 * long primitive delay descriptions continue on separate numeric lines. */
function report() {
  return `Vivado report_timing -path_type full_clock_expanded -input_pins
Slack (VIOLATED) : -0.250ns (required time - arrival time)
  Source: top/start/C
  Destination: top/end/D
  Path Type: Setup (Max at Slow Process Corner)
  Data Path Delay: 1.250ns (logic 0.500ns (40.000%) route 0.750ns (60.000%))
  Logic Levels: 1 (LUT6=1)
  Location Delay type Incr(ns) Path(ns) Netlist Resource(s)
  -------------------------------------------------------------------
                         (clock workload rise edge)
                                                      0.000 0.000 r clk (IN)
    BUFGCE_X1Y38                                      r top/clock_buffer/I
    SLICE_X1Y1 FDRE                                   r top/start/C
  -------------------------------------------------------------------
    SLICE_X1Y1 FDRE (Prop_BFF2_SLICEM_C_Q)
                                                      0.100 2.100 r top/start/Q
                         net (fo=2, routed)           0.250 2.350 top/source_net[0]
    SLICE_X2Y2                                        r top/logic_with_a_long_generated_name[17]/I5
    SLICE_X2Y2 LUT6 (Prop_C6LUT_SLICEL_I5_O)
                                                      0.400 2.750 f top/logic_with_a_long_generated_name[17]/O
                         net (fo=1, routed)           0.500 3.250 top/result_net[3]
    SLICE_X3Y3 FDRE                                   f top/end/D
  -------------------------------------------------------------------
                         (clock workload rise edge)
    BUFGCE_X1Y38                                      r top/clock_buffer/O
    SLICE_X3Y3 FDRE                                   r top/end/C
                         required time 3.000
                         arrival time -3.250
                         slack -0.250
`;
}

test("ordered data pins exclude both clock branches and preserve wrapped delay fields", () => {
  const [path] = parseTimingPaths(report(), { cells });
  assert.equal(path.id, "max/0");
  assert.equal(path.source, "top/start/C");
  assert.equal(path.launchPin, "top/start/Q");
  assert.equal(path.endpoint, "top/end/D");
  assert.equal(path.slackNs, -0.25);
  assert.equal(path.logicLevels, 1);
  assert.deepEqual(
    [path.dataDelayNs, path.logicDelayNs, path.routeDelayNs],
    [1.25, 0.5, 0.75],
  );
  assert.deepEqual(
    path.steps.map((p) => p.pin),
    [
      "top/start/Q",
      "top/logic_with_a_long_generated_name[17]/I5",
      "top/logic_with_a_long_generated_name[17]/O",
      "top/end/D",
    ],
  );
  assert.equal(path.steps[0].incrementNs, 0.1);
  assert.equal(path.steps[1].incrementNs, null);
  assert.equal(path.steps[1].arrivalNs, null);
  assert.equal(path.steps[2].transition, "f");
  assert.deepEqual(
    path.arcs.map((arc) => [arc.kind, arc.delayNs]),
    [
      ["net", 0.25],
      ["logic", 0.4],
      ["net", 0.5],
    ],
  );
  assert.equal(path.arcs[0].net, "top/source_net[0]");
  assert.equal(path.arcs[0].fanout, 2);
});

test("multiple setup paths retain report order, including CRLF and cell maps", () => {
  const parsed = parseTimingPaths(
    (report() + report()).replaceAll("\n", "\r\n"),
    { cells: new Map(cells.map((c) => [c.id, c])) },
  );
  assert.deepEqual(
    parsed.map((p) => p.id),
    ["max/0", "max/1"],
  );
});

test("missing launch/endpoint rows and missing numeric logic delays reject", () => {
  for (const bad of [
    report().replace("r top/start/C", "r top/start/OTHER"),
    report().replace("f top/end/D", "f top/end/OTHER"),
    report().replace("0.400 2.750 f", "f"),
  ])
    assert.throws(() => parseTimingPaths(bad, { cells }), /Timing report:/);
});

test("exact cell identity is mandatory; no generated-name alias guessing", () => {
  assert.throws(
    () => parseTimingPaths(report(), { cells: cells.slice(0, 2) }),
    /unknown endpoint cell/,
  );
  assert.throws(
    () =>
      parseTimingPaths(report(), {
        cells: cells.filter((c) => c.id !== "top/start"),
      }),
    /unknown source cell/,
  );
  const missingLogic = cells.filter((c) => !c.id.includes("logic"));
  assert.throws(
    () => parseTimingPaths(report(), { cells: missingLogic }),
    /unknown cell/,
  );
  assert.throws(
    () => parseTimingPaths(report(), { cells: [...cells, cells[0]] }),
    /duplicate catalogue cell/,
  );
});

test("incomplete/unsupported reports and malformed net records reject", () => {
  for (const bad of [
    "incomplete native output",
    report().replace("Logic Levels:", "Levels missing:"),
    report().replace("Logic Levels: 1", "Logic Levels: 2"),
    report().replace(
      /[^\n]*r top\/logic_with_a_long_generated_name\[17\]\/I5\n/,
      "",
    ),
    report().replace("Data Path Delay:", "Delay missing:"),
    report().replace(
      "Setup (Max at Slow Process Corner)",
      "Hold (Min at Fast Process Corner)",
    ),
    report().replace("net (fo=2, routed)", "net (fo=unknown, routed)"),
    report().replace(/\s*net \(fo=2, routed\)[^\n]+\n/, "\n"),
  ])
    assert.throws(() => parseTimingPaths(bad, { cells }), /Timing report:/);
  assert.deepEqual(
    parseTimingPaths("No constrained timing paths returned for max.\n", {
      cells,
    }),
    [],
  );
});

test("bounded bytes, paths and pins reject before publishing partial paths", () => {
  assert.throws(
    () => parseTimingPaths(report(), { cells, maxBytes: 32 }),
    /byte limit/,
  );
  assert.throws(
    () => parseTimingPaths(report() + report(), { cells, maxPaths: 1 }),
    /path limit/,
  );
  assert.throws(
    () => parseTimingPaths(report(), { cells, maxSteps: 3 }),
    /data-pin limit/,
  );
  assert.throws(
    () => parseTimingPaths(report(), { cells, maxSteps: 0 }),
    /invalid parser bound/,
  );
});
