// One independent source-domain role. The generated domain_board owns local
// host framing; the carrier owns private Ethernet packets and CDC storage.
// Bank 0 carries full application frames, bank 1 full control frames.
// Host session changes never reach any cold reset below. Reconfiguration/cold
// reset requires exclusion of the forgotten endpoint transport namespace.
module te0715_domain_link_top #(
    parameter [7:0] ROLE = 8'd1
) (
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
    wire [63:0] dma_tx_data, dma_rx_data;
    wire [1:0] dma_tx_last, dma_tx_valid, dma_tx_ready;
    wire [1:0] dma_rx_last, dma_rx_valid, dma_rx_ready;
    wire [1023:0] endpoint_tx, endpoint_rx;
    wire [5:0] endpoint_tx_words, endpoint_rx_words;
    wire endpoint_tx_valid, endpoint_tx_ready, endpoint_rx_valid, endpoint_rx_ready;
    wire [31:0] carrier_fault;
    wire carrier_armed;

    domain_board application(
        .clk(clock), .reset(!reset_n),
        .application_word(dma_tx_data[31:0]), .application_valid(dma_tx_valid[0]),
        .application_last(dma_tx_last[0]), .application_ready(dma_tx_ready[0]),
        .application_output_word(dma_rx_data[31:0]), .application_output_valid(dma_rx_valid[0]),
        .application_output_last(dma_rx_last[0]), .application_output_ready(dma_rx_ready[0]),
        .host_word(dma_tx_data[63:32]), .host_valid(dma_tx_valid[1]),
        .host_last(dma_tx_last[1]), .host_ready(dma_tx_ready[1]),
        .host_output_word(dma_rx_data[63:32]), .host_output_valid(dma_rx_valid[1]),
        .host_output_last(dma_rx_last[1]), .host_output_ready(dma_rx_ready[1]),
        .carrier_fault(carrier_fault[7:0]), .carrier_armed(carrier_armed),
        .packet_tx(endpoint_tx), .packet_tx_words(endpoint_tx_words),
        .packet_tx_valid(endpoint_tx_valid), .packet_tx_ready(endpoint_tx_ready),
        .packet_rx(endpoint_rx), .packet_rx_words(endpoint_rx_words),
        .packet_rx_valid(endpoint_rx_valid), .packet_rx_ready(endpoint_rx_ready)
    );

    wire [7:0] tx_data, packet_rx_data, bridge_rx_data;
    wire tx_valid, tx_last, tx_ready;
    wire packet_rx_valid, packet_rx_last, packet_rx_ready;
    wire bridge_rx_valid, bridge_rx_last, bridge_rx_ready;
    wire pll_reset, gt_reset, user_ready, pll_lock, tx_done, rx_done;
    wire tx_out_clock, rx_out_clock, tx_clock, rx_clock, tx_half_clock, rx_half_clock;
    wire tx_locked, rx_locked, tx_reset_n, rx_reset_n, link_tx, link_rx, align;
    wire [15:0] tx_pins, rx_pins;
    wire [1:0] tx_dispval, tx_dispmode, rx_charisk, rx_disperr;
    wire physical_loss, tx_physical_loss, rx_physical_loss;

    // Physical-loss health is cold-reset-only and synchronized by the endpoint;
    // it is independent of host parsing and the actor's incarnation lifecycle.
    domain_link_packets #(.ROLE(ROLE)) framing(
        .clock(clock), .cold_reset_n(reset_n), .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_active_n(tx_reset_n && link_tx), .rx_active_n(rx_reset_n),
        .physical_loss(physical_loss),
        .tx_physical_loss(tx_physical_loss), .rx_physical_loss(rx_physical_loss),
        .packet_tx(endpoint_tx), .packet_tx_words(endpoint_tx_words),
        .packet_tx_valid(endpoint_tx_valid), .packet_tx_ready(endpoint_tx_ready),
        .packet_rx(endpoint_rx), .packet_rx_words(endpoint_rx_words),
        .packet_rx_valid(endpoint_rx_valid), .packet_rx_ready(endpoint_rx_ready),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_data(bridge_rx_data), .rx_valid(bridge_rx_valid),
        .rx_last(bridge_rx_last), .rx_ready(bridge_rx_ready),
        .fault(carrier_fault), .armed(carrier_armed),
        .tx_packet_accepted(), .tx_frame_committed(), .rx_frame_accepted(), .rx_packet_delivered()
    );

    // Preserve the established byte skid between the MAC slot and carrier.
    reg rx_pipe_valid, rx_pipe_last;
    reg [7:0] rx_pipe_data;
    assign packet_rx_ready = !rx_pipe_valid || bridge_rx_ready;
    assign bridge_rx_valid = rx_pipe_valid;
    assign bridge_rx_last = rx_pipe_last;
    assign bridge_rx_data = rx_pipe_data;
    always @(posedge rx_clock or negedge rx_reset_n) begin
        if (!rx_reset_n) rx_pipe_valid <= 0;
        else if (packet_rx_ready) begin
            rx_pipe_valid <= packet_rx_valid;
            if (packet_rx_valid) begin
                rx_pipe_last <= packet_rx_last;
                rx_pipe_data <= packet_rx_data;
            end
        end
    end

    (* ASYNC_REG="TRUE" *) reg [1:0] done_meta, done_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] lock_meta, lock_sync;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            done_meta <= 0; done_sync <= 0; lock_meta <= 0; lock_sync <= 0;
        end else begin
            done_meta <= {rx_done, tx_done}; done_sync <= done_meta;
            lock_meta <= {rx_locked, tx_locked}; lock_sync <= lock_meta;
        end
    end
    ethernet_dma_supervised_endpoint packets(
        .control_clk(clock), .reset_n(reset_n), .run(1'b1),
        .pll_lock(pll_lock), .tx_done(done_sync[0] && lock_sync[0]),
        .rx_done(done_sync[1] && lock_sync[1]),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready), .status(),
        .eth_tx_clk(tx_clock), .eth_rx_clk(rx_clock),
        .eth_tx_half_clk(tx_half_clock), .eth_rx_half_clk(rx_half_clock),
        .tx_reset_n(tx_reset_n), .rx_reset_n(rx_reset_n),
        .gt_tx_data(tx_pins), .gt_tx_dispval(tx_dispval), .gt_tx_dispmode(tx_dispmode),
        .gt_rx_data(rx_pins), .gt_rx_charisk(rx_charisk), .gt_rx_disperr(rx_disperr),
        .gt_align(align), .link_tx(link_tx), .link_rx(link_rx),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(packet_rx_valid), .rx_last(packet_rx_last),
        .rx_data(packet_rx_data), .rx_ready(packet_rx_ready), .physical_loss(physical_loss),
        .tx_physical_loss(tx_physical_loss), .rx_physical_loss(rx_physical_loss),
        .tx_queued(), .rx_queued(), .tx_accepted(), .tx_dropped(),
        .tx_overflowed(), .tx_aborted(), .rx_accepted(), .rx_dropped(),
        .rx_overflowed(), .rx_aborted(), .preamble_errors(), .crc_errors()
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
    BUFG fabric_clock(.I(fclk[0]), .O(clock));
    zynq_probe_reset reset_sync(.clock(clock),
        .reset_n_async(freset_n[0] && gp_reset_n), .reset_n(reset_n));
    zynq_dma_pair transport(
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp),
        .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .tx_data(dma_tx_data), .tx_last(dma_tx_last), .tx_valid(dma_tx_valid), .tx_ready(dma_tx_ready),
        .rx_data(dma_rx_data), .rx_last(dma_rx_last), .rx_valid(dma_rx_valid), .rx_ready(dma_rx_ready), .irq(irq)
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
