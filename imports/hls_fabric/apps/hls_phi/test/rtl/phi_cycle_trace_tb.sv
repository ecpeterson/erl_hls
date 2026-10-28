`timescale 1ns/1ps
// Synthetic debug projections isolate field slicing, write qualification and clock alignment.
module phi_bridge_tb;
    reg clk0 = 0, clk1 = 0, reset0 = 1, reset1 = 1, resetn = 0;
    always #3 clk0 = !clk0;
    always #7 clk1 = !clk1;
    phi_cycle_test_taps device_0(clk0, reset0);
    phi_cycle_test_taps device_1(clk1, reset1);
    wire clk17 = clk0, reset17 = reset0;
    phi_cycle_test_taps device_17(clk17, reset17);
    initial begin
        #20; reset0 = 0; reset1 = 0; resetn = 1;
        #280; $finish;
    end
endmodule
module phi_cycle_test_taps(input clk, reset);
    reg [31:0] cycle = 0;
    always @(posedge clk) if (reset) cycle <= 0; else cycle <= cycle+1;
    wire [63:0] probe_values = cycle % 5;
    wire [79:0] state_value = 80'h123456789abcde000000 | cycle;
    wire [23:0] mailbox_value = 24'h800000 | (cycle % 4);
    wire [3:0] address = cycle % 3;
    wire write_enable = cycle % 2 == 0;
    wire [109:0] actor_writes = {mailbox_value, 1'b1, state_value, address, write_enable};
endmodule
