`timescale 1ns/1ps

module hls_statem_reduction_error_tb;
`ifndef REDUCTION_DUT
`define REDUCTION_DUT __hls_statem_reduction_rtl_fixture__Top_0_next
`endif
    localparam [7:0] COUNT_VALUE_TAG = 8'd3;
    localparam [7:0] MEMBER_VALUE_TAG = 8'd4;
    localparam [7:0] ESCAPE_TAG = 8'd6;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat;
    wire output_valid;
    reg output_ready = 1'b1;

    integer beat_count = 0;
    integer cycle;
`ifdef REDUCTION_SHARED
    integer fold_retire_count = 0;
    integer folds_after_failure;
    wire fold_retired =
        dut.__hls_statem_reduction_rtl_fixture__SharedService_0__1_0_1_0_next_inst.fold_wins;
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
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            beat_count <= 0;
`ifdef REDUCTION_SHARED
            fold_retire_count <= 0;
`endif
        end else begin
            if (output_valid && output_ready)
                beat_count <= beat_count + 1;
`ifdef REDUCTION_SHARED
            if (fold_retired)
                fold_retire_count <= fold_retire_count + 1;
`endif
        end
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

    task automatic send_escape;
        begin
            send_beat(header(ESCAPE_TAG, 8'd0), 1'b1);
        end
    endtask

    task automatic wait_for_beats;
        input integer target;
        begin
            for (cycle = 0; cycle < 2000 && beat_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (beat_count < target) begin
                $display("FAIL: timed out waiting for %0d beats", target);
                $fatal(1);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            reset = 1'b1;
            input_data = 32'b0;
            input_last = 1'b0;
            input_valid = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Leaving COUNTING with one of two contributions accepted must fail,
        // so DONE's four-beat observation must never be emitted.
        send_count(32'd17, 32'd1);
        send_escape();
        repeat (1000) @(posedge clk);
        if (beat_count != 0) begin
            $display(
                "FAIL: incomplete reduction crossed a phase boundary (%0d beats)",
                beat_count
            );
            $fatal(1);
        end

        reset_dut();

        // Reach fixed-member mode, then make the third contribution repeat an
        // already-seen member.  If it were incorrectly accepted as the third
        // member, DONE would emit another four beats.
        send_count(32'd17, 32'd11);
        send_count(32'd17, 32'd5);
        wait_for_beats(4);
        send_member(32'd17, 32'd9, 32'd1);
        send_member(32'd17, 32'd2, 32'd2);
        send_member(32'd17, 32'd9, 32'd100);
        repeat (1000) @(posedge clk);
        if (beat_count != 4) begin
            $display(
                "FAIL: duplicate member completed reduction (%0d beats)",
                beat_count
            );
            $fatal(1);
        end
`ifdef REDUCTION_SHARED
        // Failure retires and disables the actor's register receptacle. A
        // later contribution may enter the mailbox, but must not be consumed
        // by the mailbox-head fold path without an ordinary actor visit.
        folds_after_failure = fold_retire_count;
        send_member(32'd17, 32'd7, 32'd3);
        repeat (200) @(posedge clk);
        if (fold_retire_count != folds_after_failure) begin
            $display(
                "FAIL: reduction receptacle remained active after actor failure"
            );
            $fatal(1);
        end
`endif
        $display(
            "PASS: incomplete boundary and duplicate member failed the actor"
        );
        $finish;
    end
endmodule
