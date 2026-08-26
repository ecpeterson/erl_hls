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
  wire [2:0] one_hot_2176;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_2598;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_2597;
  wire [31:0] sel_2596;
  wire [31:0] sel_2595;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_2208;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_2624;
  wire [127:0] one_hot_sel_2209;
  wire [7:0] one_hot_sel_2215;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_2176 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_2598 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_2597 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_2596 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_2595 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_2176[1] & beat_tlast == one_hot_2176[0];
  assign concat_2208 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_2597, sel_2596, sel_2595, sel_2598};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_2624 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_2209 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2208[0]}} | payload & {128{concat_2208[1]}};
  assign one_hot_sel_2215 = 8'h00 & {8{concat_2208[0]}} | words_seen & {8{concat_2208[1]}};
  assign __regsvc__req_buf = {{sel_2598[7:0], sel_2598[15:8], sel_2598[23:16], sel_2598[31:24]}, {sel_2597, sel_2596, sel_2595}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_2215 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_2209 : ____state_0;
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
  wire [127:0] literal_2266 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_2278;
  wire not_2279;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire regsvc__ext_send_load_en;
  wire [2:0] one_hot_2288;
  wire [2:0] one_hot_2289;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire regsvc__resp_valid_inv;
  wire and_2328;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_2331;
  wire [127:0] payload;
  wire [1:0] concat_2344;
  wire [7:0] beats_sent;
  wire regsvc__resp_load_en;
  wire or_2628;
  wire or_2632;
  wire [7:0] one_hot_sel_2332;
  wire and_2352;
  wire [127:0] one_hot_sel_2339;
  wire [7:0] one_hot_sel_2345;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_2266;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign nor_2278 = ~(last | ____state_0);
  assign not_2279 = ~last;
  assign __regsvc__ext_send_vld_buf = ____state_0 | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_2278};
  assign ____state_6__next_value_predicates = {not_2279, last};
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign one_hot_2288 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_2289 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign and_2328 = last & p0_stage_done;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | regsvc__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_2288[1] & nor_2278 == one_hot_2288[0];
  assign ____state_6__at_most_one_next_value = not_2279 == one_hot_2289[1] & last == one_hot_2289[0];
  assign concat_2331 = {and_2328, nor_2278 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_2344 = {not_2279 & p0_stage_done, and_2328};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign or_2628 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_2632 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_2332 = frame_header_payload_words__1 & {8{concat_2331[0]}} | 8'h00 & {8{concat_2331[1]}};
  assign and_2352 = (last | nor_2278) & p0_stage_done;
  assign one_hot_sel_2339 = payload & {128{concat_2331[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2331[1]}};
  assign one_hot_sel_2345 = 8'h00 & {8{concat_2344[0]}} | beats_sent & {8{concat_2344[1]}};
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
      ____state_0 <= p0_stage_done ? not_2279 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_2345 : ____state_6;
      ____state_1 <= and_2352 ? one_hot_sel_2332 : ____state_1;
      ____state_5 <= and_2352 ? one_hot_sel_2339 : ____state_5;
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
  wire [31:0] literal_2421[0:15];
  assign literal_2421[0] = 32'h0000_0000;
  assign literal_2421[1] = 32'h0000_0000;
  assign literal_2421[2] = 32'h0000_0000;
  assign literal_2421[3] = 32'h0000_0000;
  assign literal_2421[4] = 32'h0000_0000;
  assign literal_2421[5] = 32'h0000_0000;
  assign literal_2421[6] = 32'h0000_0000;
  assign literal_2421[7] = 32'h0000_0000;
  assign literal_2421[8] = 32'h0000_0000;
  assign literal_2421[9] = 32'h0000_0000;
  assign literal_2421[10] = 32'h0000_0000;
  assign literal_2421[11] = 32'h0000_0000;
  assign literal_2421[12] = 32'h0000_0000;
  assign literal_2421[13] = 32'h0000_0000;
  assign literal_2421[14] = 32'h0000_0000;
  assign literal_2421[15] = 32'h0000_0000;
  reg [31:0] ____state_1[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [31:0] frame_header;
  wire [95:0] frame_payload__2;
  wire [7:0] frame_header_op;
  wire eq_2463;
  wire eq_2441;
  wire eq_2464;
  wire static_match_1_2;
  wire [2:0] concat_2471;
  wire resp2_header_op_squeezed__3_to_4;
  wire resp2_header_op_squeezed__0_to_1;
  wire or_2506;
  wire regsvc__resp_valid_inv;
  wire [3:0] resp2_header_op_squeezed_const_msb_bits;
  wire eq_2469;
  wire nor_2470;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [31:0] register_1;
  wire [26:0] sub_2460;
  wire [1:0] ____state_1__next_value_predicates;
  wire regsvc__resp_not_pred;
  wire regsvc__resp_load_en;
  wire [31:0] value_1__1;
  wire [511:0] _2__2;
  wire [2:0] one_hot_2488;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [511:0] _3__2;
  wire [511:0] shll_2476;
  wire p0_stage_done;
  wire [31:0] _4__2;
  wire [31:0] _5__2;
  wire [1:0] resp2_header_op_squeezed__1_to_3;
  wire [3:0] one_hot_2599;
  wire regsvc__req_valid_inv;
  wire [31:0] newvalue_1;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire [95:0] _4__3;
  wire regsvc__req_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_2522;
  wire [31:0] newregisters_1[0:15];
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire or_2634;
  wire [31:0] one_hot_sel_2523[0:15];
  wire and_2529;
  wire [127:0] resp2;
  wire or_2636;
  assign frame_header = __regsvc__req_reg[127:96];
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign frame_header_op = frame_header[7:0];
  assign eq_2463 = frame_header_op == 8'h06;
  assign eq_2441 = frame_header_op == 8'h04;
  assign eq_2464 = frame_header_op == 8'h05;
  assign static_match_1_2 = frame_payload__2[31:4] == 28'h000_0000;
  assign concat_2471 = {eq_2463, eq_2441, eq_2464};
  assign resp2_header_op_squeezed__3_to_4 = 1'h0 & concat_2471[0] | static_match_1_2 & concat_2471[1] | 1'h1 & concat_2471[2];
  assign resp2_header_op_squeezed__0_to_1 = 1'h1 & concat_2471[0] | ~static_match_1_2 & concat_2471[1] | 1'h1 & concat_2471[2];
  assign or_2506 = resp2_header_op_squeezed__3_to_4 | resp2_header_op_squeezed__0_to_1;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign resp2_header_op_squeezed_const_msb_bits = 4'h0;
  assign eq_2469 = frame_header_op == 8'h03;
  assign nor_2470 = ~(~eq_2441 | static_match_1_2);
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & or_2506;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign register_1 = frame_payload__2[31:0];
  assign sub_2460 = 27'h000_0010 - frame_payload__2[58:32];
  assign ____state_1__next_value_predicates = {eq_2469, nor_2470};
  assign regsvc__resp_not_pred = ~or_2506;
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign value_1__1 = ____state_1[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign _2__2 = {____state_1[resp2_header_op_squeezed_const_msb_bits], ____state_1[4'h1], ____state_1[4'h2], ____state_1[4'h3], ____state_1[4'h4], ____state_1[4'h5], ____state_1[4'h6], ____state_1[4'h7], ____state_1[4'h8], ____state_1[4'h9], ____state_1[4'ha], ____state_1[4'hb], ____state_1[4'hc], ____state_1[4'hd], ____state_1[4'he], ____state_1[4'hf]};
  assign one_hot_2488 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign _3__2 = {frame_payload__2[26:0], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : _2__2 << {frame_payload__2[26:0], 5'h00};
  assign shll_2476 = {sub_2460, 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {sub_2460, 5'h00};
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign _4__2 = ~(~value_1__1 | mask_1);
  assign _5__2 = value_1__2 & mask_1;
  assign resp2_header_op_squeezed__1_to_3 = {2{eq_2464}};
  assign one_hot_2599 = {concat_2471[2:0] == 3'h0, concat_2471[2] && concat_2471[1:0] == 2'h0, concat_2471[1] && !concat_2471[0], concat_2471[0]};
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign newvalue_1 = _4__2 | _5__2;
  assign txid = frame_header[23:16];
  assign resp2_header_op = {resp2_header_op_squeezed_const_msb_bits, resp2_header_op_squeezed__3_to_4, resp2_header_op_squeezed__1_to_3, resp2_header_op_squeezed__0_to_1};
  assign _4__3 = _3__2[511:416] & shll_2476[511:416];
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign ____state_1__at_most_one_next_value = eq_2469 == one_hot_2488[1] & nor_2470 == one_hot_2488[0];
  assign concat_2522 = {eq_2469 & p0_stage_done, nor_2470 & p0_stage_done};
  assign resp2_header = {{6'h00, eq_2463, 1'h1 & concat_2471[0] | static_match_1_2 & concat_2471[1] | 1'h1 & concat_2471[2]}, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign or_2634 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign one_hot_sel_2523[0] = literal_2421[0] & {32{concat_2522[0]}} | newregisters_1[0] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[1] = literal_2421[1] & {32{concat_2522[0]}} | newregisters_1[1] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[2] = literal_2421[2] & {32{concat_2522[0]}} | newregisters_1[2] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[3] = literal_2421[3] & {32{concat_2522[0]}} | newregisters_1[3] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[4] = literal_2421[4] & {32{concat_2522[0]}} | newregisters_1[4] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[5] = literal_2421[5] & {32{concat_2522[0]}} | newregisters_1[5] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[6] = literal_2421[6] & {32{concat_2522[0]}} | newregisters_1[6] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[7] = literal_2421[7] & {32{concat_2522[0]}} | newregisters_1[7] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[8] = literal_2421[8] & {32{concat_2522[0]}} | newregisters_1[8] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[9] = literal_2421[9] & {32{concat_2522[0]}} | newregisters_1[9] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[10] = literal_2421[10] & {32{concat_2522[0]}} | newregisters_1[10] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[11] = literal_2421[11] & {32{concat_2522[0]}} | newregisters_1[11] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[12] = literal_2421[12] & {32{concat_2522[0]}} | newregisters_1[12] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[13] = literal_2421[13] & {32{concat_2522[0]}} | newregisters_1[13] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[14] = literal_2421[14] & {32{concat_2522[0]}} | newregisters_1[14] & {32{concat_2522[1]}};
  assign one_hot_sel_2523[15] = literal_2421[15] & {32{concat_2522[0]}} | newregisters_1[15] & {32{concat_2522[1]}};
  assign and_2529 = (eq_2469 | nor_2470) & p0_stage_done;
  assign resp2 = {resp2_header, {64'h0000_0000_0000_0000, register_1} & {96{concat_2471[0]}} | {64'h0000_0000_0000_0000, {32{static_match_1_2}} & value_1__1} & {96{concat_2471[1]}} | _4__3 & {96{concat_2471[2]}}};
  assign or_2636 = ~p0_stage_done | concat_2471 == one_hot_2599[2:0] | reset;
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
      ____state_1[0] <= and_2529 ? one_hot_sel_2523[0] : ____state_1[0];
      ____state_1[1] <= and_2529 ? one_hot_sel_2523[1] : ____state_1[1];
      ____state_1[2] <= and_2529 ? one_hot_sel_2523[2] : ____state_1[2];
      ____state_1[3] <= and_2529 ? one_hot_sel_2523[3] : ____state_1[3];
      ____state_1[4] <= and_2529 ? one_hot_sel_2523[4] : ____state_1[4];
      ____state_1[5] <= and_2529 ? one_hot_sel_2523[5] : ____state_1[5];
      ____state_1[6] <= and_2529 ? one_hot_sel_2523[6] : ____state_1[6];
      ____state_1[7] <= and_2529 ? one_hot_sel_2523[7] : ____state_1[7];
      ____state_1[8] <= and_2529 ? one_hot_sel_2523[8] : ____state_1[8];
      ____state_1[9] <= and_2529 ? one_hot_sel_2523[9] : ____state_1[9];
      ____state_1[10] <= and_2529 ? one_hot_sel_2523[10] : ____state_1[10];
      ____state_1[11] <= and_2529 ? one_hot_sel_2523[11] : ____state_1[11];
      ____state_1[12] <= and_2529 ? one_hot_sel_2523[12] : ____state_1[12];
      ____state_1[13] <= and_2529 ? one_hot_sel_2523[13] : ____state_1[13];
      ____state_1[14] <= and_2529 ? one_hot_sel_2523[14] : ____state_1[14];
      ____state_1[15] <= and_2529 ? one_hot_sel_2523[15] : ____state_1[15];
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
  wire and_2682;
  wire eq_2687;
  wire ne_2671;
  wire and_2688;
  wire or_2685;
  wire [2:0] add_2679;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2674;
  wire popped;
  wire [1:0] sub_2700;
  wire [1:0] add_2702;
  wire [2:0] umod_2680;
  wire [2:0] umod_2675;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2704;
  wire [127:0] array_update_2711[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2682 = pop_ready & push_valid;
  assign eq_2687 = head == tail;
  assign ne_2671 = head != tail;
  assign and_2688 = eq_2687 & and_2682;
  assign or_2685 = ne_2671 | push_valid;
  assign add_2679 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2674 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2685;
  assign sub_2700 = slots - 2'h1;
  assign add_2702 = slots + 2'h1;
  assign umod_2680 = add_2679 % long_buf_size_lit;
  assign umod_2675 = add_2674 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2680[1:0];
  assign did_push_occur = (can_do_push | and_2682) & push_valid & ~and_2688 & ~is_full_bool;
  assign next_tail_if_pop = umod_2675[1:0];
  assign did_pop_occur = (ne_2671 | and_2682) & pop_ready & ~and_2688;
  assign sel_2704 = pushed ? (popped ? slots : add_2702) : (popped ? sub_2700 : slots);
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
      slots <= sel_2704;
      buf__1[0] <= did_push_occur ? array_update_2711[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2711[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2685;
  assign pop_data = eq_2687 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2711_0
    assign array_update_2711[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_2739;
  wire eq_2744;
  wire ne_2728;
  wire and_2745;
  wire or_2742;
  wire [2:0] add_2736;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2731;
  wire popped;
  wire [1:0] sub_2757;
  wire [1:0] add_2759;
  wire [2:0] umod_2737;
  wire [2:0] umod_2732;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2761;
  wire [127:0] array_update_2768[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2739 = pop_ready & push_valid;
  assign eq_2744 = head == tail;
  assign ne_2728 = head != tail;
  assign and_2745 = eq_2744 & and_2739;
  assign or_2742 = ne_2728 | push_valid;
  assign add_2736 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2731 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2742;
  assign sub_2757 = slots - 2'h1;
  assign add_2759 = slots + 2'h1;
  assign umod_2737 = add_2736 % long_buf_size_lit;
  assign umod_2732 = add_2731 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2737[1:0];
  assign did_push_occur = (can_do_push | and_2739) & push_valid & ~and_2745 & ~is_full_bool;
  assign next_tail_if_pop = umod_2732[1:0];
  assign did_pop_occur = (ne_2728 | and_2739) & pop_ready & ~and_2745;
  assign sel_2761 = pushed ? (popped ? slots : add_2759) : (popped ? sub_2757 : slots);
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
      slots <= sel_2761;
      buf__1[0] <= did_push_occur ? array_update_2768[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2768[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2742;
  assign pop_data = eq_2744 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2768_0
    assign array_update_2768[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_2559;
  wire [127:0] instantiation_output_2570;
  wire instantiation_output_2571;
  wire [32:0] instantiation_output_2563;
  wire instantiation_output_2564;
  wire instantiation_output_2591;
  wire instantiation_output_2578;
  wire [127:0] instantiation_output_2583;
  wire instantiation_output_2584;
  wire instantiation_output_2776;
  wire [127:0] instantiation_output_2777;
  wire instantiation_output_2778;
  wire instantiation_output_2783;
  wire [127:0] instantiation_output_2784;
  wire instantiation_output_2785;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_2776),
    .regsvc__ext_recv_rdy(instantiation_output_2559),
    .regsvc__req(instantiation_output_2570),
    .regsvc__req_vld(instantiation_output_2571),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_2784),
    .regsvc__resp_vld(instantiation_output_2785),
    .regsvc__ext_send(instantiation_output_2563),
    .regsvc__ext_send_vld(instantiation_output_2564),
    .regsvc__resp_rdy(instantiation_output_2591),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_2777),
    .regsvc__req_vld(instantiation_output_2778),
    .regsvc__resp_rdy(instantiation_output_2783),
    .regsvc__req_rdy(instantiation_output_2578),
    .regsvc__resp(instantiation_output_2583),
    .regsvc__resp_vld(instantiation_output_2584),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_2570),
    .push_valid(instantiation_output_2571),
    .pop_ready(instantiation_output_2578),
    .push_ready(instantiation_output_2776),
    .pop_data(instantiation_output_2777),
    .pop_valid(instantiation_output_2778),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_2583),
    .push_valid(instantiation_output_2584),
    .pop_ready(instantiation_output_2591),
    .push_ready(instantiation_output_2783),
    .pop_data(instantiation_output_2784),
    .pop_valid(instantiation_output_2785),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_2559;
  assign regsvc__ext_send = instantiation_output_2563;
  assign regsvc__ext_send_vld = instantiation_output_2564;
endmodule
