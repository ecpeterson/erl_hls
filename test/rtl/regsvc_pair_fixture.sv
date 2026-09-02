// Simulation-only composition fixture. A production Vivado design should
// package the router and endpoint boundaries independently and wire its chosen
// topology in the block design.
//
// Two translated processes share packet-routed application and debug streams.
// Each packet starts with {source[15:0], destination[15:0]} and then carries
// one unchanged endpoint frame through TLAST.
module regsvc_pair_fixture (
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
    wire [32:0] app_shared_in = {s_axis_tlast, s_axis_tdata};
    wire [32:0] app_shared_out;
    wire [32:0] app_one_in;
    wire [32:0] app_two_in;
    wire [32:0] app_one_out;
    wire [32:0] app_two_out;
    wire app_one_in_valid;
    wire app_two_in_valid;
    wire app_one_in_ready;
    wire app_two_in_ready;
    wire app_one_out_valid;
    wire app_two_out_valid;
    wire app_one_out_ready;
    wire app_two_out_ready;

    wire [32:0] debug_shared_in = {s_dbg_tlast, s_dbg_tdata};
    wire [32:0] debug_shared_out;
    wire [32:0] debug_one_in;
    wire [32:0] debug_two_in;
    wire [32:0] debug_one_out;
    wire [32:0] debug_two_out;
    wire debug_one_in_valid;
    wire debug_two_in_valid;
    wire debug_one_in_ready;
    wire debug_two_in_ready;
    wire debug_one_out_valid;
    wire debug_two_out_valid;
    wire debug_one_out_ready;
    wire debug_two_out_ready;

    __hls_fabric_router__PairIngress_0_next app_ingress (
        .clk(aclk),
        .reset(!aresetn),
        ._shared_in(app_shared_in),
        ._shared_in_vld(s_axis_tvalid),
        ._shared_in_rdy(s_axis_tready),
        ._endpoint_one_out(app_one_in),
        ._endpoint_one_out_vld(app_one_in_valid),
        ._endpoint_one_out_rdy(app_one_in_ready),
        ._endpoint_two_out(app_two_in),
        ._endpoint_two_out_vld(app_two_in_valid),
        ._endpoint_two_out_rdy(app_two_in_ready)
    );

    __hls_fabric_router__PairEgress_0_next app_egress (
        .clk(aclk),
        .reset(!aresetn),
        ._endpoint_one_in(app_one_out),
        ._endpoint_one_in_vld(app_one_out_valid),
        ._endpoint_one_in_rdy(app_one_out_ready),
        ._endpoint_two_in(app_two_out),
        ._endpoint_two_in_vld(app_two_out_valid),
        ._endpoint_two_in_rdy(app_two_out_ready),
        ._shared_out(app_shared_out),
        ._shared_out_vld(m_axis_tvalid),
        ._shared_out_rdy(m_axis_tready)
    );

    __hls_fabric_router__PairIngress_0_next debug_ingress (
        .clk(aclk),
        .reset(!aresetn),
        ._shared_in(debug_shared_in),
        ._shared_in_vld(s_dbg_tvalid),
        ._shared_in_rdy(s_dbg_tready),
        ._endpoint_one_out(debug_one_in),
        ._endpoint_one_out_vld(debug_one_in_valid),
        ._endpoint_one_out_rdy(debug_one_in_ready),
        ._endpoint_two_out(debug_two_in),
        ._endpoint_two_out_vld(debug_two_in_valid),
        ._endpoint_two_out_rdy(debug_two_in_ready)
    );

    __hls_fabric_router__PairEgress_0_next debug_egress (
        .clk(aclk),
        .reset(!aresetn),
        ._endpoint_one_in(debug_one_out),
        ._endpoint_one_in_vld(debug_one_out_valid),
        ._endpoint_one_in_rdy(debug_one_out_ready),
        ._endpoint_two_in(debug_two_out),
        ._endpoint_two_in_vld(debug_two_out_valid),
        ._endpoint_two_in_rdy(debug_two_out_ready),
        ._shared_out(debug_shared_out),
        ._shared_out_vld(m_dbg_tvalid),
        ._shared_out_rdy(m_dbg_tready)
    );

    axis_regsvc_debug_top endpoint_one (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(app_one_in[31:0]),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(app_one_in_valid),
        .s_axis_tready(app_one_in_ready),
        .s_axis_tlast(app_one_in[32]),
        .m_axis_tdata(app_one_out[31:0]),
        .m_axis_tkeep(),
        .m_axis_tvalid(app_one_out_valid),
        .m_axis_tready(app_one_out_ready),
        .m_axis_tlast(app_one_out[32]),
        .s_dbg_tdata(debug_one_in[31:0]),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(debug_one_in_valid),
        .s_dbg_tready(debug_one_in_ready),
        .s_dbg_tlast(debug_one_in[32]),
        .m_dbg_tdata(debug_one_out[31:0]),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(debug_one_out_valid),
        .m_dbg_tready(debug_one_out_ready),
        .m_dbg_tlast(debug_one_out[32])
    );

    axis_regsvc_debug_top endpoint_two (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(app_two_in[31:0]),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(app_two_in_valid),
        .s_axis_tready(app_two_in_ready),
        .s_axis_tlast(app_two_in[32]),
        .m_axis_tdata(app_two_out[31:0]),
        .m_axis_tkeep(),
        .m_axis_tvalid(app_two_out_valid),
        .m_axis_tready(app_two_out_ready),
        .m_axis_tlast(app_two_out[32]),
        .s_dbg_tdata(debug_two_in[31:0]),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(debug_two_in_valid),
        .s_dbg_tready(debug_two_in_ready),
        .s_dbg_tlast(debug_two_in[32]),
        .m_dbg_tdata(debug_two_out[31:0]),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(debug_two_out_valid),
        .m_dbg_tready(debug_two_out_ready),
        .m_dbg_tlast(debug_two_out[32])
    );

    assign m_axis_tdata = app_shared_out[31:0];
    assign m_axis_tlast = app_shared_out[32];
    assign m_axis_tkeep = 4'hf;
    assign m_dbg_tdata = debug_shared_out[31:0];
    assign m_dbg_tlast = debug_shared_out[32];
    assign m_dbg_tkeep = 4'hf;

endmodule
