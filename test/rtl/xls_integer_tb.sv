`timescale 1ns/1ps
module xls_integer_tb;
    localparam W = `INTEGER_WIDTH, COUNT = `INTEGER_COUNT;
    reg [4*W+1:0] vectors [0:COUNT-1];
    reg [W-1:0] x, y;
    wire [2*W+1:0] out;
    integer i;
    integer_probe dut(.x(x), .y(y), .out(out));
    initial begin
        $readmemh(`INTEGER_VECTORS, vectors);
        for (i = 0; i < COUNT; i = i + 1) begin
            {x, y} = vectors[i][4*W+1:2*W+2];
            #1;
            if (out !== vectors[i][2*W+1:0])
                $fatal(1, "width=%0d x=%h y=%h got=%h expected=%h", W, x, y, out, vectors[i][2*W+1:0]);
        end
        $display("PASS: %0d-bit division/remainder, %0d BEAM/optimized-RTL input pairs", W, COUNT);
        $finish;
    end
endmodule
