`timescale 1ns/1ps

// Connect the generated role wrappers directly to check autonomous startup
// before the Ethernet packetizer and physical clock domains are involved.
module repetition_link_rtl_tb #(
    parameter integer HORIZON = 100000
);
    reg clock = 0;
    reg reset = 1;
    always #5 clock = !clock;

    wire [32:0] a_to_b, b_to_a;
    wire a_to_b_valid, a_to_b_ready, b_to_a_valid, b_to_a_ready;
    wire [31:0] a_fault, b_fault;
    wire a_fault_valid, b_fault_valid;
    wire [32:0] a_app_out, b_app_out;
    wire a_app_out_valid, b_app_out_valid;
    wire a_app_in_ready, b_app_in_ready;
    reg [32:0] a_app_in = 0;
    reg [32:0] b_app_in = 0;
    reg a_app_in_valid = 0;
    reg b_app_in_valid = 0;
    integer a_link_words = 0;
    integer b_link_words = 0;
    integer a_link_frames = 0;
    integer b_link_frames = 0;
    integer a_app_frames = 0;
    integer b_app_frames = 0;
    integer a_frame_words = 0;
    integer b_frame_words = 0;
    integer a_credit_frames = 0;
    integer b_credit_frames = 0;
    integer a_data_frames = 0;
    integer b_data_frames = 0;
    integer a_other_frames = 0;
    integer b_other_frames = 0;
    integer last_activity_cycle = 0;
    integer cycle = 0;
    integer index;

    role_a_model role_a(
        .clk(clock), .reset(reset),
        ._link_0_in(b_to_a), ._link_0_in_vld(b_to_a_valid),
        ._link_0_in_rdy(b_to_a_ready),
        ._link_0_out(a_to_b), ._link_0_out_vld(a_to_b_valid),
        ._link_0_out_rdy(a_to_b_ready),
        ._fault_0_out(a_fault), ._fault_0_out_vld(a_fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(a_app_in), ._app_in_vld(a_app_in_valid), ._app_in_rdy(a_app_in_ready),
        ._app_out(a_app_out), ._app_out_vld(a_app_out_valid),
        ._app_out_rdy(1'b1)
    );
    role_b_model role_b(
        .clk(clock), .reset(reset),
        ._link_0_in(a_to_b), ._link_0_in_vld(a_to_b_valid),
        ._link_0_in_rdy(a_to_b_ready),
        ._link_0_out(b_to_a), ._link_0_out_vld(b_to_a_valid),
        ._link_0_out_rdy(b_to_a_ready),
        ._fault_0_out(b_fault), ._fault_0_out_vld(b_fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(b_app_in), ._app_in_vld(b_app_in_valid), ._app_in_rdy(b_app_in_ready),
        ._app_out(b_app_out), ._app_out_vld(b_app_out_valid),
        ._app_out_rdy(1'b1)
    );

    initial begin
        repeat (8) @(posedge clock);
        reset <= 0;
        repeat (8) @(posedge clock);

        // Replay the exact routed frames emitted by hls_partition_stream:
        // attach each gateway, then set the local noise cutoff to 16.
        send_a(32'd65543, 0); send_a(32'd16777224, 0);
        send_a(32'd3702663721, 0); send_a(32'd1750217507, 0);
        send_a(32'd874993677, 0); send_a(32'd2489323987, 0);
        send_a(32'd2219707129, 0); send_a(32'd1547897174, 0);
        send_a(32'd615927388, 0); send_a(32'd2398078705, 1);
        send_b(32'd131079, 0); send_b(32'd16777224, 0);
        send_b(32'd2885318566, 0); send_b(32'd6402827, 0);
        send_b(32'd1323196506, 0); send_b(32'd3335547353, 0);
        send_b(32'd2735461460, 0); send_b(32'd3108287709, 0);
        send_b(32'd4266152839, 0); send_b(32'd2909842626, 1);
        send_a(32'd65543, 0); send_a(32'd33554437, 0);
        send_a(32'd0, 0); send_a(32'd2, 0); send_a(32'd1, 0);
        send_a(32'd251658241, 0); send_a(32'd16, 1);
        send_b(32'd131079, 0); send_b(32'd33554437, 0);
        send_b(32'd3, 0); send_b(32'd5, 0); send_b(32'd1, 0);
        send_b(32'd251658241, 0); send_b(32'd16, 1);
    end

    // Hold each beat through one accepted rising edge.
    task send_a(input [31:0] word, input last);
        begin
            @(negedge clock);
            a_app_in = {last, word};
            a_app_in_valid = 1;
            @(posedge clock);
            while (!a_app_in_ready) @(posedge clock);
            @(negedge clock);
            a_app_in_valid = 0;
        end
    endtask

    task send_b(input [31:0] word, input last);
        begin
            @(negedge clock);
            b_app_in = {last, word};
            b_app_in_valid = 1;
            @(posedge clock);
            while (!b_app_in_ready) @(posedge clock);
            @(negedge clock);
            b_app_in_valid = 0;
        end
    endtask

    // Count only accepted words and complete TLAST-delimited frames.
    always @(posedge clock) begin
        if (!reset) begin
            cycle <= cycle + 1;
            if (a_to_b_valid && a_to_b_ready) begin
                a_link_words <= a_link_words + 1;
                a_frame_words <= a_frame_words + 1;
                last_activity_cycle <= cycle;
                if (a_to_b[32]) begin
                    a_link_frames <= a_link_frames + 1;
                    a_frame_words <= 0;
                    if (a_frame_words + 1 == 1)
                        a_credit_frames <= a_credit_frames + 1;
                    else if (a_frame_words + 1 == 5)
                        a_data_frames <= a_data_frames + 1;
                    else
                        a_other_frames <= a_other_frames + 1;
                end
            end
            if (b_to_a_valid && b_to_a_ready) begin
                b_link_words <= b_link_words + 1;
                b_frame_words <= b_frame_words + 1;
                last_activity_cycle <= cycle;
                if (b_to_a[32]) begin
                    b_link_frames <= b_link_frames + 1;
                    b_frame_words <= 0;
                    if (b_frame_words + 1 == 1)
                        b_credit_frames <= b_credit_frames + 1;
                    else if (b_frame_words + 1 == 5)
                        b_data_frames <= b_data_frames + 1;
                    else
                        b_other_frames <= b_other_frames + 1;
                end
            end
            if (a_app_out_valid) begin
                last_activity_cycle <= cycle;
                if (a_app_out[32]) a_app_frames <= a_app_frames + 1;
            end
            if (b_app_out_valid) begin
                last_activity_cycle <= cycle;
                if (b_app_out[32]) b_app_frames <= b_app_frames + 1;
            end
            if (a_fault_valid || b_fault_valid)
                $fatal(1, "application fault a=%08x b=%08x", a_fault, b_fault);
            if (cycle == HORIZON) begin
                $display("RESULT a_link_words=%0d a_link_frames=%0d b_link_words=%0d b_link_frames=%0d a_app_frames=%0d b_app_frames=%0d",
                         a_link_words, a_link_frames, b_link_words, b_link_frames,
                         a_app_frames, b_app_frames);
                $display("FRAMES a_credit=%0d a_data=%0d a_other=%0d b_credit=%0d b_data=%0d b_other=%0d last_activity_cycle=%0d idle_cycles=%0d horizon=%0d",
                         a_credit_frames, a_data_frames, a_other_frames,
                         b_credit_frames, b_data_frames, b_other_frames,
                         last_activity_cycle, cycle - last_activity_cycle, HORIZON);
                $finish;
            end
        end
    end
endmodule
