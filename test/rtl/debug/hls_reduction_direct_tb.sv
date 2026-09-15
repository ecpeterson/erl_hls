`timescale 1ns/1ps
module hls_reduction_direct_tb;
    reg clk=0, reset=1, release_contributions=0;
    always #5 clk=~clk;
    wire [127:0] _reports_out;
    wire _reports_out_vld;
    wire _reports_out_rdy=1;
    integer reports=0;
    actor_debug_wrapper dut (.*);
    always @(posedge clk) if (!reset && _reports_out_vld) begin
        if (!release_contributions) $fatal(1,"completed before all participants started");
        if (_reports_out[95:0] !== 96'd3) $fatal(1,"wrong healthy fold result");
        reports=reports+1;
    end
    initial begin
        repeat(5) @(negedge clk); reset=0;
        repeat(2000) @(negedge clk); release_contributions=1;
        repeat(5000) @(negedge clk);
        if(reports != 1) $fatal(1,"expected one healthy completion, got %0d",reports);
        $display("PASS: direct RTL waits for contributors and reports only the healthy fold");
        $finish;
    end
endmodule
