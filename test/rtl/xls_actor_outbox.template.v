// Production RAM shell; all observations cross an explicit diagnostic port.
module @NAME@_wrapper(
    input wire clk, reset,
    input wire [127:0] command0, command1,
    input wire command0_valid, command1_valid,
    output wire command0_ready, command1_ready,
    output wire [127:0] report0, report1,
    output wire report0_valid, report1_valid,
    input wire report0_ready, report1_ready,
    output wire [47:0] observation,
    output wire observation_valid
);
@WIRES@
    @NAME@ core(.clk(clk), .reset(reset),
        ._command0(command0), ._command0_vld(command0_valid), ._command0_rdy(command0_ready),
        ._command1(command1), ._command1_vld(command1_valid), ._command1_rdy(command1_ready),
        ._report0(report0), ._report0_vld(report0_valid), ._report0_rdy(report0_ready),
        ._report1(report1), ._report1_vld(report1_valid), ._report1_rdy(report1_ready)
@PORTS@
@DEBUG@
    );
@DEBUG_ASSIGN@
@RAMS@
endmodule
