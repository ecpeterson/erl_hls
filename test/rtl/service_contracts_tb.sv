`timescale 1ns/1ps
module service_contracts_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:4095];
    integer count = 0, received = 0, cycles = 0, tx = 0, n;
    reg [32:0] held;
    reg stalled = 0;
    reg [31:0] value = 7;

    __service__Top_0_next dut(.clk(clk), .reset(reset),
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
            if (received >= count || reply !== expected[received])
                $fatal(1, "reply beat %0d: got %h, expected %h", received, reply, expected[received]);
            received = received + 1;
        end
    end

    task automatic beat(input [31:0] word, input last);
        begin
            repeat (tx % 3) @(negedge clk);
            @(negedge clk); request = {last, word}; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask

    task automatic expect_beat(input [31:0] word, input last);
        begin expected[count] = {last, word}; count = count + 1; end
    endtask

    task automatic header(input [7:0] tag, input [7:0] words);
        begin expect_beat({tag, 8'd0, tx[7:0], words}, 0); end
    endtask

    task automatic query(input [31:0] mode, input [31:0] next_value);
        begin
            case (mode)
                0: begin
                    header(6, 1); expect_beat(next_value, 1); value = next_value;
                end
                1: begin
                    header(7, 2); expect_beat(next_value, 0); expect_beat(value, 1);
                    value = next_value;
                end
                2, 3: begin
                    header(1, 1);
                    // Body failures precede checking the returned record.
                    expect_beat(mode == 3 && next_value != 0 ? 2 : 15, 1);
                    value = 0; // Standard hls_gs callback-failure semantics.
                end
                default: begin header(1, 1); expect_beat(1, 1); value = 0; end
            endcase
            beat({8'd3, 8'd0, tx[7:0], 8'd2}, 0);
            beat(mode, 0); beat(next_value, 1); tx = tx + 1;
        end
    endtask

    task automatic read_state;
        begin
            header(6, 1); expect_beat(value, 1);
            beat({8'd4, 8'd0, tx[7:0], 8'd1}, 0); beat(0, 1); tx = tx + 1;
        end
    endtask

    task automatic change(input [31:0] next_value);
        begin
            beat({8'd5, 8'd0, 8'd255, 8'd1}, 0); beat(next_value, 1);
            value = next_value;
        end
    endtask

    task automatic nonrequest_tag;
        begin
            // Raw wire input bypasses the proxy's request-kind validation.
            header(1, 1); expect_beat(1, 1); value = 0;
            beat({8'd8, 8'd0, tx[7:0], 8'd1}, 0); beat(0, 1); tx = tx + 1;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk); reset = 0;
        read_state();
        for (n = 0; n < 32; n = n + 1) begin
            query(0, n + 10); query(1, n + 20); query(1, 0);
            change(81); read_state();
            query(2, 999); read_state();
            change(82); query(3, 1); read_state();
            query(3, 0); read_state();
            if (n == 0) nonrequest_tag(); else query(9, 0);
            read_state();
            // A schema-length error is pre-dispatch and preserves state.
            change(83); header(1, 1); expect_beat(3, 1);
            beat({8'd3, 8'd0, tx[7:0], 8'd1}, 0); beat(0, 1); tx = tx + 1;
            read_state();
        end
        while (received < count) @(negedge clk);
        repeat (100) @(negedge clk);
        $display("PASS: %0d service calls, alternative replies, contract faults, failure precedence, state, stalls and ID wrap", tx);
        $finish;
    end
    initial begin #5000000; $fatal(1, "service contracts timeout"); end
endmodule
