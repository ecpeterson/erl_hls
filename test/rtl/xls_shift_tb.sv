`timescale 1ns/1ps
module xls_shift_tb;
    localparam W = `SHIFT_WIDTH, CW = `SHIFT_COUNT_WIDTH, COUNT = `SHIFT_CASES;
    reg [3*W+CW-1:0] vectors [0:COUNT-1];
    reg [W-1:0] x;
    reg [CW-1:0] y;
    wire [2*W-1:0] out;
    integer i;
    shift_probe dut(.x(x), .y(y), .out(out));
    initial begin
        $readmemh(`SHIFT_VECTORS, vectors);
        for (i = 0; i < COUNT; i = i + 1) begin
            {x, y} = vectors[i][3*W+CW-1:2*W];
            #1;
            if (out !== vectors[i][2*W-1:0])
                $fatal(1, "value width=%0d count width=%0d x=%h y=%h got=%h expected=%h",
                    W, CW, x, y, out, vectors[i][2*W-1:0]);
        end
        $display("PASS: %0d-bit value/%0d-bit count, %0d optimized-RTL shift pairs", W, CW, COUNT);
        $finish;
    end
endmodule
