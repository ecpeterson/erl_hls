`timescale 1ns/1ps

module phi_halo_cell_tb;
    localparam integer NORTH = 0;
    localparam integer EAST  = 1;
    localparam integer WEST  = 2;
    localparam integer SOUTH = 3;

    localparam [31:0] NORTH_MASK = 32'd1;
    localparam [31:0] EAST_MASK  = 32'd2;
    localparam [31:0] WEST_MASK  = 32'd4;
    localparam [31:0] SOUTH_MASK = 32'd8;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat [0:3];
    wire [3:0] output_valid;
    reg [3:0] output_ready = 4'b0000;

    reg [32:0] captured [0:3][0:63];
    integer beat_count [0:3];
    integer port_index;
    integer check_port;
    reg [32:0] stalled_beat;
    reg check_south_stall = 1'b0;

    __phi_halo_cell__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_halo_cell__ext_recv({input_last, input_data}),
        .phi_halo_cell__ext_recv_vld(input_valid),
        .phi_halo_cell__ext_recv_rdy(input_ready),
        .phi_halo_cell__north_send_rdy(output_ready[NORTH]),
        .phi_halo_cell__north_send(output_beat[NORTH]),
        .phi_halo_cell__north_send_vld(output_valid[NORTH]),
        .phi_halo_cell__east_send_rdy(output_ready[EAST]),
        .phi_halo_cell__east_send(output_beat[EAST]),
        .phi_halo_cell__east_send_vld(output_valid[EAST]),
        .phi_halo_cell__west_send_rdy(output_ready[WEST]),
        .phi_halo_cell__west_send(output_beat[WEST]),
        .phi_halo_cell__west_send_vld(output_valid[WEST]),
        .phi_halo_cell__south_send_rdy(output_ready[SOUTH]),
        .phi_halo_cell__south_send(output_beat[SOUTH]),
        .phi_halo_cell__south_send_vld(output_valid[SOUTH])
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            for (port_index = 0; port_index < 4; port_index = port_index + 1) begin
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

    initial begin : watchdog
        #5000000;
        $display("FAIL: phi cell simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        for (port_index = 0; port_index < 4; port_index = port_index + 1)
            beat_count[port_index] = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        output_ready = 4'b1111;
        expect_all_phi(0, 32'd0, 32'd0, 32'd0);

        // Complete the first diffusion round. Repeating gathering emits the
        // updated value at epoch one before another message can dispatch.
        send_phi(32'd0, 32'd32, 32'd48);
        send_phi(32'd0, 32'd64, 32'd80);
        send_phi(32'd0, 32'd16, 32'd32);
        send_phi(32'd0, 32'd48, 32'd64);
        expect_all_phi(4, 32'd1, 32'd20, 32'd11);

        // A complete early comparison batch occupies four of the five
        // mailbox slots. Each current diffusion message must enter and leave
        // through the fifth reserved progress slot. Distinct receiver-local
        // source masks make east the unique neighboring maximum.
        send_phi0(32'd0, NORTH_MASK, 32'd14);
        send_phi0(32'd0, EAST_MASK, 32'd18);
        send_phi0(32'd0, WEST_MASK, 32'd17);
        send_phi0(32'd0, SOUTH_MASK, 32'd16);

        // The second diffusion round produces [15, 15] and enters comparing.
        // Independently stall south's wire output while the other three ports
        // complete theirs. Its transmitter retains the comparison frame, so
        // the staged inputs can still enter flipping and queue that phase's
        // frame behind it without replaying any completed port.
        output_ready[SOUTH] = 1'b0;
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);

        while (!output_valid[SOUTH])
            @(posedge clk);
        @(negedge clk);
        stalled_beat = output_beat[SOUTH];
        if (stalled_beat !== {1'b0, header(8'd5, 8'd3)}) begin
            $display("FAIL: south did not stall on the PHI0 header");
            $fatal(1);
        end
        check_south_stall = 1'b1;

        wait_for_count(NORTH, 15);
        wait_for_count(EAST, 15);
        wait_for_count(WEST, 15);
        repeat (8) @(posedge clk);
        for (check_port = NORTH; check_port <= WEST;
                check_port = check_port + 1) begin
            if (beat_count[check_port] != 15) begin
                $display("FAIL: Service replayed an accepted output");
                $fatal(1);
            end
            check_phi(check_port, 0, 32'd0, 32'd0, 32'd0);
            check_phi(check_port, 4, 32'd1, 32'd20, 32'd11);
            check_anyon(check_port, 12, 32'd0, 32'd0);
        end
        check_phi0(NORTH, 8, 32'd0, SOUTH_MASK, 32'd15);
        check_phi0(EAST, 8, 32'd0, WEST_MASK, 32'd15);
        check_phi0(WEST, 8, 32'd0, EAST_MASK, 32'd15);
        if (beat_count[SOUTH] != 8) begin
            $display("FAIL: blocked south transferred a comparison beat");
            $fatal(1);
        end

        // Releasing south drains both its comparison frame and the flipping
        // frame queued behind it. The three completed ports must not replay
        // either entry action while south catches up.
        check_south_stall = 1'b0;
        output_ready[SOUTH] = 1'b1;
        wait_for_count(SOUTH, 15);
        check_phi0(SOUTH, 8, 32'd0, NORTH_MASK, 32'd15);
        check_anyon(SOUTH, 12, 32'd0, 32'd0);
        if (beat_count[NORTH] != 15 || beat_count[EAST] != 15 ||
                beat_count[WEST] != 15) begin
            $display("FAIL: completed entry replayed accepted ports");
            $fatal(1);
        end

        // Four current-step ANYONs complete the flipping barrier, increment
        // the decoder step, reset the diffusion round, and enter gathering at
        // wire epoch two with the final [15, 15] diffusion value.
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        expect_all_phi(15, 32'd2, 32'd15, 32'd15);

        repeat (8) @(posedge clk);
        for (check_port = 0; check_port < 4;
                check_port = check_port + 1) begin
            if (beat_count[check_port] != 19) begin
                $display("FAIL: unexpected output after next-step entry");
                $fatal(1);
            end
        end

        $display("PASS: diffusion, source-aware comparison, and flipping");
        $finish;
    end
endmodule
