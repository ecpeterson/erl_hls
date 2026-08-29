module __axis__Top__ReservedRx_0_next(
  input wire clk,
  input wire reset,
  input wire phi_halo_cell__admit,
  input wire phi_halo_cell__admit_vld,
  input wire [32:0] phi_halo_cell__ext_recv,
  input wire phi_halo_cell__ext_recv_vld,
  input wire phi_halo_cell__req_rdy,
  output wire phi_halo_cell__admit_rdy,
  output wire phi_halo_cell__ext_recv_rdy,
  output wire [127:0] phi_halo_cell__req,
  output wire phi_halo_cell__req_vld
);
  wire [32:0] __phi_halo_cell__ext_recv_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] literal_13924 = {1'h0, 32'h0000_0000};
  reg ____state_0;
  reg [7:0] ____state_2;
  reg [127:0] ____state_1;
  reg [32:0] __phi_halo_cell__ext_recv_reg;
  reg __phi_halo_cell__ext_recv_valid_reg;
  reg __phi_halo_cell__admit_reg;
  reg __phi_halo_cell__admit_valid_reg;
  reg [127:0] __phi_halo_cell__req_reg;
  reg __phi_halo_cell__req_valid_reg;
  wire [32:0] phi_halo_cell__ext_recv_select;
  wire beat_tlast;
  wire p0_all_active_inputs_valid;
  wire and_13934;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_13933;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_13946;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_15733;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_15732;
  wire [31:0] sel_15731;
  wire [31:0] sel_15730;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_13991;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_15736;
  wire nand_13962;
  wire [127:0] one_hot_sel_13992;
  wire and_14006;
  wire [7:0] one_hot_sel_13999;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_13924;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_13934 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_13934;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_13933 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_13934;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_13933, and_13934};
  assign one_hot_13946 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_15733 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_15732 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_15731 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_15730 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_13933 == one_hot_13946[1] & and_13934 == one_hot_13946[0];
  assign concat_13991 = {nor_13933 & p0_stage_done, and_13934 & p0_stage_done};
  assign payload = {sel_15732, sel_15731, sel_15730, sel_15733};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_15736 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_13962 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_13992 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13991[0]}} | payload & {128{concat_13991[1]}};
  assign and_14006 = (nor_13933 | and_13934) & p0_stage_done;
  assign one_hot_sel_13999 = 8'h00 & {8{concat_13991[0]}} | words_seen & {8{concat_13991[1]}};
  assign __phi_halo_cell__req_buf = {{sel_15733[7:0], sel_15733[15:8], sel_15733[23:16], sel_15733[31:24]}, {sel_15732, sel_15731, sel_15730}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_2 <= 8'h00;
      ____state_1 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__ext_recv_reg <= __phi_halo_cell__ext_recv_reg_init;
      __phi_halo_cell__ext_recv_valid_reg <= 1'h0;
      __phi_halo_cell__admit_reg <= 1'h0;
      __phi_halo_cell__admit_valid_reg <= 1'h0;
      __phi_halo_cell__req_reg <= __phi_halo_cell__req_reg_init;
      __phi_halo_cell__req_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? nand_13962 : ____state_0;
      ____state_2 <= and_14006 ? one_hot_sel_13999 : ____state_2;
      ____state_1 <= and_14006 ? one_hot_sel_13992 : ____state_1;
      __phi_halo_cell__ext_recv_reg <= phi_halo_cell__ext_recv_load_en ? phi_halo_cell__ext_recv : __phi_halo_cell__ext_recv_reg;
      __phi_halo_cell__ext_recv_valid_reg <= phi_halo_cell__ext_recv_valid_load_en ? phi_halo_cell__ext_recv_vld : __phi_halo_cell__ext_recv_valid_reg;
      __phi_halo_cell__admit_reg <= phi_halo_cell__admit_load_en ? phi_halo_cell__admit : __phi_halo_cell__admit_reg;
      __phi_halo_cell__admit_valid_reg <= phi_halo_cell__admit_valid_load_en ? phi_halo_cell__admit_vld : __phi_halo_cell__admit_valid_reg;
      __phi_halo_cell__req_reg <= phi_halo_cell__req_load_en ? __phi_halo_cell__req_buf : __phi_halo_cell__req_reg;
      __phi_halo_cell__req_valid_reg <= phi_halo_cell__req_valid_load_en ? __phi_halo_cell__req_vld_buf : __phi_halo_cell__req_valid_reg;
    end
  end
  assign phi_halo_cell__admit_rdy = phi_halo_cell__admit_load_en;
  assign phi_halo_cell__ext_recv_rdy = phi_halo_cell__ext_recv_load_en;
  assign phi_halo_cell__req = __phi_halo_cell__req_reg;
  assign phi_halo_cell__req_vld = __phi_halo_cell__req_valid_reg;
endmodule


module __axis__Top__Tx_0_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phi_halo_cell__north,
  input wire phi_halo_cell__north_vld,
  input wire phi_halo_cell__north_send_rdy,
  output wire phi_halo_cell__north_rdy,
  output wire [32:0] phi_halo_cell__north_send,
  output wire phi_halo_cell__north_send_vld
);
  wire [127:0] __phi_halo_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__north_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_14062 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__north_reg;
  reg __phi_halo_cell__north_valid_reg;
  reg [32:0] __phi_halo_cell__north_send_reg;
  reg __phi_halo_cell__north_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__north_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__north_send_valid_inv;
  wire nor_14074;
  wire not_14075;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_14084;
  wire [2:0] one_hot_14085;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_14124;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_14127;
  wire [127:0] payload;
  wire [1:0] concat_14140;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_15740;
  wire or_15744;
  wire [7:0] one_hot_sel_14128;
  wire and_14148;
  wire [127:0] one_hot_sel_14135;
  wire [7:0] one_hot_sel_14141;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_14062;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_14074 = ~(last | ____state_0);
  assign not_14075 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_14074};
  assign ____state_6__next_value_predicates = {not_14075, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_14084 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_14085 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_14124 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_14084[1] & nor_14074 == one_hot_14084[0];
  assign ____state_6__at_most_one_next_value = not_14075 == one_hot_14085[1] & last == one_hot_14085[0];
  assign concat_14127 = {and_14124, nor_14074 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_14140 = {not_14075 & p0_stage_done, and_14124};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_15740 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15744 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_14128 = frame_header_payload_words__1 & {8{concat_14127[0]}} | 8'h00 & {8{concat_14127[1]}};
  assign and_14148 = (last | nor_14074) & p0_stage_done;
  assign one_hot_sel_14135 = payload & {128{concat_14127[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_14127[1]}};
  assign one_hot_sel_14141 = 8'h00 & {8{concat_14140[0]}} | beats_sent & {8{concat_14140[1]}};
  assign __phi_halo_cell__north_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__north_reg <= __phi_halo_cell__north_reg_init;
      __phi_halo_cell__north_valid_reg <= 1'h0;
      __phi_halo_cell__north_send_reg <= __phi_halo_cell__north_send_reg_init;
      __phi_halo_cell__north_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_14075 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_14141 : ____state_6;
      ____state_1 <= and_14148 ? one_hot_sel_14128 : ____state_1;
      ____state_5 <= and_14148 ? one_hot_sel_14135 : ____state_5;
      __phi_halo_cell__north_reg <= phi_halo_cell__north_load_en ? phi_halo_cell__north : __phi_halo_cell__north_reg;
      __phi_halo_cell__north_valid_reg <= phi_halo_cell__north_valid_load_en ? phi_halo_cell__north_vld : __phi_halo_cell__north_valid_reg;
      __phi_halo_cell__north_send_reg <= phi_halo_cell__north_send_load_en ? __phi_halo_cell__north_send_buf : __phi_halo_cell__north_send_reg;
      __phi_halo_cell__north_send_valid_reg <= phi_halo_cell__north_send_valid_load_en ? __phi_halo_cell__north_send_vld_buf : __phi_halo_cell__north_send_valid_reg;
    end
  end
  assign phi_halo_cell__north_rdy = phi_halo_cell__north_load_en;
  assign phi_halo_cell__north_send = __phi_halo_cell__north_send_reg;
  assign phi_halo_cell__north_send_vld = __phi_halo_cell__north_send_valid_reg;
endmodule


module __axis__Top__Tx_1_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phi_halo_cell__east,
  input wire phi_halo_cell__east_vld,
  input wire phi_halo_cell__east_send_rdy,
  output wire phi_halo_cell__east_rdy,
  output wire [32:0] phi_halo_cell__east_send,
  output wire phi_halo_cell__east_send_vld
);
  wire [127:0] __phi_halo_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__east_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_14197 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__east_reg;
  reg __phi_halo_cell__east_valid_reg;
  reg [32:0] __phi_halo_cell__east_send_reg;
  reg __phi_halo_cell__east_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__east_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__east_send_valid_inv;
  wire nor_14209;
  wire not_14210;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_14219;
  wire [2:0] one_hot_14220;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_14259;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_14262;
  wire [127:0] payload;
  wire [1:0] concat_14275;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_15746;
  wire or_15750;
  wire [7:0] one_hot_sel_14263;
  wire and_14283;
  wire [127:0] one_hot_sel_14270;
  wire [7:0] one_hot_sel_14276;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_14197;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_14209 = ~(last | ____state_0);
  assign not_14210 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_14209};
  assign ____state_6__next_value_predicates = {not_14210, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_14219 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_14220 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_14259 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_14219[1] & nor_14209 == one_hot_14219[0];
  assign ____state_6__at_most_one_next_value = not_14210 == one_hot_14220[1] & last == one_hot_14220[0];
  assign concat_14262 = {and_14259, nor_14209 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_14275 = {not_14210 & p0_stage_done, and_14259};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_15746 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15750 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_14263 = frame_header_payload_words__1 & {8{concat_14262[0]}} | 8'h00 & {8{concat_14262[1]}};
  assign and_14283 = (last | nor_14209) & p0_stage_done;
  assign one_hot_sel_14270 = payload & {128{concat_14262[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_14262[1]}};
  assign one_hot_sel_14276 = 8'h00 & {8{concat_14275[0]}} | beats_sent & {8{concat_14275[1]}};
  assign __phi_halo_cell__east_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__east_reg <= __phi_halo_cell__east_reg_init;
      __phi_halo_cell__east_valid_reg <= 1'h0;
      __phi_halo_cell__east_send_reg <= __phi_halo_cell__east_send_reg_init;
      __phi_halo_cell__east_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_14210 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_14276 : ____state_6;
      ____state_1 <= and_14283 ? one_hot_sel_14263 : ____state_1;
      ____state_5 <= and_14283 ? one_hot_sel_14270 : ____state_5;
      __phi_halo_cell__east_reg <= phi_halo_cell__east_load_en ? phi_halo_cell__east : __phi_halo_cell__east_reg;
      __phi_halo_cell__east_valid_reg <= phi_halo_cell__east_valid_load_en ? phi_halo_cell__east_vld : __phi_halo_cell__east_valid_reg;
      __phi_halo_cell__east_send_reg <= phi_halo_cell__east_send_load_en ? __phi_halo_cell__east_send_buf : __phi_halo_cell__east_send_reg;
      __phi_halo_cell__east_send_valid_reg <= phi_halo_cell__east_send_valid_load_en ? __phi_halo_cell__east_send_vld_buf : __phi_halo_cell__east_send_valid_reg;
    end
  end
  assign phi_halo_cell__east_rdy = phi_halo_cell__east_load_en;
  assign phi_halo_cell__east_send = __phi_halo_cell__east_send_reg;
  assign phi_halo_cell__east_send_vld = __phi_halo_cell__east_send_valid_reg;
endmodule


module __axis__Top__Tx_2_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phi_halo_cell__west,
  input wire phi_halo_cell__west_vld,
  input wire phi_halo_cell__west_send_rdy,
  output wire phi_halo_cell__west_rdy,
  output wire [32:0] phi_halo_cell__west_send,
  output wire phi_halo_cell__west_send_vld
);
  wire [127:0] __phi_halo_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__west_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_14332 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__west_reg;
  reg __phi_halo_cell__west_valid_reg;
  reg [32:0] __phi_halo_cell__west_send_reg;
  reg __phi_halo_cell__west_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__west_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__west_send_valid_inv;
  wire nor_14344;
  wire not_14345;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_14354;
  wire [2:0] one_hot_14355;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_14394;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_14397;
  wire [127:0] payload;
  wire [1:0] concat_14410;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_15752;
  wire or_15756;
  wire [7:0] one_hot_sel_14398;
  wire and_14418;
  wire [127:0] one_hot_sel_14405;
  wire [7:0] one_hot_sel_14411;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_14332;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_14344 = ~(last | ____state_0);
  assign not_14345 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_14344};
  assign ____state_6__next_value_predicates = {not_14345, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_14354 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_14355 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_14394 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_14354[1] & nor_14344 == one_hot_14354[0];
  assign ____state_6__at_most_one_next_value = not_14345 == one_hot_14355[1] & last == one_hot_14355[0];
  assign concat_14397 = {and_14394, nor_14344 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_14410 = {not_14345 & p0_stage_done, and_14394};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_15752 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15756 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_14398 = frame_header_payload_words__1 & {8{concat_14397[0]}} | 8'h00 & {8{concat_14397[1]}};
  assign and_14418 = (last | nor_14344) & p0_stage_done;
  assign one_hot_sel_14405 = payload & {128{concat_14397[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_14397[1]}};
  assign one_hot_sel_14411 = 8'h00 & {8{concat_14410[0]}} | beats_sent & {8{concat_14410[1]}};
  assign __phi_halo_cell__west_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__west_reg <= __phi_halo_cell__west_reg_init;
      __phi_halo_cell__west_valid_reg <= 1'h0;
      __phi_halo_cell__west_send_reg <= __phi_halo_cell__west_send_reg_init;
      __phi_halo_cell__west_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_14345 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_14411 : ____state_6;
      ____state_1 <= and_14418 ? one_hot_sel_14398 : ____state_1;
      ____state_5 <= and_14418 ? one_hot_sel_14405 : ____state_5;
      __phi_halo_cell__west_reg <= phi_halo_cell__west_load_en ? phi_halo_cell__west : __phi_halo_cell__west_reg;
      __phi_halo_cell__west_valid_reg <= phi_halo_cell__west_valid_load_en ? phi_halo_cell__west_vld : __phi_halo_cell__west_valid_reg;
      __phi_halo_cell__west_send_reg <= phi_halo_cell__west_send_load_en ? __phi_halo_cell__west_send_buf : __phi_halo_cell__west_send_reg;
      __phi_halo_cell__west_send_valid_reg <= phi_halo_cell__west_send_valid_load_en ? __phi_halo_cell__west_send_vld_buf : __phi_halo_cell__west_send_valid_reg;
    end
  end
  assign phi_halo_cell__west_rdy = phi_halo_cell__west_load_en;
  assign phi_halo_cell__west_send = __phi_halo_cell__west_send_reg;
  assign phi_halo_cell__west_send_vld = __phi_halo_cell__west_send_valid_reg;
endmodule


module __axis__Top__Tx_3_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phi_halo_cell__south,
  input wire phi_halo_cell__south_vld,
  input wire phi_halo_cell__south_send_rdy,
  output wire phi_halo_cell__south_rdy,
  output wire [32:0] phi_halo_cell__south_send,
  output wire phi_halo_cell__south_send_vld
);
  wire [127:0] __phi_halo_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__south_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_14467 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__south_reg;
  reg __phi_halo_cell__south_valid_reg;
  reg [32:0] __phi_halo_cell__south_send_reg;
  reg __phi_halo_cell__south_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__south_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__south_send_valid_inv;
  wire nor_14479;
  wire not_14480;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_14489;
  wire [2:0] one_hot_14490;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_14529;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_14532;
  wire [127:0] payload;
  wire [1:0] concat_14545;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_15758;
  wire or_15762;
  wire [7:0] one_hot_sel_14533;
  wire and_14553;
  wire [127:0] one_hot_sel_14540;
  wire [7:0] one_hot_sel_14546;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_14467;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_14479 = ~(last | ____state_0);
  assign not_14480 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_14479};
  assign ____state_6__next_value_predicates = {not_14480, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_14489 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_14490 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_14529 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_14489[1] & nor_14479 == one_hot_14489[0];
  assign ____state_6__at_most_one_next_value = not_14480 == one_hot_14490[1] & last == one_hot_14490[0];
  assign concat_14532 = {and_14529, nor_14479 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_14545 = {not_14480 & p0_stage_done, and_14529};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_15758 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15762 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_14533 = frame_header_payload_words__1 & {8{concat_14532[0]}} | 8'h00 & {8{concat_14532[1]}};
  assign and_14553 = (last | nor_14479) & p0_stage_done;
  assign one_hot_sel_14540 = payload & {128{concat_14532[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_14532[1]}};
  assign one_hot_sel_14546 = 8'h00 & {8{concat_14545[0]}} | beats_sent & {8{concat_14545[1]}};
  assign __phi_halo_cell__south_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__south_reg <= __phi_halo_cell__south_reg_init;
      __phi_halo_cell__south_valid_reg <= 1'h0;
      __phi_halo_cell__south_send_reg <= __phi_halo_cell__south_send_reg_init;
      __phi_halo_cell__south_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_14480 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_14546 : ____state_6;
      ____state_1 <= and_14553 ? one_hot_sel_14533 : ____state_1;
      ____state_5 <= and_14553 ? one_hot_sel_14540 : ____state_5;
      __phi_halo_cell__south_reg <= phi_halo_cell__south_load_en ? phi_halo_cell__south : __phi_halo_cell__south_reg;
      __phi_halo_cell__south_valid_reg <= phi_halo_cell__south_valid_load_en ? phi_halo_cell__south_vld : __phi_halo_cell__south_valid_reg;
      __phi_halo_cell__south_send_reg <= phi_halo_cell__south_send_load_en ? __phi_halo_cell__south_send_buf : __phi_halo_cell__south_send_reg;
      __phi_halo_cell__south_send_valid_reg <= phi_halo_cell__south_send_valid_load_en ? __phi_halo_cell__south_send_vld_buf : __phi_halo_cell__south_send_valid_reg;
    end
  end
  assign phi_halo_cell__south_rdy = phi_halo_cell__south_load_en;
  assign phi_halo_cell__south_send = __phi_halo_cell__south_send_reg;
  assign phi_halo_cell__south_send_vld = __phi_halo_cell__south_send_valid_reg;
endmodule


module __phi_halo_cell__Top_0_next__1(
  input wire clk,
  input wire reset
);

endmodule


module __phi_halo_cell__Top__Service_0_next(
  input wire clk,
  input wire reset,
  input wire phi_halo_cell__admit_rdy,
  input wire phi_halo_cell__east_rdy,
  input wire phi_halo_cell__north_rdy,
  input wire [127:0] phi_halo_cell__req,
  input wire phi_halo_cell__req_vld,
  input wire phi_halo_cell__south_rdy,
  input wire phi_halo_cell__west_rdy,
  output wire phi_halo_cell__admit,
  output wire phi_halo_cell__admit_vld,
  output wire [127:0] phi_halo_cell__east,
  output wire phi_halo_cell__east_vld,
  output wire [127:0] phi_halo_cell__north,
  output wire phi_halo_cell__north_vld,
  output wire phi_halo_cell__req_rdy,
  output wire [127:0] phi_halo_cell__south,
  output wire phi_halo_cell__south_vld,
  output wire [127:0] phi_halo_cell__west,
  output wire phi_halo_cell__west_vld
);
  function automatic [1:0] priority_sel_2b_2way (input reg [1:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] default_value);
    begin
      casez (sel)
        2'b?1: begin
          priority_sel_2b_2way = case0;
        end
        2'b10: begin
          priority_sel_2b_2way = case1;
        end
        2'b00: begin
          priority_sel_2b_2way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_2way = 2'dx;
        end
      endcase
    end
  endfunction
  function automatic priority_sel_1b_2way (input reg [1:0] sel, input reg case0, input reg case1, input reg default_value);
    begin
      casez (sel)
        2'b?1: begin
          priority_sel_1b_2way = case0;
        end
        2'b10: begin
          priority_sel_1b_2way = case1;
        end
        2'b00: begin
          priority_sel_1b_2way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_1b_2way = 1'dx;
        end
      endcase
    end
  endfunction
  function automatic priority_sel_1b_5way (input reg [4:0] sel, input reg case0, input reg case1, input reg case2, input reg case3, input reg case4, input reg default_value);
    begin
      casez (sel)
        5'b????1: begin
          priority_sel_1b_5way = case0;
        end
        5'b???10: begin
          priority_sel_1b_5way = case1;
        end
        5'b??100: begin
          priority_sel_1b_5way = case2;
        end
        5'b?1000: begin
          priority_sel_1b_5way = case3;
        end
        5'b10000: begin
          priority_sel_1b_5way = case4;
        end
        5'b0_0000: begin
          priority_sel_1b_5way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_1b_5way = 1'dx;
        end
      endcase
    end
  endfunction
  function automatic [1:0] priority_sel_2b_5way (input reg [4:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] case3, input reg [1:0] case4, input reg [1:0] default_value);
    begin
      casez (sel)
        5'b????1: begin
          priority_sel_2b_5way = case0;
        end
        5'b???10: begin
          priority_sel_2b_5way = case1;
        end
        5'b??100: begin
          priority_sel_2b_5way = case2;
        end
        5'b?1000: begin
          priority_sel_2b_5way = case3;
        end
        5'b10000: begin
          priority_sel_2b_5way = case4;
        end
        5'b0_0000: begin
          priority_sel_2b_5way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_5way = 2'dx;
        end
      endcase
    end
  endfunction
  // lint_off MULTIPLY
  function automatic [63:0] umul64b_32b_x_32b (input reg [31:0] lhs, input reg [31:0] rhs);
    begin
      umul64b_32b_x_32b = lhs * rhs;
    end
  endfunction
  // lint_on MULTIPLY
  function automatic [95:0] priority_sel_96b_2way (input reg [1:0] sel, input reg [95:0] case0, input reg [95:0] case1, input reg [95:0] default_value);
    begin
      casez (sel)
        2'b?1: begin
          priority_sel_96b_2way = case0;
        end
        2'b10: begin
          priority_sel_96b_2way = case1;
        end
        2'b00: begin
          priority_sel_96b_2way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_96b_2way = 96'dx;
        end
      endcase
    end
  endfunction
  wire ____state_13_tuple_element_0_init[0:4];
  assign ____state_13_tuple_element_0_init[0] = 1'h0;
  assign ____state_13_tuple_element_0_init[1] = 1'h0;
  assign ____state_13_tuple_element_0_init[2] = 1'h0;
  assign ____state_13_tuple_element_0_init[3] = 1'h0;
  assign ____state_13_tuple_element_0_init[4] = 1'h0;
  wire [95:0] ____state_13_tuple_element_1_tuple_element_1_init[0:4];
  assign ____state_13_tuple_element_1_tuple_element_1_init[0] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_13_tuple_element_1_tuple_element_1_init[1] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_13_tuple_element_1_tuple_element_1_init[2] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_13_tuple_element_1_tuple_element_1_init[3] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_13_tuple_element_1_tuple_element_1_init[4] = 96'h0000_0000_0000_0000_0000_0000;
  wire [7:0] ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[0:4];
  assign ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[0] = 8'h00;
  assign ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[1] = 8'h00;
  assign ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[2] = 8'h00;
  assign ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[3] = 8'h00;
  assign ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[4] = 8'h00;
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_14661 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  reg ____state_16;
  reg ____state_17;
  reg ____state_15;
  reg ____state_13_tuple_element_0[0:4];
  reg [7:0] ____state_14;
  reg [95:0] ____state_13_tuple_element_1_tuple_element_1[0:4];
  reg [7:0] ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0:4];
  reg [31:0] ____state_7;
  reg [31:0] ____state_2;
  reg [31:0] ____state_3;
  reg [1:0] ____state_0;
  reg [1:0] ____state_10;
  reg [1:0] ____state_6;
  reg [31:0] ____state_12;
  reg [31:0] ____state_8;
  reg [31:0] ____state_11;
  reg [31:0] ____state_9;
  reg [31:0] ____state_5_1;
  reg [31:0] ____state_5_0;
  reg [31:0] ____state_4_1;
  reg [31:0] ____state_4_0;
  reg __phi_halo_cell__admit_has_been_sent_reg;
  reg __phi_halo_cell__north_has_been_sent_reg;
  reg __phi_halo_cell__east_has_been_sent_reg;
  reg __phi_halo_cell__west_has_been_sent_reg;
  reg __phi_halo_cell__south_has_been_sent_reg;
  reg [127:0] __phi_halo_cell__req_reg;
  reg __phi_halo_cell__req_valid_reg;
  reg __phi_halo_cell__admit_reg;
  reg __phi_halo_cell__admit_valid_reg;
  reg [127:0] __phi_halo_cell__north_reg;
  reg __phi_halo_cell__north_valid_reg;
  reg [127:0] __phi_halo_cell__east_reg;
  reg __phi_halo_cell__east_valid_reg;
  reg [127:0] __phi_halo_cell__west_reg;
  reg __phi_halo_cell__west_valid_reg;
  reg [127:0] __phi_halo_cell__south_reg;
  reg __phi_halo_cell__south_valid_reg;
  wire nor_14659;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_14670;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_14686;
  wire [31:0] concat_14687;
  wire ugt_14689;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_14691;
  wire postponed__4;
  wire ugt_14695;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_2831_0__2_case_0_case_1_case_0;
  wire or_reduce_14699;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_14710;
  wire postponed;
  wire [95:0] sel_14719;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_14722;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Value1_1;
  wire [31:0] _12_source;
  wire [31:0] _9_source;
  wire [31:0] _6__5_source;
  wire [31:0] _3__5_source;
  wire [7:0] sel_14731;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire _0__15;
  wire _1__5;
  wire _2__5;
  wire [31:0] _7__3;
  wire [1:0] unexpand_for_next_value_2831_0__2_case_0_case_0_case_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire eq_14743;
  wire _8__3;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [1:0] unexpand_for_next_value_2831_0__2_case_0_case_0_case_2;
  wire [30:0] add_14747;
  wire eq_14749;
  wire nor_14750;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire and_14752;
  wire _21__2;
  wire eq_14754;
  wire [31:0] _1;
  wire or_14759;
  wire eq_14760;
  wire nand_14761;
  wire eq_14762;
  wire or_14764;
  wire [31:0] _2__1;
  wire eq_14767;
  wire eq_14768;
  wire _0__11;
  wire [1:0] concat_14774;
  wire [1:0] concat_14776;
  wire and_14778;
  wire _4__1;
  wire postponed_slot_tup0;
  wire eligible_0;
  wire invalid_input;
  wire eq_14791;
  wire _6__1;
  wire [1:0] priority_sel_14795;
  wire _3;
  wire _19;
  wire _47;
  wire found;
  wire compacted_4_tup0;
  wire nand_14811;
  wire and_14814;
  wire dispatchable;
  wire [1:0] priority_sel_14824;
  wire [1:0] concat_14826;
  wire [1:0] directive;
  wire [1:0] next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_14876;
  wire [1:0] candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire nor_14840;
  wire phase_changed;
  wire [31:0] Xls_clause_1_Value_1;
  wire and_14847;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire _12__2;
  wire and_14853;
  wire and_14855;
  wire final_slots_0_case_cmp;
  wire and_14863;
  wire and_14865;
  wire and_14868;
  wire and_14869;
  wire and_14870;
  wire eq_14871;
  wire [18:0] _1__1;
  wire __phi_halo_cell__admit_buf;
  wire __phi_halo_cell__admit_not_has_been_sent;
  wire phi_halo_cell__admit_valid_inv;
  wire __phi_halo_cell__east_vld_buf;
  wire __phi_halo_cell__north_not_has_been_sent;
  wire phi_halo_cell__north_valid_inv;
  wire __phi_halo_cell__east_not_has_been_sent;
  wire phi_halo_cell__east_valid_inv;
  wire __phi_halo_cell__west_not_has_been_sent;
  wire phi_halo_cell__west_valid_inv;
  wire __phi_halo_cell__south_not_has_been_sent;
  wire phi_halo_cell__south_valid_inv;
  wire and_14883;
  wire and_14885;
  wire Xls_clause_1_NewBestDirection_1_0_case_cmp;
  wire _15__1;
  wire candidate_occupied_0_case_cmp;
  wire and_14893;
  wire candidate_slots_0_case_cmp;
  wire and_14896;
  wire and_14897;
  wire or_14898;
  wire __phi_halo_cell__admit_valid_and_not_has_been_sent;
  wire phi_halo_cell__admit_valid_load_en;
  wire __phi_halo_cell__north_valid_and_not_has_been_sent;
  wire phi_halo_cell__north_valid_load_en;
  wire __phi_halo_cell__east_valid_and_not_has_been_sent;
  wire phi_halo_cell__east_valid_load_en;
  wire __phi_halo_cell__west_valid_and_not_has_been_sent;
  wire phi_halo_cell__west_valid_load_en;
  wire __phi_halo_cell__south_valid_and_not_has_been_sent;
  wire phi_halo_cell__south_valid_load_en;
  wire and_14914;
  wire and_14915;
  wire and_14916;
  wire and_14917;
  wire and_14918;
  wire and_14919;
  wire and_14920;
  wire and_14921;
  wire and_14922;
  wire and_14923;
  wire and_14924;
  wire and_14925;
  wire and_14926;
  wire and_14927;
  wire and_14928;
  wire and_14929;
  wire and_14930;
  wire and_14931;
  wire and_14932;
  wire and_14933;
  wire and_14934;
  wire and_14935;
  wire and_14936;
  wire and_14937;
  wire and_14938;
  wire and_14939;
  wire and_14940;
  wire [31:0] _12;
  wire _7__10;
  wire _9__5;
  wire NextRandom_1__5;
  wire phi_halo_cell__admit_not_pred;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__east_not_pred;
  wire phi_halo_cell__north_load_en;
  wire phi_halo_cell__east_load_en;
  wire phi_halo_cell__west_load_en;
  wire phi_halo_cell__south_load_en;
  wire [1:0] ____state_3__next_value_predicates;
  wire [1:0] ____state_7__next_value_predicates;
  wire [1:0] ____state_8__next_value_predicates;
  wire [2:0] ____state_9__next_value_predicates;
  wire [1:0] ____state_11__next_value_predicates;
  wire [1:0] ____state_14__next_value_predicates;
  wire [1:0] ____state_16__next_value_predicates;
  wire [10:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [4:0] ____state_13_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_13_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [31:0] _8;
  wire [31:0] _35;
  wire _16;
  wire Move_1__1;
  wire _19__2;
  wire _22__1;
  wire _25;
  wire [2:0] one_hot_14998;
  wire [2:0] one_hot_14999;
  wire [2:0] one_hot_15000;
  wire [3:0] one_hot_15001;
  wire [2:0] one_hot_15002;
  wire [2:0] one_hot_15003;
  wire [2:0] one_hot_15004;
  wire [11:0] one_hot_15005;
  wire [2:0] one_hot_15006;
  wire [2:0] one_hot_15007;
  wire [5:0] one_hot_15008;
  wire [8:0] one_hot_15009;
  wire [14:0] _2__15;
  wire [30:0] add_14952;
  wire [63:0] umul_14953;
  wire [95:0] array_index_14977;
  wire [95:0] array_index_14979;
  wire [95:0] array_index_14981;
  wire [7:0] array_index_14985;
  wire [7:0] array_index_14987;
  wire [7:0] array_index_14989;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_14995;
  wire ne_15032;
  wire or_reduce_15034;
  wire ugt_15036;
  wire phi_halo_cell__req_valid_inv;
  wire and_15289;
  wire and_15290;
  wire and_15296;
  wire and_15304;
  wire _40__1;
  wire admission_pending;
  wire [15:0] add_15050;
  wire and_15389;
  wire and_15390;
  wire and_15391;
  wire and_15392;
  wire [31:0] concat_15118;
  wire compacted_0_tup0;
  wire compacted_1_tup0;
  wire compacted_2_tup0;
  wire compacted_3_tup0;
  wire [95:0] compacted_0_tup1_tup1;
  wire [95:0] compacted_1_tup1_tup1;
  wire [95:0] compacted_2_tup1_tup1;
  wire [95:0] compacted_3_tup1_tup1;
  wire [95:0] compacted_4_tup1_tup1;
  wire [7:0] compacted_0_tup1_tup0_tup3;
  wire [7:0] compacted_1_tup1_tup0_tup3;
  wire [7:0] compacted_2_tup1_tup0_tup3;
  wire [7:0] compacted_3_tup1_tup0_tup3;
  wire [95:0] concat_15013;
  wire phi_halo_cell__req_valid_load_en;
  wire ____state_3__at_most_one_next_value;
  wire ____state_7__at_most_one_next_value;
  wire ____state_8__at_most_one_next_value;
  wire ____state_9__at_most_one_next_value;
  wire ____state_11__at_most_one_next_value;
  wire ____state_14__at_most_one_next_value;
  wire ____state_16__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_10__at_most_one_next_value;
  wire ____state_13_tuple_element_0__at_most_one_next_value;
  wire ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_15292;
  wire [31:0] _42;
  wire [1:0] concat_15299;
  wire [1:0] concat_15306;
  wire [2:0] concat_15314;
  wire [1:0] concat_15321;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire [31:0] _40;
  wire [16:0] NextRandom_1__11;
  wire [9:0] NextRandom_1__10;
  wire [4:0] NextRandom_1__9;
  wire [1:0] concat_15331;
  wire [1:0] concat_15341;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_15129;
  wire [31:0] sign_ext_15130;
  wire [10:0] concat_15370;
  wire [1:0] concat_15377;
  wire [1:0] unexpand_for_next_value_2831_6__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_15384;
  wire [1:0] unexpand_for_next_value_2831_10__2_case_0_case_1_case_2_case_1_case_0;
  wire [4:0] concat_15394;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_15407;
  wire [95:0] postponed_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [95:0] compacted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [7:0] postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [7:0] compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__admit_valid_and_ready_txfr;
  wire __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__north_valid_and_ready_txfr;
  wire __phi_halo_cell__east_valid_and_ready_txfr;
  wire __phi_halo_cell__west_valid_and_ready_txfr;
  wire __phi_halo_cell__south_valid_and_ready_txfr;
  wire [31:0] tuple_15099;
  wire phi_halo_cell__req_load_en;
  wire or_15764;
  wire or_15766;
  wire or_15768;
  wire or_15770;
  wire or_15772;
  wire or_15774;
  wire or_15776;
  wire or_15778;
  wire or_15780;
  wire or_15782;
  wire or_15784;
  wire or_15786;
  wire [31:0] _8__1;
  wire and_15430;
  wire [31:0] one_hot_sel_15293;
  wire and_15433;
  wire [31:0] one_hot_sel_15300;
  wire and_15436;
  wire [31:0] one_hot_sel_15307;
  wire and_15439;
  wire [31:0] one_hot_sel_15315;
  wire and_15442;
  wire [31:0] one_hot_sel_15322;
  wire and_15445;
  wire [31:0] NextRandom_1;
  wire and_15447;
  wire [7:0] one_hot_sel_15332;
  wire and_15450;
  wire and_15182;
  wire and_15452;
  wire one_hot_sel_15342;
  wire and_15455;
  wire or_15180;
  wire [31:0] _31;
  wire and_15458;
  wire [31:0] _37;
  wire [31:0] and_15200;
  wire and_15462;
  wire [31:0] and_15201;
  wire [1:0] one_hot_sel_15371;
  wire and_15467;
  wire [1:0] one_hot_sel_15378;
  wire and_15470;
  wire [1:0] one_hot_sel_15385;
  wire and_15473;
  wire one_hot_sel_15395[0:4];
  wire and_15476;
  wire [95:0] one_hot_sel_15408[0:4];
  wire and_15479;
  wire [7:0] one_hot_sel_15421[0:4];
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_not_stage_load;
  wire __phi_halo_cell__north_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_has_been_sent_reg_load_en;
  wire __phi_halo_cell__west_has_been_sent_reg_load_en;
  wire __phi_halo_cell__south_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire [127:0] effects_east;
  wire [127:0] effects_west;
  wire [127:0] effects_south;
  assign nor_14659 = ~(____state_17 | ____state_15 | ~____state_16);
  assign received = nor_14659 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_14661;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_14670 = frame_header__1_payload_words == 8'h03;
  assign tag_ok = frame_header_op == 8'h03 & eq_14670 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02 | frame_header_op == MAILBOX_CAPACITY & eq_14670;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_14 + {7'h00, accepted};
  assign and_14686 = ~accepted & ____state_13_tuple_element_0[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign concat_14687 = {24'h00_0000, ____state_14};
  assign ugt_14689 = admitted_occupied > 8'h04;
  assign or_reduce_14691 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_14695 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_14689 | postponed__4);
  assign unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 = 2'h0;
  assign or_reduce_14699 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_14691 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_14695 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_14699 | postponed__1);
  assign eq_14710 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_14719 = accepted ? phi_halo_cell__req_select[95:0] : ____state_13_tuple_element_1_tuple_element_1[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_2831_0__2_case_0_case_1_case_0}))} & {8{eq_14710 | postponed}};
  assign bit_slice_14722 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_14722 > 3'h4 ? 3'h4 : bit_slice_14722];
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _12_source = 32'h0000_0001;
  assign _9_source = 32'h0000_0002;
  assign _6__5_source = 32'h0000_0004;
  assign _3__5_source = 32'h0000_0008;
  assign sel_14731 = accepted ? frame_header_op : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__15 = Xls_clause_1_Value1_1 == _12_source;
  assign _1__5 = Xls_clause_1_Value1_1 == _9_source;
  assign _2__5 = Xls_clause_1_Value1_1 == _6__5_source;
  assign _7__3 = ____state_7 & Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 = 2'h1;
  assign eq_14743 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _8__3 = _7__3 == 32'h0000_0000;
  assign Xls_clause_1_NewSeen_1 = ____state_7 | Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2831_0__2_case_0_case_0_case_2 = 2'h2;
  assign add_14747 = ____state_2[30:0] + ____state_3[31:1];
  assign eq_14749 = ____state_0 == unexpand_for_next_value_2831_0__2_case_0_case_0_case_1;
  assign nor_14750 = ~(____state_0[0] | ____state_0[1]);
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_14722 > 3'h4 ? 3'h4 : bit_slice_14722];
  assign and_14752 = eq_14743 & (_0__15 | _1__5 | _2__5 | Xls_clause_1_Value1_1 == _3__5_source) & _8__3;
  assign _21__2 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign eq_14754 = ____state_0 == unexpand_for_next_value_2831_0__2_case_0_case_0_case_2;
  assign _1 = {add_14747, ____state_3[0]};
  assign or_14759 = eq_14749 | nor_14750;
  assign eq_14760 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign nand_14761 = ~(and_14752 & _21__2);
  assign eq_14762 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign or_14764 = ____state_0[0] | ____state_0[1];
  assign _2__1 = _1 + _12_source;
  assign eq_14767 = add_14747 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_14768 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign _0__11 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign concat_14774 = {eq_14754, or_14759};
  assign concat_14776 = {eq_14749, nor_14750};
  assign and_14778 = eq_14762 & ~(eq_14754 | eq_14749) & or_14764;
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__1;
  assign postponed_slot_tup0 = 1'h1;
  assign eligible_0 = ~(eq_14710 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign eq_14791 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY;
  assign _6__1 = ____state_10 == 2'h3;
  assign priority_sel_14795 = priority_sel_2b_2way(concat_14776, unexpand_for_next_value_2831_0__2_case_0_case_1_case_0, nand_14761 ? unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2831_0__2_case_0_case_0_case_2, ____state_0);
  assign _3 = eq_14767 & eq_14768;
  assign _19 = ____state_6 == 2'h3;
  assign _47 = ____state_3 == _12_source;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign compacted_4_tup0 = 1'h0;
  assign nand_14811 = ~(eq_14743 & _0__11 & _6__1);
  assign and_14814 = _3 & _19 & _47;
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_14824 = priority_sel_2b_5way({eq_14791, eq_14760, and_14778, {2{eq_14762}} & {eq_14754 | eq_14749, nor_14750}}, (_4__1 ? unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2831_0__2_case_0_case_0_case_2) & {2{~(eq_14767 & eq_14768)}}, _3 ? unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2831_0__2_case_0_case_0_case_2, unexpand_for_next_value_2831_0__2_case_0_case_0_case_2, {priority_sel_1b_2way(concat_14774, ~eq_14743, ~(eq_14743 & _0__11), postponed_slot_tup0), eq_14743 & or_14759}, {priority_sel_1b_2way(concat_14776, ~eq_14743, ~and_14752, postponed_slot_tup0), ~(~eq_14743 | ____state_0[0] | ____state_0[1])}, unexpand_for_next_value_2831_0__2_case_0_case_0_case_2);
  assign concat_14826 = {priority_sel_1b_5way({eq_14791, eq_14760 & ~eq_14754 & ~or_14759, {2{eq_14760}} & concat_14774, eq_14762}, ____state_0[1], compacted_4_tup0, nand_14811, ____state_0[1], priority_sel_14795[1], ____state_0[1]), priority_sel_1b_5way({eq_14791, eq_14760 | and_14778, {3{eq_14762}} & {eq_14754, eq_14749, nor_14750}}, and_14814, postponed_slot_tup0, compacted_4_tup0, ____state_0[0], priority_sel_14795[0], ____state_0[0])};
  assign directive = priority_sel_14824 & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? concat_14826 : ____state_0;
  assign repeat_phase = dispatchable & eq_14762 & nor_14750 & _3 & ~(~_19 | _47);
  assign invalid_repeat = repeat_phase & (directive != unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 | next_phase_squeezed != ____state_0);
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_14876 = admitted_occupied + 8'hff;
  assign candidate_phase_squeezed = effective ? concat_14826 : ____state_0;
  assign failed = invalid_input | invalid_repeat | effective & directive == unexpand_for_next_value_2831_0__2_case_0_case_0_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_14876 : admitted_occupied;
  assign nor_14840 = ~(____state_17 | ____state_15);
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign Xls_clause_1_Value_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign and_14847 = nor_14840 & effective;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_16 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_16 | ____state_14 > 8'h04);
  assign _12__2 = Xls_clause_1_Value_1 > ____state_8;
  assign and_14853 = and_14847 & eq_14791;
  assign and_14855 = and_14847 & eq_14760;
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_14863 = and_14847 & eq_14762;
  assign and_14865 = and_14853 & eq_14749;
  assign and_14868 = and_14855 & eq_14754;
  assign and_14869 = nor_14840 & final_slots_0_case_cmp;
  assign and_14870 = nor_14840 & phase_boundary;
  assign eq_14871 = priority_sel_14824 == unexpand_for_next_value_2831_0__2_case_0_case_0_case_1;
  assign _1__1 = ____state_12[31:13] ^ ____state_12[18:0];
  assign __phi_halo_cell__admit_buf = ~____state_17 & ~____state_15 & reserve__1 | ~____state_17 & ____state_15 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign __phi_halo_cell__east_vld_buf = ~(____state_17 | ~____state_15);
  assign __phi_halo_cell__north_not_has_been_sent = ~__phi_halo_cell__north_has_been_sent_reg;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign __phi_halo_cell__east_not_has_been_sent = ~__phi_halo_cell__east_has_been_sent_reg;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign __phi_halo_cell__west_not_has_been_sent = ~__phi_halo_cell__west_has_been_sent_reg;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign __phi_halo_cell__south_not_has_been_sent = ~__phi_halo_cell__south_has_been_sent_reg;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_14883 = and_14863 & nor_14750;
  assign and_14885 = and_14865 & and_14752;
  assign Xls_clause_1_NewBestDirection_1_0_case_cmp = ~_12__2;
  assign _15__1 = Xls_clause_1_Value_1 == ____state_8;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_14893 = and_14868 & eq_14743 & _0__11;
  assign candidate_slots_0_case_cmp = ~effective;
  assign and_14896 = and_14869 & effective;
  assign and_14897 = and_14870 & effective;
  assign or_14898 = directive[0] | transition_slots_default_case_cmp;
  assign __phi_halo_cell__admit_valid_and_not_has_been_sent = __phi_halo_cell__admit_buf & __phi_halo_cell__admit_not_has_been_sent;
  assign phi_halo_cell__admit_valid_load_en = phi_halo_cell__admit_rdy | phi_halo_cell__admit_valid_inv;
  assign __phi_halo_cell__north_valid_and_not_has_been_sent = __phi_halo_cell__east_vld_buf & __phi_halo_cell__north_not_has_been_sent;
  assign phi_halo_cell__north_valid_load_en = phi_halo_cell__north_rdy | phi_halo_cell__north_valid_inv;
  assign __phi_halo_cell__east_valid_and_not_has_been_sent = __phi_halo_cell__east_vld_buf & __phi_halo_cell__east_not_has_been_sent;
  assign phi_halo_cell__east_valid_load_en = phi_halo_cell__east_rdy | phi_halo_cell__east_valid_inv;
  assign __phi_halo_cell__west_valid_and_not_has_been_sent = __phi_halo_cell__east_vld_buf & __phi_halo_cell__west_not_has_been_sent;
  assign phi_halo_cell__west_valid_load_en = phi_halo_cell__west_rdy | phi_halo_cell__west_valid_inv;
  assign __phi_halo_cell__south_valid_and_not_has_been_sent = __phi_halo_cell__east_vld_buf & __phi_halo_cell__south_not_has_been_sent;
  assign phi_halo_cell__south_valid_load_en = phi_halo_cell__south_rdy | phi_halo_cell__south_valid_inv;
  assign and_14914 = and_14883 & _3 & _19;
  assign and_14915 = and_14868 & eq_14743 & _0__11 & _6__1;
  assign and_14916 = and_14883 & and_14814;
  assign and_14917 = and_14865 & ~(~(and_14752 & _12__2));
  assign and_14918 = and_14885 & Xls_clause_1_NewBestDirection_1_0_case_cmp & _15__1;
  assign and_14919 = __phi_halo_cell__east_vld_buf & ~eq_14749 & or_14764;
  assign and_14920 = nor_14840 & candidate_occupied_0_case_cmp;
  assign and_14921 = nor_14840 & candidate_occupied_1_case_cmp;
  assign and_14922 = and_14863 & eq_14749;
  assign and_14923 = and_14863 & eq_14754;
  assign and_14924 = and_14855 & nor_14750;
  assign and_14925 = and_14855 & eq_14749;
  assign and_14926 = and_14853 & nor_14750;
  assign and_14927 = and_14883 & ~(_3 & _19 & _47);
  assign and_14928 = and_14868 & nand_14811;
  assign and_14929 = and_14865 & ~nand_14761;
  assign and_14930 = and_14865 & nand_14761;
  assign and_14931 = and_14883 & _3 & ~_19;
  assign and_14932 = and_14893 & ~_6__1;
  assign and_14933 = and_14869 & candidate_slots_0_case_cmp;
  assign and_14934 = and_14896 & transition_slots_predicate_piece_0;
  assign and_14935 = and_14896 & eq_14871;
  assign and_14936 = and_14896 & transition_slots_default_case_cmp;
  assign and_14937 = and_14870 & candidate_slots_0_case_cmp;
  assign and_14938 = and_14897 & transition_slots_predicate_piece_0;
  assign and_14939 = and_14897 & eq_14871 & or_14898;
  assign and_14940 = and_14897 & ~eq_14871 & or_14898;
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign _7__10 = ____state_11 == _12_source;
  assign _9__5 = ____state_9 != 32'h0000_0000;
  assign NextRandom_1__5 = _1__1[18] ^ _1__1[13];
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_14914, and_14915};
  assign ____state_7__next_value_predicates = {and_14916, and_14885};
  assign ____state_8__next_value_predicates = {and_14916, and_14917};
  assign ____state_9__next_value_predicates = {and_14916, and_14917, and_14918};
  assign ____state_11__next_value_predicates = {and_14919, and_14893};
  assign ____state_14__next_value_predicates = {and_14920, and_14921};
  assign ____state_16__next_value_predicates = {nor_14840, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_14922, and_14923, and_14924, and_14925, and_14926, and_14916, and_14927, and_14915, and_14928, and_14929, and_14930};
  assign ____state_6__next_value_predicates = {and_14931, and_14914};
  assign ____state_10__next_value_predicates = {and_14932, and_14915};
  assign ____state_13_tuple_element_0__next_value_predicates = {and_14870, and_14933, and_14934, and_14935, and_14936};
  assign ____state_13_tuple_element_1_tuple_element_1__next_value_predicates = {and_14933, and_14934, and_14935, and_14936, and_14937, and_14938, and_14939, and_14940};
  assign _8 = ____state_5_0 + Xls_clause_1_Value_1;
  assign _35 = ____state_4_0 + _12;
  assign _16 = ____state_9 == _12_source;
  assign Move_1__1 = _7__10 & _9__5 & NextRandom_1__5;
  assign _19__2 = ____state_9 == _9_source;
  assign _22__1 = ____state_9 == _6__5_source;
  assign _25 = ____state_9 == _3__5_source;
  assign one_hot_14998 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_14999 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_15000 = {____state_8__next_value_predicates[1:0] == 2'h0, ____state_8__next_value_predicates[1] && !____state_8__next_value_predicates[0], ____state_8__next_value_predicates[0]};
  assign one_hot_15001 = {____state_9__next_value_predicates[2:0] == 3'h0, ____state_9__next_value_predicates[2] && ____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_15002 = {____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_15003 = {____state_14__next_value_predicates[1:0] == 2'h0, ____state_14__next_value_predicates[1] && !____state_14__next_value_predicates[0], ____state_14__next_value_predicates[0]};
  assign one_hot_15004 = {____state_16__next_value_predicates[1:0] == 2'h0, ____state_16__next_value_predicates[1] && !____state_16__next_value_predicates[0], ____state_16__next_value_predicates[0]};
  assign one_hot_15005 = {____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_15006 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_15007 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_15008 = {____state_13_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_0__next_value_predicates[4] && ____state_13_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_0__next_value_predicates[3] && ____state_13_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_0__next_value_predicates[2] && ____state_13_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_0__next_value_predicates[1] && !____state_13_tuple_element_0__next_value_predicates[0], ____state_13_tuple_element_0__next_value_predicates[0]};
  assign one_hot_15009 = {____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign _2__15 = {_1__1[1:0], ____state_12[12:0]} ^ _1__1[18:4];
  assign add_14952 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_14953 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_14977 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_14979 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_14981 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_14985 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_14987 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_14989 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_14995 = ____state_4_1[30:0] + _8[31:1];
  assign ne_15032 = bit_slice_14722 != 3'h0;
  assign or_reduce_15034 = |selected[7:1];
  assign ugt_15036 = bit_slice_14722 > 3'h2;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_15289 = and_14914 & p0_all_active_outputs_ready;
  assign and_15290 = and_14915 & p0_all_active_outputs_ready;
  assign and_15296 = and_14916 & p0_all_active_outputs_ready;
  assign and_15304 = and_14917 & p0_all_active_outputs_ready;
  assign _40__1 = ____state_11[0] ^ Move_1__1;
  assign admission_pending = ~(~____state_16 | received);
  assign add_15050 = ____state_11[15:0] + {unexpand_for_next_value_2831_0__2_case_0_case_1_case_0, ____state_4_0[31:18]};
  assign and_15389 = and_14933 & p0_all_active_outputs_ready;
  assign and_15390 = and_14934 & p0_all_active_outputs_ready;
  assign and_15391 = and_14935 & p0_all_active_outputs_ready;
  assign and_15392 = and_14936 & p0_all_active_outputs_ready;
  assign concat_15118 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_15032 ? postponed : or_reduce_14699 & postponed__1;
  assign compacted_1_tup0 = or_reduce_15034 ? postponed__1 : ugt_14695 & postponed__2;
  assign compacted_2_tup0 = ugt_15036 ? postponed__2 : or_reduce_14691 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_14689 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_15032 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_14977 & {96{or_reduce_14699}};
  assign compacted_1_tup1_tup1 = or_reduce_15034 ? array_index_14977 : array_index_14979 & {96{ugt_14695}};
  assign compacted_2_tup1_tup1 = ugt_15036 ? array_index_14979 : array_index_14981 & {96{or_reduce_14691}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_14981 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_14689}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_15032 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_14985 & {8{or_reduce_14699}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_15034 ? array_index_14985 : array_index_14987 & {8{ugt_14695}};
  assign compacted_2_tup1_tup0_tup3 = ugt_15036 ? array_index_14987 : array_index_14989 & {8{or_reduce_14691}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_14989 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_14689}};
  assign concat_15013 = {____state_4_0, ____state_4_1, add_14747, ____state_3[0]};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_14659 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_14914 == one_hot_14998[1] & and_14915 == one_hot_14998[0];
  assign ____state_7__at_most_one_next_value = and_14916 == one_hot_14999[1] & and_14885 == one_hot_14999[0];
  assign ____state_8__at_most_one_next_value = and_14916 == one_hot_15000[1] & and_14917 == one_hot_15000[0];
  assign ____state_9__at_most_one_next_value = and_14916 == one_hot_15001[2] & and_14917 == one_hot_15001[1] & and_14918 == one_hot_15001[0];
  assign ____state_11__at_most_one_next_value = and_14919 == one_hot_15002[1] & and_14893 == one_hot_15002[0];
  assign ____state_14__at_most_one_next_value = and_14920 == one_hot_15003[1] & and_14921 == one_hot_15003[0];
  assign ____state_16__at_most_one_next_value = nor_14840 == one_hot_15004[1] & __phi_halo_cell__east_vld_buf == one_hot_15004[0];
  assign ____state_0__at_most_one_next_value = and_14922 == one_hot_15005[10] & and_14923 == one_hot_15005[9] & and_14924 == one_hot_15005[8] & and_14925 == one_hot_15005[7] & and_14926 == one_hot_15005[6] & and_14916 == one_hot_15005[5] & and_14927 == one_hot_15005[4] & and_14915 == one_hot_15005[3] & and_14928 == one_hot_15005[2] & and_14929 == one_hot_15005[1] & and_14930 == one_hot_15005[0];
  assign ____state_6__at_most_one_next_value = and_14931 == one_hot_15006[1] & and_14914 == one_hot_15006[0];
  assign ____state_10__at_most_one_next_value = and_14932 == one_hot_15007[1] & and_14915 == one_hot_15007[0];
  assign ____state_13_tuple_element_0__at_most_one_next_value = and_14870 == one_hot_15008[4] & and_14933 == one_hot_15008[3] & and_14934 == one_hot_15008[2] & and_14935 == one_hot_15008[1] & and_14936 == one_hot_15008[0];
  assign ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value = and_14933 == one_hot_15009[7] & and_14934 == one_hot_15009[6] & and_14935 == one_hot_15009[5] & and_14936 == one_hot_15009[4] & and_14937 == one_hot_15009[3] & and_14938 == one_hot_15009[2] & and_14939 == one_hot_15009[1] & and_14940 == one_hot_15009[0];
  assign concat_15292 = {and_15289, and_15290};
  assign _42 = ____state_3 + _12_source;
  assign concat_15299 = {and_15296, and_14885 & p0_all_active_outputs_ready};
  assign concat_15306 = {and_15296, and_15304};
  assign concat_15314 = {and_15296, and_15304, and_14918 & p0_all_active_outputs_ready};
  assign concat_15321 = {and_14919 & p0_all_active_outputs_ready, and_14893 & p0_all_active_outputs_ready};
  assign Xls_clause_1_NextAnyon_1 = ____state_11 ^ Xls_clause_1_Value1_1;
  assign _40 = {____state_11[31:1], _40__1};
  assign NextRandom_1__11 = _1__1[18:2] ^ {_1__1[13:2], _2__15[14:10]};
  assign NextRandom_1__10 = _2__15[14:5] ^ _2__15[9:0];
  assign NextRandom_1__9 = _2__15[4:0];
  assign concat_15331 = {and_14920 & p0_all_active_outputs_ready, and_14921 & p0_all_active_outputs_ready};
  assign concat_15341 = {nor_14840 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _27 = {add_15050, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_14995[30:2]};
  assign add_15129 = {compacted_4_tup0, add_14952[30:1]} + {3'h0, umul_14953[63:36]};
  assign sign_ext_15130 = {32{~_19}};
  assign concat_15370 = {and_14922 & p0_all_active_outputs_ready, and_14923 & p0_all_active_outputs_ready, and_14924 & p0_all_active_outputs_ready, and_14925 & p0_all_active_outputs_ready, and_14926 & p0_all_active_outputs_ready, and_15296, and_14927 & p0_all_active_outputs_ready, and_15290, and_14928 & p0_all_active_outputs_ready, and_14929 & p0_all_active_outputs_ready, and_14930 & p0_all_active_outputs_ready};
  assign concat_15377 = {and_14931 & p0_all_active_outputs_ready, and_15289};
  assign unexpand_for_next_value_2831_6__2_case_0_case_0_case_0_case_1_case_0 = ____state_6 + unexpand_for_next_value_2831_0__2_case_0_case_0_case_1;
  assign concat_15384 = {and_14932 & p0_all_active_outputs_ready, and_15290};
  assign unexpand_for_next_value_2831_10__2_case_0_case_1_case_2_case_1_case_0 = ____state_10 + unexpand_for_next_value_2831_0__2_case_0_case_0_case_1;
  assign concat_15394 = {and_14870 & p0_all_active_outputs_ready, and_15389, and_15390, and_15391, and_15392};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_15407 = {and_15389, and_15390, and_15391, and_15392, and_14937 & p0_all_active_outputs_ready, and_14938 & p0_all_active_outputs_ready, and_14939 & p0_all_active_outputs_ready, and_14940 & p0_all_active_outputs_ready};
  assign compacted_slots_tuple_idx_1_tuple_idx_1[0] = compacted_0_tup1_tup1;
  assign compacted_slots_tuple_idx_1_tuple_idx_1[1] = compacted_1_tup1_tup1;
  assign compacted_slots_tuple_idx_1_tuple_idx_1[2] = compacted_2_tup1_tup1;
  assign compacted_slots_tuple_idx_1_tuple_idx_1[3] = compacted_3_tup1_tup1;
  assign compacted_slots_tuple_idx_1_tuple_idx_1[4] = compacted_4_tup1_tup1;
  assign compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] = compacted_0_tup1_tup0_tup3;
  assign compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] = compacted_1_tup1_tup0_tup3;
  assign compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] = compacted_2_tup1_tup0_tup3;
  assign compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] = compacted_3_tup1_tup0_tup3;
  assign compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] = compacted_4_tup1_tup0_tup0;
  assign __phi_halo_cell__admit_valid_and_all_active_outputs_ready = __phi_halo_cell__admit_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__admit_valid_and_ready_txfr = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_load_en;
  assign __phi_halo_cell__east_valid_and_all_active_outputs_ready = __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__north_valid_and_ready_txfr = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_load_en;
  assign __phi_halo_cell__east_valid_and_ready_txfr = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_load_en;
  assign __phi_halo_cell__west_valid_and_ready_txfr = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_load_en;
  assign __phi_halo_cell__south_valid_and_ready_txfr = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_load_en;
  assign tuple_15099 = {{7'h01, or_14759}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, nor_14750 ? unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2831_0__2_case_0_case_0_case_2, or_14759}};
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_15764 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_15766 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_15768 = ~p0_all_active_outputs_ready | ____state_8__at_most_one_next_value | reset;
  assign or_15770 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_15772 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_15774 = ~p0_all_active_outputs_ready | ____state_14__at_most_one_next_value | reset;
  assign or_15776 = ~p0_all_active_outputs_ready | ____state_16__at_most_one_next_value | reset;
  assign or_15778 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_15780 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_15782 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_15784 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_0__at_most_one_next_value | reset;
  assign or_15786 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign _8__1 = ____state_2 + _12_source;
  assign and_15430 = and_14915 & p0_all_active_outputs_ready;
  assign one_hot_sel_15293 = 32'h0000_0000 & {32{concat_15292[0]}} | _42 & {32{concat_15292[1]}};
  assign and_15433 = (and_14914 | and_14915) & p0_all_active_outputs_ready;
  assign one_hot_sel_15300 = Xls_clause_1_NewSeen_1 & {32{concat_15299[0]}} | 32'h0000_0000 & {32{concat_15299[1]}};
  assign and_15436 = (and_14916 | and_14885) & p0_all_active_outputs_ready;
  assign one_hot_sel_15307 = Xls_clause_1_Value_1 & {32{concat_15306[0]}} | 32'h0000_0000 & {32{concat_15306[1]}};
  assign and_15439 = (and_14916 | and_14917) & p0_all_active_outputs_ready;
  assign one_hot_sel_15315 = 32'h0000_0000 & {32{concat_15314[0]}} | Xls_clause_1_Value1_1 & {32{concat_15314[1]}} | 32'h0000_0000 & {32{concat_15314[2]}};
  assign and_15442 = (and_14916 | and_14917 | and_14918) & p0_all_active_outputs_ready;
  assign one_hot_sel_15322 = Xls_clause_1_NextAnyon_1 & {32{concat_15321[0]}} | _40 & {32{concat_15321[1]}};
  assign and_15445 = (and_14919 | and_14893) & p0_all_active_outputs_ready;
  assign NextRandom_1 = {NextRandom_1__11, NextRandom_1__10, NextRandom_1__9};
  assign and_15447 = and_14919 & p0_all_active_outputs_ready;
  assign one_hot_sel_15332 = add_14876 & {8{concat_15331[0]}} | admitted_occupied & {8{concat_15331[1]}};
  assign and_15450 = (and_14920 | and_14921) & p0_all_active_outputs_ready;
  assign and_15182 = ~____state_15 & effective & phase_boundary & ~failed;
  assign and_15452 = ~____state_17 & p0_all_active_outputs_ready;
  assign one_hot_sel_15342 = (____state_16 | ____state_14 < MAILBOX_CAPACITY) & concat_15341[0] | (admission_pending | reserve__1) & concat_15341[1];
  assign and_15455 = (nor_14840 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_15180 = ____state_17 | (____state_15 ? ____state_17 : failed);
  assign _31 = _27 + _30;
  assign and_15458 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14762 & nor_14750 & eq_14767 & eq_14768 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_15129};
  assign and_15200 = _8 & sign_ext_15130;
  assign and_15462 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14762 & nor_14750 & _3 & p0_all_active_outputs_ready;
  assign and_15201 = _12 & sign_ext_15130;
  assign one_hot_sel_15371 = unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 & {2{concat_15370[0]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_2 & {2{concat_15370[1]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_2 & {2{concat_15370[2]}} | unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15370[3]}} | unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15370[4]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 & {2{concat_15370[5]}} | unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15370[6]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 & {2{concat_15370[7]}} | unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15370[8]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_2 & {2{concat_15370[9]}} | unexpand_for_next_value_2831_0__2_case_0_case_0_case_1 & {2{concat_15370[10]}};
  assign and_15467 = (and_14922 | and_14923 | and_14924 | and_14925 | and_14926 | and_14916 | and_14927 | and_14915 | and_14928 | and_14929 | and_14930) & p0_all_active_outputs_ready;
  assign one_hot_sel_15378 = unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15377[0]}} | unexpand_for_next_value_2831_6__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_15377[1]}};
  assign and_15470 = (and_14931 | and_14914) & p0_all_active_outputs_ready;
  assign one_hot_sel_15385 = unexpand_for_next_value_2831_0__2_case_0_case_1_case_0 & {2{concat_15384[0]}} | unexpand_for_next_value_2831_10__2_case_0_case_1_case_2_case_1_case_0 & {2{concat_15384[1]}};
  assign and_15473 = (and_14932 | and_14915) & p0_all_active_outputs_ready;
  assign one_hot_sel_15395[0] = admitted_slots_tuple_idx_0[0] & concat_15394[0] | postponed_slots_tuple_idx_0[0] & concat_15394[1] | compacted_slots_tuple_idx_0[0] & concat_15394[2] | admitted_slots_tuple_idx_0[0] & concat_15394[3] | unblocked_slots_tuple_idx_0[0] & concat_15394[4];
  assign one_hot_sel_15395[1] = admitted_slots_tuple_idx_0[1] & concat_15394[0] | postponed_slots_tuple_idx_0[1] & concat_15394[1] | compacted_slots_tuple_idx_0[1] & concat_15394[2] | admitted_slots_tuple_idx_0[1] & concat_15394[3] | unblocked_slots_tuple_idx_0[1] & concat_15394[4];
  assign one_hot_sel_15395[2] = admitted_slots_tuple_idx_0[2] & concat_15394[0] | postponed_slots_tuple_idx_0[2] & concat_15394[1] | compacted_slots_tuple_idx_0[2] & concat_15394[2] | admitted_slots_tuple_idx_0[2] & concat_15394[3] | unblocked_slots_tuple_idx_0[2] & concat_15394[4];
  assign one_hot_sel_15395[3] = admitted_slots_tuple_idx_0[3] & concat_15394[0] | postponed_slots_tuple_idx_0[3] & concat_15394[1] | compacted_slots_tuple_idx_0[3] & concat_15394[2] | admitted_slots_tuple_idx_0[3] & concat_15394[3] | unblocked_slots_tuple_idx_0[3] & concat_15394[4];
  assign one_hot_sel_15395[4] = admitted_slots_tuple_idx_0[4] & concat_15394[0] | postponed_slots_tuple_idx_0[4] & concat_15394[1] | compacted_slots_tuple_idx_0[4] & concat_15394[2] | admitted_slots_tuple_idx_0[4] & concat_15394[3] | unblocked_slots_tuple_idx_0[4] & concat_15394[4];
  assign and_15476 = (and_14870 | and_14933 | and_14934 | and_14935 | and_14936) & p0_all_active_outputs_ready;
  assign one_hot_sel_15408[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_15407[7]}};
  assign one_hot_sel_15408[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_15407[7]}};
  assign one_hot_sel_15408[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_15407[7]}};
  assign one_hot_sel_15408[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_15407[7]}};
  assign one_hot_sel_15408[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_15407[7]}};
  assign and_15479 = (and_14933 | and_14934 | and_14935 | and_14936 | and_14937 | and_14938 | and_14939 | and_14940) & p0_all_active_outputs_ready;
  assign one_hot_sel_15421[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_15407[7]}};
  assign one_hot_sel_15421[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_15407[7]}};
  assign one_hot_sel_15421[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_15407[7]}};
  assign one_hot_sel_15421[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_15407[7]}};
  assign one_hot_sel_15421[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_15407[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {tuple_15099, priority_sel_96b_2way(concat_14776, concat_15013, {____state_4_0, _3__5_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_16 & Move_1__1)), ____state_2})};
  assign effects_east = {tuple_15099, priority_sel_96b_2way(concat_14776, concat_15013, {____state_4_0, _6__5_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_19__2 & Move_1__1)), ____state_2})};
  assign effects_west = {tuple_15099, priority_sel_96b_2way(concat_14776, concat_15013, {____state_4_0, _9_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_22__1 & Move_1__1)), ____state_2})};
  assign effects_south = {tuple_15099, priority_sel_96b_2way(concat_14776, concat_15013, {____state_4_0, _12_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_25 & Move_1__1)), ____state_2})};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_16 <= 1'h0;
      ____state_17 <= 1'h0;
      ____state_15 <= 1'h1;
      ____state_13_tuple_element_0[0] <= ____state_13_tuple_element_0_init[0];
      ____state_13_tuple_element_0[1] <= ____state_13_tuple_element_0_init[1];
      ____state_13_tuple_element_0[2] <= ____state_13_tuple_element_0_init[2];
      ____state_13_tuple_element_0[3] <= ____state_13_tuple_element_0_init[3];
      ____state_13_tuple_element_0[4] <= ____state_13_tuple_element_0_init[4];
      ____state_14 <= 8'h00;
      ____state_13_tuple_element_1_tuple_element_1[0] <= ____state_13_tuple_element_1_tuple_element_1_init[0];
      ____state_13_tuple_element_1_tuple_element_1[1] <= ____state_13_tuple_element_1_tuple_element_1_init[1];
      ____state_13_tuple_element_1_tuple_element_1[2] <= ____state_13_tuple_element_1_tuple_element_1_init[2];
      ____state_13_tuple_element_1_tuple_element_1[3] <= ____state_13_tuple_element_1_tuple_element_1_init[3];
      ____state_13_tuple_element_1_tuple_element_1[4] <= ____state_13_tuple_element_1_tuple_element_1_init[4];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0] <= ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[0];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1] <= ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[1];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2] <= ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[2];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3] <= ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[3];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4] <= ____state_13_tuple_element_1_tuple_element_0_tuple_element_3_init[4];
      ____state_7 <= 32'h0000_0000;
      ____state_2 <= 32'h0000_0000;
      ____state_3 <= 32'h0000_0000;
      ____state_0 <= 2'h0;
      ____state_10 <= 2'h0;
      ____state_6 <= 2'h0;
      ____state_12 <= 32'h6d2b_79f5;
      ____state_8 <= 32'h0000_0000;
      ____state_11 <= 32'h0000_0000;
      ____state_9 <= 32'h0000_0000;
      ____state_5_1 <= 32'h0000_0000;
      ____state_5_0 <= 32'h0000_0000;
      ____state_4_1 <= 32'h0000_0000;
      ____state_4_0 <= 32'h0000_0000;
      __phi_halo_cell__admit_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__north_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__east_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__west_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__south_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__req_reg <= __phi_halo_cell__req_reg_init;
      __phi_halo_cell__req_valid_reg <= 1'h0;
      __phi_halo_cell__admit_reg <= 1'h0;
      __phi_halo_cell__admit_valid_reg <= 1'h0;
      __phi_halo_cell__north_reg <= __phi_halo_cell__north_reg_init;
      __phi_halo_cell__north_valid_reg <= 1'h0;
      __phi_halo_cell__east_reg <= __phi_halo_cell__east_reg_init;
      __phi_halo_cell__east_valid_reg <= 1'h0;
      __phi_halo_cell__west_reg <= __phi_halo_cell__west_reg_init;
      __phi_halo_cell__west_valid_reg <= 1'h0;
      __phi_halo_cell__south_reg <= __phi_halo_cell__south_reg_init;
      __phi_halo_cell__south_valid_reg <= 1'h0;
    end else begin
      ____state_16 <= and_15455 ? one_hot_sel_15342 : ____state_16;
      ____state_17 <= p0_all_active_outputs_ready ? or_15180 : ____state_17;
      ____state_15 <= and_15452 ? and_15182 : ____state_15;
      ____state_13_tuple_element_0[0] <= and_15476 ? one_hot_sel_15395[0] : ____state_13_tuple_element_0[0];
      ____state_13_tuple_element_0[1] <= and_15476 ? one_hot_sel_15395[1] : ____state_13_tuple_element_0[1];
      ____state_13_tuple_element_0[2] <= and_15476 ? one_hot_sel_15395[2] : ____state_13_tuple_element_0[2];
      ____state_13_tuple_element_0[3] <= and_15476 ? one_hot_sel_15395[3] : ____state_13_tuple_element_0[3];
      ____state_13_tuple_element_0[4] <= and_15476 ? one_hot_sel_15395[4] : ____state_13_tuple_element_0[4];
      ____state_14 <= and_15450 ? one_hot_sel_15332 : ____state_14;
      ____state_13_tuple_element_1_tuple_element_1[0] <= and_15479 ? one_hot_sel_15408[0] : ____state_13_tuple_element_1_tuple_element_1[0];
      ____state_13_tuple_element_1_tuple_element_1[1] <= and_15479 ? one_hot_sel_15408[1] : ____state_13_tuple_element_1_tuple_element_1[1];
      ____state_13_tuple_element_1_tuple_element_1[2] <= and_15479 ? one_hot_sel_15408[2] : ____state_13_tuple_element_1_tuple_element_1[2];
      ____state_13_tuple_element_1_tuple_element_1[3] <= and_15479 ? one_hot_sel_15408[3] : ____state_13_tuple_element_1_tuple_element_1[3];
      ____state_13_tuple_element_1_tuple_element_1[4] <= and_15479 ? one_hot_sel_15408[4] : ____state_13_tuple_element_1_tuple_element_1[4];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_15479 ? one_hot_sel_15421[0] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_15479 ? one_hot_sel_15421[1] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_15479 ? one_hot_sel_15421[2] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_15479 ? one_hot_sel_15421[3] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_15479 ? one_hot_sel_15421[4] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_7 <= and_15436 ? one_hot_sel_15300 : ____state_7;
      ____state_2 <= and_15430 ? _8__1 : ____state_2;
      ____state_3 <= and_15433 ? one_hot_sel_15293 : ____state_3;
      ____state_0 <= and_15467 ? one_hot_sel_15371 : ____state_0;
      ____state_10 <= and_15473 ? one_hot_sel_15385 : ____state_10;
      ____state_6 <= and_15470 ? one_hot_sel_15378 : ____state_6;
      ____state_12 <= and_15447 ? NextRandom_1 : ____state_12;
      ____state_8 <= and_15439 ? one_hot_sel_15307 : ____state_8;
      ____state_11 <= and_15445 ? one_hot_sel_15322 : ____state_11;
      ____state_9 <= and_15442 ? one_hot_sel_15315 : ____state_9;
      ____state_5_1 <= and_15462 ? and_15201 : ____state_5_1;
      ____state_5_0 <= and_15462 ? and_15200 : ____state_5_0;
      ____state_4_1 <= and_15458 ? _37 : ____state_4_1;
      ____state_4_0 <= and_15458 ? _31 : ____state_4_0;
      __phi_halo_cell__admit_has_been_sent_reg <= __phi_halo_cell__admit_has_been_sent_reg_load_en ? __phi_halo_cell__admit_not_stage_load : __phi_halo_cell__admit_has_been_sent_reg;
      __phi_halo_cell__north_has_been_sent_reg <= __phi_halo_cell__north_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__north_has_been_sent_reg;
      __phi_halo_cell__east_has_been_sent_reg <= __phi_halo_cell__east_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__east_has_been_sent_reg;
      __phi_halo_cell__west_has_been_sent_reg <= __phi_halo_cell__west_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__west_has_been_sent_reg;
      __phi_halo_cell__south_has_been_sent_reg <= __phi_halo_cell__south_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__south_has_been_sent_reg;
      __phi_halo_cell__req_reg <= phi_halo_cell__req_load_en ? phi_halo_cell__req : __phi_halo_cell__req_reg;
      __phi_halo_cell__req_valid_reg <= phi_halo_cell__req_valid_load_en ? phi_halo_cell__req_vld : __phi_halo_cell__req_valid_reg;
      __phi_halo_cell__admit_reg <= phi_halo_cell__admit_load_en ? __phi_halo_cell__admit_buf : __phi_halo_cell__admit_reg;
      __phi_halo_cell__admit_valid_reg <= phi_halo_cell__admit_valid_load_en ? __phi_halo_cell__admit_valid_and_not_has_been_sent : __phi_halo_cell__admit_valid_reg;
      __phi_halo_cell__north_reg <= phi_halo_cell__north_load_en ? effects_north : __phi_halo_cell__north_reg;
      __phi_halo_cell__north_valid_reg <= phi_halo_cell__north_valid_load_en ? __phi_halo_cell__north_valid_and_not_has_been_sent : __phi_halo_cell__north_valid_reg;
      __phi_halo_cell__east_reg <= phi_halo_cell__east_load_en ? effects_east : __phi_halo_cell__east_reg;
      __phi_halo_cell__east_valid_reg <= phi_halo_cell__east_valid_load_en ? __phi_halo_cell__east_valid_and_not_has_been_sent : __phi_halo_cell__east_valid_reg;
      __phi_halo_cell__west_reg <= phi_halo_cell__west_load_en ? effects_west : __phi_halo_cell__west_reg;
      __phi_halo_cell__west_valid_reg <= phi_halo_cell__west_valid_load_en ? __phi_halo_cell__west_valid_and_not_has_been_sent : __phi_halo_cell__west_valid_reg;
      __phi_halo_cell__south_reg <= phi_halo_cell__south_load_en ? effects_south : __phi_halo_cell__south_reg;
      __phi_halo_cell__south_valid_reg <= phi_halo_cell__south_valid_load_en ? __phi_halo_cell__south_valid_and_not_has_been_sent : __phi_halo_cell__south_valid_reg;
    end
  end
  assign phi_halo_cell__admit = __phi_halo_cell__admit_reg;
  assign phi_halo_cell__admit_vld = __phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__east = __phi_halo_cell__east_reg;
  assign phi_halo_cell__east_vld = __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__north = __phi_halo_cell__north_reg;
  assign phi_halo_cell__north_vld = __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__req_rdy = phi_halo_cell__req_load_en;
  assign phi_halo_cell__south = __phi_halo_cell__south_reg;
  assign phi_halo_cell__south_vld = __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__west = __phi_halo_cell__west_reg;
  assign phi_halo_cell__west_vld = __phi_halo_cell__west_valid_reg;
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_14687 == __i0 ? and_14686 : ____state_13_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_14687 == __i0 ? sel_14719 : ____state_13_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_14687 == __i0 ? sel_14731 : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_15118 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_15118 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_15118 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
  end
endmodule


module fifo_for_depth_1_ty_bits_1__with_bypass_register_push(
  input wire clk,
  input wire reset,
  input wire push_valid,
  input wire pop_ready,
  input wire push_data,
  output wire push_ready,
  output wire pop_valid,
  output wire pop_data
);
  wire buf__1_init[0:1];
  assign buf__1_init[0] = 1'h0;
  assign buf__1_init[1] = 1'h0;
  reg [1:0] head;
  reg [1:0] tail;
  reg [1:0] slots;
  reg buf__1[0:1];
  wire is_full_bool;
  wire can_do_push;
  wire and_15849;
  wire eq_15854;
  wire ne_15838;
  wire and_15855;
  wire or_15852;
  wire [2:0] add_15846;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15841;
  wire popped;
  wire [1:0] sub_15867;
  wire [1:0] add_15869;
  wire [2:0] umod_15847;
  wire [2:0] umod_15842;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15871;
  wire array_update_15878[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15849 = pop_ready & push_valid;
  assign eq_15854 = head == tail;
  assign ne_15838 = head != tail;
  assign and_15855 = eq_15854 & and_15849;
  assign or_15852 = ne_15838 | push_valid;
  assign add_15846 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15841 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15852;
  assign sub_15867 = slots - 2'h1;
  assign add_15869 = slots + 2'h1;
  assign umod_15847 = add_15846 % long_buf_size_lit;
  assign umod_15842 = add_15841 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15847[1:0];
  assign did_push_occur = (can_do_push | and_15849) & push_valid & ~and_15855 & ~is_full_bool;
  assign next_tail_if_pop = umod_15842[1:0];
  assign did_pop_occur = (ne_15838 | and_15849) & pop_ready & ~and_15855;
  assign sel_15871 = pushed ? (popped ? slots : add_15869) : (popped ? sub_15867 : slots);
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
      slots <= sel_15871;
      buf__1[0] <= did_push_occur ? array_update_15878[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15878[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15852;
  assign pop_data = eq_15854 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15878_0
    assign array_update_15878[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15906;
  wire eq_15911;
  wire ne_15895;
  wire and_15912;
  wire or_15909;
  wire [2:0] add_15903;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15898;
  wire popped;
  wire [1:0] sub_15924;
  wire [1:0] add_15926;
  wire [2:0] umod_15904;
  wire [2:0] umod_15899;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15928;
  wire [127:0] array_update_15935[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15906 = pop_ready & push_valid;
  assign eq_15911 = head == tail;
  assign ne_15895 = head != tail;
  assign and_15912 = eq_15911 & and_15906;
  assign or_15909 = ne_15895 | push_valid;
  assign add_15903 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15898 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15909;
  assign sub_15924 = slots - 2'h1;
  assign add_15926 = slots + 2'h1;
  assign umod_15904 = add_15903 % long_buf_size_lit;
  assign umod_15899 = add_15898 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15904[1:0];
  assign did_push_occur = (can_do_push | and_15906) & push_valid & ~and_15912 & ~is_full_bool;
  assign next_tail_if_pop = umod_15899[1:0];
  assign did_pop_occur = (ne_15895 | and_15906) & pop_ready & ~and_15912;
  assign sel_15928 = pushed ? (popped ? slots : add_15926) : (popped ? sub_15924 : slots);
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
      slots <= sel_15928;
      buf__1[0] <= did_push_occur ? array_update_15935[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15935[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15909;
  assign pop_data = eq_15911 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15935_0
    assign array_update_15935[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15963;
  wire eq_15968;
  wire ne_15952;
  wire and_15969;
  wire or_15966;
  wire [2:0] add_15960;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15955;
  wire popped;
  wire [1:0] sub_15981;
  wire [1:0] add_15983;
  wire [2:0] umod_15961;
  wire [2:0] umod_15956;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15985;
  wire [127:0] array_update_15992[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15963 = pop_ready & push_valid;
  assign eq_15968 = head == tail;
  assign ne_15952 = head != tail;
  assign and_15969 = eq_15968 & and_15963;
  assign or_15966 = ne_15952 | push_valid;
  assign add_15960 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15955 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15966;
  assign sub_15981 = slots - 2'h1;
  assign add_15983 = slots + 2'h1;
  assign umod_15961 = add_15960 % long_buf_size_lit;
  assign umod_15956 = add_15955 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15961[1:0];
  assign did_push_occur = (can_do_push | and_15963) & push_valid & ~and_15969 & ~is_full_bool;
  assign next_tail_if_pop = umod_15956[1:0];
  assign did_pop_occur = (ne_15952 | and_15963) & pop_ready & ~and_15969;
  assign sel_15985 = pushed ? (popped ? slots : add_15983) : (popped ? sub_15981 : slots);
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
      slots <= sel_15985;
      buf__1[0] <= did_push_occur ? array_update_15992[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15992[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15966;
  assign pop_data = eq_15968 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15992_0
    assign array_update_15992[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2(
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
  wire and_16020;
  wire eq_16025;
  wire ne_16009;
  wire and_16026;
  wire or_16023;
  wire [2:0] add_16017;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_16012;
  wire popped;
  wire [1:0] sub_16038;
  wire [1:0] add_16040;
  wire [2:0] umod_16018;
  wire [2:0] umod_16013;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_16042;
  wire [127:0] array_update_16049[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_16020 = pop_ready & push_valid;
  assign eq_16025 = head == tail;
  assign ne_16009 = head != tail;
  assign and_16026 = eq_16025 & and_16020;
  assign or_16023 = ne_16009 | push_valid;
  assign add_16017 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_16012 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_16023;
  assign sub_16038 = slots - 2'h1;
  assign add_16040 = slots + 2'h1;
  assign umod_16018 = add_16017 % long_buf_size_lit;
  assign umod_16013 = add_16012 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_16018[1:0];
  assign did_push_occur = (can_do_push | and_16020) & push_valid & ~and_16026 & ~is_full_bool;
  assign next_tail_if_pop = umod_16013[1:0];
  assign did_pop_occur = (ne_16009 | and_16020) & pop_ready & ~and_16026;
  assign sel_16042 = pushed ? (popped ? slots : add_16040) : (popped ? sub_16038 : slots);
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
      slots <= sel_16042;
      buf__1[0] <= did_push_occur ? array_update_16049[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_16049[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_16023;
  assign pop_data = eq_16025 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_16049_0
    assign array_update_16049[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3(
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
  wire and_16077;
  wire eq_16082;
  wire ne_16066;
  wire and_16083;
  wire or_16080;
  wire [2:0] add_16074;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_16069;
  wire popped;
  wire [1:0] sub_16095;
  wire [1:0] add_16097;
  wire [2:0] umod_16075;
  wire [2:0] umod_16070;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_16099;
  wire [127:0] array_update_16106[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_16077 = pop_ready & push_valid;
  assign eq_16082 = head == tail;
  assign ne_16066 = head != tail;
  assign and_16083 = eq_16082 & and_16077;
  assign or_16080 = ne_16066 | push_valid;
  assign add_16074 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_16069 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_16080;
  assign sub_16095 = slots - 2'h1;
  assign add_16097 = slots + 2'h1;
  assign umod_16075 = add_16074 % long_buf_size_lit;
  assign umod_16070 = add_16069 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_16075[1:0];
  assign did_push_occur = (can_do_push | and_16077) & push_valid & ~and_16083 & ~is_full_bool;
  assign next_tail_if_pop = umod_16070[1:0];
  assign did_pop_occur = (ne_16066 | and_16077) & pop_ready & ~and_16083;
  assign sel_16099 = pushed ? (popped ? slots : add_16097) : (popped ? sub_16095 : slots);
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
      slots <= sel_16099;
      buf__1[0] <= did_push_occur ? array_update_16106[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_16106[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_16080;
  assign pop_data = eq_16082 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_16106_0
    assign array_update_16106[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4(
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
  wire and_16134;
  wire eq_16139;
  wire ne_16123;
  wire and_16140;
  wire or_16137;
  wire [2:0] add_16131;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_16126;
  wire popped;
  wire [1:0] sub_16152;
  wire [1:0] add_16154;
  wire [2:0] umod_16132;
  wire [2:0] umod_16127;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_16156;
  wire [127:0] array_update_16163[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_16134 = pop_ready & push_valid;
  assign eq_16139 = head == tail;
  assign ne_16123 = head != tail;
  assign and_16140 = eq_16139 & and_16134;
  assign or_16137 = ne_16123 | push_valid;
  assign add_16131 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_16126 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_16137;
  assign sub_16152 = slots - 2'h1;
  assign add_16154 = slots + 2'h1;
  assign umod_16132 = add_16131 % long_buf_size_lit;
  assign umod_16127 = add_16126 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_16132[1:0];
  assign did_push_occur = (can_do_push | and_16134) & push_valid & ~and_16140 & ~is_full_bool;
  assign next_tail_if_pop = umod_16127[1:0];
  assign did_pop_occur = (ne_16123 | and_16134) & pop_ready & ~and_16140;
  assign sel_16156 = pushed ? (popped ? slots : add_16154) : (popped ? sub_16152 : slots);
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
      slots <= sel_16156;
      buf__1[0] <= did_push_occur ? array_update_16163[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_16163[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_16137;
  assign pop_data = eq_16139 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_16163_0
    assign array_update_16163[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __phi_halo_cell__Top_0_next(
  input wire clk,
  input wire reset,
  input wire phi_halo_cell__east_send_rdy,
  input wire [32:0] phi_halo_cell__ext_recv,
  input wire phi_halo_cell__ext_recv_vld,
  input wire phi_halo_cell__north_send_rdy,
  input wire phi_halo_cell__south_send_rdy,
  input wire phi_halo_cell__west_send_rdy,
  output wire [32:0] phi_halo_cell__east_send,
  output wire phi_halo_cell__east_send_vld,
  output wire phi_halo_cell__ext_recv_rdy,
  output wire [32:0] phi_halo_cell__north_send,
  output wire phi_halo_cell__north_send_vld,
  output wire [32:0] phi_halo_cell__south_send,
  output wire phi_halo_cell__south_send_vld,
  output wire [32:0] phi_halo_cell__west_send,
  output wire phi_halo_cell__west_send_vld
);
  wire instantiation_output_15631;
  wire instantiation_output_15656;
  wire [127:0] instantiation_output_15680;
  wire instantiation_output_15681;
  wire instantiation_output_15669;
  wire [32:0] instantiation_output_15673;
  wire instantiation_output_15674;
  wire instantiation_output_15644;
  wire [32:0] instantiation_output_15648;
  wire instantiation_output_15649;
  wire instantiation_output_15720;
  wire [32:0] instantiation_output_15724;
  wire instantiation_output_15725;
  wire instantiation_output_15701;
  wire [32:0] instantiation_output_15705;
  wire instantiation_output_15706;
  wire instantiation_output_15623;
  wire instantiation_output_15624;
  wire [127:0] instantiation_output_15636;
  wire instantiation_output_15637;
  wire [127:0] instantiation_output_15661;
  wire instantiation_output_15662;
  wire instantiation_output_15688;
  wire [127:0] instantiation_output_15693;
  wire instantiation_output_15694;
  wire [127:0] instantiation_output_15712;
  wire instantiation_output_15713;
  wire instantiation_output_16171;
  wire instantiation_output_16172;
  wire instantiation_output_16173;
  wire instantiation_output_16178;
  wire [127:0] instantiation_output_16179;
  wire instantiation_output_16180;
  wire instantiation_output_16185;
  wire [127:0] instantiation_output_16186;
  wire instantiation_output_16187;
  wire instantiation_output_16192;
  wire [127:0] instantiation_output_16193;
  wire instantiation_output_16194;
  wire instantiation_output_16199;
  wire [127:0] instantiation_output_16200;
  wire instantiation_output_16201;
  wire instantiation_output_16206;
  wire [127:0] instantiation_output_16207;
  wire instantiation_output_16208;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_16172),
    .phi_halo_cell__admit_vld(instantiation_output_16173),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_16192),
    .phi_halo_cell__admit_rdy(instantiation_output_15631),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_15656),
    .phi_halo_cell__req(instantiation_output_15680),
    .phi_halo_cell__req_vld(instantiation_output_15681),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_16186),
    .phi_halo_cell__north_vld(instantiation_output_16187),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_15669),
    .phi_halo_cell__north_send(instantiation_output_15673),
    .phi_halo_cell__north_send_vld(instantiation_output_15674),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_16179),
    .phi_halo_cell__east_vld(instantiation_output_16180),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_15644),
    .phi_halo_cell__east_send(instantiation_output_15648),
    .phi_halo_cell__east_send_vld(instantiation_output_15649),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_16207),
    .phi_halo_cell__west_vld(instantiation_output_16208),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_15720),
    .phi_halo_cell__west_send(instantiation_output_15724),
    .phi_halo_cell__west_send_vld(instantiation_output_15725),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_16200),
    .phi_halo_cell__south_vld(instantiation_output_16201),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_15701),
    .phi_halo_cell__south_send(instantiation_output_15705),
    .phi_halo_cell__south_send_vld(instantiation_output_15706),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_16171),
    .phi_halo_cell__east_rdy(instantiation_output_16178),
    .phi_halo_cell__north_rdy(instantiation_output_16185),
    .phi_halo_cell__req(instantiation_output_16193),
    .phi_halo_cell__req_vld(instantiation_output_16194),
    .phi_halo_cell__south_rdy(instantiation_output_16199),
    .phi_halo_cell__west_rdy(instantiation_output_16206),
    .phi_halo_cell__admit(instantiation_output_15623),
    .phi_halo_cell__admit_vld(instantiation_output_15624),
    .phi_halo_cell__east(instantiation_output_15636),
    .phi_halo_cell__east_vld(instantiation_output_15637),
    .phi_halo_cell__north(instantiation_output_15661),
    .phi_halo_cell__north_vld(instantiation_output_15662),
    .phi_halo_cell__req_rdy(instantiation_output_15688),
    .phi_halo_cell__south(instantiation_output_15693),
    .phi_halo_cell__south_vld(instantiation_output_15694),
    .phi_halo_cell__west(instantiation_output_15712),
    .phi_halo_cell__west_vld(instantiation_output_15713),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_15623),
    .push_valid(instantiation_output_15624),
    .pop_ready(instantiation_output_15631),
    .push_ready(instantiation_output_16171),
    .pop_data(instantiation_output_16172),
    .pop_valid(instantiation_output_16173),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_15636),
    .push_valid(instantiation_output_15637),
    .pop_ready(instantiation_output_15644),
    .push_ready(instantiation_output_16178),
    .pop_data(instantiation_output_16179),
    .pop_valid(instantiation_output_16180),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_15661),
    .push_valid(instantiation_output_15662),
    .pop_ready(instantiation_output_15669),
    .push_ready(instantiation_output_16185),
    .pop_data(instantiation_output_16186),
    .pop_valid(instantiation_output_16187),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_15680),
    .push_valid(instantiation_output_15681),
    .pop_ready(instantiation_output_15688),
    .push_ready(instantiation_output_16192),
    .pop_data(instantiation_output_16193),
    .pop_valid(instantiation_output_16194),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_15693),
    .push_valid(instantiation_output_15694),
    .pop_ready(instantiation_output_15701),
    .push_ready(instantiation_output_16199),
    .pop_data(instantiation_output_16200),
    .pop_valid(instantiation_output_16201),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_15712),
    .push_valid(instantiation_output_15713),
    .pop_ready(instantiation_output_15720),
    .push_ready(instantiation_output_16206),
    .pop_data(instantiation_output_16207),
    .pop_valid(instantiation_output_16208),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_15648;
  assign phi_halo_cell__east_send_vld = instantiation_output_15649;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_15656;
  assign phi_halo_cell__north_send = instantiation_output_15673;
  assign phi_halo_cell__north_send_vld = instantiation_output_15674;
  assign phi_halo_cell__south_send = instantiation_output_15705;
  assign phi_halo_cell__south_send_vld = instantiation_output_15706;
  assign phi_halo_cell__west_send = instantiation_output_15724;
  assign phi_halo_cell__west_send_vld = instantiation_output_15725;
endmodule
