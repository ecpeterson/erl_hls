`timescale 1ns/1ps

module phi_noise_topology_tb;
    localparam [31:0] PHENOM_ANYON_HEADER = 32'h0300000a;
    localparam [31:0] PHI_CORRECTION_HEADER = 32'h0300000b;
    localparam [31:0] PHI_STATUS_HEADER = 32'h03000011;
    localparam [7:0] PAULI_QUERY_TAG = 8'd13;
    localparam [7:0] PAULI_REPLY_TAG = 8'd14;
    localparam [7:0] NOISE_CUTOFF_TAG = 8'd15;
    localparam [7:0] PAULI_UPDATE_TAG = 8'd16;
    localparam [1:0] DATA_TARGET = 2'd0;
    localparam [1:0] NOISE_TARGET = 2'd1;
    localparam [31:0] FIRST_QUERY_ID = 32'h10000001;
    localparam [31:0] SECOND_QUERY_ID = 32'h10000002;
    localparam [31:0] FIRST_QUIET_STEP = 32'd7;
    localparam [15:0] QUERY_ROW = 16'd4;
    localparam [31:0] PAULI_X = 32'd2;
    localparam [31:0] PAULI_Z = 32'd1;
    localparam [31:0] NORTH = 32'd1;
    localparam [31:0] EAST = 32'd2;
    localparam [31:0] WEST = 32'd4;
    localparam [31:0] SOUTH = 32'd8;
    localparam integer MAX_WAIT_CYCLES = 100000;
    localparam integer MAX_CONTROL_WAIT_CYCLES = 2000000;
    localparam [8:0] ALL_COORDINATES = 9'h1ff;
    localparam [2:0] ALL_QUERY_COORDINATES = 3'b111;
    // These sets are deterministic fixture goldens, not a logical-decoder
    // correctness or winding assertion.
    localparam [8:0] EXPECTED_X_CORRECTIONS_STEP_0 = 9'b0;
    localparam [8:0] EXPECTED_X_CORRECTIONS_STEP_1 =
        (9'b1 << 1) | (9'b1 << 6);
    localparam [8:0] EXPECTED_Z_CORRECTIONS_STEP_0 = 9'b1 << 4;
    localparam [8:0] EXPECTED_Z_CORRECTIONS_STEP_1 =
        (9'b1 << 0) | (9'b1 << 4);

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [193:0] control_router = 194'b0;
    reg control_router_valid = 1'b0;
    wire control_router_ready;

    reg x_announcement_ready = 1'b0;
    wire [127:0] x_announcement;
    wire x_announcement_valid;

    wire z_announcement_ready = 1'b1;
    wire [127:0] z_announcement;
    wire z_announcement_valid;

    wire x_decoder_event_ready = 1'b1;
    wire [127:0] x_decoder_event;
    wire x_decoder_event_valid;

    wire z_decoder_event_ready = 1'b1;
    wire [127:0] z_decoder_event;
    wire z_decoder_event_valid;

    wire data_measurements_ready = 1'b1;
    wire [127:0] data_measurements;
    wire data_measurements_valid;

    reg [8:0] x_announcements_step_0 = 9'b0;
    reg [8:0] x_announcements_step_1 = 9'b0;
    reg [8:0] x_announcements_step_2 = 9'b0;
    reg [8:0] z_announcements_step_0 = 9'b0;
    reg [8:0] z_announcements_step_1 = 9'b0;
    reg [8:0] z_announcements_step_2 = 9'b0;
    reg [8:0] x_corrections_step_0 = 9'b0;
    reg [8:0] x_corrections_step_1 = 9'b0;
    reg [8:0] z_corrections_step_0 = 9'b0;
    reg [8:0] z_corrections_step_1 = 9'b0;
    reg [8:0] x_status_step_0 = 9'b0;
    reg [8:0] x_status_step_1 = 9'b0;
    reg [8:0] z_status_step_0 = 9'b0;
    reg [8:0] z_status_step_1 = 9'b0;
    reg [8:0] x_quiet_status_coordinates = 9'b0;
    reg [8:0] z_quiet_status_coordinates = 9'b0;
    reg [2:0] first_reply_coordinates = 3'b0;
    reg [2:0] second_reply_coordinates = 3'b0;
    reg first_reply_parity = 1'b0;
    reg second_reply_parity = 1'b0;
    integer first_reply_count = 0;
    integer second_reply_count = 0;
    reg [127:0] stalled_x_announcement;
    integer cycle;

    wire [31:0] data_state_addr [0:1];
    wire [441:0] data_state_wr_data [0:1];
    wire data_state_we [0:1];
    wire data_state_re [0:1];
    wire [441:0] data_state_rd_data [0:1];
    wire [31:0] data_mailbox_addr [0:1];
    wire [127:0] data_mailbox_wr_data [0:1];
    wire data_mailbox_we [0:1];
    wire data_mailbox_re [0:1];
    wire [127:0] data_mailbox_rd_data [0:1];

    wire [31:0] phi_state_addr [0:1];
    wire [553:0] phi_state_wr_data [0:1];
    wire phi_state_we [0:1];
    wire phi_state_re [0:1];
    wire [553:0] phi_state_rd_data [0:1];
    wire [31:0] phi_mailbox_addr [0:1];
    wire [127:0] phi_mailbox_wr_data [0:1];
    wire phi_mailbox_we [0:1];
    wire phi_mailbox_re [0:1];
    wire [127:0] phi_mailbox_rd_data [0:1];

    wire [31:0] syndrome_state_addr [0:1];
    wire [441:0] syndrome_state_wr_data [0:1];
    wire syndrome_state_we [0:1];
    wire syndrome_state_re [0:1];
    wire [441:0] syndrome_state_rd_data [0:1];
    wire [31:0] syndrome_mailbox_addr [0:1];
    wire [127:0] syndrome_mailbox_wr_data [0:1];
    wire syndrome_mailbox_we [0:1];
    wire syndrome_mailbox_re [0:1];
    wire [127:0] syndrome_mailbox_rd_data [0:1];

    __phi_noise_topology__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        ._control_router_in(control_router),
        ._control_router_in_vld(control_router_valid),
        ._control_router_in_rdy(control_router_ready),
        ._x_announcements_out_rdy(
            x_announcement_ready
        ),
        ._x_announcements_out(x_announcement),
        ._x_announcements_out_vld(
            x_announcement_valid
        ),
        ._x_decoder_events_out_rdy(
            x_decoder_event_ready
        ),
        ._x_decoder_events_out(x_decoder_event),
        ._x_decoder_events_out_vld(
            x_decoder_event_valid
        ),
        ._z_announcements_out_rdy(
            z_announcement_ready
        ),
        ._z_announcements_out(z_announcement),
        ._z_announcements_out_vld(
            z_announcement_valid
        ),
        ._z_decoder_events_out_rdy(
            z_decoder_event_ready
        ),
        ._z_decoder_events_out(z_decoder_event),
        ._z_decoder_events_out_vld(
            z_decoder_event_valid
        ),
        ._data_measurements_out_rdy(
            data_measurements_ready
        ),
        ._data_measurements_out(data_measurements),
        ._data_measurements_out_vld(
            data_measurements_valid
        ),
        .scheduler_0_state_addr(data_state_addr[0]),
        .scheduler_0_state_wr_data(data_state_wr_data[0]),
        .scheduler_0_state_we(data_state_we[0]),
        .scheduler_0_state_re(data_state_re[0]),
        .scheduler_0_state_rd_data(data_state_rd_data[0]),
        .scheduler_0_mailbox_addr(data_mailbox_addr[0]),
        .scheduler_0_mailbox_wr_data(data_mailbox_wr_data[0]),
        .scheduler_0_mailbox_we(data_mailbox_we[0]),
        .scheduler_0_mailbox_re(data_mailbox_re[0]),
        .scheduler_0_mailbox_rd_data(data_mailbox_rd_data[0]),
        .scheduler_1_state_addr(data_state_addr[1]),
        .scheduler_1_state_wr_data(data_state_wr_data[1]),
        .scheduler_1_state_we(data_state_we[1]),
        .scheduler_1_state_re(data_state_re[1]),
        .scheduler_1_state_rd_data(data_state_rd_data[1]),
        .scheduler_1_mailbox_addr(data_mailbox_addr[1]),
        .scheduler_1_mailbox_wr_data(data_mailbox_wr_data[1]),
        .scheduler_1_mailbox_we(data_mailbox_we[1]),
        .scheduler_1_mailbox_re(data_mailbox_re[1]),
        .scheduler_1_mailbox_rd_data(data_mailbox_rd_data[1]),
        .scheduler_2_state_addr(phi_state_addr[0]),
        .scheduler_2_state_wr_data(phi_state_wr_data[0]),
        .scheduler_2_state_we(phi_state_we[0]),
        .scheduler_2_state_re(phi_state_re[0]),
        .scheduler_2_state_rd_data(phi_state_rd_data[0]),
        .scheduler_2_mailbox_addr(phi_mailbox_addr[0]),
        .scheduler_2_mailbox_wr_data(phi_mailbox_wr_data[0]),
        .scheduler_2_mailbox_we(phi_mailbox_we[0]),
        .scheduler_2_mailbox_re(phi_mailbox_re[0]),
        .scheduler_2_mailbox_rd_data(phi_mailbox_rd_data[0]),
        .scheduler_3_state_addr(phi_state_addr[1]),
        .scheduler_3_state_wr_data(phi_state_wr_data[1]),
        .scheduler_3_state_we(phi_state_we[1]),
        .scheduler_3_state_re(phi_state_re[1]),
        .scheduler_3_state_rd_data(phi_state_rd_data[1]),
        .scheduler_3_mailbox_addr(phi_mailbox_addr[1]),
        .scheduler_3_mailbox_wr_data(phi_mailbox_wr_data[1]),
        .scheduler_3_mailbox_we(phi_mailbox_we[1]),
        .scheduler_3_mailbox_re(phi_mailbox_re[1]),
        .scheduler_3_mailbox_rd_data(phi_mailbox_rd_data[1]),
        .scheduler_4_state_addr(syndrome_state_addr[0]),
        .scheduler_4_state_wr_data(syndrome_state_wr_data[0]),
        .scheduler_4_state_we(syndrome_state_we[0]),
        .scheduler_4_state_re(syndrome_state_re[0]),
        .scheduler_4_state_rd_data(syndrome_state_rd_data[0]),
        .scheduler_4_mailbox_addr(syndrome_mailbox_addr[0]),
        .scheduler_4_mailbox_wr_data(syndrome_mailbox_wr_data[0]),
        .scheduler_4_mailbox_we(syndrome_mailbox_we[0]),
        .scheduler_4_mailbox_re(syndrome_mailbox_re[0]),
        .scheduler_4_mailbox_rd_data(syndrome_mailbox_rd_data[0]),
        .scheduler_5_state_addr(syndrome_state_addr[1]),
        .scheduler_5_state_wr_data(syndrome_state_wr_data[1]),
        .scheduler_5_state_we(syndrome_state_we[1]),
        .scheduler_5_state_re(syndrome_state_re[1]),
        .scheduler_5_state_rd_data(syndrome_state_rd_data[1]),
        .scheduler_5_mailbox_addr(syndrome_mailbox_addr[1]),
        .scheduler_5_mailbox_wr_data(syndrome_mailbox_wr_data[1]),
        .scheduler_5_mailbox_we(syndrome_mailbox_we[1]),
        .scheduler_5_mailbox_re(syndrome_mailbox_re[1]),
        .scheduler_5_mailbox_rd_data(syndrome_mailbox_rd_data[1])
    );

    always #5 clk = ~clk;

    genvar ram_index;
    generate
        for (ram_index = 0; ram_index < 2; ram_index = ram_index + 1) begin: scheduler_rams
            hls_1rw_ram #(.WIDTH(442), .ADDRESS_WIDTH(4)) data_state (
                .clk(clk), .addr(data_state_addr[ram_index][3:0]),
                .wr_data(data_state_wr_data[ram_index]),
                .we(data_state_we[ram_index]), .re(data_state_re[ram_index]),
                .rd_data(data_state_rd_data[ram_index])
            );
            hls_1rw_ram #(.WIDTH(554), .ADDRESS_WIDTH(4)) phi_state (
                .clk(clk), .addr(phi_state_addr[ram_index][3:0]),
                .wr_data(phi_state_wr_data[ram_index]),
                .we(phi_state_we[ram_index]), .re(phi_state_re[ram_index]),
                .rd_data(phi_state_rd_data[ram_index])
            );
            hls_1rw_ram #(.WIDTH(442), .ADDRESS_WIDTH(4)) syndrome_state (
                .clk(clk), .addr(syndrome_state_addr[ram_index][3:0]),
                .wr_data(syndrome_state_wr_data[ram_index]),
                .we(syndrome_state_we[ram_index]),
                .re(syndrome_state_re[ram_index]),
                .rd_data(syndrome_state_rd_data[ram_index])
            );
            hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) data_mailbox (
                .clk(clk), .addr(data_mailbox_addr[ram_index][5:0]),
                .wr_data(data_mailbox_wr_data[ram_index]),
                .we(data_mailbox_we[ram_index]),
                .re(data_mailbox_re[ram_index]),
                .rd_data(data_mailbox_rd_data[ram_index])
            );
            hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) phi_mailbox (
                .clk(clk), .addr(phi_mailbox_addr[ram_index][5:0]),
                .wr_data(phi_mailbox_wr_data[ram_index]),
                .we(phi_mailbox_we[ram_index]),
                .re(phi_mailbox_re[ram_index]),
                .rd_data(phi_mailbox_rd_data[ram_index])
            );
            hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(6)) syndrome_mailbox (
                .clk(clk), .addr(syndrome_mailbox_addr[ram_index][5:0]),
                .wr_data(syndrome_mailbox_wr_data[ram_index]),
                .we(syndrome_mailbox_we[ram_index]),
                .re(syndrome_mailbox_re[ram_index]),
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

    function automatic [31:0] expected_x_direction;
        input [31:0] step;
        input integer coordinate;
        begin
            case ({step, coordinate})
                {32'd1, 32'd1}: expected_x_direction = WEST;
                {32'd1, 32'd6}: expected_x_direction = SOUTH;
                default: expected_x_direction = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] expected_z_direction;
        input [31:0] step;
        input integer coordinate;
        begin
            case ({step, coordinate})
                {32'd0, 32'd4}: expected_z_direction = EAST;
                {32'd1, 32'd0}: expected_z_direction = WEST;
                {32'd1, 32'd4}: expected_z_direction = SOUTH;
                default: expected_z_direction = 32'd0;
            endcase
        end
    endfunction

    task automatic record_announcement;
        input [127:0] frame;
        input [7:0] plane;
        reg [31:0] step;
        reg [31:0] flags;
        integer x;
        integer y;
        integer coordinate;
        reg [8:0] coordinate_mask;
        begin
            if (frame[127:96] !== PHENOM_ANYON_HEADER) begin
                $display(
                    "FAIL: %s announcement has malformed header %08x",
                    plane,
                    frame[127:96]
                );
                $fatal(1);
            end
            if ((^frame[95:0]) === 1'bx) begin
                $display("FAIL: %s announcement has unknown payload bits", plane);
                $fatal(1);
            end
            step = frame[31:0];
            flags = frame[63:32];
            x = frame[79:64];
            y = frame[95:80];
            if (flags > 32'd3 || x < 0 || x >= 3 || y < 0 || y >= 3) begin
                $display(
                    "FAIL: %s announcement step=%0d flags=%0d x=%0d y=%0d",
                    plane,
                    step,
                    flags,
                    x,
                    y
                );
                $fatal(1);
            end
            coordinate = 3 * x + y;
            coordinate_mask = 9'b1 << coordinate;
            if (plane == "x") begin
                case (step)
                    32'd0: begin
                        if ((x_announcements_step_0 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate x step-0 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        x_announcements_step_0 =
                            x_announcements_step_0 | coordinate_mask;
                    end
                    32'd1: begin
                        if ((x_announcements_step_1 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate x step-1 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        x_announcements_step_1 =
                            x_announcements_step_1 | coordinate_mask;
                    end
                    32'd2: begin
                        if ((x_announcements_step_2 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate x step-2 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        x_announcements_step_2 =
                            x_announcements_step_2 | coordinate_mask;
                    end
                    default: begin end
                endcase
            end else begin
                case (step)
                    32'd0: begin
                        if ((z_announcements_step_0 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate z step-0 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        z_announcements_step_0 =
                            z_announcements_step_0 | coordinate_mask;
                    end
                    32'd1: begin
                        if ((z_announcements_step_1 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate z step-1 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        z_announcements_step_1 =
                            z_announcements_step_1 | coordinate_mask;
                    end
                    32'd2: begin
                        if ((z_announcements_step_2 & coordinate_mask) != 0) begin
                            $display("FAIL: duplicate z step-2 coordinate %0d,%0d", x, y);
                            $fatal(1);
                        end
                        z_announcements_step_2 =
                            z_announcements_step_2 | coordinate_mask;
                    end
                    default: begin end
                endcase
            end
        end
    endtask

    task automatic record_status;
        input [127:0] frame;
        input [7:0] plane;
        reg [31:0] step;
        reg [31:0] flags;
        integer x;
        integer y;
        integer coordinate;
        reg [8:0] coordinate_mask;
        begin
            if (frame[127:96] !== PHI_STATUS_HEADER ||
                    (^frame[95:0]) === 1'bx) begin
                $display("FAIL: malformed %s status %032x", plane, frame);
                $fatal(1);
            end
            step = frame[31:0];
            x = frame[47:32];
            y = frame[63:48];
            flags = frame[95:64];
            if (x < 0 || x >= 3 || y < 0 || y >= 3 || flags > 3) begin
                $display(
                    "FAIL: %s status step=%0d x=%0d y=%0d flags=%0d",
                    plane, step, x, y, flags
                );
                $fatal(1);
            end
            coordinate = 3 * x + y;
            coordinate_mask = 9'b1 << coordinate;
            if (step == 32'd0 || step == 32'd1) begin
                if (plane == "x" && step == 32'd0) begin
                    if ((x_status_step_0 & coordinate_mask) != 0)
                        $fatal(1, "duplicate x step-0 status");
                    x_status_step_0 = x_status_step_0 | coordinate_mask;
                end else if (plane == "x") begin
                    if ((x_status_step_1 & coordinate_mask) != 0)
                        $fatal(1, "duplicate x step-1 status");
                    x_status_step_1 = x_status_step_1 | coordinate_mask;
                end else if (step == 32'd0) begin
                    if ((z_status_step_0 & coordinate_mask) != 0)
                        $fatal(1, "duplicate z step-0 status");
                    z_status_step_0 = z_status_step_0 | coordinate_mask;
                end else begin
                    if ((z_status_step_1 & coordinate_mask) != 0)
                        $fatal(1, "duplicate z step-1 status");
                    z_status_step_1 = z_status_step_1 | coordinate_mask;
                end
            end
            if (step == FIRST_QUIET_STEP) begin
                if (!flags[1]) begin
                    $display(
                        "FAIL: %s coordinate %0d,%0d was not quiet at step %0d",
                        plane, x, y, step
                    );
                    $fatal(1);
                end
                if (plane == "x")
                    x_quiet_status_coordinates =
                        x_quiet_status_coordinates | coordinate_mask;
                else
                    z_quiet_status_coordinates =
                        z_quiet_status_coordinates | coordinate_mask;
            end
        end
    endtask

    task automatic record_decoder_event;
        input [127:0] frame;
        input [7:0] plane;
        begin
            case (frame[103:96])
                8'd11: record_correction(frame, plane);
                8'd17: record_status(frame, plane);
                default: begin
                    $display("FAIL: unexpected %s decoder event %032x", plane, frame);
                    $fatal(1);
                end
            endcase
        end
    endtask

    task automatic record_correction;
        input [127:0] frame;
        input [7:0] plane;
        reg [31:0] step;
        reg [31:0] direction;
        reg [31:0] expected_direction;
        integer x;
        integer y;
        integer coordinate;
        reg [8:0] coordinate_mask;
        begin
            if (frame[127:96] !== PHI_CORRECTION_HEADER) begin
                $display(
                    "FAIL: %s correction has malformed header %08x",
                    plane,
                    frame[127:96]
                );
                $fatal(1);
            end
            if ((^frame[95:0]) === 1'bx) begin
                $display("FAIL: %s correction has unknown payload bits", plane);
                $fatal(1);
            end
            step = frame[31:0];
            x = frame[47:32];
            y = frame[63:48];
            direction = frame[95:64];
            if (x < 0 || x >= 3 || y < 0 || y >= 3 ||
                    !(direction == NORTH || direction == EAST ||
                      direction == WEST || direction == SOUTH)) begin
                $display(
                    "FAIL: %s correction step=%0d x=%0d y=%0d direction=%0d",
                    plane,
                    step,
                    x,
                    y,
                    direction
                );
                $fatal(1);
            end
            if (step == 32'd0 || step == 32'd1) begin
                coordinate = 3 * x + y;
                coordinate_mask = 9'b1 << coordinate;
                expected_direction = plane == "x" ?
                    expected_x_direction(step, coordinate) :
                    expected_z_direction(step, coordinate);
                $display(
                    "TRACE: %s correction step=%0d x=%0d y=%0d direction=%0d",
                    plane,
                    step,
                    x,
                    y,
                    direction
                );
                if (expected_direction == 0 || direction != expected_direction) begin
                    $display(
                        "FAIL: unexpected %s step-%0d correction at %0d,%0d",
                        plane,
                        step,
                        x,
                        y
                    );
                    $fatal(1);
                end
                if (plane == "x" && step == 32'd0) begin
                    if ((x_corrections_step_0 & coordinate_mask) != 0) begin
                        $display("FAIL: duplicate x correction at %0d,%0d", x, y);
                        $fatal(1);
                    end
                    x_corrections_step_0 =
                        x_corrections_step_0 | coordinate_mask;
                end else if (plane == "x") begin
                    if ((x_corrections_step_1 & coordinate_mask) != 0) begin
                        $display("FAIL: duplicate x correction at %0d,%0d", x, y);
                        $fatal(1);
                    end
                    x_corrections_step_1 =
                        x_corrections_step_1 | coordinate_mask;
                end else if (step == 32'd0) begin
                    if ((z_corrections_step_0 & coordinate_mask) != 0) begin
                        $display("FAIL: duplicate z correction at %0d,%0d", x, y);
                        $fatal(1);
                    end
                    z_corrections_step_0 =
                        z_corrections_step_0 | coordinate_mask;
                end else begin
                    if ((z_corrections_step_1 & coordinate_mask) != 0) begin
                        $display("FAIL: duplicate z correction at %0d,%0d", x, y);
                        $fatal(1);
                    end
                    z_corrections_step_1 =
                        z_corrections_step_1 | coordinate_mask;
                end
            end
        end
    endtask

    task automatic record_pauli_reply;
        input [127:0] frame;
        reg [31:0] request_id;
        reg [31:0] parity;
        integer x;
        integer y;
        reg [2:0] coordinate_mask;
        begin
            request_id = frame[31:0];
            x = frame[47:32];
            y = frame[63:48];
            parity = frame[95:64];
            if (frame[127:96] !== {8'd3, 8'd0, 8'd0,
                    PAULI_REPLY_TAG} || (^frame[95:0]) === 1'bx ||
                    x < 0 || x >= 3 || y != QUERY_ROW || parity > 1) begin
                $display("FAIL: malformed or out-of-line Pauli reply %032x",
                    frame);
                $fatal(1);
            end
            coordinate_mask = 3'b1 << x;
            if (request_id == FIRST_QUERY_ID) begin
                if ((first_reply_coordinates & coordinate_mask) != 0) begin
                    $display("FAIL: duplicate first Pauli reply at %0d,%0d",
                        x, y);
                    $fatal(1);
                end
                first_reply_coordinates =
                    first_reply_coordinates | coordinate_mask;
                first_reply_count = first_reply_count + 1;
                first_reply_parity = first_reply_parity ^ parity[0];
            end else if (request_id == SECOND_QUERY_ID) begin
                if ((second_reply_coordinates & coordinate_mask) != 0) begin
                    $display("FAIL: duplicate second Pauli reply at %0d,%0d",
                        x, y);
                    $fatal(1);
                end
                second_reply_coordinates =
                    second_reply_coordinates | coordinate_mask;
                second_reply_count = second_reply_count + 1;
                second_reply_parity = second_reply_parity ^ parity[0];
            end else begin
                $display("FAIL: unexpected Pauli reply request %08x",
                    request_id);
                $fatal(1);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            if (x_announcement_valid && x_announcement_ready)
                record_announcement(x_announcement, "x");
            if (z_announcement_valid && z_announcement_ready)
                record_announcement(z_announcement, "z");
            if (x_decoder_event_valid && x_decoder_event_ready)
                record_decoder_event(x_decoder_event, "x");
            if (z_decoder_event_valid && z_decoder_event_ready)
                record_decoder_event(z_decoder_event, "z");
            if (data_measurements_valid && data_measurements_ready)
                record_pauli_reply(data_measurements);
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Stall only one observation stream. The independent plane and both
        // sparse correction streams remain drainable while this frame waits.
        for (cycle = 0;
                cycle < MAX_WAIT_CYCLES &&
                    x_announcement_valid !== 1'b1;
                cycle = cycle + 1)
            @(posedge clk);
        if (x_announcement_valid !== 1'b1) begin
            $display("FAIL: timed out waiting for first x announcement");
            $fatal(1);
        end
        stalled_x_announcement = x_announcement;
        repeat (64) begin
            @(posedge clk);
            if (x_announcement_valid !== 1'b1 ||
                    x_announcement !== stalled_x_announcement) begin
                $display("FAIL: stalled x announcement was not stable");
                $fatal(1);
            end
        end
        @(negedge clk);
        x_announcement_ready = 1'b1;

        for (cycle = 0;
                cycle < MAX_WAIT_CYCLES && !(
                    x_announcements_step_0 === ALL_COORDINATES &&
                    x_announcements_step_1 === ALL_COORDINATES &&
                    x_announcements_step_2 === ALL_COORDINATES &&
                    z_announcements_step_0 === ALL_COORDINATES &&
                    z_announcements_step_1 === ALL_COORDINATES &&
                    z_announcements_step_2 === ALL_COORDINATES &&
                    x_status_step_0 === ALL_COORDINATES &&
                    x_status_step_1 === ALL_COORDINATES &&
                    z_status_step_0 === ALL_COORDINATES &&
                    z_status_step_1 === ALL_COORDINATES &&
                    x_corrections_step_0 ===
                        EXPECTED_X_CORRECTIONS_STEP_0 &&
                    x_corrections_step_1 ===
                        EXPECTED_X_CORRECTIONS_STEP_1 &&
                    z_corrections_step_0 ===
                        EXPECTED_Z_CORRECTIONS_STEP_0 &&
                    z_corrections_step_1 ===
                        EXPECTED_Z_CORRECTIONS_STEP_1
                );
                cycle = cycle + 1)
            @(posedge clk);

        // A complete status set is ordered after every source's optional
        // correction for that step, so no arbitrary merge-drain delay is
        // needed before checking the correction sets.
        @(negedge clk);

        if (x_announcements_step_0 !== ALL_COORDINATES ||
                x_announcements_step_1 !== ALL_COORDINATES ||
                x_announcements_step_2 !== ALL_COORDINATES ||
                z_announcements_step_0 !== ALL_COORDINATES ||
                z_announcements_step_1 !== ALL_COORDINATES ||
                z_announcements_step_2 !== ALL_COORDINATES) begin
            $display(
                "FAIL: incomplete announcements x0=%03x x1=%03x x2=%03x z0=%03x z1=%03x z2=%03x",
                x_announcements_step_0,
                x_announcements_step_1,
                x_announcements_step_2,
                z_announcements_step_0,
                z_announcements_step_1,
                z_announcements_step_2
            );
            $fatal(1);
        end
        if (x_status_step_0 !== ALL_COORDINATES ||
                x_status_step_1 !== ALL_COORDINATES ||
                z_status_step_0 !== ALL_COORDINATES ||
                z_status_step_1 !== ALL_COORDINATES) begin
            $display(
                "FAIL: incomplete status x0=%03x x1=%03x z0=%03x z1=%03x",
                x_status_step_0,
                x_status_step_1,
                z_status_step_0,
                z_status_step_1
            );
            $fatal(1);
        end
        if (x_corrections_step_0 !== EXPECTED_X_CORRECTIONS_STEP_0 ||
                x_corrections_step_1 !== EXPECTED_X_CORRECTIONS_STEP_1 ||
                z_corrections_step_0 !== EXPECTED_Z_CORRECTIONS_STEP_0 ||
                z_corrections_step_1 !== EXPECTED_Z_CORRECTIONS_STEP_1) begin
            $display(
                "FAIL: incomplete corrections x0=%03x x1=%03x z0=%03x z1=%03x",
                x_corrections_step_0,
                x_corrections_step_1,
                z_corrections_step_0,
                z_corrections_step_1
            );
            $fatal(1);
        end
        $display("PROGRESS: observed complete distance-three steps 0 through 2");

        // Step seven is far enough ahead of the observed step-two traffic for
        // the one whole-fabric command to reach all four noise families before
        // any selected actor makes that step's random decision.
        send_spatial(
            16'd0,
            16'd0,
            16'd2,
            16'd5,
            NOISE_TARGET,
            frame1(NOISE_CUTOFF_TAG, FIRST_QUIET_STEP)
        );

        // Quiet is persistent after the cutoff. Occupancy is deliberately not
        // part of this ingress/embedding check, but every syndrome coordinate
        // on both planes must report quiet before querying the data frame.
        for (cycle = 0;
                cycle < MAX_CONTROL_WAIT_CYCLES && !(
                    x_quiet_status_coordinates === ALL_COORDINATES &&
                    z_quiet_status_coordinates === ALL_COORDINATES
                );
                cycle = cycle + 1)
            @(posedge clk);
        @(negedge clk);
        if (x_quiet_status_coordinates !== ALL_COORDINATES ||
                z_quiet_status_coordinates !== ALL_COORDINATES) begin
            $display(
                "FAIL: incomplete quiet status x=%03x z=%03x",
                x_quiet_status_coordinates,
                z_quiet_status_coordinates
            );
            $fatal(1);
        end
        $display("PROGRESS: every distance-three source reports quiet");

        // Physical row four is data_even[X,2]. The [1,2] embedding must map
        // this one logical line to exactly X=0,1,2 and no data_odd actor.
        send_spatial(
            16'd0,
            QUERY_ROW,
            16'd2,
            QUERY_ROW,
            DATA_TARGET,
            frame2(PAULI_QUERY_TAG, FIRST_QUERY_ID, PAULI_Z)
        );
        for (cycle = 0;
                cycle < MAX_CONTROL_WAIT_CYCLES &&
                    first_reply_count < 3;
                cycle = cycle + 1)
            @(posedge clk);
        @(negedge clk);
        if (first_reply_count != 3 ||
                first_reply_coordinates !== ALL_QUERY_COORDINATES) begin
            $display(
                "FAIL: first line query replies count=%0d coordinates=%01x",
                first_reply_count,
                first_reply_coordinates
            );
            $fatal(1);
        end
        $display("PROGRESS: first distance-three line query completed");

        send_spatial(
            16'd1,
            QUERY_ROW,
            16'd1,
            QUERY_ROW,
            DATA_TARGET,
            frame1(PAULI_UPDATE_TAG, PAULI_X)
        );
        send_spatial(
            16'd0,
            QUERY_ROW,
            16'd2,
            QUERY_ROW,
            DATA_TARGET,
            frame2(PAULI_QUERY_TAG, SECOND_QUERY_ID, PAULI_Z)
        );
        for (cycle = 0;
                cycle < MAX_CONTROL_WAIT_CYCLES &&
                    second_reply_count < 3;
                cycle = cycle + 1)
            @(posedge clk);
        @(negedge clk);
        if (second_reply_count != 3 ||
                second_reply_coordinates !== ALL_QUERY_COORDINATES) begin
            $display(
                "FAIL: second line query replies count=%0d coordinates=%01x",
                second_reply_count,
                second_reply_coordinates
            );
            $fatal(1);
        end
        if (first_reply_parity == second_reply_parity) begin
            $display("FAIL: point X update did not toggle line Z parity");
            $fatal(1);
        end
        $display("PROGRESS: point update changed the line-query parity");

        // Give the measurement merge a complete polling sweep after the three
        // expected replies. Any unintended fourth reply is rejected by the
        // duplicate- and coordinate checks above.
        repeat (128) @(posedge clk);

        $display(
            "PASS: distance-three phi/noise topology and spatial ingress"
        );
        $finish;
    end
endmodule
