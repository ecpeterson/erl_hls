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
  wire [2:0] one_hot_2403;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_2870;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_2869;
  wire [31:0] sel_2868;
  wire [31:0] sel_2867;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_2435;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_2878;
  wire [127:0] one_hot_sel_2436;
  wire [7:0] one_hot_sel_2442;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_2403 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_2870 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_2869 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_2868 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_2867 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_2403[1] & beat_tlast == one_hot_2403[0];
  assign concat_2435 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_2869, sel_2868, sel_2867, sel_2870};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_2878 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_2436 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2435[0]}} | payload & {128{concat_2435[1]}};
  assign one_hot_sel_2442 = 8'h00 & {8{concat_2435[0]}} | words_seen & {8{concat_2435[1]}};
  assign __regsvc__req_buf = {{sel_2870[7:0], sel_2870[15:8], sel_2870[23:16], sel_2870[31:24]}, {sel_2869, sel_2868, sel_2867}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_2442 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_2436 : ____state_0;
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
  wire [127:0] literal_2493 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_2505;
  wire not_2506;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire regsvc__ext_send_load_en;
  wire [2:0] one_hot_2515;
  wire [2:0] one_hot_2516;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire regsvc__resp_valid_inv;
  wire and_2555;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_2558;
  wire [127:0] payload;
  wire [1:0] concat_2571;
  wire [7:0] beats_sent;
  wire regsvc__resp_load_en;
  wire or_2882;
  wire or_2886;
  wire [7:0] one_hot_sel_2559;
  wire and_2579;
  wire [127:0] one_hot_sel_2566;
  wire [7:0] one_hot_sel_2572;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_2493;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign nor_2505 = ~(last | ____state_0);
  assign not_2506 = ~last;
  assign __regsvc__ext_send_vld_buf = ____state_0 | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_2505};
  assign ____state_6__next_value_predicates = {not_2506, last};
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign one_hot_2515 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_2516 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign and_2555 = last & p0_stage_done;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | regsvc__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_2515[1] & nor_2505 == one_hot_2515[0];
  assign ____state_6__at_most_one_next_value = not_2506 == one_hot_2516[1] & last == one_hot_2516[0];
  assign concat_2558 = {and_2555, nor_2505 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_2571 = {not_2506 & p0_stage_done, and_2555};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign or_2882 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_2886 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_2559 = frame_header_payload_words__1 & {8{concat_2558[0]}} | 8'h00 & {8{concat_2558[1]}};
  assign and_2579 = (last | nor_2505) & p0_stage_done;
  assign one_hot_sel_2566 = payload & {128{concat_2558[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_2558[1]}};
  assign one_hot_sel_2572 = 8'h00 & {8{concat_2571[0]}} | beats_sent & {8{concat_2571[1]}};
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
      ____state_0 <= p0_stage_done ? not_2506 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_2572 : ____state_6;
      ____state_1 <= and_2579 ? one_hot_sel_2559 : ____state_1;
      ____state_5 <= and_2579 ? one_hot_sel_2566 : ____state_5;
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
  function automatic [1:0] priority_sel_2b_4way (input reg [3:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] case3, input reg [1:0] default_value);
    begin
      casez (sel)
        4'b???1: begin
          priority_sel_2b_4way = case0;
        end
        4'b??10: begin
          priority_sel_2b_4way = case1;
        end
        4'b?100: begin
          priority_sel_2b_4way = case2;
        end
        4'b1000: begin
          priority_sel_2b_4way = case3;
        end
        4'b0000: begin
          priority_sel_2b_4way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_4way = 2'dx;
        end
      endcase
    end
  endfunction
  function automatic [1:0] priority_sel_2b_3way (input reg [2:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] default_value);
    begin
      casez (sel)
        3'b??1: begin
          priority_sel_2b_3way = case0;
        end
        3'b?10: begin
          priority_sel_2b_3way = case1;
        end
        3'b100: begin
          priority_sel_2b_3way = case2;
        end
        3'b000: begin
          priority_sel_2b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_3way = 2'dx;
        end
      endcase
    end
  endfunction
  function automatic [95:0] priority_sel_96b_4way (input reg [3:0] sel, input reg [95:0] case0, input reg [95:0] case1, input reg [95:0] case2, input reg [95:0] case3, input reg [95:0] default_value);
    begin
      casez (sel)
        4'b???1: begin
          priority_sel_96b_4way = case0;
        end
        4'b??10: begin
          priority_sel_96b_4way = case1;
        end
        4'b?100: begin
          priority_sel_96b_4way = case2;
        end
        4'b1000: begin
          priority_sel_96b_4way = case3;
        end
        4'b0000: begin
          priority_sel_96b_4way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_96b_4way = 96'dx;
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
  wire [31:0] literal_2656[0:15];
  assign literal_2656[0] = 32'h0000_0000;
  assign literal_2656[1] = 32'h0000_0000;
  assign literal_2656[2] = 32'h0000_0000;
  assign literal_2656[3] = 32'h0000_0000;
  assign literal_2656[4] = 32'h0000_0000;
  assign literal_2656[5] = 32'h0000_0000;
  assign literal_2656[6] = 32'h0000_0000;
  assign literal_2656[7] = 32'h0000_0000;
  assign literal_2656[8] = 32'h0000_0000;
  assign literal_2656[9] = 32'h0000_0000;
  assign literal_2656[10] = 32'h0000_0000;
  assign literal_2656[11] = 32'h0000_0000;
  assign literal_2656[12] = 32'h0000_0000;
  assign literal_2656[13] = 32'h0000_0000;
  assign literal_2656[14] = 32'h0000_0000;
  assign literal_2656[15] = 32'h0000_0000;
  reg [31:0] ____state[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [95:0] frame_payload__2;
  wire [31:0] request_value;
  wire [31:0] Xls_clause_2_Count_1;
  wire [31:0] frame_header;
  wire [31:0] Xls_clause_2_Mask_1;
  wire [31:0] _2__3;
  wire [7:0] frame_header_op;
  wire _0__5;
  wire _0__4;
  wire _0__3;
  wire _1__3;
  wire _3__1;
  wire eq_2710;
  wire eq_2711;
  wire eq_2712;
  wire eq_2713;
  wire nor_2716;
  wire and_2704;
  wire [3:0] concat_2725;
  wire [1:0] concat_2727;
  wire [2:0] concat_2737;
  wire or_2714;
  wire [1:0] resp2_header_op_squeezed__0_to_3_squeezed;
  wire [3:0] resp2_header_op_squeezed_const_msb_bits;
  wire resp2_header_op_squeezed__3_to_4;
  wire [26:0] sub_2701;
  wire or_2775;
  wire regsvc__resp_valid_inv;
  wire [511:0] _8;
  wire and_2730;
  wire nor_2731;
  wire and_2732;
  wire nor_2733;
  wire nor_2734;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [511:0] _9;
  wire [511:0] shll_2718;
  wire [4:0] ____state__next_value_predicates;
  wire regsvc__resp_not_pred;
  wire regsvc__resp_load_en;
  wire [31:0] Xls_clause_1_Value_1__1;
  wire [5:0] one_hot_2749;
  wire [95:0] _10__1;
  wire p0_stage_done;
  wire [31:0] _5__2;
  wire [31:0] _6__2;
  wire [2:0] resp2_header_op_squeezed__0_to_3;
  wire [3:0] one_hot_2871;
  wire regsvc__req_valid_inv;
  wire [31:0] Xls_clause_2_NewValue_1;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire regsvc__req_valid_load_en;
  wire ____state__at_most_one_next_value;
  wire [4:0] concat_2794;
  wire [31:0] Xls_clause_2_NewRegisters_1[0:15];
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire or_2888;
  wire [31:0] one_hot_sel_2795[0:15];
  wire and_2801;
  wire [127:0] resp2;
  wire or_2890;
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign request_value = frame_payload__2[31:0];
  assign Xls_clause_2_Count_1 = frame_payload__2[63:32];
  assign frame_header = __regsvc__req_reg[127:96];
  assign Xls_clause_2_Mask_1 = frame_payload__2[95:64];
  assign _2__3 = request_value + Xls_clause_2_Count_1;
  assign frame_header_op = frame_header[7:0];
  assign _0__5 = frame_payload__2[31:4] == 28'h000_0000;
  assign _0__4 = Xls_clause_2_Mask_1 == 32'h0000_0000;
  assign _0__3 = Xls_clause_2_Count_1 != 32'h0000_0000;
  assign _1__3 = frame_payload__2[63:34] == 30'h0000_0000;
  assign _3__1 = _2__3 < 32'h0000_0011;
  assign eq_2710 = frame_header_op == 8'h03;
  assign eq_2711 = frame_header_op == 8'h06;
  assign eq_2712 = frame_header_op == 8'h04;
  assign eq_2713 = frame_header_op == 8'h05;
  assign nor_2716 = ~(_0__4 | _0__5);
  assign and_2704 = _0__3 & _1__3 & _3__1;
  assign concat_2725 = {eq_2710, eq_2711, eq_2712, eq_2713};
  assign concat_2727 = {1'h0, nor_2716};
  assign concat_2737 = {eq_2711, eq_2712, eq_2713};
  assign or_2714 = ~_0__3 | and_2704;
  assign resp2_header_op_squeezed__0_to_3_squeezed = priority_sel_2b_4way(concat_2725, 2'h3, {1'h0, ~_0__5}, 2'h1, concat_2727, 2'h1);
  assign resp2_header_op_squeezed_const_msb_bits = 4'h0;
  assign resp2_header_op_squeezed__3_to_4 = 1'h0 & concat_2737[0] | _0__5 & concat_2737[1] | or_2714 & concat_2737[2];
  assign sub_2701 = 27'h000_0010 - frame_payload__2[58:32];
  assign or_2775 = resp2_header_op_squeezed__3_to_4 | resp2_header_op_squeezed__0_to_3_squeezed != 2'h0;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign _8 = {____state[resp2_header_op_squeezed_const_msb_bits], ____state[4'h1], ____state[4'h2], ____state[4'h3], ____state[4'h4], ____state[4'h5], ____state[4'h6], ____state[4'h7], ____state[4'h8], ____state[4'h9], ____state[4'ha], ____state[4'hb], ____state[4'hc], ____state[4'hd], ____state[4'he], ____state[4'hf]};
  assign and_2730 = ~eq_2710 & ~eq_2711 & ~eq_2712 & ~eq_2713;
  assign nor_2731 = ~(~eq_2712 | _0__5);
  assign and_2732 = eq_2711 & ~or_2714;
  assign nor_2733 = ~(~eq_2710 | _0__4 | _0__5);
  assign nor_2734 = ~(~eq_2710 | _0__4 | ~_0__5);
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & or_2775;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign _9 = {frame_payload__2[26:0], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : _8 << {frame_payload__2[26:0], 5'h00};
  assign shll_2718 = {sub_2701, 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {sub_2701, 5'h00};
  assign ____state__next_value_predicates = {and_2730, nor_2731, and_2732, nor_2733, nor_2734};
  assign regsvc__resp_not_pred = ~or_2775;
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign Xls_clause_1_Value_1__1 = ____state[request_value > 32'h0000_000f ? 4'hf : request_value[3:0]];
  assign one_hot_2749 = {____state__next_value_predicates[4:0] == 5'h00, ____state__next_value_predicates[4] && ____state__next_value_predicates[3:0] == 4'h0, ____state__next_value_predicates[3] && ____state__next_value_predicates[2:0] == 3'h0, ____state__next_value_predicates[2] && ____state__next_value_predicates[1:0] == 2'h0, ____state__next_value_predicates[1] && !____state__next_value_predicates[0], ____state__next_value_predicates[0]};
  assign _10__1 = _9[511:416] & shll_2718[511:416];
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign _5__2 = ~(~Xls_clause_1_Value_1__1 | Xls_clause_2_Mask_1);
  assign _6__2 = Xls_clause_2_Count_1 & Xls_clause_2_Mask_1;
  assign resp2_header_op_squeezed__0_to_3 = {{1{resp2_header_op_squeezed__0_to_3_squeezed[1]}}, resp2_header_op_squeezed__0_to_3_squeezed};
  assign one_hot_2871 = {concat_2737[2:0] == 3'h0, concat_2737[2] && concat_2737[1:0] == 2'h0, concat_2737[1] && !concat_2737[0], concat_2737[0]};
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign Xls_clause_2_NewValue_1 = _5__2 | _6__2;
  assign txid = frame_header[23:16];
  assign resp2_header_op = {resp2_header_op_squeezed_const_msb_bits, resp2_header_op_squeezed__3_to_4, resp2_header_op_squeezed__0_to_3};
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign ____state__at_most_one_next_value = and_2730 == one_hot_2749[4] & nor_2731 == one_hot_2749[3] & and_2732 == one_hot_2749[2] & nor_2733 == one_hot_2749[1] & nor_2734 == one_hot_2749[0];
  assign concat_2794 = {and_2730 & p0_stage_done, nor_2731 & p0_stage_done, and_2732 & p0_stage_done, nor_2733 & p0_stage_done, nor_2734 & p0_stage_done};
  assign resp2_header = {{6'h00, priority_sel_2b_3way({eq_2710, eq_2711, eq_2712 | eq_2713}, 2'h1, {or_2714, 1'h1}, concat_2727, 2'h1)}, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign or_2888 = ~p0_stage_done | ____state__at_most_one_next_value | reset;
  assign one_hot_sel_2795[0] = Xls_clause_2_NewRegisters_1[0] & {32{concat_2794[0]}} | literal_2656[0] & {32{concat_2794[1]}} | literal_2656[0] & {32{concat_2794[2]}} | literal_2656[0] & {32{concat_2794[3]}} | literal_2656[0] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[1] = Xls_clause_2_NewRegisters_1[1] & {32{concat_2794[0]}} | literal_2656[1] & {32{concat_2794[1]}} | literal_2656[1] & {32{concat_2794[2]}} | literal_2656[1] & {32{concat_2794[3]}} | literal_2656[1] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[2] = Xls_clause_2_NewRegisters_1[2] & {32{concat_2794[0]}} | literal_2656[2] & {32{concat_2794[1]}} | literal_2656[2] & {32{concat_2794[2]}} | literal_2656[2] & {32{concat_2794[3]}} | literal_2656[2] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[3] = Xls_clause_2_NewRegisters_1[3] & {32{concat_2794[0]}} | literal_2656[3] & {32{concat_2794[1]}} | literal_2656[3] & {32{concat_2794[2]}} | literal_2656[3] & {32{concat_2794[3]}} | literal_2656[3] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[4] = Xls_clause_2_NewRegisters_1[4] & {32{concat_2794[0]}} | literal_2656[4] & {32{concat_2794[1]}} | literal_2656[4] & {32{concat_2794[2]}} | literal_2656[4] & {32{concat_2794[3]}} | literal_2656[4] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[5] = Xls_clause_2_NewRegisters_1[5] & {32{concat_2794[0]}} | literal_2656[5] & {32{concat_2794[1]}} | literal_2656[5] & {32{concat_2794[2]}} | literal_2656[5] & {32{concat_2794[3]}} | literal_2656[5] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[6] = Xls_clause_2_NewRegisters_1[6] & {32{concat_2794[0]}} | literal_2656[6] & {32{concat_2794[1]}} | literal_2656[6] & {32{concat_2794[2]}} | literal_2656[6] & {32{concat_2794[3]}} | literal_2656[6] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[7] = Xls_clause_2_NewRegisters_1[7] & {32{concat_2794[0]}} | literal_2656[7] & {32{concat_2794[1]}} | literal_2656[7] & {32{concat_2794[2]}} | literal_2656[7] & {32{concat_2794[3]}} | literal_2656[7] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[8] = Xls_clause_2_NewRegisters_1[8] & {32{concat_2794[0]}} | literal_2656[8] & {32{concat_2794[1]}} | literal_2656[8] & {32{concat_2794[2]}} | literal_2656[8] & {32{concat_2794[3]}} | literal_2656[8] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[9] = Xls_clause_2_NewRegisters_1[9] & {32{concat_2794[0]}} | literal_2656[9] & {32{concat_2794[1]}} | literal_2656[9] & {32{concat_2794[2]}} | literal_2656[9] & {32{concat_2794[3]}} | literal_2656[9] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[10] = Xls_clause_2_NewRegisters_1[10] & {32{concat_2794[0]}} | literal_2656[10] & {32{concat_2794[1]}} | literal_2656[10] & {32{concat_2794[2]}} | literal_2656[10] & {32{concat_2794[3]}} | literal_2656[10] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[11] = Xls_clause_2_NewRegisters_1[11] & {32{concat_2794[0]}} | literal_2656[11] & {32{concat_2794[1]}} | literal_2656[11] & {32{concat_2794[2]}} | literal_2656[11] & {32{concat_2794[3]}} | literal_2656[11] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[12] = Xls_clause_2_NewRegisters_1[12] & {32{concat_2794[0]}} | literal_2656[12] & {32{concat_2794[1]}} | literal_2656[12] & {32{concat_2794[2]}} | literal_2656[12] & {32{concat_2794[3]}} | literal_2656[12] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[13] = Xls_clause_2_NewRegisters_1[13] & {32{concat_2794[0]}} | literal_2656[13] & {32{concat_2794[1]}} | literal_2656[13] & {32{concat_2794[2]}} | literal_2656[13] & {32{concat_2794[3]}} | literal_2656[13] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[14] = Xls_clause_2_NewRegisters_1[14] & {32{concat_2794[0]}} | literal_2656[14] & {32{concat_2794[1]}} | literal_2656[14] & {32{concat_2794[2]}} | literal_2656[14] & {32{concat_2794[3]}} | literal_2656[14] & {32{concat_2794[4]}};
  assign one_hot_sel_2795[15] = Xls_clause_2_NewRegisters_1[15] & {32{concat_2794[0]}} | literal_2656[15] & {32{concat_2794[1]}} | literal_2656[15] & {32{concat_2794[2]}} | literal_2656[15] & {32{concat_2794[3]}} | literal_2656[15] & {32{concat_2794[4]}};
  assign and_2801 = (and_2730 | nor_2731 | and_2732 | nor_2733 | nor_2734) & p0_stage_done;
  assign resp2 = {resp2_header, priority_sel_96b_4way(concat_2725, {64'h0000_0000_0000_0000, request_value}, {64'h0000_0000_0000_0000, _0__5 ? Xls_clause_1_Value_1__1 : 32'h0000_0001}, (and_2704 ? _10__1 : 96'h0000_0000_0000_0000_0000_0001) & {96{_0__3}}, {95'h0000_0000_0000_0000_0000_0000, nor_2716}, 96'h0000_0000_0000_0000_0000_0001)};
  assign or_2890 = ~p0_stage_done | concat_2737 == one_hot_2871[2:0] | reset;
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
      ____state[0] <= and_2801 ? one_hot_sel_2795[0] : ____state[0];
      ____state[1] <= and_2801 ? one_hot_sel_2795[1] : ____state[1];
      ____state[2] <= and_2801 ? one_hot_sel_2795[2] : ____state[2];
      ____state[3] <= and_2801 ? one_hot_sel_2795[3] : ____state[3];
      ____state[4] <= and_2801 ? one_hot_sel_2795[4] : ____state[4];
      ____state[5] <= and_2801 ? one_hot_sel_2795[5] : ____state[5];
      ____state[6] <= and_2801 ? one_hot_sel_2795[6] : ____state[6];
      ____state[7] <= and_2801 ? one_hot_sel_2795[7] : ____state[7];
      ____state[8] <= and_2801 ? one_hot_sel_2795[8] : ____state[8];
      ____state[9] <= and_2801 ? one_hot_sel_2795[9] : ____state[9];
      ____state[10] <= and_2801 ? one_hot_sel_2795[10] : ____state[10];
      ____state[11] <= and_2801 ? one_hot_sel_2795[11] : ____state[11];
      ____state[12] <= and_2801 ? one_hot_sel_2795[12] : ____state[12];
      ____state[13] <= and_2801 ? one_hot_sel_2795[13] : ____state[13];
      ____state[14] <= and_2801 ? one_hot_sel_2795[14] : ____state[14];
      ____state[15] <= and_2801 ? one_hot_sel_2795[15] : ____state[15];
      __regsvc__req_reg <= regsvc__req_load_en ? regsvc__req : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? regsvc__req_vld : __regsvc__req_valid_reg;
      __regsvc__resp_reg <= regsvc__resp_load_en ? resp2 : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? __regsvc__resp_vld_buf : __regsvc__resp_valid_reg;
    end
  end
  assign regsvc__req_rdy = regsvc__req_load_en;
  assign regsvc__resp = __regsvc__resp_reg;
  assign regsvc__resp_vld = __regsvc__resp_valid_reg;
  for (genvar __i0 = 0; __i0 < 16; __i0 = __i0 + 1) begin : gen__Xls_clause_2_NewRegisters_1_0
    assign Xls_clause_2_NewRegisters_1[__i0] = request_value == __i0 ? Xls_clause_2_NewValue_1 : ____state[__i0];
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
  wire and_2930;
  wire eq_2935;
  wire ne_2919;
  wire and_2936;
  wire or_2933;
  wire [2:0] add_2927;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2922;
  wire popped;
  wire [1:0] sub_2948;
  wire [1:0] add_2950;
  wire [2:0] umod_2928;
  wire [2:0] umod_2923;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_2952;
  wire [127:0] array_update_2959[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2930 = pop_ready & push_valid;
  assign eq_2935 = head == tail;
  assign ne_2919 = head != tail;
  assign and_2936 = eq_2935 & and_2930;
  assign or_2933 = ne_2919 | push_valid;
  assign add_2927 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2922 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2933;
  assign sub_2948 = slots - 2'h1;
  assign add_2950 = slots + 2'h1;
  assign umod_2928 = add_2927 % long_buf_size_lit;
  assign umod_2923 = add_2922 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2928[1:0];
  assign did_push_occur = (can_do_push | and_2930) & push_valid & ~and_2936 & ~is_full_bool;
  assign next_tail_if_pop = umod_2923[1:0];
  assign did_pop_occur = (ne_2919 | and_2930) & pop_ready & ~and_2936;
  assign sel_2952 = pushed ? (popped ? slots : add_2950) : (popped ? sub_2948 : slots);
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
      slots <= sel_2952;
      buf__1[0] <= did_push_occur ? array_update_2959[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_2959[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2933;
  assign pop_data = eq_2935 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_2959_0
    assign array_update_2959[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_2987;
  wire eq_2992;
  wire ne_2976;
  wire and_2993;
  wire or_2990;
  wire [2:0] add_2984;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_2979;
  wire popped;
  wire [1:0] sub_3005;
  wire [1:0] add_3007;
  wire [2:0] umod_2985;
  wire [2:0] umod_2980;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_3009;
  wire [127:0] array_update_3016[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_2987 = pop_ready & push_valid;
  assign eq_2992 = head == tail;
  assign ne_2976 = head != tail;
  assign and_2993 = eq_2992 & and_2987;
  assign or_2990 = ne_2976 | push_valid;
  assign add_2984 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_2979 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_2990;
  assign sub_3005 = slots - 2'h1;
  assign add_3007 = slots + 2'h1;
  assign umod_2985 = add_2984 % long_buf_size_lit;
  assign umod_2980 = add_2979 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_2985[1:0];
  assign did_push_occur = (can_do_push | and_2987) & push_valid & ~and_2993 & ~is_full_bool;
  assign next_tail_if_pop = umod_2980[1:0];
  assign did_pop_occur = (ne_2976 | and_2987) & pop_ready & ~and_2993;
  assign sel_3009 = pushed ? (popped ? slots : add_3007) : (popped ? sub_3005 : slots);
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
      slots <= sel_3009;
      buf__1[0] <= did_push_occur ? array_update_3016[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_3016[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_2990;
  assign pop_data = eq_2992 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_3016_0
    assign array_update_3016[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_2831;
  wire [127:0] instantiation_output_2842;
  wire instantiation_output_2843;
  wire [32:0] instantiation_output_2835;
  wire instantiation_output_2836;
  wire instantiation_output_2863;
  wire instantiation_output_2850;
  wire [127:0] instantiation_output_2855;
  wire instantiation_output_2856;
  wire instantiation_output_3024;
  wire [127:0] instantiation_output_3025;
  wire instantiation_output_3026;
  wire instantiation_output_3031;
  wire [127:0] instantiation_output_3032;
  wire instantiation_output_3033;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_3024),
    .regsvc__ext_recv_rdy(instantiation_output_2831),
    .regsvc__req(instantiation_output_2842),
    .regsvc__req_vld(instantiation_output_2843),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_3032),
    .regsvc__resp_vld(instantiation_output_3033),
    .regsvc__ext_send(instantiation_output_2835),
    .regsvc__ext_send_vld(instantiation_output_2836),
    .regsvc__resp_rdy(instantiation_output_2863),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_3025),
    .regsvc__req_vld(instantiation_output_3026),
    .regsvc__resp_rdy(instantiation_output_3031),
    .regsvc__req_rdy(instantiation_output_2850),
    .regsvc__resp(instantiation_output_2855),
    .regsvc__resp_vld(instantiation_output_2856),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_2842),
    .push_valid(instantiation_output_2843),
    .pop_ready(instantiation_output_2850),
    .push_ready(instantiation_output_3024),
    .pop_data(instantiation_output_3025),
    .pop_valid(instantiation_output_3026),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_2855),
    .push_valid(instantiation_output_2856),
    .pop_ready(instantiation_output_2863),
    .push_ready(instantiation_output_3031),
    .pop_data(instantiation_output_3032),
    .pop_valid(instantiation_output_3033),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_2831;
  assign regsvc__ext_send = instantiation_output_2835;
  assign regsvc__ext_send_vld = instantiation_output_2836;
endmodule
