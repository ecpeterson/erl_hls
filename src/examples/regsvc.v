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
  wire [2:0] one_hot_1147;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_1455;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_1454;
  wire [31:0] sel_1453;
  wire [31:0] sel_1452;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_1179;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_1464;
  wire [127:0] one_hot_sel_1180;
  wire [7:0] one_hot_sel_1186;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_1147 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_1455 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_1454 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_1453 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_1452 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_1147[1] & beat_tlast == one_hot_1147[0];
  assign concat_1179 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_1454, sel_1453, sel_1452, sel_1455};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_1464 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_1180 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_1179[0]}} | payload & {128{concat_1179[1]}};
  assign one_hot_sel_1186 = 8'h00 & {8{concat_1179[0]}} | words_seen & {8{concat_1179[1]}};
  assign __regsvc__req_buf = {{sel_1455[7:0], sel_1455[15:8], sel_1455[23:16], sel_1455[31:24]}, {sel_1454, sel_1453, sel_1452}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_1186 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_1180 : ____state_0;
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
  wire [127:0] literal_1236 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg [7:0] ____state_0;
  reg [7:0] ____state_5;
  reg [127:0] ____state_4;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  reg [32:0] __regsvc__ext_send_reg;
  reg __regsvc__ext_send_valid_reg;
  wire state2_header_payload_words_1_case_cmp;
  wire state2_header_payload_words_0_case_cmp;
  wire regsvc__ext_send_valid_inv;
  wire [127:0] regsvc__resp_select;
  wire __regsvc__ext_send_vld_buf;
  wire regsvc__ext_send_valid_load_en;
  wire [31:0] frame_header__1;
  wire regsvc__ext_send_load_en;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire [7:0] frame_header_payload_words__1;
  wire p0_stage_done;
  wire [7:0] state2_beats_sent__1;
  wire and_1283;
  wire regsvc__resp_valid_inv;
  wire [7:0] state2_header_payload_words;
  wire [31:0] state2_payload__1;
  wire regsvc__resp_valid_load_en;
  wire [95:0] frame_payload__1;
  wire regsvc__resp_load_en;
  wire [127:0] payload;
  wire [7:0] beats_sent;
  wire [32:0] __regsvc__ext_send_buf;
  assign state2_header_payload_words_1_case_cmp = ____state_0 >= ____state_5;
  assign state2_header_payload_words_0_case_cmp = ~state2_header_payload_words_1_case_cmp;
  assign regsvc__ext_send_valid_inv = ~__regsvc__ext_send_valid_reg;
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_1236;
  assign __regsvc__ext_send_vld_buf = state2_header_payload_words_1_case_cmp | __regsvc__resp_valid_reg;
  assign regsvc__ext_send_valid_load_en = regsvc__ext_send_rdy | regsvc__ext_send_valid_inv;
  assign frame_header__1 = regsvc__resp_select[127:96];
  assign regsvc__ext_send_load_en = __regsvc__ext_send_vld_buf & regsvc__ext_send_valid_load_en;
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign p0_stage_done = __regsvc__ext_send_vld_buf & regsvc__ext_send_load_en;
  assign state2_beats_sent__1 = ____state_5 & {8{state2_header_payload_words_1_case_cmp}};
  assign and_1283 = state2_header_payload_words_0_case_cmp & p0_stage_done;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign state2_header_payload_words = state2_header_payload_words_1_case_cmp ? ____state_0 : frame_header_payload_words__1;
  assign state2_payload__1 = state2_header_payload_words_1_case_cmp ? ____state_4[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = and_1283 | regsvc__resp_valid_inv;
  assign frame_payload__1 = regsvc__resp_select[95:0];
  assign regsvc__resp_load_en = regsvc__resp_vld & regsvc__resp_valid_load_en;
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign beats_sent = state2_beats_sent__1 + 8'h01;
  assign __regsvc__ext_send_buf = {state2_beats_sent__1 == state2_header_payload_words, state2_beats_sent__1[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__1[2:0] == 3'h1 ? ____state_4[63:32] : (state2_beats_sent__1[2:0] == 3'h2 ? ____state_4[95:64] : (state2_beats_sent__1[2:0] == 3'h3 ? ____state_4[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 8'h00;
      ____state_5 <= 8'h00;
      ____state_4 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__resp_reg <= __regsvc__resp_reg_init;
      __regsvc__resp_valid_reg <= 1'h0;
      __regsvc__ext_send_reg <= __regsvc__ext_send_reg_init;
      __regsvc__ext_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= and_1283 ? frame_header_payload_words__1 : ____state_0;
      ____state_5 <= p0_stage_done ? beats_sent : ____state_5;
      ____state_4 <= and_1283 ? payload : ____state_4;
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
  function automatic [7:0] priority_sel_8b_2way (input reg [1:0] sel, input reg [7:0] case0, input reg [7:0] case1, input reg [7:0] default_value);
    begin
      casez (sel)
        2'b?1: begin
          priority_sel_8b_2way = case0;
        end
        2'b10: begin
          priority_sel_8b_2way = case1;
        end
        2'b00: begin
          priority_sel_8b_2way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_8b_2way = 8'dx;
        end
      endcase
    end
  endfunction
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
  reg [31:0] ____state_1[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header__1_op;
  wire regsvc__resp_not_pred;
  wire [95:0] frame_payload__2;
  wire regsvc__resp_valid_inv;
  wire [31:0] register_1;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [31:0] value_1__1;
  wire resp2_header_op__0_to_4__0_to_1;
  wire eq_1346;
  wire regsvc__resp_load_en;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [1:0] concat_1355;
  wire [31:0] _4__1;
  wire [31:0] _5__1;
  wire [3:0] resp2_header_op__4_to_8;
  wire resp2_header_op__0_to_4__1_to_4__2_to_3;
  wire [1:0] resp2_header_op__0_to_4__1_to_4__0_to_2;
  wire [2:0] one_hot_1457;
  wire p0_stage_done;
  wire regsvc__req_valid_inv;
  wire [31:0] newvalue_1;
  wire [7:0] txid;
  wire [7:0] resp2_header_op;
  wire regsvc__req_valid_load_en;
  wire [31:0] sel_1456;
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire [31:0] array_update_1375[0:15];
  wire [127:0] resp2;
  wire or_1468;
  assign frame_header__1 = __regsvc__req_reg[127:96];
  assign frame_header__1_op = frame_header__1[7:0];
  assign regsvc__resp_not_pred = frame_header__1_op == 8'h02;
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign register_1 = frame_payload__2[31:0];
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & ~regsvc__resp_not_pred;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign value_1__1 = ____state_1[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign resp2_header_op__0_to_4__0_to_1 = frame_header__1_op == 8'h03;
  assign eq_1346 = frame_header__1_op == 8'h04;
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign concat_1355 = {resp2_header_op__0_to_4__0_to_1, eq_1346};
  assign _4__1 = ~(~value_1__1 | mask_1);
  assign _5__1 = value_1__2 & mask_1;
  assign resp2_header_op__4_to_8 = {4{~(resp2_header_op__0_to_4__0_to_1 | eq_1346)}};
  assign resp2_header_op__0_to_4__1_to_4__2_to_3 = 1'h0;
  assign resp2_header_op__0_to_4__1_to_4__0_to_2 = {2{resp2_header_op__0_to_4__0_to_1 | eq_1346}};
  assign one_hot_1457 = {concat_1355[1:0] == 2'h0, concat_1355[1] && !concat_1355[0], concat_1355[0]};
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign newvalue_1 = _4__1 | _5__1;
  assign txid = frame_header__1[23:16];
  assign resp2_header_op = {resp2_header_op__4_to_8, resp2_header_op__0_to_4__1_to_4__2_to_3, resp2_header_op__0_to_4__1_to_4__0_to_2, resp2_header_op__0_to_4__0_to_1};
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign sel_1456 = regsvc__resp_not_pred ? newvalue_1 : ____state_1[register_1];
  assign resp2_header = {8'h01, txid, 8'h00, resp2_header_op};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign resp2 = {resp2_header, {64'h0000_0000_0000_0000, frame_payload__2[31:8] & {24{concat_1355[0]}} | value_1__1[31:8] & {24{concat_1355[1]}}, priority_sel_8b_2way(concat_1355, frame_payload__2[7:0], value_1__1[7:0], frame_header__1_op)}};
  assign or_1468 = ~p0_stage_done | concat_1355 == one_hot_1457[1:0] | reset;
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
      ____state_1[0] <= p0_stage_done ? array_update_1375[0] : ____state_1[0];
      ____state_1[1] <= p0_stage_done ? array_update_1375[1] : ____state_1[1];
      ____state_1[2] <= p0_stage_done ? array_update_1375[2] : ____state_1[2];
      ____state_1[3] <= p0_stage_done ? array_update_1375[3] : ____state_1[3];
      ____state_1[4] <= p0_stage_done ? array_update_1375[4] : ____state_1[4];
      ____state_1[5] <= p0_stage_done ? array_update_1375[5] : ____state_1[5];
      ____state_1[6] <= p0_stage_done ? array_update_1375[6] : ____state_1[6];
      ____state_1[7] <= p0_stage_done ? array_update_1375[7] : ____state_1[7];
      ____state_1[8] <= p0_stage_done ? array_update_1375[8] : ____state_1[8];
      ____state_1[9] <= p0_stage_done ? array_update_1375[9] : ____state_1[9];
      ____state_1[10] <= p0_stage_done ? array_update_1375[10] : ____state_1[10];
      ____state_1[11] <= p0_stage_done ? array_update_1375[11] : ____state_1[11];
      ____state_1[12] <= p0_stage_done ? array_update_1375[12] : ____state_1[12];
      ____state_1[13] <= p0_stage_done ? array_update_1375[13] : ____state_1[13];
      ____state_1[14] <= p0_stage_done ? array_update_1375[14] : ____state_1[14];
      ____state_1[15] <= p0_stage_done ? array_update_1375[15] : ____state_1[15];
      __regsvc__req_reg <= regsvc__req_load_en ? regsvc__req : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? regsvc__req_vld : __regsvc__req_valid_reg;
      __regsvc__resp_reg <= regsvc__resp_load_en ? resp2 : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? __regsvc__resp_vld_buf : __regsvc__resp_valid_reg;
    end
  end
  assign regsvc__req_rdy = regsvc__req_load_en;
  assign regsvc__resp = __regsvc__resp_reg;
  assign regsvc__resp_vld = __regsvc__resp_valid_reg;
  for (genvar __i0 = 0; __i0 < 16; __i0 = __i0 + 1) begin : gen__array_update_1375_0
    assign array_update_1375[__i0] = register_1 == __i0 ? sel_1456 : ____state_1[__i0];
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
  wire and_1506;
  wire eq_1511;
  wire ne_1495;
  wire and_1512;
  wire or_1509;
  wire [2:0] add_1503;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_1498;
  wire popped;
  wire [1:0] sub_1524;
  wire [1:0] add_1526;
  wire [2:0] umod_1504;
  wire [2:0] umod_1499;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_1528;
  wire [127:0] array_update_1535[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_1506 = pop_ready & push_valid;
  assign eq_1511 = head == tail;
  assign ne_1495 = head != tail;
  assign and_1512 = eq_1511 & and_1506;
  assign or_1509 = ne_1495 | push_valid;
  assign add_1503 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_1498 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_1509;
  assign sub_1524 = slots - 2'h1;
  assign add_1526 = slots + 2'h1;
  assign umod_1504 = add_1503 % long_buf_size_lit;
  assign umod_1499 = add_1498 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_1504[1:0];
  assign did_push_occur = (can_do_push | and_1506) & push_valid & ~and_1512 & ~is_full_bool;
  assign next_tail_if_pop = umod_1499[1:0];
  assign did_pop_occur = (ne_1495 | and_1506) & pop_ready & ~and_1512;
  assign sel_1528 = pushed ? (popped ? slots : add_1526) : (popped ? sub_1524 : slots);
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
      slots <= sel_1528;
      buf__1[0] <= did_push_occur ? array_update_1535[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_1535[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_1509;
  assign pop_data = eq_1511 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_1535_0
    assign array_update_1535[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_1563;
  wire eq_1568;
  wire ne_1552;
  wire and_1569;
  wire or_1566;
  wire [2:0] add_1560;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_1555;
  wire popped;
  wire [1:0] sub_1581;
  wire [1:0] add_1583;
  wire [2:0] umod_1561;
  wire [2:0] umod_1556;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_1585;
  wire [127:0] array_update_1592[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_1563 = pop_ready & push_valid;
  assign eq_1568 = head == tail;
  assign ne_1552 = head != tail;
  assign and_1569 = eq_1568 & and_1563;
  assign or_1566 = ne_1552 | push_valid;
  assign add_1560 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_1555 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_1566;
  assign sub_1581 = slots - 2'h1;
  assign add_1583 = slots + 2'h1;
  assign umod_1561 = add_1560 % long_buf_size_lit;
  assign umod_1556 = add_1555 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_1561[1:0];
  assign did_push_occur = (can_do_push | and_1563) & push_valid & ~and_1569 & ~is_full_bool;
  assign next_tail_if_pop = umod_1556[1:0];
  assign did_pop_occur = (ne_1552 | and_1563) & pop_ready & ~and_1569;
  assign sel_1585 = pushed ? (popped ? slots : add_1583) : (popped ? sub_1581 : slots);
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
      slots <= sel_1585;
      buf__1[0] <= did_push_occur ? array_update_1592[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_1592[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_1566;
  assign pop_data = eq_1568 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_1592_0
    assign array_update_1592[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_1416;
  wire [127:0] instantiation_output_1427;
  wire instantiation_output_1428;
  wire [32:0] instantiation_output_1420;
  wire instantiation_output_1421;
  wire instantiation_output_1448;
  wire instantiation_output_1435;
  wire [127:0] instantiation_output_1440;
  wire instantiation_output_1441;
  wire instantiation_output_1600;
  wire [127:0] instantiation_output_1601;
  wire instantiation_output_1602;
  wire instantiation_output_1607;
  wire [127:0] instantiation_output_1608;
  wire instantiation_output_1609;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_1600),
    .regsvc__ext_recv_rdy(instantiation_output_1416),
    .regsvc__req(instantiation_output_1427),
    .regsvc__req_vld(instantiation_output_1428),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_1608),
    .regsvc__resp_vld(instantiation_output_1609),
    .regsvc__ext_send(instantiation_output_1420),
    .regsvc__ext_send_vld(instantiation_output_1421),
    .regsvc__resp_rdy(instantiation_output_1448),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_1601),
    .regsvc__req_vld(instantiation_output_1602),
    .regsvc__resp_rdy(instantiation_output_1607),
    .regsvc__req_rdy(instantiation_output_1435),
    .regsvc__resp(instantiation_output_1440),
    .regsvc__resp_vld(instantiation_output_1441),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_1427),
    .push_valid(instantiation_output_1428),
    .pop_ready(instantiation_output_1435),
    .push_ready(instantiation_output_1600),
    .pop_data(instantiation_output_1601),
    .pop_valid(instantiation_output_1602),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_1440),
    .push_valid(instantiation_output_1441),
    .pop_ready(instantiation_output_1448),
    .push_ready(instantiation_output_1607),
    .pop_data(instantiation_output_1608),
    .pop_valid(instantiation_output_1609),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_1416;
  assign regsvc__ext_send = instantiation_output_1420;
  assign regsvc__ext_send_vld = instantiation_output_1421;
endmodule
