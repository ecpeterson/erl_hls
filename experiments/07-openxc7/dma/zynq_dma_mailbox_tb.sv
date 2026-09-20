`timescale 1ns/1ps
// Model a burst-capable PS master and an independently stalled/invalid stream.
// All checks use the published interfaces, including the post-synthesis run.
module zynq_dma_mailbox_tb #(parameter EXHAUSTIVE_LENGTHS = 1);
    reg clock = 0, reset_n = 0;
    reg [11:0] awid = 0, wid = 0, arid = 0;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] awlen = 0, arlen = 0, wstrb = 15;
    reg [2:0] awsize = 2, arsize = 2;
    reg [1:0] awburst = 1, arburst = 1, awlock = 0, arlock = 0;
    reg awvalid = 0, wvalid = 0, wlast = 0, bready = 0, arvalid = 0, rready = 0;
    wire awready, wready, bvalid, arready, rvalid, rlast, irq;
    wire [11:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata, tx_data;
    wire tx_last, tx_valid, rx_ready;
    reg loopback = 1, permit = 1, inject_valid = 0, inject_last = 0;
    reg [31:0] inject_data = 0;
    reg bad_id = 0, bad_last = 0;
    wire tx_ready = loopback && permit && rx_ready;
    wire [31:0] rx_data = loopback ? tx_data : inject_data;
    wire rx_valid = loopback ? tx_valid && permit : inject_valid;
    wire rx_last = loopback ? tx_last : inject_last;
    reg [31:0] packet [0:511];
    reg [31:0] result;
    reg [31:0] saved_word;
    reg [16:1] write_bursts = 0, read_bursts = 0;
    integer words, offset, count, i, trial, lengths = 0;
    localparam [31:0] BASE = 32'h40000000;
`ifdef MAPPED
    zynq_dma_mailbox_mapped dut(.*);
`else
    zynq_dma_mailbox dut(.*);
`endif

    // Counter/address carries and their adjacent lengths exercise mapped boundaries.
    function automatic power_of_two(input integer value);
        power_of_two = value > 0 && (value & (value-1)) == 0;
    endfunction

    // Advance one cycle, asserting every held response/stream remains stable.
    task automatic tick;
        reg held_tx, held_r, held_b;
        reg [32:0] old_tx;
        reg [46:0] old_r;
        reg [13:0] old_b;
        begin
            #1;
            held_tx = reset_n && tx_valid && !tx_ready;
            held_r = reset_n && rvalid && !rready;
            held_b = reset_n && bvalid && !bready;
            old_tx = {tx_last,tx_data}; old_r = {rid,rresp,rlast,rdata}; old_b = {bid,bresp};
            #3; clock = 1; #1; clock = 0; #1;
            if (held_tx && (!tx_valid || {tx_last,tx_data} !== old_tx)) $fatal(1,"unstable TX");
            if (held_r && (!rvalid || {rid,rresp,rlast,rdata} !== old_r)) $fatal(1,"unstable R");
            if (held_b && (!bvalid || {bid,bresp} !== old_b)) $fatal(1,"unstable B");
        end
    endtask

    // Write a burst from packet[], allowing data to arrive ahead of its address.
    task automatic put(input [31:0] address, input integer first, input integer beats,
                       input [1:0] response);
        integer beat;
        begin
            if (response == 0) write_bursts[beats] = 1;
            awaddr = address; awid = 12'h759; awlen = beats-1;
            wid = awid ^ {11'b0,bad_id}; wdata = packet[first]; wlast = beats == 1; wvalid = 1;
            repeat(2) tick;
            if (wready) $fatal(1,"W accepted before AW");
            awvalid = 1; #1;
            if (!awready) $fatal(1,"AW blocked");
            tick; awvalid = 0; awaddr = 0; awid = 0;
            for (beat=0; beat<beats; beat=beat+1) begin
                wdata = packet[first+beat]; wlast = (beat == beats-1) ^ bad_last;
                wvalid = 1; #1;
                if (!wready) $fatal(1,"W blocked");
                tick; wvalid = 0;
                repeat(beat%3) tick;
            end
            repeat(3) tick;
            if (!bvalid || bid !== 12'h759 || bresp !== response)
                $fatal(1,"write response address=%h actual=%h expected=%h",address,bresp,response);
            bready = 1; tick; bready = 0;
        end
    endtask

    // Write one complete register value without disturbing the packet model.
    task automatic command(input [31:0] address, input [31:0] value, input [1:0] response);
        reg [31:0] saved;
        begin
            saved = packet[511]; packet[511] = value;
            put(BASE+address,511,1,response); packet[511] = saved;
        end
    endtask

    // Read a burst through stalls; compare RX RAM with the source packet model.
    task automatic get(input [31:0] address, input integer first, input integer beats,
                       input [1:0] response, input compare_ram, output [31:0] value);
        integer beat, timeout;
        begin
            if (response == 0 && compare_ram) read_bursts[beats] = 1;
            araddr = address; arid = 12'hac3; arlen = beats-1; arvalid = 1;
            #1; if (!arready) $fatal(1,"AR blocked");
            tick; arvalid = 0; araddr = 0; arid = 0;
            for (beat=0; beat<beats; beat=beat+1) begin
                timeout = 0;
                while (!rvalid && timeout < 8) begin tick; timeout=timeout+1; end
                if (!rvalid || rid !== 12'hac3 || rresp !== response || rlast !== (beat==beats-1))
                    $fatal(1,"read response address=%h beat=%d resp=%h",address,beat,rresp);
                if (compare_ram && rdata !== packet[first+beat])
                    $fatal(1,"payload word=%d got=%h expected=%h",first+beat,rdata,packet[first+beat]);
                value = rdata;
                repeat(beat%5+1) tick;
                rready = 1; tick; rready = 0;
            end
        end
    endtask

    // Fill a frame using mixed 1..16-beat DMA bursts and publish its exact length.
    task automatic transmit(input integer length);
        integer pos, burst;
        begin
            for (pos=0; pos<length; pos=pos+1) packet[pos] = 32'hab731159 ^ (pos*32'h10785b1);
            packet[1] = 32'h7c060100 | (length-2);
            pos=0;
            while (pos<length) begin
                burst = 1 + (pos*7+length)%16;
                if (burst>length-pos) burst=length-pos;
                put(BASE+'h1000+4*pos,pos,burst,0);
                pos=pos+burst;
            end
            command(12,length*4,0);
        end
    endtask

    // Await a complete packet, verify its length/data, then return RX ownership.
    task automatic receive_packet(input integer length);
        integer attempt, pos, burst;
        reg [31:0] status;
        begin
            status = 0;
            for(attempt=0; attempt<300 && !status[1]; attempt=attempt+1)
                get(BASE+8,0,1,0,0,status);
            if (!status[1]) $fatal(1,"RX timeout");
            get(BASE+16,0,1,0,0,status);
            if (status !== length*4) $fatal(1,"RX length %d",status);
            if (!irq) $fatal(1,"missing RX interrupt");
            pos=0;
            while(pos<length) begin
                burst = length-pos>16 ? 16 : length-pos;
                get(BASE+'h2000+4*pos,pos,burst,0,1,status);
                pos=pos+burst;
            end
            get(BASE+'h2000+4*length,0,1,2,0,status);
            command(20,3,0);
        end
    endtask

    initial begin
        repeat(32) tick; reset_n=1; tick;
        get(BASE,0,1,0,0,result);
        if(result!==32'h484c444d) $fatal(1,"identity");
        get(BASE+4,0,1,0,0,result);
        if(result!==1) $fatal(1,"ABI");
        get(BASE+'h2000,0,1,2,0,result); // No uninitialized memory exposure.
        command(24,7,0);
        command(12,4,2); command(12,1032,2); command(12,9,2);
        for (words=2; words<=257; words=words+1) begin
            // RTL sweeps all sizes; mapped runs cover burst tails and binary carries.
            if (EXHAUSTIVE_LENGTHS || words <= 18 || power_of_two(words-1) ||
                power_of_two(words) || power_of_two(words+1)) begin
                lengths=lengths+1;
                permit=0;
                transmit(words);
                repeat(7) tick;
                command(12,8,2); // An occupied TX slot cannot be republished or overwritten.
                put(BASE+'h1000,0,1,2);
                permit=1;
                receive_packet(words);
            end
        end
        if (write_bursts !== 16'hffff || read_bursts !== 16'hffff)
            $fatal(1,"missing burst lengths: writes=%h reads=%h",write_bursts,read_bursts);
        // Two occupied slots: RX backpressures a second published TX frame.
        transmit(17); repeat(40) tick;
        transmit(17); repeat(12) tick;
        get(BASE+8,0,1,0,0,result);
        if (result[1:0]!==3) $fatal(1,"lost backpressure");
        receive_packet(17); receive_packet(17);
        // Bad alignment, size, wraparound decode, locking and burst kind.
        get(BASE+'h2001,0,1,2,0,result);
        get(BASE-4,0,16,2,0,result);
        put(BASE-4,0,16,2);
        awsize=1; put(BASE+'h1000,0,1,2); awsize=2;
        awburst=2; put(BASE+'h1000,0,4,2); awburst=1;
        awlock=1; put(BASE+'h1000,0,1,2); awlock=0;
        bad_id=1; put(BASE+'h1000,0,2,2); bad_id=0;
        bad_last=1; put(BASE+'h1000,0,2,2); bad_last=0;
        arsize=1; get(BASE,0,1,2,0,result); arsize=2;
        arburst=2; get(BASE,0,1,2,0,result); arburst=1;
        arlock=1; get(BASE,0,1,2,0,result); arlock=0;
        // Byte-enable writes must preserve every unselected lane in TX RAM.
        for (trial=0;trial<16;trial=trial+1) begin
            packet[0]=32'h12345678; packet[1]=32'h01020300;
            put(BASE+'h1000,0,2,0);
            saved_word=packet[0]; packet[0]=32'h89abcdef;
            wstrb=trial; put(BASE+'h1000,0,1,0); wstrb=15;
            for(i=0;i<4;i=i+1)
                if (!((1<<i)&trial)) packet[0][8*i+:8]=saved_word[8*i+:8];
            command(12,8,0); receive_packet(2);
        end
        // Reject short/oversized packets; recover at TLAST and keep the next frame.
        loopback=0;
        packet[0]=32'h11223344; packet[1]=0;
        inject_data=packet[0]; inject_valid=1; inject_last=0; tick; inject_valid=0;
        get(BASE+8,0,1,0,0,result);
        if(result[3:0]!==8) $fatal(1,"incomplete RX packet invisible");
        inject_data=packet[1]; inject_valid=1; inject_last=1; tick; inject_valid=0;
        get(BASE+8,0,1,0,0,result);
        if(result[3:0]!==2) $fatal(1,"completed RX packet still active");
        receive_packet(2);
        inject_data=32'h123; inject_valid=1; inject_last=1; tick;
        inject_valid=0;
        get(BASE+8,0,1,0,0,result);
        if(result[2:1]!==2'b10) $fatal(1,"short packet published");
        command(20,4,0);
        for (i=0;i<300;i=i+1) begin
            inject_valid=1; inject_last=i==299; tick;
        end
        inject_valid=0;
        get(BASE+8,0,1,0,0,result);
        if(result[2:1]!==2'b10) $fatal(1,"oversized packet published");
        command(20,4,0);
        loopback=1; transmit(257); receive_packet(257);
        // Reset discards ownership even when TX is stalled; RAM stays inaccessible.
        permit=0; transmit(2); reset_n=0; tick; reset_n=1; tick;
        get(BASE+8,0,1,0,0,result);
        if(result!==0 || irq || tx_valid) $fatal(1,"reset retained ownership");
        get(BASE+'h2000,0,1,2,0,result);
        $display("PASS: DMA mailbox %0d frame lengths, all burst lengths, stalls, bounds and reset",lengths);
        $finish;
    end
    initial begin #10000000; $fatal(1,"watchdog"); end
endmodule
