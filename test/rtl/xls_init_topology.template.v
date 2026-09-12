// Public topology boundary and production RAMs; RAM contents survive reset.
module @NAME@_wrapper (
    input wire clk, reset,
    output wire [127:0] _reports_out,
    output wire _reports_out_vld,
    input wire _reports_out_rdy
);
@WIRES@
    @NAME@ dut (
        .clk(clk), .reset(reset),
        ._commands_in('0), ._commands_in_vld(1'b0), ._commands_in_rdy(),
        ._reports_out(_reports_out),
        ._reports_out_vld(_reports_out_vld),
        ._reports_out_rdy(_reports_out_rdy)
@PORTS@
    );
@RAMS@
endmodule
