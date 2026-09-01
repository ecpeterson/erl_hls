`timescale 1ns/1ps

module phi_memory_bridge_tb;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg [31:0] s_axis_tdata = 32'b0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    reg s_axis_tlast = 1'b0;

    wire [31:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;

    wire [32:0] routed_in = {s_axis_tlast, s_axis_tdata};
    wire [32:0] routed_out;

    assign m_axis_tdata = routed_out[31:0];

    __phi_memory_gateway__Top_0_next dut (
        .clk(clk),
        .reset(!resetn),
        .phi_memory_gateway__routed_in(routed_in),
        .phi_memory_gateway__routed_in_vld(s_axis_tvalid),
        .phi_memory_gateway__routed_in_rdy(s_axis_tready),
        .phi_memory_gateway__routed_out_rdy(m_axis_tready),
        .phi_memory_gateway__routed_out(routed_out),
        .phi_memory_gateway__routed_out_vld(m_axis_tvalid)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
    end
endmodule
