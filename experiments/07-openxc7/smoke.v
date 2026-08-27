`default_nettype none

// Small sequential design used only to exercise the openXC7 bitstream flow.
// The constraints select valid package pins, not verified board connections.
module openxc7_smoke (
    input  wire clock,
    output wire counter_msb
);
    reg [23:0] counter = 24'b0;

    always @(posedge clock)
        counter <= counter + 1'b1;

    assign counter_msb = counter[23];
endmodule

`default_nettype wire
