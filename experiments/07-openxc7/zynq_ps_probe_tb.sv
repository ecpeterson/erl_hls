`timescale 1ns/1ps
// Exercise only the AXI/reset boundary: no internal register or state peeking.
module zynq_ps_probe_tb;
    reg clock = 0, raw_reset_n = 0;
    wire reset_n;
    reg [11:0] awid = 0, wid = 0, arid = 0;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] awlen = 0, arlen = 0, wstrb = 0;
    reg [2:0] awsize = 2, arsize = 2;
    reg [1:0] awburst = 1, arburst = 1, awlock = 0, arlock = 0;
    reg awvalid = 0, wvalid = 0, wlast = 1, bready = 0;
    reg arvalid = 0, rready = 0;
    wire awready, wready, bvalid, arready, rvalid, rlast;
    wire [11:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg [127:0] status = 0;
    wire [31:0] control;
    reg [31:0] model_scratch = 0, model_writes = 0, sample, earlier;
    integer trial, lane, beats;
    localparam [31:0] BASE = 32'h40000000;

    zynq_probe_reset sync_reset(clock, raw_reset_n, reset_n);
`ifdef MAPPED
    zynq_ps_probe_mapped dut(.*);
`else
`ifdef EXTENDED
    zynq_ps_probe #(.EXTENDED(1)) dut(.*);
`else
    zynq_ps_probe dut(.*);
`endif
`endif

    // Advance one edge and allow all sequential/combinational outputs to settle.
    task automatic tick;
        begin #4; clock = 1; #1; clock = 0; #1; end
    endtask

    // Assert while the clock is stopped; release must wait two clock edges.
    task automatic reset_probe;
        begin
            raw_reset_n = 0; #1;
            if (reset_n !== 0 || bvalid !== 0 || rvalid !== 0 ||
                awready !== 0 || wready !== 0 || arready !== 0)
                $fatal(1, "asynchronous reset failed rst=%b b=%b r=%b aw=%b w=%b ar=%b", reset_n, bvalid, rvalid, awready, wready, arready);
            awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
            raw_reset_n = 1; #3;
            if (reset_n !== 0) $fatal(1, "unclocked reset release");
            tick;
            if (reset_n !== 0) $fatal(1, "early reset release");
            tick;
            if (reset_n !== 1) $fatal(1, "reset did not release");
            tick;
            if (bvalid || rvalid || !awready || !arready) $fatal(1, "stale response after reset");
            model_scratch = 0; model_writes = 0;
        end
    endtask

    // Accept an address, then change its live inputs to expose missing latches.
    task automatic start_write(input [31:0] address, input [11:0] id, input [3:0] len,
                               input [2:0] size, input [1:0] lock_value, input [1:0] burst);
        begin
            awaddr = address; awid = id; awlen = len; awsize = size;
            awlock = lock_value; awburst = burst; awvalid = 1; #1;
            if (!awready) $fatal(1, "write address did not become ready");
            tick;
            awvalid = 0; awaddr = ~address; awid = ~id; awlen = ~len; #1;
            if (awready) $fatal(1, "accepted another outstanding write");
        end
    endtask

    // Send one data beat. WVALID may also have been held before the address.
    task automatic write_beat(input [31:0] data, input [3:0] strobes,
                              input [11:0] id, input last);
        begin
            wdata = data; wstrb = strobes; wid = id; wlast = last; wvalid = 1; #1;
            if (!wready) $fatal(1, "write data did not become ready");
            tick;
            wvalid = 0; wdata = ~data; wid = ~id; wstrb = ~strobes; #1;
        end
    endtask

    // Responses and IDs must remain stable while the master withholds BREADY.
    task automatic finish_write(input [11:0] id, input [1:0] response, input integer stall);
        integer n;
        begin
            bready = 0;
            for (n = 0; n <= stall; n = n + 1) begin
                #1;
                if (!bvalid || bid !== id || bresp !== response || awready || wready)
                    $fatal(1, "write response/stall mismatch: id=%h resp=%h", bid, bresp);
                if (n != stall) tick;
            end
            bready = 1; tick; bready = 0; awvalid = 0; #1;
            if (bvalid || !awready) $fatal(1, "write response duplicated");
        end
    endtask

    // Check captured data/ID/RLAST through stalls and the whole advertised burst.
    task automatic read_value(input [31:0] address, input [11:0] id, input [3:0] len,
                              input [2:0] size, input [1:0] lock_value, input [1:0] burst,
                              input [1:0] response, input integer stall, output [31:0] value);
        integer n, beat;
        reg [31:0] held;
        begin
            araddr = address; arid = id; arlen = len; arsize = size;
            arlock = lock_value; arburst = burst; arvalid = 1; rready = 0; #1;
            if (!arready) $fatal(1, "read address did not become ready");
            tick;
            arvalid = 0; araddr = ~address; arid = ~id; arlen = ~len;
            held = rdata; value = rdata;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                for (n = 0; n <= stall; n = n + 1) begin
                    #1;
                    if (!rvalid || rid !== id || rresp !== response || rdata !== held ||
                        rlast !== (beat == len) || arready)
                        $fatal(1, "read response mismatch addr=%h beat=%0d data=%h resp=%h", address, beat, rdata, rresp);
                    if (n != stall) tick;
                end
                rready = 1; tick; rready = 0;
            end
            arvalid = 0; #1;
            if (rvalid || !arready) $fatal(1, "read response duplicated");
        end
    endtask

    // Observe scratch and completed writes through public register reads.
    task automatic check_state;
        reg [31:0] result;
        begin
            read_value(BASE+8, 12'hfed, 0, 2, 0, 1, 0, 2, result);
            if (result !== model_scratch) $fatal(1, "scratch mismatch %h != %h", result, model_scratch);
            read_value(BASE+16, 12'h102, 0, 2, 0, 1, 0, 1, result);
            if (result !== model_writes) $fatal(1, "write count mismatch %d != %d", result, model_writes);
        end
    endtask

    initial begin
        // Sample the initial held reset before testing runtime asynchronous edges.
        tick;
        reset_probe;
        read_value(BASE, 12'habc, 0, 2, 0, 1, 0, 7, sample);
        if (sample !== 32'h45524c48) $fatal(1, "identity mismatch");
        read_value(BASE+4, 12'hfff, 0, 2, 0, 0, 0, 0, sample);
        if (sample !== 1) $fatal(1, "ABI mismatch");
        check_state;
        // Extension reads snapshot each selected word and never grant writes.
        for (trial = 0; trial < 4; trial = trial + 1) begin
            status = 128'h44444444333333332222222211111111;
`ifdef EXTENDED
            read_value(BASE+20+4*trial, 12'h234, 0, 2, 0, 1, 0, 5, sample);
            if (sample !== status[32*trial +: 32]) $fatal(1, "extension word mismatch");
`else
            read_value(BASE+20+4*trial, 12'h234, 0, 2, 0, 1, 2, 5, sample);
`endif
            start_write(BASE+20+4*trial, 12'h234, 0, 2, 0, 1);
            write_beat(32'hdeadbeef, 15, 12'h234, 1);
            finish_write(12'h234, 2, 0);
        end
`ifdef EXTENDED
        araddr = BASE+20; arlen = 0; arsize = 2; arlock = 0; arburst = 1;
        arvalid = 1; tick; arvalid = 0;
        status = 0; repeat (5) tick;
        if (rdata !== 32'h11111111) $fatal(1, "live status changed a stalled response");
        rready = 1; tick; rready = 0;
`endif

        // Cover every byte mask and both address-first and data-first arrival.
        for (trial = 0; trial < 64; trial = trial + 1) begin
            wdata = 32'hc39a716e ^ (32'h01020304 * trial);
            wstrb = trial % 16; wid = trial + 12'h120; wlast = 1;
            wvalid = trial % 2;
            if (wvalid) begin
                repeat (3) begin
                    #1; if (wready || bvalid) $fatal(1, "data accepted before AW"); tick;
                end
            end
            start_write(BASE+8, trial+12'h120, 0, 2, 0, trial%2);
            // AW acceptance is independent of whether WVALID arrived first.
            for (lane = 0; lane < 4; lane = lane + 1)
                if ((trial % 16) & (1 << lane))
                    model_scratch[8*lane +: 8] = wdata[8*lane +: 8];
            write_beat(wdata, trial%16, trial+12'h120, 1);
            model_writes = model_writes + 1;
            finish_write(trial+12'h120, 0, trial%5);
            check_state;
        end

        // Decode the whole address; reject misalignment, narrow access and locks.
        read_value(BASE+32'h1008, 1, 0, 2, 0, 1, 2, 2, sample);
        if (sample !== 0) $fatal(1, "bad address leaked data");
        read_value(BASE+9, 2, 0, 2, 0, 1, 2, 0, sample);
        read_value(BASE+8, 3, 0, 1, 0, 1, 2, 0, sample);
        read_value(BASE+8, 4, 0, 2, 1, 1, 2, 0, sample);
        read_value(BASE+8, 5, 0, 2, 0, 2, 2, 0, sample);
        for (trial = 0; trial < 7; trial = trial + 1) begin
            start_write(trial == 0 ? BASE : trial == 1 ? BASE+9 : trial == 2 ? BASE+32'h1008 : BASE+8,
                        12'h678, 0, trial == 3 ? 1 : 2, trial == 4 ? 1 : 0, trial == 5 ? 2 : 1);
            write_beat(32'hffffffff, 15, trial == 6 ? 12'h679 : 12'h678, 1);
            finish_write(12'h678, 2, 1);
            check_state;
        end
        start_write(BASE+8, 12'h678, 0, 2, 0, 1);
        write_beat(32'hffffffff, 15, 12'h678, 0);
        finish_write(12'h678, 2, 0);
        check_state;

        // Unsupported bursts still drain exactly LEN+1 beats, including LEN=15.
        for (beats = 2; beats <= 16; beats = beats + 7) begin
            start_write(BASE+8, 12'h987, beats-1, 2, 0, 1);
            for (trial = 0; trial < beats; trial = trial + 1) begin
                write_beat(trial, 15, 12'h987, trial == beats-1);
                if (trial != beats-1 && bvalid) $fatal(1, "early burst B response");
                tick;
            end
            finish_write(12'h987, 2, 3);
            read_value(BASE+8, 12'h456, beats-1, 2, 0, 1, 2, 2, sample);
            if (sample !== 0) $fatal(1, "unsupported burst leaked data");
            check_state;
        end

        // Same-edge read/write snapshots the old scratch, then exposes the new one.
        start_write(BASE+8, 12'h111, 0, 2, 0, 1);
        araddr = BASE+8; arid = 12'h222; arlen = 0; arsize = 2;
        arlock = 0; arburst = 1; arvalid = 1;
        write_beat(32'h01234567, 15, 12'h111, 1); arvalid = 0;
        if (!rvalid || rdata !== model_scratch || rid !== 12'h222)
            $fatal(1, "concurrent read/write ordering mismatch");
        model_scratch = 32'h01234567; model_writes = model_writes + 1;
        if (control !== model_scratch) $fatal(1, "control did not follow scratch");
        finish_write(12'h111, 0, 3);
        rready = 1; tick; rready = 0;
        check_state;
        read_value(BASE+12, 0, 0, 2, 0, 1, 0, 0, earlier);
        repeat (10) tick;
        read_value(BASE+12, 0, 0, 2, 0, 1, 0, 0, sample);
        if (sample - earlier != 12) $fatal(1, "cycle counter did not follow FCLK");

        // Reset each occupied channel: waiting for data, partial burst, and stalled
        // B/R responses. No pre-reset transaction may reappear after release.
        start_write(BASE+8, 1, 0, 2, 0, 1); reset_probe; check_state;
        start_write(BASE+8, 2, 3, 2, 0, 1);
        write_beat(1, 15, 2, 0); reset_probe; check_state;
        start_write(BASE+8, 3, 0, 2, 0, 1); write_beat(1, 15, 3, 1);
        araddr = BASE; arid = 4; arlen = 3; arsize = 2; arlock = 0; arburst = 1; arvalid = 1;
        tick; arvalid = 0;
        if (!rvalid || !bvalid) $fatal(1, "reset test did not fill both responses");
        reset_probe; check_state;
        $display("PASS: PS probe AXI ordering, byte masks, IDs, stalls, errors, bursts and resets");
        $finish;
    end
    initial begin #1000000; $fatal(1, "timeout"); end
endmodule
