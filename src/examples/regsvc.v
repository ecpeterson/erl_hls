module __axis__Top__Rx_0_next(
  input wire clk,
  input wire reset,
  input wire [32:0] regsvc__ext_recv,
  input wire regsvc__ext_recv_vld,
  input wire regsvc__req_rdy,
  output wire regsvc__ext_recv_rdy,
  output wire [127:0] regsvc__req,
  output wire regsvc__req_vld
);
  wire [32:0] __regsvc__ext_recv_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] __regsvc__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg [7:0] ____state_1;
  reg [127:0] ____state_0;
  reg [32:0] __regsvc__ext_recv_reg;
  reg __regsvc__ext_recv_valid_reg;
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  wire beat_tlast;
  wire regsvc__req_valid_inv;
  wire __regsvc__req_vld_buf;
  wire regsvc__req_valid_load_en;
  wire [1:0] ____state_0__next_value_predicates;
  wire regsvc__req_load_en;
  wire [2:0] one_hot_1915;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_2337;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_2336;
  wire [31:0] sel_2335;
  wire [31:0] sel_2334;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_1947;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_2363;
  wire [127:0] one_hot_sel_1948;
  wire [7:0] one_hot_sel_1954;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_1915 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_2337 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_2336 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_2335 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_2334 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_1915[1] & beat_tlast == one_hot_1915[0];
  assign concat_1947 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_2336, sel_2335, sel_2334, sel_2337};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_2363 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_1948 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_1947[0]}} | payload & {128{concat_1947[1]}};
  assign one_hot_sel_1954 = 8'h00 & {8{concat_1947[0]}} | words_seen & {8{concat_1947[1]}};
  assign __regsvc__req_buf = {{sel_2337[7:0], sel_2337[15:8], sel_2337[23:16], sel_2337[31:24]}, {sel_2336, sel_2335, sel_2334}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_1954 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_1948 : ____state_0;
      __regsvc__ext_recv_reg <= regsvc__ext_recv_load_en ? regsvc__ext_recv : __regsvc__ext_recv_reg;
      __regsvc__ext_recv_valid_reg <= regsvc__ext_recv_valid_load_en ? regsvc__ext_recv_vld : __regsvc__ext_recv_valid_reg;
      __regsvc__req_reg <= regsvc__req_load_en ? __regsvc__req_buf : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? __regsvc__req_vld_buf : __regsvc__req_valid_reg;
    end
  end
  assign regsvc__ext_recv_rdy = regsvc__ext_recv_load_en;
  assign regsvc__req = __regsvc__req_reg;
  assign regsvc__req_vld = __regsvc__req_valid_reg;
endmodule


module __axis__Top__Tx_0_next(
  input wire clk,
  input wire reset,
  input wire regsvc__ext_send_rdy,
  input wire [127:0] regsvc__resp,
  input wire regsvc__resp_vld,
  output wire [32:0] regsvc__ext_send,
  output wire regsvc__ext_send_vld,
  output wire regsvc__resp_rdy
);
  wire [127:0] __regsvc__resp_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __regsvc__ext_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_2005 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  reg [32:0] __regsvc__ext_send_reg;
  reg __regsvc__ext_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] regsvc__resp_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire regsvc__ext_send_valid_inv;
  wire nor_2017;
  wire not_2018;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire regsvc__ext_send_load_en;
  wire [2:0] one_hot_2027;
  wire [2:0] one_hot_2028;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire regsvc__resp_valid_inv;
  wire and_2067;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_2070;
  wire [127:0] payload;
  wire [1:0] concat_2083;
  wire [7:0] beats_sent;
  wire regsvc__resp_load_en;
  wire or_2367;
  wire or_2371;
  wire [7:0] one_hot_sel_2071;
  wire and_2091;
  wire [127:0] one_hot_sel_2078;
  wire [7:0] one_hot_sel_2084;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_2005;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign nor_2017 = ~(last | ____state_0);
  assign not_2018 = ~last;
  assign __regsvc__ext_send_vld_buf = ____state_0 | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_2017};
  assign ____state_6__next_value_predicates = {not_2018, last};
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign one_hot_2027 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_2028 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign and_2067 = last & p0_stage_done;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | regsvc__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_2027[1] & nor_2017 == one_hot_2027[0];
  assign ____state_6__at_most_one_next_value = not_2018 == one_hot_2028[1] & last == one_hot_2028[0];
  assign concat_2070 = {and_2067, nor_2017 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_2083 = {not_2018 & p0_stage_done, and_2067};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign or_2367 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_2371 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_2071 = frame_header_payload_words__1 & {8{concat_2070[0]}} | 8'h00 & {8{concat_2070[1]}};
  assign and_2091 = (last | nor_2017) & p0_stage_done;
  assign one_hot_sel_2078 = payload & {128{concat_2070[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2070[1]}};
  assign one_hot_sel_2084 = 8'h00 & {8{concat_2083[0]}} | beats_sent & {8{concat_2083[1]}};
  assign __regsvc__ext_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__resp_reg <= __regsvc__resp_reg_init;
      __regsvc__resp_valid_reg <= 1'h0;
      __regsvc__ext_send_reg <= __regsvc__ext_send_reg_init;
      __regsvc__ext_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_2018 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_2084 : ____state_6;
      ____state_1 <= and_2091 ? one_hot_sel_2071 : ____state_1;
      ____state_5 <= and_2091 ? one_hot_sel_2078 : ____state_5;
      __regsvc__resp_reg <= regsvc__resp_load_en ? regsvc__resp : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? regsvc__resp_vld : __regsvc__resp_valid_reg;
      __regsvc__ext_send_reg <= regsvc__ext_send_load_en ? __regsvc__ext_send_buf : __regsvc__ext_send_reg;
      __regsvc__ext_send_valid_reg <= regsvc__ext_send_valid_load_en ? __regsvc__ext_send_vld_buf : __regsvc__ext_send_valid_reg;
    end
  end
  assign regsvc__ext_send = __regsvc__ext_send_reg;
  assign regsvc__ext_send_vld = __regsvc__ext_send_valid_reg;
  assign regsvc__resp_rdy = regsvc__resp_load_en;
endmodule


module __regsvc__Top_0_next__1(
  input wire clk,
  input wire reset
);

endmodule


module __regsvc__Top__Service_0_next(
  input wire clk,
  input wire reset,
  input wire [127:0] regsvc__req,
  input wire regsvc__req_vld,
  input wire regsvc__resp_rdy,
  output wire regsvc__req_rdy,
  output wire [127:0] regsvc__resp,
  output wire regsvc__resp_vld
);
  wire [31:0] ____state_1_init[0:15];
  assign ____state_1_init[0] = 32'h0000_0000;
  assign ____state_1_init[1] = 32'h0000_0000;
  assign ____state_1_init[2] = 32'h0000_0000;
  assign ____state_1_init[3] = 32'h0000_0000;
  assign ____state_1_init[4] = 32'h0000_0000;
  assign ____state_1_init[5] = 32'h0000_0000;
  assign ____state_1_init[6] = 32'h0000_0000;
  assign ____state_1_init[7] = 32'h0000_0000;
  assign ____state_1_init[8] = 32'h0000_0000;
  assign ____state_1_init[9] = 32'h0000_0000;
  assign ____state_1_init[10] = 32'h0000_0000;
  assign ____state_1_init[11] = 32'h0000_0000;
  assign ____state_1_init[12] = 32'h0000_0000;
  assign ____state_1_init[13] = 32'h0000_0000;
  assign ____state_1_init[14] = 32'h0000_0000;
  assign ____state_1_init[15] = 32'h0000_0000;
  wire [127:0] __regsvc__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __regsvc__resp_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [31:0] literal_2160[0:15];
  assign literal_2160[0] = 32'h0000_0000;
  assign literal_2160[1] = 32'h0000_0000;
  assign literal_2160[2] = 32'h0000_0000;
  assign literal_2160[3] = 32'h0000_0000;
  assign literal_2160[4] = 32'h0000_0000;
  assign literal_2160[5] = 32'h0000_0000;
  assign literal_2160[6] = 32'h0000_0000;
  assign literal_2160[7] = 32'h0000_0000;
  assign literal_2160[8] = 32'h0000_0000;
  assign literal_2160[9] = 32'h0000_0000;
  assign literal_2160[10] = 32'h0000_0000;
  assign literal_2160[11] = 32'h0000_0000;
  assign literal_2160[12] = 32'h0000_0000;
  assign literal_2160[13] = 32'h0000_0000;
  assign literal_2160[14] = 32'h0000_0000;
  assign literal_2160[15] = 32'h0000_0000;
  reg [31:0] ____state_1[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [31:0] frame_header;
  wire [95:0] frame_payload__2;
  wire [7:0] frame_header_op;
  wire eq_2202;
  wire eq_2180;
  wire eq_2203;
  wire static_match_1_2;
  wire [2:0] concat_2210;
  wire resp2_header_op_squeezed__3_to_4;
  wire resp2_header_op_squeezed__0_to_1;
  wire or_2245;
  wire regsvc__resp_valid_inv;
  wire [3:0] resp2_header_op_squeezed_const_msb_bits;
  wire eq_2208;
  wire nor_2209;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [31:0] register_1;
  wire [26:0] sub_2199;
  wire [1:0] ____state_1__next_value_predicates;
  wire regsvc__resp_not_pred;
  wire regsvc__resp_load_en;
  wire [31:0] value_1__1;
  wire [511:0] _2__2;
  wire [2:0] one_hot_2227;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [511:0] _3__2;
  wire [511:0] shll_2215;
  wire p0_stage_done;
  wire [31:0] _4__2;
  wire [31:0] _5__2;
  wire [1:0] resp2_header_op_squeezed__1_to_3;
  wire [3:0] one_hot_2338;
  wire regsvc__req_valid_inv;
  wire [31:0] newvalue_1;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire [95:0] _4__3;
  wire regsvc__req_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_2261;
  wire [31:0] newregisters_1[0:15];
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire or_2373;
  wire [31:0] one_hot_sel_2262[0:15];
  wire and_2268;
  wire [127:0] resp2;
  wire or_2375;
  assign frame_header = __regsvc__req_reg[127:96];
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign frame_header_op = frame_header[7:0];
  assign eq_2202 = frame_header_op == 8'h06;
  assign eq_2180 = frame_header_op == 8'h04;
  assign eq_2203 = frame_header_op == 8'h05;
  assign static_match_1_2 = frame_payload__2[31:4] == 28'h000_0000;
  assign concat_2210 = {eq_2202, eq_2180, eq_2203};
  assign resp2_header_op_squeezed__3_to_4 = 1'h0 & concat_2210[0] | static_match_1_2 & concat_2210[1] | 1'h1 & concat_2210[2];
  assign resp2_header_op_squeezed__0_to_1 = 1'h1 & concat_2210[0] | ~static_match_1_2 & concat_2210[1] | 1'h1 & concat_2210[2];
  assign or_2245 = resp2_header_op_squeezed__3_to_4 | resp2_header_op_squeezed__0_to_1;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign resp2_header_op_squeezed_const_msb_bits = 4'h0;
  assign eq_2208 = frame_header_op == 8'h03;
  assign nor_2209 = ~(~eq_2180 | static_match_1_2);
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & or_2245;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign register_1 = frame_payload__2[31:0];
  assign sub_2199 = 27'h000_0010 - frame_payload__2[58:32];
  assign ____state_1__next_value_predicates = {eq_2208, nor_2209};
  assign regsvc__resp_not_pred = ~or_2245;
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign value_1__1 = ____state_1[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign _2__2 = {____state_1[resp2_header_op_squeezed_const_msb_bits], ____state_1[4'h1], ____state_1[4'h2], ____state_1[4'h3], ____state_1[4'h4], ____state_1[4'h5], ____state_1[4'h6], ____state_1[4'h7], ____state_1[4'h8], ____state_1[4'h9], ____state_1[4'ha], ____state_1[4'hb], ____state_1[4'hc], ____state_1[4'hd], ____state_1[4'he], ____state_1[4'hf]};
  assign one_hot_2227 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign _3__2 = {frame_payload__2[26:0], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : _2__2 << {frame_payload__2[26:0], 5'h00};
  assign shll_2215 = {sub_2199, 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {sub_2199, 5'h00};
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign _4__2 = ~(~value_1__1 | mask_1);
  assign _5__2 = value_1__2 & mask_1;
  assign resp2_header_op_squeezed__1_to_3 = {2{eq_2203}};
  assign one_hot_2338 = {concat_2210[2:0] == 3'h0, concat_2210[2] && concat_2210[1:0] == 2'h0, concat_2210[1] && !concat_2210[0], concat_2210[0]};
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign newvalue_1 = _4__2 | _5__2;
  assign txid = frame_header[23:16];
  assign resp2_header_op = {resp2_header_op_squeezed_const_msb_bits, resp2_header_op_squeezed__3_to_4, resp2_header_op_squeezed__1_to_3, resp2_header_op_squeezed__0_to_1};
  assign _4__3 = _3__2[511:416] & shll_2215[511:416];
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign ____state_1__at_most_one_next_value = eq_2208 == one_hot_2227[1] & nor_2209 == one_hot_2227[0];
  assign concat_2261 = {eq_2208 & p0_stage_done, nor_2209 & p0_stage_done};
  assign resp2_header = {{6'h00, eq_2202, 1'h1 & concat_2210[0] | static_match_1_2 & concat_2210[1] | 1'h1 & concat_2210[2]}, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign or_2373 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign one_hot_sel_2262[0] = literal_2160[0] & {32{concat_2261[0]}} | newregisters_1[0] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[1] = literal_2160[1] & {32{concat_2261[0]}} | newregisters_1[1] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[2] = literal_2160[2] & {32{concat_2261[0]}} | newregisters_1[2] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[3] = literal_2160[3] & {32{concat_2261[0]}} | newregisters_1[3] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[4] = literal_2160[4] & {32{concat_2261[0]}} | newregisters_1[4] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[5] = literal_2160[5] & {32{concat_2261[0]}} | newregisters_1[5] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[6] = literal_2160[6] & {32{concat_2261[0]}} | newregisters_1[6] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[7] = literal_2160[7] & {32{concat_2261[0]}} | newregisters_1[7] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[8] = literal_2160[8] & {32{concat_2261[0]}} | newregisters_1[8] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[9] = literal_2160[9] & {32{concat_2261[0]}} | newregisters_1[9] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[10] = literal_2160[10] & {32{concat_2261[0]}} | newregisters_1[10] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[11] = literal_2160[11] & {32{concat_2261[0]}} | newregisters_1[11] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[12] = literal_2160[12] & {32{concat_2261[0]}} | newregisters_1[12] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[13] = literal_2160[13] & {32{concat_2261[0]}} | newregisters_1[13] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[14] = literal_2160[14] & {32{concat_2261[0]}} | newregisters_1[14] & {32{concat_2261[1]}};
  assign one_hot_sel_2262[15] = literal_2160[15] & {32{concat_2261[0]}} | newregisters_1[15] & {32{concat_2261[1]}};
  assign and_2268 = (eq_2208 | nor_2209) & p0_stage_done;
  assign resp2 = {resp2_header, {64'h0000_0000_0000_0000, register_1} & {96{concat_2210[0]}} | {64'h0000_0000_0000_0000, {32{static_match_1_2}} & value_1__1} & {96{concat_2210[1]}} | _4__3 & {96{concat_2210[2]}}};
  assign or_2375 = ~p0_stage_done | concat_2210 == one_hot_2338[2:0] | reset;
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1[0] <= ____state_1_init[0];
      ____state_1[1] <= ____state_1_init[1];
      ____state_1[2] <= ____state_1_init[2];
      ____state_1[3] <= ____state_1_init[3];
      ____state_1[4] <= ____state_1_init[4];
      ____state_1[5] <= ____state_1_init[5];
      ____state_1[6] <= ____state_1_init[6];
      ____state_1[7] <= ____state_1_init[7];
      ____state_1[8] <= ____state_1_init[8];
      ____state_1[9] <= ____state_1_init[9];
      ____state_1[10] <= ____state_1_init[10];
      ____state_1[11] <= ____state_1_init[11];
      ____state_1[12] <= ____state_1_init[12];
      ____state_1[13] <= ____state_1_init[13];
      ____state_1[14] <= ____state_1_init[14];
      ____state_1[15] <= ____state_1_init[15];
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
      __regsvc__resp_reg <= __regsvc__resp_reg_init;
      __regsvc__resp_valid_reg <= 1'h0;
    end else begin
      ____state_1[0] <= and_2268 ? one_hot_sel_2262[0] : ____state_1[0];
      ____state_1[1] <= and_2268 ? one_hot_sel_2262[1] : ____state_1[1];
      ____state_1[2] <= and_2268 ? one_hot_sel_2262[2] : ____state_1[2];
      ____state_1[3] <= and_2268 ? one_hot_sel_2262[3] : ____state_1[3];
      ____state_1[4] <= and_2268 ? one_hot_sel_2262[4] : ____state_1[4];
      ____state_1[5] <= and_2268 ? one_hot_sel_2262[5] : ____state_1[5];
      ____state_1[6] <= and_2268 ? one_hot_sel_2262[6] : ____state_1[6];
      ____state_1[7] <= and_2268 ? one_hot_sel_2262[7] : ____state_1[7];
      ____state_1[8] <= and_2268 ? one_hot_sel_2262[8] : ____state_1[8];
      ____state_1[9] <= and_2268 ? one_hot_sel_2262[9] : ____state_1[9];
      ____state_1[10] <= and_2268 ? one_hot_sel_2262[10] : ____state_1[10];
      ____state_1[11] <= and_2268 ? one_hot_sel_2262[11] : ____state_1[11];
      ____state_1[12] <= and_2268 ? one_hot_sel_2262[12] : ____state_1[12];
      ____state_1[13] <= and_2268 ? one_hot_sel_2262[13] : ____state_1[13];
      ____state_1[14] <= and_2268 ? one_hot_sel_2262[14] : ____state_1[14];
      ____state_1[15] <= and_2268 ? one_hot_sel_2262[15] : ____state_1[15];
      __regsvc__req_reg <= regsvc__req_load_en ? regsvc__req : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? regsvc__req_vld : __regsvc__req_valid_reg;
      __regsvc__resp_reg <= regsvc__resp_load_en ? resp2 : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? __regsvc__resp_vld_buf : __regsvc__resp_valid_reg;
    end
  end
  assign regsvc__req_rdy = regsvc__req_load_en;
  assign regsvc__resp = __regsvc__resp_reg;
  assign regsvc__resp_vld = __regsvc__resp_valid_reg;
  for (genvar __i0 = 0; __i0 < 16; __i0 = __i0 + 1) begin : gen__newregisters_1_0
    assign newregisters_1[__i0] = register_1 == __i0 ? newvalue_1 : ____state_1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push(
  input wire clk,
  input wire reset,
  input wire push_valid,
  input wire pop_ready,
  input wire [127:0] push_data,
  output wire push_ready,
  output wire pop_valid,
  output wire [127:0] pop_data
);
  wire [127:0] buf__1_init[0:1];
  assign buf__1_init[0] = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  assign buf__1_init[1] = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg [1:0] head;
  reg [1:0] tail;
  reg [1:0] slots;
  reg [127:0] buf__1[0:1];
  wire is_full_bool;
  wire can_do_push;
  wire and_2421;
  wire eq_2426;
  wire ne_2410;
  wire and_2427;
  wire or_2424;
  wire [2:0] add_2418;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2413;
  wire popped;
  wire [1:0] sub_2439;
  wire [1:0] add_2441;
  wire [2:0] umod_2419;
  wire [2:0] umod_2414;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2443;
  wire [127:0] array_update_2450[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2421 = pop_ready & push_valid;
  assign eq_2426 = head == tail;
  assign ne_2410 = head != tail;
  assign and_2427 = eq_2426 & and_2421;
  assign or_2424 = ne_2410 | push_valid;
  assign add_2418 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2413 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2424;
  assign sub_2439 = slots - 2'h1;
  assign add_2441 = slots + 2'h1;
  assign umod_2419 = add_2418 % long_buf_size_lit;
  assign umod_2414 = add_2413 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2419[1:0];
  assign did_push_occur = (can_do_push | and_2421) & push_valid & ~and_2427 & ~is_full_bool;
  assign next_tail_if_pop = umod_2414[1:0];
  assign did_pop_occur = (ne_2410 | and_2421) & pop_ready & ~and_2427;
  assign sel_2443 = pushed ? (popped ? slots : add_2441) : (popped ? sub_2439 : slots);
  always @ (posedge clk) begin
    if (reset) begin
      head <= 2'h0;
      tail <= 2'h0;
      slots <= 2'h0;
      buf__1[0] <= buf__1_init[0];
      buf__1[1] <= buf__1_init[1];
    end else begin
      head <= did_push_occur ? next_head_if_push : head;
      tail <= did_pop_occur ? next_tail_if_pop : tail;
      slots <= sel_2443;
      buf__1[0] <= did_push_occur ? array_update_2450[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2450[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2424;
  assign pop_data = eq_2426 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2450_0
    assign array_update_2450[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1(
  input wire clk,
  input wire reset,
  input wire push_valid,
  input wire pop_ready,
  input wire [127:0] push_data,
  output wire push_ready,
  output wire pop_valid,
  output wire [127:0] pop_data
);
  wire [127:0] buf__1_init[0:1];
  assign buf__1_init[0] = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  assign buf__1_init[1] = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg [1:0] head;
  reg [1:0] tail;
  reg [1:0] slots;
  reg [127:0] buf__1[0:1];
  wire is_full_bool;
  wire can_do_push;
  wire and_2478;
  wire eq_2483;
  wire ne_2467;
  wire and_2484;
  wire or_2481;
  wire [2:0] add_2475;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2470;
  wire popped;
  wire [1:0] sub_2496;
  wire [1:0] add_2498;
  wire [2:0] umod_2476;
  wire [2:0] umod_2471;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2500;
  wire [127:0] array_update_2507[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2478 = pop_ready & push_valid;
  assign eq_2483 = head == tail;
  assign ne_2467 = head != tail;
  assign and_2484 = eq_2483 & and_2478;
  assign or_2481 = ne_2467 | push_valid;
  assign add_2475 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2470 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2481;
  assign sub_2496 = slots - 2'h1;
  assign add_2498 = slots + 2'h1;
  assign umod_2476 = add_2475 % long_buf_size_lit;
  assign umod_2471 = add_2470 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2476[1:0];
  assign did_push_occur = (can_do_push | and_2478) & push_valid & ~and_2484 & ~is_full_bool;
  assign next_tail_if_pop = umod_2471[1:0];
  assign did_pop_occur = (ne_2467 | and_2478) & pop_ready & ~and_2484;
  assign sel_2500 = pushed ? (popped ? slots : add_2498) : (popped ? sub_2496 : slots);
  always @ (posedge clk) begin
    if (reset) begin
      head <= 2'h0;
      tail <= 2'h0;
      slots <= 2'h0;
      buf__1[0] <= buf__1_init[0];
      buf__1[1] <= buf__1_init[1];
    end else begin
      head <= did_push_occur ? next_head_if_push : head;
      tail <= did_pop_occur ? next_tail_if_pop : tail;
      slots <= sel_2500;
      buf__1[0] <= did_push_occur ? array_update_2507[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2507[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2481;
  assign pop_data = eq_2483 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2507_0
    assign array_update_2507[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __regsvc__Top_0_next(
  input wire clk,
  input wire reset,
  input wire [32:0] regsvc__ext_recv,
  input wire regsvc__ext_recv_vld,
  input wire regsvc__ext_send_rdy,
  output wire regsvc__ext_recv_rdy,
  output wire [32:0] regsvc__ext_send,
  output wire regsvc__ext_send_vld
);
  wire instantiation_output_2298;
  wire [127:0] instantiation_output_2309;
  wire instantiation_output_2310;
  wire [32:0] instantiation_output_2302;
  wire instantiation_output_2303;
  wire instantiation_output_2330;
  wire instantiation_output_2317;
  wire [127:0] instantiation_output_2322;
  wire instantiation_output_2323;
  wire instantiation_output_2515;
  wire [127:0] instantiation_output_2516;
  wire instantiation_output_2517;
  wire instantiation_output_2522;
  wire [127:0] instantiation_output_2523;
  wire instantiation_output_2524;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_2515),
    .regsvc__ext_recv_rdy(instantiation_output_2298),
    .regsvc__req(instantiation_output_2309),
    .regsvc__req_vld(instantiation_output_2310),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_2523),
    .regsvc__resp_vld(instantiation_output_2524),
    .regsvc__ext_send(instantiation_output_2302),
    .regsvc__ext_send_vld(instantiation_output_2303),
    .regsvc__resp_rdy(instantiation_output_2330),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_2516),
    .regsvc__req_vld(instantiation_output_2517),
    .regsvc__resp_rdy(instantiation_output_2522),
    .regsvc__req_rdy(instantiation_output_2317),
    .regsvc__resp(instantiation_output_2322),
    .regsvc__resp_vld(instantiation_output_2323),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_2309),
    .push_valid(instantiation_output_2310),
    .pop_ready(instantiation_output_2317),
    .push_ready(instantiation_output_2515),
    .pop_data(instantiation_output_2516),
    .pop_valid(instantiation_output_2517),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_2322),
    .push_valid(instantiation_output_2323),
    .pop_ready(instantiation_output_2330),
    .push_ready(instantiation_output_2522),
    .pop_data(instantiation_output_2523),
    .pop_valid(instantiation_output_2524),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_2298;
  assign regsvc__ext_send = instantiation_output_2302;
  assign regsvc__ext_send_vld = instantiation_output_2303;
endmodule
