// Passive application-boundary monitor with an endpoint-local debug stream.
// Application ready/valid does not depend on any signal produced here.
module hls_debug_monitor (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] app_rx_tdata,
    input  wire        app_rx_tvalid,
    input  wire        app_rx_tready,
    input  wire        app_rx_tlast,

    input  wire [31:0] app_tx_tdata,
    input  wire        app_tx_tvalid,
    input  wire        app_tx_tready,
    input  wire        app_tx_tlast,

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
    localparam integer TRACE_DEPTH = 64;
    localparam integer TRACE_EVENT_BITS = 64;
    localparam integer TRACE_COUNT_BITS = $clog2(TRACE_DEPTH + 1);
    localparam integer TRACE_ROW_COUNT = TRACE_DEPTH / 2;
    localparam integer TRACE_ROW_BITS = $clog2(TRACE_ROW_COUNT);
    localparam integer TRACE_ADDRESS_BITS = TRACE_ROW_BITS + 1;
    localparam integer TRACE_ROW_DATA_BITS = 2 * TRACE_EVENT_BITS;
    localparam integer TRACE_READ_BITS = TRACE_ADDRESS_BITS + 1;
    localparam integer TRACE_WRITE_BITS =
        TRACE_ADDRESS_BITS + TRACE_ROW_DATA_BITS;
    localparam integer STREAM_OBSERVATION_BITS = 32 + 3;
    localparam integer OBSERVATION_BITS =
        32 + 2 * STREAM_OBSERVATION_BITS;
    localparam integer COUNTER_BITS = 7 * 32;
    localparam integer TRACE_BUFFER_BITS =
        1 + TRACE_COUNT_BITS + 32 + 1 + TRACE_EVENT_BITS;
    localparam integer SNAPSHOT_BITS =
        COUNTER_BITS + 32 + 2 + TRACE_BUFFER_BITS;
    localparam integer DEBUG_BEAT_BITS = 4 + 1 + 32;

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
    wire         snapshot_request_valid;
    wire         snapshot_request_ready;
    wire [SNAPSHOT_BITS-1:0] snapshot;
    wire         snapshot_valid;
    wire         snapshot_ready;
    wire [TRACE_WRITE_BITS-1:0] trace_write;
    wire         trace_write_valid;
    wire         trace_write_ready;
    wire [TRACE_READ_BITS-1:0] trace_read_request;
    wire         trace_read_request_valid;
    wire         trace_read_request_ready;
    wire [TRACE_EVENT_BITS-1:0] trace_read_response;
    wire         trace_read_response_valid;
    wire         trace_read_response_ready;

    hls_debug_tap debug_tap (
        .aclk(aclk),
        .aresetn(aresetn),
        .app_rx_tvalid(app_rx_tvalid),
        .app_rx_tready(app_rx_tready),
        .app_rx_tlast(app_rx_tlast),
        .app_rx_tdata(app_rx_tdata),
        .app_tx_tvalid(app_tx_tvalid),
        .app_tx_tready(app_tx_tready),
        .app_tx_tlast(app_tx_tlast),
        .app_tx_tdata(app_tx_tdata),
        .observation_data(debug_observation_data),
        .observation_valid(debug_observation_valid),
        .observation_ready(debug_observation_ready)
    );

    __hls_debug_observer__Observer_0_next debug_observer (
        .clk(aclk),
        .reset(!aresetn),
        .hls_debug_observer__observation_in(debug_observation_data),
        .hls_debug_observer__observation_in_vld(debug_observation_valid),
        .hls_debug_observer__observation_in_rdy(debug_observation_ready),
        .hls_debug_observer__snapshot_request_in(snapshot_request),
        .hls_debug_observer__snapshot_request_in_vld(snapshot_request_valid),
        .hls_debug_observer__snapshot_request_in_rdy(snapshot_request_ready),
        .hls_debug_observer__snapshot_out(snapshot),
        .hls_debug_observer__snapshot_out_vld(snapshot_valid),
        .hls_debug_observer__snapshot_out_rdy(snapshot_ready),
        .hls_debug_observer__trace_write_out(trace_write),
        .hls_debug_observer__trace_write_out_vld(trace_write_valid),
        .hls_debug_observer__trace_write_out_rdy(trace_write_ready)
    );

    hls_trace_store #(
        .ADDR_WIDTH(TRACE_ADDRESS_BITS),
        .ROW_WIDTH(TRACE_ROW_DATA_BITS),
        .EVENT_WIDTH(TRACE_EVENT_BITS)
    ) trace_store (
        .clk(aclk),
        .reset(!aresetn),
        .write_request(trace_write),
        .write_request_valid(trace_write_valid),
        .write_request_ready(trace_write_ready),
        .read_request(trace_read_request),
        .read_request_valid(trace_read_request_valid),
        .read_request_ready(trace_read_request_ready),
        .read_response(trace_read_response),
        .read_response_valid(trace_read_response_valid),
        .read_response_ready(trace_read_response_ready)
    );

    __hls_debug_server__DebugServer_0_next debug_server (
        .clk(aclk),
        .reset(!aresetn),
        .hls_debug_server__request_in(debug_request),
        .hls_debug_server__request_in_vld(s_dbg_tvalid),
        .hls_debug_server__request_in_rdy(s_dbg_tready),
        .hls_debug_server__response_out(debug_response),
        .hls_debug_server__response_out_vld(m_dbg_tvalid),
        .hls_debug_server__response_out_rdy(m_dbg_tready),
        .hls_debug_server__snapshot_request_out(snapshot_request),
        .hls_debug_server__snapshot_request_out_vld(snapshot_request_valid),
        .hls_debug_server__snapshot_request_out_rdy(snapshot_request_ready),
        .hls_debug_server__snapshot_in(snapshot),
        .hls_debug_server__snapshot_in_vld(snapshot_valid),
        .hls_debug_server__snapshot_in_rdy(snapshot_ready),
        .hls_debug_server__trace_read_request_out(trace_read_request),
        .hls_debug_server__trace_read_request_out_vld(
            trace_read_request_valid
        ),
        .hls_debug_server__trace_read_request_out_rdy(
            trace_read_request_ready
        ),
        .hls_debug_server__trace_read_response_in(trace_read_response),
        .hls_debug_server__trace_read_response_in_vld(
            trace_read_response_valid
        ),
        .hls_debug_server__trace_read_response_in_rdy(
            trace_read_response_ready
        )
    );

    assign m_dbg_tdata = debug_response[31:0];
    assign m_dbg_tlast = debug_response[32];
    assign m_dbg_tkeep = debug_response[36:33];
endmodule
