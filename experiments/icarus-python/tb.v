`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg reset = 1;

  // DUT inputs (driven by VPI bridge except reset)
  reg  [128:0] fp64_fmac__wire_req = 0;
  reg          fp64_fmac__wire_req_vld = 0;
  reg          fp64_fmac__output_rdy = 1;   // keep ready asserted (bridge can change if desired)

  // DUT outputs
  wire        fp64_fmac__wire_req_rdy;
  wire [63:0] fp64_fmac__output;
  wire        fp64_fmac__output_vld;

  // Clock: 100 MHz
  always #5 clk = ~clk;

  // Reset pulse
  initial begin
    reset = 1;
    #50;
    reset = 0;
  end

  // Instantiate DUT (your XLS module)
  __fp64_fmac__fp64_fmac_0_next dut (
    // core
    .clk(clk),
    .reset(reset),
    // client
    .fp64_fmac__wire_req(fp64_fmac__wire_req),
    .fp64_fmac__wire_req_vld(fp64_fmac__wire_req_vld),
    .fp64_fmac__wire_output_rdy(fp64_fmac__output_rdy),
    // dut
    .fp64_fmac__wire_req_rdy(fp64_fmac__wire_req_rdy),
    .fp64_fmac__wire_output(fp64_fmac__output),
    .fp64_fmac__wire_output_vld(fp64_fmac__output_vld)
  );

  // Let it run forever (bridge drives transactions)
  initial begin
    $display("tb running; VPI bridge should attach and drive I/O.");
    forever #1000000;
  end
endmodule
