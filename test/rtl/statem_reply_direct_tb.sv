`timescale 1ns/1ps
module statem_reply_direct_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:255];
    integer expected_count = 0, received = 0, cycles = 0;
    reg [32:0] held;
    reg stalled = 0;
    __statem_direct__Top_0_next dut(.clk(clk), .reset(reset), ._ext_recv(request),
        ._ext_recv_vld(request_valid), ._ext_recv_rdy(request_ready),
        ._reply_send(reply), ._reply_send_vld(reply_valid), ._reply_send_rdy(reply_ready));

    // Long pauses fill the finite output path; accepted words must remain stable.
    always @(negedge clk) reply_ready = !reset && cycles % 401 >= 300;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held)) $fatal(1, "reply changed while stalled");
        held = reply; stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (received >= expected_count || reply !== expected[received])
                $fatal(1, "beat %0d got %h expected %h", received, reply, expected[received]);
            received = received + 1;
        end
    end else stalled = 0;

    task automatic beat(input [31:0] word, input last);
        begin
            @(negedge clk); request = {last, word}; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask
    task automatic packet(input [7:0] tag, input [7:0] txid, input [31:0] value);
        begin beat({tag, 8'd0, txid, 8'd1}, 0); beat(value, 1); end
    endtask
    task automatic expect_reply(input [7:0] tag, input [7:0] txid, input [31:0] value);
        begin
            expected[expected_count] = {1'b0, tag, 8'd0, txid, 8'd1};
            expected[expected_count+1] = {1'b1, value};
            expected_count = expected_count + 2;
        end
    endtask
    task automatic drained;
        begin
            while (received < expected_count) @(negedge clk);
            repeat (100) @(negedge clk);
        end
    endtask
    task automatic restart;
        begin
            @(negedge clk); reset = 1; request_valid = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    initial begin
        restart();
        // WAIT=3 RELEASE=4 READ=5 DUPLICATE=6 EXPLODE=7 REPORT=8.
        expect_reply(1, 30, 16);
        packet(3, 10, 11); packet(3, 20, 22); packet(3, 30, 33);
        drained();
        expect_reply(8, 10, 11); expect_reply(8, 20, 22); expect_reply(8, 40, 33);
        packet(4, 255, 0); packet(5, 40, 0);
        drained();
        // The same wire transaction now owns a different internal handle.
        expect_reply(8, 41, 33);
        packet(3, 20, 7); packet(6, 255, 0); packet(5, 41, 0);
        drained();
        expect_reply(8, 20, 7); expect_reply(8, 42, 40);
        packet(4, 255, 0); packet(5, 42, 0);
        drained();
        // A bad reply fails every retained and queued caller without publishing its value.
        expect_reply(1, 10, 15); expect_reply(1, 20, 15);
        expect_reply(1, 40, 15);
        packet(3, 10, 1); packet(3, 20, 2); packet(7, 255, 1); packet(5, 40, 0);
        drained();
        restart();
        expect_reply(8, 40, 0); packet(5, 40, 0); drained();
        // Ordinary callback failure also drains every accepted caller.
        expect_reply(1, 10, 2); expect_reply(1, 20, 2);
        packet(3, 10, 1); packet(3, 20, 2); packet(7, 255, 0); drained();
        restart();
        // Duplicate live transactions cannot silently acquire a second owner.
        expect_reply(1, 10, 18); packet(3, 10, 1); packet(3, 10, 2); drained();
        restart();
        expect_reply(8, 40, 0); packet(5, 40, 0); drained();
        // A malformed declared call still owns a transaction which must complete.
        restart();
        expect_reply(1, 44, 3);
        beat({8'd3, 8'd0, 8'd44, 8'd0}, 1); drained();
        $display("PASS: retained replies, bounded admission, continuations, stale handles, stalls and failure drain");
        $finish;
    end
    initial begin #2000000; $fatal(1, "bounded server timeout, received %0d/%0d", received, expected_count); end
endmodule
