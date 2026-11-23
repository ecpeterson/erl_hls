`timescale 1ns/1ps
// Finite pulse-boundary witness, not a MAC CRC/preamble decoder test. Exported
// MAC error pulses may occur without a delivered byte. Real store loss pulses
// and the production sticky capture cross independent ideal source clocks.
module ethernet_packet_loss_tb;
    reg control_clk=0, tx_clock=0, rx_clock=0, cold_reset_n=0;
    always #11 control_clk=~control_clk;
    always #4 tx_clock=~tx_clock;
    always #7 rx_clock=~rx_clock;
    reg tx_active=0, rx_active=0, tx_event=0;
    reg preamble_error=0, crc_error=0;
    reg store_reset=1, flush=0, abort_partial=0;
    reg in_valid=0, in_last=0, in_error=0;
    reg [7:0] in_data=0;
    wire in_ready, out_valid, out_last, drop_event, abort_event, physical_loss;
    wire tx_lost, rx_lost;
    wire [7:0] out_data;
    wire [1:0] queued;
    wire [31:0] accepted, dropped, overflowed, aborted;
    wire rx_event=drop_event || abort_event || preamble_error || crc_error;
    ethernet_frame_store #(.DROP_WHEN_FULL(1), .MIN_BYTES(4), .MAX_BYTES(8)) store(
        .clk(rx_clock), .rst(store_reset), .flush(flush), .abort_partial(abort_partial),
        .in_valid(in_valid), .in_last(in_last), .in_error(in_error), .in_data(in_data),
        .in_ready(in_ready), .out_valid(out_valid), .out_last(out_last), .out_data(out_data),
        .out_ready(1'b0), .queued(queued), .accepted(accepted), .dropped(dropped),
        .overflowed(overflowed), .aborted(aborted), .drop_event(drop_event), .abort_event(abort_event)
    );
    ethernet_packet_loss loss(
        .control_clk(control_clk), .cold_reset_n(cold_reset_n),
        .tx_clock(tx_clock), .rx_clock(rx_clock), .tx_active(tx_active), .rx_active(rx_active),
        .tx_loss_event(tx_event), .rx_loss_event(rx_event), .physical_loss(physical_loss), .tx_lost(tx_lost), .rx_lost(rx_lost)
    );
    integer drop_edges=0, abort_edges=0;
    // Count exact source-edge pulses independently from the store counters.
    always @(posedge rx_clock) begin
        if(drop_event) drop_edges=drop_edges+1;
        if(abort_event) abort_edges=abort_edges+1;
    end
    // Every observation allows both synchronizer stages and checks a stable result.
    task automatic check_loss(input expected);
        begin
            repeat(4) @(negedge control_clk);
            if(physical_loss !== expected) $fatal(1,"physical loss mismatch expected=%0d",expected);
            if((tx_lost || rx_lost) !== expected) $fatal(1,"source-local loss observation mismatch");
        end
    endtask
    // Only this common cold reset clears either source's retained loss history.
    task automatic cold_start;
        begin
            @(negedge control_clk);
            cold_reset_n=0; tx_active=0; rx_active=0; tx_event=0;
            preamble_error=0; crc_error=0; store_reset=1;
            in_valid=0; in_last=0; flush=0; abort_partial=0;
            repeat(4) @(negedge control_clk);
            cold_reset_n=1;
            @(negedge rx_clock); store_reset=0;
            check_loss(0);
        end
    endtask
    // Model one exported RX-domain pulse with no valid byte entering the store.
    task automatic mac_error(input crc);
        begin
            @(negedge rx_clock);
            preamble_error=!crc; crc_error=crc;
            @(negedge rx_clock);
            preamble_error=0; crc_error=0;
            if(accepted || dropped || queued || in_valid)
                $fatal(1,"zero-byte MAC pulse accidentally delivered a frame");
        end
    endtask
    // Real store transactions are bounded and include a terminal byte only when requested.
    task automatic bytes_in(input integer count, input finish_frame);
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge rx_clock);
                in_valid=1; in_data=i; in_last=finish_frame && i==count-1;
                if(!in_ready) $fatal(1,"draining RX store unexpectedly backpressured");
            end
            @(negedge rx_clock); in_valid=0; in_last=0;
        end
    endtask
    // A link/directional reset clears MAC/store state, never the loss history.
    task automatic rx_direction_reset;
        begin
            @(negedge rx_clock); rx_active=0; store_reset=1;
            repeat(3) @(negedge rx_clock);
            rx_active=1; store_reset=0;
            check_loss(1);
        end
    endtask
    // TX loss also latches in its own clock before crossing to control_clk.
    task automatic tx_error;
        begin
            @(negedge tx_clock); tx_event=1;
            @(negedge tx_clock); tx_event=0;
        end
    endtask
    initial begin
        cold_start();
        mac_error(0); mac_error(1); check_loss(0);
        rx_active=1; mac_error(0); check_loss(1); rx_direction_reset();
        cold_start(); rx_active=1;
        mac_error(1); check_loss(1);

        cold_start(); rx_active=1;
        bytes_in(3,1); check_loss(1);
        if(dropped!=1 || overflowed || drop_edges!=1)
            $fatal(1,"underlength store loss pulse mismatch");

        cold_start(); rx_active=1;
        bytes_in(4,1); bytes_in(4,1); check_loss(0);
        if(accepted!=2 || queued!=2) $fatal(1,"full-store setup mismatch");
        bytes_in(4,1); check_loss(1);
        if(dropped!=1 || overflowed!=1 || drop_edges!=2)
            $fatal(1,"full-store loss pulse mismatch");

        cold_start(); rx_active=1;
        bytes_in(2,0);
        @(negedge rx_clock); abort_partial=1;
        @(negedge rx_clock); abort_partial=0;
        check_loss(1);
        if(aborted!=1 || abort_edges!=1 || dropped)
            $fatal(1,"partial-abort store pulse mismatch");

        cold_start(); rx_active=1;
        bytes_in(4,1);
        @(negedge rx_clock); flush=1;
        @(negedge rx_clock); flush=0;
        check_loss(1);
        if(aborted!=1 || abort_edges!=2 || queued)
            $fatal(1,"queued-flush store pulse mismatch");

        cold_start(); tx_error(); check_loss(0);
        tx_active=1; tx_error(); check_loss(1);
        @(negedge tx_clock); tx_active=0;
        repeat(3) @(negedge tx_clock);
        tx_active=1; check_loss(1);
        cold_start(); tx_active=1; rx_active=1; check_loss(0);
        $display("ETHERNET_PACKET_LOSS_PASS zero_byte=2 store_drop=2 store_abort=2 directions=2 cold_rearm=1");
        $finish;
    end
    // Fixed overall horizon bounds every scenario, including any stalled stimulus.
    initial begin #100000; $fatal(1,"packet loss witness timeout"); end
endmodule
