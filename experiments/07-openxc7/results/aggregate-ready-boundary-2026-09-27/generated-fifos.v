module fifo_for_depth_0_ty__bits_32____bits_1___bits_16___bits_2___bits_32___bits_3___bits_4____bits_64___bits_64_____with_bypass(
  input wire clk,
  input wire reset,
  input wire push_valid,
  input wire pop_ready,
  input wire [217:0] push_data,
  output wire push_ready,
  output wire pop_valid,
  output wire [217:0] pop_data
);
  wire [217:0] buf__1_init = {32'h0000_0000, {1'h0, 16'h0000, 2'h0, 32'h0000_0000, 3'h0, 4'h0, {64'h0000_0000_0000_0000, 64'h0000_0000_0000_0000}}};
  reg slots;
  reg [217:0] buf__1;
  wire is_full_bool;
  wire or_193780;
  wire and_193783;
  wire sel_193786;
  assign is_full_bool = slots == 1'h1;
  assign or_193780 = slots | push_valid;
  assign and_193783 = ~is_full_bool & push_valid;
  assign sel_193786 = and_193783 ^ pop_ready & or_193780 ? and_193783 : slots;
  always @ (posedge clk) begin
    if (reset) begin
      slots <= 1'h0;
      buf__1 <= buf__1_init;
    end else begin
      slots <= sel_193786;
      buf__1 <= and_193783 ? push_data : buf__1;
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_193780;
  assign pop_data = slots ? buf__1 : push_data;
endmodule

module fifo_for_depth_0_ty__bits_32____bits_1___bits_16___bits_2___bits_32___bits_3___bits_4____bits_64___bits_64_____with_bypass___1(
  input wire clk,
  input wire reset,
  input wire push_valid,
  input wire pop_ready,
  input wire [217:0] push_data,
  output wire push_ready,
  output wire pop_valid,
  output wire [217:0] pop_data
);
  wire [217:0] buf__1_init = {32'h0000_0000, {1'h0, 16'h0000, 2'h0, 32'h0000_0000, 3'h0, 4'h0, {64'h0000_0000_0000_0000, 64'h0000_0000_0000_0000}}};
  reg slots;
  reg [217:0] buf__1;
  wire is_full_bool;
  wire or_193895;
  wire and_193898;
  wire sel_193901;
  assign is_full_bool = slots == 1'h1;
  assign or_193895 = slots | push_valid;
  assign and_193898 = ~is_full_bool & push_valid;
  assign sel_193901 = and_193898 ^ pop_ready & or_193895 ? and_193898 : slots;
  always @ (posedge clk) begin
    if (reset) begin
      slots <= 1'h0;
      buf__1 <= buf__1_init;
    end else begin
      slots <= sel_193901;
      buf__1 <= and_193898 ? push_data : buf__1;
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_193895;
  assign pop_data = slots ? buf__1 : push_data;
endmodule
