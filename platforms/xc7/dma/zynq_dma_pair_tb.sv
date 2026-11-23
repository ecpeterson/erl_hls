`timescale 1ns/1ps
// Probe bank isolation through AXI stalls, bursts, independent directions and reset.
module zynq_dma_pair_tb;
    reg clock=0, reset_n=0;
    reg [11:0] awid=0, wid=0, arid=0;
    reg [31:0] awaddr=0, wdata=0, araddr=0;
    reg [3:0] awlen=0, arlen=0, wstrb=15;
    reg [2:0] awsize=2, arsize=2;
    reg [1:0] awburst=1, arburst=1, awlock=0, arlock=0;
    reg awvalid=0, wvalid=0, wlast=0, bready=0, arvalid=0, rready=0;
    wire awready, wready, bvalid, arready, rvalid, rlast;
    wire [11:0] bid, rid;
    wire [1:0] bresp, rresp, tx_last, tx_valid, rx_ready, irq;
    wire [31:0] rdata;
    wire [63:0] tx_data;
    wire [63:0] rx_data=tx_data;
    wire [1:0] rx_last=tx_last, rx_valid=tx_valid, tx_ready=rx_ready;
    reg [31:0] result;
    localparam [31:0] APP=32'h40000000, DEBUG=32'h40004000;
    zynq_dma_pair dut(.*);

    // Clock once and require stalled responses to retain their complete payloads.
    task automatic tick;
        reg held_r, held_b;
        reg [46:0] old_r;
        reg [13:0] old_b;
        begin
            #1;
            held_r=reset_n && rvalid && !rready;
            held_b=reset_n && bvalid && !bready;
            old_r={rid,rresp,rlast,rdata}; old_b={bid,bresp};
            #3; clock=1; #1; clock=0; #1;
            if (held_r && (!rvalid || {rid,rresp,rlast,rdata} !== old_r)) $fatal(1,"unstable R");
            if (held_b && (!bvalid || {bid,bresp} !== old_b)) $fatal(1,"unstable B");
        end
    endtask

    // Read a burst while the live address selects the other bank; optionally check RAM.
    task automatic get(input [31:0] address, input integer beats, input [1:0] response,
                       input compare_ram, input [31:0] seed, output [31:0] value);
        integer beat, timeout;
        begin
            araddr=address; arid=12'hac3; arlen=beats-1; arvalid=1;
            #1; if (!arready) $fatal(1,"AR blocked");
            tick; arvalid=0; araddr=address ^ 32'h4000; arid=12'h111;
            for (beat=0; beat<beats; beat=beat+1) begin
                timeout=0;
                while (!rvalid && timeout<8) begin tick; timeout=timeout+1; end
                if (!rvalid || rid !== 12'hac3 || rresp !== response || rlast !== (beat==beats-1))
                    $fatal(1,"read response address=%h beat=%d resp=%h",address,beat,rresp);
                if (arready) $fatal(1,"second AR allowed before final R");
                if (compare_ram && rdata !== (seed ^ beat)) $fatal(1,"wrong bank/data beat=%d",beat);
                value=rdata;
                repeat(beat%3+1) tick;
                rready=1; tick; rready=0;
            end
        end
    endtask

    // Hold B while addressing the other bank, optionally completing a concurrent read.
    task automatic put(input [31:0] address, input integer beats, input [31:0] seed,
                       input [1:0] response, input concurrent_read);
        integer beat;
        reg [31:0] value;
        begin
            awaddr=address; awid=12'h759; awlen=beats-1; wid=awid; awvalid=1;
            #1; if (!awready) $fatal(1,"AW blocked");
            tick; awvalid=0; awaddr=address ^ 32'h4000; awid=12'h222;
            for (beat=0; beat<beats; beat=beat+1) begin
                wdata=seed ^ beat; wlast=beat==beats-1; wvalid=1; #1;
                if (!wready || awready) $fatal(1,"W blocked or second AW allowed");
                tick; wvalid=0; tick;
            end
            repeat(3) tick;
            if (!bvalid || bid !== 12'h759 || bresp !== response || awready)
                $fatal(1,"wrong write response address=%h resp=%h",address,bresp);
            if (concurrent_read) begin
                get((address ^ 32'h4000) & 32'hffffc000,1,0,0,0,value);
                if (value !== 32'h484c444d) $fatal(1,"concurrent read lost");
            end
            bready=1; tick; bready=0;
        end
    endtask

    // Fill a maximum-length AXI burst and commit one packet to the chosen stream.
    task automatic send_packet(input [31:0] base, input [31:0] seed);
        begin
            put(base+'h1000,16,seed,0,1);
            put(base+12,1,64,0,0);
            repeat(40) tick;
        end
    endtask

    initial begin
        repeat(4) tick; reset_n=1; tick;
        put(APP+24,1,7,0,0); put(DEBUG+24,1,7,0,0);
        send_packet(APP,32'hdead1000);
        send_packet(APP,32'hdead2000);
        get(APP+8,1,0,0,0,result);
        if (result[1:0] !== 3) $fatal(1,"application not backpressured");
        send_packet(DEBUG,32'hbeef3000);
        if (irq !== 3) $fatal(1,"independent IRQs missing");
        get(DEBUG+'h2000,16,0,1,32'hbeef3000,result);
        put(DEBUG+20,1,3,0,0);
        if (irq !== 1) $fatal(1,"debug ACK affected application IRQ");
        get(APP+'h2000,16,0,1,32'hdead1000,result);
        put(APP+20,1,3,0,0); repeat(40) tick;
        get(APP+'h2000,16,0,1,32'hdead2000,result);
        put(APP+20,1,3,0,0);
        if (irq !== 0) $fatal(1,"IRQs retained after drain");
        // Holes, aliases, and cross-bank bursts must not access either packet RAM.
        get(APP+'h3000,16,2,0,0,result); put(APP+'h3000,16,0,2,0);
        get(DEBUG+'h3000,16,2,0,0,result); put(DEBUG+'h3000,16,0,2,0);
        get(APP+'h3ffc,2,2,0,0,result); put(APP+'h3ffc,2,0,2,0);
        get(32'h50004000,1,2,0,0,result); put(32'h50004000,1,0,2,0);
        // Reset releases a selected bank even halfway through its outstanding write.
        awaddr=DEBUG+'h1000; awid=4; awlen=15; awvalid=1;
        tick; awvalid=0; wid=4; wdata=55; wlast=0; wvalid=1; tick; wvalid=0;
        reset_n=0; tick; reset_n=1; tick;
        if (bvalid || rvalid || irq || tx_valid) $fatal(1,"reset retained ownership");
        get(APP,1,0,0,0,result); if (result !== 32'h484c444d) $fatal(1,"APP after reset");
        get(DEBUG,1,0,0,0,result); if (result !== 32'h484c444d) $fatal(1,"DEBUG after reset");
        $display("PASS: DMA bank isolation, burst/address/response stalls, independent directions and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"watchdog"); end
endmodule
