// Base adapter from the generated XLS proc ports to AXI4-Stream. It contains
// no management endpoint; axis_regsvc_debug_top composes this
// adapter with the independently serviced debug monitor.
module axis_regsvc_core_adapter (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ACLK, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET ARESETN" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    input wire aclk,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETN, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    input wire aresetn,

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

    // Always-ready observation channel carrying each newly committed service
    // state. This remains internal to the instrumented wrapper.
    output wire [511:0] state_data,
    output wire         state_valid
);

    wire [32:0] xls_in;
    wire [32:0] xls_out;

    assign xls_in = {s_axis_tlast, s_axis_tdata};

    assign m_axis_tlast  = xls_out[32];
    assign m_axis_tdata  = xls_out[31:0];
    assign m_axis_tkeep  = 4'hF;

    __regsvc__Top_0_next xls_core (
        .clk(aclk),
        .reset(~aresetn),

        .regsvc__ext_recv(xls_in),
        .regsvc__ext_recv_vld(s_axis_tvalid),
        .regsvc__ext_recv_rdy(s_axis_tready),

        .regsvc__ext_send(xls_out),
        .regsvc__ext_send_vld(m_axis_tvalid),
        .regsvc__ext_send_rdy(m_axis_tready),

        .regsvc__ext_state(state_data),
        .regsvc__ext_state_vld(state_valid),
        .regsvc__ext_state_rdy(1'b1)
    );

endmodule
