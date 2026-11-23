// Physical bring-up fixture joining the PS PL330 mailbox to one external
// 1000BASE-X lane. This is transparent diagnostic plumbing, not application
// routing: one complete frame crosses each host/link clock boundary at a time.
// The lane starts automatically after the clock-programming FSBL releases PL.
module te0715_ethernet_dma_top(
    input wire ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n
);
    wire [3:0] fclk, freset_n;
    wire clock, gp_reset_n, reset_n;
    wire [11:0] awid, wid, bid, arid, rid;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0] awlen, arlen, wstrb;
    wire [1:0] awsize, arsize, awburst, arburst, awlock, arlock, bresp, rresp;
    wire awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire arvalid, arready, rvalid, rready, rlast;
    wire [1:0] irq;

    wire [31:0] host_tx_data, host_rx_data;
    wire host_tx_last, host_tx_valid, host_tx_ready;
    wire host_rx_last, host_rx_valid, host_rx_ready;
    wire [7:0] tx_data, packet_rx_data, bridge_rx_data;
    wire tx_valid, tx_last, tx_ready;
    wire packet_rx_valid, packet_rx_last, packet_rx_ready;
    wire bridge_rx_valid, bridge_rx_last, bridge_rx_ready;
    wire tx_invalid;

    wire pll_reset, gt_reset, user_ready, pll_lock, tx_done, rx_done;
    wire tx_out_clock, rx_out_clock, tx_clock, rx_clock, tx_half_clock, rx_half_clock;
    wire tx_locked, rx_locked, tx_reset_n, rx_reset_n, link_tx, link_rx, align;
    wire [15:0] tx_pins, rx_pins;
    wire [1:0] tx_dispval, tx_dispmode, rx_charisk, rx_disperr;
    wire [31:0] physical_status;

    BUFG fabric_clock(.I(fclk[0]), .O(clock));
    zynq_probe_reset reset_sync(.clock(clock),
        .reset_n_async(freset_n[0] && gp_reset_n), .reset_n(reset_n));

    // A maximum Ethernet envelope is 4 + ALIGN(1514, 4) = 1520 bytes.
    zynq_dma_mailbox #(.MAX_WORDS(380), .IDENTITY(32'h484c454d)) mailbox(
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .tx_data(host_tx_data), .tx_last(host_tx_last),
        .tx_valid(host_tx_valid), .tx_ready(host_tx_ready),
        .rx_data(host_rx_data), .rx_last(host_rx_last),
        .rx_valid(host_rx_valid), .rx_ready(host_rx_ready), .irq(irq[0])
    );
    assign irq[1] = 0;

    // Whole-frame slots isolate the 25-MHz PS clock from independent transmit
    // and recovered receive clocks. A pending TX restarts when PCS link returns.
    ethernet_dma_packets bridge(
        .clock(clock), .reset_n(reset_n), .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_active_n(tx_reset_n && link_tx), .rx_active_n(rx_reset_n),
        .host_tx_data(host_tx_data), .host_tx_valid(host_tx_valid),
        .host_tx_last(host_tx_last), .host_tx_ready(host_tx_ready),
        .host_rx_data(host_rx_data), .host_rx_valid(host_rx_valid),
        .host_rx_last(host_rx_last), .host_rx_ready(host_rx_ready),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_data(bridge_rx_data), .rx_valid(bridge_rx_valid),
        .rx_last(bridge_rx_last), .rx_ready(bridge_rx_ready),
        .tx_invalid(tx_invalid)
    );

    // Isolate the endpoint's frame-release decision from the CDC RAM write
    // enable. This elastic beat preserves backpressure and a complete TLAST.
    reg rx_pipe_valid, rx_pipe_last;
    reg [7:0] rx_pipe_data;
    assign packet_rx_ready = !rx_pipe_valid || bridge_rx_ready;
    assign bridge_rx_valid = rx_pipe_valid;
    assign bridge_rx_last = rx_pipe_last;
    assign bridge_rx_data = rx_pipe_data;
    always @(posedge rx_clock or negedge rx_reset_n) begin
        if (!rx_reset_n) rx_pipe_valid<=0;
        else if (packet_rx_ready) begin
            rx_pipe_valid<=packet_rx_valid;
            if (packet_rx_valid) begin
                rx_pipe_last<=packet_rx_last;
                rx_pipe_data<=packet_rx_data;
            end
        end
    end

    // Reset-done and MMCM-lock indications cross into the supervisor's clock.
    (* ASYNC_REG="TRUE" *) reg [1:0] done_meta, done_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] lock_meta, lock_sync;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin done_meta<=0; done_sync<=0; lock_meta<=0; lock_sync<=0; end
        else begin
            done_meta<={rx_done,tx_done}; done_sync<=done_meta;
            lock_meta<={rx_locked,tx_locked}; lock_sync<=lock_meta;
        end
    end
    ethernet_dma_supervised_endpoint packets(
        .control_clk(clock), .reset_n(reset_n), .run(1'b1),
        .pll_lock(pll_lock), .tx_done(done_sync[0] && lock_sync[0]),
        .rx_done(done_sync[1] && lock_sync[1]),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready),
        .status(physical_status),
        .eth_tx_clk(tx_clock), .eth_rx_clk(rx_clock),
        .eth_tx_half_clk(tx_half_clock), .eth_rx_half_clk(rx_half_clock),
        .tx_reset_n(tx_reset_n), .rx_reset_n(rx_reset_n),
        .gt_tx_data(tx_pins), .gt_tx_dispval(tx_dispval), .gt_tx_dispmode(tx_dispmode),
        .gt_rx_data(rx_pins), .gt_rx_charisk(rx_charisk), .gt_rx_disperr(rx_disperr),
        .gt_align(align), .link_tx(link_tx), .link_rx(link_rx),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(packet_rx_valid), .rx_last(packet_rx_last),
        .rx_data(packet_rx_data), .rx_ready(packet_rx_ready)
    );
    ethernet_gtx_clocks clocks(
        .clock(clock), .reset_n(reset_n), .gt_reset(gt_reset),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock),
        .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_half_clock(tx_half_clock), .rx_half_clock(rx_half_clock),
        .tx_locked(tx_locked), .rx_locked(rx_locked)
    );
    te0715_gtx_channel #(.PRBS(0), .EXTERNAL(1)) transceiver(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n),
        .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n), .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n),
        .pll_reset(pll_reset), .gt_reset(gt_reset),
        .user_ready(user_ready && tx_locked && rx_locked),
        .force_error(1'b0), .measure(1'b0), .align(align),
        .tx_clock(tx_half_clock), .rx_clock(rx_half_clock),
        .tx_data(tx_pins), .tx_dispval(tx_dispval), .tx_dispmode(tx_dispmode),
        .rx_data(rx_pins), .rx_charisk(rx_charisk), .rx_disperr(rx_disperr),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock)
    );

    PS7 processor(
        .FCLKCLK(fclk), .FCLKRESETN(freset_n), .FCLKCLKTRIGN(4'b0),
        .FPGAIDLEN(1'b1), .DDRARB(4'b0), .IRQF2P({18'b0, irq}),
        .MAXIGP0ACLK(clock), .MAXIGP0ARESETN(gp_reset_n),
        .MAXIGP0AWID(awid), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWLEN(awlen),
        .MAXIGP0AWSIZE(awsize), .MAXIGP0AWBURST(awburst), .MAXIGP0AWLOCK(awlock),
        .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready),
        .MAXIGP0WID(wid), .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb),
        .MAXIGP0WLAST(wlast), .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
        .MAXIGP0BID(bid), .MAXIGP0BRESP(bresp), .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready),
        .MAXIGP0ARID(arid), .MAXIGP0ARADDR(araddr), .MAXIGP0ARLEN(arlen),
        .MAXIGP0ARSIZE(arsize), .MAXIGP0ARBURST(arburst), .MAXIGP0ARLOCK(arlock),
        .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready),
        .MAXIGP0RID(rid), .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(rresp),
        .MAXIGP0RLAST(rlast), .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready)
    );
endmodule
