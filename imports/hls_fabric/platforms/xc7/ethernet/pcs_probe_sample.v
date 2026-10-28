// Counters at the raw 20-bit, gearbox 10-bit and decoded 8b/10b boundaries.
// All counters wrap. reset_n is asserted with the owning recovered clock alive.
module ethernet_pcs_raw_sample(
    input wire clock, reset_n, enable,
    input wire [19:0] word,
    output reg [31:0] words, low_commas, high_commas,
    output reg [19:0] last_word
);
    wire low_comma = word[9:0] == 10'h17c || word[9:0] == 10'h283;
    wire high_comma = word[19:10] == 10'h17c || word[19:10] == 10'h283;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            words <= 0; low_commas <= 0; high_commas <= 0; last_word <= 0;
        end else if (enable) begin
            words <= words + 1'b1;
            low_commas <= low_commas + low_comma;
            high_commas <= high_commas + high_comma;
            last_word <= word;
        end
    end
endmodule

module ethernet_pcs_decode_sample(
    input wire clock, reset_n, enable,
    input wire [9:0] tbi,
    input wire [7:0] data,
    input wire k, invalid, seen_ci, seen_config,
    input wire [15:0] config_word, lp_abi,
    output reg [31:0] symbols, invalids, k28_5, c1, c2, ci, configs,
    output reg [9:0] last_tbi,
    output reg [7:0] last_data,
    output reg last_k, last_invalid,
    output reg [15:0] last_config, last_lp_abi
);
    reg after_comma;
    wire valid = !invalid;
    wire comma = valid && k && data == 8'hbc;
    reg invalid_event, comma_event, c1_event, c2_event, ci_event, config_event;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            symbols <= 0; invalids <= 0; k28_5 <= 0; c1 <= 0; c2 <= 0;
            ci <= 0; configs <= 0; after_comma <= 0; last_tbi <= 0;
            last_data <= 0; last_k <= 0; last_invalid <= 0;
            last_config <= 0; last_lp_abi <= 0;
            invalid_event <= 0; comma_event <= 0; c1_event <= 0; c2_event <= 0;
            ci_event <= 0; config_event <= 0;
        end else if (enable) begin
            symbols <= symbols + 1'b1;
            invalids <= invalids + invalid_event;
            k28_5 <= k28_5 + comma_event;
            c1 <= c1 + c1_event;
            c2 <= c2 + c2_event;
            ci <= ci + ci_event;
            configs <= configs + config_event;
            invalid_event <= invalid;
            comma_event <= comma;
            c1_event <= after_comma && valid && !k && data == 8'hb5;
            c2_event <= after_comma && valid && !k && data == 8'h42;
            ci_event <= seen_ci;
            config_event <= seen_config;
            after_comma <= comma;
            last_tbi <= tbi;
            last_data <= data;
            last_k <= k;
            last_invalid <= invalid;
            last_lp_abi <= lp_abi;
            if (seen_config) last_config <= config_word;
        end
    end
endmodule

module ethernet_pcs_tx_sample(
    input wire clock, reset_n, enable, restart,
    output reg [31:0] restarts
);
    always @(posedge clock or negedge reset_n)
        if (!reset_n) restarts <= 0;
        else if (enable) restarts <= restarts + restart;
endmodule
