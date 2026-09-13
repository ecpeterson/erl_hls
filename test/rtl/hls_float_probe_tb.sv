`timescale 1ns/1ps
module hls_float_probe_tb;
    localparam W = `FLOAT_WIDTH;
    reg [2:0] mode;
    reg [W-1:0] x, y;
    wire [W:0] out;
    integer count = 0;
    float_probe dut(.mode(mode), .x(x), .y(y), .out(out));
    task check(input [2:0] op, input [W-1:0] a, b, expected, input failed);
        begin
            mode = op; x = a; y = b; #1;
            if (out !== {expected, failed})
                $fatal(1, "width=%0d mode=%0d x=%h y=%h got=%h expected=%h", W, op, a, b, out, {expected, failed});
            count = count + 1;
        end
    endtask
    initial begin
        `include `FLOAT_VECTORS
        $display("PASS: binary%0d, %0d BEAM/optimized-RTL arithmetic and comparison vectors", W, count);
        $finish;
    end
endmodule
