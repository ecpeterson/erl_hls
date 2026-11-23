// Test-only physical adapters: four public word streams cross the host/device
// clocks. Application framing, identity and ordering live in the XLS gateway.
reg allow_events = 0;
reg block_commands = 0;
integer activation = 0;
`ifdef PHI_PROFILE
initial begin allow_events = 1; activation = 1; end
`endif
integer commands, progress;
initial begin
    progress = $fopen("progress.log", "w");
    if (!progress) $fatal(1, "cannot open progress log");
    commands = $fopen("commands.log", "w");
    if (!commands) $fatal(1, "cannot open command admission log");
end
always @(negedge clk) if (resetn && cycles % 100 == 0) begin
    fd = $fopen("release_events", "r");
    if (fd) begin allow_events = 1; $fclose(fd); end
    if (activation == 0) begin
        fd = $fopen("hold_commands", "r");
        if (fd) begin
            block_commands = 1; $fclose(fd);
            fd = $fopen("commands_armed", "w"); $fclose(fd);
        end
    end
end

// Test-only out-of-band reset control. First isolate/reset every clock domain;
// the host must confirm raw descriptor closure before permitting fresh FIFOs.
integer reset_fd;
initial begin
    wait(resetn);
    forever begin
        @(negedge clk);
        reset_fd = $fopen("reset_hold", "r");
        if (reset_fd && activation == 0) begin
            $fclose(reset_fd);
            resetn = 0; reset = 1; paused = 0;
            block_commands = 0;
            repeat (8) @(negedge clk0);
            repeat (8) @(negedge clk1);
            reset_fd = $fopen("reset_held", "w"); $fclose(reset_fd);
            reset_fd = 0;
            while (!reset_fd) begin
                @(negedge clk);
                reset_fd = $fopen("reset_release", "r");
            end
            $fclose(reset_fd);
            activation = 1;
            reset = 0; resetn = 1;
            wait(!reset0 && !reset1);
            reset_fd = $fopen("reactivated", "w"); $fclose(reset_fd);
        end else if (reset_fd) $fclose(reset_fd);
    end
end

// Only public transfers are counted. The first response is the attachment
// acknowledgment; subsequent output is held until public debug diagnoses it.
`define MEMORY_STREAM(D, CLOCK, RESET) \
    reg [31:0] s_app``D``_tdata = 0; \
    reg [3:0] s_app``D``_tkeep = 15; \
    reg s_app``D``_tlast = 0, s_app``D``_tvalid = 0; \
    wire s_app``D``_tready; \
    wire [31:0] m_app``D``_tdata; \
    wire [3:0] m_app``D``_tkeep; \
    wire m_app``D``_tlast, m_app``D``_tvalid; \
    reg m_app``D``_tready = 0; \
    wire [31:0] app``D``_request_data, app``D``_response_data; \
    wire [3:0] app``D``_request_keep; \
    wire app``D``_request_last, app``D``_request_valid, app``D``_request_ready; \
    wire app``D``_cross_valid, app``D``_cross_ready; \
    wire app``D``_response_last, app``D``_response_valid, app``D``_response_ready; \
    wire app``D``_crossing_ready; \
    reg app``D``_attached = 0; \
    reg app``D``_command_stopped = 0; \
    reg [1:0] app``D``_request_stage = 0; \
    reg [7:0] app``D``_operation = 0; \
    integer app``D``_commands = 0; \
    integer app``D``_marker; \
    wire app``D``_admit = !app``D``_attached || allow_events; \
    assign app``D``_response_ready = app``D``_admit && app``D``_crossing_ready; \
    assign app``D``_request_valid = app``D``_cross_valid && !app``D``_command_stopped; \
    assign app``D``_cross_ready = app``D``_request_ready && !app``D``_command_stopped; \
    hls_async_fifo #(.WIDTH(37)) app``D``_request_crossing( \
        .reset(reset), .wr_clk(clk), .rd_clk(CLOCK), \
        .in_data({s_app``D``_tlast, s_app``D``_tkeep, s_app``D``_tdata}), \
        .in_valid(s_app``D``_tvalid), .in_ready(s_app``D``_tready), \
        .out_data({app``D``_request_last, app``D``_request_keep, app``D``_request_data}), \
        .out_valid(app``D``_cross_valid), .out_ready(app``D``_cross_ready)); \
    hls_async_fifo #(.WIDTH(37)) app``D``_response_crossing( \
        .reset(reset), .wr_clk(CLOCK), .rd_clk(clk), \
        .in_data({app``D``_response_last, 4'hf, app``D``_response_data}), \
        .in_valid(app``D``_response_valid && app``D``_admit), .in_ready(app``D``_crossing_ready), \
        .out_data({m_app``D``_tlast, m_app``D``_tkeep, m_app``D``_tdata}), \
        .out_valid(m_app``D``_tvalid), .out_ready(m_app``D``_tready)); \
    // Capture only accepted public output beats; time is in this testbench's ns units. \
    always @(posedge CLOCK) if (resetn && !RESET && app``D``_response_valid && app``D``_response_ready) begin \
        $fdisplay(progress, "%0d %0d %0d %0d %08h %0d", activation, D, cycles``D, $time, app``D``_response_data, app``D``_response_last); \
        $fflush(progress); \
    end \
    always @(posedge CLOCK) begin \
        if (RESET) begin \
            app``D``_attached <= 0; \
            app``D``_command_stopped <= 0; \
            app``D``_request_stage <= 0; \
            app``D``_commands <= 0; \
        end else begin \
            if (app``D``_response_valid && app``D``_response_ready && app``D``_response_last) \
                app``D``_attached <= 1; \
            if (app``D``_request_valid && app``D``_request_ready) begin \
                if (app``D``_request_keep != 15) $fatal(1, "partial application word"); \
                if (app``D``_request_stage == 1) app``D``_operation <= app``D``_request_data[31:24]; \
                if (block_commands && app``D``_request_stage == 2 && !app``D``_request_last) begin \
                    app``D``_command_stopped <= 1; \
                    app``D``_marker = $fopen($sformatf("partial-command-%0d", D), "w"); \
                    $fdisplay(app``D``_marker, "%0d", app``D``_operation); $fclose(app``D``_marker); \
                end \
                if (app``D``_request_last) begin \
                    if (app``D``_request_stage == 2 && app``D``_operation == 2) begin \
                        $fdisplay(commands, "%0d %0d %0d", activation, D, app``D``_commands); \
                        $fflush(commands); \
                        app``D``_commands <= app``D``_commands + 1; \
                    end \
                    app``D``_request_stage <= 0; \
                end else if (app``D``_request_stage < 2) app``D``_request_stage <= app``D``_request_stage + 1; \
            end \
        end \
    end

`MEMORY_STREAM(0, clk0, reset0)
`MEMORY_STREAM(1, clk1, reset1)
`undef MEMORY_STREAM
