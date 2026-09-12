// Observe committed state writes without adding a RAM port or application
// handshake. Each slot retains only its latest phase and flags, plus validity.
// Reset invalidates every slot; RAM itself need not reset. A simultaneous
// query observes the snapshot from before this edge's write.
module hls_actor_snapshot #(
    parameter integer SLOTS = 1,
    parameter integer ADDRESS_WIDTH = 1
) (
    input wire clk, reset,
    input wire write_enable,
    input wire [ADDRESS_WIDTH-1:0] write_address,
    input wire [9:0] write_value, // {failed, enter_pending, phase[7:0]}
    output wire [SLOTS*32-1:0] values
);
    genvar slot;
    generate for (slot = 0; slot < SLOTS; slot = slot + 1) begin: actor
        reg [10:0] snapshot;
        always @(posedge clk) begin
            if (reset) snapshot <= 0;
            else if (write_enable && write_address == slot)
                snapshot <= {1'b1, write_value};
        end
        assign values[slot*32 +: 32] = {21'b0, snapshot};
    end endgenerate
endmodule
