`timescale 1ns/1ps
// Finite scalar corpus: original Erlang evaluation supplies both result and
// body-failure flag; rejected guards must instead select the later case arm.
module xls_static_integer_tb;
    localparam COUNT = `STATIC_INTEGER_COUNT;
    reg [69:0] vectors [0:COUNT-1];
    reg [4:0] mode;
    reg [31:0] x;
    wire [32:0] out;
    integer i;
    static_integer_probe dut(.mode(mode), .x(x), .out(out));
    initial begin
        $readmemh(`STATIC_INTEGER_VECTORS, vectors);
        for (i = 0; i < COUNT; i = i + 1) begin
            {mode, x} = vectors[i][69:33];
            #1;
            if (out !== vectors[i][32:0])
                $fatal(1, "mode=%0d x=%h got=%h expected=%h", mode, x, out, vectors[i][32:0]);
        end
        $display("PASS: static integer BEAM/optimized-RTL expressions and failure flags");
        $finish;
    end
endmodule
