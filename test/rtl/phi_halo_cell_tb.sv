`timescale 1ns/1ps

module phi_halo_cell_tb;
    localparam integer NORTH = 0;
    localparam integer EAST  = 1;
    localparam integer WEST  = 2;
    localparam integer SOUTH = 3;

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
        input [31:0] step;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            send_beat(header(8'd3, 8'd3), 1'b0);
            send_beat(step, 1'b0);
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
        input [31:0] step;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            check_beat(port, base + 0, header(8'd3, 8'd3), 1'b0);
            check_beat(port, base + 1, step, 1'b0);
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

    task automatic expect_all_phi;
        input integer base;
        input [31:0] step;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        integer port;
        begin
            for (port = 0; port < 4; port = port + 1) begin
                wait_for_count(port, base + 4);
                check_phi(port, base, step, layer_zero, layer_one);
            end
        end
    endtask

    task automatic expect_all_anyon;
        input integer base;
        input [31:0] step;
        input [31:0] present;
        integer port;
        begin
            for (port = 0; port < 4; port = port + 1) begin
                wait_for_count(port, base + 3);
                check_anyon(port, base, step, present);
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

        // Stall south across three entries. Its transmitter holds the initial
        // PHI and its frame FIFO holds the ANYON, so the following PHI entry
        // must block in Service after north/east/west have accepted it.
        output_ready = 4'b0111;
        wait_for_count(NORTH, 4);
        wait_for_count(EAST, 4);
        wait_for_count(WEST, 4);
        while (!output_valid[SOUTH])
            @(posedge clk);
        @(negedge clk);
        stalled_beat = output_beat[SOUTH];
        check_south_stall = 1'b1;

        // Four early ANYONs occupy four of five mailbox slots. Current PHIs
        // must still make progress through the fifth reserved slot.
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_anyon(32'd0, 32'd0);
        send_phi(32'd0, 32'd32, 32'd48);
        send_phi(32'd0, 32'd64, 32'd80);
        send_phi(32'd0, 32'd16, 32'd32);
        send_phi(32'd0, 32'd48, 32'd64);

        wait_for_count(NORTH, 11);
        wait_for_count(EAST, 11);
        wait_for_count(WEST, 11);
        repeat (8) @(posedge clk);
        for (check_port = NORTH; check_port <= WEST;
                check_port = check_port + 1) begin
            if (beat_count[check_port] != 11) begin
                $display("FAIL: Service duplicated an accepted output");
                $fatal(1);
            end
            check_phi(check_port, 0, 32'd0, 32'd0, 32'd0);
            check_anyon(check_port, 4, 32'd0, 32'd0);
            check_phi(check_port, 7, 32'd1, 32'd20, 32'd11);
        end
        if (beat_count[SOUTH] != 0) begin
            $display("FAIL: blocked south output transferred a beat");
            $fatal(1);
        end

        check_south_stall = 1'b0;
        output_ready[SOUTH] = 1'b1;
        wait_for_count(SOUTH, 11);
        check_phi(SOUTH, 0, 32'd0, 32'd0, 32'd0);
        check_anyon(SOUTH, 4, 32'd0, 32'd0);
        check_phi(SOUTH, 7, 32'd1, 32'd20, 32'd11);
        if (beat_count[NORTH] != 11 || beat_count[EAST] != 11 ||
                beat_count[WEST] != 11) begin
            $display("FAIL: completed entry replayed accepted ports");
            $fatal(1);
        end

        // The symmetric lookahead: next-step PHI waits in flipping and is
        // retried only after four current ANYONs enter gathering.
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);
        send_phi(32'd1, 32'd16, 32'd32);
        expect_all_anyon(11, 32'd1, 32'd0);

        send_phi(32'd2, 32'd8, 32'd12);
        send_anyon(32'd1, 32'd0);
        send_anyon(32'd1, 32'd0);
        send_anyon(32'd1, 32'd0);
        send_anyon(32'd1, 32'd0);
        expect_all_phi(14, 32'd2, 32'd15, 32'd15);

        // The early PHI already supplied one input for step two.
        send_phi(32'd2, 32'd16, 32'd32);
        send_phi(32'd2, 32'd16, 32'd32);
        send_phi(32'd2, 32'd16, 32'd32);
        expect_all_anyon(18, 32'd2, 32'd0);

        $display("PASS: gathering/flipping phi cell with four explicit ports");
        $finish;
    end
endmodule
