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
  wire [2:0] one_hot_2136;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_2629;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_2628;
  wire [31:0] sel_2627;
  wire [31:0] sel_2626;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_2168;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_2655;
  wire [127:0] one_hot_sel_2169;
  wire [7:0] one_hot_sel_2175;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_2136 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_2629 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_2628 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_2627 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_2626 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_2136[1] & beat_tlast == one_hot_2136[0];
  assign concat_2168 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_2628, sel_2627, sel_2626, sel_2629};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_2655 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_2169 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2168[0]}} | payload & {128{concat_2168[1]}};
  assign one_hot_sel_2175 = 8'h00 & {8{concat_2168[0]}} | words_seen & {8{concat_2168[1]}};
  assign __regsvc__req_buf = {{sel_2629[7:0], sel_2629[15:8], sel_2629[23:16], sel_2629[31:24]}, {sel_2628, sel_2627, sel_2626}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_2175 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_2169 : ____state_0;
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
  wire [127:0] literal_2226 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_2238;
  wire not_2239;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire regsvc__ext_send_load_en;
  wire [2:0] one_hot_2248;
  wire [2:0] one_hot_2249;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire regsvc__resp_valid_inv;
  wire and_2288;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_2291;
  wire [127:0] payload;
  wire [1:0] concat_2304;
  wire [7:0] beats_sent;
  wire regsvc__resp_load_en;
  wire or_2659;
  wire or_2663;
  wire [7:0] one_hot_sel_2292;
  wire and_2312;
  wire [127:0] one_hot_sel_2299;
  wire [7:0] one_hot_sel_2305;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_2226;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign nor_2238 = ~(last | ____state_0);
  assign not_2239 = ~last;
  assign __regsvc__ext_send_vld_buf = ____state_0 | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_2238};
  assign ____state_6__next_value_predicates = {not_2239, last};
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign one_hot_2248 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_2249 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign and_2288 = last & p0_stage_done;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | regsvc__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_2248[1] & nor_2238 == one_hot_2248[0];
  assign ____state_6__at_most_one_next_value = not_2239 == one_hot_2249[1] & last == one_hot_2249[0];
  assign concat_2291 = {and_2288, nor_2238 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_2304 = {not_2239 & p0_stage_done, and_2288};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign or_2659 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_2663 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_2292 = frame_header_payload_words__1 & {8{concat_2291[0]}} | 8'h00 & {8{concat_2291[1]}};
  assign and_2312 = (last | nor_2238) & p0_stage_done;
  assign one_hot_sel_2299 = payload & {128{concat_2291[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2291[1]}};
  assign one_hot_sel_2305 = 8'h00 & {8{concat_2304[0]}} | beats_sent & {8{concat_2304[1]}};
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
      ____state_0 <= p0_stage_done ? not_2239 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_2305 : ____state_6;
      ____state_1 <= and_2312 ? one_hot_sel_2292 : ____state_1;
      ____state_5 <= and_2312 ? one_hot_sel_2299 : ____state_5;
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
  input wire regsvc__ext_state_rdy,
  input wire [127:0] regsvc__req,
  input wire regsvc__req_vld,
  input wire regsvc__resp_rdy,
  output wire [511:0] regsvc__ext_state,
  output wire regsvc__ext_state_vld,
  output wire regsvc__req_rdy,
  output wire [127:0] regsvc__resp,
  output wire regsvc__resp_vld
);
  function automatic [511:0] priority_sel_512b_4way (input reg [3:0] sel, input reg [511:0] case0, input reg [511:0] case1, input reg [511:0] case2, input reg [511:0] case3, input reg [511:0] default_value);
    begin
      casez (sel)
        4'b???1: begin
          priority_sel_512b_4way = case0;
        end
        4'b??10: begin
          priority_sel_512b_4way = case1;
        end
        4'b?100: begin
          priority_sel_512b_4way = case2;
        end
        4'b1000: begin
          priority_sel_512b_4way = case3;
        end
        4'b0000: begin
          priority_sel_512b_4way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_512b_4way = 512'dx;
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
  wire [31:0] literal_2381[0:15];
  assign literal_2381[0] = 32'h0000_0000;
  assign literal_2381[1] = 32'h0000_0000;
  assign literal_2381[2] = 32'h0000_0000;
  assign literal_2381[3] = 32'h0000_0000;
  assign literal_2381[4] = 32'h0000_0000;
  assign literal_2381[5] = 32'h0000_0000;
  assign literal_2381[6] = 32'h0000_0000;
  assign literal_2381[7] = 32'h0000_0000;
  assign literal_2381[8] = 32'h0000_0000;
  assign literal_2381[9] = 32'h0000_0000;
  assign literal_2381[10] = 32'h0000_0000;
  assign literal_2381[11] = 32'h0000_0000;
  assign literal_2381[12] = 32'h0000_0000;
  assign literal_2381[13] = 32'h0000_0000;
  assign literal_2381[14] = 32'h0000_0000;
  assign literal_2381[15] = 32'h0000_0000;
  reg [31:0] ____state[0:15];
  reg __regsvc__resp_has_been_sent_reg;
  reg __regsvc__ext_state_has_been_sent_reg;
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  reg [511:0] __regsvc__ext_state_reg;
  reg __regsvc__ext_state_valid_reg;
  wire [31:0] frame_header;
  wire [95:0] frame_payload__2;
  wire [7:0] frame_header_op;
  wire eq_2428;
  wire eq_2427;
  wire eq_2429;
  wire static_match_1_2;
  wire [2:0] concat_2438;
  wire resp2_header_op_squeezed__3_to_4;
  wire resp2_header_op_squeezed__0_to_1;
  wire or_2487;
  wire __regsvc__resp_vld_buf;
  wire __regsvc__resp_not_has_been_sent;
  wire regsvc__resp_valid_inv;
  wire __regsvc__ext_state_not_has_been_sent;
  wire regsvc__ext_state_valid_inv;
  wire [31:0] register_1;
  wire __regsvc__resp_valid_and_not_has_been_sent;
  wire regsvc__resp_valid_load_en;
  wire __regsvc__ext_state_valid_and_not_has_been_sent;
  wire regsvc__ext_state_valid_load_en;
  wire [3:0] resp2_header_op_squeezed_const_msb_bits;
  wire [31:0] value_1__1;
  wire eq_2445;
  wire nor_2446;
  wire regsvc__resp_not_pred;
  wire regsvc__resp_load_en;
  wire regsvc__ext_state_load_en;
  wire [26:0] sub_2425;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [1:0] ____state__next_value_predicates;
  wire __regsvc__ext_state_has_sent_or_is_ready;
  wire [511:0] _2__2;
  wire [31:0] _4__2;
  wire [31:0] _5__2;
  wire [2:0] one_hot_2463;
  wire p0_all_active_outputs_ready;
  wire [511:0] _3__2;
  wire [511:0] shll_2442;
  wire [31:0] newvalue_1;
  wire p0_stage_done;
  wire [1:0] resp2_header_op_squeezed__1_to_3;
  wire [31:0] newregisters_1[0:15];
  wire [3:0] one_hot_2630;
  wire regsvc__req_valid_inv;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire [95:0] _4__3;
  wire regsvc__req_valid_load_en;
  wire ____state__at_most_one_next_value;
  wire [1:0] concat_2510;
  wire __regsvc__resp_valid_and_all_active_outputs_ready;
  wire __regsvc__resp_valid_and_ready_txfr;
  wire __regsvc__ext_state_valid_and_all_active_outputs_ready;
  wire __regsvc__ext_state_valid_and_ready_txfr;
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire or_2665;
  wire [31:0] one_hot_sel_2511[0:15];
  wire and_2518;
  wire __regsvc__resp_not_stage_load;
  wire __regsvc__resp_has_been_sent_reg_load_en;
  wire __regsvc__ext_state_not_stage_load;
  wire __regsvc__ext_state_has_been_sent_reg_load_en;
  wire [127:0] resp2;
  wire [511:0] __regsvc__ext_state_buf;
  wire or_2667;
  assign frame_header = __regsvc__req_reg[127:96];
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign frame_header_op = frame_header[7:0];
  assign eq_2428 = frame_header_op == 8'h06;
  assign eq_2427 = frame_header_op == 8'h04;
  assign eq_2429 = frame_header_op == 8'h05;
  assign static_match_1_2 = frame_payload__2[31:4] == 28'h000_0000;
  assign concat_2438 = {eq_2428, eq_2427, eq_2429};
  assign resp2_header_op_squeezed__3_to_4 = 1'h0 & concat_2438[0] | static_match_1_2 & concat_2438[1] | 1'h1 & concat_2438[2];
  assign resp2_header_op_squeezed__0_to_1 = 1'h1 & concat_2438[0] | ~static_match_1_2 & concat_2438[1] | 1'h1 & concat_2438[2];
  assign or_2487 = resp2_header_op_squeezed__3_to_4 | resp2_header_op_squeezed__0_to_1;
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & or_2487;
  assign __regsvc__resp_not_has_been_sent = ~__regsvc__resp_has_been_sent_reg;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign __regsvc__ext_state_not_has_been_sent = ~__regsvc__ext_state_has_been_sent_reg;
  assign regsvc__ext_state_valid_inv = ~__regsvc__ext_state_valid_reg;
  assign register_1 = frame_payload__2[31:0];
  assign __regsvc__resp_valid_and_not_has_been_sent = __regsvc__resp_vld_buf & __regsvc__resp_not_has_been_sent;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign __regsvc__ext_state_valid_and_not_has_been_sent = __regsvc__req_valid_reg & __regsvc__ext_state_not_has_been_sent;
  assign regsvc__ext_state_valid_load_en = regsvc__ext_state_rdy | regsvc__ext_state_valid_inv;
  assign resp2_header_op_squeezed_const_msb_bits = 4'h0;
  assign value_1__1 = ____state[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign eq_2445 = frame_header_op == 8'h03;
  assign nor_2446 = ~(~eq_2427 | static_match_1_2);
  assign regsvc__resp_not_pred = ~or_2487;
  assign regsvc__resp_load_en = __regsvc__resp_valid_and_not_has_been_sent & regsvc__resp_valid_load_en;
  assign regsvc__ext_state_load_en = __regsvc__ext_state_valid_and_not_has_been_sent & regsvc__ext_state_valid_load_en;
  assign sub_2425 = 27'h000_0010 - frame_payload__2[58:32];
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign ____state__next_value_predicates = {eq_2445, nor_2446};
  assign __regsvc__ext_state_has_sent_or_is_ready = regsvc__ext_state_load_en | __regsvc__ext_state_has_been_sent_reg;
  assign _2__2 = {____state[resp2_header_op_squeezed_const_msb_bits], ____state[4'h1], ____state[4'h2], ____state[4'h3], ____state[4'h4], ____state[4'h5], ____state[4'h6], ____state[4'h7], ____state[4'h8], ____state[4'h9], ____state[4'ha], ____state[4'hb], ____state[4'hc], ____state[4'hd], ____state[4'he], ____state[4'hf]};
  assign _4__2 = ~(~value_1__1 | mask_1);
  assign _5__2 = value_1__2 & mask_1;
  assign one_hot_2463 = {____state__next_value_predicates[1:0] == 2'h0, ____state__next_value_predicates[1] && !____state__next_value_predicates[0], ____state__next_value_predicates[0]};
  assign p0_all_active_outputs_ready = (regsvc__resp_not_pred | regsvc__resp_load_en | __regsvc__resp_has_been_sent_reg) & __regsvc__ext_state_has_sent_or_is_ready;
  assign _3__2 = {frame_payload__2[26:0], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : _2__2 << {frame_payload__2[26:0], 5'h00};
  assign shll_2442 = {sub_2425, 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {sub_2425, 5'h00};
  assign newvalue_1 = _4__2 | _5__2;
  assign p0_stage_done = __regsvc__req_valid_reg & p0_all_active_outputs_ready;
  assign resp2_header_op_squeezed__1_to_3 = {2{eq_2429}};
  assign one_hot_2630 = {concat_2438[2:0] == 3'h0, concat_2438[2] && concat_2438[1:0] == 2'h0, concat_2438[1] && !concat_2438[0], concat_2438[0]};
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign txid = frame_header[23:16];
  assign resp2_header_op = {resp2_header_op_squeezed_const_msb_bits, resp2_header_op_squeezed__3_to_4, resp2_header_op_squeezed__1_to_3, resp2_header_op_squeezed__0_to_1};
  assign _4__3 = _3__2[511:416] & shll_2442[511:416];
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign ____state__at_most_one_next_value = eq_2445 == one_hot_2463[1] & nor_2446 == one_hot_2463[0];
  assign concat_2510 = {eq_2445 & p0_stage_done, nor_2446 & p0_stage_done};
  assign __regsvc__resp_valid_and_all_active_outputs_ready = __regsvc__resp_vld_buf & p0_all_active_outputs_ready;
  assign __regsvc__resp_valid_and_ready_txfr = __regsvc__resp_valid_and_not_has_been_sent & regsvc__resp_load_en;
  assign __regsvc__ext_state_valid_and_all_active_outputs_ready = __regsvc__req_valid_reg & p0_all_active_outputs_ready;
  assign __regsvc__ext_state_valid_and_ready_txfr = __regsvc__ext_state_valid_and_not_has_been_sent & regsvc__ext_state_load_en;
  assign resp2_header = {{6'h00, eq_2428, 1'h1 & concat_2438[0] | static_match_1_2 & concat_2438[1] | 1'h1 & concat_2438[2]}, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign or_2665 = ~p0_stage_done | ____state__at_most_one_next_value | reset;
  assign one_hot_sel_2511[0] = literal_2381[0] & {32{concat_2510[0]}} | newregisters_1[0] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[1] = literal_2381[1] & {32{concat_2510[0]}} | newregisters_1[1] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[2] = literal_2381[2] & {32{concat_2510[0]}} | newregisters_1[2] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[3] = literal_2381[3] & {32{concat_2510[0]}} | newregisters_1[3] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[4] = literal_2381[4] & {32{concat_2510[0]}} | newregisters_1[4] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[5] = literal_2381[5] & {32{concat_2510[0]}} | newregisters_1[5] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[6] = literal_2381[6] & {32{concat_2510[0]}} | newregisters_1[6] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[7] = literal_2381[7] & {32{concat_2510[0]}} | newregisters_1[7] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[8] = literal_2381[8] & {32{concat_2510[0]}} | newregisters_1[8] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[9] = literal_2381[9] & {32{concat_2510[0]}} | newregisters_1[9] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[10] = literal_2381[10] & {32{concat_2510[0]}} | newregisters_1[10] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[11] = literal_2381[11] & {32{concat_2510[0]}} | newregisters_1[11] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[12] = literal_2381[12] & {32{concat_2510[0]}} | newregisters_1[12] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[13] = literal_2381[13] & {32{concat_2510[0]}} | newregisters_1[13] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[14] = literal_2381[14] & {32{concat_2510[0]}} | newregisters_1[14] & {32{concat_2510[1]}};
  assign one_hot_sel_2511[15] = literal_2381[15] & {32{concat_2510[0]}} | newregisters_1[15] & {32{concat_2510[1]}};
  assign and_2518 = (eq_2445 | nor_2446) & p0_stage_done;
  assign __regsvc__resp_not_stage_load = ~__regsvc__resp_valid_and_all_active_outputs_ready;
  assign __regsvc__resp_has_been_sent_reg_load_en = __regsvc__resp_valid_and_ready_txfr | __regsvc__resp_valid_and_all_active_outputs_ready;
  assign __regsvc__ext_state_not_stage_load = ~__regsvc__ext_state_valid_and_all_active_outputs_ready;
  assign __regsvc__ext_state_has_been_sent_reg_load_en = __regsvc__ext_state_valid_and_ready_txfr | __regsvc__ext_state_valid_and_all_active_outputs_ready;
  assign resp2 = {resp2_header, {64'h0000_0000_0000_0000, register_1} & {96{concat_2438[0]}} | {64'h0000_0000_0000_0000, {32{static_match_1_2}} & value_1__1} & {96{concat_2438[1]}} | _4__3 & {96{concat_2438[2]}}};
  assign __regsvc__ext_state_buf = priority_sel_512b_4way({eq_2445, eq_2428, eq_2427, eq_2429}, _2__2, _2__2 & {512{static_match_1_2}}, _2__2, {newregisters_1[resp2_header_op_squeezed_const_msb_bits], newregisters_1[4'h1], newregisters_1[4'h2], newregisters_1[4'h3], newregisters_1[4'h4], newregisters_1[4'h5], newregisters_1[4'h6], newregisters_1[4'h7], newregisters_1[4'h8], newregisters_1[4'h9], newregisters_1[4'ha], newregisters_1[4'hb], newregisters_1[4'hc], newregisters_1[4'hd], newregisters_1[4'he], newregisters_1[4'hf]}, _2__2);
  assign or_2667 = ~p0_stage_done | concat_2438 == one_hot_2630[2:0] | reset;
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
      __regsvc__resp_has_been_sent_reg <= 1'h0;
      __regsvc__ext_state_has_been_sent_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
      __regsvc__resp_reg <= __regsvc__resp_reg_init;
      __regsvc__resp_valid_reg <= 1'h0;
      __regsvc__ext_state_reg <= 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_state_valid_reg <= 1'h0;
    end else begin
      ____state[0] <= and_2518 ? one_hot_sel_2511[0] : ____state[0];
      ____state[1] <= and_2518 ? one_hot_sel_2511[1] : ____state[1];
      ____state[2] <= and_2518 ? one_hot_sel_2511[2] : ____state[2];
      ____state[3] <= and_2518 ? one_hot_sel_2511[3] : ____state[3];
      ____state[4] <= and_2518 ? one_hot_sel_2511[4] : ____state[4];
      ____state[5] <= and_2518 ? one_hot_sel_2511[5] : ____state[5];
      ____state[6] <= and_2518 ? one_hot_sel_2511[6] : ____state[6];
      ____state[7] <= and_2518 ? one_hot_sel_2511[7] : ____state[7];
      ____state[8] <= and_2518 ? one_hot_sel_2511[8] : ____state[8];
      ____state[9] <= and_2518 ? one_hot_sel_2511[9] : ____state[9];
      ____state[10] <= and_2518 ? one_hot_sel_2511[10] : ____state[10];
      ____state[11] <= and_2518 ? one_hot_sel_2511[11] : ____state[11];
      ____state[12] <= and_2518 ? one_hot_sel_2511[12] : ____state[12];
      ____state[13] <= and_2518 ? one_hot_sel_2511[13] : ____state[13];
      ____state[14] <= and_2518 ? one_hot_sel_2511[14] : ____state[14];
      ____state[15] <= and_2518 ? one_hot_sel_2511[15] : ____state[15];
      __regsvc__resp_has_been_sent_reg <= __regsvc__resp_has_been_sent_reg_load_en ? __regsvc__resp_not_stage_load : __regsvc__resp_has_been_sent_reg;
      __regsvc__ext_state_has_been_sent_reg <= __regsvc__ext_state_has_been_sent_reg_load_en ? __regsvc__ext_state_not_stage_load : __regsvc__ext_state_has_been_sent_reg;
      __regsvc__req_reg <= regsvc__req_load_en ? regsvc__req : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? regsvc__req_vld : __regsvc__req_valid_reg;
      __regsvc__resp_reg <= regsvc__resp_load_en ? resp2 : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? __regsvc__resp_valid_and_not_has_been_sent : __regsvc__resp_valid_reg;
      __regsvc__ext_state_reg <= regsvc__ext_state_load_en ? __regsvc__ext_state_buf : __regsvc__ext_state_reg;
      __regsvc__ext_state_valid_reg <= regsvc__ext_state_valid_load_en ? __regsvc__ext_state_valid_and_not_has_been_sent : __regsvc__ext_state_valid_reg;
    end
  end
  assign regsvc__ext_state = __regsvc__ext_state_reg;
  assign regsvc__ext_state_vld = __regsvc__ext_state_valid_reg;
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
  wire and_2715;
  wire eq_2720;
  wire ne_2704;
  wire and_2721;
  wire or_2718;
  wire [2:0] add_2712;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2707;
  wire popped;
  wire [1:0] sub_2733;
  wire [1:0] add_2735;
  wire [2:0] umod_2713;
  wire [2:0] umod_2708;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2737;
  wire [127:0] array_update_2744[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2715 = pop_ready & push_valid;
  assign eq_2720 = head == tail;
  assign ne_2704 = head != tail;
  assign and_2721 = eq_2720 & and_2715;
  assign or_2718 = ne_2704 | push_valid;
  assign add_2712 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2707 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2718;
  assign sub_2733 = slots - 2'h1;
  assign add_2735 = slots + 2'h1;
  assign umod_2713 = add_2712 % long_buf_size_lit;
  assign umod_2708 = add_2707 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2713[1:0];
  assign did_push_occur = (can_do_push | and_2715) & push_valid & ~and_2721 & ~is_full_bool;
  assign next_tail_if_pop = umod_2708[1:0];
  assign did_pop_occur = (ne_2704 | and_2715) & pop_ready & ~and_2721;
  assign sel_2737 = pushed ? (popped ? slots : add_2735) : (popped ? sub_2733 : slots);
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
      slots <= sel_2737;
      buf__1[0] <= did_push_occur ? array_update_2744[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2744[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2718;
  assign pop_data = eq_2720 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2744_0
    assign array_update_2744[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_2772;
  wire eq_2777;
  wire ne_2761;
  wire and_2778;
  wire or_2775;
  wire [2:0] add_2769;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2764;
  wire popped;
  wire [1:0] sub_2790;
  wire [1:0] add_2792;
  wire [2:0] umod_2770;
  wire [2:0] umod_2765;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2794;
  wire [127:0] array_update_2801[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2772 = pop_ready & push_valid;
  assign eq_2777 = head == tail;
  assign ne_2761 = head != tail;
  assign and_2778 = eq_2777 & and_2772;
  assign or_2775 = ne_2761 | push_valid;
  assign add_2769 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2764 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2775;
  assign sub_2790 = slots - 2'h1;
  assign add_2792 = slots + 2'h1;
  assign umod_2770 = add_2769 % long_buf_size_lit;
  assign umod_2765 = add_2764 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2770[1:0];
  assign did_push_occur = (can_do_push | and_2772) & push_valid & ~and_2778 & ~is_full_bool;
  assign next_tail_if_pop = umod_2765[1:0];
  assign did_pop_occur = (ne_2761 | and_2772) & pop_ready & ~and_2778;
  assign sel_2794 = pushed ? (popped ? slots : add_2792) : (popped ? sub_2790 : slots);
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
      slots <= sel_2794;
      buf__1[0] <= did_push_occur ? array_update_2801[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2801[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2775;
  assign pop_data = eq_2777 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2801_0
    assign array_update_2801[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __regsvc__Top_0_next(
  input wire clk,
  input wire reset,
  input wire [32:0] regsvc__ext_recv,
  input wire regsvc__ext_recv_vld,
  input wire regsvc__ext_send_rdy,
  input wire regsvc__ext_state_rdy,
  output wire regsvc__ext_recv_rdy,
  output wire [32:0] regsvc__ext_send,
  output wire regsvc__ext_send_vld,
  output wire [511:0] regsvc__ext_state,
  output wire regsvc__ext_state_vld
);
  wire instantiation_output_2584;
  wire [127:0] instantiation_output_2601;
  wire instantiation_output_2602;
  wire [32:0] instantiation_output_2588;
  wire instantiation_output_2589;
  wire instantiation_output_2622;
  wire [511:0] instantiation_output_2594;
  wire instantiation_output_2595;
  wire instantiation_output_2609;
  wire [127:0] instantiation_output_2614;
  wire instantiation_output_2615;
  wire instantiation_output_2809;
  wire [127:0] instantiation_output_2810;
  wire instantiation_output_2811;
  wire instantiation_output_2816;
  wire [127:0] instantiation_output_2817;
  wire instantiation_output_2818;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_2809),
    .regsvc__ext_recv_rdy(instantiation_output_2584),
    .regsvc__req(instantiation_output_2601),
    .regsvc__req_vld(instantiation_output_2602),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_2817),
    .regsvc__resp_vld(instantiation_output_2818),
    .regsvc__ext_send(instantiation_output_2588),
    .regsvc__ext_send_vld(instantiation_output_2589),
    .regsvc__resp_rdy(instantiation_output_2622),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__ext_state_rdy(regsvc__ext_state_rdy),
    .regsvc__req(instantiation_output_2810),
    .regsvc__req_vld(instantiation_output_2811),
    .regsvc__resp_rdy(instantiation_output_2816),
    .regsvc__ext_state(instantiation_output_2594),
    .regsvc__ext_state_vld(instantiation_output_2595),
    .regsvc__req_rdy(instantiation_output_2609),
    .regsvc__resp(instantiation_output_2614),
    .regsvc__resp_vld(instantiation_output_2615),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_2601),
    .push_valid(instantiation_output_2602),
    .pop_ready(instantiation_output_2609),
    .push_ready(instantiation_output_2809),
    .pop_data(instantiation_output_2810),
    .pop_valid(instantiation_output_2811),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_2614),
    .push_valid(instantiation_output_2615),
    .pop_ready(instantiation_output_2622),
    .push_ready(instantiation_output_2816),
    .pop_data(instantiation_output_2817),
    .pop_valid(instantiation_output_2818),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_2584;
  assign regsvc__ext_send = instantiation_output_2588;
  assign regsvc__ext_send_vld = instantiation_output_2589;
  assign regsvc__ext_state = instantiation_output_2594;
  assign regsvc__ext_state_vld = instantiation_output_2595;
endmodule
