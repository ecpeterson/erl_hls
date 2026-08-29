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
  wire [32:0] literal_4186 = {1'h0, 32'h0000_0000};
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
  wire and_4196;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_4195;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_4208;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_5126;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_5125;
  wire [31:0] sel_5124;
  wire [31:0] sel_5123;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_4253;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_5128;
  wire nand_4224;
  wire [127:0] one_hot_sel_4254;
  wire and_4268;
  wire [7:0] one_hot_sel_4261;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_4186;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_4196 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_4196;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_4195 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_4196;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_4195, and_4196};
  assign one_hot_4208 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_5126 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_5125 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_5124 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_5123 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_4195 == one_hot_4208[1] & and_4196 == one_hot_4208[0];
  assign concat_4253 = {nor_4195 & p0_stage_done, and_4196 & p0_stage_done};
  assign payload = {sel_5125, sel_5124, sel_5123, sel_5126};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_5128 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_4224 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_4254 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_4253[0]}} | payload & {128{concat_4253[1]}};
  assign and_4268 = (nor_4195 | and_4196) & p0_stage_done;
  assign one_hot_sel_4261 = 8'h00 & {8{concat_4253[0]}} | words_seen & {8{concat_4253[1]}};
  assign __phi_halo_cell__req_buf = {{sel_5126[7:0], sel_5126[15:8], sel_5126[23:16], sel_5126[31:24]}, {sel_5125, sel_5124, sel_5123}};
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
      ____state_0 <= p0_stage_done ? nand_4224 : ____state_0;
      ____state_2 <= and_4268 ? one_hot_sel_4261 : ____state_2;
      ____state_1 <= and_4268 ? one_hot_sel_4254 : ____state_1;
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
  input wire phi_halo_cell__ext_send_rdy,
  input wire [127:0] phi_halo_cell__resp,
  input wire phi_halo_cell__resp_vld,
  output wire [32:0] phi_halo_cell__ext_send,
  output wire phi_halo_cell__ext_send_vld,
  output wire phi_halo_cell__resp_rdy
);
  wire [127:0] __phi_halo_cell__resp_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__ext_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_4324 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__resp_reg;
  reg __phi_halo_cell__resp_valid_reg;
  reg [32:0] __phi_halo_cell__ext_send_reg;
  reg __phi_halo_cell__ext_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__resp_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__ext_send_valid_inv;
  wire nor_4336;
  wire not_4337;
  wire __phi_halo_cell__ext_send_vld_buf;
  wire phi_halo_cell__ext_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__ext_send_load_en;
  wire [2:0] one_hot_4346;
  wire [2:0] one_hot_4347;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__resp_valid_inv;
  wire and_4386;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__resp_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_4389;
  wire [127:0] payload;
  wire [1:0] concat_4402;
  wire [7:0] beats_sent;
  wire phi_halo_cell__resp_load_en;
  wire or_5132;
  wire or_5136;
  wire [7:0] one_hot_sel_4390;
  wire and_4410;
  wire [127:0] one_hot_sel_4397;
  wire [7:0] one_hot_sel_4403;
  wire [32:0] __phi_halo_cell__ext_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__resp_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__resp_reg : literal_4324;
  assign frame_header__1 = phi_halo_cell__resp_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__ext_send_valid_inv = ~__phi_halo_cell__ext_send_valid_reg;
  assign nor_4336 = ~(last | ____state_0);
  assign not_4337 = ~last;
  assign __phi_halo_cell__ext_send_vld_buf = ____state_0 | __phi_halo_cell__resp_valid_reg;
  assign phi_halo_cell__ext_send_valid_load_en = phi_halo_cell__ext_send_rdy | phi_halo_cell__ext_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_4336};
  assign ____state_6__next_value_predicates = {not_4337, last};
  assign phi_halo_cell__ext_send_load_en = __phi_halo_cell__ext_send_vld_buf & phi_halo_cell__ext_send_valid_load_en;
  assign one_hot_4346 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_4347 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__ext_send_vld_buf & phi_halo_cell__ext_send_load_en;
  assign phi_halo_cell__resp_valid_inv = ~__phi_halo_cell__resp_valid_reg;
  assign and_4386 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__resp_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__resp_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__resp_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_4346[1] & nor_4336 == one_hot_4346[0];
  assign ____state_6__at_most_one_next_value = not_4337 == one_hot_4347[1] & last == one_hot_4347[0];
  assign concat_4389 = {and_4386, nor_4336 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_4402 = {not_4337 & p0_stage_done, and_4386};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__resp_load_en = phi_halo_cell__resp_vld & phi_halo_cell__resp_valid_load_en;
  assign or_5132 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_5136 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_4390 = frame_header_payload_words__1 & {8{concat_4389[0]}} | 8'h00 & {8{concat_4389[1]}};
  assign and_4410 = (last | nor_4336) & p0_stage_done;
  assign one_hot_sel_4397 = payload & {128{concat_4389[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_4389[1]}};
  assign one_hot_sel_4403 = 8'h00 & {8{concat_4402[0]}} | beats_sent & {8{concat_4402[1]}};
  assign __phi_halo_cell__ext_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__resp_reg <= __phi_halo_cell__resp_reg_init;
      __phi_halo_cell__resp_valid_reg <= 1'h0;
      __phi_halo_cell__ext_send_reg <= __phi_halo_cell__ext_send_reg_init;
      __phi_halo_cell__ext_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_4337 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_4403 : ____state_6;
      ____state_1 <= and_4410 ? one_hot_sel_4390 : ____state_1;
      ____state_5 <= and_4410 ? one_hot_sel_4397 : ____state_5;
      __phi_halo_cell__resp_reg <= phi_halo_cell__resp_load_en ? phi_halo_cell__resp : __phi_halo_cell__resp_reg;
      __phi_halo_cell__resp_valid_reg <= phi_halo_cell__resp_valid_load_en ? phi_halo_cell__resp_vld : __phi_halo_cell__resp_valid_reg;
      __phi_halo_cell__ext_send_reg <= phi_halo_cell__ext_send_load_en ? __phi_halo_cell__ext_send_buf : __phi_halo_cell__ext_send_reg;
      __phi_halo_cell__ext_send_valid_reg <= phi_halo_cell__ext_send_valid_load_en ? __phi_halo_cell__ext_send_vld_buf : __phi_halo_cell__ext_send_valid_reg;
    end
  end
  assign phi_halo_cell__ext_send = __phi_halo_cell__ext_send_reg;
  assign phi_halo_cell__ext_send_vld = __phi_halo_cell__ext_send_valid_reg;
  assign phi_halo_cell__resp_rdy = phi_halo_cell__resp_load_en;
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
  input wire [127:0] phi_halo_cell__req,
  input wire phi_halo_cell__req_vld,
  input wire phi_halo_cell__resp_rdy,
  output wire phi_halo_cell__admit,
  output wire phi_halo_cell__admit_vld,
  output wire phi_halo_cell__req_rdy,
  output wire [127:0] phi_halo_cell__resp,
  output wire phi_halo_cell__resp_vld
);
  wire [7:0] ____state_6_tuple_element_1_init[0:4];
  assign ____state_6_tuple_element_1_init[0] = 8'h00;
  assign ____state_6_tuple_element_1_init[1] = 8'h00;
  assign ____state_6_tuple_element_1_init[2] = 8'h00;
  assign ____state_6_tuple_element_1_init[3] = 8'h00;
  assign ____state_6_tuple_element_1_init[4] = 8'h00;
  wire ____state_6_tuple_element_0_init[0:4];
  assign ____state_6_tuple_element_0_init[0] = 1'h0;
  assign ____state_6_tuple_element_0_init[1] = 1'h0;
  assign ____state_6_tuple_element_0_init[2] = 1'h0;
  assign ____state_6_tuple_element_0_init[3] = 1'h0;
  assign ____state_6_tuple_element_0_init[4] = 1'h0;
  wire [31:0] ____state_6_tuple_element_2_tuple_element_0_init[0:4];
  assign ____state_6_tuple_element_2_tuple_element_0_init[0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_0_init[1] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_0_init[2] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_0_init[3] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_0_init[4] = 32'h0000_0000;
  wire [31:0] ____state_6_tuple_element_2_tuple_element_1_init[0:4][0:1];
  assign ____state_6_tuple_element_2_tuple_element_1_init[0][0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[0][1] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[1][0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[1][1] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[2][0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[2][1] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[3][0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[3][1] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[4][0] = 32'h0000_0000;
  assign ____state_6_tuple_element_2_tuple_element_1_init[4][1] = 32'h0000_0000;
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__resp_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_4499 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [31:0] _50[0:1];
  assign _50[0] = 32'h0000_0000;
  assign _50[1] = 32'h0000_0000;
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  reg __state_machine_state_machine___state_8;
  reg ____state_11;
  reg ____state_12;
  reg [7:0] ____state_6_tuple_element_1[0:4];
  reg [7:0] ____state_7;
  reg ____state_6_tuple_element_0[0:4];
  reg ____state_0;
  reg [31:0] ____state_6_tuple_element_2_tuple_element_0[0:4];
  reg [31:0] ____state_1;
  reg [1:0] ____state_4;
  reg [31:0] ____state_6_tuple_element_2_tuple_element_1[0:4][0:1];
  reg [31:0] ____state_3_0;
  reg [31:0] ____state_2_0;
  reg [31:0] ____state_2_1;
  reg [31:0] ____state_3_1;
  reg __phi_halo_cell__resp_has_been_sent_reg;
  reg __phi_halo_cell__admit_has_been_sent_reg;
  reg [127:0] __phi_halo_cell__req_reg;
  reg __phi_halo_cell__req_valid_reg;
  reg [127:0] __phi_halo_cell__resp_reg;
  reg __phi_halo_cell__resp_valid_reg;
  reg __phi_halo_cell__admit_reg;
  reg __phi_halo_cell__admit_valid_reg;
  wire nor_4497;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire tag_ok;
  wire nand_4510;
  wire [7:0] and_4514;
  wire [31:0] concat_4515;
  wire [7:0] admitted_slots_tuple_idx_1[0:4];
  wire [6:0] leading_bits___state_0;
  wire accepted;
  wire and_4519;
  wire [7:0] blocked_phase__4;
  wire [7:0] blocked_phase__3;
  wire admitted_slots_tuple_idx_0[0:4];
  wire [7:0] blocked_phase__2;
  wire [7:0] admitted_occupied;
  wire postponed__4;
  wire [7:0] blocked_phase__1;
  wire postponed__3;
  wire ugt_4541;
  wire [7:0] blocked_phase;
  wire postponed__2;
  wire or_reduce_4549;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_691_4__2_case_0_case_1;
  wire postponed__1;
  wire ugt_4558;
  wire eligible_3;
  wire [7:0] compacted_4_tup1;
  wire postponed;
  wire or_reduce_4565;
  wire eligible_2;
  wire eligible_1;
  wire eligible_0;
  wire [95:0] frame_payload;
  wire [31:0] sel_4582;
  wire [7:0] selected;
  wire [31:0] admitted_slots_tuple_idx_2_tuple_idx_0[0:4];
  wire [2:0] bit_slice_4585;
  wire [31:0] selected_slot_tuple_idx_2_tuple_idx_0;
  wire [31:0] _1;
  wire current_1;
  wire next_1;
  wire compacted_4_tup0;
  wire found;
  wire valid_1;
  wire [1:0] candidatedirective_1__1;
  wire dispatchable;
  wire ready_1;
  wire [1:0] directive_1;
  wire emit_1;
  wire [1:0] directive;
  wire emits;
  wire invalid_conclusion;
  wire transition_slots_1_case_cmp;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire [31:0] array_index_4609[0:1];
  wire [31:0] array_4610[0:1];
  wire transition_slots_predicate_piece_0;
  wire candidate_slots_0_case_cmp;
  wire nand_4620;
  wire [31:0] sel_4612[0:1];
  wire invalid_input;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_4687;
  wire _61;
  wire [31:0] admitted_slots_tuple_idx_2_tuple_idx_1[0:4][0:1];
  wire failed;
  wire [7:0] candidate_occupied;
  wire [7:0] MAILBOX_CAPACITY;
  wire candidate_phase_squeezed;
  wire [31:0] value0_1;
  wire or_4642;
  wire phase_changed;
  wire [31:0] _10;
  wire postponed_slot_tup0;
  wire and_4654;
  wire reserve;
  wire nor_4653;
  wire [28:0] add_4629;
  wire [31:0] value1_1;
  wire __phi_halo_cell__resp_vld_buf;
  wire __phi_halo_cell__resp_not_has_been_sent;
  wire phi_halo_cell__resp_valid_inv;
  wire __phi_halo_cell__admit_vld_buf;
  wire __phi_halo_cell__admit_not_has_been_sent;
  wire phi_halo_cell__admit_valid_inv;
  wire nor_4658;
  wire candidate_occupied_0_case_cmp;
  wire and_4662;
  wire and_4663;
  wire or_4664;
  wire [30:0] add_4636;
  wire [31:0] _14;
  wire __phi_halo_cell__resp_valid_and_not_has_been_sent;
  wire phi_halo_cell__resp_valid_load_en;
  wire __phi_halo_cell__admit_valid_and_not_has_been_sent;
  wire phi_halo_cell__admit_valid_load_en;
  wire and_4670;
  wire and_4671;
  wire and_4672;
  wire and_4673;
  wire and_4674;
  wire and_4675;
  wire and_4676;
  wire and_4677;
  wire and_4678;
  wire and_4679;
  wire and_4680;
  wire and_4681;
  wire and_4682;
  wire [30:0] add_4646;
  wire [28:0] add_4649;
  wire phi_halo_cell__resp_not_pred;
  wire phi_halo_cell__resp_load_en;
  wire phi_halo_cell__admit_not_pred;
  wire phi_halo_cell__admit_load_en;
  wire [1:0] ____state_7__next_value_predicates;
  wire [1:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_4__next_value_predicates;
  wire [4:0] ____state_6_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_6_tuple_element_1__next_value_predicates;
  wire [30:0] add_4656;
  wire [2:0] one_hot_4715;
  wire [2:0] one_hot_4716;
  wire [2:0] one_hot_4717;
  wire [5:0] one_hot_4718;
  wire [8:0] one_hot_4719;
  wire [31:0] array_index_4703;
  wire [31:0] array_index_4705;
  wire [31:0] array_index_4707;
  wire [31:0] array_index_4711[0:1];
  wire [31:0] array_index_4712[0:1];
  wire [31:0] array_index_4713[0:1];
  wire [31:0] array_index_4714[0:1];
  wire [30:0] add_4668;
  wire p0_all_active_outputs_ready;
  wire ne_4728;
  wire or_reduce_4730;
  wire ugt_4732;
  wire [31:0] sel_4745[0:1];
  wire [31:0] array_index_4746[0:1];
  wire [31:0] sel_4747[0:1];
  wire [31:0] sel_4748[0:1];
  wire [31:0] sel_4749[0:1];
  wire [28:0] add_4684;
  wire phi_halo_cell__req_valid_inv;
  wire and_4914;
  wire and_4921;
  wire and_4922;
  wire and_4923;
  wire and_4924;
  wire [31:0] concat_4782;
  wire compacted_0_tup0;
  wire compacted_1_tup0;
  wire compacted_2_tup0;
  wire compacted_3_tup0;
  wire [7:0] extended___state_0;
  wire [7:0] compacted_0_tup1;
  wire [7:0] compacted_1_tup1;
  wire [7:0] compacted_2_tup1;
  wire [7:0] compacted_3_tup1;
  wire [31:0] compacted_0_tup2_tup0;
  wire [31:0] compacted_1_tup2_tup0;
  wire [31:0] compacted_2_tup2_tup0;
  wire [31:0] compacted_3_tup2_tup0;
  wire [31:0] compacted_4_tup2_tup0;
  wire [31:0] selected_slot_tuple_idx_2_tuple_idx_1[0:1];
  wire [31:0] compacted_0_tup2_tup1[0:1];
  wire [31:0] compacted_1_tup2_tup1[0:1];
  wire [31:0] compacted_2_tup2_tup1[0:1];
  wire [31:0] compacted_3_tup2_tup1[0:1];
  wire [7:0] concat_4693;
  wire phi_halo_cell__req_valid_load_en;
  wire ____state_7__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_4__at_most_one_next_value;
  wire ____state_6_tuple_element_0__at_most_one_next_value;
  wire ____state_6_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_4884;
  wire admission_pending;
  wire [31:0] sign_ext_4794;
  wire [1:0] concat_4909;
  wire [1:0] concat_4916;
  wire [1:0] unexpand_for_next_value_691_4__2_case_0_case_0;
  wire [4:0] concat_4926;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_4939;
  wire [7:0] postponed_slots_tuple_idx_1[0:4];
  wire [7:0] compacted_slots_tuple_idx_1[0:4];
  wire [31:0] postponed_slots_tuple_idx_2_tuple_idx_0[0:4];
  wire [31:0] compacted_slots_tuple_idx_2_tuple_idx_0[0:4];
  wire [31:0] postponed_slots_tuple_idx_2_tuple_idx_1[0:4][0:1];
  wire [31:0] compacted_slots_tuple_idx_2_tuple_idx_1[0:4][0:1];
  wire __phi_halo_cell__resp_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__resp_valid_and_ready_txfr;
  wire __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__admit_valid_and_ready_txfr;
  wire phi_halo_cell__req_load_en;
  wire or_5138;
  wire or_5140;
  wire or_5142;
  wire or_5144;
  wire or_5146;
  wire and_4973;
  wire [7:0] one_hot_sel_4885;
  wire and_4976;
  wire or_4816;
  wire and_4978;
  wire or_4817;
  wire and_4980;
  wire [31:0] _42__1;
  wire and_4982;
  wire [31:0] new1_1;
  wire [31:0] and_4830;
  wire and_4986;
  wire [31:0] and_4831;
  wire one_hot_sel_4910;
  wire and_4991;
  wire [1:0] one_hot_sel_4917;
  wire and_4994;
  wire one_hot_sel_4927[0:4];
  wire and_4997;
  wire [7:0] one_hot_sel_4940[0:4];
  wire and_5000;
  wire [31:0] one_hot_sel_4953[0:4];
  wire [31:0] one_hot_sel_4966[0:4][0:1];
  wire __phi_halo_cell__resp_not_stage_load;
  wire __phi_halo_cell__resp_has_been_sent_reg_load_en;
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire [127:0] __phi_halo_cell__resp_buf;
  assign nor_4497 = ~(~__state_machine_state_machine___state_8 | ____state_12 | ~____state_11);
  assign received = nor_4497 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_4499;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign tag_ok = frame_header_op == 8'h03;
  assign nand_4510 = ~(received & tag_ok);
  assign and_4514 = ____state_6_tuple_element_1[____state_7 > 8'h04 ? 3'h4 : ____state_7[2:0]] & {8{nand_4510}};
  assign concat_4515 = {24'h00_0000, ____state_7};
  assign leading_bits___state_0 = 7'h00;
  assign accepted = received & tag_ok;
  assign and_4519 = nand_4510 & ____state_6_tuple_element_0[____state_7 > 8'h04 ? 3'h4 : ____state_7[2:0]];
  assign blocked_phase__4 = admitted_slots_tuple_idx_1[3'h4];
  assign blocked_phase__3 = admitted_slots_tuple_idx_1[3'h3];
  assign blocked_phase__2 = admitted_slots_tuple_idx_1[3'h2];
  assign admitted_occupied = ____state_7 + {leading_bits___state_0, accepted};
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign blocked_phase__1 = admitted_slots_tuple_idx_1[3'h1];
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign ugt_4541 = admitted_occupied > 8'h04;
  assign blocked_phase = admitted_slots_tuple_idx_1[3'h0];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign or_reduce_4549 = |admitted_occupied[7:2];
  assign eligible_4 = ugt_4541 & ~(postponed__4 & blocked_phase__4[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__4[0]);
  assign unexpand_for_next_value_691_4__2_case_0_case_1 = 2'h0;
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign ugt_4558 = admitted_occupied > 8'h02;
  assign eligible_3 = or_reduce_4549 & ~(postponed__3 & blocked_phase__3[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__3[0]);
  assign compacted_4_tup1 = 8'h00;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign or_reduce_4565 = |admitted_occupied[7:1];
  assign eligible_2 = ugt_4558 & ~(postponed__2 & blocked_phase__2[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__2[0]);
  assign eligible_1 = or_reduce_4565 & ~(postponed__1 & blocked_phase__1[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__1[0]);
  assign eligible_0 = admitted_occupied != compacted_4_tup1 & ~(postponed & blocked_phase[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase[0]);
  assign frame_payload = phi_halo_cell__req_select[95:0];
  assign sel_4582 = accepted ? frame_payload[31:0] : ____state_6_tuple_element_2_tuple_element_0[____state_7 > 8'h04 ? 3'h4 : ____state_7[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_691_4__2_case_0_case_1}))} & {8{~eligible_0}};
  assign bit_slice_4585 = selected[2:0];
  assign selected_slot_tuple_idx_2_tuple_idx_0 = admitted_slots_tuple_idx_2_tuple_idx_0[bit_slice_4585 > 3'h4 ? 3'h4 : bit_slice_4585];
  assign _1 = ____state_1 + 32'h0000_0001;
  assign current_1 = selected_slot_tuple_idx_2_tuple_idx_0 == ____state_1;
  assign next_1 = selected_slot_tuple_idx_2_tuple_idx_0 == _1;
  assign compacted_4_tup0 = 1'h0;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign valid_1 = current_1 | next_1;
  assign candidatedirective_1__1 = {compacted_4_tup0, next_1};
  assign dispatchable = found & ~(received & ~tag_ok);
  assign ready_1 = ____state_4 == 2'h3;
  assign directive_1 = valid_1 ? candidatedirective_1__1 : 2'h2;
  assign emit_1 = current_1 & ready_1;
  assign directive = directive_1 & {2{dispatchable}};
  assign emits = ~(~(dispatchable & emit_1));
  assign invalid_conclusion = directive != unexpand_for_next_value_691_4__2_case_0_case_1 & emits;
  assign transition_slots_1_case_cmp = directive[0];
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_conclusion;
  assign array_index_4609[0] = ____state_6_tuple_element_2_tuple_element_1[____state_7 > 8'h04 ? 3'h4 : ____state_7[2:0]][0];
  assign array_index_4609[1] = ____state_6_tuple_element_2_tuple_element_1[____state_7 > 8'h04 ? 3'h4 : ____state_7[2:0]][1];
  assign array_4610[0] = frame_payload[95:64];
  assign array_4610[1] = frame_payload[63:32];
  assign transition_slots_predicate_piece_0 = ~(transition_slots_1_case_cmp | transition_slots_default_case_cmp);
  assign candidate_slots_0_case_cmp = ~effective;
  assign nand_4620 = ~(current_1 & ready_1);
  assign sel_4612[0] = accepted == 1'h0 ? array_index_4609[0] : array_4610[0];
  assign sel_4612[1] = accepted == 1'h0 ? array_index_4609[1] : array_4610[1];
  assign invalid_input = ~(~received | tag_ok);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_4687 = admitted_occupied + 8'hff;
  assign _61 = ~____state_0;
  assign failed = invalid_input | invalid_conclusion | transition_slots_default_case_cmp;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_4687 : admitted_occupied;
  assign MAILBOX_CAPACITY = 8'h05;
  assign candidate_phase_squeezed = candidate_slots_0_case_cmp | nand_4620 ? ____state_0 : _61;
  assign value0_1 = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_4585 > 3'h4 ? 3'h4 : bit_slice_4585][compacted_4_tup0];
  assign or_4642 = ~__state_machine_state_machine___state_8 | ____state_12 | candidate_slots_0_case_cmp;
  assign phase_changed = candidate_phase_squeezed ^ ____state_0;
  assign _10 = ____state_3_0 + value0_1;
  assign postponed_slot_tup0 = 1'h1;
  assign and_4654 = __state_machine_state_machine___state_8 & ~____state_12 & transition_slots_predicate_piece_0 & emits;
  assign reserve = ~failed & ~received & ~(____state_11 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign nor_4653 = ~(~__state_machine_state_machine___state_8 | ____state_12 | phase_changed);
  assign add_4629 = ____state_2_0[30:2] + ____state_2_0[28:0];
  assign value1_1 = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_4585 > 3'h4 ? 3'h4 : bit_slice_4585][postponed_slot_tup0];
  assign __phi_halo_cell__resp_vld_buf = ~__state_machine_state_machine___state_8 | and_4654;
  assign __phi_halo_cell__resp_not_has_been_sent = ~__phi_halo_cell__resp_has_been_sent_reg;
  assign phi_halo_cell__resp_valid_inv = ~__phi_halo_cell__resp_valid_reg;
  assign __phi_halo_cell__admit_vld_buf = __state_machine_state_machine___state_8 & ~____state_12 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign nor_4658 = ~(~__state_machine_state_machine___state_8 | ____state_12);
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_4662 = nor_4653 & effective;
  assign and_4663 = and_4654 & effective;
  assign or_4664 = transition_slots_1_case_cmp | transition_slots_default_case_cmp;
  assign add_4636 = _10[31:1] + ____state_2_1[30:0];
  assign _14 = ____state_3_1 + value1_1;
  assign __phi_halo_cell__resp_valid_and_not_has_been_sent = __phi_halo_cell__resp_vld_buf & __phi_halo_cell__resp_not_has_been_sent;
  assign phi_halo_cell__resp_valid_load_en = phi_halo_cell__resp_rdy | phi_halo_cell__resp_valid_inv;
  assign __phi_halo_cell__admit_valid_and_not_has_been_sent = __phi_halo_cell__admit_vld_buf & __phi_halo_cell__admit_not_has_been_sent;
  assign phi_halo_cell__admit_valid_load_en = phi_halo_cell__admit_rdy | phi_halo_cell__admit_valid_inv;
  assign and_4670 = nor_4658 & candidate_occupied_0_case_cmp;
  assign and_4671 = nor_4658 & candidate_occupied_1_case_cmp;
  assign and_4672 = and_4654 & ____state_0;
  assign and_4673 = and_4654 & _61;
  assign and_4674 = ~(or_4642 | ~current_1) & ~ready_1;
  assign and_4675 = nor_4653 & candidate_slots_0_case_cmp;
  assign and_4676 = and_4662 & transition_slots_predicate_piece_0;
  assign and_4677 = and_4662 & transition_slots_1_case_cmp;
  assign and_4678 = and_4662 & transition_slots_default_case_cmp;
  assign and_4679 = and_4654 & candidate_slots_0_case_cmp;
  assign and_4680 = and_4663 & transition_slots_predicate_piece_0;
  assign and_4681 = and_4663 & next_1 & or_4664;
  assign and_4682 = and_4663 & ~next_1 & or_4664;
  assign add_4646 = add_4636 + {add_4629, ____state_2_0[1:0]};
  assign add_4649 = ____state_2_1[30:2] + ____state_2_1[28:0];
  assign phi_halo_cell__resp_not_pred = ~__phi_halo_cell__resp_vld_buf;
  assign phi_halo_cell__resp_load_en = __phi_halo_cell__resp_valid_and_not_has_been_sent & phi_halo_cell__resp_valid_load_en;
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_vld_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign ____state_7__next_value_predicates = {and_4670, and_4671};
  assign ____state_0__next_value_predicates = {and_4672, and_4673};
  assign ____state_4__next_value_predicates = {and_4674, and_4654};
  assign ____state_6_tuple_element_0__next_value_predicates = {and_4654, and_4675, and_4676, and_4677, and_4678};
  assign ____state_6_tuple_element_1__next_value_predicates = {and_4675, and_4676, and_4677, and_4678, and_4679, and_4680, and_4681, and_4682};
  assign add_4656 = _14[31:1] + ____state_2_0[30:0];
  assign one_hot_4715 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_4716 = {____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_4717 = {____state_4__next_value_predicates[1:0] == 2'h0, ____state_4__next_value_predicates[1] && !____state_4__next_value_predicates[0], ____state_4__next_value_predicates[0]};
  assign one_hot_4718 = {____state_6_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_6_tuple_element_0__next_value_predicates[4] && ____state_6_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_6_tuple_element_0__next_value_predicates[3] && ____state_6_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_6_tuple_element_0__next_value_predicates[2] && ____state_6_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_6_tuple_element_0__next_value_predicates[1] && !____state_6_tuple_element_0__next_value_predicates[0], ____state_6_tuple_element_0__next_value_predicates[0]};
  assign one_hot_4719 = {____state_6_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_6_tuple_element_1__next_value_predicates[7] && ____state_6_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_6_tuple_element_1__next_value_predicates[6] && ____state_6_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_6_tuple_element_1__next_value_predicates[5] && ____state_6_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_6_tuple_element_1__next_value_predicates[4] && ____state_6_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_6_tuple_element_1__next_value_predicates[3] && ____state_6_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_6_tuple_element_1__next_value_predicates[2] && ____state_6_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_6_tuple_element_1__next_value_predicates[1] && !____state_6_tuple_element_1__next_value_predicates[0], ____state_6_tuple_element_1__next_value_predicates[0]};
  assign array_index_4703 = admitted_slots_tuple_idx_2_tuple_idx_0[3'h1];
  assign array_index_4705 = admitted_slots_tuple_idx_2_tuple_idx_0[3'h2];
  assign array_index_4707 = admitted_slots_tuple_idx_2_tuple_idx_0[3'h3];
  assign array_index_4711[0] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h1][0];
  assign array_index_4711[1] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h1][1];
  assign array_index_4712[0] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h2][0];
  assign array_index_4712[1] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h2][1];
  assign array_index_4713[0] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h3][0];
  assign array_index_4713[1] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h3][1];
  assign array_index_4714[0] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h4][0];
  assign array_index_4714[1] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h4][1];
  assign add_4668 = add_4656 + {add_4649, ____state_2_1[1:0]};
  assign p0_all_active_outputs_ready = (phi_halo_cell__resp_not_pred | phi_halo_cell__resp_load_en | __phi_halo_cell__resp_has_been_sent_reg) & (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg);
  assign ne_4728 = bit_slice_4585 != 3'h0;
  assign or_reduce_4730 = |selected[7:1];
  assign ugt_4732 = bit_slice_4585 > 3'h2;
  assign sel_4745[0] = or_reduce_4565 == 1'h0 ? _50[0] : array_index_4711[0];
  assign sel_4745[1] = or_reduce_4565 == 1'h0 ? _50[1] : array_index_4711[1];
  assign array_index_4746[0] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h0][0];
  assign array_index_4746[1] = admitted_slots_tuple_idx_2_tuple_idx_1[3'h0][1];
  assign sel_4747[0] = ugt_4558 == 1'h0 ? _50[0] : array_index_4712[0];
  assign sel_4747[1] = ugt_4558 == 1'h0 ? _50[1] : array_index_4712[1];
  assign sel_4748[0] = or_reduce_4549 == 1'h0 ? _50[0] : array_index_4713[0];
  assign sel_4748[1] = or_reduce_4549 == 1'h0 ? _50[1] : array_index_4713[1];
  assign sel_4749[0] = ugt_4541 == 1'h0 ? _50[0] : array_index_4714[0];
  assign sel_4749[1] = ugt_4541 == 1'h0 ? _50[1] : array_index_4714[1];
  assign add_4684 = {compacted_4_tup0, add_4646[30:3]} + 29'h0000_0005;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_4914 = and_4654 & p0_all_active_outputs_ready;
  assign and_4921 = and_4675 & p0_all_active_outputs_ready;
  assign and_4922 = and_4676 & p0_all_active_outputs_ready;
  assign and_4923 = and_4677 & p0_all_active_outputs_ready;
  assign and_4924 = and_4678 & p0_all_active_outputs_ready;
  assign concat_4782 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_4728 ? postponed : or_reduce_4565 & postponed__1;
  assign compacted_1_tup0 = or_reduce_4730 ? postponed__1 : ugt_4558 & postponed__2;
  assign compacted_2_tup0 = ugt_4732 ? postponed__2 : or_reduce_4549 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_4541 & postponed__4;
  assign extended___state_0 = {leading_bits___state_0, ____state_0};
  assign compacted_0_tup1 = ne_4728 ? blocked_phase : blocked_phase__1 & {8{or_reduce_4565}};
  assign compacted_1_tup1 = or_reduce_4730 ? blocked_phase__1 : blocked_phase__2 & {8{ugt_4558}};
  assign compacted_2_tup1 = ugt_4732 ? blocked_phase__2 : blocked_phase__3 & {8{or_reduce_4549}};
  assign compacted_3_tup1 = selected[2] ? blocked_phase__3 : blocked_phase__4 & {8{ugt_4541}};
  assign compacted_0_tup2_tup0 = ne_4728 ? admitted_slots_tuple_idx_2_tuple_idx_0[3'h0] : array_index_4703 & {32{or_reduce_4565}};
  assign compacted_1_tup2_tup0 = or_reduce_4730 ? array_index_4703 : array_index_4705 & {32{ugt_4558}};
  assign compacted_2_tup2_tup0 = ugt_4732 ? array_index_4705 : array_index_4707 & {32{or_reduce_4549}};
  assign compacted_3_tup2_tup0 = selected[2] ? array_index_4707 : admitted_slots_tuple_idx_2_tuple_idx_0[3'h4] & {32{ugt_4541}};
  assign compacted_4_tup2_tup0 = 32'h0000_0000;
  assign selected_slot_tuple_idx_2_tuple_idx_1[0] = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_4585 > 3'h4 ? 3'h4 : bit_slice_4585][0];
  assign selected_slot_tuple_idx_2_tuple_idx_1[1] = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_4585 > 3'h4 ? 3'h4 : bit_slice_4585][1];
  assign compacted_0_tup2_tup1[0] = ne_4728 == 1'h0 ? sel_4745[0] : array_index_4746[0];
  assign compacted_0_tup2_tup1[1] = ne_4728 == 1'h0 ? sel_4745[1] : array_index_4746[1];
  assign compacted_1_tup2_tup1[0] = or_reduce_4730 == 1'h0 ? sel_4747[0] : array_index_4711[0];
  assign compacted_1_tup2_tup1[1] = or_reduce_4730 == 1'h0 ? sel_4747[1] : array_index_4711[1];
  assign compacted_2_tup2_tup1[0] = ugt_4732 == 1'h0 ? sel_4748[0] : array_index_4712[0];
  assign compacted_2_tup2_tup1[1] = ugt_4732 == 1'h0 ? sel_4748[1] : array_index_4712[1];
  assign compacted_3_tup2_tup1[0] = selected[2] == 1'h0 ? sel_4749[0] : array_index_4713[0];
  assign compacted_3_tup2_tup1[1] = selected[2] == 1'h0 ? sel_4749[1] : array_index_4713[1];
  assign concat_4693 = {6'h00, {2{__phi_halo_cell__resp_vld_buf}}};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_4497 | phi_halo_cell__req_valid_inv;
  assign ____state_7__at_most_one_next_value = and_4670 == one_hot_4715[1] & and_4671 == one_hot_4715[0];
  assign ____state_0__at_most_one_next_value = and_4672 == one_hot_4716[1] & and_4673 == one_hot_4716[0];
  assign ____state_4__at_most_one_next_value = and_4674 == one_hot_4717[1] & and_4654 == one_hot_4717[0];
  assign ____state_6_tuple_element_0__at_most_one_next_value = and_4654 == one_hot_4718[4] & and_4675 == one_hot_4718[3] & and_4676 == one_hot_4718[2] & and_4677 == one_hot_4718[1] & and_4678 == one_hot_4718[0];
  assign ____state_6_tuple_element_1__at_most_one_next_value = and_4675 == one_hot_4719[7] & and_4676 == one_hot_4719[6] & and_4677 == one_hot_4719[5] & and_4678 == one_hot_4719[4] & and_4679 == one_hot_4719[3] & and_4680 == one_hot_4719[2] & and_4681 == one_hot_4719[1] & and_4682 == one_hot_4719[0];
  assign concat_4884 = {and_4670 & p0_all_active_outputs_ready, and_4671 & p0_all_active_outputs_ready};
  assign admission_pending = ~(~____state_11 | received);
  assign sign_ext_4794 = {32{~ready_1}};
  assign concat_4909 = {and_4672 & p0_all_active_outputs_ready, and_4673 & p0_all_active_outputs_ready};
  assign concat_4916 = {and_4674 & p0_all_active_outputs_ready, and_4914};
  assign unexpand_for_next_value_691_4__2_case_0_case_0 = ____state_4 + 2'h1;
  assign concat_4926 = {and_4914, and_4921, and_4922, and_4923, and_4924};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_4939 = {and_4921, and_4922, and_4923, and_4924, and_4679 & p0_all_active_outputs_ready, and_4680 & p0_all_active_outputs_ready, and_4681 & p0_all_active_outputs_ready, and_4682 & p0_all_active_outputs_ready};
  assign compacted_slots_tuple_idx_1[0] = compacted_0_tup1;
  assign compacted_slots_tuple_idx_1[1] = compacted_1_tup1;
  assign compacted_slots_tuple_idx_1[2] = compacted_2_tup1;
  assign compacted_slots_tuple_idx_1[3] = compacted_3_tup1;
  assign compacted_slots_tuple_idx_1[4] = compacted_4_tup1;
  assign compacted_slots_tuple_idx_2_tuple_idx_0[0] = compacted_0_tup2_tup0;
  assign compacted_slots_tuple_idx_2_tuple_idx_0[1] = compacted_1_tup2_tup0;
  assign compacted_slots_tuple_idx_2_tuple_idx_0[2] = compacted_2_tup2_tup0;
  assign compacted_slots_tuple_idx_2_tuple_idx_0[3] = compacted_3_tup2_tup0;
  assign compacted_slots_tuple_idx_2_tuple_idx_0[4] = compacted_4_tup2_tup0;
  assign compacted_slots_tuple_idx_2_tuple_idx_1[0][0] = compacted_0_tup2_tup1[0];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[0][1] = compacted_0_tup2_tup1[1];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[1][0] = compacted_1_tup2_tup1[0];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[1][1] = compacted_1_tup2_tup1[1];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[2][0] = compacted_2_tup2_tup1[0];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[2][1] = compacted_2_tup2_tup1[1];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[3][0] = compacted_3_tup2_tup1[0];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[3][1] = compacted_3_tup2_tup1[1];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[4][0] = _50[0];
  assign compacted_slots_tuple_idx_2_tuple_idx_1[4][1] = _50[1];
  assign __phi_halo_cell__resp_valid_and_all_active_outputs_ready = __phi_halo_cell__resp_vld_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__resp_valid_and_ready_txfr = __phi_halo_cell__resp_valid_and_not_has_been_sent & phi_halo_cell__resp_load_en;
  assign __phi_halo_cell__admit_valid_and_all_active_outputs_ready = __phi_halo_cell__admit_vld_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__admit_valid_and_ready_txfr = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_load_en;
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_5138 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_5140 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_5142 = ~p0_all_active_outputs_ready | ____state_4__at_most_one_next_value | reset;
  assign or_5144 = ~p0_all_active_outputs_ready | ____state_6_tuple_element_0__at_most_one_next_value | reset;
  assign or_5146 = ~p0_all_active_outputs_ready | ____state_6_tuple_element_1__at_most_one_next_value | reset;
  assign and_4973 = and_4654 & p0_all_active_outputs_ready;
  assign one_hot_sel_4885 = add_4687 & {8{concat_4884[0]}} | admitted_occupied & {8{concat_4884[1]}};
  assign and_4976 = (and_4670 | and_4671) & p0_all_active_outputs_ready;
  assign or_4816 = admission_pending | reserve;
  assign and_4978 = nor_4658 & p0_all_active_outputs_ready;
  assign or_4817 = ____state_12 | ~____state_12 & failed;
  assign and_4980 = __state_machine_state_machine___state_8 & p0_all_active_outputs_ready;
  assign _42__1 = {3'h0, add_4684};
  assign and_4982 = ~(or_4642 | nand_4620) & p0_all_active_outputs_ready;
  assign new1_1 = {4'h0, add_4668[30:3]};
  assign and_4830 = _10 & sign_ext_4794;
  assign and_4986 = ~(or_4642 | ~current_1) & p0_all_active_outputs_ready;
  assign and_4831 = _14 & sign_ext_4794;
  assign one_hot_sel_4910 = postponed_slot_tup0 & concat_4909[0] | compacted_4_tup0 & concat_4909[1];
  assign and_4991 = (and_4672 | and_4673) & p0_all_active_outputs_ready;
  assign one_hot_sel_4917 = unexpand_for_next_value_691_4__2_case_0_case_1 & {2{concat_4916[0]}} | unexpand_for_next_value_691_4__2_case_0_case_0 & {2{concat_4916[1]}};
  assign and_4994 = (and_4674 | and_4654) & p0_all_active_outputs_ready;
  assign one_hot_sel_4927[0] = admitted_slots_tuple_idx_0[0] & concat_4926[0] | postponed_slots_tuple_idx_0[0] & concat_4926[1] | compacted_slots_tuple_idx_0[0] & concat_4926[2] | admitted_slots_tuple_idx_0[0] & concat_4926[3] | unblocked_slots_tuple_idx_0[0] & concat_4926[4];
  assign one_hot_sel_4927[1] = admitted_slots_tuple_idx_0[1] & concat_4926[0] | postponed_slots_tuple_idx_0[1] & concat_4926[1] | compacted_slots_tuple_idx_0[1] & concat_4926[2] | admitted_slots_tuple_idx_0[1] & concat_4926[3] | unblocked_slots_tuple_idx_0[1] & concat_4926[4];
  assign one_hot_sel_4927[2] = admitted_slots_tuple_idx_0[2] & concat_4926[0] | postponed_slots_tuple_idx_0[2] & concat_4926[1] | compacted_slots_tuple_idx_0[2] & concat_4926[2] | admitted_slots_tuple_idx_0[2] & concat_4926[3] | unblocked_slots_tuple_idx_0[2] & concat_4926[4];
  assign one_hot_sel_4927[3] = admitted_slots_tuple_idx_0[3] & concat_4926[0] | postponed_slots_tuple_idx_0[3] & concat_4926[1] | compacted_slots_tuple_idx_0[3] & concat_4926[2] | admitted_slots_tuple_idx_0[3] & concat_4926[3] | unblocked_slots_tuple_idx_0[3] & concat_4926[4];
  assign one_hot_sel_4927[4] = admitted_slots_tuple_idx_0[4] & concat_4926[0] | postponed_slots_tuple_idx_0[4] & concat_4926[1] | compacted_slots_tuple_idx_0[4] & concat_4926[2] | admitted_slots_tuple_idx_0[4] & concat_4926[3] | unblocked_slots_tuple_idx_0[4] & concat_4926[4];
  assign and_4997 = (and_4654 | and_4675 | and_4676 | and_4677 | and_4678) & p0_all_active_outputs_ready;
  assign one_hot_sel_4940[0] = admitted_slots_tuple_idx_1[0] & {8{concat_4939[0]}} | postponed_slots_tuple_idx_1[0] & {8{concat_4939[1]}} | compacted_slots_tuple_idx_1[0] & {8{concat_4939[2]}} | admitted_slots_tuple_idx_1[0] & {8{concat_4939[3]}} | admitted_slots_tuple_idx_1[0] & {8{concat_4939[4]}} | postponed_slots_tuple_idx_1[0] & {8{concat_4939[5]}} | compacted_slots_tuple_idx_1[0] & {8{concat_4939[6]}} | admitted_slots_tuple_idx_1[0] & {8{concat_4939[7]}};
  assign one_hot_sel_4940[1] = admitted_slots_tuple_idx_1[1] & {8{concat_4939[0]}} | postponed_slots_tuple_idx_1[1] & {8{concat_4939[1]}} | compacted_slots_tuple_idx_1[1] & {8{concat_4939[2]}} | admitted_slots_tuple_idx_1[1] & {8{concat_4939[3]}} | admitted_slots_tuple_idx_1[1] & {8{concat_4939[4]}} | postponed_slots_tuple_idx_1[1] & {8{concat_4939[5]}} | compacted_slots_tuple_idx_1[1] & {8{concat_4939[6]}} | admitted_slots_tuple_idx_1[1] & {8{concat_4939[7]}};
  assign one_hot_sel_4940[2] = admitted_slots_tuple_idx_1[2] & {8{concat_4939[0]}} | postponed_slots_tuple_idx_1[2] & {8{concat_4939[1]}} | compacted_slots_tuple_idx_1[2] & {8{concat_4939[2]}} | admitted_slots_tuple_idx_1[2] & {8{concat_4939[3]}} | admitted_slots_tuple_idx_1[2] & {8{concat_4939[4]}} | postponed_slots_tuple_idx_1[2] & {8{concat_4939[5]}} | compacted_slots_tuple_idx_1[2] & {8{concat_4939[6]}} | admitted_slots_tuple_idx_1[2] & {8{concat_4939[7]}};
  assign one_hot_sel_4940[3] = admitted_slots_tuple_idx_1[3] & {8{concat_4939[0]}} | postponed_slots_tuple_idx_1[3] & {8{concat_4939[1]}} | compacted_slots_tuple_idx_1[3] & {8{concat_4939[2]}} | admitted_slots_tuple_idx_1[3] & {8{concat_4939[3]}} | admitted_slots_tuple_idx_1[3] & {8{concat_4939[4]}} | postponed_slots_tuple_idx_1[3] & {8{concat_4939[5]}} | compacted_slots_tuple_idx_1[3] & {8{concat_4939[6]}} | admitted_slots_tuple_idx_1[3] & {8{concat_4939[7]}};
  assign one_hot_sel_4940[4] = admitted_slots_tuple_idx_1[4] & {8{concat_4939[0]}} | postponed_slots_tuple_idx_1[4] & {8{concat_4939[1]}} | compacted_slots_tuple_idx_1[4] & {8{concat_4939[2]}} | admitted_slots_tuple_idx_1[4] & {8{concat_4939[3]}} | admitted_slots_tuple_idx_1[4] & {8{concat_4939[4]}} | postponed_slots_tuple_idx_1[4] & {8{concat_4939[5]}} | compacted_slots_tuple_idx_1[4] & {8{concat_4939[6]}} | admitted_slots_tuple_idx_1[4] & {8{concat_4939[7]}};
  assign and_5000 = (and_4675 | and_4676 | and_4677 | and_4678 | and_4679 | and_4680 | and_4681 | and_4682) & p0_all_active_outputs_ready;
  assign one_hot_sel_4953[0] = admitted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0[0] & {32{concat_4939[7]}};
  assign one_hot_sel_4953[1] = admitted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0[1] & {32{concat_4939[7]}};
  assign one_hot_sel_4953[2] = admitted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0[2] & {32{concat_4939[7]}};
  assign one_hot_sel_4953[3] = admitted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0[3] & {32{concat_4939[7]}};
  assign one_hot_sel_4953[4] = admitted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0[4] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[0][0] = admitted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][0] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[0][1] = admitted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0][1] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[1][0] = admitted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][0] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[1][1] = admitted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1][1] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[2][0] = admitted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][0] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[2][1] = admitted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2][1] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[3][0] = admitted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][0] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[3][1] = admitted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3][1] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[4][0] = admitted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][0] & {32{concat_4939[7]}};
  assign one_hot_sel_4966[4][1] = admitted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4][1] & {32{concat_4939[7]}};
  assign __phi_halo_cell__resp_not_stage_load = ~__phi_halo_cell__resp_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__resp_has_been_sent_reg_load_en = __phi_halo_cell__resp_valid_and_ready_txfr | __phi_halo_cell__resp_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__resp_buf = {{concat_4693, compacted_4_tup1, compacted_4_tup1, concat_4693}, {3'h0, add_4684, 4'h0, add_4668[30:3], _1} & {96{and_4654}}};
  always @ (posedge clk) begin
    if (reset) begin
      __state_machine_state_machine___state_8 <= 1'h0;
      ____state_11 <= 1'h0;
      ____state_12 <= 1'h0;
      ____state_6_tuple_element_1[0] <= ____state_6_tuple_element_1_init[0];
      ____state_6_tuple_element_1[1] <= ____state_6_tuple_element_1_init[1];
      ____state_6_tuple_element_1[2] <= ____state_6_tuple_element_1_init[2];
      ____state_6_tuple_element_1[3] <= ____state_6_tuple_element_1_init[3];
      ____state_6_tuple_element_1[4] <= ____state_6_tuple_element_1_init[4];
      ____state_7 <= 8'h00;
      ____state_6_tuple_element_0[0] <= ____state_6_tuple_element_0_init[0];
      ____state_6_tuple_element_0[1] <= ____state_6_tuple_element_0_init[1];
      ____state_6_tuple_element_0[2] <= ____state_6_tuple_element_0_init[2];
      ____state_6_tuple_element_0[3] <= ____state_6_tuple_element_0_init[3];
      ____state_6_tuple_element_0[4] <= ____state_6_tuple_element_0_init[4];
      ____state_0 <= 1'h0;
      ____state_6_tuple_element_2_tuple_element_0[0] <= ____state_6_tuple_element_2_tuple_element_0_init[0];
      ____state_6_tuple_element_2_tuple_element_0[1] <= ____state_6_tuple_element_2_tuple_element_0_init[1];
      ____state_6_tuple_element_2_tuple_element_0[2] <= ____state_6_tuple_element_2_tuple_element_0_init[2];
      ____state_6_tuple_element_2_tuple_element_0[3] <= ____state_6_tuple_element_2_tuple_element_0_init[3];
      ____state_6_tuple_element_2_tuple_element_0[4] <= ____state_6_tuple_element_2_tuple_element_0_init[4];
      ____state_1 <= 32'h0000_0000;
      ____state_4 <= 2'h0;
      ____state_6_tuple_element_2_tuple_element_1[0][0] <= ____state_6_tuple_element_2_tuple_element_1_init[0][0];
      ____state_6_tuple_element_2_tuple_element_1[0][1] <= ____state_6_tuple_element_2_tuple_element_1_init[0][1];
      ____state_6_tuple_element_2_tuple_element_1[1][0] <= ____state_6_tuple_element_2_tuple_element_1_init[1][0];
      ____state_6_tuple_element_2_tuple_element_1[1][1] <= ____state_6_tuple_element_2_tuple_element_1_init[1][1];
      ____state_6_tuple_element_2_tuple_element_1[2][0] <= ____state_6_tuple_element_2_tuple_element_1_init[2][0];
      ____state_6_tuple_element_2_tuple_element_1[2][1] <= ____state_6_tuple_element_2_tuple_element_1_init[2][1];
      ____state_6_tuple_element_2_tuple_element_1[3][0] <= ____state_6_tuple_element_2_tuple_element_1_init[3][0];
      ____state_6_tuple_element_2_tuple_element_1[3][1] <= ____state_6_tuple_element_2_tuple_element_1_init[3][1];
      ____state_6_tuple_element_2_tuple_element_1[4][0] <= ____state_6_tuple_element_2_tuple_element_1_init[4][0];
      ____state_6_tuple_element_2_tuple_element_1[4][1] <= ____state_6_tuple_element_2_tuple_element_1_init[4][1];
      ____state_3_0 <= 32'h0000_0000;
      ____state_2_0 <= 32'h0000_0000;
      ____state_2_1 <= 32'h0000_0000;
      ____state_3_1 <= 32'h0000_0000;
      __phi_halo_cell__resp_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__admit_has_been_sent_reg <= 1'h0;
      __phi_halo_cell__req_reg <= __phi_halo_cell__req_reg_init;
      __phi_halo_cell__req_valid_reg <= 1'h0;
      __phi_halo_cell__resp_reg <= __phi_halo_cell__resp_reg_init;
      __phi_halo_cell__resp_valid_reg <= 1'h0;
      __phi_halo_cell__admit_reg <= 1'h0;
      __phi_halo_cell__admit_valid_reg <= 1'h0;
    end else begin
      __state_machine_state_machine___state_8 <= p0_all_active_outputs_ready ? postponed_slot_tup0 : __state_machine_state_machine___state_8;
      ____state_11 <= and_4978 ? or_4816 : ____state_11;
      ____state_12 <= and_4980 ? or_4817 : ____state_12;
      ____state_6_tuple_element_1[0] <= and_5000 ? one_hot_sel_4940[0] : ____state_6_tuple_element_1[0];
      ____state_6_tuple_element_1[1] <= and_5000 ? one_hot_sel_4940[1] : ____state_6_tuple_element_1[1];
      ____state_6_tuple_element_1[2] <= and_5000 ? one_hot_sel_4940[2] : ____state_6_tuple_element_1[2];
      ____state_6_tuple_element_1[3] <= and_5000 ? one_hot_sel_4940[3] : ____state_6_tuple_element_1[3];
      ____state_6_tuple_element_1[4] <= and_5000 ? one_hot_sel_4940[4] : ____state_6_tuple_element_1[4];
      ____state_7 <= and_4976 ? one_hot_sel_4885 : ____state_7;
      ____state_6_tuple_element_0[0] <= and_4997 ? one_hot_sel_4927[0] : ____state_6_tuple_element_0[0];
      ____state_6_tuple_element_0[1] <= and_4997 ? one_hot_sel_4927[1] : ____state_6_tuple_element_0[1];
      ____state_6_tuple_element_0[2] <= and_4997 ? one_hot_sel_4927[2] : ____state_6_tuple_element_0[2];
      ____state_6_tuple_element_0[3] <= and_4997 ? one_hot_sel_4927[3] : ____state_6_tuple_element_0[3];
      ____state_6_tuple_element_0[4] <= and_4997 ? one_hot_sel_4927[4] : ____state_6_tuple_element_0[4];
      ____state_0 <= and_4991 ? one_hot_sel_4910 : ____state_0;
      ____state_6_tuple_element_2_tuple_element_0[0] <= and_5000 ? one_hot_sel_4953[0] : ____state_6_tuple_element_2_tuple_element_0[0];
      ____state_6_tuple_element_2_tuple_element_0[1] <= and_5000 ? one_hot_sel_4953[1] : ____state_6_tuple_element_2_tuple_element_0[1];
      ____state_6_tuple_element_2_tuple_element_0[2] <= and_5000 ? one_hot_sel_4953[2] : ____state_6_tuple_element_2_tuple_element_0[2];
      ____state_6_tuple_element_2_tuple_element_0[3] <= and_5000 ? one_hot_sel_4953[3] : ____state_6_tuple_element_2_tuple_element_0[3];
      ____state_6_tuple_element_2_tuple_element_0[4] <= and_5000 ? one_hot_sel_4953[4] : ____state_6_tuple_element_2_tuple_element_0[4];
      ____state_1 <= and_4973 ? _1 : ____state_1;
      ____state_4 <= and_4994 ? one_hot_sel_4917 : ____state_4;
      ____state_6_tuple_element_2_tuple_element_1[0][0] <= and_5000 ? one_hot_sel_4966[0][0] : ____state_6_tuple_element_2_tuple_element_1[0][0];
      ____state_6_tuple_element_2_tuple_element_1[0][1] <= and_5000 ? one_hot_sel_4966[0][1] : ____state_6_tuple_element_2_tuple_element_1[0][1];
      ____state_6_tuple_element_2_tuple_element_1[1][0] <= and_5000 ? one_hot_sel_4966[1][0] : ____state_6_tuple_element_2_tuple_element_1[1][0];
      ____state_6_tuple_element_2_tuple_element_1[1][1] <= and_5000 ? one_hot_sel_4966[1][1] : ____state_6_tuple_element_2_tuple_element_1[1][1];
      ____state_6_tuple_element_2_tuple_element_1[2][0] <= and_5000 ? one_hot_sel_4966[2][0] : ____state_6_tuple_element_2_tuple_element_1[2][0];
      ____state_6_tuple_element_2_tuple_element_1[2][1] <= and_5000 ? one_hot_sel_4966[2][1] : ____state_6_tuple_element_2_tuple_element_1[2][1];
      ____state_6_tuple_element_2_tuple_element_1[3][0] <= and_5000 ? one_hot_sel_4966[3][0] : ____state_6_tuple_element_2_tuple_element_1[3][0];
      ____state_6_tuple_element_2_tuple_element_1[3][1] <= and_5000 ? one_hot_sel_4966[3][1] : ____state_6_tuple_element_2_tuple_element_1[3][1];
      ____state_6_tuple_element_2_tuple_element_1[4][0] <= and_5000 ? one_hot_sel_4966[4][0] : ____state_6_tuple_element_2_tuple_element_1[4][0];
      ____state_6_tuple_element_2_tuple_element_1[4][1] <= and_5000 ? one_hot_sel_4966[4][1] : ____state_6_tuple_element_2_tuple_element_1[4][1];
      ____state_3_0 <= and_4986 ? and_4830 : ____state_3_0;
      ____state_2_0 <= and_4982 ? _42__1 : ____state_2_0;
      ____state_2_1 <= and_4982 ? new1_1 : ____state_2_1;
      ____state_3_1 <= and_4986 ? and_4831 : ____state_3_1;
      __phi_halo_cell__resp_has_been_sent_reg <= __phi_halo_cell__resp_has_been_sent_reg_load_en ? __phi_halo_cell__resp_not_stage_load : __phi_halo_cell__resp_has_been_sent_reg;
      __phi_halo_cell__admit_has_been_sent_reg <= __phi_halo_cell__admit_has_been_sent_reg_load_en ? __phi_halo_cell__admit_not_stage_load : __phi_halo_cell__admit_has_been_sent_reg;
      __phi_halo_cell__req_reg <= phi_halo_cell__req_load_en ? phi_halo_cell__req : __phi_halo_cell__req_reg;
      __phi_halo_cell__req_valid_reg <= phi_halo_cell__req_valid_load_en ? phi_halo_cell__req_vld : __phi_halo_cell__req_valid_reg;
      __phi_halo_cell__resp_reg <= phi_halo_cell__resp_load_en ? __phi_halo_cell__resp_buf : __phi_halo_cell__resp_reg;
      __phi_halo_cell__resp_valid_reg <= phi_halo_cell__resp_valid_load_en ? __phi_halo_cell__resp_valid_and_not_has_been_sent : __phi_halo_cell__resp_valid_reg;
      __phi_halo_cell__admit_reg <= phi_halo_cell__admit_load_en ? postponed_slot_tup0 : __phi_halo_cell__admit_reg;
      __phi_halo_cell__admit_valid_reg <= phi_halo_cell__admit_valid_load_en ? __phi_halo_cell__admit_valid_and_not_has_been_sent : __phi_halo_cell__admit_valid_reg;
    end
  end
  assign phi_halo_cell__admit = __phi_halo_cell__admit_reg;
  assign phi_halo_cell__admit_vld = __phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__req_rdy = phi_halo_cell__req_load_en;
  assign phi_halo_cell__resp = __phi_halo_cell__resp_reg;
  assign phi_halo_cell__resp_vld = __phi_halo_cell__resp_valid_reg;
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1[__i0] = concat_4515 == __i0 ? and_4514 : ____state_6_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_4515 == __i0 ? and_4519 : ____state_6_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_0_0
    assign admitted_slots_tuple_idx_2_tuple_idx_0[__i0] = concat_4515 == __i0 ? sel_4582 : ____state_6_tuple_element_2_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_1_0
    for (genvar __j0 = 0; __j0 < 2; __j0 = __j0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_1_0__1
      assign admitted_slots_tuple_idx_2_tuple_idx_1[__i0][__j0] = concat_4515 == __i0 ? sel_4612[__j0] : ____state_6_tuple_element_2_tuple_element_1[__i0][__j0];
    end
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_4782 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1[__i0] = concat_4782 == __i0 ? extended___state_0 : admitted_slots_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_0_0
    assign postponed_slots_tuple_idx_2_tuple_idx_0[__i0] = concat_4782 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_0 : admitted_slots_tuple_idx_2_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_1_0
    for (genvar __j0 = 0; __j0 < 2; __j0 = __j0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_1_0__1
      assign postponed_slots_tuple_idx_2_tuple_idx_1[__i0][__j0] = concat_4782 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_1[__j0] : admitted_slots_tuple_idx_2_tuple_idx_1[__i0][__j0];
    end
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
  wire and_5190;
  wire eq_5195;
  wire ne_5179;
  wire and_5196;
  wire or_5193;
  wire [2:0] add_5187;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_5182;
  wire popped;
  wire [1:0] sub_5208;
  wire [1:0] add_5210;
  wire [2:0] umod_5188;
  wire [2:0] umod_5183;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_5212;
  wire array_update_5219[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_5190 = pop_ready & push_valid;
  assign eq_5195 = head == tail;
  assign ne_5179 = head != tail;
  assign and_5196 = eq_5195 & and_5190;
  assign or_5193 = ne_5179 | push_valid;
  assign add_5187 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_5182 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_5193;
  assign sub_5208 = slots - 2'h1;
  assign add_5210 = slots + 2'h1;
  assign umod_5188 = add_5187 % long_buf_size_lit;
  assign umod_5183 = add_5182 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_5188[1:0];
  assign did_push_occur = (can_do_push | and_5190) & push_valid & ~and_5196 & ~is_full_bool;
  assign next_tail_if_pop = umod_5183[1:0];
  assign did_pop_occur = (ne_5179 | and_5190) & pop_ready & ~and_5196;
  assign sel_5212 = pushed ? (popped ? slots : add_5210) : (popped ? sub_5208 : slots);
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
      slots <= sel_5212;
      buf__1[0] <= did_push_occur ? array_update_5219[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_5219[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_5193;
  assign pop_data = eq_5195 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_5219_0
    assign array_update_5219[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_5247;
  wire eq_5252;
  wire ne_5236;
  wire and_5253;
  wire or_5250;
  wire [2:0] add_5244;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_5239;
  wire popped;
  wire [1:0] sub_5265;
  wire [1:0] add_5267;
  wire [2:0] umod_5245;
  wire [2:0] umod_5240;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_5269;
  wire [127:0] array_update_5276[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_5247 = pop_ready & push_valid;
  assign eq_5252 = head == tail;
  assign ne_5236 = head != tail;
  assign and_5253 = eq_5252 & and_5247;
  assign or_5250 = ne_5236 | push_valid;
  assign add_5244 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_5239 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_5250;
  assign sub_5265 = slots - 2'h1;
  assign add_5267 = slots + 2'h1;
  assign umod_5245 = add_5244 % long_buf_size_lit;
  assign umod_5240 = add_5239 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_5245[1:0];
  assign did_push_occur = (can_do_push | and_5247) & push_valid & ~and_5253 & ~is_full_bool;
  assign next_tail_if_pop = umod_5240[1:0];
  assign did_pop_occur = (ne_5236 | and_5247) & pop_ready & ~and_5253;
  assign sel_5269 = pushed ? (popped ? slots : add_5267) : (popped ? sub_5265 : slots);
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
      slots <= sel_5269;
      buf__1[0] <= did_push_occur ? array_update_5276[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_5276[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_5250;
  assign pop_data = eq_5252 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_5276_0
    assign array_update_5276[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_5304;
  wire eq_5309;
  wire ne_5293;
  wire and_5310;
  wire or_5307;
  wire [2:0] add_5301;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_5296;
  wire popped;
  wire [1:0] sub_5322;
  wire [1:0] add_5324;
  wire [2:0] umod_5302;
  wire [2:0] umod_5297;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_5326;
  wire [127:0] array_update_5333[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_5304 = pop_ready & push_valid;
  assign eq_5309 = head == tail;
  assign ne_5293 = head != tail;
  assign and_5310 = eq_5309 & and_5304;
  assign or_5307 = ne_5293 | push_valid;
  assign add_5301 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_5296 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_5307;
  assign sub_5322 = slots - 2'h1;
  assign add_5324 = slots + 2'h1;
  assign umod_5302 = add_5301 % long_buf_size_lit;
  assign umod_5297 = add_5296 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_5302[1:0];
  assign did_push_occur = (can_do_push | and_5304) & push_valid & ~and_5310 & ~is_full_bool;
  assign next_tail_if_pop = umod_5297[1:0];
  assign did_pop_occur = (ne_5293 | and_5304) & pop_ready & ~and_5310;
  assign sel_5326 = pushed ? (popped ? slots : add_5324) : (popped ? sub_5322 : slots);
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
      slots <= sel_5326;
      buf__1[0] <= did_push_occur ? array_update_5333[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_5333[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_5307;
  assign pop_data = eq_5309 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_5333_0
    assign array_update_5333[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __phi_halo_cell__Top_0_next(
  input wire clk,
  input wire reset,
  input wire [32:0] phi_halo_cell__ext_recv,
  input wire phi_halo_cell__ext_recv_vld,
  input wire phi_halo_cell__ext_send_rdy,
  output wire phi_halo_cell__ext_recv_rdy,
  output wire [32:0] phi_halo_cell__ext_send,
  output wire phi_halo_cell__ext_send_vld
);
  wire instantiation_output_5081;
  wire instantiation_output_5087;
  wire [127:0] instantiation_output_5098;
  wire instantiation_output_5099;
  wire [32:0] instantiation_output_5091;
  wire instantiation_output_5092;
  wire instantiation_output_5119;
  wire instantiation_output_5073;
  wire instantiation_output_5074;
  wire instantiation_output_5106;
  wire [127:0] instantiation_output_5111;
  wire instantiation_output_5112;
  wire instantiation_output_5341;
  wire instantiation_output_5342;
  wire instantiation_output_5343;
  wire instantiation_output_5348;
  wire [127:0] instantiation_output_5349;
  wire instantiation_output_5350;
  wire instantiation_output_5355;
  wire [127:0] instantiation_output_5356;
  wire instantiation_output_5357;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_5342),
    .phi_halo_cell__admit_vld(instantiation_output_5343),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_5348),
    .phi_halo_cell__admit_rdy(instantiation_output_5081),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_5087),
    .phi_halo_cell__req(instantiation_output_5098),
    .phi_halo_cell__req_vld(instantiation_output_5099),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__ext_send_rdy(phi_halo_cell__ext_send_rdy),
    .phi_halo_cell__resp(instantiation_output_5356),
    .phi_halo_cell__resp_vld(instantiation_output_5357),
    .phi_halo_cell__ext_send(instantiation_output_5091),
    .phi_halo_cell__ext_send_vld(instantiation_output_5092),
    .phi_halo_cell__resp_rdy(instantiation_output_5119),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst2 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst3 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_5341),
    .phi_halo_cell__req(instantiation_output_5349),
    .phi_halo_cell__req_vld(instantiation_output_5350),
    .phi_halo_cell__resp_rdy(instantiation_output_5355),
    .phi_halo_cell__admit(instantiation_output_5073),
    .phi_halo_cell__admit_vld(instantiation_output_5074),
    .phi_halo_cell__req_rdy(instantiation_output_5106),
    .phi_halo_cell__resp(instantiation_output_5111),
    .phi_halo_cell__resp_vld(instantiation_output_5112),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_5073),
    .push_valid(instantiation_output_5074),
    .pop_ready(instantiation_output_5081),
    .push_ready(instantiation_output_5341),
    .pop_data(instantiation_output_5342),
    .pop_valid(instantiation_output_5343),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_5098),
    .push_valid(instantiation_output_5099),
    .pop_ready(instantiation_output_5106),
    .push_ready(instantiation_output_5348),
    .pop_data(instantiation_output_5349),
    .pop_valid(instantiation_output_5350),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__resp_ (
    .reset(reset),
    .push_data(instantiation_output_5111),
    .push_valid(instantiation_output_5112),
    .pop_ready(instantiation_output_5119),
    .push_ready(instantiation_output_5355),
    .pop_data(instantiation_output_5356),
    .pop_valid(instantiation_output_5357),
    .clk(clk)
  );
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_5087;
  assign phi_halo_cell__ext_send = instantiation_output_5091;
  assign phi_halo_cell__ext_send_vld = instantiation_output_5092;
endmodule
