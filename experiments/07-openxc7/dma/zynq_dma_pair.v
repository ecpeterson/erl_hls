// Independent application/debug packet slots behind one AXI3 master.
// Bank 0 occupies 0x40000000..0x40002fff; bank 1 starts at 0x40004000.
// Latch each bank at address acceptance and hold it through its final response.
// Read/write directions are independent; neither allows multiple outstanding IDs.
// Unmapped addresses go to bank 0, whose aperture checks return SLVERR.
module zynq_dma_pair (
    input wire clock, input wire reset_n,
    input wire [11:0] awid, input wire [31:0] awaddr,
    input wire [3:0] awlen, input wire [2:0] awsize,
    input wire [1:0] awburst, input wire [1:0] awlock,
    input wire awvalid, output wire awready,
    input wire [11:0] wid, input wire [31:0] wdata,
    input wire [3:0] wstrb, input wire wlast, input wire wvalid, output wire wready,
    output wire [11:0] bid, output wire [1:0] bresp,
    output wire bvalid, input wire bready,
    input wire [11:0] arid, input wire [31:0] araddr,
    input wire [3:0] arlen, input wire [2:0] arsize,
    input wire [1:0] arburst, input wire [1:0] arlock,
    input wire arvalid, output wire arready,
    output wire [11:0] rid, output wire [31:0] rdata,
    output wire [1:0] rresp, output wire rlast,
    output wire rvalid, input wire rready,
    output wire [63:0] tx_data, output wire [1:0] tx_last,
    output wire [1:0] tx_valid, input wire [1:0] tx_ready,
    input wire [63:0] rx_data, input wire [1:0] rx_last,
    input wire [1:0] rx_valid, output wire [1:0] rx_ready,
    output wire [1:0] irq
);
    reg write_active, read_active, write_bank, read_bank;
    wire aw_bank = awaddr[31:14] == (32'h40004000 >> 14);
    wire ar_bank = araddr[31:14] == (32'h40004000 >> 14);
    wire [1:0] bank_awready, bank_wready, bank_bvalid, bank_arready, bank_rvalid, bank_rlast;
    wire [23:0] bank_bid, bank_rid;
    wire [3:0] bank_bresp, bank_rresp;
    wire [63:0] bank_rdata;

    assign awready = !write_active && bank_awready[aw_bank];
    assign wready = write_active && bank_wready[write_bank];
    assign bvalid = write_active && bank_bvalid[write_bank];
    assign bid = bank_bid[12*write_bank +: 12];
    assign bresp = bank_bresp[2*write_bank +: 2];
    assign arready = !read_active && bank_arready[ar_bank];
    assign rvalid = read_active && bank_rvalid[read_bank];
    assign rdata = bank_rdata[32*read_bank +: 32];
    assign rid = bank_rid[12*read_bank +: 12];
    assign rresp = bank_rresp[2*read_bank +: 2];
    assign rlast = bank_rlast[read_bank];

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            write_active <= 0; read_active <= 0; write_bank <= 0; read_bank <= 0;
        end else begin
            if (awvalid && awready) begin write_active <= 1; write_bank <= aw_bank; end
            if (bvalid && bready) write_active <= 0;
            if (arvalid && arready) begin read_active <= 1; read_bank <= ar_bank; end
            if (rvalid && rready && rlast) read_active <= 0;
        end
    end

    genvar i;
    generate for (i=0; i<2; i=i+1) begin: bank
        zynq_dma_mailbox #(.BASE_ADDR(32'h40000000 + i*32'h4000)) mailbox (
            .clock(clock), .reset_n(reset_n),
            .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
            .awburst(awburst), .awlock(awlock),
            .awvalid(awvalid && !write_active && aw_bank == i), .awready(bank_awready[i]),
            .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
            .wvalid(wvalid && write_active && write_bank == i), .wready(bank_wready[i]),
            .bid(bank_bid[12*i+:12]), .bresp(bank_bresp[2*i+:2]), .bvalid(bank_bvalid[i]),
            .bready(bready && write_active && write_bank == i),
            .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
            .arburst(arburst), .arlock(arlock),
            .arvalid(arvalid && !read_active && ar_bank == i), .arready(bank_arready[i]),
            .rid(bank_rid[12*i+:12]), .rdata(bank_rdata[32*i+:32]),
            .rresp(bank_rresp[2*i+:2]), .rlast(bank_rlast[i]), .rvalid(bank_rvalid[i]),
            .rready(rready && read_active && read_bank == i),
            .tx_data(tx_data[32*i+:32]), .tx_last(tx_last[i]), .tx_valid(tx_valid[i]), .tx_ready(tx_ready[i]),
            .rx_data(rx_data[32*i+:32]), .rx_last(rx_last[i]), .rx_valid(rx_valid[i]), .rx_ready(rx_ready[i]),
            .irq(irq[i])
        );
    end endgenerate
endmodule
