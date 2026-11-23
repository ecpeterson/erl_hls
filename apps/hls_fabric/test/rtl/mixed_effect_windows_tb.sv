`timescale 1ns/1ps
module window_tb;
reg clk=0, reset=1, measuring=0;
always #5 clk=~clk;
wire [127:0] left, right;
wire left_valid, right_valid;
integer cycles=0, elapsed=0, left_count=0, right_count=0;
integer left_first=0, right_first=0, left_last=0, right_last=0;
wire left_ready=measuring && elapsed%11 < 7;
wire right_ready=measuring && elapsed%7 < 5;
reg [127:0] expected [0:31];
mixed_topology_wrapper dut(.clk(clk), .reset(reset),
  ._reports_out(left), ._reports_out_vld(left_valid), ._reports_out_rdy(left_ready),
  ._reports_peer_out(right), ._reports_peer_out_vld(right_valid), ._reports_peer_out_rdy(right_ready));
initial begin
  $readmemh("expected.hex", expected);
  repeat(5) @(negedge clk); reset=0;
  // Both feedback graphs have blocked output and buffered work at this point.
  wait(left_valid && right_valid);
  repeat(100) @(negedge clk);
  reset=1;
  repeat(5) @(negedge clk); reset=0; measuring=1;
  wait(left_count==32 && right_count==32);
  repeat(500) @(negedge clk);
  $display("METRICS %0d %0d %0d %0d", left_first, left_last, right_first, right_last);
  $display("PASS: reset during backpressure, both complete CPU transcripts, no duplicate replies");
  $finish;
end
always @(posedge clk) begin
  cycles=cycles+1;
  if(cycles>100000) $fatal(1, "mixed window timeout (%0d, %0d)", left_count, right_count);
  if(measuring && !reset) begin
    if(left_valid && left_ready) begin
      if(left_count>=32 || left !== expected[left_count]) $fatal(1, "left report %0d: %032h",left_count,left);
      if(left_count==0) left_first=elapsed;
      left_last=elapsed; left_count=left_count+1;
    end
    if(right_valid && right_ready) begin
      if(right_count>=32 || right !== expected[right_count]) $fatal(1, "right report %0d: %032h",right_count,right);
      if(right_count==0) right_first=elapsed;
      right_last=elapsed; right_count=right_count+1;
    end
    elapsed<=elapsed+1;
  end
end
endmodule
