// Test-only host: invoke the real Erlang reducer at each accepted output packet.
// Blocking FIFO exchange advances no simulation time. Only public ports are read.
integer host_requests, host_responses, scan;
reg profile_finished = 0;
reg [32:0] command_words [0:3][0:4095];
integer command_head [0:3], command_tail [0:3];
reg [31:0] response_words [0:3][0:15];
integer response_size [0:3];
integer activity;
reg [7:0] last_activity0 = 8'hff, last_activity1 = 8'hff;
wire [7:0] activity0 = {tx0_valid, tx0_ready, link10_valid, link10_ready,
    app0_response_valid, app0_response_ready, app0_request_valid, app0_request_ready};
wire [7:0] activity1 = {tx1_valid, tx1_ready, link01_valid, link01_ready,
    app1_response_valid, app1_response_ready, app1_request_valid, app1_request_ready};

// Record changes in public handshakes, sufficient to reconstruct every cycle.
always @(posedge clk0) if (resetn && !reset0) begin
    if (activity0 !== last_activity0) begin
        $fdisplay(activity, "%0d 0 %0d %02h", $time, cycles0, activity0);
        last_activity0 = activity0;
    end
end
always @(posedge clk1) if (resetn && !reset1) begin
    if (activity1 !== last_activity1) begin
        $fdisplay(activity, "%0d 1 %0d %02h", $time, cycles1, activity1);
        last_activity1 = activity1;
    end
end

// A response is a count followed by (device, length, words...) packets.
// Checked finite queues retain each command through its final accepted beat.
task read_commands;
    integer count, d, n, p, w;
    reg [31:0] value;
    begin
        scan = $fscanf(host_responses, "%h", count);
        if (scan != 1 || count < -1 || count > 128) $fatal(1, "invalid host batch");
        if (count == -1) profile_finished = 1;
        for (p = 0; p < count; p = p+1) begin
            scan = $fscanf(host_responses, "%h %h", d, n);
            if (scan != 2 || d < 0 || d > 3 || n < 2 || n > 15) $fatal(1, "invalid host packet");
            if (command_tail[d]-command_head[d]+n > 4096) $fatal(1, "host queue overflow");
            for (w = 0; w < n; w = w+1) begin
                scan = $fscanf(host_responses, "%h", value);
                if (scan != 1) $fatal(1, "truncated host packet");
                command_words[d][command_tail[d] % 4096] = {w == n-1, value};
                command_tail[d] = command_tail[d]+1;
            end
        end
    end
endtask

// Both response streams share the host clock; their packet buffers remain separate.
task accept_response(input integer d, input [31:0] word, input last);
    integer i;
    begin
        if (response_size[d] >= 15) $fatal(1, "oversized application packet");
        response_words[d][response_size[d]] = word;
        response_size[d] = response_size[d]+1;
        if (last && !profile_finished) begin
            $fwrite(host_requests, "%08h %08h\n", d, response_size[d]);
            for (i = 0; i < response_size[d]; i = i+1)
                $fwrite(host_requests, " %08h", response_words[d][i]);
            $fwrite(host_requests, "\n"); $fflush(host_requests);
            read_commands;
            response_size[d] = 0;
        end
    end
endtask

initial begin
    for (integer d = 0; d < 4; d = d+1) begin
        command_head[d] = 0; command_tail[d] = 0; response_size[d] = 0;
    end
    activity = $fopen("activity.log", "w");
    host_requests = $fopen("host_requests", "w");
    host_responses = $fopen("host_responses", "r");
    if (!activity || !host_requests || !host_responses) $fatal(1, "cannot open profile transport");
    read_commands;
    m_app0_tready = 1; m_app1_tready = 1;
    m_axis_tready = 1; m_dbg_tready = 1;
end
always @(posedge clk) if (resetn) begin
    if ((^{s_app0_tvalid, s_app1_tvalid, s_axis_tvalid, s_dbg_tvalid,
           m_app0_tvalid, m_app1_tvalid, m_axis_tvalid, m_dbg_tvalid}) === 1'bx)
        $fatal(1, "unknown public application/debug valid");
    if (s_app0_tvalid && s_app0_tready) command_head[0] = command_head[0]+1;
    if (s_app1_tvalid && s_app1_tready) command_head[1] = command_head[1]+1;
    if (s_axis_tvalid && s_axis_tready) command_head[2] = command_head[2]+1;
    if (s_dbg_tvalid && s_dbg_tready) command_head[3] = command_head[3]+1;
    if (m_axis_tvalid && m_axis_tready) accept_response(2, m_axis_tdata, m_axis_tlast);
    if (m_dbg_tvalid && m_dbg_tready) accept_response(3, m_dbg_tdata, m_dbg_tlast);
    if (m_app0_tvalid && m_app0_tready) accept_response(0, m_app0_tdata, m_app0_tlast);
    if (m_app1_tvalid && m_app1_tready) accept_response(1, m_app1_tdata, m_app1_tlast);
end
always @(negedge clk) begin
    s_app0_tvalid = resetn && command_head[0] < command_tail[0];
    s_app1_tvalid = resetn && command_head[1] < command_tail[1];
    s_axis_tvalid = resetn && command_head[2] < command_tail[2];
    s_dbg_tvalid = resetn && command_head[3] < command_tail[3];
    if (s_axis_tvalid) {s_axis_tlast, s_axis_tdata} = command_words[2][command_head[2] % 4096];
    if (s_dbg_tvalid) {s_dbg_tlast, s_dbg_tdata} = command_words[3][command_head[3] % 4096];
    if (s_app0_tvalid) {s_app0_tlast, s_app0_tdata} = command_words[0][command_head[0] % 4096];
    if (s_app1_tvalid) {s_app1_tlast, s_app1_tdata} = command_words[1][command_head[1] % 4096];
end

// The selected oracle is complete; remaining autonomous output is outside its finite witness.
always @(negedge clk) if (profile_finished) begin
    if (command_head[0] != command_tail[0] || command_head[1] != command_tail[1])
        $fatal(1, "unfinished host commands at closeout");
    $display("PASS: two-device phi service profile clocks=%0d/%0d ns", 2*half0, 2*half1);
    $finish;
end

// Word timestamps distinguish data packets from credit returns without inspecting proc state.
integer traffic;
initial traffic = $fopen("traffic.log", "w");
always @(posedge clk0) if (resetn && !reset0 && tx0_valid && tx0_ready)
    $fdisplay(traffic, "%0d 0 %09h", $time, tx0_data);
always @(posedge clk1) if (resetn && !reset1 && tx1_valid && tx1_ready)
    $fdisplay(traffic, "%0d 1 %09h", $time, tx1_data);
