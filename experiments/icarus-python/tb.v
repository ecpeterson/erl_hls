`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg reset = 1;

  // DUT inputs (driven by VPI bridge except reset)
  reg  [63:0] fp64_fmac__input_a = 0;
  reg         fp64_fmac__input_a_vld = 0;
  reg  [63:0] fp64_fmac__input_b = 0;
  reg         fp64_fmac__input_b_vld = 0;

  reg         fp64_fmac__output_rdy = 1;   // keep ready asserted (bridge can change if desired)

  reg         fp64_fmac__reset = 0;
  reg         fp64_fmac__reset_vld = 0;

  // DUT outputs
  wire        fp64_fmac__input_a_rdy;
  wire        fp64_fmac__input_b_rdy;
  wire [63:0] fp64_fmac__output;
  wire        fp64_fmac__output_vld;
  wire        fp64_fmac__reset_rdy;

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
    .clk(clk),
    .reset(reset),
    .fp64_fmac__wire_a(fp64_fmac__input_a),
    .fp64_fmac__wire_a_vld(fp64_fmac__input_a_vld),
    .fp64_fmac__wire_b(fp64_fmac__input_b),
    .fp64_fmac__wire_b_vld(fp64_fmac__input_b_vld),
    .fp64_fmac__wire_output_rdy(fp64_fmac__output_rdy),
    .fp64_fmac__wire_reset(fp64_fmac__reset),
    .fp64_fmac__wire_reset_vld(fp64_fmac__reset_vld),
    .fp64_fmac__wire_a_rdy(fp64_fmac__input_a_rdy),
    .fp64_fmac__wire_b_rdy(fp64_fmac__input_b_rdy),
    .fp64_fmac__wire_output(fp64_fmac__output),
    .fp64_fmac__wire_output_vld(fp64_fmac__output_vld),
    .fp64_fmac__wire_reset_rdy(fp64_fmac__reset_rdy)
  );

  // Let it run forever (bridge drives transactions)
  initial begin
    $display("tb running; VPI bridge should attach and drive I/O.");
    forever #1000000;
  end
endmodule
