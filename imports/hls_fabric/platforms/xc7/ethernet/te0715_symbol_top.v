// External raw-symbol probe. It transmits alternating K28.5 disparity forms,
// observes the recovered 20-bit stream at every phase and can enable the hard
// comma aligner. Control bit 0 runs, bit 1 aligns and bit 4 selects status page.
module te0715_symbol_top(
    input wire ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n
);
    localparam [19:0] PATTERN = {10'h283, 10'h17c};
    wire clock, reset_n, pll_reset, gt_reset, user_ready, measure;
    wire pll_lock, tx_done, rx_done, tx_out_clock, rx_out_clock, tx_clock, rx_clock;
    wire [31:0] control, physical_status, tx_words;
    wire [31:0] raw_phase, rx_words, patterns, aligned, swapped, phase_changes;
    wire tx_fresh, rx_fresh, unused_tx_enable;
    wire [15:0] rx_data;
    wire [1:0] rx_charisk, rx_disperr;
    wire [19:0] rx_word = {rx_disperr[1], rx_charisk[1], rx_data[15:8],
                           rx_disperr[0], rx_charisk[0], rx_data[7:0]};
    wire [127:0] page_zero = {patterns, rx_words, raw_phase, physical_status};
    wire [127:0] page_one = {phase_changes, swapped, aligned, physical_status};
    wire counter_reset_n = reset_n && control[0];
    BUFG tx_clock_buffer(.I(tx_out_clock), .O(tx_clock));
    BUFG rx_clock_buffer(.I(rx_out_clock), .O(rx_clock));

    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h53594d37)) processor_shell(
        .clock(clock), .reset_n(reset_n), .control(control),
        .status(control[4] ? page_one : page_zero));
    gtx_probe_control controller(
        .clock(clock), .reset_n(reset_n), .run(control[0]),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_fresh(tx_fresh), .rx_fresh(rx_fresh), .pll_reset(pll_reset),
        .gt_reset(gt_reset), .user_ready(user_ready), .measure(measure),
        .status(physical_status));
    gtx_probe_sample tx_sample(
        .clock(clock), .source_clock(tx_clock), .reset_n(counter_reset_n),
        .enable(1'b0), .error(1'b0), .source_enable(unused_tx_enable),
        .words(tx_words), .errors(), .fresh(tx_fresh));
    ethernet_symbol_probe_sample #(.PATTERN(PATTERN)) rx_sample(
        .clock(clock), .source_clock(rx_clock), .reset_n(counter_reset_n),
        .enable(measure), .word(rx_word), .raw_phase(raw_phase), .words(rx_words),
        .patterns(patterns), .aligned(aligned), .swapped(swapped),
        .phase_changes(phase_changes), .fresh(rx_fresh));
    te0715_gtx_channel #(.PRBS(0), .EXTERNAL(1)) transceiver(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n),
        .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n), .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready),
        .force_error(1'b0), .measure(1'b0), .align(control[1] && measure),
        .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_data({PATTERN[17:10], PATTERN[7:0]}),
        .tx_dispval({PATTERN[18], PATTERN[8]}),
        .tx_dispmode({PATTERN[19], PATTERN[9]}),
        .rx_data(rx_data), .rx_charisk(rx_charisk), .rx_disperr(rx_disperr),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .rx_error(), .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock));
endmodule
