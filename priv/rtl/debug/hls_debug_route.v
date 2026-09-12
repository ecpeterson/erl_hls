// One routed debug endpoint. Requests/replies retain whole-frame ownership,
// including the source address, until the reply's accepted TLAST.
module hls_debug_route #(
    parameter [15:0] ENDPOINT = 2
) (
    input wire clk, reset,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready,
    output wire [31:0] request_data,
    output wire [3:0] request_keep,
    output wire request_last, request_valid,
    input wire request_ready,
    input wire [31:0] response_data,
    input wire [3:0] response_keep,
    input wire response_last, response_valid,
    output wire response_ready
);
    localparam [2:0] ADDRESS = 0, REQUEST = 1, REPLY_ROUTE = 2, REPLY = 3, DROP = 4;
    reg [2:0] state;
    reg [15:0] source;
    assign s_ready = state == ADDRESS || state == DROP || (state == REQUEST && request_ready);
    assign request_data = s_data;
    assign request_keep = s_keep;
    assign request_last = s_last;
    assign request_valid = state == REQUEST && s_valid;
    assign response_ready = state == REPLY && m_ready;
    assign m_valid = (state == REPLY_ROUTE || state == REPLY) && response_valid;
    assign m_data = state == REPLY_ROUTE ? {ENDPOINT, source} : response_data;
    assign m_keep = state == REPLY_ROUTE ? 4'hf : response_keep;
    assign m_last = state == REPLY && response_last;
    always @(posedge clk) begin
        if (reset) begin
            state <= ADDRESS;
            source <= 0;
        end else begin
            case (state)
                ADDRESS: if (s_valid) begin
                    source <= s_data[31:16];
                    if (s_last) state <= ADDRESS;
                    else if (s_keep != 15 || s_data[15:0] != ENDPOINT) state <= DROP;
                    else state <= REQUEST;
                end
                DROP: if (s_valid && s_last) state <= ADDRESS;
                REQUEST: if (s_valid && request_ready && s_last) state <= REPLY_ROUTE;
                REPLY_ROUTE: if (response_valid && m_ready) state <= REPLY;
                REPLY: if (response_valid && m_ready && response_last) state <= ADDRESS;
                default: state <= ADDRESS;
            endcase
        end
    end
endmodule
