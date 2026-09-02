`timescale 1ns/1ps

module phenom_data_cell_tb;
    localparam integer MEASUREMENT = 4;

    localparam [7:0] PHENOM_CONFIG_TAG = 8'd6;
    localparam [7:0] PHENOM_QUERY_TAG = 8'd8;
    localparam [7:0] PAULI_QUERY_TAG = 8'd13;
    localparam [7:0] PAULI_REPLY_TAG = 8'd14;
    localparam [7:0] NOISE_CUTOFF_TAG = 8'd15;
    localparam [7:0] PAULI_UPDATE_TAG = 8'd16;

    localparam [31:0] NORTH_MASK = 32'd1;
    localparam [31:0] EAST_MASK = 32'd2;
    localparam [31:0] WEST_MASK = 32'd4;
    localparam [31:0] SOUTH_MASK = 32'd8;
    localparam [31:0] PAULI_X = 32'd2;
    localparam [31:0] PAULI_Z = 32'd1;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat [0:4];
    wire [4:0] output_valid;
    wire [4:0] output_ready = 5'b11111;

    reg [32:0] captured [0:11];
    integer beat_count = 0;

    __phenom_data_cell__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        ._ext_recv({input_last, input_data}),
        ._ext_recv_vld(input_valid),
        ._ext_recv_rdy(input_ready),
        ._north_send_rdy(output_ready[0]),
        ._north_send(output_beat[0]),
        ._north_send_vld(output_valid[0]),
        ._east_send_rdy(output_ready[1]),
        ._east_send(output_beat[1]),
        ._east_send_vld(output_valid[1]),
        ._west_send_rdy(output_ready[2]),
        ._west_send(output_beat[2]),
        ._west_send_vld(output_valid[2]),
        ._south_send_rdy(output_ready[3]),
        ._south_send(output_beat[3]),
        ._south_send_vld(output_valid[3]),
        ._measurement_send_rdy(output_ready[MEASUREMENT]),
        ._measurement_send(output_beat[MEASUREMENT]),
        ._measurement_send_vld(output_valid[MEASUREMENT])
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && output_valid[MEASUREMENT] &&
                output_ready[MEASUREMENT]) begin
            captured[beat_count] <= output_beat[MEASUREMENT];
            beat_count <= beat_count + 1;
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

    task automatic send_config;
        begin
            send_beat(header(PHENOM_CONFIG_TAG, 8'd3), 1'b0);
            send_beat(32'h6d2b79f5, 1'b0);
            send_beat(32'hffffffff, 1'b0);
            send_beat({16'd17, 16'd13}, 1'b1);
        end
    endtask

    task automatic send_neighbor_query;
        input [31:0] step;
        input [31:0] source;
        begin
            send_beat(header(PHENOM_QUERY_TAG, 8'd2), 1'b0);
            send_beat(step, 1'b0);
            send_beat(source, 1'b1);
        end
    endtask

    task automatic complete_round;
        input [31:0] step;
        begin
            send_neighbor_query(step, NORTH_MASK);
            send_neighbor_query(step, EAST_MASK);
            send_neighbor_query(step, WEST_MASK);
            send_neighbor_query(step, SOUTH_MASK);
        end
    endtask

    task automatic send_pauli_query;
        input [31:0] request_id;
        input [31:0] measurement;
        begin
            send_beat(header(PAULI_QUERY_TAG, 8'd2), 1'b0);
            send_beat(request_id, 1'b0);
            send_beat(measurement, 1'b1);
        end
    endtask

    task automatic send_noise_cutoff;
        input [31:0] first_quiet_step;
        begin
            send_beat(header(NOISE_CUTOFF_TAG, 8'd1), 1'b0);
            send_beat(first_quiet_step, 1'b1);
        end
    endtask

    task automatic send_pauli_update;
        input [31:0] pauli;
        begin
            send_beat(header(PAULI_UPDATE_TAG, 8'd1), 1'b0);
            send_beat(pauli, 1'b1);
        end
    endtask

    task automatic wait_for_count;
        input integer target;
        integer cycle;
        begin
            for (cycle = 0;
                    cycle < 10000 && beat_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (beat_count < target) begin
                $display("FAIL: timed out waiting for Pauli reply beat %0d",
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
                    "FAIL: reply beat %0d expected %x/%0d, got %x/%0d",
                    index, expected_word, expected_last,
                    captured[index][31:0], captured[index][32]
                );
                $fatal(1);
            end
        end
    endtask

    task automatic check_reply;
        input integer base;
        input [31:0] request_id;
        input [31:0] anticommutes;
        begin
            check_beat(base + 0, header(PAULI_REPLY_TAG, 8'd3), 1'b0);
            check_beat(base + 1, request_id, 1'b0);
            check_beat(base + 2, {16'd17, 16'd13}, 1'b0);
            check_beat(base + 3, anticommutes, 1'b1);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        send_config();
        complete_round(32'd0);
        send_noise_cutoff(32'd1);
        complete_round(32'd1);

        send_pauli_query(32'd101, PAULI_X);
        send_pauli_query(32'd102, PAULI_Z);
        wait_for_count(8);
        check_reply(0, 32'd101, 32'd1);
        check_reply(4, 32'd102, 32'd1);

        // A point-addressed decoder X update turns the accumulated Y into Z.
        send_pauli_update(PAULI_X);
        send_pauli_query(32'd103, PAULI_Z);
        wait_for_count(12);
        check_reply(8, 32'd103, 32'd0);

        $display("PASS: generated data-cell cutoff/update/query protocol");
        $finish;
    end
endmodule
