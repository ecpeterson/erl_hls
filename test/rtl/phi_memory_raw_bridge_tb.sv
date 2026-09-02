`timescale 1ns/1ps

module phi_memory_raw_bridge_tb;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg [31:0] s_axis_tdata = 32'b0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    reg s_axis_tlast = 1'b0;

    wire [31:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;

    phi_memory_raw_d3 dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast()
    );

    always #5 clk = ~clk;

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
    end
endmodule
