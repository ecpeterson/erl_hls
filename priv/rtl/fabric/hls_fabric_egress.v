// Fair packet mux with one first-beat register. Each endpoint supplies an
// unrouted frame and the destination of its first beat; the source comes from
// ENDPOINTS. A grant survives source gaps and sink stalls through accepted
// TLAST. No other endpoint is accepted while the grant is held.
module hls_fabric_egress #(
    parameter integer PORTS = 2,
    parameter [16*PORTS-1:0] ENDPOINTS = {16'd2, 16'd1}
) (
    input wire clk, reset,
    input wire [32*PORTS-1:0] s_data,
    input wire [4*PORTS-1:0] s_keep,
    input wire [PORTS-1:0] s_last, s_valid,
    input wire [16*PORTS-1:0] s_destination,
    output wire [PORTS-1:0] s_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready
);
    localparam integer INDEX_BITS = PORTS > 1 ? $clog2(PORTS) : 1;
    localparam [1:0] IDLE = 0, ROUTE = 1, FIRST = 2, BODY = 3;
    reg [1:0] state;
    reg [INDEX_BITS-1:0] selected, next_port;
    reg [15:0] destination;
    reg [36:0] first;
    reg found;
    reg [INDEX_BITS-1:0] candidate;
    // Two fixed-index priority scans avoid a barrel selector for every
    // possible cursor offset. Prefer the lowest requester at/after next_port;
    // if none exists, wrap to the lowest requester overall.
    integer i;
    always @* begin
        found = 0;
        candidate = 0;
        for (i = PORTS - 1; i >= 0; i = i - 1) begin
            if (s_valid[i]) begin
                candidate = i;
                found = 1;
            end
        end
        for (i = PORTS - 1; i >= 0; i = i - 1) begin
            if (i >= next_port && s_valid[i]) candidate = i;
        end
    end
    genvar p, q;
    generate for (p = 0; p < PORTS; p = p + 1) begin: endpoint
        assign s_ready[p] = !reset &&
            ((state == IDLE && found && candidate == p) ||
             (state == BODY && selected == p && m_ready));
        for (q = 0; q < p; q = q + 1) begin: unique_id
            if (ENDPOINTS[16*p +: 16] == ENDPOINTS[16*q +: 16]) begin: invalid
                initial $fatal(1, "fabric endpoint IDs must be unique");
            end
        end
    end endgenerate
    generate if (PORTS < 1 || PORTS > 65536) begin: invalid_ports
        initial $fatal(1, "fabric PORTS must be in 1..65536");
    end endgenerate
    // First-beat capture and body forwarding are mutually exclusive. Share
    // their wide selector instead of muxing every endpoint's payload twice.
    wire [INDEX_BITS-1:0] input_port = state == IDLE ? candidate : selected;
    wire [36:0] input_beat = {s_last[input_port], s_keep[4*input_port +: 4],
                              s_data[32*input_port +: 32]};
    assign m_valid = !reset && (state == ROUTE || state == FIRST ||
                                (state == BODY && s_valid[selected]));
    assign m_data = state == ROUTE ? {ENDPOINTS[16*selected +: 16], destination} :
                    state == FIRST ? first[31:0] : input_beat[31:0];
    assign m_keep = state == ROUTE ? 4'hf :
                    state == FIRST ? first[35:32] : input_beat[35:32];
    assign m_last = state == FIRST ? first[36] : state == BODY && input_beat[36];
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            selected <= 0;
            next_port <= 0;
            destination <= 0;
            first <= 0;
        end else begin
            case (state)
                IDLE: if (found) begin
                    selected <= candidate;
                    destination <= s_destination[16*candidate +: 16];
                    first <= input_beat;
                    state <= ROUTE;
                end
                ROUTE: if (m_ready) state <= FIRST;
                FIRST, BODY: if (m_valid && m_ready) begin
                    if (m_last) begin
                        next_port <= selected == PORTS - 1 ? 0 : selected + 1'b1;
                        state <= IDLE;
                    end else state <= BODY;
                end
            endcase
        end
    end
endmodule
