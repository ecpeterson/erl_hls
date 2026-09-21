// GTX packet endpoint supervised from an always-running 25-MHz control clock.
// run is synchronous to control_clk; lock/done inputs may be asynchronous.
// full/half clocks retain the endpoint's constrained 2:1 relationship.
//
// The existing GTX startup controller drives pll_reset/gt_reset/user_ready.
// Clock-generator locks must join each corresponding reset-done input. A fault
// latches until run=0; automatic PCS negotiation restart does not reset the GTX.
// tx_reset_n/rx_reset_n assert even with stopped clocks and release locally.
// Producers/consumers MUST abandon partial frames on these resets. All buffered
// frames and packet counters clear on this hard recovery, unlike ordinary PCS
// link loss. No host-clock CDC, MMCM or hard transceiver is instantiated here.
module ethernet_supervised_endpoint #(
    parameter BOOT_CYCLES = 32, RESET_CYCLES = 8, SETTLE_CYCLES = 1024,
    parameter TIMEOUT_CYCLES = 25000, CLOCK_TIMEOUT = 1024
)(
    input wire control_clk, reset_n, run,
    input wire pll_lock, tx_done, rx_done,
    output wire pll_reset, gt_reset, user_ready,
    output wire [31:0] status,
    input wire eth_tx_clk, eth_rx_clk, eth_tx_half_clk, eth_rx_half_clk,
    output wire tx_reset_n, rx_reset_n,
    output wire [15:0] gt_tx_data,
    output wire [1:0] gt_tx_dispval, gt_tx_dispmode,
    input wire [15:0] gt_rx_data,
    input wire [1:0] gt_rx_charisk, gt_rx_disperr,
    output wire gt_align, link_tx, link_rx, restart,
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
    wire control_reset_n, tx_fresh, rx_fresh, physical_ready;
    zynq_probe_reset cr(control_clk, reset_n, control_reset_n);
    ethernet_clock_pair tx_watch(control_clk, control_reset_n, eth_tx_clk, eth_tx_half_clk, tx_fresh);
    ethernet_clock_pair rx_watch(control_clk, control_reset_n, eth_rx_clk, eth_rx_half_clk, rx_fresh);
    gtx_probe_control #(.BOOT_CYCLES(BOOT_CYCLES), .RESET_CYCLES(RESET_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES), .TIMEOUT_CYCLES(TIMEOUT_CYCLES),
        .CLOCK_TIMEOUT(CLOCK_TIMEOUT)) control (
        .clock(control_clk), .reset_n(control_reset_n), .run(run),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_fresh(tx_fresh), .rx_fresh(rx_fresh), .pll_reset(pll_reset),
        .gt_reset(gt_reset), .user_ready(user_ready), .measure(physical_ready), .status(status)
    );
    // Asynchronous assertion masks stale ready/valid even when its owner clock
    // has stopped. Synchronous release guarantees reset edges before reuse.
    wire packet_reset_n = reset_n && physical_ready;
    wire tx_half_reset_n, rx_half_reset_n;
    zynq_probe_reset tr(eth_tx_clk, packet_reset_n, tx_reset_n);
    zynq_probe_reset rr(eth_rx_clk, packet_reset_n, rx_reset_n);
    zynq_probe_reset th(eth_tx_half_clk, packet_reset_n, tx_half_reset_n);
    zynq_probe_reset rh(eth_rx_half_clk, packet_reset_n, rx_half_reset_n);
    wire raw_tx_ready, raw_rx_valid, raw_link_tx, raw_link_rx, raw_restart, raw_align;
    assign tx_ready = tx_reset_n && raw_tx_ready;
    assign rx_valid = rx_reset_n && raw_rx_valid;
    assign link_tx = tx_reset_n && raw_link_tx;
    assign link_rx = rx_reset_n && raw_link_rx;
    assign restart = tx_reset_n && raw_restart;
    assign gt_align = rx_half_reset_n && raw_align;
    ethernet_gtx_packet_endpoint packets (
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(!tx_reset_n),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(!rx_reset_n),
        .eth_tx_half_clk(eth_tx_half_clk), .eth_tx_half_rst(!tx_half_reset_n),
        .eth_rx_half_clk(eth_rx_half_clk), .eth_rx_half_rst(!rx_half_reset_n),
        .gt_tx_data(gt_tx_data), .gt_tx_dispval(gt_tx_dispval), .gt_tx_dispmode(gt_tx_dispmode),
        .gt_rx_data(gt_rx_data), .gt_rx_charisk(gt_rx_charisk), .gt_rx_disperr(gt_rx_disperr),
        .gt_align(raw_align), .link_tx(raw_link_tx), .link_rx(raw_link_rx), .restart(raw_restart),
        .tx_valid(tx_valid && tx_reset_n), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(raw_tx_ready),
        .rx_valid(raw_rx_valid), .rx_last(rx_last), .rx_data(rx_data), .rx_ready(rx_ready && rx_reset_n),
        .tx_queued(tx_queued), .rx_queued(rx_queued),
        .tx_accepted(tx_accepted), .tx_dropped(tx_dropped), .tx_overflowed(tx_overflowed), .tx_aborted(tx_aborted),
        .rx_accepted(rx_accepted), .rx_dropped(rx_dropped), .rx_overflowed(rx_overflowed), .rx_aborted(rx_aborted),
        .preamble_errors(preamble_errors), .crc_errors(crc_errors)
    );
endmodule
