// Two registered signed products share a numerator and clock enable.
module products(input clk, enable, input signed [12:0] n, output reg signed [30:0] a,b);
always @(posedge clk) if(enable) begin a <= n * 18'sd43691; b <= n * 18'sd87381; end
endmodule
