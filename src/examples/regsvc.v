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
  wire [2:0] one_hot_1260;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_1583;
  wire regsvc__ext_recv_valid_inv;
  wire [31:0] sel_1582;
  wire [31:0] sel_1581;
  wire [31:0] sel_1580;
  wire regsvc__ext_recv_valid_load_en;
  wire ____state_0__at_most_one_next_value;
  wire [1:0] concat_1292;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire regsvc__ext_recv_load_en;
  wire or_1592;
  wire [127:0] one_hot_sel_1293;
  wire [7:0] one_hot_sel_1299;
  wire [127:0] __regsvc__req_buf;
  assign beat_tlast = __regsvc__ext_recv_reg[32:32];
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign __regsvc__req_vld_buf = __regsvc__ext_recv_valid_reg & beat_tlast;
  assign regsvc__req_valid_load_en = regsvc__req_rdy | regsvc__req_valid_inv;
  assign ____state_0__next_value_predicates = {~beat_tlast, beat_tlast};
  assign regsvc__req_load_en = __regsvc__req_vld_buf & regsvc__req_valid_load_en;
  assign one_hot_1260 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign beat_word = __regsvc__ext_recv_reg[31:0];
  assign p0_stage_done = __regsvc__ext_recv_valid_reg & (~beat_tlast | regsvc__req_load_en);
  assign sel_1583 = ____state_1[2:0] == 3'h0 ? beat_word : ____state_0[31:0];
  assign regsvc__ext_recv_valid_inv = ~__regsvc__ext_recv_valid_reg;
  assign sel_1582 = ____state_1[2:0] == 3'h3 ? beat_word : ____state_0[127:96];
  assign sel_1581 = ____state_1[2:0] == 3'h2 ? beat_word : ____state_0[95:64];
  assign sel_1580 = ____state_1[2:0] == 3'h1 ? beat_word : ____state_0[63:32];
  assign regsvc__ext_recv_valid_load_en = p0_stage_done | regsvc__ext_recv_valid_inv;
  assign ____state_0__at_most_one_next_value = ~beat_tlast == one_hot_1260[1] & beat_tlast == one_hot_1260[0];
  assign concat_1292 = {~beat_tlast & p0_stage_done, beat_tlast & p0_stage_done};
  assign payload = {sel_1582, sel_1581, sel_1580, sel_1583};
  assign words_seen = ____state_1 + 8'h01;
  assign regsvc__ext_recv_load_en = regsvc__ext_recv_vld & regsvc__ext_recv_valid_load_en;
  assign or_1592 = ~p0_stage_done | ____state_0__at_most_one_next_value | reset;
  assign one_hot_sel_1293 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_1292[0]}} | payload & {128{concat_1292[1]}};
  assign one_hot_sel_1299 = 8'h00 & {8{concat_1292[0]}} | words_seen & {8{concat_1292[1]}};
  assign __regsvc__req_buf = {{sel_1583[7:0], sel_1583[15:8], sel_1583[23:16], sel_1583[31:24]}, {sel_1582, sel_1581, sel_1580}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_1 <= 8'h00;
      ____state_0 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __regsvc__ext_recv_reg <= __regsvc__ext_recv_reg_init;
      __regsvc__ext_recv_valid_reg <= 1'h0;
      __regsvc__req_reg <= __regsvc__req_reg_init;
      __regsvc__req_valid_reg <= 1'h0;
    end else begin
      ____state_1 <= p0_stage_done ? one_hot_sel_1299 : ____state_1;
      ____state_0 <= p0_stage_done ? one_hot_sel_1293 : ____state_0;
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
  wire [127:0] literal_1349 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire and_1396;
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
  assign regsvc__resp_select = state2_header_payload_words_0_case_cmp ? __regsvc__resp_reg : literal_1349;
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
  assign and_1396 = state2_header_payload_words_0_case_cmp & p0_stage_done;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign state2_header_payload_words = state2_header_payload_words_1_case_cmp ? ____state_0 : frame_header_payload_words__1;
  assign state2_payload__1 = state2_header_payload_words_1_case_cmp ? ____state_4[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign regsvc__resp_valid_load_en = and_1396 | regsvc__resp_valid_inv;
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
      ____state_0 <= and_1396 ? frame_header_payload_words__1 : ____state_0;
      ____state_5 <= p0_stage_done ? beats_sent : ____state_5;
      ____state_4 <= and_1396 ? payload : ____state_4;
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
  wire [3:0] literal_1438[0:6];
  assign literal_1438[0] = 4'h0;
  assign literal_1438[1] = 4'h0;
  assign literal_1438[2] = 4'h0;
  assign literal_1438[3] = 4'h7;
  assign literal_1438[4] = 4'h6;
  assign literal_1438[5] = 4'h8;
  assign literal_1438[6] = 4'h0;
  wire [1:0] literal_1437[0:6];
  assign literal_1437[0] = 2'h0;
  assign literal_1437[1] = 2'h0;
  assign literal_1437[2] = 2'h0;
  assign literal_1437[3] = 2'h1;
  assign literal_1437[4] = 2'h1;
  assign literal_1437[5] = 2'h3;
  assign literal_1437[6] = 2'h0;
  reg [31:0] ____state_1[0:15];
  reg [127:0] __regsvc__req_reg;
  reg __regsvc__req_valid_reg;
  reg [127:0] __regsvc__resp_reg;
  reg __regsvc__resp_valid_reg;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [3:0] array_index_1479;
  wire [95:0] frame_payload__2;
  wire ne_1502;
  wire regsvc__resp_valid_inv;
  wire [31:0] register_1;
  wire __regsvc__resp_vld_buf;
  wire regsvc__resp_valid_load_en;
  wire [31:0] value_1__1;
  wire regsvc__resp_not_pred;
  wire regsvc__resp_load_en;
  wire [31:0] mask_1;
  wire [31:0] value_1__2;
  wire [511:0] shll_1474;
  wire [2:0] concat_1490;
  wire [31:0] _4__2;
  wire [31:0] _5__2;
  wire [3:0] one_hot_1584;
  wire p0_stage_done;
  wire regsvc__req_valid_inv;
  wire [31:0] newvalue_1;
  wire [7:0] resp_header_tuple_idx_0;
  wire [7:0] txid;
  wire [7:0] resp_header_tuple_idx_3;
  wire [95:0] _3__3;
  wire regsvc__req_valid_load_en;
  wire [31:0] sel_1590;
  wire [31:0] resp2_header;
  wire regsvc__req_load_en;
  wire [31:0] array_update_1503[0:15];
  wire [127:0] resp2;
  wire or_1596;
  assign frame_header = __regsvc__req_reg[127:96];
  assign frame_header_op = frame_header[7:0];
  assign array_index_1479 = literal_1438[frame_header_op > 8'h06 ? 3'h6 : frame_header_op[2:0]];
  assign frame_payload__2 = __regsvc__req_reg[95:0];
  assign ne_1502 = array_index_1479 != 4'h0;
  assign regsvc__resp_valid_inv = ~__regsvc__resp_valid_reg;
  assign register_1 = frame_payload__2[31:0];
  assign __regsvc__resp_vld_buf = __regsvc__req_valid_reg & ne_1502;
  assign regsvc__resp_valid_load_en = regsvc__resp_rdy | regsvc__resp_valid_inv;
  assign value_1__1 = ____state_1[register_1 > 32'h0000_000f ? 4'hf : register_1[3:0]];
  assign regsvc__resp_not_pred = ~ne_1502;
  assign regsvc__resp_load_en = __regsvc__resp_vld_buf & regsvc__resp_valid_load_en;
  assign mask_1 = frame_payload__2[95:64];
  assign value_1__2 = frame_payload__2[63:32];
  assign shll_1474 = {frame_payload__2[58:32], 5'h00} >= 32'h0000_0200 ? 512'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 : 512'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff << {frame_payload__2[58:32], 5'h00};
  assign concat_1490 = {frame_header_op == 8'h05, frame_header_op == 8'h03, frame_header_op == 8'h04};
  assign _4__2 = ~(~value_1__1 | mask_1);
  assign _5__2 = value_1__2 & mask_1;
  assign one_hot_1584 = {concat_1490[2:0] == 3'h0, concat_1490[2] && concat_1490[1:0] == 2'h0, concat_1490[1] && !concat_1490[0], concat_1490[0]};
  assign p0_stage_done = __regsvc__req_valid_reg & (regsvc__resp_not_pred | regsvc__resp_load_en);
  assign regsvc__req_valid_inv = ~__regsvc__req_valid_reg;
  assign newvalue_1 = _4__2 | _5__2;
  assign resp_header_tuple_idx_0 = {6'h00, literal_1437[frame_header_op > 8'h06 ? 3'h6 : frame_header_op[2:0]]};
  assign txid = frame_header[23:16];
  assign resp_header_tuple_idx_3 = {4'h0, array_index_1479};
  assign _3__3 = ({frame_payload__2[26:0], 5'h00} >= 32'h0000_0060 ? 96'h0000_0000_0000_0000_0000_0000 : {____state_1[4'h0], ____state_1[4'h1], ____state_1[4'h2]} >> {frame_payload__2[26:0], 5'h00}) & shll_1474[511:416];
  assign regsvc__req_valid_load_en = p0_stage_done | regsvc__req_valid_inv;
  assign sel_1590 = frame_header_op == 8'h02 ? newvalue_1 : ____state_1[register_1];
  assign resp2_header = {resp_header_tuple_idx_0, txid, 8'h00, resp_header_tuple_idx_3};
  assign regsvc__req_load_en = regsvc__req_vld & regsvc__req_valid_load_en;
  assign resp2 = {resp2_header, {64'h0000_0000_0000_0000, register_1} & {96{concat_1490[0]}} | {64'h0000_0000_0000_0000, value_1__1} & {96{concat_1490[1]}} | _3__3 & {96{concat_1490[2]}}};
  assign or_1596 = ~p0_stage_done | concat_1490 == one_hot_1584[2:0] | reset;
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
      ____state_1[0] <= p0_stage_done ? array_update_1503[0] : ____state_1[0];
      ____state_1[1] <= p0_stage_done ? array_update_1503[1] : ____state_1[1];
      ____state_1[2] <= p0_stage_done ? array_update_1503[2] : ____state_1[2];
      ____state_1[3] <= p0_stage_done ? array_update_1503[3] : ____state_1[3];
      ____state_1[4] <= p0_stage_done ? array_update_1503[4] : ____state_1[4];
      ____state_1[5] <= p0_stage_done ? array_update_1503[5] : ____state_1[5];
      ____state_1[6] <= p0_stage_done ? array_update_1503[6] : ____state_1[6];
      ____state_1[7] <= p0_stage_done ? array_update_1503[7] : ____state_1[7];
      ____state_1[8] <= p0_stage_done ? array_update_1503[8] : ____state_1[8];
      ____state_1[9] <= p0_stage_done ? array_update_1503[9] : ____state_1[9];
      ____state_1[10] <= p0_stage_done ? array_update_1503[10] : ____state_1[10];
      ____state_1[11] <= p0_stage_done ? array_update_1503[11] : ____state_1[11];
      ____state_1[12] <= p0_stage_done ? array_update_1503[12] : ____state_1[12];
      ____state_1[13] <= p0_stage_done ? array_update_1503[13] : ____state_1[13];
      ____state_1[14] <= p0_stage_done ? array_update_1503[14] : ____state_1[14];
      ____state_1[15] <= p0_stage_done ? array_update_1503[15] : ____state_1[15];
      __regsvc__req_reg <= regsvc__req_load_en ? regsvc__req : __regsvc__req_reg;
      __regsvc__req_valid_reg <= regsvc__req_valid_load_en ? regsvc__req_vld : __regsvc__req_valid_reg;
      __regsvc__resp_reg <= regsvc__resp_load_en ? resp2 : __regsvc__resp_reg;
      __regsvc__resp_valid_reg <= regsvc__resp_valid_load_en ? __regsvc__resp_vld_buf : __regsvc__resp_valid_reg;
    end
  end
  assign regsvc__req_rdy = regsvc__req_load_en;
  assign regsvc__resp = __regsvc__resp_reg;
  assign regsvc__resp_vld = __regsvc__resp_valid_reg;
  for (genvar __i0 = 0; __i0 < 16; __i0 = __i0 + 1) begin : gen__array_update_1503_0
    assign array_update_1503[__i0] = register_1 == __i0 ? sel_1590 : ____state_1[__i0];
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
  wire and_1634;
  wire eq_1639;
  wire ne_1623;
  wire and_1640;
  wire or_1637;
  wire [2:0] add_1631;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_1626;
  wire popped;
  wire [1:0] sub_1652;
  wire [1:0] add_1654;
  wire [2:0] umod_1632;
  wire [2:0] umod_1627;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_1656;
  wire [127:0] array_update_1663[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_1634 = pop_ready & push_valid;
  assign eq_1639 = head == tail;
  assign ne_1623 = head != tail;
  assign and_1640 = eq_1639 & and_1634;
  assign or_1637 = ne_1623 | push_valid;
  assign add_1631 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_1626 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_1637;
  assign sub_1652 = slots - 2'h1;
  assign add_1654 = slots + 2'h1;
  assign umod_1632 = add_1631 % long_buf_size_lit;
  assign umod_1627 = add_1626 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_1632[1:0];
  assign did_push_occur = (can_do_push | and_1634) & push_valid & ~and_1640 & ~is_full_bool;
  assign next_tail_if_pop = umod_1627[1:0];
  assign did_pop_occur = (ne_1623 | and_1634) & pop_ready & ~and_1640;
  assign sel_1656 = pushed ? (popped ? slots : add_1654) : (popped ? sub_1652 : slots);
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
      slots <= sel_1656;
      buf__1[0] <= did_push_occur ? array_update_1663[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_1663[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_1637;
  assign pop_data = eq_1639 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_1663_0
    assign array_update_1663[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_1691;
  wire eq_1696;
  wire ne_1680;
  wire and_1697;
  wire or_1694;
  wire [2:0] add_1688;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_1683;
  wire popped;
  wire [1:0] sub_1709;
  wire [1:0] add_1711;
  wire [2:0] umod_1689;
  wire [2:0] umod_1684;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_1713;
  wire [127:0] array_update_1720[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_1691 = pop_ready & push_valid;
  assign eq_1696 = head == tail;
  assign ne_1680 = head != tail;
  assign and_1697 = eq_1696 & and_1691;
  assign or_1694 = ne_1680 | push_valid;
  assign add_1688 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_1683 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_1694;
  assign sub_1709 = slots - 2'h1;
  assign add_1711 = slots + 2'h1;
  assign umod_1689 = add_1688 % long_buf_size_lit;
  assign umod_1684 = add_1683 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_1689[1:0];
  assign did_push_occur = (can_do_push | and_1691) & push_valid & ~and_1697 & ~is_full_bool;
  assign next_tail_if_pop = umod_1684[1:0];
  assign did_pop_occur = (ne_1680 | and_1691) & pop_ready & ~and_1697;
  assign sel_1713 = pushed ? (popped ? slots : add_1711) : (popped ? sub_1709 : slots);
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
      slots <= sel_1713;
      buf__1[0] <= did_push_occur ? array_update_1720[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_1720[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_1694;
  assign pop_data = eq_1696 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_1720_0
    assign array_update_1720[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_1544;
  wire [127:0] instantiation_output_1555;
  wire instantiation_output_1556;
  wire [32:0] instantiation_output_1548;
  wire instantiation_output_1549;
  wire instantiation_output_1576;
  wire instantiation_output_1563;
  wire [127:0] instantiation_output_1568;
  wire instantiation_output_1569;
  wire instantiation_output_1728;
  wire [127:0] instantiation_output_1729;
  wire instantiation_output_1730;
  wire instantiation_output_1735;
  wire [127:0] instantiation_output_1736;
  wire instantiation_output_1737;

  // ===== Instantiations
  __axis__Top__Rx_0_next __axis__Top__Rx_0_next_inst0 (
    .reset(reset),
    .regsvc__ext_recv(regsvc__ext_recv),
    .regsvc__ext_recv_vld(regsvc__ext_recv_vld),
    .regsvc__req_rdy(instantiation_output_1728),
    .regsvc__ext_recv_rdy(instantiation_output_1544),
    .regsvc__req(instantiation_output_1555),
    .regsvc__req_vld(instantiation_output_1556),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .regsvc__ext_send_rdy(regsvc__ext_send_rdy),
    .regsvc__resp(instantiation_output_1736),
    .regsvc__resp_vld(instantiation_output_1737),
    .regsvc__ext_send(instantiation_output_1548),
    .regsvc__ext_send_vld(instantiation_output_1549),
    .regsvc__resp_rdy(instantiation_output_1576),
    .clk(clk)
  );
  __regsvc__Top_0_next__1 __regsvc__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __regsvc__Top__Service_0_next __regsvc__Top__Service_0_next_inst3 (
    .reset(reset),
    .regsvc__req(instantiation_output_1729),
    .regsvc__req_vld(instantiation_output_1730),
    .regsvc__resp_rdy(instantiation_output_1735),
    .regsvc__req_rdy(instantiation_output_1563),
    .regsvc__resp(instantiation_output_1568),
    .regsvc__resp_vld(instantiation_output_1569),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_regsvc__req_ (
    .reset(reset),
    .push_data(instantiation_output_1555),
    .push_valid(instantiation_output_1556),
    .pop_ready(instantiation_output_1563),
    .push_ready(instantiation_output_1728),
    .pop_data(instantiation_output_1729),
    .pop_valid(instantiation_output_1730),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_regsvc__resp_ (
    .reset(reset),
    .push_data(instantiation_output_1568),
    .push_valid(instantiation_output_1569),
    .pop_ready(instantiation_output_1576),
    .push_ready(instantiation_output_1735),
    .pop_data(instantiation_output_1736),
    .pop_valid(instantiation_output_1737),
    .clk(clk)
  );
  assign regsvc__ext_recv_rdy = instantiation_output_1544;
  assign regsvc__ext_send = instantiation_output_1548;
  assign regsvc__ext_send_vld = instantiation_output_1549;
endmodule
