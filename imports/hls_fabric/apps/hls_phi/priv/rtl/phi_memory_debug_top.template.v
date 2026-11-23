// Routed phi-memory gateway plus the shared passive boundary monitor. The
// application gateway owns endpoint 1 on its application stream. The debug
// stream routes endpoint 1 to the boundary monitor. Unknown routes drain.
//
// Scheduler RAM declarations, ports, and instances are inserted by
// phi_memory_debug_top_v.
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
    wire [32:0] debug_local_in;
    wire [32:0] debug_local_out;
    wire [3:0] debug_local_keep_in, debug_local_keep_out;
    wire        debug_local_in_valid;
    wire        debug_local_in_ready;
    wire        debug_local_out_valid;
    wire        debug_local_out_ready;

@APPLICATION@
    hls_fabric_ingress #(.PORTS(1),.ENDPOINTS(16'd1)) debug_ingress (
        .clk(aclk),.reset(!aresetn),
        .s_data(s_dbg_tdata),.s_keep(s_dbg_tkeep),.s_last(s_dbg_tlast),
        .s_valid(s_dbg_tvalid),.s_ready(s_dbg_tready),
        .m_data(debug_local_in[31:0]),.m_keep(debug_local_keep_in),
        .m_last(debug_local_in[32]),.m_valid(debug_local_in_valid),
        .m_ready(debug_local_in_ready),.m_source(),.route_error()
    );
    hls_fabric_egress #(.PORTS(1),.ENDPOINTS(16'd1)) debug_egress (
        .clk(aclk),.reset(!aresetn),
        .s_data(debug_local_out[31:0]),.s_keep(debug_local_keep_out),
        .s_last(debug_local_out[32]),.s_valid(debug_local_out_valid),
        .s_ready(debug_local_out_ready),.s_destination(16'd0),
        .m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_last(m_dbg_tlast),
        .m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready)
    );

    hls_debug_monitor #(.ROUTED(1)) debug_monitor (
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
        .s_dbg_tkeep(debug_local_keep_in),
        .s_dbg_tvalid(debug_local_in_valid),
        .s_dbg_tready(debug_local_in_ready),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out[31:0]),
        .m_dbg_tkeep(debug_local_keep_out),
        .m_dbg_tvalid(debug_local_out_valid),
        .m_dbg_tready(debug_local_out_ready),
        .m_dbg_tlast(debug_local_out[32])
    );

endmodule
