// Two bounded frame slots. Input/output transfer on valid && ready; last ends
// a frame. Only complete, error-free frames of MIN_BYTES..MAX_BYTES are visible.
// DROP_WHEN_FULL=0 backpressures a producer between frames; =1 drains and drops
// an entire incoming frame when no slot was free at its first byte. Mid-frame
// valid gaps are allowed. Error, overlength and underlength frames are discarded.
// abort_partial discards only an unfinished input frame (upstream must also
// abandon its remainder); flush additionally discards queued/output bytes.
// Require 1 <= MIN_BYTES <= MAX_BYTES <= 2048. Memory is not reset.
// Counters wrap modulo 2^32 and clear only on rst.
module ethernet_frame_store #(
    parameter DROP_WHEN_FULL = 0,
    parameter MIN_BYTES = 14,
    parameter MAX_BYTES = 1514
)(
    input wire clk, rst, flush, abort_partial,
    input wire in_valid, in_last, in_error,
    input wire [7:0] in_data,
    output wire in_ready,
    output reg out_valid,
    input wire out_ready,
    output reg out_last,
    output reg [7:0] out_data,
    output reg [1:0] queued,
    output reg [31:0] accepted, dropped, overflowed, aborted
);
    reg [7:0] memory [0:4095];
    reg [11:0] lengths [0:1];
    reg write_slot, read_slot;
    reg [11:0] length;
    reg [10:0] read_index;
    reg bad, no_space;
    wire take = in_valid && in_ready;
    wire unavailable = no_space || (length == 0 && queued == 2);
    wire invalid = bad || in_error || length >= MAX_BYTES || unavailable;
    wire commit = take && in_last && !invalid && length + 1 >= MIN_BYTES;
    wire release_slot = out_valid && out_ready && out_last;
    wire read_enable = queued != 0 && (!out_valid || out_ready) && !release_slot;
    assign in_ready = !rst && !flush && !abort_partial &&
                      (DROP_WHEN_FULL || length != 0 || queued != 2);

    // One synchronous read and write port preserve BRAM inference. A held output
    // consumes no further reads; a busy receive frame never overwrites a slot.
    always @(posedge clk) begin
        if (take && !invalid)
            memory[{write_slot, length[10:0]}] <= in_data;
        if (read_enable)
            out_data <= memory[{read_slot, read_index}];
    end

    always @(posedge clk) begin
        if (rst) begin
            write_slot <= 0;
            read_slot <= 0;
            length <= 0;
            read_index <= 0;
            bad <= 0;
            no_space <= 0;
            out_valid <= 0;
            out_last <= 0;
            queued <= 0;
            accepted <= 0;
            dropped <= 0;
            overflowed <= 0;
            aborted <= 0;
        end else if (flush) begin
            aborted <= aborted + queued + (length != 0);
            write_slot <= 0;
            read_slot <= 0;
            length <= 0;
            read_index <= 0;
            bad <= 0;
            no_space <= 0;
            out_valid <= 0;
            queued <= 0;
        end else begin
            if (read_enable) begin
                out_valid <= 1;
                out_last <= read_index == lengths[read_slot] - 1;
                read_index <= read_index + 1'b1;
            end
            if (release_slot) begin
                out_valid <= 0;
                read_index <= 0;
                read_slot <= !read_slot;
            end
            case ({commit, release_slot})
                2'b10: queued <= queued + 1'b1;
                2'b01: queued <= queued - 1'b1;
                default: ;
            endcase
            if (abort_partial) begin
                aborted <= aborted + (length != 0);
                length <= 0;
                bad <= 0;
                no_space <= 0;
            end else if (take) begin
                if (in_last) begin
                    if (commit) begin
                        lengths[write_slot] <= length + 1'b1;
                        write_slot <= !write_slot;
                        accepted <= accepted + 1'b1;
                    end else begin
                        dropped <= dropped + 1'b1;
                        overflowed <= overflowed + unavailable;
                    end
                    length <= 0;
                    bad <= 0;
                    no_space <= 0;
                end else begin
                    // Saturating length prevents an arbitrarily long bad frame
                    // from wrapping around into a new admission or memory write.
                    if (length < MAX_BYTES + 1) length <= length + 1'b1;
                    bad <= invalid;
                    no_space <= unavailable;
                end
            end
        end
    end
endmodule
