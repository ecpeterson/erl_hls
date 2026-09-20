// PS7/GP0 packet loopback with a level interrupt and no PL package pins. Boot must
// configure FCLK0, PS-PL level shifters and resets before any CPU MMIO access.
// Dedicated PS pins and DDR/MIO configuration are owned by the board boot setup.
module zynq_dma_top #(parameter ROUTED = 0);
    wire [3:0] fclk, freset_n;
    wire clock, gp_reset_n, reset_n;
    wire [11:0] awid, wid, bid, arid, rid;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0] awlen, arlen, wstrb;
    // The PS7 primitive exposes two size bits on its 32-bit GP ports.
    wire [1:0] awsize, arsize;
    wire [1:0] awburst, arburst, awlock, arlock, bresp, rresp;
    wire awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire arvalid, arready, rvalid, rready, rlast;

    wire [31:0] stream_data;
    wire stream_last, stream_valid, stream_ready;
    wire [1:0] irq;

    BUFG fabric_clock(.I(fclk[0]), .O(clock));
    zynq_probe_reset reset_sync(.clock(clock),
        .reset_n_async(freset_n[0] && gp_reset_n), .reset_n(reset_n));
    // The same PS pins and reset boundary serve either acceptance payload.
    generate if (ROUTED) begin: routed
        zynq_regsvc_core core(
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready), .irq(irq)
        );
    end else begin: loopback
    zynq_dma_mailbox mailbox(
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .tx_data(stream_data), .tx_last(stream_last), .tx_valid(stream_valid), .tx_ready(stream_ready),
        .rx_data(stream_data), .rx_last(stream_last), .rx_valid(stream_valid), .rx_ready(stream_ready), .irq(irq[0])
    );
        assign irq[1] = 0;
    end endgenerate
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
