`default_nettype none

// TE0715-05 + TEF1002-03 RGPIO status probe. FCLK0 is 25 MHz from the matched
// regsvc FSBL. No GTX or carrier control activation; only ordinary bank-13 I/O.
module te0715_sfp_top(
    input wire rgpio_rx,
    output wire rgpio_tx, rgpio_clock
);
    wire clock, reset_n;
    wire [31:0] control;
    wire [127:0] status;
    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h53465037)) processor_shell(
        .clock(clock), .reset_n(reset_n), .control(control), .status(status));
    sfp_status monitor(.clock(clock), .reset_n(reset_n), .control(control),
        .rx(rgpio_rx), .tx(rgpio_tx), .serial_clock(rgpio_clock), .status(status));
endmodule

`default_nettype wire
