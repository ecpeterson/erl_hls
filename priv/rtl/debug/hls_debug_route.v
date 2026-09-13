// Routed debug services share one request/reply transaction at a time. The
// destination and source remain owned until the reply's accepted TLAST, so
// even a long stalled trace reply cannot mix with a topology query. A blocked
// debug reader delays all services; passive application sampling stays live.
// Service port zero uses the least-significant 16-bit element of ENDPOINTS.
module hls_debug_route #(
    parameter PORTS = 1,
    parameter [16*PORTS-1:0] ENDPOINTS = 2
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
    output wire request_last,
    output wire [PORTS-1:0] request_valid,
    input wire [PORTS-1:0] request_ready,
    input wire [32*PORTS-1:0] response_data,
    input wire [4*PORTS-1:0] response_keep,
    input wire [PORTS-1:0] response_last, response_valid,
    output wire [PORTS-1:0] response_ready
);
    localparam [2:0] ADDRESS = 0, REQUEST = 1, REPLY_ROUTE = 2, REPLY = 3, DROP = 4;
    reg [2:0] state;
    reg [15:0] source;
    localparam INDEX_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1;
    reg [INDEX_WIDTH-1:0] selected;
    reg [INDEX_WIDTH-1:0] destination;
    reg found;
    integer i;
    always @* begin
        destination = 0;
        found = 0;
        for (i = 0; i < PORTS; i = i + 1) begin
            if (s_data[15:0] == ENDPOINTS[16*i +: 16]) begin
                destination = i;
                found = 1;
            end
        end
    end
    assign s_ready = state == ADDRESS || state == DROP || (state == REQUEST && request_ready[selected]);
    assign request_data = s_data;
    assign request_keep = s_keep;
    assign request_last = s_last;
    genvar port;
    generate for (port = 0; port < PORTS; port = port + 1) begin: service
        assign request_valid[port] = state == REQUEST && selected == port && s_valid;
        assign response_ready[port] = state == REPLY && selected == port && m_ready;
    end endgenerate
    assign m_valid = (state == REPLY_ROUTE || state == REPLY) && response_valid[selected];
    assign m_data = state == REPLY_ROUTE ? {ENDPOINTS[16*selected +: 16], source} : response_data[32*selected +: 32];
    assign m_keep = state == REPLY_ROUTE ? 4'hf : response_keep[4*selected +: 4];
    assign m_last = state == REPLY && response_last[selected];
    always @(posedge clk) begin
        if (reset) begin
            state <= ADDRESS;
            source <= 0;
            selected <= 0;
        end else begin
            case (state)
                ADDRESS: if (s_valid) begin
                    source <= s_data[31:16];
                    selected <= destination;
                    if (s_last) state <= ADDRESS;
                    else if (s_keep != 15 || !found) state <= DROP;
                    else state <= REQUEST;
                end
                DROP: if (s_valid && s_last) state <= ADDRESS;
                REQUEST: if (s_valid && request_ready[selected] && s_last) state <= REPLY_ROUTE;
                REPLY_ROUTE: if (response_valid[selected] && m_ready) state <= REPLY;
                REPLY: if (response_valid[selected] && m_ready && response_last[selected]) state <= ADDRESS;
                default: state <= ADDRESS;
            endcase
        end
    end
endmodule
