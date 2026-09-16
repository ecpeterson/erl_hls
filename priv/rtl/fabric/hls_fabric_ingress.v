// Removes one {source, destination} routing word and holds the destination
// through the packet's accepted TLAST. Port zero is ENDPOINTS[15:0]. Payload
// TKEEP is preserved: a word-only consumer must enforce its own word contract.
module hls_fabric_ingress #(
    parameter integer PORTS = 2,
    parameter [16*PORTS-1:0] ENDPOINTS = {16'd2, 16'd1}
) (
    input wire clk, reset,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_last,
    output wire [15:0] m_source,
    output wire [PORTS-1:0] m_valid,
    input wire [PORTS-1:0] m_ready,
    // Accepted rejected route: 1 = partial word, 2 = unknown destination,
    // 3 = route-only packet. Nonzero for that handshake only.
    output wire [1:0] route_error
);
    localparam integer INDEX_BITS = PORTS > 1 ? $clog2(PORTS) : 1;
    localparam [1:0] ADDRESS = 0, FORWARD = 1, DROP = 2;
    reg [1:0] state;
    reg [INDEX_BITS-1:0] selected;
    reg [15:0] source;
    reg found;
    reg [INDEX_BITS-1:0] destination;
    integer i;
    always @* begin
        found = 0;
        destination = 0;
        for (i = 0; i < PORTS; i = i + 1) begin
            if (s_data[15:0] == ENDPOINTS[16*i +: 16]) begin
                found = 1;
                destination = i;
            end
        end
    end
    assign s_ready = !reset && (state != FORWARD || m_ready[selected]);
    assign m_data = s_data;
    assign m_keep = s_keep;
    assign m_last = s_last;
    assign m_source = source;
    genvar p, q;
    generate for (p = 0; p < PORTS; p = p + 1) begin: endpoint
        assign m_valid[p] = !reset && state == FORWARD && selected == p && s_valid;
        for (q = 0; q < p; q = q + 1) begin: unique_id
            if (ENDPOINTS[16*p +: 16] == ENDPOINTS[16*q +: 16]) begin: invalid
                initial $fatal(1, "fabric endpoint IDs must be unique");
            end
        end
    end endgenerate
    generate if (PORTS < 1 || PORTS > 65536) begin: invalid_ports
        initial $fatal(1, "fabric PORTS must be in 1..65536");
    end endgenerate
    assign route_error = state == ADDRESS && s_valid && s_ready ?
        (s_keep != 4'hf ? 2'd1 : s_last ? 2'd3 : !found ? 2'd2 : 2'd0) : 2'd0;
    always @(posedge clk) begin
        if (reset) begin
            state <= ADDRESS;
            selected <= 0;
            source <= 0;
        end else if (s_valid && s_ready) begin
            case (state)
                ADDRESS: begin
                    selected <= destination;
                    source <= s_data[31:16];
                    state <= s_last ? ADDRESS : (s_keep == 4'hf && found ? FORWARD : DROP);
                end
                FORWARD, DROP: if (s_last) state <= ADDRESS;
                default: state <= ADDRESS;
            endcase
        end
    end
endmodule
