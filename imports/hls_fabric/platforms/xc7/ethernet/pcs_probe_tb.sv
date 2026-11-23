`timescale 1ns/1ps
module pcs_probe_tb;
    reg raw_clock = 0, rx_clock = 0, tx_clock = 0, reset_n = 0, enable = 0;
    always #8 raw_clock = !raw_clock;
    always #4 rx_clock = !rx_clock;
    always #4 tx_clock = !tx_clock;
    reg [19:0] word = 0;
    reg [9:0] tbi = 0;
    reg [7:0] data = 0;
    reg k = 0, invalid = 0, seen_ci = 0, seen_config = 0, restart = 0;
    reg [15:0] config_word = 0, lp_abi = 0;
    wire [31:0] raw_words, low_commas, high_commas;
    wire [19:0] last_word;
    wire [31:0] symbols, invalids, k28_5, c1, c2, ci, configs, restarts;
    wire [9:0] last_tbi;
    wire [7:0] last_data;
    wire last_k, last_invalid;
    wire [15:0] last_config, last_lp_abi;

    ethernet_pcs_raw_sample raw(
        raw_clock, reset_n, enable, word, raw_words, low_commas, high_commas, last_word);
    ethernet_pcs_decode_sample decoded(
        rx_clock, reset_n, enable, tbi, data, k, invalid, seen_ci, seen_config,
        config_word, lp_abi, symbols, invalids, k28_5, c1, c2, ci, configs,
        last_tbi, last_data, last_k, last_invalid, last_config, last_lp_abi);
    ethernet_pcs_tx_sample tx(tx_clock, reset_n, enable, restart, restarts);

    task rx_symbol(input [9:0] code, input [7:0] byte_value,
                   input is_k, input bad, input ci_pulse, input config_pulse);
        begin
            @(negedge rx_clock);
            tbi = code; data = byte_value; k = is_k; invalid = bad;
            seen_ci = ci_pulse; seen_config = config_pulse;
            @(posedge rx_clock); #1;
            k = 0; invalid = 0; seen_ci = 0; seen_config = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge rx_clock);
        reset_n = 1; enable = 1; config_word = 16'h4020; lp_abi = 16'h0020;
        @(negedge raw_clock); word = {10'h155, 10'h17c};
        @(negedge raw_clock); word = {10'h283, 10'h155};
        rx_symbol(10'h17c, 8'hbc, 1, 0, 0, 0);
        rx_symbol(10'h2aa, 8'hb5, 0, 0, 1, 0);
        rx_symbol(10'h283, 8'hbc, 1, 0, 0, 0);
        rx_symbol(10'h155, 8'h42, 0, 0, 1, 0);
        rx_symbol(10'h000, 8'h00, 0, 1, 0, 0);
        rx_symbol(10'h123, 8'h20, 0, 0, 0, 1);
        rx_symbol(10'h123, 8'h20, 0, 0, 0, 0);
        @(negedge tx_clock); restart = 1;
        @(posedge tx_clock); #1; restart = 0;
        @(negedge raw_clock); enable = 0;
        #20;
        if (raw_words < 2 || low_commas == 0 || high_commas == 0) $fatal(1, "raw counters");
        if (symbols < 7 || invalids != 1 || k28_5 != 2) $fatal(1, "decode counters");
        if (c1 != 1 || c2 != 1 || ci != 2 || configs != 1) $fatal(1, "ordered sets");
        if (last_config != 16'h4020 || last_lp_abi != 16'h0020) $fatal(1, "config capture");
        if (restarts != 1) $fatal(1, "restart counter");
        $display("PASS: raw, decoded, ordered-set, configuration and restart counters");
        $finish;
    end
endmodule
