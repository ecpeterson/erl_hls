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
  wire [32:0] literal_7856 = {1'h0, 32'h0000_0000};
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
  wire and_7866;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_7865;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_7878;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_9456;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_9455;
  wire [31:0] sel_9454;
  wire [31:0] sel_9453;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_7923;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_9465;
  wire nand_7894;
  wire [127:0] one_hot_sel_7924;
  wire and_7938;
  wire [7:0] one_hot_sel_7931;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_7856;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_7866 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_7866;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_7865 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_7866;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_7865, and_7866};
  assign one_hot_7878 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_9456 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_9455 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_9454 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_9453 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_7865 == one_hot_7878[1] & and_7866 == one_hot_7878[0];
  assign concat_7923 = {nor_7865 & p0_stage_done, and_7866 & p0_stage_done};
  assign payload = {sel_9455, sel_9454, sel_9453, sel_9456};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_9465 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_7894 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_7924 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_7923[0]}} | payload & {128{concat_7923[1]}};
  assign and_7938 = (nor_7865 | and_7866) & p0_stage_done;
  assign one_hot_sel_7931 = 8'h00 & {8{concat_7923[0]}} | words_seen & {8{concat_7923[1]}};
  assign __phi_halo_cell__req_buf = {{sel_9456[7:0], sel_9456[15:8], sel_9456[23:16], sel_9456[31:24]}, {sel_9455, sel_9454, sel_9453}};
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
      ____state_0 <= p0_stage_done ? nand_7894 : ____state_0;
      ____state_2 <= and_7938 ? one_hot_sel_7931 : ____state_2;
      ____state_1 <= and_7938 ? one_hot_sel_7924 : ____state_1;
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
  wire [127:0] literal_7994 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8006;
  wire not_8007;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_8016;
  wire [2:0] one_hot_8017;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_8056;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8059;
  wire [127:0] payload;
  wire [1:0] concat_8072;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_9469;
  wire or_9473;
  wire [7:0] one_hot_sel_8060;
  wire and_8080;
  wire [127:0] one_hot_sel_8067;
  wire [7:0] one_hot_sel_8073;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_7994;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_8006 = ~(last | ____state_0);
  assign not_8007 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8006};
  assign ____state_6__next_value_predicates = {not_8007, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_8016 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8017 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_8056 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8016[1] & nor_8006 == one_hot_8016[0];
  assign ____state_6__at_most_one_next_value = not_8007 == one_hot_8017[1] & last == one_hot_8017[0];
  assign concat_8059 = {and_8056, nor_8006 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8072 = {not_8007 & p0_stage_done, and_8056};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_9469 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9473 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8060 = frame_header_payload_words__1 & {8{concat_8059[0]}} | 8'h00 & {8{concat_8059[1]}};
  assign and_8080 = (last | nor_8006) & p0_stage_done;
  assign one_hot_sel_8067 = payload & {128{concat_8059[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8059[1]}};
  assign one_hot_sel_8073 = 8'h00 & {8{concat_8072[0]}} | beats_sent & {8{concat_8072[1]}};
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
      ____state_0 <= p0_stage_done ? not_8007 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8073 : ____state_6;
      ____state_1 <= and_8080 ? one_hot_sel_8060 : ____state_1;
      ____state_5 <= and_8080 ? one_hot_sel_8067 : ____state_5;
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
  wire [127:0] literal_8129 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8141;
  wire not_8142;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_8151;
  wire [2:0] one_hot_8152;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_8191;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8194;
  wire [127:0] payload;
  wire [1:0] concat_8207;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_9475;
  wire or_9479;
  wire [7:0] one_hot_sel_8195;
  wire and_8215;
  wire [127:0] one_hot_sel_8202;
  wire [7:0] one_hot_sel_8208;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_8129;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_8141 = ~(last | ____state_0);
  assign not_8142 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8141};
  assign ____state_6__next_value_predicates = {not_8142, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_8151 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8152 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_8191 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8151[1] & nor_8141 == one_hot_8151[0];
  assign ____state_6__at_most_one_next_value = not_8142 == one_hot_8152[1] & last == one_hot_8152[0];
  assign concat_8194 = {and_8191, nor_8141 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8207 = {not_8142 & p0_stage_done, and_8191};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_9475 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9479 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8195 = frame_header_payload_words__1 & {8{concat_8194[0]}} | 8'h00 & {8{concat_8194[1]}};
  assign and_8215 = (last | nor_8141) & p0_stage_done;
  assign one_hot_sel_8202 = payload & {128{concat_8194[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8194[1]}};
  assign one_hot_sel_8208 = 8'h00 & {8{concat_8207[0]}} | beats_sent & {8{concat_8207[1]}};
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
      ____state_0 <= p0_stage_done ? not_8142 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8208 : ____state_6;
      ____state_1 <= and_8215 ? one_hot_sel_8195 : ____state_1;
      ____state_5 <= and_8215 ? one_hot_sel_8202 : ____state_5;
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
  wire [127:0] literal_8264 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8276;
  wire not_8277;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_8286;
  wire [2:0] one_hot_8287;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_8326;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8329;
  wire [127:0] payload;
  wire [1:0] concat_8342;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_9481;
  wire or_9485;
  wire [7:0] one_hot_sel_8330;
  wire and_8350;
  wire [127:0] one_hot_sel_8337;
  wire [7:0] one_hot_sel_8343;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_8264;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_8276 = ~(last | ____state_0);
  assign not_8277 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8276};
  assign ____state_6__next_value_predicates = {not_8277, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_8286 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8287 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_8326 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8286[1] & nor_8276 == one_hot_8286[0];
  assign ____state_6__at_most_one_next_value = not_8277 == one_hot_8287[1] & last == one_hot_8287[0];
  assign concat_8329 = {and_8326, nor_8276 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8342 = {not_8277 & p0_stage_done, and_8326};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_9481 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9485 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8330 = frame_header_payload_words__1 & {8{concat_8329[0]}} | 8'h00 & {8{concat_8329[1]}};
  assign and_8350 = (last | nor_8276) & p0_stage_done;
  assign one_hot_sel_8337 = payload & {128{concat_8329[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8329[1]}};
  assign one_hot_sel_8343 = 8'h00 & {8{concat_8342[0]}} | beats_sent & {8{concat_8342[1]}};
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
      ____state_0 <= p0_stage_done ? not_8277 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8343 : ____state_6;
      ____state_1 <= and_8350 ? one_hot_sel_8330 : ____state_1;
      ____state_5 <= and_8350 ? one_hot_sel_8337 : ____state_5;
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
  wire [127:0] literal_8399 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8411;
  wire not_8412;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_8421;
  wire [2:0] one_hot_8422;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_8461;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8464;
  wire [127:0] payload;
  wire [1:0] concat_8477;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_9487;
  wire or_9491;
  wire [7:0] one_hot_sel_8465;
  wire and_8485;
  wire [127:0] one_hot_sel_8472;
  wire [7:0] one_hot_sel_8478;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_8399;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_8411 = ~(last | ____state_0);
  assign not_8412 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8411};
  assign ____state_6__next_value_predicates = {not_8412, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_8421 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8422 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_8461 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8421[1] & nor_8411 == one_hot_8421[0];
  assign ____state_6__at_most_one_next_value = not_8412 == one_hot_8422[1] & last == one_hot_8422[0];
  assign concat_8464 = {and_8461, nor_8411 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8477 = {not_8412 & p0_stage_done, and_8461};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_9487 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9491 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8465 = frame_header_payload_words__1 & {8{concat_8464[0]}} | 8'h00 & {8{concat_8464[1]}};
  assign and_8485 = (last | nor_8411) & p0_stage_done;
  assign one_hot_sel_8472 = payload & {128{concat_8464[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8464[1]}};
  assign one_hot_sel_8478 = 8'h00 & {8{concat_8477[0]}} | beats_sent & {8{concat_8477[1]}};
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
      ____state_0 <= p0_stage_done ? not_8412 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8478 : ____state_6;
      ____state_1 <= and_8485 ? one_hot_sel_8465 : ____state_1;
      ____state_5 <= and_8485 ? one_hot_sel_8472 : ____state_5;
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
  function automatic priority_sel_1b_4way (input reg [3:0] sel, input reg case0, input reg case1, input reg case2, input reg case3, input reg default_value);
    begin
      casez (sel)
        4'b???1: begin
          priority_sel_1b_4way = case0;
        end
        4'b??10: begin
          priority_sel_1b_4way = case1;
        end
        4'b?100: begin
          priority_sel_1b_4way = case2;
        end
        4'b1000: begin
          priority_sel_1b_4way = case3;
        end
        4'b0000: begin
          priority_sel_1b_4way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_1b_4way = 1'dx;
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
  // lint_off MULTIPLY
  function automatic [63:0] umul64b_32b_x_32b (input reg [31:0] lhs, input reg [31:0] rhs);
    begin
      umul64b_32b_x_32b = lhs * rhs;
    end
  endfunction
  // lint_on MULTIPLY
  wire [7:0] ____state_8_tuple_element_1_init[0:4];
  assign ____state_8_tuple_element_1_init[0] = 8'h00;
  assign ____state_8_tuple_element_1_init[1] = 8'h00;
  assign ____state_8_tuple_element_1_init[2] = 8'h00;
  assign ____state_8_tuple_element_1_init[3] = 8'h00;
  assign ____state_8_tuple_element_1_init[4] = 8'h00;
  wire ____state_8_tuple_element_0_init[0:4];
  assign ____state_8_tuple_element_0_init[0] = 1'h0;
  assign ____state_8_tuple_element_0_init[1] = 1'h0;
  assign ____state_8_tuple_element_0_init[2] = 1'h0;
  assign ____state_8_tuple_element_0_init[3] = 1'h0;
  assign ____state_8_tuple_element_0_init[4] = 1'h0;
  wire [7:0] ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[0:4];
  assign ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[0] = 8'h00;
  assign ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[1] = 8'h00;
  assign ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[2] = 8'h00;
  assign ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[3] = 8'h00;
  assign ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[4] = 8'h00;
  wire [95:0] ____state_8_tuple_element_2_tuple_element_1_init[0:4];
  assign ____state_8_tuple_element_2_tuple_element_1_init[0] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_8_tuple_element_2_tuple_element_1_init[1] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_8_tuple_element_2_tuple_element_1_init[2] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_8_tuple_element_2_tuple_element_1_init[3] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_8_tuple_element_2_tuple_element_1_init[4] = 96'h0000_0000_0000_0000_0000_0000;
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_8586 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  reg ____state_11;
  reg ____state_12;
  reg ____state_10;
  reg [7:0] ____state_8_tuple_element_1[0:4];
  reg [7:0] ____state_9;
  reg ____state_8_tuple_element_0[0:4];
  reg ____state_0;
  reg [7:0] ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0:4];
  reg [95:0] ____state_8_tuple_element_2_tuple_element_1[0:4];
  reg [31:0] ____state_2;
  reg [1:0] ____state_5;
  reg [1:0] ____state_6;
  reg [31:0] ____state_4_1;
  reg [31:0] ____state_4_0;
  reg [31:0] ____state_3_1;
  reg [31:0] ____state_3_0;
  reg [31:0] ____state_7;
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
  wire nor_8584;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire tag_ok;
  wire accepted;
  wire [7:0] and_8609;
  wire [31:0] concat_8610;
  wire [7:0] admitted_slots_tuple_idx_1[0:4];
  wire [6:0] leading_bits___state_0;
  wire and_8613;
  wire [7:0] blocked_phase__4;
  wire [7:0] blocked_phase__3;
  wire admitted_slots_tuple_idx_0[0:4];
  wire [7:0] blocked_phase__2;
  wire [7:0] admitted_occupied;
  wire postponed__4;
  wire [7:0] blocked_phase__1;
  wire postponed__3;
  wire ugt_8635;
  wire [7:0] blocked_phase;
  wire postponed__2;
  wire or_reduce_8643;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1;
  wire postponed__1;
  wire ugt_8652;
  wire eligible_3;
  wire [7:0] compacted_4_tup1;
  wire postponed;
  wire or_reduce_8659;
  wire eligible_2;
  wire eligible_1;
  wire eligible_0;
  wire [7:0] sel_8675;
  wire [7:0] selected;
  wire [7:0] admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0:4];
  wire [2:0] bit_slice_8680;
  wire [95:0] sel_8681;
  wire [7:0] selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3;
  wire [95:0] admitted_slots_tuple_idx_2_tuple_idx_1[0:4];
  wire eq_8684;
  wire eq_8686;
  wire [95:0] selected_slot_tuple_idx_2_tuple_idx_1;
  wire [31:0] Xls_clause_1_Step_1;
  wire [31:0] _0__2;
  wire and_8694;
  wire nor_8695;
  wire nor_8700;
  wire and_8701;
  wire _2__1;
  wire eq_8697;
  wire _0__6;
  wire invalid_input;
  wire postponed_slot_tup0;
  wire [2:0] concat_8712;
  wire compacted_4_tup0;
  wire found;
  wire priority_sel_8717;
  wire one_hot_sel_9463;
  wire effective;
  wire _15;
  wire [1:0] directive;
  wire _6__1;
  wire nand_8716;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_8747;
  wire candidate_slots_0_case_cmp;
  wire failed;
  wire [7:0] candidate_occupied;
  wire [7:0] MAILBOX_CAPACITY;
  wire candidate_phase_squeezed;
  wire phase_changed;
  wire reserve__1;
  wire reserve;
  wire and_8735;
  wire and_8740;
  wire and_8742;
  wire nor_8743;
  wire nor_8746;
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
  wire nor_8753;
  wire candidate_occupied_0_case_cmp;
  wire and_8756;
  wire and_8758;
  wire and_8760;
  wire nor_8761;
  wire or_8762;
  wire nand_8763;
  wire and_8764;
  wire [31:0] Xls_clause_1_Value1_1;
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
  wire and_8772;
  wire and_8773;
  wire and_8775;
  wire and_8776;
  wire and_8777;
  wire and_8778;
  wire and_8779;
  wire and_8780;
  wire and_8781;
  wire and_8782;
  wire and_8783;
  wire and_8784;
  wire and_8785;
  wire and_8786;
  wire and_8787;
  wire and_8788;
  wire and_8789;
  wire and_8790;
  wire [31:0] Xls_clause_1_Value0_1;
  wire [31:0] _8;
  wire phi_halo_cell__admit_not_pred;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__east_not_pred;
  wire phi_halo_cell__north_load_en;
  wire phi_halo_cell__east_load_en;
  wire phi_halo_cell__west_load_en;
  wire phi_halo_cell__south_load_en;
  wire [1:0] ____state_9__next_value_predicates;
  wire [1:0] ____state_11__next_value_predicates;
  wire [5:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_5__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [4:0] ____state_8_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_8_tuple_element_1__next_value_predicates;
  wire [31:0] _4;
  wire [31:0] _31;
  wire [2:0] one_hot_8835;
  wire [2:0] one_hot_8836;
  wire [6:0] one_hot_8837;
  wire [2:0] one_hot_8838;
  wire [2:0] one_hot_8839;
  wire [5:0] one_hot_8840;
  wire [8:0] one_hot_8841;
  wire [30:0] add_8798;
  wire [63:0] umul_8799;
  wire [7:0] sign_ext_8814;
  wire [7:0] sign_ext_8815;
  wire [7:0] sign_ext_8816;
  wire [7:0] sign_ext_8817;
  wire [95:0] array_index_8818;
  wire [95:0] array_index_8820;
  wire [95:0] array_index_8822;
  wire [7:0] array_index_8826;
  wire [7:0] array_index_8827;
  wire [7:0] array_index_8828;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_8832;
  wire ne_8850;
  wire or_reduce_8852;
  wire ugt_8854;
  wire [3:0] one_hot_9458;
  wire phi_halo_cell__req_valid_inv;
  wire admission_pending;
  wire [15:0] add_8872;
  wire and_9087;
  wire and_9089;
  wire and_9111;
  wire and_9112;
  wire and_9113;
  wire and_9114;
  wire [31:0] concat_8919;
  wire compacted_0_tup0;
  wire compacted_1_tup0;
  wire compacted_2_tup0;
  wire compacted_3_tup0;
  wire [7:0] extended___state_0;
  wire [7:0] compacted_0_tup1;
  wire [7:0] compacted_1_tup1;
  wire [7:0] compacted_2_tup1;
  wire [7:0] compacted_3_tup1;
  wire [95:0] compacted_0_tup2_tup1;
  wire [95:0] compacted_1_tup2_tup1;
  wire [95:0] compacted_2_tup2_tup1;
  wire [95:0] compacted_3_tup2_tup1;
  wire [95:0] compacted_4_tup2_tup1;
  wire [7:0] compacted_0_tup2_tup0_tup3;
  wire [7:0] compacted_1_tup2_tup0_tup3;
  wire [7:0] compacted_2_tup2_tup0_tup3;
  wire [7:0] compacted_3_tup2_tup0_tup3;
  wire phi_halo_cell__req_valid_load_en;
  wire ____state_9__at_most_one_next_value;
  wire ____state_11__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_5__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_8_tuple_element_0__at_most_one_next_value;
  wire ____state_8_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_9058;
  wire [1:0] concat_9068;
  wire [31:0] _23;
  wire [31:0] _26;
  wire [30:0] add_8931;
  wire [31:0] sign_ext_8932;
  wire [5:0] concat_9092;
  wire [1:0] concat_9099;
  wire [1:0] unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_9106;
  wire [1:0] unexpand_for_next_value_1172_6__2_case_0_case_1_case_1_case_1_case_0;
  wire [4:0] concat_9116;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_9129;
  wire [7:0] postponed_slots_tuple_idx_1[0:4];
  wire [7:0] compacted_slots_tuple_idx_1[0:4];
  wire [95:0] postponed_slots_tuple_idx_2_tuple_idx_1[0:4];
  wire [95:0] compacted_slots_tuple_idx_2_tuple_idx_1[0:4];
  wire [7:0] postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0:4];
  wire [7:0] compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0:4];
  wire __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__admit_valid_and_ready_txfr;
  wire __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__north_valid_and_ready_txfr;
  wire __phi_halo_cell__east_valid_and_ready_txfr;
  wire __phi_halo_cell__west_valid_and_ready_txfr;
  wire __phi_halo_cell__south_valid_and_ready_txfr;
  wire phi_halo_cell__req_load_en;
  wire or_9493;
  wire or_9495;
  wire or_9497;
  wire or_9499;
  wire or_9501;
  wire or_9503;
  wire or_9505;
  wire and_9165;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire and_9167;
  wire [7:0] one_hot_sel_9059;
  wire and_9170;
  wire and_8965;
  wire and_9172;
  wire one_hot_sel_9069;
  wire and_9175;
  wire or_8963;
  wire [31:0] _27;
  wire and_9178;
  wire [31:0] _33;
  wire [31:0] and_8981;
  wire and_9182;
  wire [31:0] and_8982;
  wire one_hot_sel_9093;
  wire and_9187;
  wire [1:0] one_hot_sel_9100;
  wire and_9190;
  wire [1:0] one_hot_sel_9107;
  wire and_9193;
  wire one_hot_sel_9117[0:4];
  wire and_9196;
  wire [7:0] one_hot_sel_9130[0:4];
  wire and_9199;
  wire [95:0] one_hot_sel_9143[0:4];
  wire [7:0] one_hot_sel_9156[0:4];
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_not_stage_load;
  wire __phi_halo_cell__north_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_has_been_sent_reg_load_en;
  wire __phi_halo_cell__west_has_been_sent_reg_load_en;
  wire __phi_halo_cell__south_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire or_9511;
  assign nor_8584 = ~(____state_12 | ____state_10 | ~____state_11);
  assign received = nor_8584 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_8586;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign tag_ok = frame_header_op == 8'h03 & frame_header__1_payload_words == 8'h03 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02;
  assign accepted = received & tag_ok;
  assign and_8609 = ____state_8_tuple_element_1[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]] & {8{~accepted}};
  assign concat_8610 = {24'h00_0000, ____state_9};
  assign leading_bits___state_0 = 7'h00;
  assign and_8613 = ~accepted & ____state_8_tuple_element_0[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign blocked_phase__4 = admitted_slots_tuple_idx_1[3'h4];
  assign blocked_phase__3 = admitted_slots_tuple_idx_1[3'h3];
  assign blocked_phase__2 = admitted_slots_tuple_idx_1[3'h2];
  assign admitted_occupied = ____state_9 + {leading_bits___state_0, accepted};
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign blocked_phase__1 = admitted_slots_tuple_idx_1[3'h1];
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign ugt_8635 = admitted_occupied > 8'h04;
  assign blocked_phase = admitted_slots_tuple_idx_1[3'h0];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign or_reduce_8643 = |admitted_occupied[7:2];
  assign eligible_4 = ugt_8635 & ~(postponed__4 & blocked_phase__4[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__4[0]);
  assign unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1 = 2'h0;
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign ugt_8652 = admitted_occupied > 8'h02;
  assign eligible_3 = or_reduce_8643 & ~(postponed__3 & blocked_phase__3[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__3[0]);
  assign compacted_4_tup1 = 8'h00;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign or_reduce_8659 = |admitted_occupied[7:1];
  assign eligible_2 = ugt_8652 & ~(postponed__2 & blocked_phase__2[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__2[0]);
  assign eligible_1 = or_reduce_8659 & ~(postponed__1 & blocked_phase__1[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__1[0]);
  assign eligible_0 = admitted_occupied != compacted_4_tup1 & ~(postponed & blocked_phase[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase[0]);
  assign sel_8675 = accepted ? frame_header_op : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1}))} & {8{~eligible_0}};
  assign bit_slice_8680 = selected[2:0];
  assign sel_8681 = accepted ? phi_halo_cell__req_select[95:0] : ____state_8_tuple_element_2_tuple_element_1[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[bit_slice_8680 > 3'h4 ? 3'h4 : bit_slice_8680];
  assign eq_8684 = selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign eq_8686 = selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign selected_slot_tuple_idx_2_tuple_idx_1 = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_8680 > 3'h4 ? 3'h4 : bit_slice_8680];
  assign Xls_clause_1_Step_1 = selected_slot_tuple_idx_2_tuple_idx_1[31:0];
  assign _0__2 = ____state_2 + 32'h0000_0001;
  assign and_8694 = eq_8686 & ____state_0;
  assign nor_8695 = ~(~eq_8684 | ____state_0);
  assign nor_8700 = ~(~eq_8686 | ____state_0);
  assign and_8701 = eq_8684 & ____state_0;
  assign _2__1 = Xls_clause_1_Step_1 == _0__2;
  assign eq_8697 = Xls_clause_1_Step_1 == ____state_2;
  assign _0__6 = selected_slot_tuple_idx_2_tuple_idx_1[63:33] == 31'h0000_0000;
  assign invalid_input = received & ~tag_ok;
  assign postponed_slot_tup0 = 1'h1;
  assign concat_8712 = {nor_8700, and_8694 | nor_8695, and_8701};
  assign compacted_4_tup0 = 1'h0;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign priority_sel_8717 = priority_sel_1b_4way({nor_8700, and_8694, nor_8695, and_8701}, ~_2__1, ~eq_8697, ~(eq_8697 & _0__6), ~eq_8697, postponed_slot_tup0);
  assign one_hot_sel_9463 = _2__1 & concat_8712[0] | compacted_4_tup0 & concat_8712[1] | eq_8697 & concat_8712[2];
  assign effective = found & ~invalid_input;
  assign _15 = ____state_5 == 2'h3;
  assign directive = {priority_sel_8717, one_hot_sel_9463} & {2{effective}};
  assign _6__1 = ____state_6 == 2'h3;
  assign nand_8716 = ~(eq_8697 & _0__6 & _6__1);
  assign transition_slots_predicate_piece_0 = ~(directive[0] | directive[1]);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_8747 = admitted_occupied + 8'hff;
  assign candidate_slots_0_case_cmp = ~effective;
  assign failed = invalid_input | directive[1];
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_8747 : admitted_occupied;
  assign MAILBOX_CAPACITY = 8'h05;
  assign candidate_phase_squeezed = effective ? priority_sel_1b_2way({eq_8686, eq_8684}, ____state_0 | ~(____state_0 | ~eq_8697 | ~_15), ____state_0 & nand_8716, ____state_0) : ____state_0;
  assign phase_changed = candidate_phase_squeezed ^ ____state_0;
  assign reserve__1 = ~failed & ~received & ~(____state_11 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_11 | ____state_9 > 8'h04);
  assign and_8735 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8686;
  assign and_8740 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8684;
  assign and_8742 = and_8735 & ____state_0;
  assign nor_8743 = ~(____state_12 | ____state_10 | phase_changed);
  assign nor_8746 = ~(____state_12 | ____state_10 | ~phase_changed);
  assign __phi_halo_cell__admit_buf = ~____state_12 & ~____state_10 & reserve__1 | ~____state_12 & ____state_10 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign __phi_halo_cell__east_vld_buf = ~(____state_12 | ~____state_10);
  assign __phi_halo_cell__north_not_has_been_sent = ~__phi_halo_cell__north_has_been_sent_reg;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign __phi_halo_cell__east_not_has_been_sent = ~__phi_halo_cell__east_has_been_sent_reg;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign __phi_halo_cell__west_not_has_been_sent = ~__phi_halo_cell__west_has_been_sent_reg;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign __phi_halo_cell__south_not_has_been_sent = ~__phi_halo_cell__south_has_been_sent_reg;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign nor_8753 = ~(____state_12 | ____state_10);
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_8756 = and_8740 & ~____state_0;
  assign and_8758 = and_8742 & eq_8697 & _0__6;
  assign and_8760 = nor_8743 & effective;
  assign nor_8761 = ~(priority_sel_8717 | ~one_hot_sel_9463);
  assign or_8762 = directive[0] | directive[1];
  assign nand_8763 = ~(~priority_sel_8717 & one_hot_sel_9463);
  assign and_8764 = nor_8746 & effective;
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_2_tuple_idx_1[63:32];
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
  assign and_8772 = nor_8753 & candidate_occupied_0_case_cmp;
  assign and_8773 = nor_8753 & candidate_occupied_1_case_cmp;
  assign and_8775 = and_8740 & ____state_0;
  assign and_8776 = and_8735 & ~____state_0;
  assign and_8777 = and_8756 & eq_8697 & _15;
  assign and_8778 = and_8756 & ~(eq_8697 & _15);
  assign and_8779 = and_8742 & eq_8697 & _0__6 & _6__1;
  assign and_8780 = and_8742 & nand_8716;
  assign and_8781 = and_8756 & eq_8697 & ~_15;
  assign and_8782 = and_8758 & ~_6__1;
  assign and_8783 = nor_8743 & candidate_slots_0_case_cmp;
  assign and_8784 = and_8760 & transition_slots_predicate_piece_0;
  assign and_8785 = and_8760 & nor_8761 & or_8762;
  assign and_8786 = and_8760 & nand_8763 & or_8762;
  assign and_8787 = nor_8746 & candidate_slots_0_case_cmp;
  assign and_8788 = and_8764 & transition_slots_predicate_piece_0;
  assign and_8789 = and_8764 & nor_8761 & or_8762;
  assign and_8790 = and_8764 & nand_8763 & or_8762;
  assign Xls_clause_1_Value0_1 = selected_slot_tuple_idx_2_tuple_idx_1[95:64];
  assign _8 = ____state_4_1 + Xls_clause_1_Value1_1;
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_9__next_value_predicates = {and_8772, and_8773};
  assign ____state_11__next_value_predicates = {nor_8753, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_8775, and_8776, and_8777, and_8778, and_8779, and_8780};
  assign ____state_5__next_value_predicates = {and_8781, and_8777};
  assign ____state_6__next_value_predicates = {and_8782, and_8779};
  assign ____state_8_tuple_element_0__next_value_predicates = {nor_8746, and_8783, and_8784, and_8785, and_8786};
  assign ____state_8_tuple_element_1__next_value_predicates = {and_8783, and_8784, and_8785, and_8786, and_8787, and_8788, and_8789, and_8790};
  assign _4 = ____state_4_0 + Xls_clause_1_Value0_1;
  assign _31 = ____state_3_0 + _8;
  assign one_hot_8835 = {____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_8836 = {____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_8837 = {____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_8838 = {____state_5__next_value_predicates[1:0] == 2'h0, ____state_5__next_value_predicates[1] && !____state_5__next_value_predicates[0], ____state_5__next_value_predicates[0]};
  assign one_hot_8839 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_8840 = {____state_8_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_8_tuple_element_0__next_value_predicates[4] && ____state_8_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_8_tuple_element_0__next_value_predicates[3] && ____state_8_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_8_tuple_element_0__next_value_predicates[2] && ____state_8_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_8_tuple_element_0__next_value_predicates[1] && !____state_8_tuple_element_0__next_value_predicates[0], ____state_8_tuple_element_0__next_value_predicates[0]};
  assign one_hot_8841 = {____state_8_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_8_tuple_element_1__next_value_predicates[7] && ____state_8_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_8_tuple_element_1__next_value_predicates[6] && ____state_8_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_8_tuple_element_1__next_value_predicates[5] && ____state_8_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_8_tuple_element_1__next_value_predicates[4] && ____state_8_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_8_tuple_element_1__next_value_predicates[3] && ____state_8_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_8_tuple_element_1__next_value_predicates[2] && ____state_8_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_8_tuple_element_1__next_value_predicates[1] && !____state_8_tuple_element_1__next_value_predicates[0], ____state_8_tuple_element_1__next_value_predicates[0]};
  assign add_8798 = ____state_3_1[31:1] + ____state_3_1[30:0];
  assign umul_8799 = umul64b_32b_x_32b(_31, 32'hcccc_cccd);
  assign sign_ext_8814 = {8{or_reduce_8659}};
  assign sign_ext_8815 = {8{ugt_8652}};
  assign sign_ext_8816 = {8{or_reduce_8643}};
  assign sign_ext_8817 = {8{ugt_8635}};
  assign array_index_8818 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h1];
  assign array_index_8820 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h2];
  assign array_index_8822 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h3];
  assign array_index_8826 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_8827 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_8828 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_8832 = ____state_3_1[30:0] + _4[31:1];
  assign ne_8850 = bit_slice_8680 != 3'h0;
  assign or_reduce_8852 = |selected[7:1];
  assign ugt_8854 = bit_slice_8680 > 3'h2;
  assign one_hot_9458 = {concat_8712[2:0] == 3'h0, concat_8712[2] && concat_8712[1:0] == 2'h0, concat_8712[1] && !concat_8712[0], concat_8712[0]};
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign admission_pending = ~(~____state_11 | received);
  assign add_8872 = ____state_7[15:0] + {unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1, ____state_3_0[31:18]};
  assign and_9087 = and_8777 & p0_all_active_outputs_ready;
  assign and_9089 = and_8779 & p0_all_active_outputs_ready;
  assign and_9111 = and_8783 & p0_all_active_outputs_ready;
  assign and_9112 = and_8784 & p0_all_active_outputs_ready;
  assign and_9113 = and_8785 & p0_all_active_outputs_ready;
  assign and_9114 = and_8786 & p0_all_active_outputs_ready;
  assign concat_8919 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_8850 ? postponed : or_reduce_8659 & postponed__1;
  assign compacted_1_tup0 = or_reduce_8852 ? postponed__1 : ugt_8652 & postponed__2;
  assign compacted_2_tup0 = ugt_8854 ? postponed__2 : or_reduce_8643 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_8635 & postponed__4;
  assign extended___state_0 = {leading_bits___state_0, ____state_0};
  assign compacted_0_tup1 = ne_8850 ? blocked_phase : blocked_phase__1 & sign_ext_8814;
  assign compacted_1_tup1 = or_reduce_8852 ? blocked_phase__1 : blocked_phase__2 & sign_ext_8815;
  assign compacted_2_tup1 = ugt_8854 ? blocked_phase__2 : blocked_phase__3 & sign_ext_8816;
  assign compacted_3_tup1 = selected[2] ? blocked_phase__3 : blocked_phase__4 & sign_ext_8817;
  assign compacted_0_tup2_tup1 = ne_8850 ? admitted_slots_tuple_idx_2_tuple_idx_1[3'h0] : array_index_8818 & {96{or_reduce_8659}};
  assign compacted_1_tup2_tup1 = or_reduce_8852 ? array_index_8818 : array_index_8820 & {96{ugt_8652}};
  assign compacted_2_tup2_tup1 = ugt_8854 ? array_index_8820 : array_index_8822 & {96{or_reduce_8643}};
  assign compacted_3_tup2_tup1 = selected[2] ? array_index_8822 : admitted_slots_tuple_idx_2_tuple_idx_1[3'h4] & {96{ugt_8635}};
  assign compacted_4_tup2_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup2_tup0_tup3 = ne_8850 ? admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h0] : array_index_8826 & sign_ext_8814;
  assign compacted_1_tup2_tup0_tup3 = or_reduce_8852 ? array_index_8826 : array_index_8827 & sign_ext_8815;
  assign compacted_2_tup2_tup0_tup3 = ugt_8854 ? array_index_8827 : array_index_8828 & sign_ext_8816;
  assign compacted_3_tup2_tup0_tup3 = selected[2] ? array_index_8828 : admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h4] & sign_ext_8817;
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_8584 | phi_halo_cell__req_valid_inv;
  assign ____state_9__at_most_one_next_value = and_8772 == one_hot_8835[1] & and_8773 == one_hot_8835[0];
  assign ____state_11__at_most_one_next_value = nor_8753 == one_hot_8836[1] & __phi_halo_cell__east_vld_buf == one_hot_8836[0];
  assign ____state_0__at_most_one_next_value = and_8775 == one_hot_8837[5] & and_8776 == one_hot_8837[4] & and_8777 == one_hot_8837[3] & and_8778 == one_hot_8837[2] & and_8779 == one_hot_8837[1] & and_8780 == one_hot_8837[0];
  assign ____state_5__at_most_one_next_value = and_8781 == one_hot_8838[1] & and_8777 == one_hot_8838[0];
  assign ____state_6__at_most_one_next_value = and_8782 == one_hot_8839[1] & and_8779 == one_hot_8839[0];
  assign ____state_8_tuple_element_0__at_most_one_next_value = nor_8746 == one_hot_8840[4] & and_8783 == one_hot_8840[3] & and_8784 == one_hot_8840[2] & and_8785 == one_hot_8840[1] & and_8786 == one_hot_8840[0];
  assign ____state_8_tuple_element_1__at_most_one_next_value = and_8783 == one_hot_8841[7] & and_8784 == one_hot_8841[6] & and_8785 == one_hot_8841[5] & and_8786 == one_hot_8841[4] & and_8787 == one_hot_8841[3] & and_8788 == one_hot_8841[2] & and_8789 == one_hot_8841[1] & and_8790 == one_hot_8841[0];
  assign concat_9058 = {and_8772 & p0_all_active_outputs_ready, and_8773 & p0_all_active_outputs_ready};
  assign concat_9068 = {nor_8753 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _23 = {add_8872, ____state_3_0[17:2]};
  assign _26 = {3'h0, add_8832[30:2]};
  assign add_8931 = {compacted_4_tup0, add_8798[30:1]} + {3'h0, umul_8799[63:36]};
  assign sign_ext_8932 = {32{~_15}};
  assign concat_9092 = {and_8775 & p0_all_active_outputs_ready, and_8776 & p0_all_active_outputs_ready, and_9087, and_8778 & p0_all_active_outputs_ready, and_9089, and_8780 & p0_all_active_outputs_ready};
  assign concat_9099 = {and_8781 & p0_all_active_outputs_ready, and_9087};
  assign unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_0 = ____state_5 + 2'h1;
  assign concat_9106 = {and_8782 & p0_all_active_outputs_ready, and_9089};
  assign unexpand_for_next_value_1172_6__2_case_0_case_1_case_1_case_1_case_0 = ____state_6 + 2'h1;
  assign concat_9116 = {nor_8746 & p0_all_active_outputs_ready, and_9111, and_9112, and_9113, and_9114};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_9129 = {and_9111, and_9112, and_9113, and_9114, and_8787 & p0_all_active_outputs_ready, and_8788 & p0_all_active_outputs_ready, and_8789 & p0_all_active_outputs_ready, and_8790 & p0_all_active_outputs_ready};
  assign compacted_slots_tuple_idx_1[0] = compacted_0_tup1;
  assign compacted_slots_tuple_idx_1[1] = compacted_1_tup1;
  assign compacted_slots_tuple_idx_1[2] = compacted_2_tup1;
  assign compacted_slots_tuple_idx_1[3] = compacted_3_tup1;
  assign compacted_slots_tuple_idx_1[4] = compacted_4_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[0] = compacted_0_tup2_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[1] = compacted_1_tup2_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[2] = compacted_2_tup2_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[3] = compacted_3_tup2_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[4] = compacted_4_tup2_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] = compacted_0_tup2_tup0_tup3;
  assign compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] = compacted_1_tup2_tup0_tup3;
  assign compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] = compacted_2_tup2_tup0_tup3;
  assign compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] = compacted_3_tup2_tup0_tup3;
  assign compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] = compacted_4_tup1;
  assign __phi_halo_cell__admit_valid_and_all_active_outputs_ready = __phi_halo_cell__admit_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__admit_valid_and_ready_txfr = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_load_en;
  assign __phi_halo_cell__east_valid_and_all_active_outputs_ready = __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__north_valid_and_ready_txfr = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_load_en;
  assign __phi_halo_cell__east_valid_and_ready_txfr = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_load_en;
  assign __phi_halo_cell__west_valid_and_ready_txfr = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_load_en;
  assign __phi_halo_cell__south_valid_and_ready_txfr = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_load_en;
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_9493 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_9495 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_9497 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_9499 = ~p0_all_active_outputs_ready | ____state_5__at_most_one_next_value | reset;
  assign or_9501 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_9503 = ~p0_all_active_outputs_ready | ____state_8_tuple_element_0__at_most_one_next_value | reset;
  assign or_9505 = ~p0_all_active_outputs_ready | ____state_8_tuple_element_1__at_most_one_next_value | reset;
  assign and_9165 = and_8779 & p0_all_active_outputs_ready;
  assign Xls_clause_1_NextAnyon_1 = ____state_7 ^ Xls_clause_1_Value1_1;
  assign and_9167 = and_8758 & p0_all_active_outputs_ready;
  assign one_hot_sel_9059 = add_8747 & {8{concat_9058[0]}} | admitted_occupied & {8{concat_9058[1]}};
  assign and_9170 = (and_8772 | and_8773) & p0_all_active_outputs_ready;
  assign and_8965 = ~____state_10 & effective & phase_changed & ~failed;
  assign and_9172 = ~____state_12 & p0_all_active_outputs_ready;
  assign one_hot_sel_9069 = (____state_11 | ____state_9 < MAILBOX_CAPACITY) & concat_9068[0] | (admission_pending | reserve__1) & concat_9068[1];
  assign and_9175 = (nor_8753 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_8963 = ____state_12 | (____state_10 ? ____state_12 : failed);
  assign _27 = _23 + _26;
  assign and_9178 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8684 & ~____state_0 & eq_8697 & _15 & p0_all_active_outputs_ready;
  assign _33 = {compacted_4_tup0, add_8931};
  assign and_8981 = _4 & sign_ext_8932;
  assign and_9182 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8684 & ~____state_0 & eq_8697 & p0_all_active_outputs_ready;
  assign and_8982 = _8 & sign_ext_8932;
  assign one_hot_sel_9093 = postponed_slot_tup0 & concat_9092[0] | compacted_4_tup0 & concat_9092[1] | compacted_4_tup0 & concat_9092[2] | postponed_slot_tup0 & concat_9092[3] | compacted_4_tup0 & concat_9092[4] | postponed_slot_tup0 & concat_9092[5];
  assign and_9187 = (and_8775 | and_8776 | and_8777 | and_8778 | and_8779 | and_8780) & p0_all_active_outputs_ready;
  assign one_hot_sel_9100 = unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9099[0]}} | unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_9099[1]}};
  assign and_9190 = (and_8781 | and_8777) & p0_all_active_outputs_ready;
  assign one_hot_sel_9107 = unexpand_for_next_value_1172_5__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9106[0]}} | unexpand_for_next_value_1172_6__2_case_0_case_1_case_1_case_1_case_0 & {2{concat_9106[1]}};
  assign and_9193 = (and_8782 | and_8779) & p0_all_active_outputs_ready;
  assign one_hot_sel_9117[0] = admitted_slots_tuple_idx_0[0] & concat_9116[0] | postponed_slots_tuple_idx_0[0] & concat_9116[1] | compacted_slots_tuple_idx_0[0] & concat_9116[2] | admitted_slots_tuple_idx_0[0] & concat_9116[3] | unblocked_slots_tuple_idx_0[0] & concat_9116[4];
  assign one_hot_sel_9117[1] = admitted_slots_tuple_idx_0[1] & concat_9116[0] | postponed_slots_tuple_idx_0[1] & concat_9116[1] | compacted_slots_tuple_idx_0[1] & concat_9116[2] | admitted_slots_tuple_idx_0[1] & concat_9116[3] | unblocked_slots_tuple_idx_0[1] & concat_9116[4];
  assign one_hot_sel_9117[2] = admitted_slots_tuple_idx_0[2] & concat_9116[0] | postponed_slots_tuple_idx_0[2] & concat_9116[1] | compacted_slots_tuple_idx_0[2] & concat_9116[2] | admitted_slots_tuple_idx_0[2] & concat_9116[3] | unblocked_slots_tuple_idx_0[2] & concat_9116[4];
  assign one_hot_sel_9117[3] = admitted_slots_tuple_idx_0[3] & concat_9116[0] | postponed_slots_tuple_idx_0[3] & concat_9116[1] | compacted_slots_tuple_idx_0[3] & concat_9116[2] | admitted_slots_tuple_idx_0[3] & concat_9116[3] | unblocked_slots_tuple_idx_0[3] & concat_9116[4];
  assign one_hot_sel_9117[4] = admitted_slots_tuple_idx_0[4] & concat_9116[0] | postponed_slots_tuple_idx_0[4] & concat_9116[1] | compacted_slots_tuple_idx_0[4] & concat_9116[2] | admitted_slots_tuple_idx_0[4] & concat_9116[3] | unblocked_slots_tuple_idx_0[4] & concat_9116[4];
  assign and_9196 = (nor_8746 | and_8783 | and_8784 | and_8785 | and_8786) & p0_all_active_outputs_ready;
  assign one_hot_sel_9130[0] = admitted_slots_tuple_idx_1[0] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_1[0] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_1[0] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_1[0] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_1[0] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9129[7]}};
  assign one_hot_sel_9130[1] = admitted_slots_tuple_idx_1[1] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_1[1] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_1[1] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_1[1] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_1[1] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9129[7]}};
  assign one_hot_sel_9130[2] = admitted_slots_tuple_idx_1[2] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_1[2] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_1[2] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_1[2] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_1[2] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9129[7]}};
  assign one_hot_sel_9130[3] = admitted_slots_tuple_idx_1[3] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_1[3] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_1[3] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_1[3] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_1[3] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9129[7]}};
  assign one_hot_sel_9130[4] = admitted_slots_tuple_idx_1[4] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_1[4] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_1[4] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_1[4] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_1[4] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9129[7]}};
  assign and_9199 = (and_8783 | and_8784 | and_8785 | and_8786 | and_8787 | and_8788 | and_8789 | and_8790) & p0_all_active_outputs_ready;
  assign one_hot_sel_9143[0] = admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9129[7]}};
  assign one_hot_sel_9143[1] = admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9129[7]}};
  assign one_hot_sel_9143[2] = admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9129[7]}};
  assign one_hot_sel_9143[3] = admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9129[7]}};
  assign one_hot_sel_9143[4] = admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9129[7]}};
  assign one_hot_sel_9156[0] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9129[7]}};
  assign one_hot_sel_9156[1] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9129[7]}};
  assign one_hot_sel_9156[2] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9129[7]}};
  assign one_hot_sel_9156[3] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9129[7]}};
  assign one_hot_sel_9156[4] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9129[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {{{7'h01, ~____state_0}, compacted_4_tup1, compacted_4_tup1, {5'h00, ____state_0 ? 3'h4 : 3'h3}}, {{____state_3_0, ____state_3_1} & {64{~____state_0}}, ____state_2}};
  assign or_9511 = ~p0_all_active_outputs_ready | concat_8712 == one_hot_9458[2:0] | reset;
  always @ (posedge clk) begin
    if (reset) begin
      ____state_11 <= 1'h0;
      ____state_12 <= 1'h0;
      ____state_10 <= 1'h1;
      ____state_8_tuple_element_1[0] <= ____state_8_tuple_element_1_init[0];
      ____state_8_tuple_element_1[1] <= ____state_8_tuple_element_1_init[1];
      ____state_8_tuple_element_1[2] <= ____state_8_tuple_element_1_init[2];
      ____state_8_tuple_element_1[3] <= ____state_8_tuple_element_1_init[3];
      ____state_8_tuple_element_1[4] <= ____state_8_tuple_element_1_init[4];
      ____state_9 <= 8'h00;
      ____state_8_tuple_element_0[0] <= ____state_8_tuple_element_0_init[0];
      ____state_8_tuple_element_0[1] <= ____state_8_tuple_element_0_init[1];
      ____state_8_tuple_element_0[2] <= ____state_8_tuple_element_0_init[2];
      ____state_8_tuple_element_0[3] <= ____state_8_tuple_element_0_init[3];
      ____state_8_tuple_element_0[4] <= ____state_8_tuple_element_0_init[4];
      ____state_0 <= 1'h0;
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0] <= ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[0];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[1] <= ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[1];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[2] <= ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[2];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[3] <= ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[3];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[4] <= ____state_8_tuple_element_2_tuple_element_0_tuple_element_3_init[4];
      ____state_8_tuple_element_2_tuple_element_1[0] <= ____state_8_tuple_element_2_tuple_element_1_init[0];
      ____state_8_tuple_element_2_tuple_element_1[1] <= ____state_8_tuple_element_2_tuple_element_1_init[1];
      ____state_8_tuple_element_2_tuple_element_1[2] <= ____state_8_tuple_element_2_tuple_element_1_init[2];
      ____state_8_tuple_element_2_tuple_element_1[3] <= ____state_8_tuple_element_2_tuple_element_1_init[3];
      ____state_8_tuple_element_2_tuple_element_1[4] <= ____state_8_tuple_element_2_tuple_element_1_init[4];
      ____state_2 <= 32'h0000_0000;
      ____state_5 <= 2'h0;
      ____state_6 <= 2'h0;
      ____state_4_1 <= 32'h0000_0000;
      ____state_4_0 <= 32'h0000_0000;
      ____state_3_1 <= 32'h0000_0000;
      ____state_3_0 <= 32'h0000_0000;
      ____state_7 <= 32'h0000_0000;
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
      ____state_11 <= and_9175 ? one_hot_sel_9069 : ____state_11;
      ____state_12 <= p0_all_active_outputs_ready ? or_8963 : ____state_12;
      ____state_10 <= and_9172 ? and_8965 : ____state_10;
      ____state_8_tuple_element_1[0] <= and_9199 ? one_hot_sel_9130[0] : ____state_8_tuple_element_1[0];
      ____state_8_tuple_element_1[1] <= and_9199 ? one_hot_sel_9130[1] : ____state_8_tuple_element_1[1];
      ____state_8_tuple_element_1[2] <= and_9199 ? one_hot_sel_9130[2] : ____state_8_tuple_element_1[2];
      ____state_8_tuple_element_1[3] <= and_9199 ? one_hot_sel_9130[3] : ____state_8_tuple_element_1[3];
      ____state_8_tuple_element_1[4] <= and_9199 ? one_hot_sel_9130[4] : ____state_8_tuple_element_1[4];
      ____state_9 <= and_9170 ? one_hot_sel_9059 : ____state_9;
      ____state_8_tuple_element_0[0] <= and_9196 ? one_hot_sel_9117[0] : ____state_8_tuple_element_0[0];
      ____state_8_tuple_element_0[1] <= and_9196 ? one_hot_sel_9117[1] : ____state_8_tuple_element_0[1];
      ____state_8_tuple_element_0[2] <= and_9196 ? one_hot_sel_9117[2] : ____state_8_tuple_element_0[2];
      ____state_8_tuple_element_0[3] <= and_9196 ? one_hot_sel_9117[3] : ____state_8_tuple_element_0[3];
      ____state_8_tuple_element_0[4] <= and_9196 ? one_hot_sel_9117[4] : ____state_8_tuple_element_0[4];
      ____state_0 <= and_9187 ? one_hot_sel_9093 : ____state_0;
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0] <= and_9199 ? one_hot_sel_9156[0] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[1] <= and_9199 ? one_hot_sel_9156[1] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[1];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[2] <= and_9199 ? one_hot_sel_9156[2] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[2];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[3] <= and_9199 ? one_hot_sel_9156[3] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[3];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[4] <= and_9199 ? one_hot_sel_9156[4] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[4];
      ____state_8_tuple_element_2_tuple_element_1[0] <= and_9199 ? one_hot_sel_9143[0] : ____state_8_tuple_element_2_tuple_element_1[0];
      ____state_8_tuple_element_2_tuple_element_1[1] <= and_9199 ? one_hot_sel_9143[1] : ____state_8_tuple_element_2_tuple_element_1[1];
      ____state_8_tuple_element_2_tuple_element_1[2] <= and_9199 ? one_hot_sel_9143[2] : ____state_8_tuple_element_2_tuple_element_1[2];
      ____state_8_tuple_element_2_tuple_element_1[3] <= and_9199 ? one_hot_sel_9143[3] : ____state_8_tuple_element_2_tuple_element_1[3];
      ____state_8_tuple_element_2_tuple_element_1[4] <= and_9199 ? one_hot_sel_9143[4] : ____state_8_tuple_element_2_tuple_element_1[4];
      ____state_2 <= and_9165 ? _0__2 : ____state_2;
      ____state_5 <= and_9190 ? one_hot_sel_9100 : ____state_5;
      ____state_6 <= and_9193 ? one_hot_sel_9107 : ____state_6;
      ____state_4_1 <= and_9182 ? and_8982 : ____state_4_1;
      ____state_4_0 <= and_9182 ? and_8981 : ____state_4_0;
      ____state_3_1 <= and_9178 ? _33 : ____state_3_1;
      ____state_3_0 <= and_9178 ? _27 : ____state_3_0;
      ____state_7 <= and_9167 ? Xls_clause_1_NextAnyon_1 : ____state_7;
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
      __phi_halo_cell__east_reg <= phi_halo_cell__east_load_en ? effects_north : __phi_halo_cell__east_reg;
      __phi_halo_cell__east_valid_reg <= phi_halo_cell__east_valid_load_en ? __phi_halo_cell__east_valid_and_not_has_been_sent : __phi_halo_cell__east_valid_reg;
      __phi_halo_cell__west_reg <= phi_halo_cell__west_load_en ? effects_north : __phi_halo_cell__west_reg;
      __phi_halo_cell__west_valid_reg <= phi_halo_cell__west_valid_load_en ? __phi_halo_cell__west_valid_and_not_has_been_sent : __phi_halo_cell__west_valid_reg;
      __phi_halo_cell__south_reg <= phi_halo_cell__south_load_en ? effects_north : __phi_halo_cell__south_reg;
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
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1[__i0] = concat_8610 == __i0 ? and_8609 : ____state_8_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_8610 == __i0 ? and_8613 : ____state_8_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0] = concat_8610 == __i0 ? sel_8675 : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_1_0
    assign admitted_slots_tuple_idx_2_tuple_idx_1[__i0] = concat_8610 == __i0 ? sel_8681 : ____state_8_tuple_element_2_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_8919 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1[__i0] = concat_8919 == __i0 ? extended___state_0 : admitted_slots_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_1_0
    assign postponed_slots_tuple_idx_2_tuple_idx_1[__i0] = concat_8919 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_1 : admitted_slots_tuple_idx_2_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0] = concat_8919 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_9572;
  wire eq_9577;
  wire ne_9561;
  wire and_9578;
  wire or_9575;
  wire [2:0] add_9569;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9564;
  wire popped;
  wire [1:0] sub_9590;
  wire [1:0] add_9592;
  wire [2:0] umod_9570;
  wire [2:0] umod_9565;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9594;
  wire array_update_9601[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9572 = pop_ready & push_valid;
  assign eq_9577 = head == tail;
  assign ne_9561 = head != tail;
  assign and_9578 = eq_9577 & and_9572;
  assign or_9575 = ne_9561 | push_valid;
  assign add_9569 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9564 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9575;
  assign sub_9590 = slots - 2'h1;
  assign add_9592 = slots + 2'h1;
  assign umod_9570 = add_9569 % long_buf_size_lit;
  assign umod_9565 = add_9564 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9570[1:0];
  assign did_push_occur = (can_do_push | and_9572) & push_valid & ~and_9578 & ~is_full_bool;
  assign next_tail_if_pop = umod_9565[1:0];
  assign did_pop_occur = (ne_9561 | and_9572) & pop_ready & ~and_9578;
  assign sel_9594 = pushed ? (popped ? slots : add_9592) : (popped ? sub_9590 : slots);
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
      slots <= sel_9594;
      buf__1[0] <= did_push_occur ? array_update_9601[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9601[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9575;
  assign pop_data = eq_9577 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9601_0
    assign array_update_9601[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9629;
  wire eq_9634;
  wire ne_9618;
  wire and_9635;
  wire or_9632;
  wire [2:0] add_9626;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9621;
  wire popped;
  wire [1:0] sub_9647;
  wire [1:0] add_9649;
  wire [2:0] umod_9627;
  wire [2:0] umod_9622;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9651;
  wire [127:0] array_update_9658[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9629 = pop_ready & push_valid;
  assign eq_9634 = head == tail;
  assign ne_9618 = head != tail;
  assign and_9635 = eq_9634 & and_9629;
  assign or_9632 = ne_9618 | push_valid;
  assign add_9626 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9621 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9632;
  assign sub_9647 = slots - 2'h1;
  assign add_9649 = slots + 2'h1;
  assign umod_9627 = add_9626 % long_buf_size_lit;
  assign umod_9622 = add_9621 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9627[1:0];
  assign did_push_occur = (can_do_push | and_9629) & push_valid & ~and_9635 & ~is_full_bool;
  assign next_tail_if_pop = umod_9622[1:0];
  assign did_pop_occur = (ne_9618 | and_9629) & pop_ready & ~and_9635;
  assign sel_9651 = pushed ? (popped ? slots : add_9649) : (popped ? sub_9647 : slots);
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
      slots <= sel_9651;
      buf__1[0] <= did_push_occur ? array_update_9658[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9658[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9632;
  assign pop_data = eq_9634 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9658_0
    assign array_update_9658[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9686;
  wire eq_9691;
  wire ne_9675;
  wire and_9692;
  wire or_9689;
  wire [2:0] add_9683;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9678;
  wire popped;
  wire [1:0] sub_9704;
  wire [1:0] add_9706;
  wire [2:0] umod_9684;
  wire [2:0] umod_9679;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9708;
  wire [127:0] array_update_9715[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9686 = pop_ready & push_valid;
  assign eq_9691 = head == tail;
  assign ne_9675 = head != tail;
  assign and_9692 = eq_9691 & and_9686;
  assign or_9689 = ne_9675 | push_valid;
  assign add_9683 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9678 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9689;
  assign sub_9704 = slots - 2'h1;
  assign add_9706 = slots + 2'h1;
  assign umod_9684 = add_9683 % long_buf_size_lit;
  assign umod_9679 = add_9678 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9684[1:0];
  assign did_push_occur = (can_do_push | and_9686) & push_valid & ~and_9692 & ~is_full_bool;
  assign next_tail_if_pop = umod_9679[1:0];
  assign did_pop_occur = (ne_9675 | and_9686) & pop_ready & ~and_9692;
  assign sel_9708 = pushed ? (popped ? slots : add_9706) : (popped ? sub_9704 : slots);
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
      slots <= sel_9708;
      buf__1[0] <= did_push_occur ? array_update_9715[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9715[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9689;
  assign pop_data = eq_9691 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9715_0
    assign array_update_9715[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9743;
  wire eq_9748;
  wire ne_9732;
  wire and_9749;
  wire or_9746;
  wire [2:0] add_9740;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9735;
  wire popped;
  wire [1:0] sub_9761;
  wire [1:0] add_9763;
  wire [2:0] umod_9741;
  wire [2:0] umod_9736;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9765;
  wire [127:0] array_update_9772[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9743 = pop_ready & push_valid;
  assign eq_9748 = head == tail;
  assign ne_9732 = head != tail;
  assign and_9749 = eq_9748 & and_9743;
  assign or_9746 = ne_9732 | push_valid;
  assign add_9740 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9735 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9746;
  assign sub_9761 = slots - 2'h1;
  assign add_9763 = slots + 2'h1;
  assign umod_9741 = add_9740 % long_buf_size_lit;
  assign umod_9736 = add_9735 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9741[1:0];
  assign did_push_occur = (can_do_push | and_9743) & push_valid & ~and_9749 & ~is_full_bool;
  assign next_tail_if_pop = umod_9736[1:0];
  assign did_pop_occur = (ne_9732 | and_9743) & pop_ready & ~and_9749;
  assign sel_9765 = pushed ? (popped ? slots : add_9763) : (popped ? sub_9761 : slots);
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
      slots <= sel_9765;
      buf__1[0] <= did_push_occur ? array_update_9772[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9772[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9746;
  assign pop_data = eq_9748 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9772_0
    assign array_update_9772[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9800;
  wire eq_9805;
  wire ne_9789;
  wire and_9806;
  wire or_9803;
  wire [2:0] add_9797;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9792;
  wire popped;
  wire [1:0] sub_9818;
  wire [1:0] add_9820;
  wire [2:0] umod_9798;
  wire [2:0] umod_9793;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9822;
  wire [127:0] array_update_9829[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9800 = pop_ready & push_valid;
  assign eq_9805 = head == tail;
  assign ne_9789 = head != tail;
  assign and_9806 = eq_9805 & and_9800;
  assign or_9803 = ne_9789 | push_valid;
  assign add_9797 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9792 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9803;
  assign sub_9818 = slots - 2'h1;
  assign add_9820 = slots + 2'h1;
  assign umod_9798 = add_9797 % long_buf_size_lit;
  assign umod_9793 = add_9792 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9798[1:0];
  assign did_push_occur = (can_do_push | and_9800) & push_valid & ~and_9806 & ~is_full_bool;
  assign next_tail_if_pop = umod_9793[1:0];
  assign did_pop_occur = (ne_9789 | and_9800) & pop_ready & ~and_9806;
  assign sel_9822 = pushed ? (popped ? slots : add_9820) : (popped ? sub_9818 : slots);
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
      slots <= sel_9822;
      buf__1[0] <= did_push_occur ? array_update_9829[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9829[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9803;
  assign pop_data = eq_9805 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9829_0
    assign array_update_9829[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9857;
  wire eq_9862;
  wire ne_9846;
  wire and_9863;
  wire or_9860;
  wire [2:0] add_9854;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9849;
  wire popped;
  wire [1:0] sub_9875;
  wire [1:0] add_9877;
  wire [2:0] umod_9855;
  wire [2:0] umod_9850;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9879;
  wire [127:0] array_update_9886[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9857 = pop_ready & push_valid;
  assign eq_9862 = head == tail;
  assign ne_9846 = head != tail;
  assign and_9863 = eq_9862 & and_9857;
  assign or_9860 = ne_9846 | push_valid;
  assign add_9854 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9849 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9860;
  assign sub_9875 = slots - 2'h1;
  assign add_9877 = slots + 2'h1;
  assign umod_9855 = add_9854 % long_buf_size_lit;
  assign umod_9850 = add_9849 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9855[1:0];
  assign did_push_occur = (can_do_push | and_9857) & push_valid & ~and_9863 & ~is_full_bool;
  assign next_tail_if_pop = umod_9850[1:0];
  assign did_pop_occur = (ne_9846 | and_9857) & pop_ready & ~and_9863;
  assign sel_9879 = pushed ? (popped ? slots : add_9877) : (popped ? sub_9875 : slots);
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
      slots <= sel_9879;
      buf__1[0] <= did_push_occur ? array_update_9886[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9886[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9860;
  assign pop_data = eq_9862 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9886_0
    assign array_update_9886[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_9354;
  wire instantiation_output_9379;
  wire [127:0] instantiation_output_9403;
  wire instantiation_output_9404;
  wire instantiation_output_9392;
  wire [32:0] instantiation_output_9396;
  wire instantiation_output_9397;
  wire instantiation_output_9367;
  wire [32:0] instantiation_output_9371;
  wire instantiation_output_9372;
  wire instantiation_output_9443;
  wire [32:0] instantiation_output_9447;
  wire instantiation_output_9448;
  wire instantiation_output_9424;
  wire [32:0] instantiation_output_9428;
  wire instantiation_output_9429;
  wire instantiation_output_9346;
  wire instantiation_output_9347;
  wire [127:0] instantiation_output_9359;
  wire instantiation_output_9360;
  wire [127:0] instantiation_output_9384;
  wire instantiation_output_9385;
  wire instantiation_output_9411;
  wire [127:0] instantiation_output_9416;
  wire instantiation_output_9417;
  wire [127:0] instantiation_output_9435;
  wire instantiation_output_9436;
  wire instantiation_output_9894;
  wire instantiation_output_9895;
  wire instantiation_output_9896;
  wire instantiation_output_9901;
  wire [127:0] instantiation_output_9902;
  wire instantiation_output_9903;
  wire instantiation_output_9908;
  wire [127:0] instantiation_output_9909;
  wire instantiation_output_9910;
  wire instantiation_output_9915;
  wire [127:0] instantiation_output_9916;
  wire instantiation_output_9917;
  wire instantiation_output_9922;
  wire [127:0] instantiation_output_9923;
  wire instantiation_output_9924;
  wire instantiation_output_9929;
  wire [127:0] instantiation_output_9930;
  wire instantiation_output_9931;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_9895),
    .phi_halo_cell__admit_vld(instantiation_output_9896),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_9915),
    .phi_halo_cell__admit_rdy(instantiation_output_9354),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_9379),
    .phi_halo_cell__req(instantiation_output_9403),
    .phi_halo_cell__req_vld(instantiation_output_9404),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_9909),
    .phi_halo_cell__north_vld(instantiation_output_9910),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_9392),
    .phi_halo_cell__north_send(instantiation_output_9396),
    .phi_halo_cell__north_send_vld(instantiation_output_9397),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_9902),
    .phi_halo_cell__east_vld(instantiation_output_9903),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_9367),
    .phi_halo_cell__east_send(instantiation_output_9371),
    .phi_halo_cell__east_send_vld(instantiation_output_9372),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_9930),
    .phi_halo_cell__west_vld(instantiation_output_9931),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_9443),
    .phi_halo_cell__west_send(instantiation_output_9447),
    .phi_halo_cell__west_send_vld(instantiation_output_9448),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_9923),
    .phi_halo_cell__south_vld(instantiation_output_9924),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_9424),
    .phi_halo_cell__south_send(instantiation_output_9428),
    .phi_halo_cell__south_send_vld(instantiation_output_9429),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_9894),
    .phi_halo_cell__east_rdy(instantiation_output_9901),
    .phi_halo_cell__north_rdy(instantiation_output_9908),
    .phi_halo_cell__req(instantiation_output_9916),
    .phi_halo_cell__req_vld(instantiation_output_9917),
    .phi_halo_cell__south_rdy(instantiation_output_9922),
    .phi_halo_cell__west_rdy(instantiation_output_9929),
    .phi_halo_cell__admit(instantiation_output_9346),
    .phi_halo_cell__admit_vld(instantiation_output_9347),
    .phi_halo_cell__east(instantiation_output_9359),
    .phi_halo_cell__east_vld(instantiation_output_9360),
    .phi_halo_cell__north(instantiation_output_9384),
    .phi_halo_cell__north_vld(instantiation_output_9385),
    .phi_halo_cell__req_rdy(instantiation_output_9411),
    .phi_halo_cell__south(instantiation_output_9416),
    .phi_halo_cell__south_vld(instantiation_output_9417),
    .phi_halo_cell__west(instantiation_output_9435),
    .phi_halo_cell__west_vld(instantiation_output_9436),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_9346),
    .push_valid(instantiation_output_9347),
    .pop_ready(instantiation_output_9354),
    .push_ready(instantiation_output_9894),
    .pop_data(instantiation_output_9895),
    .pop_valid(instantiation_output_9896),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_9359),
    .push_valid(instantiation_output_9360),
    .pop_ready(instantiation_output_9367),
    .push_ready(instantiation_output_9901),
    .pop_data(instantiation_output_9902),
    .pop_valid(instantiation_output_9903),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_9384),
    .push_valid(instantiation_output_9385),
    .pop_ready(instantiation_output_9392),
    .push_ready(instantiation_output_9908),
    .pop_data(instantiation_output_9909),
    .pop_valid(instantiation_output_9910),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_9403),
    .push_valid(instantiation_output_9404),
    .pop_ready(instantiation_output_9411),
    .push_ready(instantiation_output_9915),
    .pop_data(instantiation_output_9916),
    .pop_valid(instantiation_output_9917),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_9416),
    .push_valid(instantiation_output_9417),
    .pop_ready(instantiation_output_9424),
    .push_ready(instantiation_output_9922),
    .pop_data(instantiation_output_9923),
    .pop_valid(instantiation_output_9924),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_9435),
    .push_valid(instantiation_output_9436),
    .pop_ready(instantiation_output_9443),
    .push_ready(instantiation_output_9929),
    .pop_data(instantiation_output_9930),
    .pop_valid(instantiation_output_9931),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_9371;
  assign phi_halo_cell__east_send_vld = instantiation_output_9372;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_9379;
  assign phi_halo_cell__north_send = instantiation_output_9396;
  assign phi_halo_cell__north_send_vld = instantiation_output_9397;
  assign phi_halo_cell__south_send = instantiation_output_9428;
  assign phi_halo_cell__south_send_vld = instantiation_output_9429;
  assign phi_halo_cell__west_send = instantiation_output_9447;
  assign phi_halo_cell__west_send_vld = instantiation_output_9448;
endmodule
