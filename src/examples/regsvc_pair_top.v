// Two independent translated processes sharing packet-routed application and
// debug streams. Each fabric packet starts with {source[15:0], destination[15:0]}
// and then carries one unchanged endpoint frame through TLAST.
module axis_regsvc_pair_top (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ACLK, ASSOCIATED_BUSIF S_AXIS:M_AXIS:S_DBG:M_DBG, ASSOCIATED_RESET ARESETN" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    input  wire        aclk,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETN, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    input  wire        aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [31:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
    input  wire [3:0]  s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire        s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire        s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire        s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0]  m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_DBG TDATA" *)
    input  wire [31:0] s_dbg_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_DBG TKEEP" *)
    input  wire [3:0]  s_dbg_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_DBG TVALID" *)
    input  wire        s_dbg_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_DBG TREADY" *)
    output wire        s_dbg_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_DBG TLAST" *)
    input  wire        s_dbg_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_DBG TDATA" *)
    output wire [31:0] m_dbg_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_DBG TKEEP" *)
    output wire [3:0]  m_dbg_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_DBG TVALID" *)
    output wire        m_dbg_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_DBG TREADY" *)
    input  wire        m_dbg_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_DBG TLAST" *)
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

    __xls_fabric_router__PairIngress_0_next app_ingress (
        .clk(aclk),
        .reset(!aresetn),
        .xls_fabric_router__shared_in(app_shared_in),
        .xls_fabric_router__shared_in_vld(s_axis_tvalid),
        .xls_fabric_router__shared_in_rdy(s_axis_tready),
        .xls_fabric_router__endpoint_one_out(app_one_in),
        .xls_fabric_router__endpoint_one_out_vld(app_one_in_valid),
        .xls_fabric_router__endpoint_one_out_rdy(app_one_in_ready),
        .xls_fabric_router__endpoint_two_out(app_two_in),
        .xls_fabric_router__endpoint_two_out_vld(app_two_in_valid),
        .xls_fabric_router__endpoint_two_out_rdy(app_two_in_ready)
    );

    __xls_fabric_router__PairEgress_0_next app_egress (
        .clk(aclk),
        .reset(!aresetn),
        .xls_fabric_router__endpoint_one_in(app_one_out),
        .xls_fabric_router__endpoint_one_in_vld(app_one_out_valid),
        .xls_fabric_router__endpoint_one_in_rdy(app_one_out_ready),
        .xls_fabric_router__endpoint_two_in(app_two_out),
        .xls_fabric_router__endpoint_two_in_vld(app_two_out_valid),
        .xls_fabric_router__endpoint_two_in_rdy(app_two_out_ready),
        .xls_fabric_router__shared_out(app_shared_out),
        .xls_fabric_router__shared_out_vld(m_axis_tvalid),
        .xls_fabric_router__shared_out_rdy(m_axis_tready)
    );

    __xls_fabric_router__PairIngress_0_next debug_ingress (
        .clk(aclk),
        .reset(!aresetn),
        .xls_fabric_router__shared_in(debug_shared_in),
        .xls_fabric_router__shared_in_vld(s_dbg_tvalid),
        .xls_fabric_router__shared_in_rdy(s_dbg_tready),
        .xls_fabric_router__endpoint_one_out(debug_one_in),
        .xls_fabric_router__endpoint_one_out_vld(debug_one_in_valid),
        .xls_fabric_router__endpoint_one_out_rdy(debug_one_in_ready),
        .xls_fabric_router__endpoint_two_out(debug_two_in),
        .xls_fabric_router__endpoint_two_out_vld(debug_two_in_valid),
        .xls_fabric_router__endpoint_two_out_rdy(debug_two_in_ready)
    );

    __xls_fabric_router__PairEgress_0_next debug_egress (
        .clk(aclk),
        .reset(!aresetn),
        .xls_fabric_router__endpoint_one_in(debug_one_out),
        .xls_fabric_router__endpoint_one_in_vld(debug_one_out_valid),
        .xls_fabric_router__endpoint_one_in_rdy(debug_one_out_ready),
        .xls_fabric_router__endpoint_two_in(debug_two_out),
        .xls_fabric_router__endpoint_two_in_vld(debug_two_out_valid),
        .xls_fabric_router__endpoint_two_in_rdy(debug_two_out_ready),
        .xls_fabric_router__shared_out(debug_shared_out),
        .xls_fabric_router__shared_out_vld(m_dbg_tvalid),
        .xls_fabric_router__shared_out_rdy(m_dbg_tready)
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
