`timescale 1ns/1ps
// Two packet endpoints with independently running TX clocks; each receiver uses
// the peer's recovered clock. Wire vectors are generated without LiteEth.
module packet_tb;
    reg clock_a=0, clock_b=0, reset=1;
    always #4 clock_a = !clock_a;
    // 100 ppm frequency offset and a phase offset; no fake asynchronous sampling
    // of a parallel TBI bus. Analog clock recovery is outside this regression.
    initial begin #1.25; forever #4.0004 clock_b = !clock_b; end
    reg cut=0, inject=0;
    reg [9:0] injected=0;
    wire [9:0] wire_a, wire_b;
    wire up_a, up_b, rx_up_b;
    reg tx_valid=0, tx_last=0;
    reg [7:0] tx_data=0;
    reg reverse_valid=0, reverse_last=0, reverse_expected=0;
    reg [7:0] reverse_data=0;
    wire reverse_ready, reverse_rx_valid, reverse_rx_last;
    wire [7:0] reverse_rx_data;
    integer reverse_offset=0, reverse_received=0;
    wire tx_ready, rx_valid, rx_last;
    wire [7:0] rx_data;
    reg rx_ready=1, stall=0;
    wire [31:0] accepted, dropped, overflowed, aborted, crc_errors, preamble_errors;
    wire [31:0] tx_accepted, tx_dropped, tx_aborted;
    wire [1:0] rx_queued;
    ethernet_packet_endpoint a(
        .eth_tx_clk(clock_a), .eth_rx_clk(clock_b), .eth_tx_rst(reset), .eth_rx_rst(reset),
        .tbi_rx(cut ? 10'b0 : wire_b), .tbi_tx(wire_a), .link_tx(up_a),
        .tx_valid(tx_valid), .tx_data(tx_data), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_ready(1'b1), .rx_valid(reverse_rx_valid), .rx_data(reverse_rx_data), .rx_last(reverse_rx_last),
        .tx_accepted(tx_accepted), .tx_dropped(tx_dropped), .tx_aborted(tx_aborted)
    );
    ethernet_packet_endpoint b(
        .eth_tx_clk(clock_b), .eth_rx_clk(clock_a), .eth_tx_rst(reset), .eth_rx_rst(reset),
        .tbi_rx(cut ? 10'b0 : inject ? injected : wire_a), .tbi_tx(wire_b),
        .link_tx(up_b), .link_rx(rx_up_b), .tx_valid(reverse_valid), .tx_data(reverse_data),
        .tx_last(reverse_last), .tx_ready(reverse_ready),
        .rx_valid(rx_valid), .rx_data(rx_data), .rx_last(rx_last), .rx_ready(rx_ready),
        .rx_accepted(accepted), .rx_dropped(dropped), .rx_overflowed(overflowed),
        .rx_aborted(aborted), .rx_queued(rx_queued), .crc_errors(crc_errors),
        .preamble_errors(preamble_errors)
    );
    always @(posedge clock_b) if (!reset && reverse_rx_valid) begin
        if (!reverse_expected || reverse_rx_data !== ((reverse_offset*17+21) & 8'hff) ||
            reverse_rx_last !== (reverse_offset==63)) $fatal(1,"reverse frame mismatch");
        if (reverse_rx_last) begin reverse_received=reverse_received+1;reverse_expected=0;end
        else reverse_offset=reverse_offset+1;
    end
    integer expected_length[0:63], expected_tag[0:63];
    integer expected_count=0, received=0, offset=0, cycle=0;
    reg [7:0] wanted;
    reg was_stalled=0;
    reg [8:0] held;
    integer capture;
    always @(negedge clock_a) begin
        cycle = cycle+1;
        rx_ready = !stall && cycle%5 != 0 && cycle%7 != 0;
    end
    always @(posedge clock_a) begin
        if (!reset) begin
            if (capture) $fdisplay(capture, "%03x", wire_a);
            if (was_stalled && (!rx_valid || {rx_last,rx_data} !== held))
                $fatal(1,"RX changed while stalled");
            was_stalled = rx_valid && !rx_ready;
            held = {rx_last,rx_data};
            if (rx_valid && rx_ready) begin
                if (received >= expected_count) $fatal(1,"unexpected frame %d",received);
                wanted = offset < expected_length[received] ? offset*17+expected_tag[received] : 0;
                if (rx_data !== wanted) $fatal(1,"frame %d byte %d got %x expected %x",received,offset,rx_data,wanted);
                if (rx_last !== (offset == (expected_length[received]<60 ? 59 : expected_length[received]-1)))
                    $fatal(1,"last at frame %d byte %d",received,offset);
                if (rx_last) begin received=received+1; offset=0; end
                else offset=offset+1;
            end
        end
    end

    // Queue one expected whole-frame delivery; padding remains visible.
    task expect_frame(input integer length, tag);
        begin
            expected_length[expected_count]=length;
            expected_tag[expected_count]=tag;
            expected_count=expected_count+1;
        end
    endtask

    // Exercise TX and RX simultaneously with the reverse sender's own clock.
    task send_reverse;
        integer i;
        begin
            reverse_expected=1;
            for(i=0;i<64;i=i+1) begin
                @(negedge clock_b);reverse_valid=1;reverse_data=i*17+21;reverse_last=i==63;
                @(posedge clock_b);while(!reverse_ready) @(posedge clock_b);
            end
            @(negedge clock_b);reverse_valid=0;reverse_last=0;
        end
    endtask

    // Host may pause arbitrarily while constructing a frame. Nothing may be
    // transmitted until last commits it to a slot.
    task send_frame(input integer length, tag, gaps);
        integer i;
        begin
            for (i=0;i<length;i=i+1) begin
                @(negedge clock_a);
                tx_valid=1; tx_data=i*17+tag; tx_last=i==length-1;
                @(posedge clock_a); while (!tx_ready) @(posedge clock_a);
                if (gaps && i!=length-1) begin
                    @(negedge clock_a); tx_valid=0;
                    repeat (i%3+1) @(negedge clock_a);
                end
            end
            @(negedge clock_a); tx_valid=0; tx_last=0;
        end
    endtask

    // The file includes ordered idles, a complete packet and termination.
    task inject_file(input string name);
        integer file, parsed;
        reg [9:0] code;
        begin
            file=$fopen(name,"r"); if (!file) $fatal(1,"missing vector %s",name);
            while (!$feof(file)) begin
                parsed=$fscanf(file,"%h\n",code);
                if (parsed==1) begin @(negedge clock_a); inject=1; injected=code; end
            end
            @(negedge clock_a); inject=0;
            $fclose(file);
            repeat(80) @(negedge clock_a);
        end
    endtask

    // Await all promised deliveries and let any stray output reach the checker.
    task drained;
        begin
            wait(received==expected_count);
            repeat(100) @(negedge clock_a);
        end
    endtask

    integer before_drop, before_crc, before_preamble, before_accepted;
    initial begin
        capture=$fopen("wire.hex","w");
        repeat(8) @(negedge clock_a); reset=0;
        wait(up_a && up_b && rx_up_b);
        repeat(20) @(negedge clock_a);
        expect_frame(14,1); send_frame(14,1,1); drained();
        expect_frame(59,2); send_frame(59,2,0); drained();
        expect_frame(60,3); send_frame(60,3,0); drained();
        expect_frame(61,4); send_frame(61,4,1); drained();
        expect_frame(1514,5); send_frame(1514,5,1); drained();
        // TX rejects malformed bounds before any byte reaches the wire.
        send_frame(13,6,0); send_frame(1515,7,0);
        repeat(100) @(negedge clock_a);
        if (tx_dropped != 2 || tx_accepted != 5) $fatal(1,"TX bounds not enforced");
        // Both RX slots remain intact while a third on-wire frame is dropped.
        stall=1;
        expect_frame(100,8); send_frame(100,8,0);
        expect_frame(101,9); send_frame(101,9,0);
        wait(rx_queued==2);
        before_drop=dropped;
        send_frame(102,10,0);
        wait(dropped==before_drop+1);
        @(negedge clock_a);
        if (overflowed!=1) $fatal(1,"missing overflow count");
        stall=0; drained();
        expect_frame(103,11); send_frame(103,11,0); drained();
        expect_frame(67,24);
        fork send_frame(67,24,0); send_reverse(); join
        drained(); wait(reverse_received==1);
        $fclose(capture); capture=0;
        // Inject independent wire bytes and FCS, then corrupt only the FCS.
        expect_frame(97,43); inject_file("good.hex"); drained();
        before_drop=dropped; before_crc=crc_errors;
        inject_file("crc_bad.hex");
        if (dropped!=before_drop+1 || crc_errors!=before_crc+1) $fatal(1,"CRC rejection missing");
        before_drop=dropped;
        inject_file("oversize.hex"); inject_file("runt.hex");
        if (dropped!=before_drop+2) $fatal(1,"RX bounds not enforced");
        before_preamble=preamble_errors;
        inject_file("preamble_bad.hex");
        if (preamble_errors!=before_preamble+1) $fatal(1,"preamble error missing");
        expect_frame(97,43); inject_file("good.hex"); drained();
        // Preserve a committed/stalled RX frame through link failure. A second
        // frame interrupted on the wire must never appear after renegotiation.
        stall=1;
        expect_frame(200,12); send_frame(200,12,0);
        wait(rx_queued==1);
        // Snapshot after mapped counter carry chains have settled.
        @(negedge clock_a);
        before_accepted=accepted;
        send_frame(1514,13,0);
        repeat(100) @(negedge clock_a); cut=1;
        wait(!up_a && !up_b && !rx_up_b);
        repeat(30) @(negedge clock_a);
        if (accepted!=before_accepted) $fatal(1,"partial frame committed across link loss");
        cut=0;
        wait(up_a && up_b && rx_up_b);
        stall=0; drained();
        expect_frame(64,14); send_frame(64,14,1); drained();
        $display("PASS: PCS/MAC full duplex, independent FCS, bounds, slots, backpressure, loss/recovery (%0d frames)",received+reverse_received);
        $finish;
    end
    initial begin #2000000; $fatal(1,"packet timeout received=%d expected=%d up=%b%b",received,expected_count,up_a,up_b); end
endmodule
