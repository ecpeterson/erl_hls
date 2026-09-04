`timescale 1ns/1ps

module phi_noise_topology_smoke_tb;
    localparam [7:0] PHI_CORRECTION_TAG = 8'd11;
    localparam [7:0] PAULI_QUERY_TAG = 8'd13;
    localparam [7:0] PAULI_REPLY_TAG = 8'd14;
    localparam [7:0] NOISE_CUTOFF_TAG = 8'd15;
    localparam [7:0] PAULI_UPDATE_TAG = 8'd16;
    localparam [7:0] PHI_STATUS_TAG = 8'd17;
    localparam [1:0] DATA_TARGET = 2'd0;
    localparam [1:0] NOISE_TARGET = 2'd1;
    localparam [31:0] FIRST_QUERY_ID = 32'h10000001;
    localparam [31:0] SECOND_QUERY_ID = 32'h10000002;
    localparam [31:0] FIRST_QUIET_STEP = 32'd4;
    localparam [31:0] PAULI_X = 32'd2;
    localparam [31:0] PAULI_Z = 32'd1;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [193:0] control_router = 194'b0;
    reg control_router_valid = 1'b0;
    wire control_router_ready;

    wire x_decoder_events_ready = 1'b1;
    wire [127:0] x_decoder_events;
    wire x_decoder_events_valid;

    wire z_decoder_events_ready = 1'b1;
    wire [127:0] z_decoder_events;
    wire z_decoder_events_valid;

    wire data_measurements_ready = 1'b1;
    wire [127:0] data_measurements;
    wire data_measurements_valid;

    reg x_quiet_status_seen = 1'b0;
    reg z_quiet_status_seen = 1'b0;
    reg first_reply_seen = 1'b0;
    reg second_reply_seen = 1'b0;
    reg first_reply_parity;
    reg second_reply_parity;
    integer cycle;
    integer ram_index_trace;
    integer ram_index_check;

    wire [31:0] data_state_rd_addr [0:1];
    wire [31:0] data_state_wr_addr [0:1];
    wire [433:0] data_state_wr_data [0:1];
    wire data_state_wr_en [0:1];
    wire data_state_rd_en [0:1];
    wire [433:0] data_state_rd_data [0:1];
    wire [31:0] data_mailbox_rd_addr [0:1];
    wire [31:0] data_mailbox_wr_addr [0:1];
    wire [127:0] data_mailbox_wr_data [0:1];
    wire data_mailbox_wr_en [0:1];
    wire data_mailbox_rd_en [0:1];
    wire [127:0] data_mailbox_rd_data [0:1];

    wire [31:0] phi_state_rd_addr [0:1];
    wire [31:0] phi_state_wr_addr [0:1];
    wire [545:0] phi_state_wr_data [0:1];
    wire phi_state_wr_en [0:1];
    wire phi_state_rd_en [0:1];
    wire [545:0] phi_state_rd_data [0:1];
    wire [31:0] phi_mailbox_rd_addr [0:1];
    wire [31:0] phi_mailbox_wr_addr [0:1];
    wire [127:0] phi_mailbox_wr_data [0:1];
    wire phi_mailbox_wr_en [0:1];
    wire phi_mailbox_rd_en [0:1];
    wire [127:0] phi_mailbox_rd_data [0:1];

    wire [31:0] syndrome_state_rd_addr [0:1];
    wire [31:0] syndrome_state_wr_addr [0:1];
    wire [433:0] syndrome_state_wr_data [0:1];
    wire syndrome_state_wr_en [0:1];
    wire syndrome_state_rd_en [0:1];
    wire [433:0] syndrome_state_rd_data [0:1];
    wire [31:0] syndrome_mailbox_rd_addr [0:1];
    wire [31:0] syndrome_mailbox_wr_addr [0:1];
    wire [127:0] syndrome_mailbox_wr_data [0:1];
    wire syndrome_mailbox_wr_en [0:1];
    wire syndrome_mailbox_rd_en [0:1];
    wire [127:0] syndrome_mailbox_rd_data [0:1];

    __phi_noise_topology_smoke__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        ._control_router_in(control_router),
        ._control_router_in_vld(
            control_router_valid
        ),
        ._control_router_in_rdy(
            control_router_ready
        ),
        ._data_measurements_out_rdy(
            data_measurements_ready
        ),
        ._data_measurements_out(data_measurements),
        ._data_measurements_out_vld(
            data_measurements_valid
        ),
        ._x_decoder_events_out_rdy(
            x_decoder_events_ready
        ),
        ._x_decoder_events_out(x_decoder_events),
        ._x_decoder_events_out_vld(
            x_decoder_events_valid
        ),
        ._z_decoder_events_out_rdy(
            z_decoder_events_ready
        ),
        ._z_decoder_events_out(z_decoder_events),
        ._z_decoder_events_out_vld(
            z_decoder_events_valid
        ),
        .scheduler_0_state_rd_addr(data_state_rd_addr[0]),
        .scheduler_0_state_wr_addr(data_state_wr_addr[0]),
        .scheduler_0_state_wr_data(data_state_wr_data[0]),
        .scheduler_0_state_wr_en(data_state_wr_en[0]),
        .scheduler_0_state_rd_en(data_state_rd_en[0]),
        .scheduler_0_state_rd_data(data_state_rd_data[0]),
        .scheduler_0_mailbox_rd_addr(data_mailbox_rd_addr[0]),
        .scheduler_0_mailbox_wr_addr(data_mailbox_wr_addr[0]),
        .scheduler_0_mailbox_wr_data(data_mailbox_wr_data[0]),
        .scheduler_0_mailbox_wr_en(data_mailbox_wr_en[0]),
        .scheduler_0_mailbox_rd_en(data_mailbox_rd_en[0]),
        .scheduler_0_mailbox_rd_data(data_mailbox_rd_data[0]),
        .scheduler_1_state_rd_addr(data_state_rd_addr[1]),
        .scheduler_1_state_wr_addr(data_state_wr_addr[1]),
        .scheduler_1_state_wr_data(data_state_wr_data[1]),
        .scheduler_1_state_wr_en(data_state_wr_en[1]),
        .scheduler_1_state_rd_en(data_state_rd_en[1]),
        .scheduler_1_state_rd_data(data_state_rd_data[1]),
        .scheduler_1_mailbox_rd_addr(data_mailbox_rd_addr[1]),
        .scheduler_1_mailbox_wr_addr(data_mailbox_wr_addr[1]),
        .scheduler_1_mailbox_wr_data(data_mailbox_wr_data[1]),
        .scheduler_1_mailbox_wr_en(data_mailbox_wr_en[1]),
        .scheduler_1_mailbox_rd_en(data_mailbox_rd_en[1]),
        .scheduler_1_mailbox_rd_data(data_mailbox_rd_data[1]),
        .scheduler_2_state_rd_addr(phi_state_rd_addr[0]),
        .scheduler_2_state_wr_addr(phi_state_wr_addr[0]),
        .scheduler_2_state_wr_data(phi_state_wr_data[0]),
        .scheduler_2_state_wr_en(phi_state_wr_en[0]),
        .scheduler_2_state_rd_en(phi_state_rd_en[0]),
        .scheduler_2_state_rd_data(phi_state_rd_data[0]),
        .scheduler_2_mailbox_rd_addr(phi_mailbox_rd_addr[0]),
        .scheduler_2_mailbox_wr_addr(phi_mailbox_wr_addr[0]),
        .scheduler_2_mailbox_wr_data(phi_mailbox_wr_data[0]),
        .scheduler_2_mailbox_wr_en(phi_mailbox_wr_en[0]),
        .scheduler_2_mailbox_rd_en(phi_mailbox_rd_en[0]),
        .scheduler_2_mailbox_rd_data(phi_mailbox_rd_data[0]),
        .scheduler_3_state_rd_addr(phi_state_rd_addr[1]),
        .scheduler_3_state_wr_addr(phi_state_wr_addr[1]),
        .scheduler_3_state_wr_data(phi_state_wr_data[1]),
        .scheduler_3_state_wr_en(phi_state_wr_en[1]),
        .scheduler_3_state_rd_en(phi_state_rd_en[1]),
        .scheduler_3_state_rd_data(phi_state_rd_data[1]),
        .scheduler_3_mailbox_rd_addr(phi_mailbox_rd_addr[1]),
        .scheduler_3_mailbox_wr_addr(phi_mailbox_wr_addr[1]),
        .scheduler_3_mailbox_wr_data(phi_mailbox_wr_data[1]),
        .scheduler_3_mailbox_wr_en(phi_mailbox_wr_en[1]),
        .scheduler_3_mailbox_rd_en(phi_mailbox_rd_en[1]),
        .scheduler_3_mailbox_rd_data(phi_mailbox_rd_data[1]),
        .scheduler_4_state_rd_addr(syndrome_state_rd_addr[0]),
        .scheduler_4_state_wr_addr(syndrome_state_wr_addr[0]),
        .scheduler_4_state_wr_data(syndrome_state_wr_data[0]),
        .scheduler_4_state_wr_en(syndrome_state_wr_en[0]),
        .scheduler_4_state_rd_en(syndrome_state_rd_en[0]),
        .scheduler_4_state_rd_data(syndrome_state_rd_data[0]),
        .scheduler_4_mailbox_rd_addr(syndrome_mailbox_rd_addr[0]),
        .scheduler_4_mailbox_wr_addr(syndrome_mailbox_wr_addr[0]),
        .scheduler_4_mailbox_wr_data(syndrome_mailbox_wr_data[0]),
        .scheduler_4_mailbox_wr_en(syndrome_mailbox_wr_en[0]),
        .scheduler_4_mailbox_rd_en(syndrome_mailbox_rd_en[0]),
        .scheduler_4_mailbox_rd_data(syndrome_mailbox_rd_data[0]),
        .scheduler_5_state_rd_addr(syndrome_state_rd_addr[1]),
        .scheduler_5_state_wr_addr(syndrome_state_wr_addr[1]),
        .scheduler_5_state_wr_data(syndrome_state_wr_data[1]),
        .scheduler_5_state_wr_en(syndrome_state_wr_en[1]),
        .scheduler_5_state_rd_en(syndrome_state_rd_en[1]),
        .scheduler_5_state_rd_data(syndrome_state_rd_data[1]),
        .scheduler_5_mailbox_rd_addr(syndrome_mailbox_rd_addr[1]),
        .scheduler_5_mailbox_wr_addr(syndrome_mailbox_wr_addr[1]),
        .scheduler_5_mailbox_wr_data(syndrome_mailbox_wr_data[1]),
        .scheduler_5_mailbox_wr_en(syndrome_mailbox_wr_en[1]),
        .scheduler_5_mailbox_rd_en(syndrome_mailbox_rd_en[1]),
        .scheduler_5_mailbox_rd_data(syndrome_mailbox_rd_data[1])
    );

    always #5 clk = ~clk;

    genvar ram_index;
    generate
        for (ram_index = 0; ram_index < 2; ram_index = ram_index + 1) begin: scheduler_rams
            hls_1r1w_ram #(.WIDTH(434), .ADDRESS_WIDTH(4)) data_state (
                .clk(clk), .rd_addr(data_state_rd_addr[ram_index][3:0]),
                .wr_addr(data_state_wr_addr[ram_index][3:0]),
                .wr_data(data_state_wr_data[ram_index]),
                .wr_en(data_state_wr_en[ram_index]), .rd_en(data_state_rd_en[ram_index]),
                .rd_data(data_state_rd_data[ram_index])
            );
            hls_1r1w_ram #(.WIDTH(546), .ADDRESS_WIDTH(4)) phi_state (
                .clk(clk), .rd_addr(phi_state_rd_addr[ram_index][3:0]),
                .wr_addr(phi_state_wr_addr[ram_index][3:0]),
                .wr_data(phi_state_wr_data[ram_index]),
                .wr_en(phi_state_wr_en[ram_index]), .rd_en(phi_state_rd_en[ram_index]),
                .rd_data(phi_state_rd_data[ram_index])
            );
            hls_1r1w_ram #(.WIDTH(434), .ADDRESS_WIDTH(4)) syndrome_state (
                .clk(clk), .rd_addr(syndrome_state_rd_addr[ram_index][3:0]),
                .wr_addr(syndrome_state_wr_addr[ram_index][3:0]),
                .wr_data(syndrome_state_wr_data[ram_index]),
                .wr_en(syndrome_state_wr_en[ram_index]),
                .rd_en(syndrome_state_rd_en[ram_index]),
                .rd_data(syndrome_state_rd_data[ram_index])
            );
            hls_1r1w_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) data_mailbox (
                .clk(clk), .rd_addr(data_mailbox_rd_addr[ram_index][5:0]),
                .wr_addr(data_mailbox_wr_addr[ram_index][5:0]),
                .wr_data(data_mailbox_wr_data[ram_index]),
                .wr_en(data_mailbox_wr_en[ram_index]),
                .rd_en(data_mailbox_rd_en[ram_index]),
                .rd_data(data_mailbox_rd_data[ram_index])
            );
            hls_1r1w_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) phi_mailbox (
                .clk(clk), .rd_addr(phi_mailbox_rd_addr[ram_index][5:0]),
                .wr_addr(phi_mailbox_wr_addr[ram_index][5:0]),
                .wr_data(phi_mailbox_wr_data[ram_index]),
                .wr_en(phi_mailbox_wr_en[ram_index]),
                .rd_en(phi_mailbox_rd_en[ram_index]),
                .rd_data(phi_mailbox_rd_data[ram_index])
            );
            hls_1r1w_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) syndrome_mailbox (
                .clk(clk), .rd_addr(syndrome_mailbox_rd_addr[ram_index][5:0]),
                .wr_addr(syndrome_mailbox_wr_addr[ram_index][5:0]),
                .wr_data(syndrome_mailbox_wr_data[ram_index]),
                .wr_en(syndrome_mailbox_wr_en[ram_index]),
                .rd_en(syndrome_mailbox_rd_en[ram_index]),
                .rd_data(syndrome_mailbox_rd_data[ram_index])
            );
        end
    endgenerate

    function automatic [127:0] frame1;
        input [7:0] tag;
        input [31:0] word0;
        begin
            frame1 = {{8'd1, 8'd0, 8'd0, tag}, 64'd0, word0};
        end
    endfunction

    function automatic [127:0] frame2;
        input [7:0] tag;
        input [31:0] word0;
        input [31:0] word1;
        begin
            frame2 = {{8'd2, 8'd0, 8'd0, tag}, 32'd0, word1, word0};
        end
    endfunction

    task automatic send_spatial;
        input [15:0] x0;
        input [15:0] y0;
        input [15:0] x1;
        input [15:0] y1;
        input [1:0] target;
        input [127:0] frame;
        begin
            @(negedge clk);
            control_router = {x0, y0, x1, y1, target, frame};
            control_router_valid = 1'b1;
            @(posedge clk);
            while (!control_router_ready)
                @(posedge clk);
            @(negedge clk);
            control_router_valid = 1'b0;
            control_router = 194'b0;
        end
    endtask

    task automatic record_decoder_event;
        input [127:0] frame;
        input [7:0] plane;
        reg [31:0] header;
        reg [31:0] step;
        reg [31:0] flags;
        begin
            header = frame[127:96];
            step = frame[31:0];
            flags = frame[95:64];
            if (header[7:0] == PHI_CORRECTION_TAG) begin
                $display("FAIL: distance-one %s plane emitted a correction",
                    plane);
                $fatal(1);
            end
            if (header !== {8'd3, 8'd0, 8'd0, PHI_STATUS_TAG} ||
                    frame[63:32] !== 32'd0 || flags > 32'd3) begin
                $display("FAIL: malformed %s decoder status %032x",
                    plane, frame);
                $fatal(1);
            end
            // The distance-one smoke topology can retain an aliased anyon.
            // Quiet propagation, rather than the occupancy bit, is the fence
            // needed before exercising endpoint-local Pauli queries.
            if (step >= FIRST_QUIET_STEP && flags[1]) begin
                if (plane == "x")
                    x_quiet_status_seen = 1'b1;
                else
                    z_quiet_status_seen = 1'b1;
            end
        end
    endtask

    task automatic record_pauli_reply;
        input [127:0] frame;
        reg [31:0] request_id;
        reg [31:0] parity;
        begin
            request_id = frame[31:0];
            parity = frame[95:64];
            if (frame[127:96] !== {8'd3, 8'd0, 8'd0,
                    PAULI_REPLY_TAG} ||
                    frame[47:32] !== 16'd0 ||
                    frame[63:48] !== 16'd0 || parity > 1) begin
                $display("FAIL: malformed Pauli reply %032x", frame);
                $fatal(1);
            end
            if (request_id == FIRST_QUERY_ID && !first_reply_seen) begin
                first_reply_parity = parity[0];
                first_reply_seen = 1'b1;
            end else if (request_id == SECOND_QUERY_ID &&
                    !second_reply_seen) begin
                second_reply_parity = parity[0];
                second_reply_seen = 1'b1;
            end else begin
                $display("FAIL: duplicate or unexpected Pauli reply %08x",
                    request_id);
                $fatal(1);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset && x_decoder_events_valid && x_decoder_events_ready)
            record_decoder_event(x_decoder_events, "x");
        if (!reset && z_decoder_events_valid && z_decoder_events_ready)
            record_decoder_event(z_decoder_events, "z");
        if (!reset && data_measurements_valid && data_measurements_ready)
            record_pauli_reply(data_measurements);
        if (!reset) begin
            for (ram_index_check = 0; ram_index_check < 2;
                    ram_index_check = ram_index_check + 1) begin
                if ((data_state_rd_en[ram_index_check] &&
                        data_state_wr_en[ram_index_check] &&
                        data_state_rd_addr[ram_index_check] ==
                            data_state_wr_addr[ram_index_check]) ||
                    (phi_state_rd_en[ram_index_check] &&
                        phi_state_wr_en[ram_index_check] &&
                        phi_state_rd_addr[ram_index_check] ==
                            phi_state_wr_addr[ram_index_check]) ||
                    (syndrome_state_rd_en[ram_index_check] &&
                        syndrome_state_wr_en[ram_index_check] &&
                        syndrome_state_rd_addr[ram_index_check] ==
                            syndrome_state_wr_addr[ram_index_check]) ||
                    (data_mailbox_rd_en[ram_index_check] &&
                        data_mailbox_wr_en[ram_index_check] &&
                        data_mailbox_rd_addr[ram_index_check] ==
                            data_mailbox_wr_addr[ram_index_check]) ||
                    (phi_mailbox_rd_en[ram_index_check] &&
                        phi_mailbox_wr_en[ram_index_check] &&
                        phi_mailbox_rd_addr[ram_index_check] ==
                            phi_mailbox_wr_addr[ram_index_check]) ||
                    (syndrome_mailbox_rd_en[ram_index_check] &&
                        syndrome_mailbox_wr_en[ram_index_check] &&
                        syndrome_mailbox_rd_addr[ram_index_check] ==
                            syndrome_mailbox_wr_addr[ram_index_check])) begin
                    $display("FAIL: scheduler %0d overlapped one RAM row",
                        ram_index_check);
                    $fatal(1);
                end
            end
        end
    end

`ifdef HLS_TRACE_MAILBOX
    always @(posedge clk) begin
        for (ram_index_trace = 0; ram_index_trace < 2;
                ram_index_trace = ram_index_trace + 1) begin
            if (!reset && data_mailbox_wr_en[ram_index_trace])
                $display("data[%0d] mailbox write addr=%0d tag=%0d",
                    ram_index_trace, data_mailbox_wr_addr[ram_index_trace],
                    data_mailbox_wr_data[ram_index_trace][31:24]);
            if (!reset && phi_mailbox_wr_en[ram_index_trace])
                $display("phi[%0d] mailbox write addr=%0d tag=%0d",
                    ram_index_trace, phi_mailbox_wr_addr[ram_index_trace],
                    phi_mailbox_wr_data[ram_index_trace][31:24]);
            if (!reset && syndrome_mailbox_wr_en[ram_index_trace])
                $display("syndrome[%0d] mailbox write addr=%0d tag=%0d",
                    ram_index_trace, syndrome_mailbox_wr_addr[ram_index_trace],
                    syndrome_mailbox_wr_data[ram_index_trace][31:24]);
            if (!reset && data_state_wr_en[ram_index_trace])
                $display("data[%0d] state write slot=%0d phase=%0d enter=%0d failed=%0d",
                    ram_index_trace, data_state_wr_addr[ram_index_trace],
                    data_state_wr_data[ram_index_trace][7:0],
                    data_state_wr_data[ram_index_trace][432],
                    data_state_wr_data[ram_index_trace][433]);
            if (!reset && phi_state_wr_en[ram_index_trace])
                $display("phi[%0d] state write slot=%0d phase=%0d enter=%0d failed=%0d",
                    ram_index_trace, phi_state_wr_addr[ram_index_trace],
                    phi_state_wr_data[ram_index_trace][7:0],
                    phi_state_wr_data[ram_index_trace][544],
                    phi_state_wr_data[ram_index_trace][545]);
            if (!reset && syndrome_state_wr_en[ram_index_trace])
                $display("syndrome[%0d] state write slot=%0d phase=%0d enter=%0d failed=%0d",
                    ram_index_trace, syndrome_state_wr_addr[ram_index_trace],
                    syndrome_state_wr_data[ram_index_trace][7:0],
                    syndrome_state_wr_data[ram_index_trace][432],
                    syndrome_state_wr_data[ram_index_trace][433]);
        end
    end
`endif

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // The host submits one whole-fabric rectangle to the router service.
        // It expands the envelope into ordinary lossless actor casts; no leaf
        // actor sees the rectangle or gains broadcast-specific semantics.
        send_spatial(
            16'd0,
            16'd0,
            16'd0,
            16'd1,
            NOISE_TARGET,
            frame1(NOISE_CUTOFF_TAG, FIRST_QUIET_STEP)
        );

        // Quiet reaches each phi status only after every data reply and the
        // paired syndrome source for that completed step are also quiet.
        for (cycle = 0;
                cycle < 200000 &&
                    !(x_quiet_status_seen && z_quiet_status_seen);
                cycle = cycle + 1)
            @(posedge clk);
        if (!x_quiet_status_seen || !z_quiet_status_seen) begin
            $display("FAIL: timed out waiting for quiet x/z decoder status");
            $fatal(1);
        end

        // A one-cell-thick line reaches one data qubit at d=1. Query its
        // stable Pauli frame, apply one point-addressed X correction, then
        // query again. Anticommutation with Z must toggle.
        send_spatial(
            16'd0,
            16'd0,
            16'd0,
            16'd0,
            DATA_TARGET,
            frame2(PAULI_QUERY_TAG, FIRST_QUERY_ID, PAULI_Z)
        );
        for (cycle = 0;
                cycle < 100000 && !first_reply_seen;
                cycle = cycle + 1)
            @(posedge clk);
        if (!first_reply_seen) begin
            $display("FAIL: timed out waiting for first Pauli reply");
            $fatal(1);
        end

        send_spatial(
            16'd0,
            16'd0,
            16'd0,
            16'd0,
            DATA_TARGET,
            frame1(PAULI_UPDATE_TAG, PAULI_X)
        );
        send_spatial(
            16'd0,
            16'd0,
            16'd0,
            16'd0,
            DATA_TARGET,
            frame2(PAULI_QUERY_TAG, SECOND_QUERY_ID, PAULI_Z)
        );
        for (cycle = 0;
                cycle < 100000 && !second_reply_seen;
                cycle = cycle + 1)
            @(posedge clk);
        if (!second_reply_seen) begin
            $display("FAIL: timed out waiting for second Pauli reply");
            $fatal(1);
        end
        if (first_reply_parity == second_reply_parity) begin
            $display("FAIL: point-addressed X update did not toggle Z parity");
            $fatal(1);
        end

        $display(
            "PASS: distance-one phi/noise topology and spatial ingress router"
        );
        $finish;
    end
endmodule
