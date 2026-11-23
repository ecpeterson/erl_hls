`timescale 1ns/1ps

`ifndef MAX_CYCLES
`define MAX_CYCLES 20000
`endif

// Bounded witness that one exact production role and its qualified external
// RAM wrapper publish the expected first private frame through the packet CDC.
// ROLE_B selects the role-B attachment/cutoff command and packet identity.
module repetition_packet_role_tb;
    reg clock = 0;
    reg wire_clock = 0;
    reg reset = 1;
    always #20 clock = !clock;
    always #4 wire_clock = !wire_clock;

    wire [32:0] link_out;
    wire link_out_valid, link_out_ready;
    wire [31:0] fault;
    wire fault_valid;
    wire app_in_ready;
    wire [4:0] scheduler_probe;
    reg [32:0] app_in = 0;
    reg app_in_valid = 0;
    wire [7:0] tx_data;
    wire tx_valid, tx_last;
    wire [31:0] packet_fault;
    wire tx_frame_accepted;
    integer app_in_words = 0;
    integer link_words = 0;
    integer link_frames = 0;
    integer packet_frames = 0;
    integer tx_bytes = 0;
    integer tx_frames = 0;
    integer cycle = 0;

`ifdef ROLE_B
    localparam [7:0] ROLE = 8'd2;
`else
    localparam [7:0] ROLE = 8'd1;
`endif

    role_model application(
        .clk(clock), .reset(reset),
        ._link_0_in(33'b0), ._link_0_in_vld(1'b0), ._link_0_in_rdy(),
        ._link_0_out(link_out), ._link_0_out_vld(link_out_valid),
        ._link_0_out_rdy(link_out_ready),
        ._fault_0_out(fault), ._fault_0_out_vld(fault_valid),
        ._fault_0_out_rdy(1'b1),
        ._app_in(app_in), ._app_in_vld(app_in_valid), ._app_in_rdy(app_in_ready),
        ._app_out(), ._app_out_vld(), ._app_out_rdy(1'b1),
        ._scheduler_probe(scheduler_probe)
    );

    partition_link_packets #(.ROLE(ROLE)) packets(
        .clock(clock), .reset_n(!reset),
        .tx_clock(wire_clock), .rx_clock(wire_clock),
        .tx_active_n(1'b1), .rx_active_n(1'b1),
        .link_tx(link_out), .link_tx_valid(link_out_valid),
        .link_tx_ready(link_out_ready),
        .link_rx(), .link_rx_valid(), .link_rx_ready(1'b1),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last),
        .tx_ready(1'b1),
        .rx_data(8'b0), .rx_valid(1'b0), .rx_last(1'b0), .rx_ready(),
        .fault(packet_fault), .tx_frame_accepted(tx_frame_accepted),
        .rx_frame_accepted(), .link_rx_frame_delivered()
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
            if (app_in_valid && app_in_ready) app_in_words <= app_in_words + 1;
            if (link_out_valid && link_out_ready) begin
                link_words <= link_words + 1;
                if (link_out[32]) link_frames <= link_frames + 1;
            end
            if (tx_frame_accepted) packet_frames <= packet_frames + 1;
            if (fault_valid) $fatal(1, "application fault %08x", fault);
            if (packet_fault) $fatal(1, "packet fault %08x", packet_fault);
            if (cycle == `MAX_CYCLES) begin
                if (app_in_words != 17 || link_frames < 1 || packet_frames < 1 ||
                    tx_bytes < 60 || tx_frames < 1)
                    $fatal(1, "missing progress app=%0d link=%0d/%0d packet=%0d tx=%0d/%0d",
                           app_in_words, link_words, link_frames, packet_frames,
                           tx_bytes, tx_frames);
                $display("PASS: exact role %0d command reached a complete MAC-side frame within %0d application cycles",
                         ROLE, `MAX_CYCLES);
                $finish;
            end
        end
    end

    always @(posedge wire_clock) begin
        if (!reset && tx_valid) begin
            tx_bytes <= tx_bytes + 1;
            if (tx_last) tx_frames <= tx_frames + 1;
        end
    end
endmodule
