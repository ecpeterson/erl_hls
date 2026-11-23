// Compile-only PS7/GP0/FCLK0 shell with no PL package pins. PS boot software must
// configure FCLK0, PS-PL level shifters and resets before any CPU MMIO access.
// Dedicated PS pins and DDR/MIO configuration are owned by the board boot setup.
module zynq_ps_probe_top;
    zynq_probe_ps processor_shell(.status(128'b0));
endmodule

// PS7/GP0 register shell. Extended status and control use the exported FCLK0
// clock/reset domain; IDENTITY distinguishes a diagnostic's register contract.
module zynq_probe_ps #(
    parameter EXTENDED = 0, parameter [31:0] IDENTITY = 32'h45524c48,
    parameter [31:0] ABI = 1
)(
    input wire [127:0] status, output wire [31:0] control,
    output wire clock, output wire reset_n
);
    wire [3:0] fclk, freset_n;
    wire gp_reset_n;
    wire [11:0] awid, wid, bid, arid, rid;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0] awlen, arlen, wstrb;
    // The PS7 primitive exposes two size bits on its 32-bit GP ports.
    wire [1:0] awsize, arsize;
    wire [1:0] awburst, arburst, awlock, arlock, bresp, rresp;
    wire awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire arvalid, arready, rvalid, rready, rlast;

    BUFG fabric_clock(.I(fclk[0]), .O(clock));
    zynq_probe_reset reset_sync(.clock(clock),
        .reset_n_async(freset_n[0] && gp_reset_n), .reset_n(reset_n));
    zynq_ps_probe #(.EXTENDED(EXTENDED), .IDENTITY(IDENTITY), .ABI(ABI)) registers(
        .status(status), .control(control),
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );
    PS7 processor(
        .FCLKCLK(fclk), .FCLKRESETN(freset_n), .FCLKCLKTRIGN(4'b0),
        .FPGAIDLEN(1'b1), .DDRARB(4'b0), .IRQF2P(20'b0),
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
