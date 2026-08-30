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
  wire [32:0] literal_13469 = {1'h0, 32'h0000_0000};
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
  wire and_13479;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_13478;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_13491;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_15278;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_15277;
  wire [31:0] sel_15276;
  wire [31:0] sel_15275;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_13536;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_15281;
  wire nand_13507;
  wire [127:0] one_hot_sel_13537;
  wire and_13551;
  wire [7:0] one_hot_sel_13544;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_13469;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_13479 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_13479;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_13478 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_13479;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_13478, and_13479};
  assign one_hot_13491 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_15278 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_15277 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_15276 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_15275 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_13478 == one_hot_13491[1] & and_13479 == one_hot_13491[0];
  assign concat_13536 = {nor_13478 & p0_stage_done, and_13479 & p0_stage_done};
  assign payload = {sel_15277, sel_15276, sel_15275, sel_15278};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_15281 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_13507 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_13537 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13536[0]}} | payload & {128{concat_13536[1]}};
  assign and_13551 = (nor_13478 | and_13479) & p0_stage_done;
  assign one_hot_sel_13544 = 8'h00 & {8{concat_13536[0]}} | words_seen & {8{concat_13536[1]}};
  assign __phi_halo_cell__req_buf = {{sel_15278[7:0], sel_15278[15:8], sel_15278[23:16], sel_15278[31:24]}, {sel_15277, sel_15276, sel_15275}};
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
      ____state_0 <= p0_stage_done ? nand_13507 : ____state_0;
      ____state_2 <= and_13551 ? one_hot_sel_13544 : ____state_2;
      ____state_1 <= and_13551 ? one_hot_sel_13537 : ____state_1;
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
  wire [127:0] literal_13607 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13619;
  wire not_13620;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_13629;
  wire [2:0] one_hot_13630;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_13669;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13672;
  wire [127:0] payload;
  wire [1:0] concat_13685;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_15285;
  wire or_15289;
  wire [7:0] one_hot_sel_13673;
  wire and_13693;
  wire [127:0] one_hot_sel_13680;
  wire [7:0] one_hot_sel_13686;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_13607;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_13619 = ~(last | ____state_0);
  assign not_13620 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13619};
  assign ____state_6__next_value_predicates = {not_13620, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_13629 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13630 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_13669 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13629[1] & nor_13619 == one_hot_13629[0];
  assign ____state_6__at_most_one_next_value = not_13620 == one_hot_13630[1] & last == one_hot_13630[0];
  assign concat_13672 = {and_13669, nor_13619 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13685 = {not_13620 & p0_stage_done, and_13669};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_15285 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15289 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13673 = frame_header_payload_words__1 & {8{concat_13672[0]}} | 8'h00 & {8{concat_13672[1]}};
  assign and_13693 = (last | nor_13619) & p0_stage_done;
  assign one_hot_sel_13680 = payload & {128{concat_13672[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13672[1]}};
  assign one_hot_sel_13686 = 8'h00 & {8{concat_13685[0]}} | beats_sent & {8{concat_13685[1]}};
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
      ____state_0 <= p0_stage_done ? not_13620 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13686 : ____state_6;
      ____state_1 <= and_13693 ? one_hot_sel_13673 : ____state_1;
      ____state_5 <= and_13693 ? one_hot_sel_13680 : ____state_5;
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
  wire [127:0] literal_13742 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13754;
  wire not_13755;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_13764;
  wire [2:0] one_hot_13765;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_13804;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13807;
  wire [127:0] payload;
  wire [1:0] concat_13820;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_15291;
  wire or_15295;
  wire [7:0] one_hot_sel_13808;
  wire and_13828;
  wire [127:0] one_hot_sel_13815;
  wire [7:0] one_hot_sel_13821;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_13742;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_13754 = ~(last | ____state_0);
  assign not_13755 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13754};
  assign ____state_6__next_value_predicates = {not_13755, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_13764 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13765 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_13804 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13764[1] & nor_13754 == one_hot_13764[0];
  assign ____state_6__at_most_one_next_value = not_13755 == one_hot_13765[1] & last == one_hot_13765[0];
  assign concat_13807 = {and_13804, nor_13754 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13820 = {not_13755 & p0_stage_done, and_13804};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_15291 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15295 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13808 = frame_header_payload_words__1 & {8{concat_13807[0]}} | 8'h00 & {8{concat_13807[1]}};
  assign and_13828 = (last | nor_13754) & p0_stage_done;
  assign one_hot_sel_13815 = payload & {128{concat_13807[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13807[1]}};
  assign one_hot_sel_13821 = 8'h00 & {8{concat_13820[0]}} | beats_sent & {8{concat_13820[1]}};
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
      ____state_0 <= p0_stage_done ? not_13755 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13821 : ____state_6;
      ____state_1 <= and_13828 ? one_hot_sel_13808 : ____state_1;
      ____state_5 <= and_13828 ? one_hot_sel_13815 : ____state_5;
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
  wire [127:0] literal_13877 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_13889;
  wire not_13890;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_13899;
  wire [2:0] one_hot_13900;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_13939;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_13942;
  wire [127:0] payload;
  wire [1:0] concat_13955;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_15297;
  wire or_15301;
  wire [7:0] one_hot_sel_13943;
  wire and_13963;
  wire [127:0] one_hot_sel_13950;
  wire [7:0] one_hot_sel_13956;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_13877;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_13889 = ~(last | ____state_0);
  assign not_13890 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_13889};
  assign ____state_6__next_value_predicates = {not_13890, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_13899 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_13900 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_13939 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_13899[1] & nor_13889 == one_hot_13899[0];
  assign ____state_6__at_most_one_next_value = not_13890 == one_hot_13900[1] & last == one_hot_13900[0];
  assign concat_13942 = {and_13939, nor_13889 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_13955 = {not_13890 & p0_stage_done, and_13939};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_15297 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15301 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_13943 = frame_header_payload_words__1 & {8{concat_13942[0]}} | 8'h00 & {8{concat_13942[1]}};
  assign and_13963 = (last | nor_13889) & p0_stage_done;
  assign one_hot_sel_13950 = payload & {128{concat_13942[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_13942[1]}};
  assign one_hot_sel_13956 = 8'h00 & {8{concat_13955[0]}} | beats_sent & {8{concat_13955[1]}};
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
      ____state_0 <= p0_stage_done ? not_13890 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_13956 : ____state_6;
      ____state_1 <= and_13963 ? one_hot_sel_13943 : ____state_1;
      ____state_5 <= and_13963 ? one_hot_sel_13950 : ____state_5;
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
  wire [127:0] literal_14012 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_14024;
  wire not_14025;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_14034;
  wire [2:0] one_hot_14035;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_14074;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_14077;
  wire [127:0] payload;
  wire [1:0] concat_14090;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_15303;
  wire or_15307;
  wire [7:0] one_hot_sel_14078;
  wire and_14098;
  wire [127:0] one_hot_sel_14085;
  wire [7:0] one_hot_sel_14091;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_14012;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_14024 = ~(last | ____state_0);
  assign not_14025 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_14024};
  assign ____state_6__next_value_predicates = {not_14025, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_14034 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_14035 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_14074 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_14034[1] & nor_14024 == one_hot_14034[0];
  assign ____state_6__at_most_one_next_value = not_14025 == one_hot_14035[1] & last == one_hot_14035[0];
  assign concat_14077 = {and_14074, nor_14024 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_14090 = {not_14025 & p0_stage_done, and_14074};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_15303 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_15307 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_14078 = frame_header_payload_words__1 & {8{concat_14077[0]}} | 8'h00 & {8{concat_14077[1]}};
  assign and_14098 = (last | nor_14024) & p0_stage_done;
  assign one_hot_sel_14085 = payload & {128{concat_14077[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_14077[1]}};
  assign one_hot_sel_14091 = 8'h00 & {8{concat_14090[0]}} | beats_sent & {8{concat_14090[1]}};
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
      ____state_0 <= p0_stage_done ? not_14025 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_14091 : ____state_6;
      ____state_1 <= and_14098 ? one_hot_sel_14078 : ____state_1;
      ____state_5 <= and_14098 ? one_hot_sel_14085 : ____state_5;
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
  wire [127:0] literal_14206 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_14204;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_14215;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_14231;
  wire [31:0] concat_14232;
  wire ugt_14234;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_14236;
  wire postponed__4;
  wire ugt_14240;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_2645_0__2_case_0_case_1_case_0;
  wire or_reduce_14244;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_14255;
  wire postponed;
  wire [95:0] sel_14264;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_14267;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Value1_1;
  wire [31:0] _5__9_source;
  wire [31:0] _5__8_source;
  wire [31:0] _5__7_source;
  wire [31:0] _5__6_source;
  wire [7:0] sel_14276;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire _0__15;
  wire _1__5;
  wire _2__5;
  wire [31:0] _7__3;
  wire [1:0] unexpand_for_next_value_2645_0__2_case_0_case_0_case_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire eq_14288;
  wire _8__3;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [1:0] unexpand_for_next_value_2645_0__2_case_0_case_0_case_2;
  wire [30:0] add_14292;
  wire eq_14294;
  wire nor_14295;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire and_14297;
  wire _21__2;
  wire eq_14299;
  wire [31:0] _1;
  wire or_14304;
  wire eq_14305;
  wire nand_14306;
  wire eq_14307;
  wire or_14309;
  wire [31:0] _2__1;
  wire eq_14312;
  wire eq_14313;
  wire _0__11;
  wire [1:0] concat_14319;
  wire [1:0] concat_14321;
  wire and_14323;
  wire _4__1;
  wire postponed_slot_tup0;
  wire eligible_0;
  wire invalid_input;
  wire eq_14336;
  wire _6__1;
  wire [1:0] priority_sel_14340;
  wire _3;
  wire _19;
  wire _47;
  wire found;
  wire compacted_4_tup0;
  wire nand_14356;
  wire and_14359;
  wire dispatchable;
  wire [1:0] priority_sel_14369;
  wire [1:0] concat_14371;
  wire [1:0] directive;
  wire [1:0] next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_14421;
  wire [1:0] candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire nor_14385;
  wire phase_changed;
  wire [31:0] Xls_clause_1_Value_1;
  wire and_14392;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire _12__2;
  wire and_14398;
  wire and_14400;
  wire final_slots_0_case_cmp;
  wire and_14408;
  wire and_14410;
  wire and_14413;
  wire and_14414;
  wire and_14415;
  wire eq_14416;
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
  wire and_14428;
  wire and_14430;
  wire Xls_clause_1_NewBestDirection_1_0_case_cmp;
  wire _15__1;
  wire candidate_occupied_0_case_cmp;
  wire and_14438;
  wire candidate_slots_0_case_cmp;
  wire and_14441;
  wire and_14442;
  wire or_14443;
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
  wire and_14459;
  wire and_14460;
  wire and_14461;
  wire and_14462;
  wire and_14463;
  wire and_14464;
  wire and_14465;
  wire and_14466;
  wire and_14467;
  wire and_14468;
  wire and_14469;
  wire and_14470;
  wire and_14471;
  wire and_14472;
  wire and_14473;
  wire and_14474;
  wire and_14475;
  wire and_14476;
  wire and_14477;
  wire and_14478;
  wire and_14479;
  wire and_14480;
  wire and_14481;
  wire and_14482;
  wire and_14483;
  wire and_14484;
  wire and_14485;
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
  wire _16__1;
  wire Move_1__1;
  wire _19__2;
  wire _22__3;
  wire _25__4;
  wire [2:0] one_hot_14543;
  wire [2:0] one_hot_14544;
  wire [2:0] one_hot_14545;
  wire [3:0] one_hot_14546;
  wire [2:0] one_hot_14547;
  wire [2:0] one_hot_14548;
  wire [2:0] one_hot_14549;
  wire [11:0] one_hot_14550;
  wire [2:0] one_hot_14551;
  wire [2:0] one_hot_14552;
  wire [5:0] one_hot_14553;
  wire [8:0] one_hot_14554;
  wire [14:0] _2__15;
  wire [30:0] add_14497;
  wire [63:0] umul_14498;
  wire [95:0] array_index_14522;
  wire [95:0] array_index_14524;
  wire [95:0] array_index_14526;
  wire [7:0] array_index_14530;
  wire [7:0] array_index_14532;
  wire [7:0] array_index_14534;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_14540;
  wire ne_14577;
  wire or_reduce_14579;
  wire ugt_14581;
  wire phi_halo_cell__req_valid_inv;
  wire and_14834;
  wire and_14835;
  wire and_14841;
  wire and_14849;
  wire _31__2;
  wire admission_pending;
  wire [15:0] add_14595;
  wire and_14934;
  wire and_14935;
  wire and_14936;
  wire and_14937;
  wire [31:0] concat_14663;
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
  wire [95:0] concat_14558;
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
  wire [1:0] concat_14837;
  wire [31:0] _42;
  wire [1:0] concat_14844;
  wire [1:0] concat_14851;
  wire [2:0] concat_14859;
  wire [1:0] concat_14866;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire [31:0] _31__1;
  wire [16:0] NextRandom_1__11;
  wire [9:0] NextRandom_1__10;
  wire [4:0] NextRandom_1__9;
  wire [1:0] concat_14876;
  wire [1:0] concat_14886;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_14674;
  wire [31:0] sign_ext_14675;
  wire [10:0] concat_14915;
  wire [1:0] concat_14922;
  wire [1:0] unexpand_for_next_value_2645_6__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_14929;
  wire [1:0] unexpand_for_next_value_2645_10__2_case_0_case_1_case_2_case_1_case_0;
  wire [4:0] concat_14939;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_14952;
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
  wire [31:0] tuple_14644;
  wire phi_halo_cell__req_load_en;
  wire or_15309;
  wire or_15311;
  wire or_15313;
  wire or_15315;
  wire or_15317;
  wire or_15319;
  wire or_15321;
  wire or_15323;
  wire or_15325;
  wire or_15327;
  wire or_15329;
  wire or_15331;
  wire [31:0] _8__1;
  wire and_14975;
  wire [31:0] one_hot_sel_14838;
  wire and_14978;
  wire [31:0] one_hot_sel_14845;
  wire and_14981;
  wire [31:0] one_hot_sel_14852;
  wire and_14984;
  wire [31:0] one_hot_sel_14860;
  wire and_14987;
  wire [31:0] one_hot_sel_14867;
  wire and_14990;
  wire [31:0] NextRandom_1;
  wire and_14992;
  wire [7:0] one_hot_sel_14877;
  wire and_14995;
  wire and_14727;
  wire and_14997;
  wire one_hot_sel_14887;
  wire and_15000;
  wire or_14725;
  wire [31:0] _31;
  wire and_15003;
  wire [31:0] _37;
  wire [31:0] and_14745;
  wire and_15007;
  wire [31:0] and_14746;
  wire [1:0] one_hot_sel_14916;
  wire and_15012;
  wire [1:0] one_hot_sel_14923;
  wire and_15015;
  wire [1:0] one_hot_sel_14930;
  wire and_15018;
  wire one_hot_sel_14940[0:4];
  wire and_15021;
  wire [95:0] one_hot_sel_14953[0:4];
  wire and_15024;
  wire [7:0] one_hot_sel_14966[0:4];
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
  assign nor_14204 = ~(____state_17 | ____state_15 | ~____state_16);
  assign received = nor_14204 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_14206;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_14215 = frame_header__1_payload_words == 8'h03;
  assign tag_ok = frame_header_op == 8'h03 & eq_14215 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02 | frame_header_op == MAILBOX_CAPACITY & eq_14215;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_14 + {7'h00, accepted};
  assign and_14231 = ~accepted & ____state_13_tuple_element_0[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign concat_14232 = {24'h00_0000, ____state_14};
  assign ugt_14234 = admitted_occupied > 8'h04;
  assign or_reduce_14236 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_14240 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_14234 | postponed__4);
  assign unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 = 2'h0;
  assign or_reduce_14244 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_14236 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_14240 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_14244 | postponed__1);
  assign eq_14255 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_14264 = accepted ? phi_halo_cell__req_select[95:0] : ____state_13_tuple_element_1_tuple_element_1[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_2645_0__2_case_0_case_1_case_0}))} & {8{eq_14255 | postponed}};
  assign bit_slice_14267 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_14267 > 3'h4 ? 3'h4 : bit_slice_14267];
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _5__9_source = 32'h0000_0001;
  assign _5__8_source = 32'h0000_0002;
  assign _5__7_source = 32'h0000_0004;
  assign _5__6_source = 32'h0000_0008;
  assign sel_14276 = accepted ? frame_header_op : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__15 = Xls_clause_1_Value1_1 == _5__9_source;
  assign _1__5 = Xls_clause_1_Value1_1 == _5__8_source;
  assign _2__5 = Xls_clause_1_Value1_1 == _5__7_source;
  assign _7__3 = ____state_7 & Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 = 2'h1;
  assign eq_14288 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _8__3 = _7__3 == 32'h0000_0000;
  assign Xls_clause_1_NewSeen_1 = ____state_7 | Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2645_0__2_case_0_case_0_case_2 = 2'h2;
  assign add_14292 = ____state_2[30:0] + ____state_3[31:1];
  assign eq_14294 = ____state_0 == unexpand_for_next_value_2645_0__2_case_0_case_0_case_1;
  assign nor_14295 = ~(____state_0[0] | ____state_0[1]);
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_14267 > 3'h4 ? 3'h4 : bit_slice_14267];
  assign and_14297 = eq_14288 & (_0__15 | _1__5 | _2__5 | Xls_clause_1_Value1_1 == _5__6_source) & _8__3;
  assign _21__2 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign eq_14299 = ____state_0 == unexpand_for_next_value_2645_0__2_case_0_case_0_case_2;
  assign _1 = {add_14292, ____state_3[0]};
  assign or_14304 = eq_14294 | nor_14295;
  assign eq_14305 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign nand_14306 = ~(and_14297 & _21__2);
  assign eq_14307 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign or_14309 = ____state_0[0] | ____state_0[1];
  assign _2__1 = _1 + _5__9_source;
  assign eq_14312 = add_14292 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_14313 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign _0__11 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign concat_14319 = {eq_14299, or_14304};
  assign concat_14321 = {eq_14294, nor_14295};
  assign and_14323 = eq_14307 & ~(eq_14299 | eq_14294) & or_14309;
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__1;
  assign postponed_slot_tup0 = 1'h1;
  assign eligible_0 = ~(eq_14255 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign eq_14336 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY;
  assign _6__1 = ____state_10 == 2'h3;
  assign priority_sel_14340 = priority_sel_2b_2way(concat_14321, unexpand_for_next_value_2645_0__2_case_0_case_1_case_0, nand_14306 ? unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2645_0__2_case_0_case_0_case_2, ____state_0);
  assign _3 = eq_14312 & eq_14313;
  assign _19 = ____state_6 == 2'h3;
  assign _47 = ____state_3 == _5__9_source;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign compacted_4_tup0 = 1'h0;
  assign nand_14356 = ~(eq_14288 & _0__11 & _6__1);
  assign and_14359 = _3 & _19 & _47;
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_14369 = priority_sel_2b_5way({eq_14336, eq_14305, and_14323, {2{eq_14307}} & {eq_14299 | eq_14294, nor_14295}}, (_4__1 ? unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2645_0__2_case_0_case_0_case_2) & {2{~(eq_14312 & eq_14313)}}, _3 ? unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2645_0__2_case_0_case_0_case_2, unexpand_for_next_value_2645_0__2_case_0_case_0_case_2, {priority_sel_1b_2way(concat_14319, ~eq_14288, ~(eq_14288 & _0__11), postponed_slot_tup0), eq_14288 & or_14304}, {priority_sel_1b_2way(concat_14321, ~eq_14288, ~and_14297, postponed_slot_tup0), ~(~eq_14288 | ____state_0[0] | ____state_0[1])}, unexpand_for_next_value_2645_0__2_case_0_case_0_case_2);
  assign concat_14371 = {priority_sel_1b_5way({eq_14336, eq_14305 & ~eq_14299 & ~or_14304, {2{eq_14305}} & concat_14319, eq_14307}, ____state_0[1], compacted_4_tup0, nand_14356, ____state_0[1], priority_sel_14340[1], ____state_0[1]), priority_sel_1b_5way({eq_14336, eq_14305 | and_14323, {3{eq_14307}} & {eq_14299, eq_14294, nor_14295}}, and_14359, postponed_slot_tup0, compacted_4_tup0, ____state_0[0], priority_sel_14340[0], ____state_0[0])};
  assign directive = priority_sel_14369 & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? concat_14371 : ____state_0;
  assign repeat_phase = dispatchable & eq_14307 & nor_14295 & _3 & ~(~_19 | _47);
  assign invalid_repeat = repeat_phase & (directive != unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 | next_phase_squeezed != ____state_0);
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_14421 = admitted_occupied + 8'hff;
  assign candidate_phase_squeezed = effective ? concat_14371 : ____state_0;
  assign failed = invalid_input | invalid_repeat | effective & directive == unexpand_for_next_value_2645_0__2_case_0_case_0_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_14421 : admitted_occupied;
  assign nor_14385 = ~(____state_17 | ____state_15);
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign Xls_clause_1_Value_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign and_14392 = nor_14385 & effective;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_16 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_16 | ____state_14 > 8'h04);
  assign _12__2 = Xls_clause_1_Value_1 > ____state_8;
  assign and_14398 = and_14392 & eq_14336;
  assign and_14400 = and_14392 & eq_14305;
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_14408 = and_14392 & eq_14307;
  assign and_14410 = and_14398 & eq_14294;
  assign and_14413 = and_14400 & eq_14299;
  assign and_14414 = nor_14385 & final_slots_0_case_cmp;
  assign and_14415 = nor_14385 & phase_boundary;
  assign eq_14416 = priority_sel_14369 == unexpand_for_next_value_2645_0__2_case_0_case_0_case_1;
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
  assign and_14428 = and_14408 & nor_14295;
  assign and_14430 = and_14410 & and_14297;
  assign Xls_clause_1_NewBestDirection_1_0_case_cmp = ~_12__2;
  assign _15__1 = Xls_clause_1_Value_1 == ____state_8;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_14438 = and_14413 & eq_14288 & _0__11;
  assign candidate_slots_0_case_cmp = ~effective;
  assign and_14441 = and_14414 & effective;
  assign and_14442 = and_14415 & effective;
  assign or_14443 = directive[0] | transition_slots_default_case_cmp;
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
  assign and_14459 = and_14428 & _3 & _19;
  assign and_14460 = and_14413 & eq_14288 & _0__11 & _6__1;
  assign and_14461 = and_14428 & and_14359;
  assign and_14462 = and_14410 & ~(~(and_14297 & _12__2));
  assign and_14463 = and_14430 & Xls_clause_1_NewBestDirection_1_0_case_cmp & _15__1;
  assign and_14464 = __phi_halo_cell__east_vld_buf & ~eq_14294 & or_14309;
  assign and_14465 = nor_14385 & candidate_occupied_0_case_cmp;
  assign and_14466 = nor_14385 & candidate_occupied_1_case_cmp;
  assign and_14467 = and_14408 & eq_14294;
  assign and_14468 = and_14408 & eq_14299;
  assign and_14469 = and_14400 & nor_14295;
  assign and_14470 = and_14400 & eq_14294;
  assign and_14471 = and_14398 & nor_14295;
  assign and_14472 = and_14428 & ~(_3 & _19 & _47);
  assign and_14473 = and_14413 & nand_14356;
  assign and_14474 = and_14410 & ~nand_14306;
  assign and_14475 = and_14410 & nand_14306;
  assign and_14476 = and_14428 & _3 & ~_19;
  assign and_14477 = and_14438 & ~_6__1;
  assign and_14478 = and_14414 & candidate_slots_0_case_cmp;
  assign and_14479 = and_14441 & transition_slots_predicate_piece_0;
  assign and_14480 = and_14441 & eq_14416;
  assign and_14481 = and_14441 & transition_slots_default_case_cmp;
  assign and_14482 = and_14415 & candidate_slots_0_case_cmp;
  assign and_14483 = and_14442 & transition_slots_predicate_piece_0;
  assign and_14484 = and_14442 & eq_14416 & or_14443;
  assign and_14485 = and_14442 & ~eq_14416 & or_14443;
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign _7__9 = ____state_11 == _5__9_source;
  assign _9 = ____state_9 != 32'h0000_0000;
  assign NextRandom_1__5 = _1__1[18] ^ _1__1[13];
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_14459, and_14460};
  assign ____state_7__next_value_predicates = {and_14461, and_14430};
  assign ____state_8__next_value_predicates = {and_14461, and_14462};
  assign ____state_9__next_value_predicates = {and_14461, and_14462, and_14463};
  assign ____state_11__next_value_predicates = {and_14464, and_14438};
  assign ____state_14__next_value_predicates = {and_14465, and_14466};
  assign ____state_16__next_value_predicates = {nor_14385, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_14467, and_14468, and_14469, and_14470, and_14471, and_14461, and_14472, and_14460, and_14473, and_14474, and_14475};
  assign ____state_6__next_value_predicates = {and_14476, and_14459};
  assign ____state_10__next_value_predicates = {and_14477, and_14460};
  assign ____state_13_tuple_element_0__next_value_predicates = {and_14415, and_14478, and_14479, and_14480, and_14481};
  assign ____state_13_tuple_element_1_tuple_element_1__next_value_predicates = {and_14478, and_14479, and_14480, and_14481, and_14482, and_14483, and_14484, and_14485};
  assign _8 = ____state_5_0 + Xls_clause_1_Value_1;
  assign _35 = ____state_4_0 + _12;
  assign _16__1 = ____state_9 == _5__9_source;
  assign Move_1__1 = _7__9 & _9 & NextRandom_1__5;
  assign _19__2 = ____state_9 == _5__8_source;
  assign _22__3 = ____state_9 == _5__7_source;
  assign _25__4 = ____state_9 == _5__6_source;
  assign one_hot_14543 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_14544 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_14545 = {____state_8__next_value_predicates[1:0] == 2'h0, ____state_8__next_value_predicates[1] && !____state_8__next_value_predicates[0], ____state_8__next_value_predicates[0]};
  assign one_hot_14546 = {____state_9__next_value_predicates[2:0] == 3'h0, ____state_9__next_value_predicates[2] && ____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_14547 = {____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_14548 = {____state_14__next_value_predicates[1:0] == 2'h0, ____state_14__next_value_predicates[1] && !____state_14__next_value_predicates[0], ____state_14__next_value_predicates[0]};
  assign one_hot_14549 = {____state_16__next_value_predicates[1:0] == 2'h0, ____state_16__next_value_predicates[1] && !____state_16__next_value_predicates[0], ____state_16__next_value_predicates[0]};
  assign one_hot_14550 = {____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_14551 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_14552 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_14553 = {____state_13_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_0__next_value_predicates[4] && ____state_13_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_0__next_value_predicates[3] && ____state_13_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_0__next_value_predicates[2] && ____state_13_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_0__next_value_predicates[1] && !____state_13_tuple_element_0__next_value_predicates[0], ____state_13_tuple_element_0__next_value_predicates[0]};
  assign one_hot_14554 = {____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign _2__15 = {_1__1[1:0], ____state_12[12:0]} ^ _1__1[18:4];
  assign add_14497 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_14498 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_14522 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_14524 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_14526 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_14530 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_14532 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_14534 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_14540 = ____state_4_1[30:0] + _8[31:1];
  assign ne_14577 = bit_slice_14267 != 3'h0;
  assign or_reduce_14579 = |selected[7:1];
  assign ugt_14581 = bit_slice_14267 > 3'h2;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_14834 = and_14459 & p0_all_active_outputs_ready;
  assign and_14835 = and_14460 & p0_all_active_outputs_ready;
  assign and_14841 = and_14461 & p0_all_active_outputs_ready;
  assign and_14849 = and_14462 & p0_all_active_outputs_ready;
  assign _31__2 = ____state_11[0] ^ Move_1__1;
  assign admission_pending = ~(~____state_16 | received);
  assign add_14595 = ____state_11[15:0] + {unexpand_for_next_value_2645_0__2_case_0_case_1_case_0, ____state_4_0[31:18]};
  assign and_14934 = and_14478 & p0_all_active_outputs_ready;
  assign and_14935 = and_14479 & p0_all_active_outputs_ready;
  assign and_14936 = and_14480 & p0_all_active_outputs_ready;
  assign and_14937 = and_14481 & p0_all_active_outputs_ready;
  assign concat_14663 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_14577 ? postponed : or_reduce_14244 & postponed__1;
  assign compacted_1_tup0 = or_reduce_14579 ? postponed__1 : ugt_14240 & postponed__2;
  assign compacted_2_tup0 = ugt_14581 ? postponed__2 : or_reduce_14236 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_14234 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_14577 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_14522 & {96{or_reduce_14244}};
  assign compacted_1_tup1_tup1 = or_reduce_14579 ? array_index_14522 : array_index_14524 & {96{ugt_14240}};
  assign compacted_2_tup1_tup1 = ugt_14581 ? array_index_14524 : array_index_14526 & {96{or_reduce_14236}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_14526 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_14234}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_14577 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_14530 & {8{or_reduce_14244}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_14579 ? array_index_14530 : array_index_14532 & {8{ugt_14240}};
  assign compacted_2_tup1_tup0_tup3 = ugt_14581 ? array_index_14532 : array_index_14534 & {8{or_reduce_14236}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_14534 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_14234}};
  assign concat_14558 = {____state_4_0, ____state_4_1, add_14292, ____state_3[0]};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_14204 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_14459 == one_hot_14543[1] & and_14460 == one_hot_14543[0];
  assign ____state_7__at_most_one_next_value = and_14461 == one_hot_14544[1] & and_14430 == one_hot_14544[0];
  assign ____state_8__at_most_one_next_value = and_14461 == one_hot_14545[1] & and_14462 == one_hot_14545[0];
  assign ____state_9__at_most_one_next_value = and_14461 == one_hot_14546[2] & and_14462 == one_hot_14546[1] & and_14463 == one_hot_14546[0];
  assign ____state_11__at_most_one_next_value = and_14464 == one_hot_14547[1] & and_14438 == one_hot_14547[0];
  assign ____state_14__at_most_one_next_value = and_14465 == one_hot_14548[1] & and_14466 == one_hot_14548[0];
  assign ____state_16__at_most_one_next_value = nor_14385 == one_hot_14549[1] & __phi_halo_cell__east_vld_buf == one_hot_14549[0];
  assign ____state_0__at_most_one_next_value = and_14467 == one_hot_14550[10] & and_14468 == one_hot_14550[9] & and_14469 == one_hot_14550[8] & and_14470 == one_hot_14550[7] & and_14471 == one_hot_14550[6] & and_14461 == one_hot_14550[5] & and_14472 == one_hot_14550[4] & and_14460 == one_hot_14550[3] & and_14473 == one_hot_14550[2] & and_14474 == one_hot_14550[1] & and_14475 == one_hot_14550[0];
  assign ____state_6__at_most_one_next_value = and_14476 == one_hot_14551[1] & and_14459 == one_hot_14551[0];
  assign ____state_10__at_most_one_next_value = and_14477 == one_hot_14552[1] & and_14460 == one_hot_14552[0];
  assign ____state_13_tuple_element_0__at_most_one_next_value = and_14415 == one_hot_14553[4] & and_14478 == one_hot_14553[3] & and_14479 == one_hot_14553[2] & and_14480 == one_hot_14553[1] & and_14481 == one_hot_14553[0];
  assign ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value = and_14478 == one_hot_14554[7] & and_14479 == one_hot_14554[6] & and_14480 == one_hot_14554[5] & and_14481 == one_hot_14554[4] & and_14482 == one_hot_14554[3] & and_14483 == one_hot_14554[2] & and_14484 == one_hot_14554[1] & and_14485 == one_hot_14554[0];
  assign concat_14837 = {and_14834, and_14835};
  assign _42 = ____state_3 + _5__9_source;
  assign concat_14844 = {and_14841, and_14430 & p0_all_active_outputs_ready};
  assign concat_14851 = {and_14841, and_14849};
  assign concat_14859 = {and_14841, and_14849, and_14463 & p0_all_active_outputs_ready};
  assign concat_14866 = {and_14464 & p0_all_active_outputs_ready, and_14438 & p0_all_active_outputs_ready};
  assign Xls_clause_1_NextAnyon_1 = ____state_11 ^ Xls_clause_1_Value1_1;
  assign _31__1 = {____state_11[31:1], _31__2};
  assign NextRandom_1__11 = _1__1[18:2] ^ {_1__1[13:2], _2__15[14:10]};
  assign NextRandom_1__10 = _2__15[14:5] ^ _2__15[9:0];
  assign NextRandom_1__9 = _2__15[4:0];
  assign concat_14876 = {and_14465 & p0_all_active_outputs_ready, and_14466 & p0_all_active_outputs_ready};
  assign concat_14886 = {nor_14385 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _27 = {add_14595, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_14540[30:2]};
  assign add_14674 = {compacted_4_tup0, add_14497[30:1]} + {3'h0, umul_14498[63:36]};
  assign sign_ext_14675 = {32{~_19}};
  assign concat_14915 = {and_14467 & p0_all_active_outputs_ready, and_14468 & p0_all_active_outputs_ready, and_14469 & p0_all_active_outputs_ready, and_14470 & p0_all_active_outputs_ready, and_14471 & p0_all_active_outputs_ready, and_14841, and_14472 & p0_all_active_outputs_ready, and_14835, and_14473 & p0_all_active_outputs_ready, and_14474 & p0_all_active_outputs_ready, and_14475 & p0_all_active_outputs_ready};
  assign concat_14922 = {and_14476 & p0_all_active_outputs_ready, and_14834};
  assign unexpand_for_next_value_2645_6__2_case_0_case_0_case_0_case_1_case_0 = ____state_6 + unexpand_for_next_value_2645_0__2_case_0_case_0_case_1;
  assign concat_14929 = {and_14477 & p0_all_active_outputs_ready, and_14835};
  assign unexpand_for_next_value_2645_10__2_case_0_case_1_case_2_case_1_case_0 = ____state_10 + unexpand_for_next_value_2645_0__2_case_0_case_0_case_1;
  assign concat_14939 = {and_14415 & p0_all_active_outputs_ready, and_14934, and_14935, and_14936, and_14937};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_14952 = {and_14934, and_14935, and_14936, and_14937, and_14482 & p0_all_active_outputs_ready, and_14483 & p0_all_active_outputs_ready, and_14484 & p0_all_active_outputs_ready, and_14485 & p0_all_active_outputs_ready};
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
  assign tuple_14644 = {{7'h01, or_14304}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, nor_14295 ? unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2645_0__2_case_0_case_0_case_2, or_14304}};
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_15309 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_15311 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_15313 = ~p0_all_active_outputs_ready | ____state_8__at_most_one_next_value | reset;
  assign or_15315 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_15317 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_15319 = ~p0_all_active_outputs_ready | ____state_14__at_most_one_next_value | reset;
  assign or_15321 = ~p0_all_active_outputs_ready | ____state_16__at_most_one_next_value | reset;
  assign or_15323 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_15325 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_15327 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_15329 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_0__at_most_one_next_value | reset;
  assign or_15331 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign _8__1 = ____state_2 + _5__9_source;
  assign and_14975 = and_14460 & p0_all_active_outputs_ready;
  assign one_hot_sel_14838 = 32'h0000_0000 & {32{concat_14837[0]}} | _42 & {32{concat_14837[1]}};
  assign and_14978 = (and_14459 | and_14460) & p0_all_active_outputs_ready;
  assign one_hot_sel_14845 = Xls_clause_1_NewSeen_1 & {32{concat_14844[0]}} | 32'h0000_0000 & {32{concat_14844[1]}};
  assign and_14981 = (and_14461 | and_14430) & p0_all_active_outputs_ready;
  assign one_hot_sel_14852 = Xls_clause_1_Value_1 & {32{concat_14851[0]}} | 32'h0000_0000 & {32{concat_14851[1]}};
  assign and_14984 = (and_14461 | and_14462) & p0_all_active_outputs_ready;
  assign one_hot_sel_14860 = 32'h0000_0000 & {32{concat_14859[0]}} | Xls_clause_1_Value1_1 & {32{concat_14859[1]}} | 32'h0000_0000 & {32{concat_14859[2]}};
  assign and_14987 = (and_14461 | and_14462 | and_14463) & p0_all_active_outputs_ready;
  assign one_hot_sel_14867 = Xls_clause_1_NextAnyon_1 & {32{concat_14866[0]}} | _31__1 & {32{concat_14866[1]}};
  assign and_14990 = (and_14464 | and_14438) & p0_all_active_outputs_ready;
  assign NextRandom_1 = {NextRandom_1__11, NextRandom_1__10, NextRandom_1__9};
  assign and_14992 = and_14464 & p0_all_active_outputs_ready;
  assign one_hot_sel_14877 = add_14421 & {8{concat_14876[0]}} | admitted_occupied & {8{concat_14876[1]}};
  assign and_14995 = (and_14465 | and_14466) & p0_all_active_outputs_ready;
  assign and_14727 = ~____state_15 & effective & phase_boundary & ~failed;
  assign and_14997 = ~____state_17 & p0_all_active_outputs_ready;
  assign one_hot_sel_14887 = (____state_16 | ____state_14 < MAILBOX_CAPACITY) & concat_14886[0] | (admission_pending | reserve__1) & concat_14886[1];
  assign and_15000 = (nor_14385 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_14725 = ____state_17 | (____state_15 ? ____state_17 : failed);
  assign _31 = _27 + _30;
  assign and_15003 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14307 & nor_14295 & eq_14312 & eq_14313 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_14674};
  assign and_14745 = _8 & sign_ext_14675;
  assign and_15007 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_14307 & nor_14295 & _3 & p0_all_active_outputs_ready;
  assign and_14746 = _12 & sign_ext_14675;
  assign one_hot_sel_14916 = unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 & {2{concat_14915[0]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_2 & {2{concat_14915[1]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_2 & {2{concat_14915[2]}} | unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14915[3]}} | unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14915[4]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 & {2{concat_14915[5]}} | unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14915[6]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 & {2{concat_14915[7]}} | unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14915[8]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_2 & {2{concat_14915[9]}} | unexpand_for_next_value_2645_0__2_case_0_case_0_case_1 & {2{concat_14915[10]}};
  assign and_15012 = (and_14467 | and_14468 | and_14469 | and_14470 | and_14471 | and_14461 | and_14472 | and_14460 | and_14473 | and_14474 | and_14475) & p0_all_active_outputs_ready;
  assign one_hot_sel_14923 = unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14922[0]}} | unexpand_for_next_value_2645_6__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_14922[1]}};
  assign and_15015 = (and_14476 | and_14459) & p0_all_active_outputs_ready;
  assign one_hot_sel_14930 = unexpand_for_next_value_2645_0__2_case_0_case_1_case_0 & {2{concat_14929[0]}} | unexpand_for_next_value_2645_10__2_case_0_case_1_case_2_case_1_case_0 & {2{concat_14929[1]}};
  assign and_15018 = (and_14477 | and_14460) & p0_all_active_outputs_ready;
  assign one_hot_sel_14940[0] = admitted_slots_tuple_idx_0[0] & concat_14939[0] | postponed_slots_tuple_idx_0[0] & concat_14939[1] | compacted_slots_tuple_idx_0[0] & concat_14939[2] | admitted_slots_tuple_idx_0[0] & concat_14939[3] | unblocked_slots_tuple_idx_0[0] & concat_14939[4];
  assign one_hot_sel_14940[1] = admitted_slots_tuple_idx_0[1] & concat_14939[0] | postponed_slots_tuple_idx_0[1] & concat_14939[1] | compacted_slots_tuple_idx_0[1] & concat_14939[2] | admitted_slots_tuple_idx_0[1] & concat_14939[3] | unblocked_slots_tuple_idx_0[1] & concat_14939[4];
  assign one_hot_sel_14940[2] = admitted_slots_tuple_idx_0[2] & concat_14939[0] | postponed_slots_tuple_idx_0[2] & concat_14939[1] | compacted_slots_tuple_idx_0[2] & concat_14939[2] | admitted_slots_tuple_idx_0[2] & concat_14939[3] | unblocked_slots_tuple_idx_0[2] & concat_14939[4];
  assign one_hot_sel_14940[3] = admitted_slots_tuple_idx_0[3] & concat_14939[0] | postponed_slots_tuple_idx_0[3] & concat_14939[1] | compacted_slots_tuple_idx_0[3] & concat_14939[2] | admitted_slots_tuple_idx_0[3] & concat_14939[3] | unblocked_slots_tuple_idx_0[3] & concat_14939[4];
  assign one_hot_sel_14940[4] = admitted_slots_tuple_idx_0[4] & concat_14939[0] | postponed_slots_tuple_idx_0[4] & concat_14939[1] | compacted_slots_tuple_idx_0[4] & concat_14939[2] | admitted_slots_tuple_idx_0[4] & concat_14939[3] | unblocked_slots_tuple_idx_0[4] & concat_14939[4];
  assign and_15021 = (and_14415 | and_14478 | and_14479 | and_14480 | and_14481) & p0_all_active_outputs_ready;
  assign one_hot_sel_14953[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_14952[7]}};
  assign one_hot_sel_14953[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_14952[7]}};
  assign one_hot_sel_14953[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_14952[7]}};
  assign one_hot_sel_14953[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_14952[7]}};
  assign one_hot_sel_14953[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_14952[7]}};
  assign and_15024 = (and_14478 | and_14479 | and_14480 | and_14481 | and_14482 | and_14483 | and_14484 | and_14485) & p0_all_active_outputs_ready;
  assign one_hot_sel_14966[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_14952[7]}};
  assign one_hot_sel_14966[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_14952[7]}};
  assign one_hot_sel_14966[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_14952[7]}};
  assign one_hot_sel_14966[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_14952[7]}};
  assign one_hot_sel_14966[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_14952[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {tuple_14644, priority_sel_96b_2way(concat_14321, concat_14558, {____state_4_0, _5__6_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_16__1 & Move_1__1)), ____state_2})};
  assign effects_east = {tuple_14644, priority_sel_96b_2way(concat_14321, concat_14558, {____state_4_0, _5__7_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_19__2 & Move_1__1)), ____state_2})};
  assign effects_west = {tuple_14644, priority_sel_96b_2way(concat_14321, concat_14558, {____state_4_0, _5__8_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_22__3 & Move_1__1)), ____state_2})};
  assign effects_south = {tuple_14644, priority_sel_96b_2way(concat_14321, concat_14558, {____state_4_0, _5__9_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(_25__4 & Move_1__1)), ____state_2})};
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
      ____state_16 <= and_15000 ? one_hot_sel_14887 : ____state_16;
      ____state_17 <= p0_all_active_outputs_ready ? or_14725 : ____state_17;
      ____state_15 <= and_14997 ? and_14727 : ____state_15;
      ____state_13_tuple_element_0[0] <= and_15021 ? one_hot_sel_14940[0] : ____state_13_tuple_element_0[0];
      ____state_13_tuple_element_0[1] <= and_15021 ? one_hot_sel_14940[1] : ____state_13_tuple_element_0[1];
      ____state_13_tuple_element_0[2] <= and_15021 ? one_hot_sel_14940[2] : ____state_13_tuple_element_0[2];
      ____state_13_tuple_element_0[3] <= and_15021 ? one_hot_sel_14940[3] : ____state_13_tuple_element_0[3];
      ____state_13_tuple_element_0[4] <= and_15021 ? one_hot_sel_14940[4] : ____state_13_tuple_element_0[4];
      ____state_14 <= and_14995 ? one_hot_sel_14877 : ____state_14;
      ____state_13_tuple_element_1_tuple_element_1[0] <= and_15024 ? one_hot_sel_14953[0] : ____state_13_tuple_element_1_tuple_element_1[0];
      ____state_13_tuple_element_1_tuple_element_1[1] <= and_15024 ? one_hot_sel_14953[1] : ____state_13_tuple_element_1_tuple_element_1[1];
      ____state_13_tuple_element_1_tuple_element_1[2] <= and_15024 ? one_hot_sel_14953[2] : ____state_13_tuple_element_1_tuple_element_1[2];
      ____state_13_tuple_element_1_tuple_element_1[3] <= and_15024 ? one_hot_sel_14953[3] : ____state_13_tuple_element_1_tuple_element_1[3];
      ____state_13_tuple_element_1_tuple_element_1[4] <= and_15024 ? one_hot_sel_14953[4] : ____state_13_tuple_element_1_tuple_element_1[4];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_15024 ? one_hot_sel_14966[0] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_15024 ? one_hot_sel_14966[1] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_15024 ? one_hot_sel_14966[2] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_15024 ? one_hot_sel_14966[3] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_15024 ? one_hot_sel_14966[4] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_7 <= and_14981 ? one_hot_sel_14845 : ____state_7;
      ____state_2 <= and_14975 ? _8__1 : ____state_2;
      ____state_3 <= and_14978 ? one_hot_sel_14838 : ____state_3;
      ____state_0 <= and_15012 ? one_hot_sel_14916 : ____state_0;
      ____state_10 <= and_15018 ? one_hot_sel_14930 : ____state_10;
      ____state_6 <= and_15015 ? one_hot_sel_14923 : ____state_6;
      ____state_12 <= and_14992 ? NextRandom_1 : ____state_12;
      ____state_8 <= and_14984 ? one_hot_sel_14852 : ____state_8;
      ____state_11 <= and_14990 ? one_hot_sel_14867 : ____state_11;
      ____state_9 <= and_14987 ? one_hot_sel_14860 : ____state_9;
      ____state_5_1 <= and_15007 ? and_14746 : ____state_5_1;
      ____state_5_0 <= and_15007 ? and_14745 : ____state_5_0;
      ____state_4_1 <= and_15003 ? _37 : ____state_4_1;
      ____state_4_0 <= and_15003 ? _31 : ____state_4_0;
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
    assign admitted_slots_tuple_idx_0[__i0] = concat_14232 == __i0 ? and_14231 : ____state_13_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_14232 == __i0 ? sel_14264 : ____state_13_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_14232 == __i0 ? sel_14276 : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_14663 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_14663 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_14663 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_15394;
  wire eq_15399;
  wire ne_15383;
  wire and_15400;
  wire or_15397;
  wire [2:0] add_15391;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15386;
  wire popped;
  wire [1:0] sub_15412;
  wire [1:0] add_15414;
  wire [2:0] umod_15392;
  wire [2:0] umod_15387;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15416;
  wire array_update_15423[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15394 = pop_ready & push_valid;
  assign eq_15399 = head == tail;
  assign ne_15383 = head != tail;
  assign and_15400 = eq_15399 & and_15394;
  assign or_15397 = ne_15383 | push_valid;
  assign add_15391 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15386 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15397;
  assign sub_15412 = slots - 2'h1;
  assign add_15414 = slots + 2'h1;
  assign umod_15392 = add_15391 % long_buf_size_lit;
  assign umod_15387 = add_15386 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15392[1:0];
  assign did_push_occur = (can_do_push | and_15394) & push_valid & ~and_15400 & ~is_full_bool;
  assign next_tail_if_pop = umod_15387[1:0];
  assign did_pop_occur = (ne_15383 | and_15394) & pop_ready & ~and_15400;
  assign sel_15416 = pushed ? (popped ? slots : add_15414) : (popped ? sub_15412 : slots);
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
      slots <= sel_15416;
      buf__1[0] <= did_push_occur ? array_update_15423[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15423[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15397;
  assign pop_data = eq_15399 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15423_0
    assign array_update_15423[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15451;
  wire eq_15456;
  wire ne_15440;
  wire and_15457;
  wire or_15454;
  wire [2:0] add_15448;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15443;
  wire popped;
  wire [1:0] sub_15469;
  wire [1:0] add_15471;
  wire [2:0] umod_15449;
  wire [2:0] umod_15444;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15473;
  wire [127:0] array_update_15480[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15451 = pop_ready & push_valid;
  assign eq_15456 = head == tail;
  assign ne_15440 = head != tail;
  assign and_15457 = eq_15456 & and_15451;
  assign or_15454 = ne_15440 | push_valid;
  assign add_15448 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15443 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15454;
  assign sub_15469 = slots - 2'h1;
  assign add_15471 = slots + 2'h1;
  assign umod_15449 = add_15448 % long_buf_size_lit;
  assign umod_15444 = add_15443 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15449[1:0];
  assign did_push_occur = (can_do_push | and_15451) & push_valid & ~and_15457 & ~is_full_bool;
  assign next_tail_if_pop = umod_15444[1:0];
  assign did_pop_occur = (ne_15440 | and_15451) & pop_ready & ~and_15457;
  assign sel_15473 = pushed ? (popped ? slots : add_15471) : (popped ? sub_15469 : slots);
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
      slots <= sel_15473;
      buf__1[0] <= did_push_occur ? array_update_15480[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15480[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15454;
  assign pop_data = eq_15456 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15480_0
    assign array_update_15480[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15508;
  wire eq_15513;
  wire ne_15497;
  wire and_15514;
  wire or_15511;
  wire [2:0] add_15505;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15500;
  wire popped;
  wire [1:0] sub_15526;
  wire [1:0] add_15528;
  wire [2:0] umod_15506;
  wire [2:0] umod_15501;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15530;
  wire [127:0] array_update_15537[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15508 = pop_ready & push_valid;
  assign eq_15513 = head == tail;
  assign ne_15497 = head != tail;
  assign and_15514 = eq_15513 & and_15508;
  assign or_15511 = ne_15497 | push_valid;
  assign add_15505 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15500 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15511;
  assign sub_15526 = slots - 2'h1;
  assign add_15528 = slots + 2'h1;
  assign umod_15506 = add_15505 % long_buf_size_lit;
  assign umod_15501 = add_15500 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15506[1:0];
  assign did_push_occur = (can_do_push | and_15508) & push_valid & ~and_15514 & ~is_full_bool;
  assign next_tail_if_pop = umod_15501[1:0];
  assign did_pop_occur = (ne_15497 | and_15508) & pop_ready & ~and_15514;
  assign sel_15530 = pushed ? (popped ? slots : add_15528) : (popped ? sub_15526 : slots);
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
      slots <= sel_15530;
      buf__1[0] <= did_push_occur ? array_update_15537[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15537[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15511;
  assign pop_data = eq_15513 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15537_0
    assign array_update_15537[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15565;
  wire eq_15570;
  wire ne_15554;
  wire and_15571;
  wire or_15568;
  wire [2:0] add_15562;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15557;
  wire popped;
  wire [1:0] sub_15583;
  wire [1:0] add_15585;
  wire [2:0] umod_15563;
  wire [2:0] umod_15558;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15587;
  wire [127:0] array_update_15594[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15565 = pop_ready & push_valid;
  assign eq_15570 = head == tail;
  assign ne_15554 = head != tail;
  assign and_15571 = eq_15570 & and_15565;
  assign or_15568 = ne_15554 | push_valid;
  assign add_15562 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15557 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15568;
  assign sub_15583 = slots - 2'h1;
  assign add_15585 = slots + 2'h1;
  assign umod_15563 = add_15562 % long_buf_size_lit;
  assign umod_15558 = add_15557 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15563[1:0];
  assign did_push_occur = (can_do_push | and_15565) & push_valid & ~and_15571 & ~is_full_bool;
  assign next_tail_if_pop = umod_15558[1:0];
  assign did_pop_occur = (ne_15554 | and_15565) & pop_ready & ~and_15571;
  assign sel_15587 = pushed ? (popped ? slots : add_15585) : (popped ? sub_15583 : slots);
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
      slots <= sel_15587;
      buf__1[0] <= did_push_occur ? array_update_15594[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15594[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15568;
  assign pop_data = eq_15570 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15594_0
    assign array_update_15594[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15622;
  wire eq_15627;
  wire ne_15611;
  wire and_15628;
  wire or_15625;
  wire [2:0] add_15619;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15614;
  wire popped;
  wire [1:0] sub_15640;
  wire [1:0] add_15642;
  wire [2:0] umod_15620;
  wire [2:0] umod_15615;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15644;
  wire [127:0] array_update_15651[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15622 = pop_ready & push_valid;
  assign eq_15627 = head == tail;
  assign ne_15611 = head != tail;
  assign and_15628 = eq_15627 & and_15622;
  assign or_15625 = ne_15611 | push_valid;
  assign add_15619 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15614 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15625;
  assign sub_15640 = slots - 2'h1;
  assign add_15642 = slots + 2'h1;
  assign umod_15620 = add_15619 % long_buf_size_lit;
  assign umod_15615 = add_15614 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15620[1:0];
  assign did_push_occur = (can_do_push | and_15622) & push_valid & ~and_15628 & ~is_full_bool;
  assign next_tail_if_pop = umod_15615[1:0];
  assign did_pop_occur = (ne_15611 | and_15622) & pop_ready & ~and_15628;
  assign sel_15644 = pushed ? (popped ? slots : add_15642) : (popped ? sub_15640 : slots);
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
      slots <= sel_15644;
      buf__1[0] <= did_push_occur ? array_update_15651[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15651[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15625;
  assign pop_data = eq_15627 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15651_0
    assign array_update_15651[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_15679;
  wire eq_15684;
  wire ne_15668;
  wire and_15685;
  wire or_15682;
  wire [2:0] add_15676;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_15671;
  wire popped;
  wire [1:0] sub_15697;
  wire [1:0] add_15699;
  wire [2:0] umod_15677;
  wire [2:0] umod_15672;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_15701;
  wire [127:0] array_update_15708[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_15679 = pop_ready & push_valid;
  assign eq_15684 = head == tail;
  assign ne_15668 = head != tail;
  assign and_15685 = eq_15684 & and_15679;
  assign or_15682 = ne_15668 | push_valid;
  assign add_15676 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_15671 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_15682;
  assign sub_15697 = slots - 2'h1;
  assign add_15699 = slots + 2'h1;
  assign umod_15677 = add_15676 % long_buf_size_lit;
  assign umod_15672 = add_15671 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_15677[1:0];
  assign did_push_occur = (can_do_push | and_15679) & push_valid & ~and_15685 & ~is_full_bool;
  assign next_tail_if_pop = umod_15672[1:0];
  assign did_pop_occur = (ne_15668 | and_15679) & pop_ready & ~and_15685;
  assign sel_15701 = pushed ? (popped ? slots : add_15699) : (popped ? sub_15697 : slots);
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
      slots <= sel_15701;
      buf__1[0] <= did_push_occur ? array_update_15708[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_15708[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_15682;
  assign pop_data = eq_15684 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_15708_0
    assign array_update_15708[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_15176;
  wire instantiation_output_15201;
  wire [127:0] instantiation_output_15225;
  wire instantiation_output_15226;
  wire instantiation_output_15214;
  wire [32:0] instantiation_output_15218;
  wire instantiation_output_15219;
  wire instantiation_output_15189;
  wire [32:0] instantiation_output_15193;
  wire instantiation_output_15194;
  wire instantiation_output_15265;
  wire [32:0] instantiation_output_15269;
  wire instantiation_output_15270;
  wire instantiation_output_15246;
  wire [32:0] instantiation_output_15250;
  wire instantiation_output_15251;
  wire instantiation_output_15168;
  wire instantiation_output_15169;
  wire [127:0] instantiation_output_15181;
  wire instantiation_output_15182;
  wire [127:0] instantiation_output_15206;
  wire instantiation_output_15207;
  wire instantiation_output_15233;
  wire [127:0] instantiation_output_15238;
  wire instantiation_output_15239;
  wire [127:0] instantiation_output_15257;
  wire instantiation_output_15258;
  wire instantiation_output_15716;
  wire instantiation_output_15717;
  wire instantiation_output_15718;
  wire instantiation_output_15723;
  wire [127:0] instantiation_output_15724;
  wire instantiation_output_15725;
  wire instantiation_output_15730;
  wire [127:0] instantiation_output_15731;
  wire instantiation_output_15732;
  wire instantiation_output_15737;
  wire [127:0] instantiation_output_15738;
  wire instantiation_output_15739;
  wire instantiation_output_15744;
  wire [127:0] instantiation_output_15745;
  wire instantiation_output_15746;
  wire instantiation_output_15751;
  wire [127:0] instantiation_output_15752;
  wire instantiation_output_15753;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_15717),
    .phi_halo_cell__admit_vld(instantiation_output_15718),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_15737),
    .phi_halo_cell__admit_rdy(instantiation_output_15176),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_15201),
    .phi_halo_cell__req(instantiation_output_15225),
    .phi_halo_cell__req_vld(instantiation_output_15226),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_15731),
    .phi_halo_cell__north_vld(instantiation_output_15732),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_15214),
    .phi_halo_cell__north_send(instantiation_output_15218),
    .phi_halo_cell__north_send_vld(instantiation_output_15219),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_15724),
    .phi_halo_cell__east_vld(instantiation_output_15725),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_15189),
    .phi_halo_cell__east_send(instantiation_output_15193),
    .phi_halo_cell__east_send_vld(instantiation_output_15194),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_15752),
    .phi_halo_cell__west_vld(instantiation_output_15753),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_15265),
    .phi_halo_cell__west_send(instantiation_output_15269),
    .phi_halo_cell__west_send_vld(instantiation_output_15270),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_15745),
    .phi_halo_cell__south_vld(instantiation_output_15746),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_15246),
    .phi_halo_cell__south_send(instantiation_output_15250),
    .phi_halo_cell__south_send_vld(instantiation_output_15251),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_15716),
    .phi_halo_cell__east_rdy(instantiation_output_15723),
    .phi_halo_cell__north_rdy(instantiation_output_15730),
    .phi_halo_cell__req(instantiation_output_15738),
    .phi_halo_cell__req_vld(instantiation_output_15739),
    .phi_halo_cell__south_rdy(instantiation_output_15744),
    .phi_halo_cell__west_rdy(instantiation_output_15751),
    .phi_halo_cell__admit(instantiation_output_15168),
    .phi_halo_cell__admit_vld(instantiation_output_15169),
    .phi_halo_cell__east(instantiation_output_15181),
    .phi_halo_cell__east_vld(instantiation_output_15182),
    .phi_halo_cell__north(instantiation_output_15206),
    .phi_halo_cell__north_vld(instantiation_output_15207),
    .phi_halo_cell__req_rdy(instantiation_output_15233),
    .phi_halo_cell__south(instantiation_output_15238),
    .phi_halo_cell__south_vld(instantiation_output_15239),
    .phi_halo_cell__west(instantiation_output_15257),
    .phi_halo_cell__west_vld(instantiation_output_15258),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_15168),
    .push_valid(instantiation_output_15169),
    .pop_ready(instantiation_output_15176),
    .push_ready(instantiation_output_15716),
    .pop_data(instantiation_output_15717),
    .pop_valid(instantiation_output_15718),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_15181),
    .push_valid(instantiation_output_15182),
    .pop_ready(instantiation_output_15189),
    .push_ready(instantiation_output_15723),
    .pop_data(instantiation_output_15724),
    .pop_valid(instantiation_output_15725),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_15206),
    .push_valid(instantiation_output_15207),
    .pop_ready(instantiation_output_15214),
    .push_ready(instantiation_output_15730),
    .pop_data(instantiation_output_15731),
    .pop_valid(instantiation_output_15732),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_15225),
    .push_valid(instantiation_output_15226),
    .pop_ready(instantiation_output_15233),
    .push_ready(instantiation_output_15737),
    .pop_data(instantiation_output_15738),
    .pop_valid(instantiation_output_15739),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_15238),
    .push_valid(instantiation_output_15239),
    .pop_ready(instantiation_output_15246),
    .push_ready(instantiation_output_15744),
    .pop_data(instantiation_output_15745),
    .pop_valid(instantiation_output_15746),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_15257),
    .push_valid(instantiation_output_15258),
    .pop_ready(instantiation_output_15265),
    .push_ready(instantiation_output_15751),
    .pop_data(instantiation_output_15752),
    .pop_valid(instantiation_output_15753),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_15193;
  assign phi_halo_cell__east_send_vld = instantiation_output_15194;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_15201;
  assign phi_halo_cell__north_send = instantiation_output_15218;
  assign phi_halo_cell__north_send_vld = instantiation_output_15219;
  assign phi_halo_cell__south_send = instantiation_output_15250;
  assign phi_halo_cell__south_send_vld = instantiation_output_15251;
  assign phi_halo_cell__west_send = instantiation_output_15269;
  assign phi_halo_cell__west_send_vld = instantiation_output_15270;
endmodule
