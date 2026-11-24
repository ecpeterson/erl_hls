`timescale 1ns/1ps
// Use the original two-pin timing harness. Release the UNISIM global reset
// before C0 and sample the single public output after each rising edge.
module functional_tb #(parameter integer CLOCKS = 4096);
    reg clock = 0;
    wire activity;
    phi_timing_harness dut(.clock(clock), .activity(activity));
    integer cycle = 0;

    initial begin
        #200;
        repeat (CLOCKS) begin
            #10;
            clock = 1;
            #1;
            $display("%0d %b", cycle, activity);
            cycle = cycle + 1;
            #9;
            clock = 0;
        end
        $finish;
    end
endmodule
