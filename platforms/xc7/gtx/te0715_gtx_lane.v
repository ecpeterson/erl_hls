// SPDX-License-Identifier: BSD-2-Clause
// GTX attributes and reserved-port ties derived from LiteICLink, Copyright
// (c) 2017-2024 Florent Kermarrec. See LICENSE.liteiclink and sources.lock.json.
// Compile candidate: 125 MHz refclk1, CPLL 2.5 GHz, 1.25 Gbaud, raw 20-bit
// datapath with both elastic buffers enabled. Fixed near-end PMA loopback;
// zero polarity inversion internally. This does not exercise the SFP pins.
module te0715_gtx_lane(
    input wire clock, ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n,
    input wire pll_reset, gt_reset, user_ready, force_error, measure,
    output wire pll_lock, tx_done, rx_done, rx_error, tx_clock, rx_clock
);
    wire tx_out_clock, rx_out_clock;
    BUFG tx_clock_buffer(.I(tx_out_clock), .O(tx_clock));
    BUFG rx_clock_buffer(.I(rx_out_clock), .O(rx_clock));
    te0715_gtx_channel channel(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n), .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n),
        .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n), .pll_reset(pll_reset), .gt_reset(gt_reset),
        .user_ready(user_ready), .force_error(force_error), .measure(measure), .align(1'b0),
        .tx_clock(tx_clock), .rx_clock(rx_clock), .tx_data(16'b0), .tx_dispval(2'b0), .tx_dispmode(2'b0),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done), .rx_error(rx_error),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock)
    );
endmodule
