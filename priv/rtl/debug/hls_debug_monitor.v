// Passive application-boundary monitor with an endpoint-local debug stream.
// Application ready/valid does not depend on any signal produced here.
module hls_debug_monitor #(parameter integer ROUTED = 0) (
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
    wire [103:0] debug_observation_data;
    wire debug_observation_valid, debug_observation_ready;

    hls_debug_tap #(.ROUTED(ROUTED)) debug_tap (
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

    hls_debug_capture capture (
        .aclk(aclk),
        .aresetn(aresetn),
        .observation_data(debug_observation_data),
        .observation_valid(debug_observation_valid),
        .observation_ready(debug_observation_ready),
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

// Protocol/trace collector for a passive observation provider. The provider
// samples independently of application progress; rejected samples are accounted
// for in its cumulative tap_drops field. Debug requests use the public stream.
module hls_debug_capture (
    input wire aclk,
    input wire aresetn,
    input wire [103:0] observation_data,
    input wire observation_valid,
    output wire observation_ready,
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
    localparam integer TRACE_EVENT_BITS = 96;
    localparam integer TRACE_COUNT_BITS = $clog2(TRACE_DEPTH + 1);
    localparam integer TRACE_ROW_COUNT = TRACE_DEPTH / 2;
    localparam integer TRACE_ROW_BITS = $clog2(TRACE_ROW_COUNT);
    localparam integer TRACE_ADDRESS_BITS = TRACE_ROW_BITS + 1;
    localparam integer TRACE_ROW_DATA_BITS = 2 * TRACE_EVENT_BITS;
    localparam integer TRACE_READ_BITS = TRACE_ADDRESS_BITS + 1;
    localparam integer TRACE_WRITE_BITS =
        TRACE_ADDRESS_BITS + TRACE_ROW_DATA_BITS;
    localparam integer COUNTER_BITS = 7 * 32;
    localparam integer TRACE_BUFFER_BITS =
        1 + TRACE_COUNT_BITS + 32 + 1 + TRACE_EVENT_BITS;
    localparam integer SNAPSHOT_BITS =
        COUNTER_BITS + 32 + 2 * (2 + 32 + 1) + TRACE_BUFFER_BITS;
    localparam integer DEBUG_BEAT_BITS = 4 + 1 + 32;

    wire [DEBUG_BEAT_BITS-1:0] debug_request = {
        s_dbg_tkeep,
        s_dbg_tlast,
        s_dbg_tdata
    };
    wire [DEBUG_BEAT_BITS-1:0] debug_response;
    wire [7:0] server_snapshot_request;
    wire server_snapshot_request_valid;
    wire server_snapshot_request_ready;
    reg [7:0] snapshot_request;
    reg snapshot_request_valid;
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

    // Decouple the separately scheduled procs. Observer may consume a request
    // in the same stage that sends its snapshot, while Server consumes that
    // snapshot in a later stage than its request send. An unbuffered connection
    // can then deadlock. This one-entry request register breaks that dependency.
    assign server_snapshot_request_ready = !snapshot_request_valid;
    always @(posedge aclk) begin
        if (!aresetn) begin
            snapshot_request <= 0;
            snapshot_request_valid <= 0;
        end else if (server_snapshot_request_ready) begin
            snapshot_request_valid <= server_snapshot_request_valid;
            if (server_snapshot_request_valid)
                snapshot_request <= server_snapshot_request;
        end else if (snapshot_request_ready) begin
            snapshot_request_valid <= 0;
        end
    end

    __hls_debug_observer__Observer_0_next debug_observer (
        .clk(aclk),
        .reset(!aresetn),
        ._observation_in(observation_data),
        ._observation_in_vld(observation_valid),
        ._observation_in_rdy(observation_ready),
        ._snapshot_request_in(snapshot_request),
        ._snapshot_request_in_vld(snapshot_request_valid),
        ._snapshot_request_in_rdy(snapshot_request_ready),
        ._snapshot_out(snapshot),
        ._snapshot_out_vld(snapshot_valid),
        ._snapshot_out_rdy(snapshot_ready),
        ._trace_write_out(trace_write),
        ._trace_write_out_vld(trace_write_valid),
        ._trace_write_out_rdy(trace_write_ready)
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
        ._request_in(debug_request),
        ._request_in_vld(s_dbg_tvalid),
        ._request_in_rdy(s_dbg_tready),
        ._response_out(debug_response),
        ._response_out_vld(m_dbg_tvalid),
        ._response_out_rdy(m_dbg_tready),
        ._snapshot_request_out(server_snapshot_request),
        ._snapshot_request_out_vld(server_snapshot_request_valid),
        ._snapshot_request_out_rdy(server_snapshot_request_ready),
        ._snapshot_in(snapshot),
        ._snapshot_in_vld(snapshot_valid),
        ._snapshot_in_rdy(snapshot_ready),
        ._trace_read_request_out(trace_read_request),
        ._trace_read_request_out_vld(
            trace_read_request_valid
        ),
        ._trace_read_request_out_rdy(
            trace_read_request_ready
        ),
        ._trace_read_response_in(trace_read_response),
        ._trace_read_response_in_vld(
            trace_read_response_valid
        ),
        ._trace_read_response_in_rdy(
            trace_read_response_ready
        )
    );

    assign m_dbg_tdata = debug_response[31:0];
    assign m_dbg_tlast = debug_response[32];
    assign m_dbg_tkeep = debug_response[36:33];
endmodule
