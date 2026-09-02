// Inferred-memory wrapper for the XLS RAM-rewritten sequential phi core.
//
// The core initializes every location it reads after reset. The synchronous
// read and write behavior below matches the one-cycle 1RW contract passed to
// XLS codegen. The block-RAM attribute is a Xilinx mapping preference, not a
// behavioral dependency of the core.

module phi_sequential_bram_top (
  input wire clk,
  input wire reset,
  output wire [97:0] summary,
  output wire summary_valid
);
  wire [7:0] actor_state_addr;
  wire [31:0] actor_state_wr_data;
  wire actor_state_we;
  wire actor_state_re;
  reg [31:0] actor_state_rd_data;

  (* ram_style = "block" *) reg [31:0] actor_state [0:255];

  always @(posedge clk) begin
    if (actor_state_we)
      actor_state[actor_state_addr] <= actor_state_wr_data;
    if (actor_state_re)
      actor_state_rd_data <= actor_state[actor_state_addr];
  end

  __phi_sequential_bram_core__SequentialBramCore_0_next core (
    .clk(clk),
    .reset(reset),
    .phi_sequential_bram_core__summary_out_rdy(1'b1),
    .actor_state_rd_data(actor_state_rd_data),
    .phi_sequential_bram_core__summary_out(summary),
    .phi_sequential_bram_core__summary_out_vld(summary_valid),
    .actor_state_addr(actor_state_addr),
    .actor_state_wr_data(actor_state_wr_data),
    .actor_state_we(actor_state_we),
    .actor_state_re(actor_state_re)
  );
endmodule
