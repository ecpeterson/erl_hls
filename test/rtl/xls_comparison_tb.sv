`timescale 1ns/1ps
// Exhaustive small-width and boundary wide-width comparisons against BEAM.
module xls_comparison_tb;
    localparam W = `LEFT_WIDTH, V = `RIGHT_WIDTH, COUNT = `COMPARISON_COUNT;
    reg [W+V+23:0] vectors [0:COUNT-1];
    reg [W-1:0] x;
    reg [V-1:0] y;
    wire [23:0] out;
    integer i;
    comparison_probe dut(.x(x), .y(y), .out(out));
    initial begin
        $readmemh(`COMPARISON_VECTORS, vectors);
        for (i = 0; i < COUNT; i = i + 1) begin
            {x,y} = vectors[i][W+V+23:24];
            #1;
            if (out !== vectors[i][23:0])
                $fatal(1, "widths=%0d/%0d x=%h y=%h got=%h expected=%h", W,V,x,y,out,vectors[i][23:0]);
        end
        $display("PASS: %0d/%0d-bit comparisons, %0d BEAM/RTL pairs", W,V,COUNT);
        $finish;
    end
endmodule
