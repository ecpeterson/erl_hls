`timescale 1ns/1ps
module xls_init_topology_tb;
    `include "init_expected.svh"
    reg clk = 0, reset = 1, ready = 0;
    always #5 clk = ~clk;
    wire [127:0] report;
    wire valid;
    `INIT_TOP dut(.clk(clk), .reset(reset),
        ._reports_out(report), ._reports_out_vld(valid), ._reports_out_rdy(ready));

    task automatic restart;
        begin
            @(negedge clk); reset = 1; ready = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    task automatic await_stalled_report;
        reg [127:0] held;
        begin
            while (!valid) @(negedge clk);
            held = report;
            repeat (100) begin
                @(negedge clk);
                if (!valid || report !== held)
                    $fatal(1, "startup report changed under backpressure");
            end
        end
    endtask

    task automatic collect;
        integer count;
        reg seen_first, seen_second;
        begin
            count = 0; seen_first = 0; seen_second = 0;
            @(negedge clk); ready = 1;
            while (count < 2) begin
                @(posedge clk);
                if (valid) begin
                    if (report[127:32] !== {32'h03000004, 32'd7, 32'd0})
                        $fatal(1, "startup phase/default/header mismatch: %h", report);
                    case (report[31:0])
                        EXPECTED_1: begin
                            if (seen_first) $fatal(1, "duplicated first actor");
                            seen_first = 1;
                        end
                        EXPECTED_2: begin
                            if (seen_second) $fatal(1, "duplicated second actor");
                            seen_second = 1;
                        end
                        default: $fatal(1, "startup value differs from BEAM: %h", report);
                    endcase
                    count = count + 1;
                end
            end
            repeat (150) begin
                @(posedge clk);
                if (valid) $fatal(1, "unexpected extra startup report");
            end
            @(negedge clk); ready = 0;
        end
    endtask

    initial begin
        restart(); await_stalled_report(); collect();
        // Changed actor RAM survives reset. Boot must rewrite every slot,
        // restore the nonfirst phase, and reapply startup exactly once.
        restart(); await_stalled_report(); collect();
        restart(); repeat (2) @(negedge clk); restart();
        await_stalled_report(); collect();
        restart(); repeat (20) @(negedge clk); restart();
        await_stalled_report(); collect();
        restart(); await_stalled_report(); restart();
        await_stalled_report(); collect();
        $display("PASS: topology initialization/reset matches BEAM for both actors");
        $finish;
    end
    initial begin #500000; $fatal(1, "topology initialization timeout"); end
endmodule
