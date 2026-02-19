`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg reset = 1;

  // DUT inputs (driven by VPI bridge except reset)
  reg  [31:0] fp32_fmac__input_a = 0;
  reg         fp32_fmac__input_a_vld = 0;
  reg  [31:0] fp32_fmac__input_b = 0;
  reg         fp32_fmac__input_b_vld = 0;

  reg         fp32_fmac__output_rdy = 1;   // keep ready asserted (bridge can change if desired)

  reg         fp32_fmac__reset = 0;
  reg         fp32_fmac__reset_vld = 0;

  // DUT outputs
  wire        fp32_fmac__input_a_rdy;
  wire        fp32_fmac__input_b_rdy;
  wire [31:0] fp32_fmac__output;
  wire        fp32_fmac__output_vld;
  wire        fp32_fmac__reset_rdy;

  // Clock: 100 MHz
  always #5 clk = ~clk;

  // Reset pulse
  initial begin
    reset = 1;
    #50;
    reset = 0;
  end

  // Instantiate DUT (your XLS module)
  __fp32_fmac__fp32_fmac_0_next dut (
    .clk(clk),
    .reset(reset),
    .fp32_fmac__input_a(fp32_fmac__input_a),
    .fp32_fmac__input_a_vld(fp32_fmac__input_a_vld),
    .fp32_fmac__input_b(fp32_fmac__input_b),
    .fp32_fmac__input_b_vld(fp32_fmac__input_b_vld),
    .fp32_fmac__output_rdy(fp32_fmac__output_rdy),
    .fp32_fmac__reset(fp32_fmac__reset),
    .fp32_fmac__reset_vld(fp32_fmac__reset_vld),
    .fp32_fmac__input_a_rdy(fp32_fmac__input_a_rdy),
    .fp32_fmac__input_b_rdy(fp32_fmac__input_b_rdy),
    .fp32_fmac__output(fp32_fmac__output),
    .fp32_fmac__output_vld(fp32_fmac__output_vld),
    .fp32_fmac__reset_rdy(fp32_fmac__reset_rdy)
  );

  // Let it run forever (bridge drives transactions)
  initial begin
    $display("tb running; VPI bridge should attach and drive I/O.");
    forever #1000000;
  end
endmodule
