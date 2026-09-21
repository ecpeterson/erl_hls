// Board-facing compile probe: one buffered 1000BASE-X lane and GP0 diagnostics.
// Default is internal PMA loopback. EXTERNAL=1 selects SFP with both polarity
// inversions; it does not activate the carrier controller or verify its clocks.
// Control bit 0 runs the lane, bit 1 enables fixed test-frame transmission.
// Status words: physical/link flags, TX admitted, RX delivered, RX bad pattern.
module te0715_ethernet_top #(parameter EXTERNAL=0)(
    input wire ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n
);
    wire clock, reset_n;
    wire [31:0] control, status;
    wire pll_reset, gt_reset, user_ready, pll_lock, tx_done, rx_done;
    wire tx_out_clock, rx_out_clock, tx_clock, rx_clock, tx_half_clock, rx_half_clock;
    wire tx_locked, rx_locked, tx_reset_n, rx_reset_n, link_tx, link_rx, align;
    wire [15:0] tx_pins, rx_pins;
    wire [1:0] tx_dispval, tx_dispmode, rx_charisk, rx_disperr;
    wire tx_valid, tx_last, tx_ready, rx_valid, rx_last, rx_ready;
    wire [7:0] tx_data, rx_data;
    wire [31:0] sent, received, bad_frames, sent_snapshot;
    wire [63:0] rx_snapshot;
    (* ASYNC_REG="TRUE" *) reg [3:0] flags_meta, flags_sync;
    always @(posedge clock or negedge reset_n)
        if(!reset_n) begin flags_meta<=0; flags_sync<=0; end
        else begin flags_meta<={rx_locked,tx_locked,link_rx,link_tx}; flags_sync<=flags_meta; end
    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h45544837)) processor_shell (
        .clock(clock), .reset_n(reset_n), .control(control),
        .status({rx_snapshot[63:32],rx_snapshot[31:0],sent_snapshot,12'b0,flags_sync,status[15:0]})
    );
    ethernet_supervised_endpoint packets (
        .control_clk(clock), .reset_n(reset_n), .run(control[0]),
        .pll_lock(pll_lock), .tx_done(tx_done && tx_locked), .rx_done(rx_done && rx_locked),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready), .status(status),
        .eth_tx_clk(tx_clock), .eth_rx_clk(rx_clock), .eth_tx_half_clk(tx_half_clock), .eth_rx_half_clk(rx_half_clock),
        .tx_reset_n(tx_reset_n), .rx_reset_n(rx_reset_n),
        .gt_tx_data(tx_pins), .gt_tx_dispval(tx_dispval), .gt_tx_dispmode(tx_dispmode),
        .gt_rx_data(rx_pins), .gt_rx_charisk(rx_charisk), .gt_rx_disperr(rx_disperr),
        .gt_align(align), .link_tx(link_tx), .link_rx(link_rx),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last), .rx_data(rx_data), .rx_ready(rx_ready)
    );
    ethernet_probe_traffic traffic (
        .tx_clock(tx_clock), .tx_reset_n(tx_reset_n), .rx_clock(rx_clock), .rx_reset_n(rx_reset_n),
        .enable(control[1]), .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last), .rx_data(rx_data), .rx_ready(rx_ready),
        .sent(sent), .received(received), .bad_frames(bad_frames)
    );
    ethernet_snapshot tx_stats(clock, tx_clock, reset_n && control[0], sent, sent_snapshot);
    ethernet_snapshot #(.WIDTH(64)) rx_stats(clock, rx_clock, reset_n && control[0],
                                            {bad_frames,received}, rx_snapshot);
    ethernet_gtx_clocks clocks (
        .clock(clock), .reset_n(reset_n), .gt_reset(gt_reset), .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock),
        .tx_clock(tx_clock), .rx_clock(rx_clock), .tx_half_clock(tx_half_clock), .rx_half_clock(rx_half_clock),
        .tx_locked(tx_locked), .rx_locked(rx_locked)
    );
    te0715_gtx_channel #(.PRBS(0), .EXTERNAL(EXTERNAL)) transceiver (
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n), .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n),
        .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n), .pll_reset(pll_reset), .gt_reset(gt_reset),
        .user_ready(user_ready && tx_locked && rx_locked), .force_error(1'b0), .measure(1'b0), .align(align),
        .tx_clock(tx_half_clock), .rx_clock(rx_half_clock), .tx_data(tx_pins), .tx_dispval(tx_dispval), .tx_dispmode(tx_dispmode),
        .rx_data(rx_pins), .rx_charisk(rx_charisk), .rx_disperr(rx_disperr),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock)
    );
endmodule
