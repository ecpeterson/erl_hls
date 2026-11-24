`timescale 1ns/1ps
// Record stable pre-edge D/Q, control inputs and post-edge Q for the two-bit fixture.
module bench;
    reg clock = 0, enable = 0, reset = 0;
    wire activity;
    top dut(clock, enable, reset, activity);
    integer cycle = 0;
    reg [1:0] before_q, before_d;
    task sample(input reg r, input reg e);
        begin
            reset = r; enable = e; #5;
            before_q = dut.q; before_d = dut.d;
            clock = 1; #5;
            $display("{%0d,%0d,%0d,%0d,%0d,%0d}.", cycle, r, e, before_q, before_d, dut.q);
            clock = 0; #5;
            cycle = cycle + 1;
        end
    endtask
    initial begin
        sample(0,0); sample(1,0); sample(0,1); sample(0,0);
        sample(0,1); sample(0,1); sample(1,1); sample(0,1);
        $display("{complete,%0d}.", cycle);
    end
endmodule
