`timescale 1ns/1ps

module phi_sequential_bram_tb;
  reg clk = 1'b0;
  reg reset = 1'b1;
  wire [97:0] summary;
  wire summary_valid;

  always #5 clk = ~clk;

  phi_sequential_bram_top dut (
    .clk(clk),
    .reset(reset),
    .summary(summary),
    .summary_valid(summary_valid)
  );

  initial begin
    repeat (4) @(posedge clk);
    reset <= 1'b0;
  end

  initial begin
    repeat (500000) begin
      @(posedge clk);
      if (summary_valid) begin
        if (summary[97:66] !== 32'd21)
          $fatal(1, "unexpected step %0d", summary[97:66]);
        if (summary[65:50] !== 16'd84)
          $fatal(1, "unexpected corrections %0d", summary[65:50]);
        if (summary[49:34] !== 16'd45)
          $fatal(1, "unexpected X corrections %0d", summary[49:34]);
        if (summary[33:18] !== 16'd39)
          $fatal(1, "unexpected Z corrections %0d", summary[33:18]);
        if (summary[17:0] !== 18'h1320c)
          $fatal(1, "unexpected measurement %h", summary[17:0]);
        $display("phi sequential BRAM regression passed");
        $finish;
      end
    end
    $fatal(1, "timed out waiting for BRAM-backed decoder summary");
  end
endmodule
