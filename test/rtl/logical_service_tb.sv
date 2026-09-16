`timescale 1ns/1ps
module logical_service_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:8191];
    reg [32:0] held, word;
    reg stalled = 0;
    integer count = 0, received = 0, sent = 0, cycles = 0, fd, fields;
    string requests, replies;
    __service__Top_0_next dut(.clk(clk), .reset(reset),
        ._ext_recv(request), ._ext_recv_vld(request_valid), ._ext_recv_rdy(request_ready),
        ._ext_send(reply), ._ext_send_vld(reply_valid), ._ext_send_rdy(reply_ready));

    always @(negedge clk) reply_ready = !reset && cycles % 23 >= 13;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held))
            $fatal(1, "reply changed under backpressure");
        held = reply;
        stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (received >= count || reply !== expected[received])
                $fatal(1, "reply beat %0d got=%h expected=%h", received, reply, expected[received]);
            received = received + 1;
        end
    end
    initial begin
        if (!$value$plusargs("requests=%s", requests) || !$value$plusargs("replies=%s", replies))
            $fatal(1, "missing vectors");
        fd = $fopen(replies, "r");
        if (!fd) $fatal(1, "cannot read replies");
        while (!$feof(fd)) begin
            fields = $fscanf(fd, "%h\n", word);
            if (fields != 1 || count >= 8192) $fatal(1, "invalid replies");
            expected[count] = word;
            count = count + 1;
        end
        $fclose(fd);
        if (!count) $fatal(1, "empty replies");
        repeat (5) @(negedge clk); reset = 0;
        fd = $fopen(requests, "r");
        if (!fd) $fatal(1, "cannot read requests");
        while (!$feof(fd)) begin
            fields = $fscanf(fd, "%h\n", word);
            if (fields != 1) $fatal(1, "invalid requests");
            repeat (sent % 3) @(negedge clk);
            @(negedge clk); request = word; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
            sent = sent + 1;
        end
        $fclose(fd);
        wait(received == count);
        repeat (100) @(posedge clk);
        $display("PASS: %0d request beats, %0d BEAM/RTL reply beats with stalls", sent, received);
        $finish;
    end
    initial begin #2000000; $fatal(1, "timeout: received %0d/%0d", received, count); end
endmodule
