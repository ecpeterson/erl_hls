module xls_debug_monitor (
    input  wire        aclk,
    input  wire        aresetn,

    // Passive taps on the application stream. These signals never feed back
    // into the application ready/valid path.
    input  wire        app_rx_tvalid,
    input  wire        app_rx_tready,
    input  wire        app_rx_tlast,
    input  wire        app_tx_tvalid,
    input  wire        app_tx_tready,
    input  wire        app_tx_tlast,

    input  wire [31:0] s_dbg_tdata,
    input  wire [3:0]  s_dbg_tkeep,
    input  wire        s_dbg_tvalid,
    output wire        s_dbg_tready,
    input  wire        s_dbg_tlast,

    output reg  [31:0] m_dbg_tdata,
    output wire [3:0]  m_dbg_tkeep,
    output reg         m_dbg_tvalid,
    input  wire        m_dbg_tready,
    output reg         m_dbg_tlast
);
    localparam [7:0] DEBUG_GET_COUNTERS = 8'hd0;
    localparam [7:0] DEBUG_COUNTERS     = 8'hd1;
    localparam [7:0] DEBUG_ERROR        = 8'hdf;
    localparam [7:0] DEBUG_VERSION      = 8'd1;
    localparam [7:0] COUNTER_WORDS      = 8'd8;

    reg [31:0] cycles;
    reg [31:0] app_rx_beats;
    reg [31:0] app_rx_frames;
    reg [31:0] app_rx_stall_cycles;
    reg [31:0] app_tx_beats;
    reg [31:0] app_tx_frames;
    reg [31:0] app_tx_stall_cycles;

    reg [31:0] snap_cycles;
    reg [31:0] snap_app_rx_beats;
    reg [31:0] snap_app_rx_frames;
    reg [31:0] snap_app_rx_stall_cycles;
    reg [31:0] snap_app_tx_beats;
    reg [31:0] snap_app_tx_frames;
    reg [31:0] snap_app_tx_stall_cycles;

    reg [7:0] response_words;
    reg [7:0] response_index;
    reg       error_response;

    wire debug_request = s_dbg_tvalid && s_dbg_tready;
    wire valid_counter_request =
        s_dbg_tkeep == 4'hf &&
        s_dbg_tlast &&
        s_dbg_tdata[31:24] == DEBUG_GET_COUNTERS &&
        s_dbg_tdata[7:0] == 8'd0;

    assign s_dbg_tready = !m_dbg_tvalid;
    assign m_dbg_tkeep = 4'hf;

    function [31:0] payload_word;
        input [7:0] index;
        begin
            if (error_response) begin
                payload_word = 32'd1;
            end else begin
                case (index)
                    8'd1: payload_word = {24'd0, DEBUG_VERSION};
                    8'd2: payload_word = snap_cycles;
                    8'd3: payload_word = snap_app_rx_beats;
                    8'd4: payload_word = snap_app_rx_frames;
                    8'd5: payload_word = snap_app_rx_stall_cycles;
                    8'd6: payload_word = snap_app_tx_beats;
                    8'd7: payload_word = snap_app_tx_frames;
                    8'd8: payload_word = snap_app_tx_stall_cycles;
                    default: payload_word = 32'd0;
                endcase
            end
        end
    endfunction

    always @(posedge aclk) begin
        if (!aresetn) begin
            cycles <= 32'd0;
            app_rx_beats <= 32'd0;
            app_rx_frames <= 32'd0;
            app_rx_stall_cycles <= 32'd0;
            app_tx_beats <= 32'd0;
            app_tx_frames <= 32'd0;
            app_tx_stall_cycles <= 32'd0;

            snap_cycles <= 32'd0;
            snap_app_rx_beats <= 32'd0;
            snap_app_rx_frames <= 32'd0;
            snap_app_rx_stall_cycles <= 32'd0;
            snap_app_tx_beats <= 32'd0;
            snap_app_tx_frames <= 32'd0;
            snap_app_tx_stall_cycles <= 32'd0;

            response_words <= 8'd0;
            response_index <= 8'd0;
            error_response <= 1'b0;
            m_dbg_tdata <= 32'd0;
            m_dbg_tvalid <= 1'b0;
            m_dbg_tlast <= 1'b0;
        end else begin
            cycles <= cycles + 32'd1;

            if (app_rx_tvalid && app_rx_tready) begin
                app_rx_beats <= app_rx_beats + 32'd1;
                if (app_rx_tlast)
                    app_rx_frames <= app_rx_frames + 32'd1;
            end
            if (app_rx_tvalid && !app_rx_tready)
                app_rx_stall_cycles <= app_rx_stall_cycles + 32'd1;

            if (app_tx_tvalid && app_tx_tready) begin
                app_tx_beats <= app_tx_beats + 32'd1;
                if (app_tx_tlast)
                    app_tx_frames <= app_tx_frames + 32'd1;
            end
            if (app_tx_tvalid && !app_tx_tready)
                app_tx_stall_cycles <= app_tx_stall_cycles + 32'd1;

            if (debug_request) begin
                snap_cycles <= cycles;
                snap_app_rx_beats <= app_rx_beats;
                snap_app_rx_frames <= app_rx_frames;
                snap_app_rx_stall_cycles <= app_rx_stall_cycles;
                snap_app_tx_beats <= app_tx_beats;
                snap_app_tx_frames <= app_tx_frames;
                snap_app_tx_stall_cycles <= app_tx_stall_cycles;

                error_response <= !valid_counter_request;
                response_words <= valid_counter_request ? COUNTER_WORDS : 8'd1;
                response_index <= 8'd0;
                m_dbg_tdata <= {
                    valid_counter_request ? DEBUG_COUNTERS : DEBUG_ERROR,
                    8'd0,
                    s_dbg_tdata[15:8],
                    valid_counter_request ? COUNTER_WORDS : 8'd1
                };
                m_dbg_tvalid <= 1'b1;
                m_dbg_tlast <= 1'b0;
            end else if (m_dbg_tvalid && m_dbg_tready) begin
                if (response_index == response_words) begin
                    response_index <= 8'd0;
                    m_dbg_tvalid <= 1'b0;
                    m_dbg_tlast <= 1'b0;
                end else begin
                    response_index <= response_index + 8'd1;
                    m_dbg_tdata <= payload_word(response_index + 8'd1);
                    m_dbg_tlast <= response_index + 8'd1 == response_words;
                end
            end
        end
    end
endmodule
