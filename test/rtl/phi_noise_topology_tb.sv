`timescale 1ns/1ps

module phi_noise_topology_tb;
    localparam [31:0] PHENOM_ANYON_HEADER = 32'h0300000a;
    localparam [31:0] PHI_CORRECTION_HEADER = 32'h0300000b;
    localparam [31:0] NORTH = 32'd1;
    localparam [31:0] EAST = 32'd2;
    localparam [31:0] WEST = 32'd4;
    localparam [31:0] SOUTH = 32'd8;
    localparam integer MAX_WAIT_CYCLES = 5000;
    localparam [8:0] ALL_COORDINATES = 9'h1ff;
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

    reg x_announcement_ready = 1'b0;
    wire [127:0] x_announcement;
    wire x_announcement_valid;

    wire z_announcement_ready = 1'b1;
    wire [127:0] z_announcement;
    wire z_announcement_valid;

    wire x_correction_ready = 1'b1;
    wire [127:0] x_correction;
    wire x_correction_valid;

    wire z_correction_ready = 1'b1;
    wire [127:0] z_correction;
    wire z_correction_valid;

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
    reg [127:0] stalled_x_announcement;
    integer cycle;

    __phi_noise_topology__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_noise_topology__x_announcements_out_rdy(
            x_announcement_ready
        ),
        .phi_noise_topology__x_announcements_out(x_announcement),
        .phi_noise_topology__x_announcements_out_vld(
            x_announcement_valid
        ),
        .phi_noise_topology__x_corrections_out_rdy(x_correction_ready),
        .phi_noise_topology__x_corrections_out(x_correction),
        .phi_noise_topology__x_corrections_out_vld(x_correction_valid),
        .phi_noise_topology__z_announcements_out_rdy(
            z_announcement_ready
        ),
        .phi_noise_topology__z_announcements_out(z_announcement),
        .phi_noise_topology__z_announcements_out_vld(
            z_announcement_valid
        ),
        .phi_noise_topology__z_corrections_out_rdy(z_correction_ready),
        .phi_noise_topology__z_corrections_out(z_correction),
        .phi_noise_topology__z_corrections_out_vld(z_correction_valid)
    );

    always #5 clk = ~clk;

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
        reg [31:0] present;
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
            present = frame[63:32];
            x = frame[79:64];
            y = frame[95:80];
            if (present > 32'd1 || x < 0 || x >= 3 || y < 0 || y >= 3) begin
                $display(
                    "FAIL: %s announcement step=%0d present=%0d x=%0d y=%0d",
                    plane,
                    step,
                    present,
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

    always @(posedge clk) begin
        if (!reset) begin
            if (x_announcement_valid && x_announcement_ready)
                record_announcement(x_announcement, "x");
            if (z_announcement_valid && z_announcement_ready)
                record_announcement(z_announcement, "z");
            if (x_correction_valid && x_correction_ready)
                record_correction(x_correction, "x");
            if (z_correction_valid && z_correction_ready)
                record_correction(z_correction, "z");
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

        // All actors have begun step two, so their step-one correction actions
        // are behind them. Give the independent polling merges time to drain
        // before declaring the unordered correction sets complete.
        repeat (64) @(posedge clk);
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

        $display("PASS: distance-three phi/noise topology");
        $finish;
    end
endmodule
