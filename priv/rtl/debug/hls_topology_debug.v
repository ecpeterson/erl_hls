// Passive current-state queries. Only the selected reply is retained; no trace
// RAM or duplicate FIFO counters. The observation is taken before this edge's
// application state updates and held stable for arbitrarily slow readout.
module hls_topology_debug #(
    parameter integer RESOURCES = 1,
    parameter integer CHANNELS = 1,
    parameter integer ACTORS = 0,
    // Byte zero of the SHA-256 manifest fingerprint occupies bits [7:0].
    parameter [255:0] FINGERPRINT = 0
) (
    input wire clk, reset,
    input wire [RESOURCES*32-1:0] probe_values,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    output reg [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready
);
    localparam [7:0] INFO = 8'h10, QUERY = 8'h11, ERROR = 8'hff;
    reg sending;
    reg [7:0] reply_tag, reply_txid, reply_index;
    reg [127:0] observation;
    reg [63:0] cycle;
    wire [31:0] request, resource_id;
    wire malformed, request_valid;
    wire [7:0] operation = request[31:24];
    wire [7:0] words = request[7:0];
    wire [7:0] reply_count = reply_tag == (INFO | 8'h80) ? 13 :
        reply_tag == (QUERY | 8'h80) ? 4 : 1;

    hls_debug_frame_rx #(.MAX_WORDS(1)) receiver (
        .clk(clk), .reset(reset),
        .s_data(s_data), .s_keep(s_keep), .s_last(s_last),
        .s_valid(s_valid), .s_ready(s_ready),
        .header(request), .payload(resource_id), .malformed(malformed),
        .valid(request_valid), .ready(!sending)
    );
    assign m_valid = sending;
    assign m_keep = 4'hf;
    assign m_last = reply_index == reply_count;
    always @* begin
        m_data = 0;
        if (reply_index == 0)
            m_data = {reply_tag, 8'd0, reply_txid, reply_count};
        else if (reply_tag == (INFO | 8'h80)) begin
            case (reply_index)
                1: m_data = 2; // protocol/manifest schema
                2: m_data = RESOURCES;
                3: m_data = CHANNELS;
                4: m_data = RESOURCES - CHANNELS - ACTORS;
                5: m_data = ACTORS;
                default: m_data = FINGERPRINT[(reply_index-6)*32 +: 32];
            endcase
        end else m_data = observation[(reply_index-1)*32 +: 32];
    end

    always @(posedge clk) begin
        if (reset) begin
            sending <= 0;
            reply_tag <= 0;
            reply_txid <= 0;
            reply_index <= 0;
            observation <= 0;
            cycle <= 0;
        end else begin
            cycle <= cycle + 1'b1;
            if (!sending && request_valid) begin
                sending <= 1;
                reply_tag <= operation | 8'h80;
                reply_txid <= request[15:8];
                reply_index <= 0;
                observation <= 0;
                if (!malformed && operation == INFO && words == 0) begin
                    // INFO is immutable and read directly from parameters.
                end else if (!malformed && operation == QUERY && words == 1 && resource_id < RESOURCES) begin
                    observation <= {probe_values[resource_id*32 +: 32], cycle, resource_id};
                end else begin
                    reply_tag <= ERROR;
                    observation <= !malformed && operation == QUERY && words == 1 ? 2 : 1;
                end
            end else if (sending && m_ready) begin
                if (m_last) sending <= 0;
                else reply_index <= reply_index + 1'b1;
            end
        end
    end
endmodule
