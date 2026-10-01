`timescale 1ns/1ps
module xls_init_gs_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [127:0] request = 0;
    reg request_valid = 0, report_ready = 0;
    wire request_ready, report_valid;
    wire [127:0] report;
    init_gs dut(.clk(clk), .reset(reset),
        ._request(request), ._request_vld(request_valid), ._request_rdy(request_ready),
        ._report(report), ._report_vld(report_valid), ._report_rdy(report_ready));

    task automatic restart;
        begin
            @(negedge clk);
            reset = 1; request_valid = 0; report_ready = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    task automatic send_frame(input [7:0] tag, input [31:0] value);
        begin
            @(negedge clk);
            request = {8'd1, 16'd0, tag, 64'd0, value};
            request_valid = 1;
            do @(posedge clk); while (!request_ready);
            @(negedge clk); request_valid = 0;
        end
    endtask

    task automatic check_report(input [31:0] expected, input consume);
        reg [127:0] held;
        begin
            while (!report_valid) @(negedge clk);
            held = report;
            if (held !== {32'h02000005, 64'd0, expected})
                $fatal(1, "GS initialization: expected %0d, got %h", expected, held);
            repeat (30) begin
                @(negedge clk);
                if (!report_valid || report !== held)
                    $fatal(1, "GS reply changed while stalled");
            end
            if (consume) begin
                report_ready = 1;
                @(posedge clk); @(negedge clk); report_ready = 0;
            end
        end
    endtask

    task automatic query(input [31:0] expected);
        // A zero-buffer service may accept the request and reply together.
        // Drive the two directions concurrently rather than requiring input
        // acceptance before the response consumer can become ready.
        fork
            send_frame(3, 0);
            check_report(expected, 1);
        join
    endtask

    initial begin
        restart();
        query(42);
        send_frame(4, 99);
        query(99);
        restart();
        query(42);
        send_frame(4, 123);
        @(negedge clk);
        request = {32'h01000003, 96'd0}; request_valid = 1;
        check_report(123, 0);
        // A hardware reset aborts outstanding traffic; it is a new session.
        restart();
        query(42);
        repeat (100) begin
            @(negedge clk);
            if (report_valid) $fatal(1, "reply survived reset or was duplicated");
        end
        $display("PASS: hls_gs cold start, mutation, reset and stalled-reply reset");
        $finish;
    end
    initial begin #200000; $fatal(1, "GS initialization timeout"); end
endmodule
