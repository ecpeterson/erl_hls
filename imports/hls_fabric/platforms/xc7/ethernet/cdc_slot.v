// One immutable packet slot shared by unrelated clocks. The writer fills RAM
// while write_ready, then publishes length; the reader releases only after its
// final transfer. Addresses are 32-bit words, length is metadata in bytes.
// Both domains share reset_n; reset requires quiescent users. Link resets must
// NOT reset this ownership handshake. RAM contents are never reset.
//
// Physical implementation must constrain the held length bus to settle before
// the two-stage request synchronizer exposes it, and place synchronizers as CDC.
module ethernet_cdc_slot(
    input wire reset_n, write_clock, read_clock,
    input wire write_enable, publish,
    input wire [8:0] write_address,
    input wire [31:0] write_data,
    input wire [10:0] write_length,
    output wire write_ready,
    input wire read_enable, release_packet,
    input wire [8:0] read_address,
    output reg [31:0] read_data,
    output wire [10:0] read_length,
    output wire read_valid
);
    wire wr_reset_n, rd_reset_n;
    zynq_probe_reset wr_reset(write_clock, reset_n, wr_reset_n);
    zynq_probe_reset rd_reset(read_clock, reset_n, rd_reset_n);
    reg request, acknowledge;
    reg [10:0] length;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync, req_meta, req_sync;
    (* ram_style="block" *) reg [31:0] memory [0:511];
    assign write_ready = wr_reset_n && request == ack_sync;
    assign read_valid = rd_reset_n && req_sync != acknowledge;
    assign read_length = length;
    always @(posedge write_clock) begin
        if (write_enable && write_ready) memory[write_address] <= write_data;
    end
    always @(posedge read_clock) begin
        if (read_enable && read_valid) read_data <= memory[read_address];
    end
    always @(posedge write_clock or negedge wr_reset_n) begin
        if (!wr_reset_n) begin request<=0; length<=0; ack_meta<=0; ack_sync<=0; end
        else begin
            ack_meta<=acknowledge; ack_sync<=ack_meta;
            if (publish && write_ready) begin length<=write_length; request<=!request; end
        end
    end
    always @(posedge read_clock or negedge rd_reset_n) begin
        if (!rd_reset_n) begin acknowledge<=0; req_meta<=0; req_sync<=0; end
        else begin
            req_meta<=request; req_sync<=req_meta;
            if (release_packet && read_valid) acknowledge<=req_sync;
        end
    end
endmodule
