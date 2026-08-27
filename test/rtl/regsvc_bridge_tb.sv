`timescale 1ns/1ps

module regsvc_bridge_tb;
    reg         clk = 1'b0;
    reg         resetn = 1'b0;

    reg  [31:0] s_axis_tdata = 32'b0;
    reg         s_axis_tvalid = 1'b0;
    wire        s_axis_tready;
    reg         s_axis_tlast = 1'b0;

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1'b1;

    reg  [31:0] s_dbg_tdata = 32'b0;
    reg         s_dbg_tvalid = 1'b0;
    wire        s_dbg_tready;
    reg         s_dbg_tlast = 1'b0;

    wire [31:0] m_dbg_tdata;
    wire        m_dbg_tvalid;
    reg         m_dbg_tready = 1'b1;

    regsvc_pair_fixture dut (
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
        .m_axis_tlast(),
        .s_dbg_tdata(s_dbg_tdata),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(s_dbg_tvalid),
        .s_dbg_tready(s_dbg_tready),
        .s_dbg_tlast(s_dbg_tlast),
        .m_dbg_tdata(m_dbg_tdata),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(m_dbg_tvalid),
        .m_dbg_tready(m_dbg_tready),
        .m_dbg_tlast()
    );

    always #5 clk = ~clk;

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
    end
endmodule
