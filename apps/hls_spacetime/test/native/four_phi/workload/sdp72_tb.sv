`timescale 1ns/1ps
// Write and read each one-hot word on distinct clocks. A mismatch names the actual logical lane.
module sdp72_tb;
    reg clk=0, wr=0, rd=0;
    reg [8:0] wa=0, ra=0;
    reg [71:0] d=0;
    wire [71:0] q;
    integer lane;
    parity_memory dut(clk, wr, rd, wa, ra, d, q);
    initial begin
        #200;
        for (lane=0;lane<72;lane=lane+1) begin
            wa=lane; d=72'b1<<lane; wr=1; rd=0;
            #10; clk=1; #10; clk=0;
            ra=lane; wr=0; rd=1;
            #10; clk=1; #10; clk=0;
            if (q !== d) $fatal(1,"SDP72 lane %0d expected %h read %h",lane,d,q);
        end
        $display("PASS SDP72 72 independent write/read lanes");
        $finish;
    end
endmodule
