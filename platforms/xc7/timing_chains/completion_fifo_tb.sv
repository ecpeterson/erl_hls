`timescale 1ns/1ps
// Compare live FIFO data/handshakes against synthesized XC7 distributed RAM.
module completion_fifo_tb;
  parameter WIDTH = 384;
  reg clk = 0;
  always #5 clk = !clk;
  reg reset = 1;
  reg push_valid = 0;
  reg pop_ready = 0;
  reg [WIDTH-1:0] push_data = 0;
  wire reference_ready, reference_valid, candidate_ready, candidate_valid;
  wire [WIDTH-1:0] reference_data, candidate_data;
  reference_fifo reference (.clk(clk), .reset(reset), .push_valid(push_valid),
    .push_data(push_data), .push_ready(reference_ready),
    .pop_ready(pop_ready), .pop_valid(reference_valid), .pop_data(reference_data));
  completion_fifo candidate (.clk(clk), .reset(reset), .push_valid(push_valid),
    .push_data(push_data), .push_ready(candidate_ready),
    .pop_ready(pop_ready), .pop_valid(candidate_valid), .pop_data(candidate_data));
  integer cycle, chunk, simultaneous = 0, stalled = 0, reset_live = 0;
  reg [31:0] random_state = 32'h16ca937b;
  initial begin
    for (cycle = 0; cycle < 10000; cycle = cycle + 1) begin
      @(negedge clk);
      if (cycle % 997 == 0 && reference_valid) reset_live = reset_live + 1;
      reset = cycle < 2 || cycle % 997 < 2;
      for (chunk = 0; chunk < WIDTH; chunk = chunk + 32) begin
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        push_data = (push_data << 32) | random_state;
      end
      // Fill/stall, recover and stream, drain, then offer irregular traffic.
      push_valid = cycle % 512 < 320 ? 1 :
        (cycle % 512 < 384 ? 0 : random_state[0]);
      pop_ready = cycle % 512 < 160 ? 0 :
        (cycle % 512 < 384 ? 1 : random_state[1]);
      #1;
      if (!reset) begin
        if (reference_ready !== candidate_ready || reference_valid !== candidate_valid)
          $fatal(1, "handshake mismatch at cycle %0d", cycle);
        if (reference_valid && reference_data !== candidate_data)
          $fatal(1, "payload mismatch at cycle %0d", cycle);
        if (push_valid && reference_ready && pop_ready && reference_valid)
          simultaneous = simultaneous + 1;
        if (push_valid && !reference_ready) stalled = stalled + 1;
      end
    end
    if (!simultaneous || !stalled || !reset_live) $fatal(1, "missing coverage");
    $display("PASS: %0d-bit mapped FIFO, 10000 cycles; simultaneous=%0d stalled=%0d reset-live=%0d",
      WIDTH, simultaneous, stalled, reset_live);
    $finish;
  end
endmodule
