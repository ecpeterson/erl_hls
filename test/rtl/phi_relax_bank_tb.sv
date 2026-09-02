`timescale 1ns/1ps

module phi_relax_bank_tb;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg start = 1'b0;
    reg anyon = 1'b0;
    reg signed [31:0] center0 = 32'sd0;
    reg signed [31:0] center1 = 32'sd0;
    reg signed [31:0] north0 = 32'sd0;
    reg signed [31:0] east0 = 32'sd0;
    reg signed [31:0] west0 = 32'sd0;
    reg signed [31:0] south0 = 32'sd0;
    reg signed [31:0] north1 = 32'sd0;
    reg signed [31:0] east1 = 32'sd0;
    reg signed [31:0] west1 = 32'sd0;
    reg signed [31:0] south1 = 32'sd0;
    wire done;
    wire busy;
    wire signed [31:0] result0;
    wire signed [31:0] result1;

    phi_relax_bank_1 dut (.*);

    always #5 aclk = ~aclk;

    task automatic run_case(
        input case_anyon,
        input signed [31:0] case_center0,
        input signed [31:0] case_center1,
        input signed [31:0] case_neighbor0,
        input signed [31:0] case_neighbor1,
        input signed [31:0] expected0,
        input signed [31:0] expected1
    );
        integer clocks;
        begin
            @(negedge aclk);
            anyon = case_anyon;
            center0 = case_center0;
            center1 = case_center1;
            north0 = case_neighbor0;
            east0 = case_neighbor0;
            west0 = case_neighbor0;
            south0 = case_neighbor0;
            north1 = case_neighbor1;
            east1 = case_neighbor1;
            west1 = case_neighbor1;
            south1 = case_neighbor1;
            start = 1'b1;
            @(negedge aclk);
            start = 1'b0;
            clocks = 0;
            while (!done && clocks < 100) begin
                @(negedge aclk);
                clocks = clocks + 1;
            end
            if (!done)
                $fatal(1, "relaxation did not complete");
            if (result0 !== expected0 || result1 !== expected1)
                $fatal(1,
                    "unexpected result %0d %0d, expected %0d %0d",
                    result0, result1, expected0, expected1);
            if (clocks != 76)
                $fatal(1, "unexpected measured latency %0d", clocks);
        end
    endtask

    initial begin
        repeat (2) @(negedge aclk);
        aresetn = 1'b1;
        run_case(1'b1, 0, 0, 0, 0, 32'sd65536, 32'sd0);
        run_case(
            1'b0,
            32'sd65536,
            32'sd32768,
            32'sd16384,
            32'sd8192,
            32'sd54613,
            32'sd29491
        );
        run_case(
            1'b1,
            -32'sd65536,
            -32'sd32768,
            -32'sd16384,
            -32'sd8192,
            32'sd10923,
            -32'sd29491
        );
        $display("PASS phi_relax_bank latency=76");
        $finish;
    end
endmodule
