// Debug top level: the base XLS-to-AXIS application adapter plus the passive
// tap and independently scheduled XLS observer and debug server.
module axis_regsvc_debug_top (
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
    // These mirror the logical DSLX types. SNAPSHOT_BITS is the Verilog-side
    // equivalent of bit_count<MonitorState>(); changing TRACE_DEPTH updates
    // the trace array, its count width, and the flattened snapshot width. The
    // DSLX TRACE_DEPTH must change with this value before regenerating RTL.
    localparam integer APPLICATION_STATE_BITS = 512;
    localparam integer TRACE_DEPTH = 8;
    localparam integer TRACE_EVENT_BITS = 64;
    localparam integer TRACE_COUNT_BITS = $clog2(TRACE_DEPTH + 1);
    localparam integer STREAM_OBSERVATION_BITS = 32 + 3;
    localparam integer OBSERVATION_BITS =
        APPLICATION_STATE_BITS + 32 + 2 * STREAM_OBSERVATION_BITS + 1;
    localparam integer COUNTER_BITS = 7 * 32;
    localparam integer TRACE_BUFFER_BITS =
        TRACE_DEPTH * TRACE_EVENT_BITS + TRACE_COUNT_BITS + 32;
    localparam integer SNAPSHOT_BITS =
        COUNTER_BITS + 32 + APPLICATION_STATE_BITS + 2 + TRACE_BUFFER_BITS;
    localparam integer DEBUG_BEAT_BITS = 4 + 1 + 32;

    wire [APPLICATION_STATE_BITS-1:0] app_state_data;
    wire         app_state_valid;
    wire [OBSERVATION_BITS-1:0] debug_observation_data;
    wire         debug_observation_valid;
    wire         debug_observation_ready;
    wire [DEBUG_BEAT_BITS-1:0] debug_request = {
        s_dbg_tkeep,
        s_dbg_tlast,
        s_dbg_tdata
    };
    wire [DEBUG_BEAT_BITS-1:0] debug_response;
    wire [7:0]   snapshot_request;
    wire          snapshot_request_valid;
    wire          snapshot_request_ready;
    wire [SNAPSHOT_BITS-1:0] snapshot;
    wire          snapshot_valid;
    wire          snapshot_ready;

    axis_regsvc_core_adapter application (
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
        .m_axis_tlast(m_axis_tlast),
        .state_data(app_state_data),
        .state_valid(app_state_valid)
    );

    xls_debug_tap #(
        .STATE_BITS(APPLICATION_STATE_BITS)
    ) debug_tap (
        .aclk(aclk),
        .aresetn(aresetn),
        .app_rx_tvalid(s_axis_tvalid),
        .app_rx_tready(s_axis_tready),
        .app_rx_tlast(s_axis_tlast),
        .app_rx_tdata(s_axis_tdata),
        .app_tx_tvalid(m_axis_tvalid),
        .app_tx_tready(m_axis_tready),
        .app_tx_tlast(m_axis_tlast),
        .app_tx_tdata(m_axis_tdata),
        .app_state_data(app_state_data),
        .app_state_valid(app_state_valid),
        .observation_data(debug_observation_data),
        .observation_valid(debug_observation_valid),
        .observation_ready(debug_observation_ready)
    );

    __xls_debug_monitor__Observer_0_next debug_observer (
        .clk(aclk),
        .reset(!aresetn),
        .xls_debug_monitor__observation_in(debug_observation_data),
        .xls_debug_monitor__observation_in_vld(debug_observation_valid),
        .xls_debug_monitor__observation_in_rdy(debug_observation_ready),
        .xls_debug_monitor__snapshot_request_in(snapshot_request),
        .xls_debug_monitor__snapshot_request_in_vld(snapshot_request_valid),
        .xls_debug_monitor__snapshot_request_in_rdy(snapshot_request_ready),
        .xls_debug_monitor__snapshot_out(snapshot),
        .xls_debug_monitor__snapshot_out_vld(snapshot_valid),
        .xls_debug_monitor__snapshot_out_rdy(snapshot_ready)
    );

    __xls_debug_monitor__DebugServer_0_next debug_server (
        .clk(aclk),
        .reset(!aresetn),
        .xls_debug_monitor__request_in(debug_request),
        .xls_debug_monitor__request_in_vld(s_dbg_tvalid),
        .xls_debug_monitor__request_in_rdy(s_dbg_tready),
        .xls_debug_monitor__response_out(debug_response),
        .xls_debug_monitor__response_out_vld(m_dbg_tvalid),
        .xls_debug_monitor__response_out_rdy(m_dbg_tready),
        .xls_debug_monitor__snapshot_request_out(snapshot_request),
        .xls_debug_monitor__snapshot_request_out_vld(snapshot_request_valid),
        .xls_debug_monitor__snapshot_request_out_rdy(snapshot_request_ready),
        .xls_debug_monitor__snapshot_in(snapshot),
        .xls_debug_monitor__snapshot_in_vld(snapshot_valid),
        .xls_debug_monitor__snapshot_in_rdy(snapshot_ready)
    );

    assign m_dbg_tdata = debug_response[31:0];
    assign m_dbg_tlast = debug_response[32];
    assign m_dbg_tkeep = debug_response[36:33];
endmodule
