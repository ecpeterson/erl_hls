#!/usr/bin/env python3
"""Check simulation cleanup against a four-state sequential reference, including pre-clock values."""
import argparse
import json
from pathlib import Path

from test_phi_bridge import execute, simulation_netlist

REFERENCE = r"""
module reference(input clk, reset, enable, input [7:0] data,
                 output [7:0] result, constant, output [23:0] hls_probe_values);
    reg [7:0] value, zero;
    always @(posedge clk) begin
        value <= reset ? 8'b0 : (enable ? data : value);
        zero <= 0;
    end
    wire [7:0] first = value + 8'b0;
    wire [7:0] second = value + 8'b0;
    assign result = first | second;
    assign constant = zero;
    assign hls_probe_values = {first, second, zero};
endmodule
"""

TESTBENCH = r"""
module tb;
    reg clk = 0, reset = 0, enable = 0;
    reg [7:0] data = 0;
    wire [39:0] expected, actual;
    reference gold(clk, reset, enable, data, expected[7:0], expected[15:8], expected[39:16]);
    hls_phi_device_0 gate(clk, reset, enable, data, actual[7:0], actual[15:8], actual[39:16]);
    function value(input integer i);
        case (i) 0: value = 0; 1: value = 1; 2: value = 1'bx; 3: value = 1'bz; endcase
    endfunction
    task check;
        if (actual !== expected) $fatal(1, "four-state mismatch: %h != %h", actual, expected);
    endtask
    integer r, e, d;
    initial begin
        #1; check();
        // Sweep all four control values and representative mixed X/Z data.
        for (r=0; r<4; r=r+1) for (e=0; e<4; e=e+1) for (d=0; d<4; d=d+1) begin
            reset=1; enable=0; #1; clk=1; #1; check(); clk=0;
            reset=value(r); enable=value(e); data={2'b10, value(d), 2'b01, value(d), 2'b11};
            #1; check(); clk=1; #1; check(); clk=0;
            reset=0; enable=0; #1; clk=1; #1; check(); clk=0;
        end
        $display("PASS: 64 four-state scenarios, reset/hold transitions and pre-clock values");
        $finish;
    end
endmodule
"""


def main() -> None:
    """Compare original RTL with the exact cleanup used by the Phi simulation build."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    args.stage = args.stage.resolve()
    debug = args.stage / "device0/debug"
    debug.mkdir(parents=True, exist_ok=False)
    source = args.stage / "reference.v"
    source.write_text(REFERENCE)
    testbench = args.stage / "tb.sv"
    testbench.write_text(TESTBENCH)
    execute([args.yosys, "-Q", "-T", "-p",
             f"read_verilog {json.dumps(str(source))}; hierarchy -top reference; proc; "
             f"rename reference hls_phi_device_0; write_json {json.dumps(str(debug / 'instrumented.json'))}"],
            args.stage, "reference")
    optimized = simulation_netlist(args, 0)
    executable = args.stage / "test.vvp"
    execute(["iverilog", "-g2012", "-s", "tb", "-o", str(executable),
             str(source), str(optimized), str(testbench)], args.stage, "compile")
    execute(["vvp", str(executable)], args.stage, "witness")
    print((args.stage / "witness.log").read_text(), end="")


if __name__ == "__main__":
    main()
