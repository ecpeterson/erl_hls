// External 1000BASE-X boundary probe. The production PCS exchanges real
// configuration ordered sets while counters expose the first stalled layer.
// Control bit 0 runs; bits 6:4 select one of five read-only status pages.
module te0715_pcs_probe_top(
    input wire ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n
);
    wire clock, reset_n, pll_reset, gt_reset, user_ready, measure;
    wire pll_lock, tx_done, rx_done, tx_out_clock, rx_out_clock;
    wire tx_clock, rx_clock, tx_half_clock, rx_half_clock, tx_locked, rx_locked;
    wire tx_fresh, rx_fresh, tx_reset_n, rx_reset_n, tx_half_reset_n, rx_half_reset_n;
    wire [31:0] control, physical_status;
    wire [15:0] gt_tx_data, gt_rx_data;
    wire [1:0] gt_tx_dispval, gt_tx_dispmode, gt_rx_charisk, gt_rx_disperr;
    wire [19:0] tx_word, rx_word;
    wire [9:0] tbi_tx, tbi_rx;
    wire [7:0] decoded_data;
    wire decoded_k, decoded_invalid, seen_ci, seen_config;
    wire [15:0] rx_config, lp_abi;
    wire link, restart, align, autoneg_ack, config_empty;
    wire [31:0] raw_words, low_commas, high_commas;
    wire [19:0] raw_last;
    wire [31:0] symbols, invalids, k28_5, c1, c2, ci, configs, restarts;
    wire [9:0] last_tbi;
    wire [7:0] last_data;
    wire last_k, last_invalid;
    wire [15:0] last_config, last_lp_abi;
    wire [115:0] raw_values = {raw_last, high_commas, low_commas, raw_words};
    wire [115:0] raw_snapshot;
    wire [275:0] rx_values = {last_lp_abi, last_config, last_invalid, last_k,
                              last_data, last_tbi, configs, ci, c2, c1,
                              k28_5, invalids, symbols};
    wire [275:0] rx_snapshot;
    wire [31:0] tx_snapshot;
    reg [127:0] selected_page;
    reg [5:0] flags_meta, flags_sync;
    reg [1:0] done_meta, done_sync;

    assign gt_tx_data = {tx_word[17:10], tx_word[7:0]};
    assign gt_tx_dispval = {tx_word[18], tx_word[8]};
    assign gt_tx_dispmode = {tx_word[19], tx_word[9]};
    assign rx_word = {gt_rx_disperr[1], gt_rx_charisk[1], gt_rx_data[15:8],
                      gt_rx_disperr[0], gt_rx_charisk[0], gt_rx_data[7:0]};

    always @* begin
        case (control[6:4])
            0: selected_page = {raw_snapshot[95:64], raw_snapshot[63:32],
                                raw_snapshot[31:0], physical_status};
            1: selected_page = {rx_snapshot[95:64], rx_snapshot[63:32],
                                rx_snapshot[31:0], physical_status};
            2: selected_page = {rx_snapshot[223:192], rx_snapshot[159:128],
                                rx_snapshot[127:96], physical_status};
            3: selected_page = {{rx_snapshot[275:260], rx_snapshot[259:244]},
                                tx_snapshot, rx_snapshot[191:160], physical_status};
            4: selected_page = {{10'b0, flags_sync, 16'b0},
                                {12'b0, rx_snapshot[233:224], rx_snapshot[243],
                                 rx_snapshot[242], rx_snapshot[241:234]},
                                {12'b0, raw_snapshot[115:96]},
                                physical_status};
            default: selected_page = {96'b0, physical_status};
        endcase
    end

    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h50435337)) processor_shell(
        .clock(clock), .reset_n(reset_n), .control(control), .status(selected_page));
    ethernet_gtx_clocks clocks(
        .clock(clock), .reset_n(reset_n), .gt_reset(gt_reset),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock),
        .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_half_clock(tx_half_clock), .rx_half_clock(rx_half_clock),
        .tx_locked(tx_locked), .rx_locked(rx_locked));
    ethernet_clock_pair tx_watch(clock, reset_n, tx_clock, tx_half_clock, tx_fresh);
    ethernet_clock_pair rx_watch(clock, reset_n, rx_clock, rx_half_clock, rx_fresh);
    gtx_probe_control controller(
        .clock(clock), .reset_n(reset_n), .run(control[0]),
        .pll_lock(pll_lock), .tx_done(done_sync[0] && flags_sync[0]),
        .rx_done(done_sync[1] && flags_sync[1]),
        .tx_fresh(tx_fresh), .rx_fresh(rx_fresh), .pll_reset(pll_reset),
        .gt_reset(gt_reset), .user_ready(user_ready), .measure(measure),
        .status(physical_status));

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            done_meta <= 0; done_sync <= 0; flags_meta <= 0; flags_sync <= 0;
        end else begin
            done_meta <= {rx_done, tx_done};
            done_sync <= done_meta;
            flags_meta <= {link, config_empty, autoneg_ack, align, rx_locked, tx_locked};
            flags_sync <= flags_meta;
        end
    end

    wire packet_reset_n = reset_n && measure;
    zynq_probe_reset tr(tx_clock, packet_reset_n, tx_reset_n);
    zynq_probe_reset rr(rx_clock, packet_reset_n, rx_reset_n);
    zynq_probe_reset th(tx_half_clock, packet_reset_n, tx_half_reset_n);
    zynq_probe_reset rh(rx_half_clock, packet_reset_n, rx_half_reset_n);

    liteeth_pcs_probe pcs(
        .eth_tx_clk(tx_clock), .eth_tx_rst(!tx_reset_n),
        .eth_rx_clk(rx_clock), .eth_rx_rst(!rx_reset_n),
        .tbi_tx(tbi_tx), .tbi_rx(tbi_rx), .link(link), .restart(restart), .align(align),
        .rx_data(decoded_data), .rx_k(decoded_k), .rx_invalid(decoded_invalid),
        .rx_seen_ci(seen_ci), .rx_seen_config(seen_config), .rx_config(rx_config),
        .lp_abi(lp_abi), .autoneg_ack(autoneg_ack),
        .config_empty(config_empty));
    liteeth_pcs_gearbox gearbox(
        .eth_tx_clk(tx_clock), .eth_tx_rst(!tx_reset_n),
        .eth_rx_clk(rx_clock), .eth_rx_rst(!rx_reset_n),
        .eth_tx_half_clk(tx_half_clock), .eth_tx_half_rst(!tx_half_reset_n),
        .eth_rx_half_clk(rx_half_clock), .eth_rx_half_rst(!rx_half_reset_n),
        .tx_data(tbi_tx), .tx_data_half(tx_word),
        .rx_data_half(rx_word), .rx_data(tbi_rx));

    reg align_registered;
    reg [1:0] align_sync;
    always @(posedge tx_clock or negedge tx_reset_n)
        if (!tx_reset_n) align_registered <= 0; else align_registered <= align;
    always @(posedge rx_half_clock or negedge rx_half_reset_n)
        if (!rx_half_reset_n) align_sync <= 0;
        else align_sync <= {align_sync[0], align_registered};

    ethernet_pcs_raw_sample raw_sample(
        .clock(rx_half_clock), .reset_n(rx_half_reset_n), .enable(1'b1), .word(rx_word),
        .words(raw_words), .low_commas(low_commas), .high_commas(high_commas),
        .last_word(raw_last));
    ethernet_pcs_decode_sample decode_sample(
        .clock(rx_clock), .reset_n(rx_reset_n), .enable(1'b1), .tbi(tbi_rx),
        .data(decoded_data), .k(decoded_k), .invalid(decoded_invalid),
        .seen_ci(seen_ci), .seen_config(seen_config), .config_word(rx_config), .lp_abi(lp_abi),
        .symbols(symbols), .invalids(invalids), .k28_5(k28_5), .c1(c1), .c2(c2),
        .ci(ci), .configs(configs), .last_tbi(last_tbi), .last_data(last_data),
        .last_k(last_k), .last_invalid(last_invalid), .last_config(last_config),
        .last_lp_abi(last_lp_abi));
    ethernet_pcs_tx_sample tx_sample(
        .clock(tx_clock), .reset_n(tx_reset_n), .enable(1'b1),
        .restart(restart), .restarts(restarts));
    ethernet_snapshot #(.WIDTH(116)) raw_cross(
        clock, rx_half_clock, packet_reset_n, raw_values, raw_snapshot);
    ethernet_snapshot #(.WIDTH(276)) rx_cross(
        clock, rx_clock, packet_reset_n, rx_values, rx_snapshot);
    ethernet_snapshot tx_cross(
        clock, tx_clock, packet_reset_n, restarts, tx_snapshot);

    te0715_gtx_channel #(.PRBS(0), .EXTERNAL(1)) transceiver(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n),
        .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n), .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n),
        .pll_reset(pll_reset), .gt_reset(gt_reset),
        .user_ready(user_ready && tx_locked && rx_locked),
        .force_error(1'b0), .measure(1'b0), .align(align_sync[1] && measure),
        .tx_clock(tx_half_clock), .rx_clock(rx_half_clock),
        .tx_data(gt_tx_data), .tx_dispval(gt_tx_dispval), .tx_dispmode(gt_tx_dispmode),
        .rx_data(gt_rx_data), .rx_charisk(gt_rx_charisk), .rx_disperr(gt_rx_disperr),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done), .rx_error(),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock));
endmodule
