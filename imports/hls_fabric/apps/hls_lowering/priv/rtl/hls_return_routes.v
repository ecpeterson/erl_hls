// Request context for a service whose frames carry an 8-bit TXID without a return route.
// The requester owns {source, TXID}; the service sees a bounded private slot.
// Replies restore the original identity, even after the host session retires.
// Sources must present complete valid frames, and the service must not produce
// a reply before the request header has been accepted on a clock edge.
module hls_return_routes #(
    parameter integer SLOTS = 16,
    parameter integer CAST_TXID = 255
) (
    input wire clk, reset,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    input wire [15:0] s_source,
    output wire [31:0] request_data,
    output wire [3:0] request_keep,
    output wire request_last, request_valid,
    input wire request_ready,
    input wire [31:0] reply_data,
    input wire [3:0] reply_keep,
    input wire reply_last, reply_valid,
    output wire reply_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready,
    output wire [15:0] m_destination,
    output reg [SLOTS-1:0] context_busy,
    output reg dropped_reply
);
    localparam integer INDEX_BITS = SLOTS <= 1 ? 1 : $clog2(SLOTS);
    reg [15:0] sources [0:SLOTS-1];
    reg [7:0] transactions [0:SLOTS-1];
    reg in_payload, out_payload, dropping;
    reg [INDEX_BITS-1:0] response_slot;
    reg [15:0] response_destination;
    reg found;
    reg [INDEX_BITS-1:0] free_slot;
    reg offer_held;
    reg [INDEX_BITS-1:0] offered_slot;
    // Registered ownership breaks the reply-ready -> request-ready path.
    // A slot freed on this edge becomes eligible on the following cycle.
    always @* begin
        found = 0;
        free_slot = 0;
        for (integer n = 0; n < SLOTS; n = n + 1) begin
            if (!context_busy[n] && !found) begin
                found = 1;
                free_slot = n;
            end
        end
    end
    wire is_cast = CAST_TXID >= 0 && s_data[15:8] == CAST_TXID;
    wire [INDEX_BITS-1:0] selected_slot = offer_held ? offered_slot : free_slot;
    wire admitted = in_payload || is_cast || offer_held || found;
    assign request_valid = s_valid && admitted && !reset;
    assign s_ready = request_ready && admitted && !reset;
    assign request_data = in_payload || is_cast ? s_data :
        {s_data[31:16], 8'(selected_slot), s_data[7:0]};
    assign request_keep = s_keep;
    assign request_last = s_last;

    wire [7:0] wire_slot = reply_data[15:8];
    wire known = wire_slot < SLOTS &&
        !(CAST_TXID >= 0 && wire_slot == CAST_TXID) && context_busy[wire_slot];
    wire discard = out_payload ? dropping : !known;
    assign reply_ready = (discard || m_ready) && !reset;
    assign m_valid = reply_valid && !discard && !reset;
    assign m_data = out_payload ? reply_data :
        {reply_data[31:16], (known ? transactions[wire_slot] : 8'b0), reply_data[7:0]};
    assign m_keep = reply_keep;
    assign m_last = reply_last;
    assign m_destination = out_payload ? response_destination : (known ? sources[wire_slot] : 16'b0);

    always @(posedge clk) begin
        if (reset) begin
            context_busy <= 0;
            offer_held <= 0;
            offered_slot <= 0;
            in_payload <= 0;
            out_payload <= 0;
            dropping <= 0;
            response_slot <= 0;
            response_destination <= 0;
            dropped_reply <= 0;
        end else begin
            dropped_reply <= 0;
            // A different reply can free an earlier slot while this header
            // is stalled. Freeze the offered wire TXID until acceptance.
            if (!in_payload && !is_cast && !offer_held && found && s_valid && !request_ready) begin
                offer_held <= 1;
                offered_slot <= free_slot;
            end
            if (s_valid && s_ready) begin
                offer_held <= 0;
                if (!in_payload && !is_cast) begin
                    context_busy[selected_slot] <= 1;
                    sources[selected_slot] <= s_source;
                    transactions[selected_slot] <= s_data[15:8];
                end
                in_payload <= !s_last;
            end
            if (reply_valid && reply_ready) begin
                if (!out_payload) begin
                    dropping <= !known;
                    response_slot <= wire_slot[INDEX_BITS-1:0];
                    response_destination <= known ? sources[wire_slot] : 16'b0;
                    if (!known) dropped_reply <= 1;
                end
                if (reply_last && !discard)
                    context_busy[out_payload ? response_slot : wire_slot[INDEX_BITS-1:0]] <= 0;
                out_payload <= !reply_last;
            end
        end
    end

    initial begin
        if (SLOTS < 1 || SLOTS > 256 || CAST_TXID < -1 || CAST_TXID > 255 ||
            (CAST_TXID >= 0 && SLOTS > CAST_TXID))
            $fatal(1, "invalid request-context capacity");
    end
endmodule
