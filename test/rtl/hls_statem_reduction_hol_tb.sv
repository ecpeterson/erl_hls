`timescale 1ns/1ps

module hls_statem_reduction_hol_tb;
`ifndef REDUCTION_HOL_DUT
`define REDUCTION_HOL_DUT __hls_statem_reduction_hol_top__Top_0_next
`endif
    localparam [7:0] COUNT_VALUE_TAG = 8'd3;
    localparam [7:0] MEMBER_VALUE_TAG = 8'd4;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat;
    wire output_valid;
    reg output_ready = 1'b1;

    wire [31:0] state_write_probe;
    wire state_write_probe_valid;
    reg state_write_probe_ready = 1'b1;

    wire [31:0] state_read_probe;
    wire state_read_probe_valid;
    reg state_read_probe_ready = 1'b1;

    integer output_beat_count = 0;
    integer cycle_count = 0;
    reg watch_actor_one = 1'b0;
    reg actor_one_fold_retired = 1'b0;
    reg watch_actor_one_read = 1'b0;
    reg actor_one_nonfold_probed = 1'b0;
    reg watch_actor_two = 1'b0;
    reg actor_two_fold_retired = 1'b0;

    `REDUCTION_HOL_DUT dut (
        .clk(clk),
        .reset(reset),
        ._ext_recv({input_last, input_data}),
        ._ext_recv_vld(input_valid),
        ._ext_recv_rdy(input_ready),
        ._out_send_rdy(output_ready),
        ._out_send(output_beat),
        ._out_send_vld(output_valid),
        ._state_read_probe_rdy(state_read_probe_ready),
        ._state_read_probe(state_read_probe),
        ._state_read_probe_vld(state_read_probe_valid),
        ._state_write_probe_rdy(state_write_probe_ready),
        ._state_write_probe(state_write_probe),
        ._state_write_probe_vld(state_write_probe_valid)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            cycle_count <= cycle_count + 1;
            if (output_valid && output_ready)
                output_beat_count <= output_beat_count + 1;
            if (watch_actor_one && state_write_probe_valid &&
                    state_write_probe_ready && state_write_probe == 32'd1)
                actor_one_fold_retired <= 1'b1;
            if (watch_actor_one_read && state_read_probe_valid &&
                    state_read_probe_ready && state_read_probe == 32'd1)
                actor_one_nonfold_probed <= 1'b1;
            if (watch_actor_two && state_write_probe_valid &&
                    state_write_probe_ready && state_write_probe == 32'd2)
                actor_two_fold_retired <= 1'b1;
        end
    end

    function automatic [31:0] header;
        input [7:0] tag;
        input [7:0] actor;
        input [7:0] payload_words;
        begin
            // The harness uses txid as the destination actor slot.
            header = {tag, 8'h00, actor, payload_words};
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
        input [7:0] actor;
        input [31:0] key;
        input [31:0] value;
        begin
            send_beat(header(COUNT_VALUE_TAG, actor, 8'd2), 1'b0);
            send_beat(key, 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic send_member;
        input [7:0] actor;
        input [31:0] key;
        input [31:0] member;
        input [31:0] value;
        begin
            send_beat(header(MEMBER_VALUE_TAG, actor, 8'd3), 1'b0);
            send_beat(key, 1'b0);
            send_beat(member, 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic wait_for_output_beats;
        input integer target;
        integer cycle;
        begin
            for (cycle = 0; cycle < 2000 && output_beat_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (output_beat_count < target) begin
                $display("FAIL: first effect batch never reached its sink");
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Allow both actors to run initial entry and open their count reducers.
        repeat (100) @(posedge clk);

        // Actor zero's first completion enters collecting_members and emits
        // one observation. The harness drains that batch but never returns
        // its effect-window credit.
        send_count(8'd0, 32'd17, 32'd11);
        send_count(8'd0, 32'd17, 32'd5);
        wait_for_output_beats(4);

        // Local folds remain legal while the first effect batch owns credit.
        // Completing this second reduction creates an ordinary executor
        // result with another effect batch, which must now remain buffered.
        send_member(8'd0, 32'd17, 32'd7, 32'd4);
        send_member(8'd0, 32'd17, 32'd9, 32'd1);
        send_member(8'd0, 32'd17, 32'd2, 32'd2);
        repeat (300) @(posedge clk);

        // No old actor-one write can satisfy the observation after this edge.
        watch_actor_one = 1'b1;
        send_count(8'd1, 32'd17, 32'd3);

        // Actor one's selected contribution needs neither the held effect
        // credit nor the executor. It must fold, retire, and free its mailbox
        // slot even while actor zero's older ordinary result stays blocked.
        repeat (500) @(posedge clk);
        if (!actor_one_fold_retired) begin
            $display(
                "FAIL: blocked ordinary result globally stopped actor-one fold"
            );
            $fatal(1);
        end

        // Actor one is still in its count phase. A member contribution is
        // therefore an ordinary (non-foldable) mailbox head. Under the same
        // blocked effect epoch the scheduler must probe it once, roll back
        // its speculative ownership, and continue looking for local work.
        watch_actor_one_read = 1'b1;
        send_member(8'd1, 32'd17, 32'd9, 32'd99);
        repeat (300) @(posedge clk);
        if (!actor_one_nonfold_probed) begin
            $display("FAIL: actor-one non-contribution was not probed");
            $fatal(1);
        end

        // Enqueue the progress-making fold only after observing the failed
        // probe. Actor one's blocked-probed bit must prevent that earlier
        // head from starving actor two.
        watch_actor_two = 1'b1;
        send_count(8'd2, 32'd17, 32'd13);
        repeat (500) @(posedge clk);
        if (!actor_two_fold_retired) begin
            $display(
                "FAIL: non-contribution probe starved actor-two local fold"
            );
            $fatal(1);
        end

        $display(
            "PASS: blocked probing skipped a nonfold head and retired a later fold"
        );
        $finish;
    end
endmodule
