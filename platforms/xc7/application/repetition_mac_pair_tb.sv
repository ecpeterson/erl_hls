`timescale 1ns/1ps

// Bounded witness for the exact two-role application, private framing and
// PCS/MAC path. Independent TX clocks model the two boards; each receiver is
// clocked from its peer, as it is with a recovered GTX clock.
module repetition_mac_pair_tb #(
    parameter integer HORIZON = 10000,
    parameter integer APP_HALF_PERIOD_NS = 40
);
    reg clock = 0;
    reg clock_a = 0;
    reg clock_b = 0;
    reg reset = 1;
    always #(APP_HALF_PERIOD_NS) clock = !clock;
    always #4 clock_a = !clock_a;
    initial begin
        #1.25;
        forever #4.0004 clock_b = !clock_b;
    end

    wire [32:0] a_link_tx, b_link_tx;
    wire a_link_tx_valid, b_link_tx_valid;
    wire a_link_tx_ready, b_link_tx_ready;
    wire [32:0] a_link_rx, b_link_rx;
    wire a_link_rx_valid, b_link_rx_valid;
    wire a_link_rx_ready, b_link_rx_ready;
    wire [31:0] a_fault, b_fault;
    wire a_fault_valid, b_fault_valid;
    wire [32:0] a_app_out, b_app_out;
    wire a_app_out_valid, b_app_out_valid;
    wire a_app_in_ready, b_app_in_ready;
    reg [32:0] a_app_in = 0;
    reg [32:0] b_app_in = 0;
    reg a_app_in_valid = 0;
    reg b_app_in_valid = 0;

    wire [7:0] a_tx_data, b_tx_data, a_rx_data, b_rx_data;
    wire a_tx_valid, a_tx_last, a_tx_ready, a_rx_valid, a_rx_last, a_rx_ready;
    wire b_tx_valid, b_tx_last, b_tx_ready, b_rx_valid, b_rx_last, b_rx_ready;
    wire [31:0] a_packet_fault, b_packet_fault;
    wire a_tx_frame, a_rx_frame, a_delivered_frame;
    wire b_tx_frame, b_rx_frame, b_delivered_frame;

    wire [9:0] wire_a, wire_b;
    wire a_link_up, b_link_up, a_rx_link_up, b_rx_link_up;
    wire [1:0] a_tx_queued, b_tx_queued, a_rx_queued, b_rx_queued;
    wire [31:0] a_mac_tx, b_mac_tx, a_mac_rx, b_mac_rx;
    wire [31:0] a_mac_tx_drop, b_mac_tx_drop, a_mac_rx_drop, b_mac_rx_drop;
    wire [31:0] a_mac_tx_overflow, b_mac_tx_overflow;
    wire [31:0] a_mac_rx_overflow, b_mac_rx_overflow;
    wire [31:0] a_mac_tx_abort, b_mac_tx_abort, a_mac_rx_abort, b_mac_rx_abort;
    wire [31:0] a_preamble, b_preamble, a_crc, b_crc;

    integer cycle = 0;
    integer a_link_words = 0;
    integer b_link_words = 0;
    integer a_link_frames = 0;
    integer b_link_frames = 0;
    integer a_app_frames = 0;
    integer b_app_frames = 0;
    integer last_activity_cycle = 0;
    integer a_bad_words = 0;
    integer b_bad_words = 0;

    role_a_model role_a(
        .clk(clock), .reset(reset),
        ._link_0_in(a_link_rx), ._link_0_in_vld(a_link_rx_valid),
        ._link_0_in_rdy(a_link_rx_ready),
        ._link_0_out(a_link_tx), ._link_0_out_vld(a_link_tx_valid),
        ._link_0_out_rdy(a_link_tx_ready),
        ._fault_0_out(a_fault), ._fault_0_out_vld(a_fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(a_app_in), ._app_in_vld(a_app_in_valid),
        ._app_in_rdy(a_app_in_ready),
        ._app_out(a_app_out), ._app_out_vld(a_app_out_valid),
        ._app_out_rdy(1'b1)
    );
    role_b_model role_b(
        .clk(clock), .reset(reset),
        ._link_0_in(b_link_rx), ._link_0_in_vld(b_link_rx_valid),
        ._link_0_in_rdy(b_link_rx_ready),
        ._link_0_out(b_link_tx), ._link_0_out_vld(b_link_tx_valid),
        ._link_0_out_rdy(b_link_tx_ready),
        ._fault_0_out(b_fault), ._fault_0_out_vld(b_fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(b_app_in), ._app_in_vld(b_app_in_valid),
        ._app_in_rdy(b_app_in_ready),
        ._app_out(b_app_out), ._app_out_vld(b_app_out_valid),
        ._app_out_rdy(1'b1)
    );

    partition_link_packets #(.ROLE(8'd1)) packets_a(
        .clock(clock), .reset_n(!reset),
        .tx_clock(clock_a), .rx_clock(clock_b),
        .tx_active_n(a_link_up), .rx_active_n(1'b1),
        .link_tx(a_link_tx), .link_tx_valid(a_link_tx_valid),
        .link_tx_ready(a_link_tx_ready),
        .link_rx(a_link_rx), .link_rx_valid(a_link_rx_valid),
        .link_rx_ready(a_link_rx_ready),
        .tx_data(a_tx_data), .tx_valid(a_tx_valid), .tx_last(a_tx_last),
        .tx_ready(a_tx_ready),
        .rx_data(a_rx_data), .rx_valid(a_rx_valid), .rx_last(a_rx_last),
        .rx_ready(a_rx_ready), .fault(a_packet_fault),
        .tx_frame_accepted(a_tx_frame), .rx_frame_accepted(a_rx_frame),
        .link_rx_frame_delivered(a_delivered_frame)
    );
    partition_link_packets #(.ROLE(8'd2)) packets_b(
        .clock(clock), .reset_n(!reset),
        .tx_clock(clock_b), .rx_clock(clock_a),
        .tx_active_n(b_link_up), .rx_active_n(1'b1),
        .link_tx(b_link_tx), .link_tx_valid(b_link_tx_valid),
        .link_tx_ready(b_link_tx_ready),
        .link_rx(b_link_rx), .link_rx_valid(b_link_rx_valid),
        .link_rx_ready(b_link_rx_ready),
        .tx_data(b_tx_data), .tx_valid(b_tx_valid), .tx_last(b_tx_last),
        .tx_ready(b_tx_ready),
        .rx_data(b_rx_data), .rx_valid(b_rx_valid), .rx_last(b_rx_last),
        .rx_ready(b_rx_ready), .fault(b_packet_fault),
        .tx_frame_accepted(b_tx_frame), .rx_frame_accepted(b_rx_frame),
        .link_rx_frame_delivered(b_delivered_frame)
    );

    ethernet_dma_packet_endpoint mac_a(
        .eth_tx_clk(clock_a), .eth_tx_rst(reset),
        .eth_rx_clk(clock_b), .eth_rx_rst(reset),
        .tbi_rx(wire_b), .tbi_tx(wire_a), .link_tx(a_link_up),
        .link_rx(a_rx_link_up),
        .tx_valid(a_tx_valid), .tx_data(a_tx_data), .tx_last(a_tx_last),
        .tx_ready(a_tx_ready),
        .rx_valid(a_rx_valid), .rx_data(a_rx_data), .rx_last(a_rx_last),
        .rx_ready(a_rx_ready), .tx_queued(a_tx_queued), .rx_queued(a_rx_queued),
        .tx_accepted(a_mac_tx), .tx_dropped(a_mac_tx_drop),
        .tx_overflowed(a_mac_tx_overflow), .tx_aborted(a_mac_tx_abort),
        .rx_accepted(a_mac_rx), .rx_dropped(a_mac_rx_drop),
        .rx_overflowed(a_mac_rx_overflow), .rx_aborted(a_mac_rx_abort),
        .preamble_errors(a_preamble), .crc_errors(a_crc)
    );
    ethernet_dma_packet_endpoint mac_b(
        .eth_tx_clk(clock_b), .eth_tx_rst(reset),
        .eth_rx_clk(clock_a), .eth_rx_rst(reset),
        .tbi_rx(wire_a), .tbi_tx(wire_b), .link_tx(b_link_up),
        .link_rx(b_rx_link_up),
        .tx_valid(b_tx_valid), .tx_data(b_tx_data), .tx_last(b_tx_last),
        .tx_ready(b_tx_ready),
        .rx_valid(b_rx_valid), .rx_data(b_rx_data), .rx_last(b_rx_last),
        .rx_ready(b_rx_ready), .tx_queued(b_tx_queued), .rx_queued(b_rx_queued),
        .tx_accepted(b_mac_tx), .tx_dropped(b_mac_tx_drop),
        .tx_overflowed(b_mac_tx_overflow), .tx_aborted(b_mac_tx_abort),
        .rx_accepted(b_mac_rx), .rx_dropped(b_mac_rx_drop),
        .rx_overflowed(b_mac_rx_overflow), .rx_aborted(b_mac_rx_abort),
        .preamble_errors(b_preamble), .crc_errors(b_crc)
    );

    initial begin
        repeat (8) @(posedge clock);
        reset <= 0;
        wait (a_link_up && b_link_up && a_rx_link_up && b_rx_link_up);
        repeat (20) @(posedge clock);
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

    // Hold each beat through one accepted application-clock edge.
    task send_a(input [31:0] word, input last);
        begin
            @(negedge clock); a_app_in = {last, word}; a_app_in_valid = 1;
            @(posedge clock); while (!a_app_in_ready) @(posedge clock);
            @(negedge clock); a_app_in_valid = 0;
        end
    endtask
    task send_b(input [31:0] word, input last);
        begin
            @(negedge clock); b_app_in = {last, word}; b_app_in_valid = 1;
            @(posedge clock); while (!b_app_in_ready) @(posedge clock);
            @(negedge clock); b_app_in_valid = 0;
        end
    endtask

    always @(posedge clock) begin
        if (!reset) begin
            cycle <= cycle + 1;
            if (a_link_tx_valid && a_link_tx_ready) begin
                a_link_words <= a_link_words + 1;
                last_activity_cycle <= cycle;
                if (a_link_tx[32]) a_link_frames <= a_link_frames + 1;
            end
            if (b_link_tx_valid && b_link_tx_ready) begin
                b_link_words <= b_link_words + 1;
                last_activity_cycle <= cycle;
                if (b_link_tx[32]) b_link_frames <= b_link_frames + 1;
            end
            if (a_app_out_valid && a_app_out[32]) a_app_frames <= a_app_frames + 1;
            if (b_app_out_valid && b_app_out[32]) b_app_frames <= b_app_frames + 1;
            if (a_fault_valid || b_fault_valid)
                $fatal(1, "application fault a=%08x b=%08x", a_fault, b_fault);
            if (packets_a.host_rx_take && packets_a.rx_word_bad) begin
                a_bad_words <= a_bad_words + 1;
                $display("BAD A cycle=%0d index=%0d data=%08x last=%b expected_sequence=%0d",
                         cycle, packets_a.rx_index, packets_a.host_rx_data,
                         packets_a.host_rx_last, packets_a.rx_expected_sequence);
            end
            if (packets_b.host_rx_take && packets_b.rx_word_bad) begin
                b_bad_words <= b_bad_words + 1;
                $display("BAD B cycle=%0d index=%0d data=%08x last=%b expected_sequence=%0d",
                         cycle, packets_b.rx_index, packets_b.host_rx_data,
                         packets_b.host_rx_last, packets_b.rx_expected_sequence);
            end
            if (a_packet_fault || b_packet_fault)
                $fatal(1, "packet fault a=%08x b=%08x bad_words=%0d/%0d mac_rx=%0d/%0d drop=%0d/%0d crc=%0d/%0d",
                       a_packet_fault, b_packet_fault, a_bad_words, b_bad_words,
                       a_mac_rx, b_mac_rx, a_mac_rx_drop, b_mac_rx_drop,
                       a_crc, b_crc);
            if (cycle == HORIZON) begin
                $display("RESULT link=%0d/%0d words=%0d/%0d app=%0d/%0d last_activity=%0d idle=%0d",
                         a_link_frames, b_link_frames, a_link_words, b_link_words,
                         a_app_frames, b_app_frames,
                         last_activity_cycle, cycle - last_activity_cycle);
                $display("MAC tx=%0d/%0d drop=%0d/%0d overflow=%0d/%0d abort=%0d/%0d queued=%0d/%0d",
                         a_mac_tx, b_mac_tx, a_mac_tx_drop, b_mac_tx_drop,
                         a_mac_tx_overflow, b_mac_tx_overflow,
                         a_mac_tx_abort, b_mac_tx_abort, a_tx_queued, b_tx_queued);
                $display("MAC rx=%0d/%0d drop=%0d/%0d overflow=%0d/%0d abort=%0d/%0d queued=%0d/%0d preamble=%0d/%0d crc=%0d/%0d",
                         a_mac_rx, b_mac_rx, a_mac_rx_drop, b_mac_rx_drop,
                         a_mac_rx_overflow, b_mac_rx_overflow,
                         a_mac_rx_abort, b_mac_rx_abort, a_rx_queued, b_rx_queued,
                         a_preamble, b_preamble, a_crc, b_crc);
                $finish;
            end
        end
    end
endmodule
