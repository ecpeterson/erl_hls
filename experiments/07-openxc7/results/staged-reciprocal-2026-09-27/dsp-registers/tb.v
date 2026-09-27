module tb;
reg clk=0; always #5 clk=!clk; reg enable=1; reg signed [12:0] n=0;
wire signed [30:0] a,b; products dut(.*);
integer i;
initial begin for(i=-8;i<8;i=i+1) begin
@(negedge clk); n=i;
@(posedge clk); #1;
if(a !== i*43691 || b !== i*87381) $fatal(1,"n=%0d a=%0d b=%0d",n,a,b);
end $display("PASS"); $finish; end
endmodule
