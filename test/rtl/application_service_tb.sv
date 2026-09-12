`timescale 1ns/1ps
module application_service_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:1023];
    integer expected_count = 0, received = 0, cycles = 0;
    integer declared, actual, txid = 0;
    reg [31:0] value = 42;
    reg [32:0] held;
    reg stalled = 0;

    application_service dut(.clk(clk), .reset(reset),
        ._ext_recv(request), ._ext_recv_vld(request_valid), ._ext_recv_rdy(request_ready),
        ._ext_send(reply), ._ext_send_vld(reply_valid), ._ext_send_rdy(reply_ready));

    always @(negedge clk) reply_ready = !reset && cycles % 13 >= 7;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held))
            $fatal(1, "application reply changed under backpressure");
        held = reply;
        stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (received >= expected_count || reply !== expected[received])
                $fatal(1, "reply beat %0d: got %h, expected %h", received, reply, expected[received]);
            received = received + 1;
        end
    end

    task automatic beat(input [31:0] word, input last);
        begin
            @(negedge clk); request = {last, word}; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask

    task automatic packet(input [7:0] tag, input integer length,
        input integer count, input [31:0] payload);
        integer i;
        begin
            beat({tag, 8'h00, txid[7:0], length[7:0]}, count == 0);
            for (i = 0; i < count; i = i + 1) beat(payload + i, i + 1 == count);
            txid = txid + 1;
        end
    endtask

    task automatic expect_beat(input [31:0] word, input last);
        begin
            expected[expected_count] = {last, word};
            expected_count = expected_count + 1;
        end
    endtask

    task automatic drained;
        begin
            while (received < expected_count) @(negedge clk);
            repeat (20) @(negedge clk);
        end
    endtask

    task automatic query;
        begin
            expect_beat({8'd5, 8'd0, txid[7:0], 8'd2}, 0);
            expect_beat(value, 0);
            expect_beat(0, 1);
            packet(3, 1, 1, 0);
            drained();
        end
    endtask

    initial begin
        repeat (5) @(negedge clk); reset = 0;
        query();
        // A complete packet still needs to match its callback's wire schema.
        // Short/long changes must not reach handle_cast or alter the ledger.
        for (declared = 0; declared <= 5; declared = declared + 1) begin
            for (actual = 0; actual <= 5; actual = actual + 1) begin
                if (declared == actual && declared <= 3) begin
                    if (declared == 1) value = 99;
                    else begin
                        expect_beat({8'd1, 8'd0, txid[7:0], 8'd1}, 0);
                        expect_beat(3, 1); // request_length, preserving state
                    end
                end
                packet(4, declared, actual, 99);
                drained();
                query();
            end
        end
        // A call with the wrong schema length also returns the typed error.
        expect_beat({8'd1, 8'd0, txid[7:0], 8'd1}, 0);
        expect_beat(3, 1);
        packet(3, 0, 0, 0);
        drained(); query();
        packet(4, 1, 257, 0);
        query();
        repeat (100) @(negedge clk);
        $display("PASS: generated hls_gs framing, schema errors, txids and state conservation");
        $finish;
    end
    initial begin #2000000; $fatal(1, "application service timeout"); end
endmodule
