`timescale 1ns/1ps

// Bounded simulation witness: all four inferred shapes complete five patterns
// without a mismatch under ordinary RTL memory semantics.
module bram_probe_tb;
    reg clock = 0;
    reg reset_n = 0;
    reg [31:0] control = 0;
    wire [127:0] status;
    integer cycles;

    always #5 clock = ~clock;
    bram_probe_core dut(.clock(clock), .reset_n(reset_n),
                        .control(control), .status(status));

    initial begin
        repeat (3) @(posedge clock);
        reset_n = 1;
        for (cycles = 0; cycles < 2000 && !status[2]; cycles = cycles + 1)
            @(posedge clock);
        if (status[2] !== 1'b1 || status[3] !== 1'b0) begin
            $display("FAIL: status=%032x", status);
            $fatal(1);
        end
        $display("PASS: four BRAM shapes completed in %0d cycles", cycles);
        $finish;
    end
endmodule
