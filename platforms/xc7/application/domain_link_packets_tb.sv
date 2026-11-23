`timescale 1ns/1ps
// Finite simulation witness with the real DMA/CDC bridge and independent clocks.
module domain_link_packets_tb;
    reg clock=0, tx_clock=0, rx_clock=0, cold_reset_n=0;
    always #11 clock=~clock;
    always #4 tx_clock=~tx_clock;
    always #7 rx_clock=~rx_clock;
    reg tx_active_n=0, rx_active_n=0, physical_loss=0;
    reg tx_physical_loss=0, rx_physical_loss=0;
    reg [1023:0] packet_tx=0;
    reg [5:0] packet_tx_words=11;
    reg packet_tx_valid=0, packet_rx_ready=0;
    wire packet_tx_ready, packet_rx_valid;
    wire [1023:0] packet_rx;
    wire [5:0] packet_rx_words;
    wire [7:0] tx_data;
    wire tx_valid, tx_last, rx_ready;
    reg tx_ready=0, tx_gate=0;
    reg [7:0] rx_data=0;
    reg rx_valid=0, rx_last=0;
    wire [31:0] fault;
    wire armed, tx_packet_accepted, tx_frame_committed, rx_frame_accepted, rx_packet_delivered;
    domain_link_packets #(.ROLE(8'd1)) dut(.*);

    integer tx_cycles=0, tx_bytes_count=0, tx_frames=0;
    integer local_accepts=0, dma_commits=0, rx_frames=0, deliveries=0;
    reg [7:0] captured [0:511];
    // Deterministic byte stalls occur independently of both host and RX edges.
    always @(negedge tx_clock) begin
        tx_cycles=tx_cycles+1;
        tx_ready=tx_gate && tx_cycles%5!=2 && tx_cycles%7!=3;
    end
    always @(posedge tx_clock or negedge cold_reset_n) begin
        if (!cold_reset_n) begin tx_bytes_count=0; tx_frames=0; end
        else if (tx_valid && tx_ready) begin
            if (tx_bytes_count>=512) $fatal(1,"unbounded TX witness");
            captured[tx_bytes_count]=tx_data;
            tx_bytes_count=tx_bytes_count+1;
            if (tx_last) tx_frames=tx_frames+1;
        end
    end
    always @(posedge clock or negedge cold_reset_n) begin
        if (!cold_reset_n) begin local_accepts=0; dma_commits=0; rx_frames=0; deliveries=0; end
        else begin
            if (tx_packet_accepted) local_accepts=local_accepts+1;
            if (tx_frame_committed) dma_commits=dma_commits+1;
            if (rx_frame_accepted) rx_frames=rx_frames+1;
            if (rx_packet_delivered) deliveries=deliveries+1;
        end
    end

    // Every word varies; ACK high words deliberately contain garbage on TX.
    function automatic [1023:0] payload(input integer seed);
        integer i;
        begin
            for(i=0;i<32;i=i+1)
                payload[i*32 +: 32]=32'ha5030000 ^ (seed<<16) ^ (i*32'h01020408);
        end
    endfunction
    // Byte order is the public private-envelope contract, not internal DMA state.
    function automatic [7:0] frame_byte(input integer index, words, source_role, destination_role,
                                        input [1023:0] value);
        begin
            case(index)
                0,6: frame_byte=8'h02;
                5: frame_byte=destination_role;
                11,21: frame_byte=source_role;
                12: frame_byte=8'h88;
                13: frame_byte=8'hb5;
                16: frame_byte=8'h45;
                17: frame_byte=8'h48;
                18: frame_byte=8'h4c;
                19: frame_byte=8'h44;
                20: frame_byte=8'd2;
                22: frame_byte=words;
                default: frame_byte=index<24 ? 8'd0 : value[(index-24)*8 +: 8];
            endcase
        end
    endfunction

    // Startup absence of active indications is allowed; cold reset alone rearms.
    task automatic cold_start;
        integer wait_count;
        begin
            @(negedge clock);
            cold_reset_n=0; tx_active_n=0; rx_active_n=0; physical_loss=0;
            tx_physical_loss=0; rx_physical_loss=0;
            packet_tx_valid=0; packet_rx_ready=0; rx_valid=0; rx_last=0; tx_gate=0;
            packet_tx_words=11;
            repeat(5) @(negedge clock);
            cold_reset_n=1;
            repeat(4) @(negedge clock);
            if(armed || fault || packet_tx_ready || packet_rx_valid || tx_valid || rx_ready)
                $fatal(1,"startup absence became a fault or admitted traffic");
            tx_active_n=1; rx_active_n=1;
            wait_count=0;
            while(!armed && !fault && wait_count<40) begin
                @(negedge clock); wait_count=wait_count+1;
            end
            if(!armed || fault || !packet_tx_ready) $fatal(1,"cold startup did not arm");
        end
    endtask
    // Whole-packet acceptance is one host edge, then the input is changed.
    task automatic offer(input [1023:0] value, input integer words);
        integer wait_count;
        begin
            @(negedge clock); packet_tx=value; packet_tx_words=words; packet_tx_valid=1;
            wait_count=0;
            while(!packet_tx_ready && !fault && wait_count<500) begin
                @(negedge clock); wait_count=wait_count+1;
            end
            if(!packet_tx_ready || fault) $fatal(1,"whole packet not accepted");
            @(negedge clock); packet_tx_valid=0; packet_tx=~value;
        end
    endtask
    // Backpressure is honored byte by byte; a fatal carrier stops an injected bad frame.
    task automatic byte_in(input [7:0] value, input last);
        integer wait_count;
        begin
            @(negedge rx_clock); rx_data=value; rx_last=last; rx_valid=1;
            wait_count=0;
            while(!rx_ready && !fault && wait_count<500) begin
                @(negedge rx_clock); wait_count=wait_count+1;
            end
            if(!rx_ready && !fault) $fatal(1,"RX byte stalled without bound");
            @(negedge rx_clock); rx_valid=0;
        end
    endtask
    // Optional corruption targets only public wire bytes or frame termination.
    task automatic inject(input [1023:0] value, input integer words, mode);
        integer i, length;
        reg [7:0] byte_value;
        begin
            length=24+4*words;
            if(mode==1) length=13;
            if(mode==2) length=67;
            if(mode==3) length=153;
            for(i=0;i<length && !fault;i=i+1) begin
                byte_value=i<152 ? frame_byte(i,words,2,1,value) : 0;
                if(mode==4 && i==16) byte_value=byte_value^1;
                if(mode==5 && i==21) byte_value=1;
                if(mode==6 && i==5) byte_value=2;
                if(mode==7 && i==22) byte_value=32;
                if(mode==8 && i==20) byte_value=1;
                byte_in(byte_value,i==length-1);
            end
        end
    endtask
    // Verify exact opaque TX bytes, envelope and the final immutable packet boundary.
    task automatic check_tx(input [1023:0] value, input integer words);
        integer wait_count, i;
        begin
            wait_count=0;
            while(tx_frames==0 && !fault && wait_count<1500) begin
                @(negedge clock); wait_count=wait_count+1;
            end
            if(fault || tx_frames!=1 || tx_bytes_count!=24+4*words)
                $fatal(1,"TX frame/length/fault mismatch %0d %0d %h",tx_frames,tx_bytes_count,fault);
            for(i=0;i<tx_bytes_count;i=i+1)
                if(captured[i] !== frame_byte(i,words,1,2,value)) $fatal(1,"TX byte mismatch %0d",i);
        end
    endtask
    // Hold the complete local RX offer through host stalls, checking canonical ACK padding.
    task automatic check_rx(input [1023:0] value, input integer words);
        integer wait_count, i;
        reg [1023:0] expected;
        begin
            expected=words==11 ? {672'd0,value[351:0]} : value;
            wait_count=0;
            while(!packet_rx_valid && !fault && wait_count<1500) begin
                @(negedge clock); wait_count=wait_count+1;
            end
            if(fault || !packet_rx_valid) $fatal(1,"RX complete offer missing");
            for(i=0;i<12;i=i+1) begin
                @(negedge clock);
                if(!packet_rx_valid || packet_rx_words!=words || packet_rx!==expected)
                    $fatal(1,"stalled RX packet changed or ACK high words were not zero");
            end
            packet_rx_ready=1;
            @(negedge clock); packet_rx_ready=0;
            if(packet_rx_valid) $fatal(1,"RX packet was delivered twice");
        end
    endtask
    // After the bounded stop crossing, all ownership/wire offers remain closed.
    // Previously accepted actions during propagation are not transparent retries.
    task automatic check_fatal;
        integer wait_count, i, before_bytes;
        begin
            wait_count=0;
            while(!fault && wait_count<100) begin @(negedge clock); wait_count=wait_count+1; end
            if(!fault) $fatal(1,"malformed traffic did not latch fatal");
            if(packet_tx_ready || packet_rx_valid) $fatal(1,"host admission survived host fault");
            // Opposite directions may finish already accepted work before their
            // two-stage stop observation. Count only after that bounded window.
            repeat(4) @(negedge tx_clock);
            repeat(4) @(negedge rx_clock);
            before_bytes=tx_bytes_count;
            packet_tx_valid=1; packet_tx_words=32; rx_valid=1; rx_last=1; tx_gate=1;
            for(i=0;i<20;i=i+1) begin
                @(negedge clock);
                if(!fault || packet_tx_ready || packet_rx_valid || tx_valid || rx_ready)
                    $fatal(1,"faulted carrier resumed traffic");
                if(tx_bytes_count!=before_bytes) $fatal(1,"retained TX replay escaped after fault");
            end
            packet_tx_valid=0; rx_valid=0;
        end
    endtask
    // TX loss recovers wholly between host edges; the asynchronous hold must remember it.
    task automatic short_tx_loss;
        integer wait_count;
        begin
            cold_start(); tx_gate=1; offer(payload(7),32);
            wait_count=0;
            while(tx_bytes_count<8 && wait_count<500) begin @(negedge clock); wait_count=wait_count+1; end
            if(tx_bytes_count<8 || tx_frames) $fatal(1,"TX loss did not interrupt a partial frame");
            @(negedge clock); #2; tx_active_n=0; #1;
            if(tx_valid) $fatal(1,"local TX loss not caught asynchronously");
            #2; tx_active_n=1; #1;
            if(tx_valid) $fatal(1,"sub-host-cycle TX recovery restarted cursor");
            check_fatal();
        end
    endtask
    // RX loss remains low over host edges, then cannot resurrect a partial receive frame.
    task automatic long_rx_loss;
        integer i;
        begin
            cold_start();
            for(i=0;i<8;i=i+1) byte_in(frame_byte(i,32,2,1,payload(8)),0);
            rx_active_n=0; #1;
            if(rx_ready) $fatal(1,"local RX active loss did not stop cursor");
            repeat(3) @(negedge clock);
            rx_active_n=1;
            check_fatal();
            if(rx_frames || deliveries) $fatal(1,"partial RX frame was published after loss");
        end
    endtask

    integer mode;
    initial begin
        cold_start(); tx_gate=1;
        fork
            begin offer(payload(1),32); check_tx(payload(1),32); end
            begin inject(payload(2),11,0); check_rx(payload(2),11); end
        join
        if(local_accepts!=1 || dma_commits!=1 || rx_frames!=1 || deliveries!=1 || fault)
            $fatal(1,"DATA/ACK ownership boundary counts mismatch");
        cold_start(); tx_gate=1;
        fork
            begin offer(payload(3),11); check_tx(payload(3),11); end
            begin inject(payload(4),32,0); check_rx(payload(4),32); end
        join
        if(local_accepts!=1 || dma_commits!=1 || rx_frames!=1 || deliveries!=1 || fault)
            $fatal(1,"ACK/DATA ownership boundary counts mismatch");
        for(mode=1;mode<=8;mode=mode+1) begin
            cold_start(); inject(payload(5),mode==3 ? 32 : 11,mode); check_fatal();
            if(rx_frames || deliveries) $fatal(1,"malformed envelope was published mode=%0d",mode);
        end
        cold_start();
        @(negedge clock); packet_tx_words=12; packet_tx_valid=1;
        @(negedge clock); packet_tx_valid=0;
        check_fatal();
        if(local_accepts || dma_commits || tx_frames) $fatal(1,"illegal TX length was accepted");
        short_tx_loss(); long_rx_loss();
        cold_start(); tx_gate=1;
        offer(payload(8),32);
        @(negedge clock); physical_loss=1;
        check_fatal();
        if(!fault[6]) $fatal(1,"qualified physical loss cause missing");
        cold_start(); tx_gate=1;
        fork
            begin offer(payload(9),32); check_tx(payload(9),32); end
            begin inject(payload(10),11,0); check_rx(payload(10),11); end
        join
        if(fault || local_accepts!=1 || deliveries!=1) $fatal(1,"cold-only rearm failed");
        $display("DOMAIN_LINK_PACKETS_PASS good_pairs=3 malformed_rx=8 illegal_tx=1 directional_loss=2 physical_loss=1");
        $finish;
    end
    // Independent of every bounded task loop, the entire finite schedule has a fixed horizon.
    initial begin #2000000; $fatal(1,"domain carrier witness timeout"); end
endmodule
