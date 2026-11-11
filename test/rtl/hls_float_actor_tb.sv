`timescale 1ns/1ps
module hls_float_actor_tb;
    localparam W = `FLOAT_WIDTH;
    localparam WORDS = (W + 31) / 32;
    localparam [W-1:0] INITIAL = `FLOAT_INITIAL;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:4095];
    reg [32:0] expected_mask [0:4095];
    reg [31:0] last_fault;
    integer expected_count = 0, received = 0, cycles = 0, txid = 0, vectors = 0;
    reg [32:0] held;
    reg stalled = 0;
    float_actor dut(.clk(clk), .reset(reset),
        ._ext_recv(request), ._ext_recv_vld(request_valid), ._ext_recv_rdy(request_ready),
        ._ext_send(reply), ._ext_send_vld(reply_valid), ._ext_send_rdy(reply_ready));

    always @(negedge clk) reply_ready = !reset && cycles % 17 >= 9;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held))
            $fatal(1, "reply changed under backpressure");
        held = reply;
        stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (received >= expected_count || (reply & expected_mask[received]) !== (expected[received] & expected_mask[received]))
                $fatal(1, "binary%0d reply beat %0d: got %h, expected %h", W, received, reply, expected[received]);
            if (reply[32] && expected_mask[received] != 33'h1ffffffff) last_fault = reply[31:0];
            received = received + 1;
        end
    end else stalled = 0;

    task beat(input [31:0] word, input last);
        begin
            @(negedge clk); request = {last, word}; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask

    task payload(input [W-1:0] value);
        integer i;
        begin
            for (i = 0; i < WORDS; i = i + 1) beat(value >> (32*i), i == WORDS-1);
        end
    endtask

    task expect_reply(input [W-1:0] value, input failed);
        integer i, n;
        reg [7:0] tag;
        begin
            n = failed ? 1 : WORDS;
            tag = failed ? 1 : 6;
            expected[expected_count] = {1'b0, tag, 8'd0, txid[7:0], n[7:0]};
            expected_mask[expected_count] = 33'h1ffffffff;
            expected_count = expected_count + 1;
            for (i = 0; i < n; i = i + 1) begin
                expected[expected_count] = {i == n-1, failed ? 32'hc000000d : 32'(value >> (32*i))};
                expected_mask[expected_count] = failed ? 33'h1ffff000f : 33'h1ffffffff;
                expected_count = expected_count + 1;
            end
        end
    endtask

    task restart;
        begin
            @(negedge clk); reset = 1; request_valid = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    task drained;
        begin
            while (received < expected_count) @(negedge clk);
            repeat (4) @(negedge clk);
        end
    endtask

    task read_state(input [W-1:0] value);
        begin
            expect_reply(value, 0);
            beat({8'd4, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
            txid = txid + 1;
            drained();
        end
    endtask

    task calculate(input [31:0] mode, input [W-1:0] x, y, value, input failed);
        begin
            // A public load message sets the accumulator before the operation.
            beat({8'd5, 8'd0, txid[7:0], 8'(WORDS)}, 0); payload(x);
            txid = txid + 1;
            expect_reply(value, failed);
            beat({8'd3, 8'd0, txid[7:0], 8'(WORDS+1)}, 0);
            beat(mode, 0); payload(y);
            txid = txid + 1;
            drained();
            if (failed) begin
                if (last_fault[15:4] == 0) $fatal(1, "float failure lost source identity");
                expect_reply(0, 1);
                expected[expected_count - 1] = {1'b1, last_fault};
                expected_mask[expected_count - 1] = 33'h1ffffffff;
                beat({8'd4, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
                txid = txid + 1; drained();
                restart(); read_state(INITIAL);
            end else read_state(value);
            vectors = vectors + 1;
        end
    endtask

    initial begin
        restart();
        read_state(INITIAL);
        `include `FLOAT_ACTOR_VECTORS
        repeat (50) @(negedge clk);
        $display("PASS: binary%0d, %0d public actor requests, reset, terminal overflow and coordinated reset and stalled replies", W, vectors);
        $finish;
    end
    initial begin #2000000; $fatal(1, "float actor timeout"); end
endmodule
