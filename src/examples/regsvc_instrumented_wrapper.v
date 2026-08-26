module axis_regsvc_instrumented_wrapper (
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
    axis_regsvc_xls_axis_wrapper application (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    xls_debug_monitor debug_monitor (
        .aclk(aclk),
        .aresetn(aresetn),
        .app_rx_tvalid(s_axis_tvalid),
        .app_rx_tready(s_axis_tready),
        .app_rx_tlast(s_axis_tlast),
        .app_tx_tvalid(m_axis_tvalid),
        .app_tx_tready(m_axis_tready),
        .app_tx_tlast(m_axis_tlast),
        .s_dbg_tdata(s_dbg_tdata),
        .s_dbg_tkeep(s_dbg_tkeep),
        .s_dbg_tvalid(s_dbg_tvalid),
        .s_dbg_tready(s_dbg_tready),
        .s_dbg_tlast(s_dbg_tlast),
        .m_dbg_tdata(m_dbg_tdata),
        .m_dbg_tkeep(m_dbg_tkeep),
        .m_dbg_tvalid(m_dbg_tvalid),
        .m_dbg_tready(m_dbg_tready),
        .m_dbg_tlast(m_dbg_tlast)
    );
endmodule
