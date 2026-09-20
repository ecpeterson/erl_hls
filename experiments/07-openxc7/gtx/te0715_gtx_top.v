// Compile-only TE0715 lane-1 PRBS7 loopback and GP0 diagnostics. See docs/gtx.md
// for the register contract and unqualified clock/bitstream dependencies.
module te0715_gtx_top(
    input wire ref_p, input wire ref_n, input wire gt_rx_p, input wire gt_rx_n,
    output wire gt_tx_p, output wire gt_tx_n
);
    wire clock, reset_n, pll_reset, gt_reset, user_ready, measure;
    wire tx_clock, rx_clock, pll_lock, tx_done, rx_done, rx_error;
    wire [31:0] control, status, rx_words, rx_errors, tx_words;
    wire rx_fresh, tx_fresh, rx_measure, force_error;
    wire counter_reset_n = reset_n && control[0];
    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h47545837)) processor_shell(
        .clock(clock), .reset_n(reset_n), .control(control),
        .status({tx_words, rx_errors, rx_words, status}));
    gtx_probe_control controller(
        .clock(clock), .reset_n(reset_n), .run(control[0]),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_fresh(tx_fresh), .rx_fresh(rx_fresh), .pll_reset(pll_reset),
        .gt_reset(gt_reset), .user_ready(user_ready), .measure(measure), .status(status));
    gtx_probe_sample rx_sample(
        .clock(clock), .source_clock(rx_clock), .reset_n(counter_reset_n),
        .enable(measure), .error(rx_error), .source_enable(rx_measure),
        .words(rx_words), .errors(rx_errors), .fresh(rx_fresh));
    gtx_probe_sample tx_sample(
        .clock(clock), .source_clock(tx_clock), .reset_n(counter_reset_n),
        .enable(control[1]), .error(1'b0), .source_enable(force_error),
        .words(tx_words), .fresh(tx_fresh));
    te0715_gtx_lane transceiver(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n),
        .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n), .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready),
        .force_error(force_error), .measure(rx_measure), .pll_lock(pll_lock),
        .tx_done(tx_done), .rx_done(rx_done), .rx_error(rx_error),
        .tx_clock(tx_clock), .rx_clock(rx_clock));
endmodule
