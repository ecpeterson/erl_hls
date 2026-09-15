`timescale 1ns/1ps
module xls_collection_tb;
    localparam W = `COLLECTION_WIDTH;
    localparam COUNT = `COLLECTION_COUNT;
    reg [W-1:0] index, count;
    reg [23:0] values;
    reg [7:0] value;
    wire [87:0] result;
    reg [87:0] expected;
    reg [2*W+119:0] vectors [0:COUNT-1];
    integer i;
    collection_probe dut (.index(index), .count(count), .values(values), .value(value), .out(result));
    initial begin
        $readmemh(`COLLECTION_VECTORS, vectors);
        for (i=0; i<COUNT; i=i+1) begin
            {index, count, values, value, expected} = vectors[i];
            #1;
            if (result !== expected)
                $fatal(1, "collection vector %0d: index=%h count=%h got=%h expected=%h", i, index, count, result, expected);
        end
        $display("PASS: %0d BEAM/RTL collection vectors at %0d-bit index width", COUNT, W);
        $finish;
    end
endmodule
