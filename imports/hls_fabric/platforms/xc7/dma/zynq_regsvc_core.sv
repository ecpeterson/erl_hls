// Two routed regsvc actors with independent application and debug DMA slots.
// All streams and the GP0 slave share the same fabric clock/reset.
module zynq_regsvc_core (
    input wire clock, input wire reset_n,
    input wire [11:0] awid, input wire [31:0] awaddr,
    input wire [3:0] awlen, input wire [2:0] awsize,
    input wire [1:0] awburst, input wire [1:0] awlock,
    input wire awvalid, output wire awready,
    input wire [11:0] wid, input wire [31:0] wdata,
    input wire [3:0] wstrb, input wire wlast, input wire wvalid, output wire wready,
    output wire [11:0] bid, output wire [1:0] bresp,
    output wire bvalid, input wire bready,
    input wire [11:0] arid, input wire [31:0] araddr,
    input wire [3:0] arlen, input wire [2:0] arsize,
    input wire [1:0] arburst, input wire [1:0] arlock,
    input wire arvalid, output wire arready,
    output wire [11:0] rid, output wire [31:0] rdata,
    output wire [1:0] rresp, output wire rlast,
    output wire rvalid, input wire rready,
    output wire [1:0] irq
);
    wire [63:0] tx_data, rx_data;
    wire [1:0] tx_last, tx_valid, tx_ready, rx_last, rx_valid, rx_ready;
    wire [3:0] app_keep, debug_keep;
    zynq_dma_pair transport(.*);
    regsvc_fabric_fixture services (
        .aclk(clock), .aresetn(reset_n),
        .s_axis_tdata(tx_data[31:0]), .s_axis_tkeep(4'hf), .s_axis_tlast(tx_last[0]),
        .s_axis_tvalid(tx_valid[0]), .s_axis_tready(tx_ready[0]),
        .m_axis_tdata(rx_data[31:0]), .m_axis_tkeep(app_keep), .m_axis_tlast(rx_last[0]),
        .m_axis_tvalid(rx_valid[0]), .m_axis_tready(rx_ready[0]),
        .s_dbg_tdata(tx_data[63:32]), .s_dbg_tkeep(4'hf), .s_dbg_tlast(tx_last[1]),
        .s_dbg_tvalid(tx_valid[1]), .s_dbg_tready(tx_ready[1]),
        .m_dbg_tdata(rx_data[63:32]), .m_dbg_tkeep(debug_keep), .m_dbg_tlast(rx_last[1]),
        .m_dbg_tvalid(rx_valid[1]), .m_dbg_tready(rx_ready[1])
    );
endmodule
