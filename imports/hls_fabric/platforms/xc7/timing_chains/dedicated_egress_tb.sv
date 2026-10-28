`timescale 1ns/1ps
// Exercise a blocked grant, a late preferred arrival, reset and sustained fairness.
module dedicated_egress_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1;
  reg [423:0] a = 424'h10, b = 424'h20;
  reg av = 0, bv = 0, ready = 0;
  wire ar, br, valid;
  wire [423:0] value;
  integer i;
  reg prior_choice;
  __phi_halo_cell__DedicatedEgress_0_next dut(
    .clk(clk), .reset(reset), ._inputs__0(a), ._inputs__0_vld(av),
    ._inputs__1(b), ._inputs__1_vld(bv), ._output_rdy(ready),
    ._inputs__0_rdy(ar), ._inputs__1_rdy(br), ._output(value), ._output_vld(valid));

  initial begin
    repeat (2) @(posedge clk);
    @(negedge clk); reset = 0; bv = 1;
    @(posedge clk); #1;
    if (!valid || value !== b) $fatal(1, "idle preferred input blocked service");
    @(posedge clk); #1;
    @(negedge clk); av = 1;
    repeat (4) begin
      @(posedge clk); #1;
      if (!valid || value !== b || ar || br) $fatal(1, "blocked grant changed");
    end
    @(negedge clk); ready = 1;
    #1; if (!br || ar || value !== b) $fatal(1, "blocked batch was not first");
    @(posedge clk); #1;
    if (!ar || br || value !== a) $fatal(1, "priority did not advance after service");
    prior_choice = 0;
    for (i = 0; i < 20; i = i + 1) begin
      @(posedge clk); #1;
      if (!valid || !(ar ^ br) || br == prior_choice)
        $fatal(1, "saturated inputs did not alternate");
      prior_choice = br;
    end
    @(negedge clk); ready = 0;
    @(posedge clk); #1;
    @(negedge clk); reset = 1;
    @(posedge clk); #1;
    if (valid || ar || br) $fatal(1, "reset did not clear the grant");
    $display("PASS: work-conserving merge, stable blocked grant, fairness and reset");
    $finish;
  end
endmodule
