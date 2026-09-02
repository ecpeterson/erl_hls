// Routed phi-memory gateway plus the shared passive boundary monitor. The
// application gateway owns endpoint 1 on its application stream. The debug
// stream uses the existing two-endpoint router fixture with endpoint 1 active;
// endpoint 2 is tied off until debug endpoint allocation is generated.
module phi_memory_debug_top (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    output wire [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,

    input  wire [31:0] s_dbg_tdata,
    input  wire [3:0]  s_dbg_tkeep,
    input  wire        s_dbg_tvalid,
    output wire        s_dbg_tready,
    input  wire        s_dbg_tlast,

    output wire [31:0] m_dbg_tdata,
    output wire [3:0]  m_dbg_tkeep,
    output wire        m_dbg_tvalid,
    input  wire        m_dbg_tready,
    output wire        m_dbg_tlast
);
    wire [32:0] routed_in = {s_axis_tlast, s_axis_tdata};
    wire [32:0] routed_out;

    wire [32:0] debug_shared_in = {s_dbg_tlast, s_dbg_tdata};
    wire [32:0] debug_shared_out;
    wire [32:0] debug_local_in;
    wire [32:0] debug_local_out;
    wire        debug_local_in_valid;
    wire        debug_local_in_ready;
    wire        debug_local_out_valid;
    wire        debug_local_out_ready;

    __phi_memory_gateway__Top_0_next application (
        .clk(aclk),
        .reset(!aresetn),
        .phi_memory_gateway__routed_in(routed_in),
        .phi_memory_gateway__routed_in_vld(s_axis_tvalid),
        .phi_memory_gateway__routed_in_rdy(s_axis_tready),
        .phi_memory_gateway__routed_out(routed_out),
        .phi_memory_gateway__routed_out_vld(m_axis_tvalid),
        .phi_memory_gateway__routed_out_rdy(m_axis_tready)
    );

    __hls_fabric_router__PairIngress_0_next debug_ingress (
        .clk(aclk),
        .reset(!aresetn),
        .hls_fabric_router__shared_in(debug_shared_in),
        .hls_fabric_router__shared_in_vld(s_dbg_tvalid),
        .hls_fabric_router__shared_in_rdy(s_dbg_tready),
        .hls_fabric_router__endpoint_one_out(debug_local_in),
        .hls_fabric_router__endpoint_one_out_vld(debug_local_in_valid),
        .hls_fabric_router__endpoint_one_out_rdy(debug_local_in_ready),
        .hls_fabric_router__endpoint_two_out(),
        .hls_fabric_router__endpoint_two_out_vld(),
        .hls_fabric_router__endpoint_two_out_rdy(1'b1)
    );

    __hls_fabric_router__PairEgress_0_next debug_egress (
        .clk(aclk),
        .reset(!aresetn),
        .hls_fabric_router__endpoint_one_in(debug_local_out),
        .hls_fabric_router__endpoint_one_in_vld(debug_local_out_valid),
        .hls_fabric_router__endpoint_one_in_rdy(debug_local_out_ready),
        .hls_fabric_router__endpoint_two_in(33'b0),
        .hls_fabric_router__endpoint_two_in_vld(1'b0),
        .hls_fabric_router__endpoint_two_in_rdy(),
        .hls_fabric_router__shared_out(debug_shared_out),
        .hls_fabric_router__shared_out_vld(m_dbg_tvalid),
        .hls_fabric_router__shared_out_rdy(m_dbg_tready)
    );

    hls_debug_monitor debug_monitor (
        .aclk(aclk),
        .aresetn(aresetn),
        .app_rx_tdata(s_axis_tdata),
        .app_rx_tvalid(s_axis_tvalid),
        .app_rx_tready(s_axis_tready),
        .app_rx_tlast(s_axis_tlast),
        .app_tx_tdata(routed_out[31:0]),
        .app_tx_tvalid(m_axis_tvalid),
        .app_tx_tready(m_axis_tready),
        .app_tx_tlast(routed_out[32]),
        .s_dbg_tdata(debug_local_in[31:0]),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(debug_local_in_valid),
        .s_dbg_tready(debug_local_in_ready),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out[31:0]),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(debug_local_out_valid),
        .m_dbg_tready(debug_local_out_ready),
        .m_dbg_tlast(debug_local_out[32])
    );

    assign m_axis_tdata = routed_out[31:0];
    assign m_axis_tlast = routed_out[32];
    assign m_axis_tkeep = 4'hf;
    assign m_dbg_tdata = debug_shared_out[31:0];
    assign m_dbg_tlast = debug_shared_out[32];
    assign m_dbg_tkeep = 4'hf;

endmodule
