// Replay each native-derived one-step transition, including invalid cursor operations.
module hls_ring_tb;
  localparam W = 128 + 8 * `RING_CAPACITY;
  localparam ROW = 2*W + 22;
  reg [ROW-1:0] vectors [0:`RING_COUNT-1];
  reg [W-1:0] raw;
  reg [3:0] op;
  reg [7:0] value;
  wire [W+9:0] out;
  ring_probe dut(.raw(raw), .op(op), .value(value), .out(out));
  integer i;
  initial begin
    $readmemh(`RING_VECTORS, vectors);
    for (i=0; i<`RING_COUNT; i=i+1) begin
      {raw, op, value} = vectors[i][ROW-1:W+10];
      #1;
      if (out !== vectors[i][W+9:0]) $fatal(1, "ring transition %0d op %0d: %h != %h", i, op, out, vectors[i][W+9:0]);
    end
    $display("PASS ring %0d transitions", `RING_COUNT);
    $finish;
  end
endmodule
