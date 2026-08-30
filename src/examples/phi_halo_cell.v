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
  wire [32:0] literal_13347 = {1'h0, 32'h0000_0000};
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
  wire and_13357;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_13356;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_13369;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_15156;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_15155;
  wire [31:0] sel_15154;
  wire [31:0] sel_15153;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_13414;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_15159;
  wire nand_13385;
  wire [127:0] one_hot_sel_13415;
  wire and_13429;
  wire [7:0] one_hot_sel_13422;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_13347;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_13357 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_13357;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_13356 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_13357;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_13356, and_13357};
  assign one_hot_13369 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_15156 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_15155 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_15154 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_15153 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_13356 == one_hot_13369[1] & and_13357 == one_hot_13369[0];
  assign concat_13414 = {nor_13356 & p0_stage_done, and_13357 & p0_stage_done};
  assign payload = {sel_15155, sel_15154, sel_15153, sel_15156};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_15159 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_13385 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_13415 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13414[0]}} | payload & {128{concat_13414[1]}};
  assign and_13429 = (nor_13356 | and_13357) & p0_stage_done;
  assign one_hot_sel_13422 = 8'h00 & {8{concat_13414[0]}} | words_seen & {8{concat_13414[1]}};
  assign __phi_halo_cell__req_buf = {{sel_15156[7:0], sel_15156[15:8], sel_15156[23:16], sel_15156[31:24]}, {sel_15155, sel_15154, sel_15153}};
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
      ____state_0 <= p0_stage_done ? nand_13385 : ____state_0;
      ____state_2 <= and_13429 ? one_hot_sel_13422 : ____state_2;
      ____state_1 <= and_13429 ? one_hot_sel_13415 : ____state_1;
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
  wire [127:0] literal_13485 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13497;
  wire not_13498;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_13507;
  wire [2:0] one_hot_13508;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_13547;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13550;
  wire [127:0] payload;
  wire [1:0] concat_13563;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_15163;
  wire or_15167;
  wire [7:0] one_hot_sel_13551;
  wire and_13571;
  wire [127:0] one_hot_sel_13558;
  wire [7:0] one_hot_sel_13564;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_13485;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_13497 = ~(last | ____state_0);
  assign not_13498 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13497};
  assign ____state_6__next_value_predicates = {not_13498, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_13507 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13508 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_13547 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13507[1] & nor_13497 == one_hot_13507[0];
  assign ____state_6__at_most_one_next_value = not_13498 == one_hot_13508[1] & last == one_hot_13508[0];
  assign concat_13550 = {and_13547, nor_13497 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13563 = {not_13498 & p0_stage_done, and_13547};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_15163 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15167 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13551 = frame_header_payload_words__1 & {8{concat_13550[0]}} | 8'h00 & {8{concat_13550[1]}};
  assign and_13571 = (last | nor_13497) & p0_stage_done;
  assign one_hot_sel_13558 = payload & {128{concat_13550[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13550[1]}};
  assign one_hot_sel_13564 = 8'h00 & {8{concat_13563[0]}} | beats_sent & {8{concat_13563[1]}};
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
      ____state_0 <= p0_stage_done ? not_13498 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13564 : ____state_6;
      ____state_1 <= and_13571 ? one_hot_sel_13551 : ____state_1;
      ____state_5 <= and_13571 ? one_hot_sel_13558 : ____state_5;
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
  wire [127:0] literal_13620 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13632;
  wire not_13633;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_13642;
  wire [2:0] one_hot_13643;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_13682;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13685;
  wire [127:0] payload;
  wire [1:0] concat_13698;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_15169;
  wire or_15173;
  wire [7:0] one_hot_sel_13686;
  wire and_13706;
  wire [127:0] one_hot_sel_13693;
  wire [7:0] one_hot_sel_13699;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_13620;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_13632 = ~(last | ____state_0);
  assign not_13633 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13632};
  assign ____state_6__next_value_predicates = {not_13633, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_13642 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13643 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_13682 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13642[1] & nor_13632 == one_hot_13642[0];
  assign ____state_6__at_most_one_next_value = not_13633 == one_hot_13643[1] & last == one_hot_13643[0];
  assign concat_13685 = {and_13682, nor_13632 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13698 = {not_13633 & p0_stage_done, and_13682};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_15169 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15173 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13686 = frame_header_payload_words__1 & {8{concat_13685[0]}} | 8'h00 & {8{concat_13685[1]}};
  assign and_13706 = (last | nor_13632) & p0_stage_done;
  assign one_hot_sel_13693 = payload & {128{concat_13685[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13685[1]}};
  assign one_hot_sel_13699 = 8'h00 & {8{concat_13698[0]}} | beats_sent & {8{concat_13698[1]}};
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
      ____state_0 <= p0_stage_done ? not_13633 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13699 : ____state_6;
      ____state_1 <= and_13706 ? one_hot_sel_13686 : ____state_1;
      ____state_5 <= and_13706 ? one_hot_sel_13693 : ____state_5;
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
  wire [127:0] literal_13755 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13767;
  wire not_13768;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_13777;
  wire [2:0] one_hot_13778;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_13817;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13820;
  wire [127:0] payload;
  wire [1:0] concat_13833;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_15175;
  wire or_15179;
  wire [7:0] one_hot_sel_13821;
  wire and_13841;
  wire [127:0] one_hot_sel_13828;
  wire [7:0] one_hot_sel_13834;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_13755;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_13767 = ~(last | ____state_0);
  assign not_13768 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13767};
  assign ____state_6__next_value_predicates = {not_13768, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_13777 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13778 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_13817 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13777[1] & nor_13767 == one_hot_13777[0];
  assign ____state_6__at_most_one_next_value = not_13768 == one_hot_13778[1] & last == one_hot_13778[0];
  assign concat_13820 = {and_13817, nor_13767 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13833 = {not_13768 & p0_stage_done, and_13817};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_15175 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15179 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13821 = frame_header_payload_words__1 & {8{concat_13820[0]}} | 8'h00 & {8{concat_13820[1]}};
  assign and_13841 = (last | nor_13767) & p0_stage_done;
  assign one_hot_sel_13828 = payload & {128{concat_13820[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13820[1]}};
  assign one_hot_sel_13834 = 8'h00 & {8{concat_13833[0]}} | beats_sent & {8{concat_13833[1]}};
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
      ____state_0 <= p0_stage_done ? not_13768 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13834 : ____state_6;
      ____state_1 <= and_13841 ? one_hot_sel_13821 : ____state_1;
      ____state_5 <= and_13841 ? one_hot_sel_13828 : ____state_5;
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
  wire [127:0] literal_13890 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13902;
  wire not_13903;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_13912;
  wire [2:0] one_hot_13913;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_13952;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13955;
  wire [127:0] payload;
  wire [1:0] concat_13968;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_15181;
  wire or_15185;
  wire [7:0] one_hot_sel_13956;
  wire and_13976;
  wire [127:0] one_hot_sel_13963;
  wire [7:0] one_hot_sel_13969;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_13890;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_13902 = ~(last | ____state_0);
  assign not_13903 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13902};
  assign ____state_6__next_value_predicates = {not_13903, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_13912 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13913 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_13952 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13912[1] & nor_13902 == one_hot_13912[0];
  assign ____state_6__at_most_one_next_value = not_13903 == one_hot_13913[1] & last == one_hot_13913[0];
  assign concat_13955 = {and_13952, nor_13902 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13968 = {not_13903 & p0_stage_done, and_13952};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_15181 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15185 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13956 = frame_header_payload_words__1 & {8{concat_13955[0]}} | 8'h00 & {8{concat_13955[1]}};
  assign and_13976 = (last | nor_13902) & p0_stage_done;
  assign one_hot_sel_13963 = payload & {128{concat_13955[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13955[1]}};
  assign one_hot_sel_13969 = 8'h00 & {8{concat_13968[0]}} | beats_sent & {8{concat_13968[1]}};
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
      ____state_0 <= p0_stage_done ? not_13903 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13969 : ____state_6;
      ____state_1 <= and_13976 ? one_hot_sel_13956 : ____state_1;
      ____state_5 <= and_13976 ? one_hot_sel_13963 : ____state_5;
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
  wire [127:0] literal_14084 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_14082;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_14093;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_14109;
  wire [31:0] concat_14110;
  wire ugt_14112;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_14114;
  wire postponed__4;
  wire ugt_14118;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_2560_0__2_case_0_case_1_case_0;
  wire or_reduce_14122;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_14133;
  wire postponed;
  wire [95:0] sel_14142;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_14145;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Value1_1;
  wire [31:0] _5__9_source;
  wire [31:0] _5__8_source;
  wire [31:0] _5__7_source;
  wire [31:0] _5__6_source;
  wire [7:0] sel_14154;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire _0__15;
  wire _1__5;
  wire _2__5;
  wire [31:0] _7__3;
  wire [31:0] Absent_1__1;
  wire [1:0] unexpand_for_next_value_2560_0__2_case_0_case_0_case_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire eq_14166;
  wire _8__3;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [1:0] unexpand_for_next_value_2560_0__2_case_0_case_0_case_2;
  wire [30:0] add_14170;
  wire eq_14172;
  wire nor_14173;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire and_14175;
  wire _21__2;
  wire eq_14177;
  wire [31:0] _1;
  wire or_14182;
  wire eq_14183;
  wire nand_14184;
  wire eq_14185;
  wire or_14187;
  wire [31:0] _2__1;
  wire eq_14190;
  wire eq_14191;
  wire _0__11;
  wire [1:0] concat_14197;
  wire [1:0] concat_14199;
  wire and_14201;
  wire _4__1;
  wire postponed_slot_tup0;
  wire eligible_0;
  wire invalid_input;
  wire eq_14214;
  wire _6__1;
  wire [1:0] priority_sel_14218;
  wire _3;
  wire _19;
  wire _47;
  wire found;
  wire compacted_4_tup0;
  wire nand_14234;
  wire and_14237;
  wire dispatchable;
  wire [1:0] priority_sel_14247;
  wire [1:0] concat_14249;
  wire [1:0] directive;
  wire [1:0] next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_14299;
  wire [1:0] candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire nor_14263;
  wire phase_changed;
  wire [31:0] Xls_clause_1_Value_1;
  wire and_14270;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire _12__2;
  wire and_14276;
  wire and_14278;
  wire final_slots_0_case_cmp;
  wire and_14286;
  wire and_14288;
  wire and_14291;
  wire and_14292;
  wire and_14293;
  wire eq_14294;
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
  wire and_14306;
  wire and_14308;
  wire Xls_clause_1_NewBestDirection_1_0_case_cmp;
  wire _15__1;
  wire candidate_occupied_0_case_cmp;
  wire and_14316;
  wire candidate_slots_0_case_cmp;
  wire and_14319;
  wire and_14320;
  wire or_14321;
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
  wire and_14337;
  wire and_14338;
  wire and_14339;
  wire and_14340;
  wire and_14341;
  wire and_14342;
  wire and_14343;
  wire and_14344;
  wire and_14345;
  wire and_14346;
  wire and_14347;
  wire and_14348;
  wire and_14349;
  wire and_14350;
  wire and_14351;
  wire and_14352;
  wire and_14353;
  wire and_14354;
  wire and_14355;
  wire and_14356;
  wire and_14357;
  wire and_14358;
  wire and_14359;
  wire and_14360;
  wire and_14361;
  wire and_14362;
  wire and_14363;
  wire [31:0] _12;
  wire _7__9;
  wire _9;
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
  wire Move_1__1;
  wire [2:0] one_hot_14421;
  wire [2:0] one_hot_14422;
  wire [2:0] one_hot_14423;
  wire [3:0] one_hot_14424;
  wire [2:0] one_hot_14425;
  wire [2:0] one_hot_14426;
  wire [2:0] one_hot_14427;
  wire [11:0] one_hot_14428;
  wire [2:0] one_hot_14429;
  wire [2:0] one_hot_14430;
  wire [5:0] one_hot_14431;
  wire [8:0] one_hot_14432;
  wire [14:0] _2__15;
  wire [30:0] add_14375;
  wire [63:0] umul_14376;
  wire [95:0] array_index_14400;
  wire [95:0] array_index_14402;
  wire [95:0] array_index_14404;
  wire [7:0] array_index_14408;
  wire [7:0] array_index_14410;
  wire [7:0] array_index_14412;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_14418;
  wire ne_14455;
  wire or_reduce_14457;
  wire ugt_14459;
  wire phi_halo_cell__req_valid_inv;
  wire and_14712;
  wire and_14713;
  wire and_14719;
  wire and_14727;
  wire _22__2;
  wire admission_pending;
  wire [15:0] add_14473;
  wire and_14812;
  wire and_14813;
  wire and_14814;
  wire and_14815;
  wire [31:0] concat_14541;
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
  wire [95:0] concat_14436;
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
  wire [1:0] concat_14715;
  wire [31:0] _42;
  wire [1:0] concat_14722;
  wire [1:0] concat_14729;
  wire [2:0] concat_14737;
  wire [1:0] concat_14744;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire [31:0] _22__1;
  wire [16:0] NextRandom_1__11;
  wire [9:0] NextRandom_1__10;
  wire [4:0] NextRandom_1__9;
  wire [1:0] concat_14754;
  wire [1:0] concat_14764;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_14552;
  wire [31:0] sign_ext_14553;
  wire [10:0] concat_14793;
  wire [1:0] concat_14800;
  wire [1:0] unexpand_for_next_value_2560_6__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_14807;
  wire [1:0] unexpand_for_next_value_2560_10__2_case_0_case_1_case_2_case_1_case_0;
  wire [4:0] concat_14817;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_14830;
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
  wire [31:0] tuple_14522;
  wire phi_halo_cell__req_load_en;
  wire or_15187;
  wire or_15189;
  wire or_15191;
  wire or_15193;
  wire or_15195;
  wire or_15197;
  wire or_15199;
  wire or_15201;
  wire or_15203;
  wire or_15205;
  wire or_15207;
  wire or_15209;
  wire [31:0] _8__1;
  wire and_14853;
  wire [31:0] one_hot_sel_14716;
  wire and_14856;
  wire [31:0] one_hot_sel_14723;
  wire and_14859;
  wire [31:0] one_hot_sel_14730;
  wire and_14862;
  wire [31:0] one_hot_sel_14738;
  wire and_14865;
  wire [31:0] one_hot_sel_14745;
  wire and_14868;
  wire [31:0] NextRandom_1;
  wire and_14870;
  wire [7:0] one_hot_sel_14755;
  wire and_14873;
  wire and_14605;
  wire and_14875;
  wire one_hot_sel_14765;
  wire and_14878;
  wire or_14603;
  wire [31:0] _31;
  wire and_14881;
  wire [31:0] _37;
  wire [31:0] and_14623;
  wire and_14885;
  wire [31:0] and_14624;
  wire [1:0] one_hot_sel_14794;
  wire and_14890;
  wire [1:0] one_hot_sel_14801;
  wire and_14893;
  wire [1:0] one_hot_sel_14808;
  wire and_14896;
  wire one_hot_sel_14818[0:4];
  wire and_14899;
  wire [95:0] one_hot_sel_14831[0:4];
  wire and_14902;
  wire [7:0] one_hot_sel_14844[0:4];
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
  assign nor_14082 = ~(____state_17 | ____state_15 | ~____state_16);
  assign received = nor_14082 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_14084;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_14093 = frame_header__1_payload_words == 8'h03;
  assign tag_ok = frame_header_op == 8'h03 & eq_14093 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02 | frame_header_op == MAILBOX_CAPACITY & eq_14093;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_14 + {7'h00, accepted};
  assign and_14109 = ~accepted & ____state_13_tuple_element_0[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign concat_14110 = {24'h00_0000, ____state_14};
  assign ugt_14112 = admitted_occupied > 8'h04;
  assign or_reduce_14114 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_14118 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_14112 | postponed__4);
  assign unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 = 2'h0;
  assign or_reduce_14122 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_14114 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_14118 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_14122 | postponed__1);
  assign eq_14133 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_14142 = accepted ? phi_halo_cell__req_select[95:0] : ____state_13_tuple_element_1_tuple_element_1[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_2560_0__2_case_0_case_1_case_0}))} & {8{eq_14133 | postponed}};
  assign bit_slice_14145 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_14145 > 3'h4 ? 3'h4 : bit_slice_14145];
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _5__9_source = 32'h0000_0001;
  assign _5__8_source = 32'h0000_0002;
  assign _5__7_source = 32'h0000_0004;
  assign _5__6_source = 32'h0000_0008;
  assign sel_14154 = accepted ? frame_header_op : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__15 = Xls_clause_1_Value1_1 == _5__9_source;
  assign _1__5 = Xls_clause_1_Value1_1 == _5__8_source;
  assign _2__5 = Xls_clause_1_Value1_1 == _5__7_source;
  assign _7__3 = ____state_7 & Xls_clause_1_Value1_1;
  assign Absent_1__1 = 32'h0000_0000;
  assign unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 = 2'h1;
  assign eq_14166 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _8__3 = _7__3 == Absent_1__1;
  assign Xls_clause_1_NewSeen_1 = ____state_7 | Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2560_0__2_case_0_case_0_case_2 = 2'h2;
  assign add_14170 = ____state_2[30:0] + ____state_3[31:1];
  assign eq_14172 = ____state_0 == unexpand_for_next_value_2560_0__2_case_0_case_0_case_1;
  assign nor_14173 = ~(____state_0[0] | ____state_0[1]);
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_14145 > 3'h4 ? 3'h4 : bit_slice_14145];
  assign and_14175 = eq_14166 & (_0__15 | _1__5 | _2__5 | Xls_clause_1_Value1_1 == _5__6_source) & _8__3;
  assign _21__2 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign eq_14177 = ____state_0 == unexpand_for_next_value_2560_0__2_case_0_case_0_case_2;
  assign _1 = {add_14170, ____state_3[0]};
  assign or_14182 = eq_14172 | nor_14173;
  assign eq_14183 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign nand_14184 = ~(and_14175 & _21__2);
  assign eq_14185 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign or_14187 = ____state_0[0] | ____state_0[1];
  assign _2__1 = _1 + _5__9_source;
  assign eq_14190 = add_14170 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_14191 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign _0__11 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign concat_14197 = {eq_14177, or_14182};
  assign concat_14199 = {eq_14172, nor_14173};
  assign and_14201 = eq_14185 & ~(eq_14177 | eq_14172) & or_14187;
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__1;
  assign postponed_slot_tup0 = 1'h1;
  assign eligible_0 = ~(eq_14133 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign eq_14214 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY;
  assign _6__1 = ____state_10 == 2'h3;
  assign priority_sel_14218 = priority_sel_2b_2way(concat_14199, unexpand_for_next_value_2560_0__2_case_0_case_1_case_0, nand_14184 ? unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2560_0__2_case_0_case_0_case_2, ____state_0);
  assign _3 = eq_14190 & eq_14191;
  assign _19 = ____state_6 == 2'h3;
  assign _47 = ____state_3 == _5__9_source;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign compacted_4_tup0 = 1'h0;
  assign nand_14234 = ~(eq_14166 & _0__11 & _6__1);
  assign and_14237 = _3 & _19 & _47;
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_14247 = priority_sel_2b_5way({eq_14214, eq_14183, and_14201, {2{eq_14185}} & {eq_14177 | eq_14172, nor_14173}}, (_4__1 ? unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2560_0__2_case_0_case_0_case_2) & {2{~(eq_14190 & eq_14191)}}, _3 ? unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2560_0__2_case_0_case_0_case_2, unexpand_for_next_value_2560_0__2_case_0_case_0_case_2, {priority_sel_1b_2way(concat_14197, ~eq_14166, ~(eq_14166 & _0__11), postponed_slot_tup0), eq_14166 & or_14182}, {priority_sel_1b_2way(concat_14199, ~eq_14166, ~and_14175, postponed_slot_tup0), ~(~eq_14166 | ____state_0[0] | ____state_0[1])}, unexpand_for_next_value_2560_0__2_case_0_case_0_case_2);
  assign concat_14249 = {priority_sel_1b_5way({eq_14214, eq_14183 & ~eq_14177 & ~or_14182, {2{eq_14183}} & concat_14197, eq_14185}, ____state_0[1], compacted_4_tup0, nand_14234, ____state_0[1], priority_sel_14218[1], ____state_0[1]), priority_sel_1b_5way({eq_14214, eq_14183 | and_14201, {3{eq_14185}} & {eq_14177, eq_14172, nor_14173}}, and_14237, postponed_slot_tup0, compacted_4_tup0, ____state_0[0], priority_sel_14218[0], ____state_0[0])};
  assign directive = priority_sel_14247 & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? concat_14249 : ____state_0;
  assign repeat_phase = dispatchable & eq_14185 & nor_14173 & _3 & ~(~_19 | _47);
  assign invalid_repeat = repeat_phase & (directive != unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 | next_phase_squeezed != ____state_0);
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_14299 = admitted_occupied + 8'hff;
  assign candidate_phase_squeezed = effective ? concat_14249 : ____state_0;
  assign failed = invalid_input | invalid_repeat | effective & directive == unexpand_for_next_value_2560_0__2_case_0_case_0_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_14299 : admitted_occupied;
  assign nor_14263 = ~(____state_17 | ____state_15);
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign Xls_clause_1_Value_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign and_14270 = nor_14263 & effective;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_16 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_16 | ____state_14 > 8'h04);
  assign _12__2 = Xls_clause_1_Value_1 > ____state_8;
  assign and_14276 = and_14270 & eq_14214;
  assign and_14278 = and_14270 & eq_14183;
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_14286 = and_14270 & eq_14185;
  assign and_14288 = and_14276 & eq_14172;
  assign and_14291 = and_14278 & eq_14177;
  assign and_14292 = nor_14263 & final_slots_0_case_cmp;
  assign and_14293 = nor_14263 & phase_boundary;
  assign eq_14294 = priority_sel_14247 == unexpand_for_next_value_2560_0__2_case_0_case_0_case_1;
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
  assign and_14306 = and_14286 & nor_14173;
  assign and_14308 = and_14288 & and_14175;
  assign Xls_clause_1_NewBestDirection_1_0_case_cmp = ~_12__2;
  assign _15__1 = Xls_clause_1_Value_1 == ____state_8;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_14316 = and_14291 & eq_14166 & _0__11;
  assign candidate_slots_0_case_cmp = ~effective;
  assign and_14319 = and_14292 & effective;
  assign and_14320 = and_14293 & effective;
  assign or_14321 = directive[0] | transition_slots_default_case_cmp;
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
  assign and_14337 = and_14306 & _3 & _19;
  assign and_14338 = and_14291 & eq_14166 & _0__11 & _6__1;
  assign and_14339 = and_14306 & and_14237;
  assign and_14340 = and_14288 & ~(~(and_14175 & _12__2));
  assign and_14341 = and_14308 & Xls_clause_1_NewBestDirection_1_0_case_cmp & _15__1;
  assign and_14342 = __phi_halo_cell__east_vld_buf & ~eq_14172 & or_14187;
  assign and_14343 = nor_14263 & candidate_occupied_0_case_cmp;
  assign and_14344 = nor_14263 & candidate_occupied_1_case_cmp;
  assign and_14345 = and_14286 & eq_14172;
  assign and_14346 = and_14286 & eq_14177;
  assign and_14347 = and_14278 & nor_14173;
  assign and_14348 = and_14278 & eq_14172;
  assign and_14349 = and_14276 & nor_14173;
  assign and_14350 = and_14306 & ~(_3 & _19 & _47);
  assign and_14351 = and_14291 & nand_14234;
  assign and_14352 = and_14288 & ~nand_14184;
  assign and_14353 = and_14288 & nand_14184;
  assign and_14354 = and_14306 & _3 & ~_19;
  assign and_14355 = and_14316 & ~_6__1;
  assign and_14356 = and_14292 & candidate_slots_0_case_cmp;
  assign and_14357 = and_14319 & transition_slots_predicate_piece_0;
  assign and_14358 = and_14319 & eq_14294;
  assign and_14359 = and_14319 & transition_slots_default_case_cmp;
  assign and_14360 = and_14293 & candidate_slots_0_case_cmp;
  assign and_14361 = and_14320 & transition_slots_predicate_piece_0;
  assign and_14362 = and_14320 & eq_14294 & or_14321;
  assign and_14363 = and_14320 & ~eq_14294 & or_14321;
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign _7__9 = ____state_11 == _5__9_source;
  assign _9 = ____state_9 != Absent_1__1;
  assign NextRandom_1__5 = _1__1[18] ^ _1__1[13];
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_14337, and_14338};
  assign ____state_7__next_value_predicates = {and_14339, and_14308};
  assign ____state_8__next_value_predicates = {and_14339, and_14340};
  assign ____state_9__next_value_predicates = {and_14339, and_14340, and_14341};
  assign ____state_11__next_value_predicates = {and_14342, and_14316};
  assign ____state_14__next_value_predicates = {and_14343, and_14344};
  assign ____state_16__next_value_predicates = {nor_14263, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_14345, and_14346, and_14347, and_14348, and_14349, and_14339, and_14350, and_14338, and_14351, and_14352, and_14353};
  assign ____state_6__next_value_predicates = {and_14354, and_14337};
  assign ____state_10__next_value_predicates = {and_14355, and_14338};
  assign ____state_13_tuple_element_0__next_value_predicates = {and_14293, and_14356, and_14357, and_14358, and_14359};
  assign ____state_13_tuple_element_1_tuple_element_1__next_value_predicates = {and_14356, and_14357, and_14358, and_14359, and_14360, and_14361, and_14362, and_14363};
  assign _8 = ____state_5_0 + Xls_clause_1_Value_1;
  assign _35 = ____state_4_0 + _12;
  assign Move_1__1 = _7__9 & _9 & NextRandom_1__5;
  assign one_hot_14421 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_14422 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_14423 = {____state_8__next_value_predicates[1:0] == 2'h0, ____state_8__next_value_predicates[1] && !____state_8__next_value_predicates[0], ____state_8__next_value_predicates[0]};
  assign one_hot_14424 = {____state_9__next_value_predicates[2:0] == 3'h0, ____state_9__next_value_predicates[2] && ____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_14425 = {____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_14426 = {____state_14__next_value_predicates[1:0] == 2'h0, ____state_14__next_value_predicates[1] && !____state_14__next_value_predicates[0], ____state_14__next_value_predicates[0]};
  assign one_hot_14427 = {____state_16__next_value_predicates[1:0] == 2'h0, ____state_16__next_value_predicates[1] && !____state_16__next_value_predicates[0], ____state_16__next_value_predicates[0]};
  assign one_hot_14428 = {____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_14429 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_14430 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_14431 = {____state_13_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_0__next_value_predicates[4] && ____state_13_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_0__next_value_predicates[3] && ____state_13_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_0__next_value_predicates[2] && ____state_13_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_0__next_value_predicates[1] && !____state_13_tuple_element_0__next_value_predicates[0], ____state_13_tuple_element_0__next_value_predicates[0]};
  assign one_hot_14432 = {____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign _2__15 = {_1__1[1:0], ____state_12[12:0]} ^ _1__1[18:4];
  assign add_14375 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_14376 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_14400 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_14402 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_14404 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_14408 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_14410 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_14412 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_14418 = ____state_4_1[30:0] + _8[31:1];
  assign ne_14455 = bit_slice_14145 != 3'h0;
  assign or_reduce_14457 = |selected[7:1];
  assign ugt_14459 = bit_slice_14145 > 3'h2;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_14712 = and_14337 & p0_all_active_outputs_ready;
  assign and_14713 = and_14338 & p0_all_active_outputs_ready;
  assign and_14719 = and_14339 & p0_all_active_outputs_ready;
  assign and_14727 = and_14340 & p0_all_active_outputs_ready;
  assign _22__2 = ____state_11[0] ^ Move_1__1;
  assign admission_pending = ~(~____state_16 | received);
  assign add_14473 = ____state_11[15:0] + {unexpand_for_next_value_2560_0__2_case_0_case_1_case_0, ____state_4_0[31:18]};
  assign and_14812 = and_14356 & p0_all_active_outputs_ready;
  assign and_14813 = and_14357 & p0_all_active_outputs_ready;
  assign and_14814 = and_14358 & p0_all_active_outputs_ready;
  assign and_14815 = and_14359 & p0_all_active_outputs_ready;
  assign concat_14541 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_14455 ? postponed : or_reduce_14122 & postponed__1;
  assign compacted_1_tup0 = or_reduce_14457 ? postponed__1 : ugt_14118 & postponed__2;
  assign compacted_2_tup0 = ugt_14459 ? postponed__2 : or_reduce_14114 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_14112 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_14455 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_14400 & {96{or_reduce_14122}};
  assign compacted_1_tup1_tup1 = or_reduce_14457 ? array_index_14400 : array_index_14402 & {96{ugt_14118}};
  assign compacted_2_tup1_tup1 = ugt_14459 ? array_index_14402 : array_index_14404 & {96{or_reduce_14114}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_14404 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_14112}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_14455 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_14408 & {8{or_reduce_14122}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_14457 ? array_index_14408 : array_index_14410 & {8{ugt_14118}};
  assign compacted_2_tup1_tup0_tup3 = ugt_14459 ? array_index_14410 : array_index_14412 & {8{or_reduce_14114}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_14412 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_14112}};
  assign concat_14436 = {____state_4_0, ____state_4_1, add_14170, ____state_3[0]};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_14082 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_14337 == one_hot_14421[1] & and_14338 == one_hot_14421[0];
  assign ____state_7__at_most_one_next_value = and_14339 == one_hot_14422[1] & and_14308 == one_hot_14422[0];
  assign ____state_8__at_most_one_next_value = and_14339 == one_hot_14423[1] & and_14340 == one_hot_14423[0];
  assign ____state_9__at_most_one_next_value = and_14339 == one_hot_14424[2] & and_14340 == one_hot_14424[1] & and_14341 == one_hot_14424[0];
  assign ____state_11__at_most_one_next_value = and_14342 == one_hot_14425[1] & and_14316 == one_hot_14425[0];
  assign ____state_14__at_most_one_next_value = and_14343 == one_hot_14426[1] & and_14344 == one_hot_14426[0];
  assign ____state_16__at_most_one_next_value = nor_14263 == one_hot_14427[1] & __phi_halo_cell__east_vld_buf == one_hot_14427[0];
  assign ____state_0__at_most_one_next_value = and_14345 == one_hot_14428[10] & and_14346 == one_hot_14428[9] & and_14347 == one_hot_14428[8] & and_14348 == one_hot_14428[7] & and_14349 == one_hot_14428[6] & and_14339 == one_hot_14428[5] & and_14350 == one_hot_14428[4] & and_14338 == one_hot_14428[3] & and_14351 == one_hot_14428[2] & and_14352 == one_hot_14428[1] & and_14353 == one_hot_14428[0];
  assign ____state_6__at_most_one_next_value = and_14354 == one_hot_14429[1] & and_14337 == one_hot_14429[0];
  assign ____state_10__at_most_one_next_value = and_14355 == one_hot_14430[1] & and_14338 == one_hot_14430[0];
  assign ____state_13_tuple_element_0__at_most_one_next_value = and_14293 == one_hot_14431[4] & and_14356 == one_hot_14431[3] & and_14357 == one_hot_14431[2] & and_14358 == one_hot_14431[1] & and_14359 == one_hot_14431[0];
  assign ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value = and_14356 == one_hot_14432[7] & and_14357 == one_hot_14432[6] & and_14358 == one_hot_14432[5] & and_14359 == one_hot_14432[4] & and_14360 == one_hot_14432[3] & and_14361 == one_hot_14432[2] & and_14362 == one_hot_14432[1] & and_14363 == one_hot_14432[0];
  assign concat_14715 = {and_14712, and_14713};
  assign _42 = ____state_3 + _5__9_source;
  assign concat_14722 = {and_14719, and_14308 & p0_all_active_outputs_ready};
  assign concat_14729 = {and_14719, and_14727};
  assign concat_14737 = {and_14719, and_14727, and_14341 & p0_all_active_outputs_ready};
  assign concat_14744 = {and_14342 & p0_all_active_outputs_ready, and_14316 & p0_all_active_outputs_ready};
  assign Xls_clause_1_NextAnyon_1 = ____state_11 ^ Xls_clause_1_Value1_1;
  assign _22__1 = {____state_11[31:1], _22__2};
  assign NextRandom_1__11 = _1__1[18:2] ^ {_1__1[13:2], _2__15[14:10]};
  assign NextRandom_1__10 = _2__15[14:5] ^ _2__15[9:0];
  assign NextRandom_1__9 = _2__15[4:0];
  assign concat_14754 = {and_14343 & p0_all_active_outputs_ready, and_14344 & p0_all_active_outputs_ready};
  assign concat_14764 = {nor_14263 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _27 = {add_14473, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_14418[30:2]};
  assign add_14552 = {compacted_4_tup0, add_14375[30:1]} + {3'h0, umul_14376[63:36]};
  assign sign_ext_14553 = {32{~_19}};
  assign concat_14793 = {and_14345 & p0_all_active_outputs_ready, and_14346 & p0_all_active_outputs_ready, and_14347 & p0_all_active_outputs_ready, and_14348 & p0_all_active_outputs_ready, and_14349 & p0_all_active_outputs_ready, and_14719, and_14350 & p0_all_active_outputs_ready, and_14713, and_14351 & p0_all_active_outputs_ready, and_14352 & p0_all_active_outputs_ready, and_14353 & p0_all_active_outputs_ready};
  assign concat_14800 = {and_14354 & p0_all_active_outputs_ready, and_14712};
  assign unexpand_for_next_value_2560_6__2_case_0_case_0_case_0_case_1_case_0 = ____state_6 + unexpand_for_next_value_2560_0__2_case_0_case_0_case_1;
  assign concat_14807 = {and_14355 & p0_all_active_outputs_ready, and_14713};
  assign unexpand_for_next_value_2560_10__2_case_0_case_1_case_2_case_1_case_0 = ____state_10 + unexpand_for_next_value_2560_0__2_case_0_case_0_case_1;
  assign concat_14817 = {and_14293 & p0_all_active_outputs_ready, and_14812, and_14813, and_14814, and_14815};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_14830 = {and_14812, and_14813, and_14814, and_14815, and_14360 & p0_all_active_outputs_ready, and_14361 & p0_all_active_outputs_ready, and_14362 & p0_all_active_outputs_ready, and_14363 & p0_all_active_outputs_ready};
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
  assign tuple_14522 = {{7'h01, or_14182}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, nor_14173 ? unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2560_0__2_case_0_case_0_case_2, or_14182}};
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_15187 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_15189 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_15191 = ~p0_all_active_outputs_ready | ____state_8__at_most_one_next_value | reset;
  assign or_15193 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_15195 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_15197 = ~p0_all_active_outputs_ready | ____state_14__at_most_one_next_value | reset;
  assign or_15199 = ~p0_all_active_outputs_ready | ____state_16__at_most_one_next_value | reset;
  assign or_15201 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_15203 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_15205 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_15207 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_0__at_most_one_next_value | reset;
  assign or_15209 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign _8__1 = ____state_2 + _5__9_source;
  assign and_14853 = and_14338 & p0_all_active_outputs_ready;
  assign one_hot_sel_14716 = Absent_1__1 & {32{concat_14715[0]}} | _42 & {32{concat_14715[1]}};
  assign and_14856 = (and_14337 | and_14338) & p0_all_active_outputs_ready;
  assign one_hot_sel_14723 = Xls_clause_1_NewSeen_1 & {32{concat_14722[0]}} | Absent_1__1 & {32{concat_14722[1]}};
  assign and_14859 = (and_14339 | and_14308) & p0_all_active_outputs_ready;
  assign one_hot_sel_14730 = Xls_clause_1_Value_1 & {32{concat_14729[0]}} | Absent_1__1 & {32{concat_14729[1]}};
  assign and_14862 = (and_14339 | and_14340) & p0_all_active_outputs_ready;
  assign one_hot_sel_14738 = Absent_1__1 & {32{concat_14737[0]}} | Xls_clause_1_Value1_1 & {32{concat_14737[1]}} | Absent_1__1 & {32{concat_14737[2]}};
  assign and_14865 = (and_14339 | and_14340 | and_14341) & p0_all_active_outputs_ready;
  assign one_hot_sel_14745 = Xls_clause_1_NextAnyon_1 & {32{concat_14744[0]}} | _22__1 & {32{concat_14744[1]}};
  assign and_14868 = (and_14342 | and_14316) & p0_all_active_outputs_ready;
  assign NextRandom_1 = {NextRandom_1__11, NextRandom_1__10, NextRandom_1__9};
  assign and_14870 = and_14342 & p0_all_active_outputs_ready;
  assign one_hot_sel_14755 = add_14299 & {8{concat_14754[0]}} | admitted_occupied & {8{concat_14754[1]}};
  assign and_14873 = (and_14343 | and_14344) & p0_all_active_outputs_ready;
  assign and_14605 = ~____state_15 & effective & phase_boundary & ~failed;
  assign and_14875 = ~____state_17 & p0_all_active_outputs_ready;
  assign one_hot_sel_14765 = (____state_16 | ____state_14 < MAILBOX_CAPACITY) & concat_14764[0] | (admission_pending | reserve__1) & concat_14764[1];
  assign and_14878 = (nor_14263 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_14603 = ____state_17 | (____state_15 ? ____state_17 : failed);
  assign _31 = _27 + _30;
  assign and_14881 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14185 & nor_14173 & eq_14190 & eq_14191 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_14552};
  assign and_14623 = _8 & sign_ext_14553;
  assign and_14885 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14185 & nor_14173 & _3 & p0_all_active_outputs_ready;
  assign and_14624 = _12 & sign_ext_14553;
  assign one_hot_sel_14794 = unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 & {2{concat_14793[0]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_2 & {2{concat_14793[1]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_2 & {2{concat_14793[2]}} | unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14793[3]}} | unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14793[4]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 & {2{concat_14793[5]}} | unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14793[6]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 & {2{concat_14793[7]}} | unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14793[8]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_2 & {2{concat_14793[9]}} | unexpand_for_next_value_2560_0__2_case_0_case_0_case_1 & {2{concat_14793[10]}};
  assign and_14890 = (and_14345 | and_14346 | and_14347 | and_14348 | and_14349 | and_14339 | and_14350 | and_14338 | and_14351 | and_14352 | and_14353) & p0_all_active_outputs_ready;
  assign one_hot_sel_14801 = unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14800[0]}} | unexpand_for_next_value_2560_6__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_14800[1]}};
  assign and_14893 = (and_14354 | and_14337) & p0_all_active_outputs_ready;
  assign one_hot_sel_14808 = unexpand_for_next_value_2560_0__2_case_0_case_1_case_0 & {2{concat_14807[0]}} | unexpand_for_next_value_2560_10__2_case_0_case_1_case_2_case_1_case_0 & {2{concat_14807[1]}};
  assign and_14896 = (and_14355 | and_14338) & p0_all_active_outputs_ready;
  assign one_hot_sel_14818[0] = admitted_slots_tuple_idx_0[0] & concat_14817[0] | postponed_slots_tuple_idx_0[0] & concat_14817[1] | compacted_slots_tuple_idx_0[0] & concat_14817[2] | admitted_slots_tuple_idx_0[0] & concat_14817[3] | unblocked_slots_tuple_idx_0[0] & concat_14817[4];
  assign one_hot_sel_14818[1] = admitted_slots_tuple_idx_0[1] & concat_14817[0] | postponed_slots_tuple_idx_0[1] & concat_14817[1] | compacted_slots_tuple_idx_0[1] & concat_14817[2] | admitted_slots_tuple_idx_0[1] & concat_14817[3] | unblocked_slots_tuple_idx_0[1] & concat_14817[4];
  assign one_hot_sel_14818[2] = admitted_slots_tuple_idx_0[2] & concat_14817[0] | postponed_slots_tuple_idx_0[2] & concat_14817[1] | compacted_slots_tuple_idx_0[2] & concat_14817[2] | admitted_slots_tuple_idx_0[2] & concat_14817[3] | unblocked_slots_tuple_idx_0[2] & concat_14817[4];
  assign one_hot_sel_14818[3] = admitted_slots_tuple_idx_0[3] & concat_14817[0] | postponed_slots_tuple_idx_0[3] & concat_14817[1] | compacted_slots_tuple_idx_0[3] & concat_14817[2] | admitted_slots_tuple_idx_0[3] & concat_14817[3] | unblocked_slots_tuple_idx_0[3] & concat_14817[4];
  assign one_hot_sel_14818[4] = admitted_slots_tuple_idx_0[4] & concat_14817[0] | postponed_slots_tuple_idx_0[4] & concat_14817[1] | compacted_slots_tuple_idx_0[4] & concat_14817[2] | admitted_slots_tuple_idx_0[4] & concat_14817[3] | unblocked_slots_tuple_idx_0[4] & concat_14817[4];
  assign and_14899 = (and_14293 | and_14356 | and_14357 | and_14358 | and_14359) & p0_all_active_outputs_ready;
  assign one_hot_sel_14831[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14830[7]}};
  assign one_hot_sel_14831[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14830[7]}};
  assign one_hot_sel_14831[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14830[7]}};
  assign one_hot_sel_14831[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14830[7]}};
  assign one_hot_sel_14831[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14830[7]}};
  assign and_14902 = (and_14356 | and_14357 | and_14358 | and_14359 | and_14360 | and_14361 | and_14362 | and_14363) & p0_all_active_outputs_ready;
  assign one_hot_sel_14844[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14830[7]}};
  assign one_hot_sel_14844[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14830[7]}};
  assign one_hot_sel_14844[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14830[7]}};
  assign one_hot_sel_14844[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14830[7]}};
  assign one_hot_sel_14844[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14830[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {tuple_14522, priority_sel_96b_2way(concat_14199, concat_14436, {____state_4_0, _5__6_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__9_source & Move_1__1)), ____state_2})};
  assign effects_east = {tuple_14522, priority_sel_96b_2way(concat_14199, concat_14436, {____state_4_0, _5__7_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__8_source & Move_1__1)), ____state_2})};
  assign effects_west = {tuple_14522, priority_sel_96b_2way(concat_14199, concat_14436, {____state_4_0, _5__8_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__7_source & Move_1__1)), ____state_2})};
  assign effects_south = {tuple_14522, priority_sel_96b_2way(concat_14199, concat_14436, {____state_4_0, _5__9_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__6_source & Move_1__1)), ____state_2})};
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
      ____state_16 <= and_14878 ? one_hot_sel_14765 : ____state_16;
      ____state_17 <= p0_all_active_outputs_ready ? or_14603 : ____state_17;
      ____state_15 <= and_14875 ? and_14605 : ____state_15;
      ____state_13_tuple_element_0[0] <= and_14899 ? one_hot_sel_14818[0] : ____state_13_tuple_element_0[0];
      ____state_13_tuple_element_0[1] <= and_14899 ? one_hot_sel_14818[1] : ____state_13_tuple_element_0[1];
      ____state_13_tuple_element_0[2] <= and_14899 ? one_hot_sel_14818[2] : ____state_13_tuple_element_0[2];
      ____state_13_tuple_element_0[3] <= and_14899 ? one_hot_sel_14818[3] : ____state_13_tuple_element_0[3];
      ____state_13_tuple_element_0[4] <= and_14899 ? one_hot_sel_14818[4] : ____state_13_tuple_element_0[4];
      ____state_14 <= and_14873 ? one_hot_sel_14755 : ____state_14;
      ____state_13_tuple_element_1_tuple_element_1[0] <= and_14902 ? one_hot_sel_14831[0] : ____state_13_tuple_element_1_tuple_element_1[0];
      ____state_13_tuple_element_1_tuple_element_1[1] <= and_14902 ? one_hot_sel_14831[1] : ____state_13_tuple_element_1_tuple_element_1[1];
      ____state_13_tuple_element_1_tuple_element_1[2] <= and_14902 ? one_hot_sel_14831[2] : ____state_13_tuple_element_1_tuple_element_1[2];
      ____state_13_tuple_element_1_tuple_element_1[3] <= and_14902 ? one_hot_sel_14831[3] : ____state_13_tuple_element_1_tuple_element_1[3];
      ____state_13_tuple_element_1_tuple_element_1[4] <= and_14902 ? one_hot_sel_14831[4] : ____state_13_tuple_element_1_tuple_element_1[4];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_14902 ? one_hot_sel_14844[0] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_14902 ? one_hot_sel_14844[1] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_14902 ? one_hot_sel_14844[2] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_14902 ? one_hot_sel_14844[3] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_14902 ? one_hot_sel_14844[4] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_7 <= and_14859 ? one_hot_sel_14723 : ____state_7;
      ____state_2 <= and_14853 ? _8__1 : ____state_2;
      ____state_3 <= and_14856 ? one_hot_sel_14716 : ____state_3;
      ____state_0 <= and_14890 ? one_hot_sel_14794 : ____state_0;
      ____state_10 <= and_14896 ? one_hot_sel_14808 : ____state_10;
      ____state_6 <= and_14893 ? one_hot_sel_14801 : ____state_6;
      ____state_12 <= and_14870 ? NextRandom_1 : ____state_12;
      ____state_8 <= and_14862 ? one_hot_sel_14730 : ____state_8;
      ____state_11 <= and_14868 ? one_hot_sel_14745 : ____state_11;
      ____state_9 <= and_14865 ? one_hot_sel_14738 : ____state_9;
      ____state_5_1 <= and_14885 ? and_14624 : ____state_5_1;
      ____state_5_0 <= and_14885 ? and_14623 : ____state_5_0;
      ____state_4_1 <= and_14881 ? _37 : ____state_4_1;
      ____state_4_0 <= and_14881 ? _31 : ____state_4_0;
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
    assign admitted_slots_tuple_idx_0[__i0] = concat_14110 == __i0 ? and_14109 : ____state_13_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_14110 == __i0 ? sel_14142 : ____state_13_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_14110 == __i0 ? sel_14154 : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_14541 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_14541 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_14541 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_15272;
  wire eq_15277;
  wire ne_15261;
  wire and_15278;
  wire or_15275;
  wire [2:0] add_15269;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15264;
  wire popped;
  wire [1:0] sub_15290;
  wire [1:0] add_15292;
  wire [2:0] umod_15270;
  wire [2:0] umod_15265;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15294;
  wire array_update_15301[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15272 = pop_ready & push_valid;
  assign eq_15277 = head == tail;
  assign ne_15261 = head != tail;
  assign and_15278 = eq_15277 & and_15272;
  assign or_15275 = ne_15261 | push_valid;
  assign add_15269 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15264 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15275;
  assign sub_15290 = slots - 2'h1;
  assign add_15292 = slots + 2'h1;
  assign umod_15270 = add_15269 % long_buf_size_lit;
  assign umod_15265 = add_15264 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15270[1:0];
  assign did_push_occur = (can_do_push | and_15272) & push_valid & ~and_15278 & ~is_full_bool;
  assign next_tail_if_pop = umod_15265[1:0];
  assign did_pop_occur = (ne_15261 | and_15272) & pop_ready & ~and_15278;
  assign sel_15294 = pushed ? (popped ? slots : add_15292) : (popped ? sub_15290 : slots);
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
      slots <= sel_15294;
      buf__1[0] <= did_push_occur ? array_update_15301[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15301[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15275;
  assign pop_data = eq_15277 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15301_0
    assign array_update_15301[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15329;
  wire eq_15334;
  wire ne_15318;
  wire and_15335;
  wire or_15332;
  wire [2:0] add_15326;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15321;
  wire popped;
  wire [1:0] sub_15347;
  wire [1:0] add_15349;
  wire [2:0] umod_15327;
  wire [2:0] umod_15322;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15351;
  wire [127:0] array_update_15358[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15329 = pop_ready & push_valid;
  assign eq_15334 = head == tail;
  assign ne_15318 = head != tail;
  assign and_15335 = eq_15334 & and_15329;
  assign or_15332 = ne_15318 | push_valid;
  assign add_15326 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15321 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15332;
  assign sub_15347 = slots - 2'h1;
  assign add_15349 = slots + 2'h1;
  assign umod_15327 = add_15326 % long_buf_size_lit;
  assign umod_15322 = add_15321 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15327[1:0];
  assign did_push_occur = (can_do_push | and_15329) & push_valid & ~and_15335 & ~is_full_bool;
  assign next_tail_if_pop = umod_15322[1:0];
  assign did_pop_occur = (ne_15318 | and_15329) & pop_ready & ~and_15335;
  assign sel_15351 = pushed ? (popped ? slots : add_15349) : (popped ? sub_15347 : slots);
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
      slots <= sel_15351;
      buf__1[0] <= did_push_occur ? array_update_15358[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15358[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15332;
  assign pop_data = eq_15334 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15358_0
    assign array_update_15358[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15386;
  wire eq_15391;
  wire ne_15375;
  wire and_15392;
  wire or_15389;
  wire [2:0] add_15383;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15378;
  wire popped;
  wire [1:0] sub_15404;
  wire [1:0] add_15406;
  wire [2:0] umod_15384;
  wire [2:0] umod_15379;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15408;
  wire [127:0] array_update_15415[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15386 = pop_ready & push_valid;
  assign eq_15391 = head == tail;
  assign ne_15375 = head != tail;
  assign and_15392 = eq_15391 & and_15386;
  assign or_15389 = ne_15375 | push_valid;
  assign add_15383 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15378 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15389;
  assign sub_15404 = slots - 2'h1;
  assign add_15406 = slots + 2'h1;
  assign umod_15384 = add_15383 % long_buf_size_lit;
  assign umod_15379 = add_15378 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15384[1:0];
  assign did_push_occur = (can_do_push | and_15386) & push_valid & ~and_15392 & ~is_full_bool;
  assign next_tail_if_pop = umod_15379[1:0];
  assign did_pop_occur = (ne_15375 | and_15386) & pop_ready & ~and_15392;
  assign sel_15408 = pushed ? (popped ? slots : add_15406) : (popped ? sub_15404 : slots);
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
      slots <= sel_15408;
      buf__1[0] <= did_push_occur ? array_update_15415[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15415[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15389;
  assign pop_data = eq_15391 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15415_0
    assign array_update_15415[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15443;
  wire eq_15448;
  wire ne_15432;
  wire and_15449;
  wire or_15446;
  wire [2:0] add_15440;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15435;
  wire popped;
  wire [1:0] sub_15461;
  wire [1:0] add_15463;
  wire [2:0] umod_15441;
  wire [2:0] umod_15436;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15465;
  wire [127:0] array_update_15472[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15443 = pop_ready & push_valid;
  assign eq_15448 = head == tail;
  assign ne_15432 = head != tail;
  assign and_15449 = eq_15448 & and_15443;
  assign or_15446 = ne_15432 | push_valid;
  assign add_15440 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15435 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15446;
  assign sub_15461 = slots - 2'h1;
  assign add_15463 = slots + 2'h1;
  assign umod_15441 = add_15440 % long_buf_size_lit;
  assign umod_15436 = add_15435 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15441[1:0];
  assign did_push_occur = (can_do_push | and_15443) & push_valid & ~and_15449 & ~is_full_bool;
  assign next_tail_if_pop = umod_15436[1:0];
  assign did_pop_occur = (ne_15432 | and_15443) & pop_ready & ~and_15449;
  assign sel_15465 = pushed ? (popped ? slots : add_15463) : (popped ? sub_15461 : slots);
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
      slots <= sel_15465;
      buf__1[0] <= did_push_occur ? array_update_15472[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15472[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15446;
  assign pop_data = eq_15448 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15472_0
    assign array_update_15472[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15500;
  wire eq_15505;
  wire ne_15489;
  wire and_15506;
  wire or_15503;
  wire [2:0] add_15497;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15492;
  wire popped;
  wire [1:0] sub_15518;
  wire [1:0] add_15520;
  wire [2:0] umod_15498;
  wire [2:0] umod_15493;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15522;
  wire [127:0] array_update_15529[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15500 = pop_ready & push_valid;
  assign eq_15505 = head == tail;
  assign ne_15489 = head != tail;
  assign and_15506 = eq_15505 & and_15500;
  assign or_15503 = ne_15489 | push_valid;
  assign add_15497 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15492 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15503;
  assign sub_15518 = slots - 2'h1;
  assign add_15520 = slots + 2'h1;
  assign umod_15498 = add_15497 % long_buf_size_lit;
  assign umod_15493 = add_15492 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15498[1:0];
  assign did_push_occur = (can_do_push | and_15500) & push_valid & ~and_15506 & ~is_full_bool;
  assign next_tail_if_pop = umod_15493[1:0];
  assign did_pop_occur = (ne_15489 | and_15500) & pop_ready & ~and_15506;
  assign sel_15522 = pushed ? (popped ? slots : add_15520) : (popped ? sub_15518 : slots);
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
      slots <= sel_15522;
      buf__1[0] <= did_push_occur ? array_update_15529[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15529[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15503;
  assign pop_data = eq_15505 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15529_0
    assign array_update_15529[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15557;
  wire eq_15562;
  wire ne_15546;
  wire and_15563;
  wire or_15560;
  wire [2:0] add_15554;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15549;
  wire popped;
  wire [1:0] sub_15575;
  wire [1:0] add_15577;
  wire [2:0] umod_15555;
  wire [2:0] umod_15550;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15579;
  wire [127:0] array_update_15586[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15557 = pop_ready & push_valid;
  assign eq_15562 = head == tail;
  assign ne_15546 = head != tail;
  assign and_15563 = eq_15562 & and_15557;
  assign or_15560 = ne_15546 | push_valid;
  assign add_15554 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15549 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15560;
  assign sub_15575 = slots - 2'h1;
  assign add_15577 = slots + 2'h1;
  assign umod_15555 = add_15554 % long_buf_size_lit;
  assign umod_15550 = add_15549 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15555[1:0];
  assign did_push_occur = (can_do_push | and_15557) & push_valid & ~and_15563 & ~is_full_bool;
  assign next_tail_if_pop = umod_15550[1:0];
  assign did_pop_occur = (ne_15546 | and_15557) & pop_ready & ~and_15563;
  assign sel_15579 = pushed ? (popped ? slots : add_15577) : (popped ? sub_15575 : slots);
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
      slots <= sel_15579;
      buf__1[0] <= did_push_occur ? array_update_15586[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15586[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15560;
  assign pop_data = eq_15562 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15586_0
    assign array_update_15586[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_15054;
  wire instantiation_output_15079;
  wire [127:0] instantiation_output_15103;
  wire instantiation_output_15104;
  wire instantiation_output_15092;
  wire [32:0] instantiation_output_15096;
  wire instantiation_output_15097;
  wire instantiation_output_15067;
  wire [32:0] instantiation_output_15071;
  wire instantiation_output_15072;
  wire instantiation_output_15143;
  wire [32:0] instantiation_output_15147;
  wire instantiation_output_15148;
  wire instantiation_output_15124;
  wire [32:0] instantiation_output_15128;
  wire instantiation_output_15129;
  wire instantiation_output_15046;
  wire instantiation_output_15047;
  wire [127:0] instantiation_output_15059;
  wire instantiation_output_15060;
  wire [127:0] instantiation_output_15084;
  wire instantiation_output_15085;
  wire instantiation_output_15111;
  wire [127:0] instantiation_output_15116;
  wire instantiation_output_15117;
  wire [127:0] instantiation_output_15135;
  wire instantiation_output_15136;
  wire instantiation_output_15594;
  wire instantiation_output_15595;
  wire instantiation_output_15596;
  wire instantiation_output_15601;
  wire [127:0] instantiation_output_15602;
  wire instantiation_output_15603;
  wire instantiation_output_15608;
  wire [127:0] instantiation_output_15609;
  wire instantiation_output_15610;
  wire instantiation_output_15615;
  wire [127:0] instantiation_output_15616;
  wire instantiation_output_15617;
  wire instantiation_output_15622;
  wire [127:0] instantiation_output_15623;
  wire instantiation_output_15624;
  wire instantiation_output_15629;
  wire [127:0] instantiation_output_15630;
  wire instantiation_output_15631;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_15595),
    .phi_halo_cell__admit_vld(instantiation_output_15596),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_15615),
    .phi_halo_cell__admit_rdy(instantiation_output_15054),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_15079),
    .phi_halo_cell__req(instantiation_output_15103),
    .phi_halo_cell__req_vld(instantiation_output_15104),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_15609),
    .phi_halo_cell__north_vld(instantiation_output_15610),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_15092),
    .phi_halo_cell__north_send(instantiation_output_15096),
    .phi_halo_cell__north_send_vld(instantiation_output_15097),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_15602),
    .phi_halo_cell__east_vld(instantiation_output_15603),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_15067),
    .phi_halo_cell__east_send(instantiation_output_15071),
    .phi_halo_cell__east_send_vld(instantiation_output_15072),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_15630),
    .phi_halo_cell__west_vld(instantiation_output_15631),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_15143),
    .phi_halo_cell__west_send(instantiation_output_15147),
    .phi_halo_cell__west_send_vld(instantiation_output_15148),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_15623),
    .phi_halo_cell__south_vld(instantiation_output_15624),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_15124),
    .phi_halo_cell__south_send(instantiation_output_15128),
    .phi_halo_cell__south_send_vld(instantiation_output_15129),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_15594),
    .phi_halo_cell__east_rdy(instantiation_output_15601),
    .phi_halo_cell__north_rdy(instantiation_output_15608),
    .phi_halo_cell__req(instantiation_output_15616),
    .phi_halo_cell__req_vld(instantiation_output_15617),
    .phi_halo_cell__south_rdy(instantiation_output_15622),
    .phi_halo_cell__west_rdy(instantiation_output_15629),
    .phi_halo_cell__admit(instantiation_output_15046),
    .phi_halo_cell__admit_vld(instantiation_output_15047),
    .phi_halo_cell__east(instantiation_output_15059),
    .phi_halo_cell__east_vld(instantiation_output_15060),
    .phi_halo_cell__north(instantiation_output_15084),
    .phi_halo_cell__north_vld(instantiation_output_15085),
    .phi_halo_cell__req_rdy(instantiation_output_15111),
    .phi_halo_cell__south(instantiation_output_15116),
    .phi_halo_cell__south_vld(instantiation_output_15117),
    .phi_halo_cell__west(instantiation_output_15135),
    .phi_halo_cell__west_vld(instantiation_output_15136),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_15046),
    .push_valid(instantiation_output_15047),
    .pop_ready(instantiation_output_15054),
    .push_ready(instantiation_output_15594),
    .pop_data(instantiation_output_15595),
    .pop_valid(instantiation_output_15596),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_15059),
    .push_valid(instantiation_output_15060),
    .pop_ready(instantiation_output_15067),
    .push_ready(instantiation_output_15601),
    .pop_data(instantiation_output_15602),
    .pop_valid(instantiation_output_15603),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_15084),
    .push_valid(instantiation_output_15085),
    .pop_ready(instantiation_output_15092),
    .push_ready(instantiation_output_15608),
    .pop_data(instantiation_output_15609),
    .pop_valid(instantiation_output_15610),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_15103),
    .push_valid(instantiation_output_15104),
    .pop_ready(instantiation_output_15111),
    .push_ready(instantiation_output_15615),
    .pop_data(instantiation_output_15616),
    .pop_valid(instantiation_output_15617),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_15116),
    .push_valid(instantiation_output_15117),
    .pop_ready(instantiation_output_15124),
    .push_ready(instantiation_output_15622),
    .pop_data(instantiation_output_15623),
    .pop_valid(instantiation_output_15624),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_15135),
    .push_valid(instantiation_output_15136),
    .pop_ready(instantiation_output_15143),
    .push_ready(instantiation_output_15629),
    .pop_data(instantiation_output_15630),
    .pop_valid(instantiation_output_15631),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_15071;
  assign phi_halo_cell__east_send_vld = instantiation_output_15072;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_15079;
  assign phi_halo_cell__north_send = instantiation_output_15096;
  assign phi_halo_cell__north_send_vld = instantiation_output_15097;
  assign phi_halo_cell__south_send = instantiation_output_15128;
  assign phi_halo_cell__south_send_vld = instantiation_output_15129;
  assign phi_halo_cell__west_send = instantiation_output_15147;
  assign phi_halo_cell__west_send_vld = instantiation_output_15148;
endmodule
