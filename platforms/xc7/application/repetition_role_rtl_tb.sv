`timescale 1ns/1ps

`ifndef MAX_CYCLES
`define MAX_CYCLES 20000
`endif

// Exercise one generated role through its public gateway while accepting every
// private-link word. ROLE_B selects the role-B deployment vectors.
module repetition_role_rtl_tb;
    reg clock = 0;
    reg reset = 1;
    always #5 clock = !clock;

    wire [32:0] link_out;
    wire link_out_valid;
    wire [31:0] fault;
    wire fault_valid;
    wire [32:0] app_out;
    wire app_out_valid;
    wire app_in_ready;
    wire [4:0] scheduler_probe;
    reg [32:0] app_in = 0;
    reg app_in_valid = 0;
    integer app_in_words = 0;
    integer app_out_words = 0;
    integer app_out_frames = 0;
    integer link_words = 0;
    integer link_frames = 0;
    integer state_reads = 0;
    integer state_writes = 0;
    integer mailbox_reads = 0;
    integer mailbox_writes = 0;
    integer mailbox_snapshots = 0;
    integer cycle = 0;

    role_model dut(
        .clk(clock), .reset(reset),
        ._link_0_in(33'b0), ._link_0_in_vld(1'b0), ._link_0_in_rdy(),
        ._link_0_out(link_out), ._link_0_out_vld(link_out_valid),
        ._link_0_out_rdy(1'b1),
        ._fault_0_out(fault), ._fault_0_out_vld(fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(app_in), ._app_in_vld(app_in_valid), ._app_in_rdy(app_in_ready),
        ._app_out(app_out), ._app_out_vld(app_out_valid), ._app_out_rdy(1'b1),
        ._scheduler_probe(scheduler_probe)
    );

    initial begin
        repeat (8) @(posedge clock);
        reset <= 0;
        repeat (8) @(posedge clock);
`ifdef ROLE_B
        send(32'd131079, 0); send(32'd16777224, 0);
        send(32'd2885318566, 0); send(32'd6402827, 0);
        send(32'd1323196506, 0); send(32'd3335547353, 0);
        send(32'd2735461460, 0); send(32'd3108287709, 0);
        send(32'd4266152839, 0); send(32'd2909842626, 1);
        send(32'd131079, 0); send(32'd33554437, 0);
        send(32'd3, 0); send(32'd5, 0); send(32'd1, 0);
`else
        send(32'd65543, 0); send(32'd16777224, 0);
        send(32'd3702663721, 0); send(32'd1750217507, 0);
        send(32'd874993677, 0); send(32'd2489323987, 0);
        send(32'd2219707129, 0); send(32'd1547897174, 0);
        send(32'd615927388, 0); send(32'd2398078705, 1);
        send(32'd65543, 0); send(32'd33554437, 0);
        send(32'd0, 0); send(32'd2, 0); send(32'd1, 0);
`endif
        send(32'd251658241, 0); send(32'd16, 1);
    end

    task send(input [31:0] word, input last);
        begin
            @(negedge clock);
            app_in = {last, word};
            app_in_valid = 1;
            @(posedge clock);
            while (!app_in_ready) @(posedge clock);
            @(negedge clock);
            app_in_valid = 0;
        end
    endtask

    always @(posedge clock) begin
        if (!reset) begin
            cycle <= cycle + 1;
            if (app_in_valid && app_in_ready)
                app_in_words <= app_in_words + 1;
            if (app_out_valid) begin
                app_out_words <= app_out_words + 1;
                if (app_out[32]) app_out_frames <= app_out_frames + 1;
            end
            if (link_out_valid) begin
                link_words <= link_words + 1;
                if (link_out[32]) link_frames <= link_frames + 1;
            end
            if (scheduler_probe[0]) state_reads <= state_reads + 1;
            if (scheduler_probe[1]) state_writes <= state_writes + 1;
            if (scheduler_probe[2]) mailbox_reads <= mailbox_reads + 1;
            if (scheduler_probe[3]) mailbox_writes <= mailbox_writes + 1;
            if (scheduler_probe[4]) mailbox_snapshots <= mailbox_snapshots + 1;
`ifdef TRACE_SCHEDULER
            if (|scheduler_probe[3:0])
                $display("SCHEDULER cycle=%0d flags=%02x", cycle, scheduler_probe);
`endif
            if (fault_valid)
                $fatal(1, "application fault %08x", fault);
            if (cycle == `MAX_CYCLES) begin
                $display("RESULT app_in_words=%0d app_out_words=%0d app_out_frames=%0d link_words=%0d link_frames=%0d state_reads=%0d state_writes=%0d mailbox_reads=%0d mailbox_writes=%0d mailbox_snapshots=%0d",
                         app_in_words, app_out_words, app_out_frames, link_words,
                         link_frames, state_reads, state_writes, mailbox_reads,
                         mailbox_writes, mailbox_snapshots);
                $finish;
            end
        end
    end
endmodule
