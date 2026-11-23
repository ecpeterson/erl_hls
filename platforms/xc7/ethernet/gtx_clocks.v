// Related 125/62.5-MHz pairs from each 62.5-MHz GTX OUTCLK. TX and RX are
// unrelated. Buffered outputs feed PCS/gearbox and GTX USRCLK/USRCLK2.
// Hold MMCMs reset through GTX reset; RX additionally waits 50,000 UI (40 us)
// for CDR settling, following LiteEth's K7 PHY. This delay is not a CDR lock
// measurement. clock is the always-running 25-MHz control clock.
module ethernet_gtx_clocks (
    input wire clock, reset_n, gt_reset, tx_out_clock, rx_out_clock,
    output wire tx_clock, tx_half_clock, rx_clock, rx_half_clock,
    output wire tx_locked, rx_locked
);
    reg [9:0] settle;
    reg rx_reset;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin settle<=0; rx_reset<=1; end
        else if (gt_reset) begin settle<=0; rx_reset<=1; end
        else if (settle<1000) begin settle<=settle+1'b1; rx_reset<=1; end
        else rx_reset<=0;
    end
    ethernet_clock_generator tx(tx_out_clock, gt_reset || !reset_n,
                                tx_clock, tx_half_clock, tx_locked);
    ethernet_clock_generator rx(rx_out_clock, rx_reset,
                                rx_clock, rx_half_clock, rx_locked);
endmodule

// One shared MMCM creates the edge-related pair. 62.5*16=1,000-MHz VCO;
// /8 and /16 yield 125 and 62.5 MHz at zero requested phase. No fabric divider
// or gated data-clock net. Feedback and both outputs use global clock buffers.
module ethernet_clock_generator (
    input wire source_clock, reset,
    output wire full_clock, half_clock, locked
);
    wire input_clock, feedback, feedback_buffered, full_raw, half_raw;
    BUFG input_buffer(.I(source_clock), .O(input_clock));
    BUFG feedback_buffer(.I(feedback), .O(feedback_buffered));
    BUFG full_buffer(.I(full_raw), .O(full_clock));
    BUFG half_buffer(.I(half_raw), .O(half_clock));
    MMCME2_BASE #(.CLKIN1_PERIOD(16.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(16.0),
        .CLKOUT0_DIVIDE_F(8.0), .CLKOUT1_DIVIDE(16), .STARTUP_WAIT("FALSE")) generator (
        .CLKIN1(input_clock), .CLKFBIN(feedback_buffered), .CLKFBOUT(feedback),
        .CLKOUT0(full_raw), .CLKOUT1(half_raw), .RST(reset), .PWRDWN(1'b0), .LOCKED(locked)
    );
endmodule
