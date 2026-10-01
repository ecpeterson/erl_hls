`timescale 1ns/1ps
// Compare each optimized combinational result with an independently executed
// BEAM call. Inputs deliberately have unequal widths and signedness.
module hls_serial_tb;
    localparam W = `SERIAL_WIDTH, COUNT = `SERIAL_COUNT;
    localparam XW = W + 2, YW = W + 1, OW = 4 * (W + 1);
    reg [XW+YW+OW-1:0] vectors [0:COUNT-1];
    reg signed [XW-1:0] x;
    reg [YW-1:0] y;
    wire [OW-1:0] out;
    integer i;
    serial_probe dut(.x(x), .y(y), .out(out));
    initial begin
        $readmemh(`SERIAL_VECTORS, vectors);
        for (i = 0; i < COUNT; i = i + 1) begin
            {x, y} = vectors[i][XW+YW+OW-1:OW];
            #1;
            if (out !== vectors[i][OW-1:0])
                $fatal(1, "width=%0d x=%h y=%h got=%h expected=%h", W, x, y, out, vectors[i][OW-1:0]);
        end
        $display("PASS: %0d-bit serial arithmetic, %0d BEAM/optimized-RTL input pairs", W, COUNT);
        $finish;
    end
endmodule
