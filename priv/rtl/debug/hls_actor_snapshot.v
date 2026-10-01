// Observe committed state writes without adding a RAM port or application
// handshake. One write and one asynchronous query port per scheduler bank let
// synthesis use distributed RAM for the latest phase, entry flag, and failure
// code. Only validity resets; unread/uninitialized memory is masked to zero.
// The query controller captures the value before this edge's write.
module hls_actor_snapshot #(
    parameter integer SLOTS = 1,
    parameter integer ADDRESS_WIDTH = 1,
    parameter integer MAILBOX = 0,
    parameter integer REDUCTION_WIDTH = 0
) (
    input wire clk, reset,
    input wire write_enable,
    input wire [ADDRESS_WIDTH-1:0] write_address,
    // Low 25 bits: {failure[15:0], enter_pending, phase[7:0]}; then reduction metadata.
    input wire [24+REDUCTION_WIDTH:0] write_value,
    input wire mailbox_valid,
    input wire [SLOTS*24-1:0] mailbox_values,
    input wire [ADDRESS_WIDTH-1:0] read_address,
    output wire [127:0] value
);
    reg [24+REDUCTION_WIDTH:0] snapshot [0:SLOTS-1];
    reg [SLOTS-1:0] initialized;
    always @(posedge clk) begin
        if (reset) initialized <= 0;
        else if (write_enable && write_address < SLOTS) begin
            snapshot[write_address] <= write_value;
            initialized[write_address] <= 1'b1;
        end
    end
    assign value[31:0] = read_address < SLOTS && initialized[read_address] ?
        {6'b0, 1'b1, snapshot[read_address][24:0]} : 32'b0;
    generate if (REDUCTION_WIDTH > 0) begin: reduction
        assign value[127:56] = read_address < SLOTS && initialized[read_address] ?
            {{(72-REDUCTION_WIDTH){1'b0}}, snapshot[read_address][25 +: REDUCTION_WIDTH]} : 72'b0;
    end else begin: no_reduction
        assign value[127:56] = 0;
    end endgenerate
    generate if (MAILBOX) begin: metadata
        // Every slot can change on the same publication edge, so this remains
        // a parallel register bank rather than a single-write-port memory.
        reg [SLOTS*24-1:0] retained;
        always @(posedge clk) begin
            if (reset) retained <= 0;
            else if (mailbox_valid) retained <= mailbox_values;
        end
        assign value[55:32] = read_address < SLOTS ?
            retained[read_address*24 +: 24] : 24'b0;
    end else begin: no_metadata
        assign value[55:32] = 0;
    end endgenerate
endmodule
