`timescale 1ns/1ps

module hls_statem_reduction_tb;
`ifndef REDUCTION_DUT
`define REDUCTION_DUT __hls_statem_reduction_rtl_fixture__Top_0_next
`endif
    localparam [7:0] COUNT_VALUE_TAG = 8'd3;
    localparam [7:0] MEMBER_VALUE_TAG = 8'd4;
    localparam [7:0] OBSERVATION_TAG = 8'd5;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat;
    wire output_valid;
    reg output_ready = 1'b1;

    reg [32:0] captured [0:7];
    integer beat_count = 0;
`ifdef REDUCTION_SHARED
    wire [31:0] mailbox_write_probe;
    wire mailbox_write_probe_valid;
    integer mailbox_write_count = 0;
`endif

    `REDUCTION_DUT dut (
        .clk(clk),
        .reset(reset),
        ._ext_recv({input_last, input_data}),
        ._ext_recv_vld(input_valid),
        ._ext_recv_rdy(input_ready),
        ._out_send_rdy(output_ready),
        ._out_send(output_beat),
        ._out_send_vld(output_valid)
`ifdef REDUCTION_SHARED
        ,._mailbox_write_probe_rdy(1'b1)
        ,._mailbox_write_probe(mailbox_write_probe)
        ,._mailbox_write_probe_vld(mailbox_write_probe_valid)
`endif
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && output_valid && output_ready) begin
            captured[beat_count] <= output_beat;
            beat_count <= beat_count + 1;
        end
`ifdef REDUCTION_SHARED
        if (reset)
            mailbox_write_count <= 0;
        else if (mailbox_write_probe_valid)
            mailbox_write_count <= mailbox_write_count + 1;
`endif
    end

    function automatic [31:0] header;
        input [7:0] tag;
        input [7:0] payload_words;
        begin
            header = {tag, 8'h00, 8'h00, payload_words};
        end
    endfunction

    task automatic send_beat;
        input [31:0] word;
        input last;
        begin
            @(negedge clk);
            input_data = word;
            input_last = last;
            input_valid = 1'b1;
            while (!input_ready)
                @(posedge clk);
            @(negedge clk);
            input_data = 32'b0;
            input_last = 1'b0;
            input_valid = 1'b0;
        end
    endtask

    task automatic send_count;
        input [31:0] key;
        input [31:0] value;
        begin
            send_beat(header(COUNT_VALUE_TAG, 8'd2), 1'b0);
            send_beat(key, 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic send_member;
        input [31:0] key;
        input [31:0] member;
        input [31:0] value;
        begin
            send_beat(header(MEMBER_VALUE_TAG, 8'd3), 1'b0);
            send_beat(key, 1'b0);
            send_beat(member, 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic wait_for_count;
        input integer target;
        integer cycle;
        begin
            for (cycle = 0; cycle < 2000 && beat_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (beat_count < target) begin
                $display("FAIL: timed out waiting for reduction output %0d",
                    target);
                $fatal(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic check_beat;
        input integer index;
        input [31:0] expected_word;
        input expected_last;
        begin
            if (captured[index][31:0] !== expected_word ||
                    captured[index][32] !== expected_last) begin
                $display(
                    "FAIL: beat %0d expected %x/%0d, got %x/%0d",
                    index, expected_word, expected_last,
                    captured[index][31:0], captured[index][32]
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // A next-epoch value arrives early.  It must be postponed while key
        // 17 is open, then retried after the 99-total completion repeats the
        // phase and opens key 18.
        send_count(32'd18, 32'd5);
        send_count(32'd17, 32'd44);
        send_count(32'd17, 32'd55);
        send_count(32'd18, 32'd6);
        wait_for_count(4);
        check_beat(0, header(OBSERVATION_TAG, 8'd3), 1'b0);
        check_beat(1, 32'd31, 1'b0);
        check_beat(2, 32'd11, 1'b0);
        check_beat(3, 32'd0, 1'b1);

        // The declared universe is [9, 2, 7], but arrival order is free.
        send_member(32'd18, 32'd7, 32'd4);
        send_member(32'd18, 32'd9, 32'd1);
        send_member(32'd18, 32'd2, 32'd2);
        wait_for_count(8);
        check_beat(4, header(OBSERVATION_TAG, 8'd3), 1'b0);
        check_beat(5, 32'd32, 1'b0);
        check_beat(6, 32'd11, 1'b0);
        check_beat(7, 32'd7, 1'b1);

`ifdef REDUCTION_SHARED
        // Only the deliberately early key-18 message should fall back to the
        // mailbox. The other six contributions must use the direct fold.
        if (mailbox_write_count != 1) begin
            $display("FAIL: expected one mailbox fallback, got %0d",
                mailbox_write_count);
            $fatal(1);
        end
`endif
        $display(
            "PASS: reductions atomically installed entry data and open state"
        );
        $finish;
    end
endmodule
