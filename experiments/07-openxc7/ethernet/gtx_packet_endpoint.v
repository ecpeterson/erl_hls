// Complete-frame service at the GTX raw 20-bit pin boundary, with hard 8b/10b
// bypassed. Each 125-MHz eth clock and 62.5-MHz half clock must come from one
// constrained clock generator. TX and RX pairs may be unrelated to each other.
// See packet_endpoint.v for frame/loss semantics. Reset each full/half pair
// together with stable clocks before use; this module does not recover clocks
// or sequence GTX reset. Half-domain pins transfer every cycle without ready.
module ethernet_gtx_packet_endpoint (
    input wire eth_tx_clk, eth_tx_rst, eth_rx_clk, eth_rx_rst,
    input wire eth_tx_half_clk, eth_tx_half_rst, eth_rx_half_clk, eth_rx_half_rst,
    output wire [15:0] gt_tx_data,
    output wire [1:0] gt_tx_dispval, gt_tx_dispmode,
    input wire [15:0] gt_rx_data,
    input wire [1:0] gt_rx_charisk, gt_rx_disperr,
    output wire gt_align,
    output wire link_tx, link_rx, restart,
    input wire tx_valid, tx_last,
    input wire [7:0] tx_data,
    output wire tx_ready,
    output wire rx_valid, rx_last,
    output wire [7:0] rx_data,
    input wire rx_ready,
    output wire [1:0] tx_queued, rx_queued,
    output wire [31:0] tx_accepted, tx_dropped, tx_overflowed, tx_aborted,
    output wire [31:0] rx_accepted, rx_dropped, rx_overflowed, rx_aborted,
    output wire [31:0] preamble_errors, crc_errors
);
    wire [9:0] tbi_tx, tbi_rx;
    wire [19:0] tx_word, rx_word;
    wire align;
    // In raw mode the two extra bits travel through disparity sideband pins,
    // not through TXCHARISK. Low symbol/bit goes first on the serial wire.
    assign gt_tx_data = {tx_word[17:10], tx_word[7:0]};
    assign gt_tx_dispval = {tx_word[18], tx_word[8]};
    assign gt_tx_dispmode = {tx_word[19], tx_word[9]};
    assign rx_word = {gt_rx_disperr[1], gt_rx_charisk[1], gt_rx_data[15:8],
                      gt_rx_disperr[0], gt_rx_charisk[0], gt_rx_data[7:0]};
    // PCS requests alignment in TX; the GTX control is consumed in RX half.
    (* ASYNC_REG = "TRUE" *) reg [1:0] align_sync = 0;
    always @(posedge eth_rx_half_clk)
        if (eth_rx_half_rst) align_sync <= 0;
        else align_sync <= {align_sync[0], align};
    assign gt_align = align_sync[1];
    liteeth_pcs_gearbox gearbox (
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .eth_tx_half_clk(eth_tx_half_clk), .eth_tx_half_rst(eth_tx_half_rst),
        .eth_rx_half_clk(eth_rx_half_clk), .eth_rx_half_rst(eth_rx_half_rst),
        .tx_data(tbi_tx), .tx_data_half(tx_word),
        .rx_data_half(rx_word), .rx_data(tbi_rx)
    );
    ethernet_packet_endpoint packets (
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .tbi_tx(tbi_tx), .tbi_rx(tbi_rx), .align(align),
        .link_tx(link_tx), .link_rx(link_rx), .restart(restart),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last), .rx_data(rx_data), .rx_ready(rx_ready),
        .tx_queued(tx_queued), .rx_queued(rx_queued),
        .tx_accepted(tx_accepted), .tx_dropped(tx_dropped),
        .tx_overflowed(tx_overflowed), .tx_aborted(tx_aborted),
        .rx_accepted(rx_accepted), .rx_dropped(rx_dropped),
        .rx_overflowed(rx_overflowed), .rx_aborted(rx_aborted),
        .preamble_errors(preamble_errors), .crc_errors(crc_errors)
    );
endmodule
