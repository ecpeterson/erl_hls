`timescale 1ns/1ps

module phi_decoder_profile_tb;
    localparam [31:0] PHI_CORRECTION_HEADER = 32'h0300000b;
    localparam [31:0] PHI_STATUS_HEADER = 32'h03000011;
    localparam [31:0] NORTH = 32'd1;
    localparam [31:0] EAST = 32'd2;
    localparam [31:0] WEST = 32'd4;
    localparam [31:0] SOUTH = 32'd8;
    localparam [8:0] ALL_COORDINATES = 9'h1ff;
    localparam integer WARMUP_STEP = 8;
    localparam integer TARGET_STEP = 32;
    localparam integer MAX_CYCLES = 500000;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    wire [127:0] x_decoder_event;
    wire x_decoder_event_valid;
    wire [127:0] z_decoder_event;
    wire z_decoder_event_valid;
    wire x_decoder_event_ready = 1'b1;
    wire z_decoder_event_ready = 1'b1;

    reg [8:0] x_status [0:TARGET_STEP];
    reg [8:0] z_status [0:TARGET_STEP];
    integer x_corrections = 0;
    integer z_corrections = 0;
    integer cycle_count = 0;
    integer source_state_reads = 0;
    integer phi_state_reads = 0;
    integer source_mailbox_reads = 0;
    integer phi_mailbox_reads = 0;
    integer warmup_cycle;
    integer target_cycle;
    integer measured_cycles;
    integer index;

    phi_decoder_profile_top dut (
        .aclk(clk),
        .aresetn(resetn),
        .x_decoder_event(x_decoder_event),
        .x_decoder_event_valid(x_decoder_event_valid),
        .x_decoder_event_ready(x_decoder_event_ready),
        .z_decoder_event(z_decoder_event),
        .z_decoder_event_valid(z_decoder_event_valid),
        .z_decoder_event_ready(z_decoder_event_ready)
    );

    always #5 clk = ~clk;

    task automatic record_event;
        input [127:0] frame;
        input integer plane;
        reg [31:0] step;
        reg [31:0] value;
        integer x;
        integer y;
        integer coordinate;
        reg [8:0] coordinate_mask;
        begin
            if ((^frame) === 1'bx) begin
                $display("FAIL: plane %0d emitted unknown bits: %032x",
                    plane, frame);
                $fatal(1);
            end
            step = frame[31:0];
            x = frame[47:32];
            y = frame[63:48];
            value = frame[95:64];
            if (x < 0 || x >= 3 || y < 0 || y >= 3) begin
                $display("FAIL: plane %0d emitted out-of-range coordinate %0d,%0d",
                    plane, x, y);
                $fatal(1);
            end
            coordinate = 3 * x + y;
            coordinate_mask = 9'b1 << coordinate;
            case (frame[127:96])
                PHI_CORRECTION_HEADER: begin
                    if (!(value == NORTH || value == EAST ||
                            value == WEST || value == SOUTH)) begin
                        $display("FAIL: invalid direction %0d", value);
                        $fatal(1);
                    end
                    if (plane == 0)
                        x_corrections = x_corrections + 1;
                    else
                        z_corrections = z_corrections + 1;
                end
                PHI_STATUS_HEADER: begin
                    if (value > 3) begin
                        $display("FAIL: invalid status flags %0d", value);
                        $fatal(1);
                    end
                    if (step <= TARGET_STEP) begin
                        if (plane == 0) begin
                            if ((x_status[step] & coordinate_mask) != 0) begin
                                $display("FAIL: duplicate x status at step %0d, %0d,%0d",
                                    step, x, y);
                                $fatal(1);
                            end
                            x_status[step] = x_status[step] | coordinate_mask;
                        end else begin
                            if ((z_status[step] & coordinate_mask) != 0) begin
                                $display("FAIL: duplicate z status at step %0d, %0d,%0d",
                                    step, x, y);
                                $fatal(1);
                            end
                            z_status[step] = z_status[step] | coordinate_mask;
                        end
                    end
                end
                default: begin
                    $display("FAIL: unexpected decoder event %032x", frame);
                    $fatal(1);
                end
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (resetn) begin
            cycle_count = cycle_count + 1;
            source_state_reads = source_state_reads +
                dut.scheduler_0_state_rd_en + dut.scheduler_1_state_rd_en;
            phi_state_reads = phi_state_reads +
                dut.scheduler_2_state_rd_en + dut.scheduler_3_state_rd_en +
                dut.scheduler_4_state_rd_en + dut.scheduler_5_state_rd_en +
                dut.scheduler_6_state_rd_en + dut.scheduler_7_state_rd_en;
            source_mailbox_reads = source_mailbox_reads +
                dut.scheduler_0_mailbox_rd_en +
                dut.scheduler_1_mailbox_rd_en;
            phi_mailbox_reads = phi_mailbox_reads +
                dut.scheduler_2_mailbox_rd_en +
                dut.scheduler_3_mailbox_rd_en +
                dut.scheduler_4_mailbox_rd_en +
                dut.scheduler_5_mailbox_rd_en +
                dut.scheduler_6_mailbox_rd_en +
                dut.scheduler_7_mailbox_rd_en;
            if (x_decoder_event_valid && x_decoder_event_ready)
                record_event(x_decoder_event, 0);
            if (z_decoder_event_valid && z_decoder_event_ready)
                record_event(z_decoder_event, 1);
        end
    end

    initial begin
        for (index = 0; index <= TARGET_STEP; index = index + 1) begin
            x_status[index] = 9'b0;
            z_status[index] = 9'b0;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        while (cycle_count < MAX_CYCLES &&
                !(x_status[WARMUP_STEP] == ALL_COORDINATES &&
                  z_status[WARMUP_STEP] == ALL_COORDINATES))
            @(negedge clk);
        if (cycle_count >= MAX_CYCLES) begin
            $display("FAIL: decoder did not complete warmup step %0d",
                WARMUP_STEP);
            $fatal(1);
        end
        warmup_cycle = cycle_count;

        while (cycle_count < MAX_CYCLES &&
                !(x_status[TARGET_STEP] == ALL_COORDINATES &&
                  z_status[TARGET_STEP] == ALL_COORDINATES))
            @(negedge clk);
        if (cycle_count >= MAX_CYCLES) begin
            $display("FAIL: decoder did not complete target step %0d",
                TARGET_STEP);
            $fatal(1);
        end
        target_cycle = cycle_count;
        measured_cycles = target_cycle - warmup_cycle;

        if (x_corrections == 0 || z_corrections == 0) begin
            $display("FAIL: trivial replay produced x=%0d z=%0d corrections",
                x_corrections, z_corrections);
            $fatal(1);
        end
        for (index = 0; index <= TARGET_STEP; index = index + 1) begin
            if (x_status[index] != ALL_COORDINATES ||
                    z_status[index] != ALL_COORDINATES) begin
                $display("FAIL: incomplete status set at step %0d: x=%03x z=%03x",
                    index, x_status[index], z_status[index]);
                $fatal(1);
            end
        end

        $display(
            "PROFILE_RESULT warmup_step=%0d target_step=%0d measured_cycles=%0d cycles_per_step=%0f projected_steps_per_second_200mhz=%0f",
            WARMUP_STEP,
            TARGET_STEP,
            measured_cycles,
            measured_cycles * 1.0 / (TARGET_STEP - WARMUP_STEP),
            200000000.0 * (TARGET_STEP - WARMUP_STEP) / measured_cycles
        );
        $display(
            "PROFILE_ACTIVITY total_cycles=%0d source_state_reads=%0d phi_state_reads=%0d source_mailbox_reads=%0d phi_mailbox_reads=%0d x_corrections=%0d z_corrections=%0d",
            cycle_count,
            source_state_reads,
            phi_state_reads,
            source_mailbox_reads,
            phi_mailbox_reads,
            x_corrections,
            z_corrections
        );
        $display("PASS: decoder-only request-paced profile completed");
        $finish;
    end
endmodule
