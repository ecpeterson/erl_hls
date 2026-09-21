`timescale 1ns/1ps
// QEMU transactions drive only the mailbox's published AXI and stream ports.
// Clock stepping is a functional schedule, not a model of PS/PL relative timing.
module mailbox_cosim_tb;
    reg clock = 0, reset_n = 0;
    reg [11:0] awid = 0, wid = 0, arid = 0;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] awlen = 0, arlen = 0, wstrb = 15;
    reg [2:0] awsize = 2, arsize = 2;
    reg [1:0] awburst = 1, arburst = 1, awlock = 0, arlock = 0;
    reg awvalid = 0, wvalid = 0, wlast = 0, bready = 0, arvalid = 0, rready = 0;
    wire awready, wready, bvalid, arready, rvalid, rlast;
    wire [1:0] irq;
    wire [11:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata, tx_data;
    wire tx_last, tx_valid, rx_ready;
    integer clock_count = 0, reads = 0, writes = 0, steps = 0, resets = 0;
    integer frames = 0, stalls = 0, irq_rises = 0;
    reg [1:0] previous_irq = 0;
`ifdef ETHERNET_COSIM
    wire tx_ready, rx_valid, rx_last;
    wire [31:0] rx_data, fixture_status;
    reg [1:0] fixture_control=0;
    ethernet_cosim_fixture packet_link(.cut(fixture_control[0]), .hold_rx(fixture_control[1]),
                                      .status(fixture_status), .*);
`else
    wire permit = clock_count % 16 < 11;
    wire tx_ready = permit && rx_ready;
    wire [31:0] rx_data = tx_data;
    wire rx_valid = tx_valid && permit;
    wire rx_last = tx_last;
`endif
    integer op, address, value, amount, cycles;
    reg [31:0] response, result;
`ifdef REGSVC_COSIM
    // Integration counters come from guest debug queries, not hierarchical peeks.
    zynq_regsvc_core dut(.*);
    assign tx_data = 0;
    assign tx_last = 0;
    assign tx_valid = 0;
    assign rx_ready = 0;
`else
`ifdef ETHERNET_COSIM
    zynq_dma_mailbox #(.MAX_WORDS(380), .IDENTITY(32'h484c454d)) dut(.irq(irq[0]), .*);
`else
    zynq_dma_mailbox dut(.irq(irq[0]), .*);
`endif
    assign irq[1] = 0;
`endif

    // Complete a clock edge and check stalled outputs before serving another RPC.
    task automatic tick;
        reg held;
        reg [32:0] saved;
        begin
            #1;
            held = reset_n && tx_valid && !tx_ready;
            saved = {tx_last, tx_data};
            if (held) stalls = stalls + 1;
            if (reset_n && tx_valid && tx_ready && tx_last) frames = frames + 1;
`ifdef ETHERNET_COSIM
            #19; clock = 1; #20; clock = 0; #1;
`else
            #4; clock = 1; #5; clock = 0; #1;
`endif
            if (held && (!tx_valid || {tx_last, tx_data} !== saved)) $fatal(1,"unstable stream");
            if (|(irq & ~previous_irq)) irq_rises = irq_rises + 1;
            previous_irq = irq;
            clock_count = clock_count + 1;
            cycles = cycles + 1;
            if (cycles > 4096) $fatal(1,"AXI transaction stalled");
        end
    endtask

    // Deliver one complete aligned write and preserve the device's response.
    task automatic write_word;
        begin
            awaddr = address; awid = 12'h759; wid = awid; awvalid = 1;
            #1; while (!awready) tick;
            tick; awvalid = 0;
            wdata = value; wlast = 1; wvalid = 1;
            #1; while (!wready) tick;
            tick; wvalid = 0;
            while (!bvalid) tick;
            if (bid !== 12'h759) $fatal(1,"wrong write ID");
            response = {30'b0,bresp}; bready = 1;
            tick; bready = 0;
        end
    endtask

    // Return only data accepted through the AXI read response channel.
    task automatic read_word;
        begin
            araddr = address; arid = 12'hac3; arvalid = 1;
            #1; while (!arready) tick;
            tick; arvalid = 0;
            while (!rvalid) tick;
            if (rid !== 12'hac3 || !rlast) $fatal(1,"wrong read ID/last");
            response = {30'b0,rresp}; result = rdata; rready = 1;
            tick; rready = 0;
        end
    endtask

    initial begin
        while ($cosim_next(op,address,value,amount)) begin
            cycles = 0; response = 0; result = 0;
            case (op)
                1: begin
                    reads = reads + 1;
`ifdef ETHERNET_COSIM
                    // Emulated fixture controls are outside the mailbox aperture.
                    if (address==32'h40003000) begin result=32'h4543544c; tick; end
                    else if (address==32'h40003004) begin result={30'b0,fixture_control}; tick; end
                    else if (address==32'h40003008) begin result=fixture_status; tick; end
                    else
`endif
                    read_word;
                end
                2: begin
                    writes = writes + 1;
`ifdef ETHERNET_COSIM
                    if (address==32'h40003004) begin fixture_control=value[1:0]; tick; end
                    else
`endif
                    write_word;
                end
                3: begin steps = steps + 1; repeat(amount) tick; end
                4: begin
                    resets = resets + 1;
                    reset_n = 0; repeat(4) tick; reset_n = 1; tick;
                end
                default: $fatal(1,"unknown co-simulation command");
            endcase
            $cosim_reply(response,result,{30'b0,irq},cycles);
        end
        $display("COSIM reads=%0d writes=%0d steps=%0d resets=%0d frames=%0d stalls=%0d irq_rises=%0d",
                 reads,writes,steps,resets,frames,stalls,irq_rises);
        $finish;
    end
endmodule
