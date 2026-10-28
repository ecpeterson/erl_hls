// Experimental fair merge for the four-phi fixture's opaque 424-bit batches.
// Upstream must hold a valid batch until accepted. A blocked grant is retained,
// so an arrival on the other input cannot change the visible output. No payload
// storage is added: the existing upstream FIFOs retain their capacity and data.
module __phi_halo_cell__DedicatedEgress_0_next(
  input wire clk,
  input wire reset,
  input wire [423:0] _inputs__0,
  input wire _inputs__0_vld,
  input wire [423:0] _inputs__1,
  input wire _inputs__1_vld,
  input wire _output_rdy,
  output wire _inputs__0_rdy,
  output wire _inputs__1_rdy,
  output wire [423:0] _output,
  output wire _output_vld
);
  reg prefer_one = 0;
  reg held = 0;
  reg held_one = 0;
  reg active = 0;
  wire choose_one = held ? held_one :
    ((_inputs__1_vld && prefer_one) || !_inputs__0_vld);
  assign _output = choose_one ? _inputs__1 : _inputs__0;
  assign _output_vld = active && (choose_one ? _inputs__1_vld : _inputs__0_vld);
  assign _inputs__0_rdy = active && !choose_one && _output_rdy;
  assign _inputs__1_rdy = active && choose_one && _output_rdy;
  always @(posedge clk) begin
    if (reset) begin
      prefer_one <= 0;
      held <= 0;
      held_one <= 0;
      active <= 0;
    end else begin
      active <= 1;
      if (_output_vld) begin
        held <= !_output_rdy;
        held_one <= choose_one;
        if (_output_rdy) prefer_one <= !choose_one;
      end
    end
  end
endmodule
