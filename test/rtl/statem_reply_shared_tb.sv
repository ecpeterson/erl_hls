`timescale 1ns/1ps
// Public topology ports only: two actors share production RAMs and one reply sequencer.
module statem_reply_shared_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [193:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [127:0] reply;
    integer cycles = 0, pending = 0, received = 0;
    reg [40:0] expected [0:254];
    reg [127:0] held;
    reg stalled = 0;
    integer i;
    statem_shared_wrapper dut(.*);

    // Retain whole frames across long stalls; unrelated actors must remain independent.
    always @(negedge clk) reply_ready = !reset && cycles % 401 >= 300;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held)) $fatal(1, "unstable stalled reply");
        held = reply; stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (reply[119:112] == 255 || !expected[reply[119:112]][40])
                $fatal(1, "unexpected transaction: %h", reply);
            if (reply[127:120] !== 1 || reply[111:104] !== 0 || reply[95:32] !== 0 ||
                {reply[103:96], reply[31:0]} !== expected[reply[119:112]][39:0])
                $fatal(1, "wrong response: %h", reply);
            expected[reply[119:112]][40] = 0;
            pending = pending - 1; received = received + 1;
        end
    end else stalled = 0;

    // Single-point rectangles ensure each synchronous request names exactly one actor.
    task automatic packet(input [15:0] actor, input [7:0] tag, input [7:0] txid, input [31:0] value);
        begin
            @(negedge clk);
            request = {actor, 16'd0, actor, 16'd0, 2'd0, 8'd1, txid, 8'd0, tag, 64'd0, value};
            request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask
    task automatic expect_reply(input [7:0] txid, input [7:0] tag, input [31:0] value);
        begin
            if (expected[txid][40]) $fatal(1, "test reused a live transaction");
            expected[txid] = {1'b1, tag, value}; pending = pending + 1;
        end
    endtask
    task automatic drained;
        begin
            while (pending != 0) @(negedge clk);
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
        for (i = 0; i < 255; i = i + 1) expected[i] = 0;
        restart();
        expect_reply(3, 1, 16); expect_reply(13, 1, 16);
        packet(0, 3, 1, 11); packet(1, 3, 11, 101);
        packet(0, 3, 2, 22); packet(1, 3, 12, 202);
        packet(0, 3, 3, 33); packet(1, 3, 13, 303);
        drained();
        expect_reply(1, 8, 11); expect_reply(2, 8, 22); expect_reply(4, 8, 33);
        expect_reply(11, 8, 101); expect_reply(12, 8, 202); expect_reply(14, 8, 303);
        packet(0, 4, 255, 0); packet(1, 4, 255, 0);
        packet(0, 5, 4, 0); packet(1, 5, 14, 0);
        drained();
        // Reuse the wire ID while a stale application handle still exists.
        packet(0, 3, 2, 7); packet(0, 6, 255, 0);
        expect_reply(4, 8, 33); packet(0, 5, 4, 0); drained();
        expect_reply(2, 8, 7); packet(0, 4, 255, 0); drained();
        // Failing one actor must not lose queued callers or stop its healthy neighbour.
        packet(0, 3, 1, 1); packet(1, 3, 11, 30);
        expect_reply(1, 1, 15); expect_reply(11, 8, 30); expect_reply(4, 1, 15);
        packet(0, 7, 255, 1); packet(0, 5, 4, 0); packet(1, 4, 255, 0);
        drained();
        expect_reply(4, 1, 15); expect_reply(14, 8, 333);
        packet(0, 5, 4, 0); packet(1, 5, 14, 0); drained();
        restart();
        expect_reply(4, 8, 0); expect_reply(14, 8, 0);
        packet(0, 5, 4, 0); packet(1, 5, 14, 0); drained();
        $display("PASS: shared retained calls, independent actors, stalled replies, failure and RAM reset (%0d replies)", received);
        $finish;
    end
    initial begin #3000000; $fatal(1, "shared reply timeout (%0d pending)", pending); end
endmodule
