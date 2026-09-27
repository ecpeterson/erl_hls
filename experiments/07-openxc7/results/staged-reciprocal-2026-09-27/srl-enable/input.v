module shifter(input clk, enable, input [7:0] d, output reg [7:0] q); reg [7:0] a,b; always @(posedge clk) if(enable) begin a<=d; b<=a; q<=b; end endmodule
