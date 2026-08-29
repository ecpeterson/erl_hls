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
  wire [2:0] one_hot_1870;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_2297;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_2296;
  wire [31:0] sel_2295;
  wire [31:0] sel_2294;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_1902;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_2305;
  wire [127:0] one_hot_sel_1903;
  wire [7:0] one_hot_sel_1909;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_1870 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_2297 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_2296 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_2295 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_2294 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_1870[1] & beat_tlast == one_hot_1870[0];
  assign concat_1902 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_2296, sel_2295, sel_2294, sel_2297};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_2305 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_1903 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_1902[0]}} | payload & {128{concat_1902[1]}};
  assign one_hot_sel_1909 = 8'h00 & {8{concat_1902[0]}} | words_seen & {8{concat_1902[1]}};
  assign __regsvc__req_buf = {{sel_2297[7:0], sel_2297[15:8], sel_2297[23:16], sel_2297[31:24]}, {sel_2296, sel_2295, sel_2294}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_1909 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_1903 : ____state_0;
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
  wire [127:0] literal_1960 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_1972;
  wire not_1973;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire regsvc__ext_send_load_en;
  wire [2:0] one_hot_1982;
  wire [2:0] one_hot_1983;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire regsvc__resp_valid_inv;
  wire and_2022;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_2025;
  wire [127:0] payload;
  wire [1:0] concat_2038;
  wire [7:0] beats_sent;
  wire regsvc__resp_load_en;
  wire or_2309;
  wire or_2313;
  wire [7:0] one_hot_sel_2026;
  wire and_2046;
  wire [127:0] one_hot_sel_2033;
  wire [7:0] one_hot_sel_2039;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_1960;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign nor_1972 = ~(last | ____state_0);
  assign not_1973 = ~last;
  assign __regsvc__ext_send_vld_buf = ____state_0 | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_1972};
  assign ____state_6__next_value_predicates = {not_1973, last};
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign one_hot_1982 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_1983 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign and_2022 = last & p0_stage_done;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | regsvc__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_1982[1] & nor_1972 == one_hot_1982[0];
  assign ____state_6__at_most_one_next_value = not_1973 == one_hot_1983[1] & last == one_hot_1983[0];
  assign concat_2025 = {and_2022, nor_1972 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_2038 = {not_1973 & p0_stage_done, and_2022};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign or_2309 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_2313 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_2026 = frame_header_payload_words__1 & {8{concat_2025[0]}} | 8'h00 & {8{concat_2025[1]}};
  assign and_2046 = (last | nor_1972) & p0_stage_done;
  assign one_hot_sel_2033 = payload & {128{concat_2025[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2025[1]}};
  assign one_hot_sel_2039 = 8'h00 & {8{concat_2038[0]}} | beats_sent & {8{concat_2038[1]}};
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
      ____state_0 <= p0_stage_done ? not_1973 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_2039 : ____state_6;
      ____state_1 <= and_2046 ? one_hot_sel_2026 : ____state_1;
      ____state_5 <= and_2046 ? one_hot_sel_2033 : ____state_5;
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
  function automatic [95:0] priority_sel_96b_3way (input reg [2:0] sel, input reg [95:0] case0, input reg [95:0] case1, input reg [95:0] case2, input reg [95:0] default_value);
    begin
      casez (sel)
        3'b??1: begin
          priority_sel_96b_3way = case0;
        end
        3'b?10: begin
          priority_sel_96b_3way = case1;
        end
        3'b100: begin
          priority_sel_96b_3way = case2;
        end
        3'b000: begin
          priority_sel_96b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_96b_3way = 96'dx;
        end
      endcase
    end
  endfunction
  wire [31:0] ____state_init[0:15];
  assign ____state_init[0] = 32'h0000_0000;
  assign ____state_init[1] = 32'h0000_0000;
  assign ____state_init[2] = 32'h0000_0000;
  assign ____state_init[3] = 32'h0000_0000;
  assign ____state_init[4] = 32'h0000_0000;
  assign ____state_init[5] = 32'h0000_0000;
  assign ____state_init[6] = 32'h0000_0000;
  assign ____state_init[7] = 32'h0000_0000;
  assign ____state_init[8] = 32'h0000_0000;
  assign ____state_init[9] = 32'h0000_0000;
  assign ____state_init[10] = 32'h0000_0000;
  assign ____state_init[11] = 32'h0000_0000;
  assign ____state_init[12] = 32'h0000_0000;
  assign ____state_init[13] = 32'h0000_0000;
  assign ____state_init[14] = 32'h0000_0000;
  assign ____state_init[15] = 32'h0000_0000;
  wire [127:0] __regsvc__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __regsvc__resp_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [31:0] literal_2116[0:15];
  assign literal_2116[0] = 32'h0000_0000;
  assign literal_2116[1] = 32'h0000_0000;
  assign literal_2116[2] = 32'h0000_0000;
  assign literal_2116[3] = 32'h0000_0000;
  assign literal_2116[4] = 32'h0000_0000;
  assign literal_2116[5] = 32'h0000_0000;
  assign literal_2116[6] = 32'h0000_0000;
  assign literal_2116[7] = 32'h0000_0000;
  assign literal_2116[8] = 32'h0000_0000;
  assign literal_2116[9] = 32'h0000_0000;
  assign literal_2116[10] = 32'h0000_0000;
  assign literal_2116[11] = 32'h0000_0000;
  assign literal_2116[12] = 32'h0000_0000;
  assign literal_2116[13] = 32'h0000_0000;
  assign literal_2116[14] = 32'h0000_0000;
  assign literal_2116[15] = 32'h0000_0000;
  reg [31:0] ____state[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [95:0] frame_payload__2;
  wire regsvc__resp_not_pred;
  wire eq_2138;
  wire eq_2139;
  wire resp2_header_op_squeezed__0_to_3_squeezed__1_to_2;
  wire static_match_1_2;
  wire regsvc__resp_valid_inv;
  wire [3:0] resp2_header_op_squeezed_const_msb_bits;
  wire and_2169;
  wire nor_2170;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [31:0] register_1;
  wire [26:0] sub_2159;
  wire [2:0] ____state__next_value_predicates;
  wire regsvc__resp_load_en;
  wire [31:0] value_1__1;
  wire resp2_header_op_squeezed__0_to_3_squeezed__0_to_1;
  wire [511:0] _2__2;
  wire [3:0] one_hot_2185;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [2:0] concat_2171;
  wire [1:0] resp2_header_op_squeezed__0_to_3_squeezed;
  wire [511:0] _3__2;
  wire [511:0] shll_2175;
  wire p0_stage_done;
  wire [31:0] _4__2;
  wire [31:0] _5__2;
  wire resp2_header_op_squeezed__3_to_4;
  wire [2:0] resp2_header_op_squeezed__0_to_3;
  wire [3:0] one_hot_2298;
  wire regsvc__req_valid_inv;
  wire [31:0] newvalue_1;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire [95:0] _4__3;
  wire regsvc__req_valid_load_en;
  wire ____state__at_most_one_next_value;
  wire [2:0] concat_2221;
  wire [31:0] newregisters_1[0:15];
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire or_2315;
  wire [31:0] one_hot_sel_2222[0:15];
  wire and_2228;
  wire [127:0] resp2;
  wire or_2317;
  assign frame_header = __regsvc__req_reg[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign regsvc__resp_not_pred = frame_header_op == 8'h03;
  assign eq_2138 = frame_header_op == 8'h06;
  assign eq_2139 = frame_header_op == 8'h04;
  assign resp2_header_op_squeezed__0_to_3_squeezed__1_to_2 = frame_header_op == 8'h05;
  assign static_match_1_2 = frame_payload__2[31:4] == 28'h000_0000;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign resp2_header_op_squeezed_const_msb_bits = 4'h0;
  assign and_2169 = ~regsvc__resp_not_pred & ~eq_2138 & ~eq_2139 & ~resp2_header_op_squeezed__0_to_3_squeezed__1_to_2;
  assign nor_2170 = ~(~eq_2139 | static_match_1_2);
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & ~regsvc__resp_not_pred;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign register_1 = frame_payload__2[31:0];
  assign sub_2159 = 27'h000_0010 - frame_payload__2[58:32];
  assign ____state__next_value_predicates = {regsvc__resp_not_pred, and_2169, nor_2170};
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign value_1__1 = ____state[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign resp2_header_op_squeezed__0_to_3_squeezed__0_to_1 = ~(eq_2139 & static_match_1_2);
  assign _2__2 = {____state[resp2_header_op_squeezed_const_msb_bits], ____state[4'h1], ____state[4'h2], ____state[4'h3], ____state[4'h4], ____state[4'h5], ____state[4'h6], ____state[4'h7], ____state[4'h8], ____state[4'h9], ____state[4'ha], ____state[4'hb], ____state[4'hc], ____state[4'hd], ____state[4'he], ____state[4'hf]};
  assign one_hot_2185 = {____state__next_value_predicates[2:0] == 3'h0, ____state__next_value_predicates[2] && ____state__next_value_predicates[1:0] == 2'h0, ____state__next_value_predicates[1] && !____state__next_value_predicates[0], ____state__next_value_predicates[0]};
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign concat_2171 = {eq_2138, eq_2139, resp2_header_op_squeezed__0_to_3_squeezed__1_to_2};
  assign resp2_header_op_squeezed__0_to_3_squeezed = {resp2_header_op_squeezed__0_to_3_squeezed__1_to_2, resp2_header_op_squeezed__0_to_3_squeezed__0_to_1};
  assign _3__2 = {frame_payload__2[26:0], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : _2__2 << {frame_payload__2[26:0], 5'h00};
  assign shll_2175 = {sub_2159, 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {sub_2159, 5'h00};
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign _4__2 = ~(~value_1__1 | mask_1);
  assign _5__2 = value_1__2 & mask_1;
  assign resp2_header_op_squeezed__3_to_4 = 1'h0 & concat_2171[0] | static_match_1_2 & concat_2171[1] | 1'h1 & concat_2171[2];
  assign resp2_header_op_squeezed__0_to_3 = {{1{resp2_header_op_squeezed__0_to_3_squeezed[1]}}, resp2_header_op_squeezed__0_to_3_squeezed};
  assign one_hot_2298 = {concat_2171[2:0] == 3'h0, concat_2171[2] && concat_2171[1:0] == 2'h0, concat_2171[1] && !concat_2171[0], concat_2171[0]};
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign newvalue_1 = _4__2 | _5__2;
  assign txid = frame_header[23:16];
  assign resp2_header_op = {resp2_header_op_squeezed_const_msb_bits, resp2_header_op_squeezed__3_to_4, resp2_header_op_squeezed__0_to_3};
  assign _4__3 = _3__2[511:416] & shll_2175[511:416];
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign ____state__at_most_one_next_value = regsvc__resp_not_pred == one_hot_2185[2] & and_2169 == one_hot_2185[1] & nor_2170 == one_hot_2185[0];
  assign concat_2221 = {regsvc__resp_not_pred & p0_stage_done, and_2169 & p0_stage_done, nor_2170 & p0_stage_done};
  assign resp2_header = {{6'h00, eq_2138, 1'h1}, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign or_2315 = ~p0_stage_done | ____state__at_most_one_next_value | reset;
  assign one_hot_sel_2222[0] = literal_2116[0] & {32{concat_2221[0]}} | literal_2116[0] & {32{concat_2221[1]}} | newregisters_1[0] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[1] = literal_2116[1] & {32{concat_2221[0]}} | literal_2116[1] & {32{concat_2221[1]}} | newregisters_1[1] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[2] = literal_2116[2] & {32{concat_2221[0]}} | literal_2116[2] & {32{concat_2221[1]}} | newregisters_1[2] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[3] = literal_2116[3] & {32{concat_2221[0]}} | literal_2116[3] & {32{concat_2221[1]}} | newregisters_1[3] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[4] = literal_2116[4] & {32{concat_2221[0]}} | literal_2116[4] & {32{concat_2221[1]}} | newregisters_1[4] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[5] = literal_2116[5] & {32{concat_2221[0]}} | literal_2116[5] & {32{concat_2221[1]}} | newregisters_1[5] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[6] = literal_2116[6] & {32{concat_2221[0]}} | literal_2116[6] & {32{concat_2221[1]}} | newregisters_1[6] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[7] = literal_2116[7] & {32{concat_2221[0]}} | literal_2116[7] & {32{concat_2221[1]}} | newregisters_1[7] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[8] = literal_2116[8] & {32{concat_2221[0]}} | literal_2116[8] & {32{concat_2221[1]}} | newregisters_1[8] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[9] = literal_2116[9] & {32{concat_2221[0]}} | literal_2116[9] & {32{concat_2221[1]}} | newregisters_1[9] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[10] = literal_2116[10] & {32{concat_2221[0]}} | literal_2116[10] & {32{concat_2221[1]}} | newregisters_1[10] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[11] = literal_2116[11] & {32{concat_2221[0]}} | literal_2116[11] & {32{concat_2221[1]}} | newregisters_1[11] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[12] = literal_2116[12] & {32{concat_2221[0]}} | literal_2116[12] & {32{concat_2221[1]}} | newregisters_1[12] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[13] = literal_2116[13] & {32{concat_2221[0]}} | literal_2116[13] & {32{concat_2221[1]}} | newregisters_1[13] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[14] = literal_2116[14] & {32{concat_2221[0]}} | literal_2116[14] & {32{concat_2221[1]}} | newregisters_1[14] & {32{concat_2221[2]}};
  assign one_hot_sel_2222[15] = literal_2116[15] & {32{concat_2221[0]}} | literal_2116[15] & {32{concat_2221[1]}} | newregisters_1[15] & {32{concat_2221[2]}};
  assign and_2228 = (regsvc__resp_not_pred | and_2169 | nor_2170) & p0_stage_done;
  assign resp2 = {resp2_header, priority_sel_96b_3way(concat_2171, {64'h0000_0000_0000_0000, register_1}, {64'h0000_0000_0000_0000, static_match_1_2 ? value_1__1 : 32'h0000_0002}, _4__3, 96'h0000_0000_0000_0000_0000_0001)};
  assign or_2317 = ~p0_stage_done | concat_2171 == one_hot_2298[2:0] | reset;
  always @ (posedge clk) begin
    if (reset) begin
      ____state[0] <= ____state_init[0];
      ____state[1] <= ____state_init[1];
      ____state[2] <= ____state_init[2];
      ____state[3] <= ____state_init[3];
      ____state[4] <= ____state_init[4];
      ____state[5] <= ____state_init[5];
      ____state[6] <= ____state_init[6];
      ____state[7] <= ____state_init[7];
      ____state[8] <= ____state_init[8];
      ____state[9] <= ____state_init[9];
      ____state[10] <= ____state_init[10];
      ____state[11] <= ____state_init[11];
      ____state[12] <= ____state_init[12];
      ____state[13] <= ____state_init[13];
      ____state[14] <= ____state_init[14];
      ____state[15] <= ____state_init[15];
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
      __regsvc__resp_reg <= __regsvc__resp_reg_init;
      __regsvc__resp_valid_reg <= 1'h0;
    end else begin
      ____state[0] <= and_2228 ? one_hot_sel_2222[0] : ____state[0];
      ____state[1] <= and_2228 ? one_hot_sel_2222[1] : ____state[1];
      ____state[2] <= and_2228 ? one_hot_sel_2222[2] : ____state[2];
      ____state[3] <= and_2228 ? one_hot_sel_2222[3] : ____state[3];
      ____state[4] <= and_2228 ? one_hot_sel_2222[4] : ____state[4];
      ____state[5] <= and_2228 ? one_hot_sel_2222[5] : ____state[5];
      ____state[6] <= and_2228 ? one_hot_sel_2222[6] : ____state[6];
      ____state[7] <= and_2228 ? one_hot_sel_2222[7] : ____state[7];
      ____state[8] <= and_2228 ? one_hot_sel_2222[8] : ____state[8];
      ____state[9] <= and_2228 ? one_hot_sel_2222[9] : ____state[9];
      ____state[10] <= and_2228 ? one_hot_sel_2222[10] : ____state[10];
      ____state[11] <= and_2228 ? one_hot_sel_2222[11] : ____state[11];
      ____state[12] <= and_2228 ? one_hot_sel_2222[12] : ____state[12];
      ____state[13] <= and_2228 ? one_hot_sel_2222[13] : ____state[13];
      ____state[14] <= and_2228 ? one_hot_sel_2222[14] : ____state[14];
      ____state[15] <= and_2228 ? one_hot_sel_2222[15] : ____state[15];
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
    assign newregisters_1[__i0] = register_1 == __i0 ? newvalue_1 : ____state[__i0];
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
  wire and_2357;
  wire eq_2362;
  wire ne_2346;
  wire and_2363;
  wire or_2360;
  wire [2:0] add_2354;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2349;
  wire popped;
  wire [1:0] sub_2375;
  wire [1:0] add_2377;
  wire [2:0] umod_2355;
  wire [2:0] umod_2350;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2379;
  wire [127:0] array_update_2386[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2357 = pop_ready & push_valid;
  assign eq_2362 = head == tail;
  assign ne_2346 = head != tail;
  assign and_2363 = eq_2362 & and_2357;
  assign or_2360 = ne_2346 | push_valid;
  assign add_2354 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2349 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2360;
  assign sub_2375 = slots - 2'h1;
  assign add_2377 = slots + 2'h1;
  assign umod_2355 = add_2354 % long_buf_size_lit;
  assign umod_2350 = add_2349 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2355[1:0];
  assign did_push_occur = (can_do_push | and_2357) & push_valid & ~and_2363 & ~is_full_bool;
  assign next_tail_if_pop = umod_2350[1:0];
  assign did_pop_occur = (ne_2346 | and_2357) & pop_ready & ~and_2363;
  assign sel_2379 = pushed ? (popped ? slots : add_2377) : (popped ? sub_2375 : slots);
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
      slots <= sel_2379;
      buf__1[0] <= did_push_occur ? array_update_2386[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2386[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2360;
  assign pop_data = eq_2362 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2386_0
    assign array_update_2386[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_2414;
  wire eq_2419;
  wire ne_2403;
  wire and_2420;
  wire or_2417;
  wire [2:0] add_2411;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2406;
  wire popped;
  wire [1:0] sub_2432;
  wire [1:0] add_2434;
  wire [2:0] umod_2412;
  wire [2:0] umod_2407;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2436;
  wire [127:0] array_update_2443[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2414 = pop_ready & push_valid;
  assign eq_2419 = head == tail;
  assign ne_2403 = head != tail;
  assign and_2420 = eq_2419 & and_2414;
  assign or_2417 = ne_2403 | push_valid;
  assign add_2411 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2406 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2417;
  assign sub_2432 = slots - 2'h1;
  assign add_2434 = slots + 2'h1;
  assign umod_2412 = add_2411 % long_buf_size_lit;
  assign umod_2407 = add_2406 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2412[1:0];
  assign did_push_occur = (can_do_push | and_2414) & push_valid & ~and_2420 & ~is_full_bool;
  assign next_tail_if_pop = umod_2407[1:0];
  assign did_pop_occur = (ne_2403 | and_2414) & pop_ready & ~and_2420;
  assign sel_2436 = pushed ? (popped ? slots : add_2434) : (popped ? sub_2432 : slots);
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
      slots <= sel_2436;
      buf__1[0] <= did_push_occur ? array_update_2443[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2443[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2417;
  assign pop_data = eq_2419 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2443_0
    assign array_update_2443[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_2258;
  wire [127:0] instantiation_output_2269;
  wire instantiation_output_2270;
  wire [32:0] instantiation_output_2262;
  wire instantiation_output_2263;
  wire instantiation_output_2290;
  wire instantiation_output_2277;
  wire [127:0] instantiation_output_2282;
  wire instantiation_output_2283;
  wire instantiation_output_2451;
  wire [127:0] instantiation_output_2452;
  wire instantiation_output_2453;
  wire instantiation_output_2458;
  wire [127:0] instantiation_output_2459;
  wire instantiation_output_2460;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_2451),
    .regsvc__ext_recv_rdy(instantiation_output_2258),
    .regsvc__req(instantiation_output_2269),
    .regsvc__req_vld(instantiation_output_2270),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_2459),
    .regsvc__resp_vld(instantiation_output_2460),
    .regsvc__ext_send(instantiation_output_2262),
    .regsvc__ext_send_vld(instantiation_output_2263),
    .regsvc__resp_rdy(instantiation_output_2290),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_2452),
    .regsvc__req_vld(instantiation_output_2453),
    .regsvc__resp_rdy(instantiation_output_2458),
    .regsvc__req_rdy(instantiation_output_2277),
    .regsvc__resp(instantiation_output_2282),
    .regsvc__resp_vld(instantiation_output_2283),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_2269),
    .push_valid(instantiation_output_2270),
    .pop_ready(instantiation_output_2277),
    .push_ready(instantiation_output_2451),
    .pop_data(instantiation_output_2452),
    .pop_valid(instantiation_output_2453),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_2282),
    .push_valid(instantiation_output_2283),
    .pop_ready(instantiation_output_2290),
    .push_ready(instantiation_output_2458),
    .pop_data(instantiation_output_2459),
    .pop_valid(instantiation_output_2460),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_2258;
  assign regsvc__ext_send = instantiation_output_2262;
  assign regsvc__ext_send_vld = instantiation_output_2263;
endmodule
