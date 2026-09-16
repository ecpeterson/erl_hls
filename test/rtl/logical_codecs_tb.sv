`timescale 1ns/1ps
module logical_codecs_tb;
    reg [127:0] raw;
    reg [7:0] kind;
    wire [127:0] out;
    reg [127:0] expected;
    integer fd, fields, count = 0;
    string vectors;
    probe dut(.raw(raw), .kind(kind), .out(out));
    initial begin
        if (!$value$plusargs("vectors=%s", vectors)) $fatal(1, "missing vectors");
        fd = $fopen(vectors, "r");
        if (!fd) $fatal(1, "cannot read vectors");
        while (!$feof(fd)) begin
            fields = $fscanf(fd, "%h %h %h\n", kind, raw, expected);
            if (fields != 3) $fatal(1, "malformed vector");
            #1;
            if (out !== expected)
                $fatal(1, "codec %0d raw=%h got=%h expected=%h", kind, raw, out, expected);
            count = count + 1;
        end
        if (!count) $fatal(1, "empty vectors");
        $display("PASS: %0d BEAM/RTL codec vectors", count);
        $finish;
    end
endmodule
