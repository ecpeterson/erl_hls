`timescale 1ns/1ps

module phi_halo_cell_tb;
    localparam integer NORTH = 0;
    localparam integer EAST  = 1;
    localparam integer WEST  = 2;
    localparam integer SOUTH = 3;
    localparam integer SYNDROME = 4;
    localparam integer CORRECTION = 5;
    localparam integer STATUS = 6;

    localparam [31:0] NORTH_MASK = 32'd1;
    localparam [31:0] EAST_MASK  = 32'd2;
    localparam [31:0] WEST_MASK  = 32'd4;
    localparam [31:0] SOUTH_MASK = 32'd8;
    localparam [7:0] PHI_CONFIG_TAG = 8'd12;
    localparam [31:0] PHI_PRNG_SEED = 32'h6d2b79f5;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat [0:6];
    wire [6:0] output_valid;
    reg [6:0] output_ready = 7'b0000000;

    reg [32:0] captured [0:6][0:255];
    integer beat_count [0:6];
    integer port_index;
    integer check_port;
    reg [32:0] stalled_beat;
    reg check_south_stall = 1'b0;
    reg check_east_stall = 1'b0;

    __phi_halo_cell__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        ._ext_recv({input_last, input_data}),
        ._ext_recv_vld(input_valid),
        ._ext_recv_rdy(input_ready),
        ._north_send_rdy(output_ready[NORTH]),
        ._north_send(output_beat[NORTH]),
        ._north_send_vld(output_valid[NORTH]),
        ._east_send_rdy(output_ready[EAST]),
        ._east_send(output_beat[EAST]),
        ._east_send_vld(output_valid[EAST]),
        ._west_send_rdy(output_ready[WEST]),
        ._west_send(output_beat[WEST]),
        ._west_send_vld(output_valid[WEST]),
        ._south_send_rdy(output_ready[SOUTH]),
        ._south_send(output_beat[SOUTH]),
        ._south_send_vld(output_valid[SOUTH]),
        ._syndrome_send_rdy(output_ready[SYNDROME]),
        ._syndrome_send(output_beat[SYNDROME]),
        ._syndrome_send_vld(output_valid[SYNDROME]),
        ._correction_send_rdy(output_ready[CORRECTION]),
        ._correction_send(output_beat[CORRECTION]),
        ._correction_send_vld(output_valid[CORRECTION]),
        ._status_send_rdy(output_ready[STATUS]),
        ._status_send(output_beat[STATUS]),
        ._status_send_vld(output_valid[STATUS])
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            for (port_index = 0; port_index < 7; port_index = port_index + 1) begin
                if (output_valid[port_index] && output_ready[port_index]) begin
                    captured[port_index][beat_count[port_index]] <=
                        output_beat[port_index];
                    beat_count[port_index] <= beat_count[port_index] + 1;
                end
            end
            if (check_south_stall) begin
                if (!output_valid[SOUTH]) begin
                    $display("FAIL: stalled south output dropped valid");
                    $fatal(1);
                end
                if (output_beat[SOUTH] !== stalled_beat) begin
                    $display("FAIL: stalled south output was not stable");
                    $fatal(1);
                end
            end
            if (check_east_stall) begin
                if (!output_valid[EAST]) begin
                    $display("FAIL: stalled east output dropped valid");
                    $fatal(1);
                end
                if (output_beat[EAST] !== stalled_beat) begin
                    $display("FAIL: stalled east output was not stable");
                    $fatal(1);
                end
            end
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

    task automatic send_phi;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            send_beat(header(8'd3, 8'd3), 1'b0);
            send_beat(epoch, 1'b0);
            // Fixed arrays put element zero in the most-significant bits.
            send_beat(layer_one, 1'b0);
            send_beat(layer_zero, 1'b1);
        end
    endtask

    task automatic send_uniform_phi;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            send_phi(epoch, layer_zero, layer_one);
            send_phi(epoch, layer_zero, layer_one);
            send_phi(epoch, layer_zero, layer_one);
            send_phi(epoch, layer_zero, layer_one);
        end
    endtask

    task automatic send_config;
        input [31:0] seed;
        begin
            send_beat(header(PHI_CONFIG_TAG, 8'd1), 1'b0);
            send_beat(seed, 1'b1);
        end
    endtask

    task automatic send_anyon;
        input [31:0] step;
        input [31:0] present;
        begin
            send_beat(header(8'd4, 8'd2), 1'b0);
            send_beat(step, 1'b0);
            send_beat(present, 1'b1);
        end
    endtask

    task automatic send_phi0;
        input [31:0] step;
        input [31:0] source;
        input [31:0] value;
        begin
            send_beat(header(8'd5, 8'd3), 1'b0);
            send_beat(step, 1'b0);
            send_beat(source, 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic send_measurement;
        input [31:0] step;
        input [31:0] present;
        begin
            send_beat(header(8'd10, 8'd3), 1'b0);
            send_beat(step, 1'b0);
            send_beat(present, 1'b0);
            // This direct actor fixture always measures the origin cell.
            send_beat(32'd0, 1'b1);
        end
    endtask

    task automatic wait_for_count;
        input integer port;
        input integer target;
        begin
            while (beat_count[port] < target)
                @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic check_beat;
        input integer port;
        input integer index;
        input [31:0] expected_word;
        input expected_last;
        begin
            if (captured[port][index][31:0] !== expected_word) begin
                $display("FAIL: port %0d beat %0d expected %08x, got %08x",
                         port, index, expected_word,
                         captured[port][index][31:0]);
                $fatal(1);
            end
            if (captured[port][index][32] !== expected_last) begin
                $display("FAIL: port %0d beat %0d TLAST mismatch", port, index);
                $fatal(1);
            end
        end
    endtask

    task automatic check_phi;
        input integer port;
        input integer base;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            check_beat(port, base + 0, header(8'd3, 8'd3), 1'b0);
            check_beat(port, base + 1, epoch, 1'b0);
            check_beat(port, base + 2, layer_one, 1'b0);
            check_beat(port, base + 3, layer_zero, 1'b1);
        end
    endtask

    task automatic check_anyon;
        input integer port;
        input integer base;
        input [31:0] step;
        input [31:0] present;
        begin
            check_beat(port, base + 0, header(8'd4, 8'd2), 1'b0);
            check_beat(port, base + 1, step, 1'b0);
            check_beat(port, base + 2, present, 1'b1);
        end
    endtask

    task automatic check_phi0;
        input integer port;
        input integer base;
        input [31:0] step;
        input [31:0] source;
        input [31:0] value;
        begin
            check_beat(port, base + 0, header(8'd5, 8'd3), 1'b0);
            check_beat(port, base + 1, step, 1'b0);
            check_beat(port, base + 2, source, 1'b0);
            check_beat(port, base + 3, value, 1'b1);
        end
    endtask

    task automatic check_correction;
        input integer base;
        input [31:0] step;
        input [31:0] direction;
        begin
            check_beat(CORRECTION, base + 0, header(8'd11, 8'd3), 1'b0);
            check_beat(CORRECTION, base + 1, step, 1'b0);
            check_beat(CORRECTION, base + 2, 32'd0, 1'b0);
            check_beat(CORRECTION, base + 3, direction, 1'b1);
        end
    endtask

    task automatic check_status;
        input integer base;
        input [31:0] step;
        input [31:0] flags;
        begin
            check_beat(STATUS, base + 0, header(8'd17, 8'd3), 1'b0);
            check_beat(STATUS, base + 1, step, 1'b0);
            // This direct actor fixture always uses the origin coordinate.
            check_beat(STATUS, base + 2, 32'd0, 1'b0);
            check_beat(STATUS, base + 3, flags, 1'b1);
        end
    endtask

    task automatic expect_measurement_request;
        input integer base;
        input [31:0] step;
        begin
            wait_for_count(SYNDROME, base + 2);
            check_beat(
                SYNDROME,
                base + 0,
                header(8'd7, 8'd1),
                1'b0
            );
            check_beat(SYNDROME, base + 1, step, 1'b1);
        end
    endtask

    task automatic expect_all_phi;
        input integer base;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        integer port;
        begin
            for (port = 0; port < 4; port = port + 1) begin
                wait_for_count(port, base + 4);
                check_phi(port, base, epoch, layer_zero, layer_one);
            end
        end
    endtask

    task automatic advance_uniform_phi;
        input [31:0] epoch;
        input [31:0] neighbor_zero;
        input [31:0] neighbor_one;
        input integer base;
        input [31:0] expected_zero;
        input [31:0] expected_one;
        begin
            send_uniform_phi(epoch, neighbor_zero, neighbor_one);
            expect_all_phi(
                base, epoch + 32'd1, expected_zero, expected_one);
        end
    endtask

    initial begin : watchdog
        #5000000;
        $display("FAIL: phi cell simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        for (port_index = 0; port_index < 7; port_index = port_index + 1)
            beat_count[port_index] = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        output_ready = 7'b1111111;
        send_config(PHI_PRNG_SEED);
        expect_measurement_request(0, 32'd0);
        if (beat_count[STATUS] != 0) begin
            $display("FAIL: initial measuring entry emitted a status");
            $fatal(1);
        end
        send_measurement(32'd0, 32'd0);
        expect_all_phi(0, 32'd0, 32'd0, 32'd0);

        // Complete the first canonical rounded diffusion round. Repeating
        // gathering emits [13, 19] at epoch one before another message can
        // dispatch.
        send_phi(32'd0, 32'd32, 32'd48);
        send_phi(32'd0, 32'd64, 32'd80);
        send_phi(32'd0, 32'd16, 32'd32);
        send_phi(32'd0, 32'd48, 32'd64);
        expect_all_phi(4, 32'd1, 32'd13, 32'd19);

        // A complete early comparison batch occupies four of the five
        // mailbox slots. Each current diffusion message must enter and leave
        // through the fifth reserved progress slot. Distinct receiver-local
        // source masks make east the unique neighboring maximum.
        send_phi0(32'd0, NORTH_MASK, 32'd14);
        send_phi0(32'd0, EAST_MASK, 32'd18);
        send_phi0(32'd0, WEST_MASK, 32'd17);
        send_phi0(32'd0, SOUTH_MASK, 32'd16);

        // Advance through the remaining nonterminal rounds. The field settles
        // at [20, 29] before the twelfth round enters comparison.
        advance_uniform_phi(32'd1, 32'd16, 32'd32,
                            8, 32'd15, 32'd23);
        advance_uniform_phi(32'd2, 32'd16, 32'd32,
                            12, 32'd17, 32'd25);
        advance_uniform_phi(32'd3, 32'd16, 32'd32,
                            16, 32'd18, 32'd27);
        advance_uniform_phi(32'd4, 32'd16, 32'd32,
                            20, 32'd19, 32'd28);
        advance_uniform_phi(32'd5, 32'd16, 32'd32,
                            24, 32'd20, 32'd29);
        advance_uniform_phi(32'd6, 32'd16, 32'd32,
                            28, 32'd20, 32'd29);
        advance_uniform_phi(32'd7, 32'd16, 32'd32,
                            32, 32'd20, 32'd29);
        advance_uniform_phi(32'd8, 32'd16, 32'd32,
                            36, 32'd20, 32'd29);
        advance_uniform_phi(32'd9, 32'd16, 32'd32,
                            40, 32'd20, 32'd29);
        advance_uniform_phi(32'd10, 32'd16, 32'd32,
                            44, 32'd20, 32'd29);

        // Independently stall south's wire output while the other three ports
        // complete theirs. Its transmitter retains the comparison frame, so
        // the staged inputs can still enter flipping and queue that phase's
        // frame behind it without replaying any completed port.
        output_ready[SOUTH] = 1'b0;
        send_uniform_phi(32'd11, 32'd16, 32'd32);

        while (!output_valid[SOUTH])
            @(posedge clk);
        @(negedge clk);
        stalled_beat = output_beat[SOUTH];
        if (stalled_beat !== {1'b0, header(8'd5, 8'd3)}) begin
            $display("FAIL: south did not stall on the PHI0 header");
            $fatal(1);
        end
        check_south_stall = 1'b1;

        wait_for_count(NORTH, 55);
        wait_for_count(EAST, 55);
        wait_for_count(WEST, 55);
        repeat (8) @(posedge clk);
        for (check_port = NORTH; check_port <= WEST;
                check_port = check_port + 1) begin
            if (beat_count[check_port] != 55) begin
                $display("FAIL: Service replayed an accepted output");
                $fatal(1);
            end
            check_anyon(check_port, 52, 32'd0, 32'd0);
        end
        check_phi0(NORTH, 48, 32'd0, SOUTH_MASK, 32'd20);
        check_phi0(EAST, 48, 32'd0, WEST_MASK, 32'd20);
        check_phi0(WEST, 48, 32'd0, EAST_MASK, 32'd20);
        if (beat_count[SOUTH] != 48) begin
            $display("FAIL: blocked south transferred a comparison beat");
            $fatal(1);
        end

        // Releasing south drains both its comparison frame and the flipping
        // frame queued behind it. The three completed ports must not replay
        // either entry action while south catches up.
        check_south_stall = 1'b0;
        output_ready[SOUTH] = 1'b1;
        wait_for_count(SOUTH, 55);
        check_phi0(SOUTH, 48, 32'd0, NORTH_MASK, 32'd20);
        check_anyon(SOUTH, 52, 32'd0, 32'd0);
        if (beat_count[CORRECTION] != 0) begin
            $display("FAIL: tails emitted a correction");
            $fatal(1);
        end
        if (beat_count[NORTH] != 55 || beat_count[EAST] != 55 ||
                beat_count[WEST] != 55) begin
            $display("FAIL: completed entry replayed accepted ports");
            $fatal(1);
        end

        // The first xorshift32 result has its high bit clear, so step zero
        // cannot move even though east won the comparison. One incoming move
        // seeds a local anyon for the next decoder step.
        // Status is the first post-move effect. Holding the next syndrome
        // request proves the complete status can cross its output before that
        // request is accepted by its own stream.
        output_ready[SYNDROME] = 1'b0;
        send_anyon(32'd0, 32'd1);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        wait_for_count(STATUS, 4);
        check_status(0, 32'd0, 32'd1);
        output_ready[SYNDROME] = 1'b1;
        expect_measurement_request(2, 32'd1);
        send_measurement(32'd1, 32'd0);
        expect_all_phi(55, 32'd12, 32'd20, 32'd29);

        // With the local anyon present, zero-valued neighbors still contribute
        // its signed Q15.16 charge. Drive eleven nonterminal rounds, then the
        // twelfth enters comparison with layer zero equal to 139927.
        advance_uniform_phi(32'd12, 32'd0, 32'd0,
                            59, 32'd65551, 32'd19);
        advance_uniform_phi(32'd13, 32'd0, 32'd0,
                            63, 32'd98315, 32'd5474);
        advance_uniform_phi(32'd14, 32'd0, 32'd0,
                            67, 32'd115606, 32'd11386);
        advance_uniform_phi(32'd15, 32'd0, 32'd0,
                            71, 32'd125237, 32'd16276);
        advance_uniform_phi(32'd16, 32'd0, 32'd0,
                            75, 32'd130867, 32'd19931);
        advance_uniform_phi(32'd17, 32'd0, 32'd0,
                            79, 32'd134291, 32'd22532);
        advance_uniform_phi(32'd18, 32'd0, 32'd0,
                            83, 32'd136437, 32'd24335);
        advance_uniform_phi(32'd19, 32'd0, 32'd0,
                            87, 32'd137810, 32'd25565);
        advance_uniform_phi(32'd20, 32'd0, 32'd0,
                            91, 32'd138702, 32'd26397);
        advance_uniform_phi(32'd21, 32'd0, 32'd0,
                            95, 32'd139287, 32'd26957);
        advance_uniform_phi(32'd22, 32'd0, 32'd0,
                            99, 32'd139672, 32'd27332);
        send_uniform_phi(32'd23, 32'd0, 32'd0);
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1)
            wait_for_count(check_port, 107);
        check_phi0(NORTH, 103, 32'd1, SOUTH_MASK, 32'd139927);
        check_phi0(EAST, 103, 32'd1, WEST_MASK, 32'd139927);
        check_phi0(WEST, 103, 32'd1, EAST_MASK, 32'd139927);
        check_phi0(SOUTH, 103, 32'd1, NORTH_MASK, 32'd139927);

        // The second xorshift32 result has its high bit set. East is the unique
        // winner above the local value 139927, so its output alone carries
        // present=1. Stall that selected frame to exercise the new data under
        // backpressure.
        output_ready[EAST] = 1'b0;
        send_phi0(32'd1, NORTH_MASK, 32'd140000);
        send_phi0(32'd1, EAST_MASK, 32'd150000);
        send_phi0(32'd1, WEST_MASK, 32'd145000);
        send_phi0(32'd1, SOUTH_MASK, 32'd135000);

        while (!output_valid[EAST])
            @(posedge clk);
        @(negedge clk);
        stalled_beat = output_beat[EAST];
        if (stalled_beat !== {1'b0, header(8'd4, 8'd2)}) begin
            $display("FAIL: east did not stall on the selected ANYON header");
            $fatal(1);
        end
        check_east_stall = 1'b1;

        wait_for_count(NORTH, 110);
        wait_for_count(WEST, 110);
        wait_for_count(SOUTH, 110);
        repeat (8) @(posedge clk);
        if (beat_count[EAST] != 107) begin
            $display("FAIL: blocked east transferred a selected ANYON beat");
            $fatal(1);
        end
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1) begin
            if (check_port != EAST && beat_count[check_port] != 110) begin
                $display("FAIL: selected ANYON entry replayed a completed port");
                $fatal(1);
            end
            if (check_port != EAST)
                check_anyon(check_port, 107, 32'd1, 32'd0);
        end

        check_east_stall = 1'b0;
        output_ready[EAST] = 1'b1;
        wait_for_count(EAST, 110);
        check_anyon(EAST, 107, 32'd1, 32'd1);
        wait_for_count(CORRECTION, 4);
        check_correction(0, 32'd1, EAST_MASK);
        if (beat_count[NORTH] != 110 || beat_count[WEST] != 110 ||
                beat_count[SOUTH] != 110) begin
            $display("FAIL: completed ports replayed while east caught up");
            $fatal(1);
        end

        // The outgoing move clears the local anyon. One incoming move restores
        // it by parity, which the charge term in the following round exposes.
        send_anyon(32'd1, 32'd1);
        send_anyon(32'd1, 32'd0);
        send_anyon(32'd1, 32'd0);
        send_anyon(32'd1, 32'd0);
        expect_measurement_request(4, 32'd2);
        send_measurement(32'd2, 32'd0);
        expect_all_phi(110, 32'd24, 32'd139927, 32'd27583);

        // A second charged relaxation approaches the reflected two-layer
        // fixed point, reaching [140431, 28083] after twelve rounds.
        advance_uniform_phi(32'd24, 32'd0, 32'd0,
                            114, 32'd140097, 32'd27751);
        advance_uniform_phi(32'd25, 32'd0, 32'd0,
                            118, 32'd140210, 32'd27863);
        advance_uniform_phi(32'd26, 32'd0, 32'd0,
                            122, 32'd140285, 32'd27938);
        advance_uniform_phi(32'd27, 32'd0, 32'd0,
                            126, 32'd140335, 32'd27988);
        advance_uniform_phi(32'd28, 32'd0, 32'd0,
                            130, 32'd140368, 32'd28021);
        advance_uniform_phi(32'd29, 32'd0, 32'd0,
                            134, 32'd140390, 32'd28043);
        advance_uniform_phi(32'd30, 32'd0, 32'd0,
                            138, 32'd140405, 32'd28058);
        advance_uniform_phi(32'd31, 32'd0, 32'd0,
                            142, 32'd140415, 32'd28068);
        advance_uniform_phi(32'd32, 32'd0, 32'd0,
                            146, 32'd140422, 32'd28074);
        advance_uniform_phi(32'd33, 32'd0, 32'd0,
                            150, 32'd140426, 32'd28078);
        advance_uniform_phi(32'd34, 32'd0, 32'd0,
                            154, 32'd140429, 32'd28081);

        // The third xorshift32 result is also heads. Complete an all-negative
        // signed comparison with east as the unique least-negative winner.
        // Observing east's move proves both signed ordering and that the
        // stalled step-one entry
        // advanced the generator once, not once per retry or output port.
        send_uniform_phi(32'd35, 32'd0, 32'd0);
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1)
            wait_for_count(check_port, 162);
        check_phi0(NORTH, 158, 32'd2, SOUTH_MASK, 32'd140431);
        check_phi0(EAST, 158, 32'd2, WEST_MASK, 32'd140431);
        check_phi0(WEST, 158, 32'd2, EAST_MASK, 32'd140431);
        check_phi0(SOUTH, 158, 32'd2, NORTH_MASK, 32'd140431);

        send_phi0(32'd2, NORTH_MASK, 32'hfffffffc);
        send_phi0(32'd2, EAST_MASK, 32'hffffffff);
        send_phi0(32'd2, WEST_MASK, 32'hfffffffd);
        send_phi0(32'd2, SOUTH_MASK, 32'hfffffffe);
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1)
            wait_for_count(check_port, 165);
        check_anyon(NORTH, 162, 32'd2, 32'd0);
        check_anyon(EAST, 162, 32'd2, 32'd1);
        check_anyon(WEST, 162, 32'd2, 32'd0);
        check_anyon(SOUTH, 162, 32'd2, 32'd0);
        wait_for_count(CORRECTION, 8);
        check_correction(4, 32'd2, EAST_MASK);

        repeat (8) @(posedge clk);
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1) begin
            if (beat_count[check_port] != 165) begin
                $display("FAIL: unexpected output after second coin check");
                $fatal(1);
            end
        end
        if (beat_count[CORRECTION] != 8) begin
            $display("FAIL: unexpected correction output count");
            $fatal(1);
        end

        $display("PASS: comparison, coin-gated move, and backpressure");
        $finish;
    end
endmodule
