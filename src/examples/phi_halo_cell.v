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
  wire [32:0] literal_8248 = {1'h0, 32'h0000_0000};
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
  wire and_8258;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_8257;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_8270;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_9840;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_9839;
  wire [31:0] sel_9838;
  wire [31:0] sel_9837;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_8315;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_9850;
  wire nand_8286;
  wire [127:0] one_hot_sel_8316;
  wire and_8330;
  wire [7:0] one_hot_sel_8323;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_8248;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_8258 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_8258;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_8257 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_8258;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_8257, and_8258};
  assign one_hot_8270 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_9840 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_9839 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_9838 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_9837 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_8257 == one_hot_8270[1] & and_8258 == one_hot_8270[0];
  assign concat_8315 = {nor_8257 & p0_stage_done, and_8258 & p0_stage_done};
  assign payload = {sel_9839, sel_9838, sel_9837, sel_9840};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_9850 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_8286 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_8316 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8315[0]}} | payload & {128{concat_8315[1]}};
  assign and_8330 = (nor_8257 | and_8258) & p0_stage_done;
  assign one_hot_sel_8323 = 8'h00 & {8{concat_8315[0]}} | words_seen & {8{concat_8315[1]}};
  assign __phi_halo_cell__req_buf = {{sel_9840[7:0], sel_9840[15:8], sel_9840[23:16], sel_9840[31:24]}, {sel_9839, sel_9838, sel_9837}};
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
      ____state_0 <= p0_stage_done ? nand_8286 : ____state_0;
      ____state_2 <= and_8330 ? one_hot_sel_8323 : ____state_2;
      ____state_1 <= and_8330 ? one_hot_sel_8316 : ____state_1;
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
  wire [127:0] literal_8386 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8398;
  wire not_8399;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_8408;
  wire [2:0] one_hot_8409;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_8448;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8451;
  wire [127:0] payload;
  wire [1:0] concat_8464;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_9854;
  wire or_9858;
  wire [7:0] one_hot_sel_8452;
  wire and_8472;
  wire [127:0] one_hot_sel_8459;
  wire [7:0] one_hot_sel_8465;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_8386;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_8398 = ~(last | ____state_0);
  assign not_8399 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8398};
  assign ____state_6__next_value_predicates = {not_8399, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_8408 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8409 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_8448 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8408[1] & nor_8398 == one_hot_8408[0];
  assign ____state_6__at_most_one_next_value = not_8399 == one_hot_8409[1] & last == one_hot_8409[0];
  assign concat_8451 = {and_8448, nor_8398 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8464 = {not_8399 & p0_stage_done, and_8448};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_9854 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9858 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8452 = frame_header_payload_words__1 & {8{concat_8451[0]}} | 8'h00 & {8{concat_8451[1]}};
  assign and_8472 = (last | nor_8398) & p0_stage_done;
  assign one_hot_sel_8459 = payload & {128{concat_8451[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8451[1]}};
  assign one_hot_sel_8465 = 8'h00 & {8{concat_8464[0]}} | beats_sent & {8{concat_8464[1]}};
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
      ____state_0 <= p0_stage_done ? not_8399 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8465 : ____state_6;
      ____state_1 <= and_8472 ? one_hot_sel_8452 : ____state_1;
      ____state_5 <= and_8472 ? one_hot_sel_8459 : ____state_5;
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
  wire [127:0] literal_8521 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8533;
  wire not_8534;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_8543;
  wire [2:0] one_hot_8544;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_8583;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8586;
  wire [127:0] payload;
  wire [1:0] concat_8599;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_9860;
  wire or_9864;
  wire [7:0] one_hot_sel_8587;
  wire and_8607;
  wire [127:0] one_hot_sel_8594;
  wire [7:0] one_hot_sel_8600;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_8521;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_8533 = ~(last | ____state_0);
  assign not_8534 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8533};
  assign ____state_6__next_value_predicates = {not_8534, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_8543 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8544 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_8583 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8543[1] & nor_8533 == one_hot_8543[0];
  assign ____state_6__at_most_one_next_value = not_8534 == one_hot_8544[1] & last == one_hot_8544[0];
  assign concat_8586 = {and_8583, nor_8533 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8599 = {not_8534 & p0_stage_done, and_8583};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_9860 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9864 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8587 = frame_header_payload_words__1 & {8{concat_8586[0]}} | 8'h00 & {8{concat_8586[1]}};
  assign and_8607 = (last | nor_8533) & p0_stage_done;
  assign one_hot_sel_8594 = payload & {128{concat_8586[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8586[1]}};
  assign one_hot_sel_8600 = 8'h00 & {8{concat_8599[0]}} | beats_sent & {8{concat_8599[1]}};
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
      ____state_0 <= p0_stage_done ? not_8534 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8600 : ____state_6;
      ____state_1 <= and_8607 ? one_hot_sel_8587 : ____state_1;
      ____state_5 <= and_8607 ? one_hot_sel_8594 : ____state_5;
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
  wire [127:0] literal_8656 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8668;
  wire not_8669;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_8678;
  wire [2:0] one_hot_8679;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_8718;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8721;
  wire [127:0] payload;
  wire [1:0] concat_8734;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_9866;
  wire or_9870;
  wire [7:0] one_hot_sel_8722;
  wire and_8742;
  wire [127:0] one_hot_sel_8729;
  wire [7:0] one_hot_sel_8735;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_8656;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_8668 = ~(last | ____state_0);
  assign not_8669 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8668};
  assign ____state_6__next_value_predicates = {not_8669, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_8678 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8679 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_8718 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8678[1] & nor_8668 == one_hot_8678[0];
  assign ____state_6__at_most_one_next_value = not_8669 == one_hot_8679[1] & last == one_hot_8679[0];
  assign concat_8721 = {and_8718, nor_8668 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8734 = {not_8669 & p0_stage_done, and_8718};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_9866 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9870 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8722 = frame_header_payload_words__1 & {8{concat_8721[0]}} | 8'h00 & {8{concat_8721[1]}};
  assign and_8742 = (last | nor_8668) & p0_stage_done;
  assign one_hot_sel_8729 = payload & {128{concat_8721[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8721[1]}};
  assign one_hot_sel_8735 = 8'h00 & {8{concat_8734[0]}} | beats_sent & {8{concat_8734[1]}};
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
      ____state_0 <= p0_stage_done ? not_8669 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8735 : ____state_6;
      ____state_1 <= and_8742 ? one_hot_sel_8722 : ____state_1;
      ____state_5 <= and_8742 ? one_hot_sel_8729 : ____state_5;
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
  wire [127:0] literal_8791 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8803;
  wire not_8804;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_8813;
  wire [2:0] one_hot_8814;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_8853;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8856;
  wire [127:0] payload;
  wire [1:0] concat_8869;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_9872;
  wire or_9876;
  wire [7:0] one_hot_sel_8857;
  wire and_8877;
  wire [127:0] one_hot_sel_8864;
  wire [7:0] one_hot_sel_8870;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_8791;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_8803 = ~(last | ____state_0);
  assign not_8804 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8803};
  assign ____state_6__next_value_predicates = {not_8804, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_8813 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8814 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_8853 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8813[1] & nor_8803 == one_hot_8813[0];
  assign ____state_6__at_most_one_next_value = not_8804 == one_hot_8814[1] & last == one_hot_8814[0];
  assign concat_8856 = {and_8853, nor_8803 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8869 = {not_8804 & p0_stage_done, and_8853};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_9872 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9876 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8857 = frame_header_payload_words__1 & {8{concat_8856[0]}} | 8'h00 & {8{concat_8856[1]}};
  assign and_8877 = (last | nor_8803) & p0_stage_done;
  assign one_hot_sel_8864 = payload & {128{concat_8856[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8856[1]}};
  assign one_hot_sel_8870 = 8'h00 & {8{concat_8869[0]}} | beats_sent & {8{concat_8869[1]}};
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
      ____state_0 <= p0_stage_done ? not_8804 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8870 : ____state_6;
      ____state_1 <= and_8877 ? one_hot_sel_8857 : ____state_1;
      ____state_5 <= and_8877 ? one_hot_sel_8864 : ____state_5;
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
  wire ____state_9_tuple_element_0_init[0:4];
  assign ____state_9_tuple_element_0_init[0] = 1'h0;
  assign ____state_9_tuple_element_0_init[1] = 1'h0;
  assign ____state_9_tuple_element_0_init[2] = 1'h0;
  assign ____state_9_tuple_element_0_init[3] = 1'h0;
  assign ____state_9_tuple_element_0_init[4] = 1'h0;
  wire [95:0] ____state_9_tuple_element_1_tuple_element_1_init[0:4];
  assign ____state_9_tuple_element_1_tuple_element_1_init[0] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_9_tuple_element_1_tuple_element_1_init[1] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_9_tuple_element_1_tuple_element_1_init[2] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_9_tuple_element_1_tuple_element_1_init[3] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_9_tuple_element_1_tuple_element_1_init[4] = 96'h0000_0000_0000_0000_0000_0000;
  wire [7:0] ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[0:4];
  assign ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[0] = 8'h00;
  assign ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[1] = 8'h00;
  assign ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[2] = 8'h00;
  assign ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[3] = 8'h00;
  assign ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[4] = 8'h00;
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_8981 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  reg ____state_12;
  reg ____state_13;
  reg ____state_11;
  reg ____state_9_tuple_element_0[0:4];
  reg [7:0] ____state_10;
  reg [95:0] ____state_9_tuple_element_1_tuple_element_1[0:4];
  reg [7:0] ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0:4];
  reg [31:0] ____state_2;
  reg [31:0] ____state_3;
  reg [1:0] ____state_6;
  reg ____state_0;
  reg [1:0] ____state_7;
  reg [31:0] ____state_5_1;
  reg [31:0] ____state_5_0;
  reg [31:0] ____state_4_1;
  reg [31:0] ____state_4_0;
  reg [31:0] ____state_8;
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
  wire nor_8979;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_9004;
  wire [31:0] concat_9005;
  wire ugt_9007;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_9009;
  wire postponed__4;
  wire ugt_9013;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1;
  wire or_reduce_9017;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_9028;
  wire postponed;
  wire [95:0] sel_9040;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_9046;
  wire [7:0] sel_9047;
  wire [30:0] add_9048;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [31:0] _1;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire [31:0] _2__1;
  wire eq_9058;
  wire eq_9059;
  wire eq_9060;
  wire eq_9061;
  wire _4__1;
  wire nand_9063;
  wire _3;
  wire _19;
  wire _47;
  wire [1:0] and_9080;
  wire eq_9081;
  wire _0__7;
  wire eligible_0;
  wire invalid_input;
  wire and_9086;
  wire _6__1;
  wire [3:0] concat_9088;
  wire postponed_slot_tup0;
  wire compacted_4_tup0;
  wire found;
  wire nand_9096;
  wire priority_sel_9097;
  wire one_hot_sel_9848;
  wire dispatchable;
  wire priority_sel_9105;
  wire [1:0] directive;
  wire next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_9139;
  wire candidate_slots_0_case_cmp;
  wire candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire [7:0] MAILBOX_CAPACITY;
  wire phase_changed;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire and_9127;
  wire nor_9128;
  wire final_slots_0_case_cmp;
  wire and_9132;
  wire and_9134;
  wire and_9135;
  wire and_9137;
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
  wire and_9145;
  wire candidate_occupied_0_case_cmp;
  wire and_9149;
  wire and_9151;
  wire nor_9152;
  wire and_9153;
  wire or_9154;
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
  wire and_9163;
  wire and_9164;
  wire and_9165;
  wire and_9166;
  wire and_9168;
  wire and_9169;
  wire and_9170;
  wire and_9171;
  wire and_9172;
  wire and_9173;
  wire and_9174;
  wire and_9175;
  wire and_9176;
  wire and_9177;
  wire and_9178;
  wire and_9179;
  wire and_9180;
  wire and_9181;
  wire and_9182;
  wire [31:0] Xls_clause_1_Value0_1;
  wire [31:0] _12;
  wire phi_halo_cell__admit_not_pred;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__east_not_pred;
  wire phi_halo_cell__north_load_en;
  wire phi_halo_cell__east_load_en;
  wire phi_halo_cell__west_load_en;
  wire phi_halo_cell__south_load_en;
  wire [1:0] ____state_3__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [1:0] ____state_12__next_value_predicates;
  wire [5:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_7__next_value_predicates;
  wire [4:0] ____state_9_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_9_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [31:0] _8;
  wire [31:0] _35;
  wire [2:0] one_hot_9226;
  wire [2:0] one_hot_9227;
  wire [2:0] one_hot_9228;
  wire [6:0] one_hot_9229;
  wire [2:0] one_hot_9230;
  wire [2:0] one_hot_9231;
  wire [5:0] one_hot_9232;
  wire [8:0] one_hot_9233;
  wire [30:0] add_9190;
  wire [63:0] umul_9191;
  wire [95:0] array_index_9205;
  wire [95:0] array_index_9207;
  wire [95:0] array_index_9209;
  wire [7:0] array_index_9213;
  wire [7:0] array_index_9215;
  wire [7:0] array_index_9217;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_9223;
  wire ne_9243;
  wire or_reduce_9245;
  wire ugt_9247;
  wire [4:0] one_hot_9843;
  wire phi_halo_cell__req_valid_inv;
  wire and_9442;
  wire and_9443;
  wire admission_pending;
  wire [15:0] add_9261;
  wire and_9508;
  wire and_9509;
  wire and_9510;
  wire and_9511;
  wire [31:0] concat_9306;
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
  wire phi_halo_cell__req_valid_load_en;
  wire ____state_3__at_most_one_next_value;
  wire ____state_10__at_most_one_next_value;
  wire ____state_12__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_7__at_most_one_next_value;
  wire ____state_9_tuple_element_0__at_most_one_next_value;
  wire ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_9445;
  wire [31:0] _42;
  wire [1:0] concat_9455;
  wire [1:0] concat_9465;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_9317;
  wire [31:0] sign_ext_9318;
  wire [5:0] concat_9489;
  wire [1:0] concat_9496;
  wire [1:0] unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_9503;
  wire [1:0] unexpand_for_next_value_1302_7__2_case_0_case_1_case_1_case_1_case_0;
  wire [4:0] concat_9513;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_9526;
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
  wire phi_halo_cell__req_load_en;
  wire or_9878;
  wire or_9880;
  wire or_9882;
  wire or_9884;
  wire or_9886;
  wire or_9888;
  wire or_9890;
  wire or_9892;
  wire [31:0] _8__1;
  wire and_9549;
  wire [31:0] one_hot_sel_9446;
  wire and_9552;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire and_9554;
  wire [7:0] one_hot_sel_9456;
  wire and_9557;
  wire and_9353;
  wire and_9559;
  wire one_hot_sel_9466;
  wire and_9562;
  wire or_9351;
  wire [31:0] _31;
  wire and_9565;
  wire [31:0] _37;
  wire [31:0] and_9369;
  wire and_9569;
  wire [31:0] and_9370;
  wire one_hot_sel_9490;
  wire and_9574;
  wire [1:0] one_hot_sel_9497;
  wire and_9577;
  wire [1:0] one_hot_sel_9504;
  wire and_9580;
  wire one_hot_sel_9514[0:4];
  wire and_9583;
  wire [95:0] one_hot_sel_9527[0:4];
  wire and_9586;
  wire [7:0] one_hot_sel_9540[0:4];
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_not_stage_load;
  wire __phi_halo_cell__north_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_has_been_sent_reg_load_en;
  wire __phi_halo_cell__west_has_been_sent_reg_load_en;
  wire __phi_halo_cell__south_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire or_9896;
  assign nor_8979 = ~(____state_13 | ____state_11 | ~____state_12);
  assign received = nor_8979 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_8981;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign tag_ok = frame_header_op == 8'h03 & frame_header__1_payload_words == 8'h03 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_10 + {7'h00, accepted};
  assign and_9004 = ~accepted & ____state_9_tuple_element_0[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign concat_9005 = {24'h00_0000, ____state_10};
  assign ugt_9007 = admitted_occupied > 8'h04;
  assign or_reduce_9009 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_9013 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_9007 | postponed__4);
  assign unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1 = 2'h0;
  assign or_reduce_9017 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_9009 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_9013 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_9017 | postponed__1);
  assign eq_9028 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_9040 = accepted ? phi_halo_cell__req_select[95:0] : ____state_9_tuple_element_1_tuple_element_1[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1}))} & {8{eq_9028 | postponed}};
  assign bit_slice_9046 = selected[2:0];
  assign sel_9047 = accepted ? frame_header_op : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign add_9048 = ____state_2[30:0] + ____state_3[31:1];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_9046 > 3'h4 ? 3'h4 : bit_slice_9046];
  assign _1 = {add_9048, ____state_3[0]};
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_9046 > 3'h4 ? 3'h4 : bit_slice_9046];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _2__1 = _1 + 32'h0000_0001;
  assign eq_9058 = add_9048 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_9059 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign eq_9060 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign eq_9061 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__1;
  assign nand_9063 = ~(eq_9058 & eq_9059);
  assign _3 = eq_9058 & eq_9059;
  assign _19 = ____state_6 == 2'h3;
  assign _47 = ____state_3 == 32'h0000_0001;
  assign and_9080 = (_4__1 ? 2'h1 : 2'h2) & {2{nand_9063}};
  assign eq_9081 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _0__7 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign eligible_0 = ~(eq_9028 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign and_9086 = _3 & _19 & _47;
  assign _6__1 = ____state_7 == 2'h3;
  assign concat_9088 = {~(~eq_9060 | ____state_0), eq_9060 & ____state_0, ~(~eq_9061 | ____state_0), eq_9061 & ____state_0};
  assign postponed_slot_tup0 = 1'h1;
  assign compacted_4_tup0 = 1'h0;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign nand_9096 = ~(eq_9081 & _0__7 & _6__1);
  assign priority_sel_9097 = priority_sel_1b_4way(concat_9088, nand_9063, and_9080[1], ~(eq_9081 & _0__7), ~eq_9081, postponed_slot_tup0);
  assign one_hot_sel_9848 = _3 & concat_9088[0] | and_9080[0] & concat_9088[1] | compacted_4_tup0 & concat_9088[2] | eq_9081 & concat_9088[3];
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_9105 = priority_sel_1b_2way({eq_9060, eq_9061}, ____state_0 | ~____state_0 & and_9086, ____state_0 & nand_9096, ____state_0);
  assign directive = {priority_sel_9097, one_hot_sel_9848} & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? priority_sel_9105 : ____state_0;
  assign repeat_phase = dispatchable & eq_9061 & ~____state_0 & _3 & ~(~_19 | _47);
  assign invalid_repeat = repeat_phase & (directive != unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1 | next_phase_squeezed ^ ____state_0);
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_9139 = admitted_occupied + 8'hff;
  assign candidate_slots_0_case_cmp = ~effective;
  assign candidate_phase_squeezed = effective ? priority_sel_9105 : ____state_0;
  assign failed = invalid_input | invalid_repeat | transition_slots_default_case_cmp;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_9139 : admitted_occupied;
  assign MAILBOX_CAPACITY = 8'h05;
  assign phase_changed = candidate_phase_squeezed ^ ____state_0;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_12 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_12 | ____state_10 > 8'h04);
  assign and_9127 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_9060;
  assign nor_9128 = ~(____state_13 | ____state_11);
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_9132 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_9061;
  assign and_9134 = and_9127 & ____state_0;
  assign and_9135 = nor_9128 & final_slots_0_case_cmp;
  assign and_9137 = nor_9128 & phase_boundary;
  assign __phi_halo_cell__admit_buf = ~____state_13 & ~____state_11 & reserve__1 | ~____state_13 & ____state_11 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign __phi_halo_cell__east_vld_buf = ~(____state_13 | ~____state_11);
  assign __phi_halo_cell__north_not_has_been_sent = ~__phi_halo_cell__north_has_been_sent_reg;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign __phi_halo_cell__east_not_has_been_sent = ~__phi_halo_cell__east_has_been_sent_reg;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign __phi_halo_cell__west_not_has_been_sent = ~__phi_halo_cell__west_has_been_sent_reg;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign __phi_halo_cell__south_not_has_been_sent = ~__phi_halo_cell__south_has_been_sent_reg;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_9145 = and_9132 & ~____state_0;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_9149 = and_9134 & eq_9081 & _0__7;
  assign and_9151 = and_9135 & effective;
  assign nor_9152 = ~(priority_sel_9097 | ~one_hot_sel_9848);
  assign and_9153 = and_9137 & effective;
  assign or_9154 = directive[0] | transition_slots_default_case_cmp;
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
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
  assign and_9163 = and_9145 & _3 & _19;
  assign and_9164 = and_9134 & eq_9081 & _0__7 & _6__1;
  assign and_9165 = nor_9128 & candidate_occupied_0_case_cmp;
  assign and_9166 = nor_9128 & candidate_occupied_1_case_cmp;
  assign and_9168 = and_9132 & ____state_0;
  assign and_9169 = and_9127 & ~____state_0;
  assign and_9170 = and_9145 & and_9086;
  assign and_9171 = and_9145 & ~(_3 & _19 & _47);
  assign and_9172 = and_9134 & nand_9096;
  assign and_9173 = and_9145 & _3 & ~_19;
  assign and_9174 = and_9149 & ~_6__1;
  assign and_9175 = and_9135 & candidate_slots_0_case_cmp;
  assign and_9176 = and_9151 & transition_slots_predicate_piece_0;
  assign and_9177 = and_9151 & nor_9152;
  assign and_9178 = and_9151 & transition_slots_default_case_cmp;
  assign and_9179 = and_9137 & candidate_slots_0_case_cmp;
  assign and_9180 = and_9153 & transition_slots_predicate_piece_0;
  assign and_9181 = and_9153 & nor_9152 & or_9154;
  assign and_9182 = and_9153 & ~(~priority_sel_9097 & one_hot_sel_9848) & or_9154;
  assign Xls_clause_1_Value0_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_9163, and_9164};
  assign ____state_10__next_value_predicates = {and_9165, and_9166};
  assign ____state_12__next_value_predicates = {nor_9128, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_9168, and_9169, and_9170, and_9171, and_9164, and_9172};
  assign ____state_6__next_value_predicates = {and_9173, and_9163};
  assign ____state_7__next_value_predicates = {and_9174, and_9164};
  assign ____state_9_tuple_element_0__next_value_predicates = {and_9137, and_9175, and_9176, and_9177, and_9178};
  assign ____state_9_tuple_element_1_tuple_element_1__next_value_predicates = {and_9175, and_9176, and_9177, and_9178, and_9179, and_9180, and_9181, and_9182};
  assign _8 = ____state_5_0 + Xls_clause_1_Value0_1;
  assign _35 = ____state_4_0 + _12;
  assign one_hot_9226 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_9227 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_9228 = {____state_12__next_value_predicates[1:0] == 2'h0, ____state_12__next_value_predicates[1] && !____state_12__next_value_predicates[0], ____state_12__next_value_predicates[0]};
  assign one_hot_9229 = {____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_9230 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_9231 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_9232 = {____state_9_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_9_tuple_element_0__next_value_predicates[4] && ____state_9_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_9_tuple_element_0__next_value_predicates[3] && ____state_9_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_9_tuple_element_0__next_value_predicates[2] && ____state_9_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_9_tuple_element_0__next_value_predicates[1] && !____state_9_tuple_element_0__next_value_predicates[0], ____state_9_tuple_element_0__next_value_predicates[0]};
  assign one_hot_9233 = {____state_9_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_9_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign add_9190 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_9191 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_9205 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_9207 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_9209 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_9213 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_9215 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_9217 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_9223 = ____state_4_1[30:0] + _8[31:1];
  assign ne_9243 = bit_slice_9046 != 3'h0;
  assign or_reduce_9245 = |selected[7:1];
  assign ugt_9247 = bit_slice_9046 > 3'h2;
  assign one_hot_9843 = {concat_9088[3:0] == 4'h0, concat_9088[3] && concat_9088[2:0] == 3'h0, concat_9088[2] && concat_9088[1:0] == 2'h0, concat_9088[1] && !concat_9088[0], concat_9088[0]};
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_9442 = and_9163 & p0_all_active_outputs_ready;
  assign and_9443 = and_9164 & p0_all_active_outputs_ready;
  assign admission_pending = ~(~____state_12 | received);
  assign add_9261 = ____state_8[15:0] + {unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1, ____state_4_0[31:18]};
  assign and_9508 = and_9175 & p0_all_active_outputs_ready;
  assign and_9509 = and_9176 & p0_all_active_outputs_ready;
  assign and_9510 = and_9177 & p0_all_active_outputs_ready;
  assign and_9511 = and_9178 & p0_all_active_outputs_ready;
  assign concat_9306 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_9243 ? postponed : or_reduce_9017 & postponed__1;
  assign compacted_1_tup0 = or_reduce_9245 ? postponed__1 : ugt_9013 & postponed__2;
  assign compacted_2_tup0 = ugt_9247 ? postponed__2 : or_reduce_9009 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_9007 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_9243 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_9205 & {96{or_reduce_9017}};
  assign compacted_1_tup1_tup1 = or_reduce_9245 ? array_index_9205 : array_index_9207 & {96{ugt_9013}};
  assign compacted_2_tup1_tup1 = ugt_9247 ? array_index_9207 : array_index_9209 & {96{or_reduce_9009}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_9209 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_9007}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_9243 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_9213 & {8{or_reduce_9017}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_9245 ? array_index_9213 : array_index_9215 & {8{ugt_9013}};
  assign compacted_2_tup1_tup0_tup3 = ugt_9247 ? array_index_9215 : array_index_9217 & {8{or_reduce_9009}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_9217 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_9007}};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_8979 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_9163 == one_hot_9226[1] & and_9164 == one_hot_9226[0];
  assign ____state_10__at_most_one_next_value = and_9165 == one_hot_9227[1] & and_9166 == one_hot_9227[0];
  assign ____state_12__at_most_one_next_value = nor_9128 == one_hot_9228[1] & __phi_halo_cell__east_vld_buf == one_hot_9228[0];
  assign ____state_0__at_most_one_next_value = and_9168 == one_hot_9229[5] & and_9169 == one_hot_9229[4] & and_9170 == one_hot_9229[3] & and_9171 == one_hot_9229[2] & and_9164 == one_hot_9229[1] & and_9172 == one_hot_9229[0];
  assign ____state_6__at_most_one_next_value = and_9173 == one_hot_9230[1] & and_9163 == one_hot_9230[0];
  assign ____state_7__at_most_one_next_value = and_9174 == one_hot_9231[1] & and_9164 == one_hot_9231[0];
  assign ____state_9_tuple_element_0__at_most_one_next_value = and_9137 == one_hot_9232[4] & and_9175 == one_hot_9232[3] & and_9176 == one_hot_9232[2] & and_9177 == one_hot_9232[1] & and_9178 == one_hot_9232[0];
  assign ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value = and_9175 == one_hot_9233[7] & and_9176 == one_hot_9233[6] & and_9177 == one_hot_9233[5] & and_9178 == one_hot_9233[4] & and_9179 == one_hot_9233[3] & and_9180 == one_hot_9233[2] & and_9181 == one_hot_9233[1] & and_9182 == one_hot_9233[0];
  assign concat_9445 = {and_9442, and_9443};
  assign _42 = ____state_3 + 32'h0000_0001;
  assign concat_9455 = {and_9165 & p0_all_active_outputs_ready, and_9166 & p0_all_active_outputs_ready};
  assign concat_9465 = {nor_9128 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _27 = {add_9261, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_9223[30:2]};
  assign add_9317 = {compacted_4_tup0, add_9190[30:1]} + {3'h0, umul_9191[63:36]};
  assign sign_ext_9318 = {32{~_19}};
  assign concat_9489 = {and_9168 & p0_all_active_outputs_ready, and_9169 & p0_all_active_outputs_ready, and_9170 & p0_all_active_outputs_ready, and_9171 & p0_all_active_outputs_ready, and_9443, and_9172 & p0_all_active_outputs_ready};
  assign concat_9496 = {and_9173 & p0_all_active_outputs_ready, and_9442};
  assign unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_0 = ____state_6 + 2'h1;
  assign concat_9503 = {and_9174 & p0_all_active_outputs_ready, and_9443};
  assign unexpand_for_next_value_1302_7__2_case_0_case_1_case_1_case_1_case_0 = ____state_7 + 2'h1;
  assign concat_9513 = {and_9137 & p0_all_active_outputs_ready, and_9508, and_9509, and_9510, and_9511};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_9526 = {and_9508, and_9509, and_9510, and_9511, and_9179 & p0_all_active_outputs_ready, and_9180 & p0_all_active_outputs_ready, and_9181 & p0_all_active_outputs_ready, and_9182 & p0_all_active_outputs_ready};
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
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_9878 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_9880 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_9882 = ~p0_all_active_outputs_ready | ____state_12__at_most_one_next_value | reset;
  assign or_9884 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_9886 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_9888 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_9890 = ~p0_all_active_outputs_ready | ____state_9_tuple_element_0__at_most_one_next_value | reset;
  assign or_9892 = ~p0_all_active_outputs_ready | ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign _8__1 = ____state_2 + 32'h0000_0001;
  assign and_9549 = and_9164 & p0_all_active_outputs_ready;
  assign one_hot_sel_9446 = 32'h0000_0000 & {32{concat_9445[0]}} | _42 & {32{concat_9445[1]}};
  assign and_9552 = (and_9163 | and_9164) & p0_all_active_outputs_ready;
  assign Xls_clause_1_NextAnyon_1 = ____state_8 ^ Xls_clause_1_Value1_1;
  assign and_9554 = and_9149 & p0_all_active_outputs_ready;
  assign one_hot_sel_9456 = add_9139 & {8{concat_9455[0]}} | admitted_occupied & {8{concat_9455[1]}};
  assign and_9557 = (and_9165 | and_9166) & p0_all_active_outputs_ready;
  assign and_9353 = ~____state_11 & effective & phase_boundary & ~failed;
  assign and_9559 = ~____state_13 & p0_all_active_outputs_ready;
  assign one_hot_sel_9466 = (____state_12 | ____state_10 < MAILBOX_CAPACITY) & concat_9465[0] | (admission_pending | reserve__1) & concat_9465[1];
  assign and_9562 = (nor_9128 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_9351 = ____state_13 | (____state_11 ? ____state_13 : failed);
  assign _31 = _27 + _30;
  assign and_9565 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_9061 & ~____state_0 & eq_9058 & eq_9059 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_9317};
  assign and_9369 = _8 & sign_ext_9318;
  assign and_9569 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_9061 & ~____state_0 & _3 & p0_all_active_outputs_ready;
  assign and_9370 = _12 & sign_ext_9318;
  assign one_hot_sel_9490 = postponed_slot_tup0 & concat_9489[0] | compacted_4_tup0 & concat_9489[1] | compacted_4_tup0 & concat_9489[2] | postponed_slot_tup0 & concat_9489[3] | compacted_4_tup0 & concat_9489[4] | postponed_slot_tup0 & concat_9489[5];
  assign and_9574 = (and_9168 | and_9169 | and_9170 | and_9171 | and_9164 | and_9172) & p0_all_active_outputs_ready;
  assign one_hot_sel_9497 = unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9496[0]}} | unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_9496[1]}};
  assign and_9577 = (and_9173 | and_9163) & p0_all_active_outputs_ready;
  assign one_hot_sel_9504 = unexpand_for_next_value_1302_6__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9503[0]}} | unexpand_for_next_value_1302_7__2_case_0_case_1_case_1_case_1_case_0 & {2{concat_9503[1]}};
  assign and_9580 = (and_9174 | and_9164) & p0_all_active_outputs_ready;
  assign one_hot_sel_9514[0] = admitted_slots_tuple_idx_0[0] & concat_9513[0] | postponed_slots_tuple_idx_0[0] & concat_9513[1] | compacted_slots_tuple_idx_0[0] & concat_9513[2] | admitted_slots_tuple_idx_0[0] & concat_9513[3] | unblocked_slots_tuple_idx_0[0] & concat_9513[4];
  assign one_hot_sel_9514[1] = admitted_slots_tuple_idx_0[1] & concat_9513[0] | postponed_slots_tuple_idx_0[1] & concat_9513[1] | compacted_slots_tuple_idx_0[1] & concat_9513[2] | admitted_slots_tuple_idx_0[1] & concat_9513[3] | unblocked_slots_tuple_idx_0[1] & concat_9513[4];
  assign one_hot_sel_9514[2] = admitted_slots_tuple_idx_0[2] & concat_9513[0] | postponed_slots_tuple_idx_0[2] & concat_9513[1] | compacted_slots_tuple_idx_0[2] & concat_9513[2] | admitted_slots_tuple_idx_0[2] & concat_9513[3] | unblocked_slots_tuple_idx_0[2] & concat_9513[4];
  assign one_hot_sel_9514[3] = admitted_slots_tuple_idx_0[3] & concat_9513[0] | postponed_slots_tuple_idx_0[3] & concat_9513[1] | compacted_slots_tuple_idx_0[3] & concat_9513[2] | admitted_slots_tuple_idx_0[3] & concat_9513[3] | unblocked_slots_tuple_idx_0[3] & concat_9513[4];
  assign one_hot_sel_9514[4] = admitted_slots_tuple_idx_0[4] & concat_9513[0] | postponed_slots_tuple_idx_0[4] & concat_9513[1] | compacted_slots_tuple_idx_0[4] & concat_9513[2] | admitted_slots_tuple_idx_0[4] & concat_9513[3] | unblocked_slots_tuple_idx_0[4] & concat_9513[4];
  assign and_9583 = (and_9137 | and_9175 | and_9176 | and_9177 | and_9178) & p0_all_active_outputs_ready;
  assign one_hot_sel_9527[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9526[7]}};
  assign one_hot_sel_9527[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9526[7]}};
  assign one_hot_sel_9527[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9526[7]}};
  assign one_hot_sel_9527[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9526[7]}};
  assign one_hot_sel_9527[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9526[7]}};
  assign and_9586 = (and_9175 | and_9176 | and_9177 | and_9178 | and_9179 | and_9180 | and_9181 | and_9182) & p0_all_active_outputs_ready;
  assign one_hot_sel_9540[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9526[7]}};
  assign one_hot_sel_9540[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9526[7]}};
  assign one_hot_sel_9540[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9526[7]}};
  assign one_hot_sel_9540[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9526[7]}};
  assign one_hot_sel_9540[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9526[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {{{7'h01, ~____state_0}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, ____state_0 ? 3'h4 : 3'h3}}, ____state_0 ? {64'h0000_0000_0000_0000, ____state_2} : {____state_4_0, ____state_4_1, add_9048, ____state_3[0]}};
  assign or_9896 = ~p0_all_active_outputs_ready | concat_9088 == one_hot_9843[3:0] | reset;
  always @ (posedge clk) begin
    if (reset) begin
      ____state_12 <= 1'h0;
      ____state_13 <= 1'h0;
      ____state_11 <= 1'h1;
      ____state_9_tuple_element_0[0] <= ____state_9_tuple_element_0_init[0];
      ____state_9_tuple_element_0[1] <= ____state_9_tuple_element_0_init[1];
      ____state_9_tuple_element_0[2] <= ____state_9_tuple_element_0_init[2];
      ____state_9_tuple_element_0[3] <= ____state_9_tuple_element_0_init[3];
      ____state_9_tuple_element_0[4] <= ____state_9_tuple_element_0_init[4];
      ____state_10 <= 8'h00;
      ____state_9_tuple_element_1_tuple_element_1[0] <= ____state_9_tuple_element_1_tuple_element_1_init[0];
      ____state_9_tuple_element_1_tuple_element_1[1] <= ____state_9_tuple_element_1_tuple_element_1_init[1];
      ____state_9_tuple_element_1_tuple_element_1[2] <= ____state_9_tuple_element_1_tuple_element_1_init[2];
      ____state_9_tuple_element_1_tuple_element_1[3] <= ____state_9_tuple_element_1_tuple_element_1_init[3];
      ____state_9_tuple_element_1_tuple_element_1[4] <= ____state_9_tuple_element_1_tuple_element_1_init[4];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0] <= ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[0];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[1] <= ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[1];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[2] <= ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[2];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[3] <= ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[3];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[4] <= ____state_9_tuple_element_1_tuple_element_0_tuple_element_3_init[4];
      ____state_2 <= 32'h0000_0000;
      ____state_3 <= 32'h0000_0000;
      ____state_6 <= 2'h0;
      ____state_0 <= 1'h0;
      ____state_7 <= 2'h0;
      ____state_5_1 <= 32'h0000_0000;
      ____state_5_0 <= 32'h0000_0000;
      ____state_4_1 <= 32'h0000_0000;
      ____state_4_0 <= 32'h0000_0000;
      ____state_8 <= 32'h0000_0000;
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
      ____state_12 <= and_9562 ? one_hot_sel_9466 : ____state_12;
      ____state_13 <= p0_all_active_outputs_ready ? or_9351 : ____state_13;
      ____state_11 <= and_9559 ? and_9353 : ____state_11;
      ____state_9_tuple_element_0[0] <= and_9583 ? one_hot_sel_9514[0] : ____state_9_tuple_element_0[0];
      ____state_9_tuple_element_0[1] <= and_9583 ? one_hot_sel_9514[1] : ____state_9_tuple_element_0[1];
      ____state_9_tuple_element_0[2] <= and_9583 ? one_hot_sel_9514[2] : ____state_9_tuple_element_0[2];
      ____state_9_tuple_element_0[3] <= and_9583 ? one_hot_sel_9514[3] : ____state_9_tuple_element_0[3];
      ____state_9_tuple_element_0[4] <= and_9583 ? one_hot_sel_9514[4] : ____state_9_tuple_element_0[4];
      ____state_10 <= and_9557 ? one_hot_sel_9456 : ____state_10;
      ____state_9_tuple_element_1_tuple_element_1[0] <= and_9586 ? one_hot_sel_9527[0] : ____state_9_tuple_element_1_tuple_element_1[0];
      ____state_9_tuple_element_1_tuple_element_1[1] <= and_9586 ? one_hot_sel_9527[1] : ____state_9_tuple_element_1_tuple_element_1[1];
      ____state_9_tuple_element_1_tuple_element_1[2] <= and_9586 ? one_hot_sel_9527[2] : ____state_9_tuple_element_1_tuple_element_1[2];
      ____state_9_tuple_element_1_tuple_element_1[3] <= and_9586 ? one_hot_sel_9527[3] : ____state_9_tuple_element_1_tuple_element_1[3];
      ____state_9_tuple_element_1_tuple_element_1[4] <= and_9586 ? one_hot_sel_9527[4] : ____state_9_tuple_element_1_tuple_element_1[4];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_9586 ? one_hot_sel_9540[0] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_9586 ? one_hot_sel_9540[1] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_9586 ? one_hot_sel_9540[2] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_9586 ? one_hot_sel_9540[3] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_9586 ? one_hot_sel_9540[4] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_2 <= and_9549 ? _8__1 : ____state_2;
      ____state_3 <= and_9552 ? one_hot_sel_9446 : ____state_3;
      ____state_6 <= and_9577 ? one_hot_sel_9497 : ____state_6;
      ____state_0 <= and_9574 ? one_hot_sel_9490 : ____state_0;
      ____state_7 <= and_9580 ? one_hot_sel_9504 : ____state_7;
      ____state_5_1 <= and_9569 ? and_9370 : ____state_5_1;
      ____state_5_0 <= and_9569 ? and_9369 : ____state_5_0;
      ____state_4_1 <= and_9565 ? _37 : ____state_4_1;
      ____state_4_0 <= and_9565 ? _31 : ____state_4_0;
      ____state_8 <= and_9554 ? Xls_clause_1_NextAnyon_1 : ____state_8;
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
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_9005 == __i0 ? and_9004 : ____state_9_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_9005 == __i0 ? sel_9040 : ____state_9_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_9005 == __i0 ? sel_9047 : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_9306 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_9306 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_9306 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_9957;
  wire eq_9962;
  wire ne_9946;
  wire and_9963;
  wire or_9960;
  wire [2:0] add_9954;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9949;
  wire popped;
  wire [1:0] sub_9975;
  wire [1:0] add_9977;
  wire [2:0] umod_9955;
  wire [2:0] umod_9950;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9979;
  wire array_update_9986[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9957 = pop_ready & push_valid;
  assign eq_9962 = head == tail;
  assign ne_9946 = head != tail;
  assign and_9963 = eq_9962 & and_9957;
  assign or_9960 = ne_9946 | push_valid;
  assign add_9954 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9949 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9960;
  assign sub_9975 = slots - 2'h1;
  assign add_9977 = slots + 2'h1;
  assign umod_9955 = add_9954 % long_buf_size_lit;
  assign umod_9950 = add_9949 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9955[1:0];
  assign did_push_occur = (can_do_push | and_9957) & push_valid & ~and_9963 & ~is_full_bool;
  assign next_tail_if_pop = umod_9950[1:0];
  assign did_pop_occur = (ne_9946 | and_9957) & pop_ready & ~and_9963;
  assign sel_9979 = pushed ? (popped ? slots : add_9977) : (popped ? sub_9975 : slots);
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
      slots <= sel_9979;
      buf__1[0] <= did_push_occur ? array_update_9986[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9986[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9960;
  assign pop_data = eq_9962 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9986_0
    assign array_update_9986[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_10014;
  wire eq_10019;
  wire ne_10003;
  wire and_10020;
  wire or_10017;
  wire [2:0] add_10011;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_10006;
  wire popped;
  wire [1:0] sub_10032;
  wire [1:0] add_10034;
  wire [2:0] umod_10012;
  wire [2:0] umod_10007;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_10036;
  wire [127:0] array_update_10043[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_10014 = pop_ready & push_valid;
  assign eq_10019 = head == tail;
  assign ne_10003 = head != tail;
  assign and_10020 = eq_10019 & and_10014;
  assign or_10017 = ne_10003 | push_valid;
  assign add_10011 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_10006 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_10017;
  assign sub_10032 = slots - 2'h1;
  assign add_10034 = slots + 2'h1;
  assign umod_10012 = add_10011 % long_buf_size_lit;
  assign umod_10007 = add_10006 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_10012[1:0];
  assign did_push_occur = (can_do_push | and_10014) & push_valid & ~and_10020 & ~is_full_bool;
  assign next_tail_if_pop = umod_10007[1:0];
  assign did_pop_occur = (ne_10003 | and_10014) & pop_ready & ~and_10020;
  assign sel_10036 = pushed ? (popped ? slots : add_10034) : (popped ? sub_10032 : slots);
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
      slots <= sel_10036;
      buf__1[0] <= did_push_occur ? array_update_10043[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10043[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_10017;
  assign pop_data = eq_10019 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10043_0
    assign array_update_10043[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_10071;
  wire eq_10076;
  wire ne_10060;
  wire and_10077;
  wire or_10074;
  wire [2:0] add_10068;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_10063;
  wire popped;
  wire [1:0] sub_10089;
  wire [1:0] add_10091;
  wire [2:0] umod_10069;
  wire [2:0] umod_10064;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_10093;
  wire [127:0] array_update_10100[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_10071 = pop_ready & push_valid;
  assign eq_10076 = head == tail;
  assign ne_10060 = head != tail;
  assign and_10077 = eq_10076 & and_10071;
  assign or_10074 = ne_10060 | push_valid;
  assign add_10068 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_10063 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_10074;
  assign sub_10089 = slots - 2'h1;
  assign add_10091 = slots + 2'h1;
  assign umod_10069 = add_10068 % long_buf_size_lit;
  assign umod_10064 = add_10063 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_10069[1:0];
  assign did_push_occur = (can_do_push | and_10071) & push_valid & ~and_10077 & ~is_full_bool;
  assign next_tail_if_pop = umod_10064[1:0];
  assign did_pop_occur = (ne_10060 | and_10071) & pop_ready & ~and_10077;
  assign sel_10093 = pushed ? (popped ? slots : add_10091) : (popped ? sub_10089 : slots);
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
      slots <= sel_10093;
      buf__1[0] <= did_push_occur ? array_update_10100[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10100[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_10074;
  assign pop_data = eq_10076 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10100_0
    assign array_update_10100[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_10128;
  wire eq_10133;
  wire ne_10117;
  wire and_10134;
  wire or_10131;
  wire [2:0] add_10125;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_10120;
  wire popped;
  wire [1:0] sub_10146;
  wire [1:0] add_10148;
  wire [2:0] umod_10126;
  wire [2:0] umod_10121;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_10150;
  wire [127:0] array_update_10157[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_10128 = pop_ready & push_valid;
  assign eq_10133 = head == tail;
  assign ne_10117 = head != tail;
  assign and_10134 = eq_10133 & and_10128;
  assign or_10131 = ne_10117 | push_valid;
  assign add_10125 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_10120 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_10131;
  assign sub_10146 = slots - 2'h1;
  assign add_10148 = slots + 2'h1;
  assign umod_10126 = add_10125 % long_buf_size_lit;
  assign umod_10121 = add_10120 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_10126[1:0];
  assign did_push_occur = (can_do_push | and_10128) & push_valid & ~and_10134 & ~is_full_bool;
  assign next_tail_if_pop = umod_10121[1:0];
  assign did_pop_occur = (ne_10117 | and_10128) & pop_ready & ~and_10134;
  assign sel_10150 = pushed ? (popped ? slots : add_10148) : (popped ? sub_10146 : slots);
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
      slots <= sel_10150;
      buf__1[0] <= did_push_occur ? array_update_10157[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10157[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_10131;
  assign pop_data = eq_10133 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10157_0
    assign array_update_10157[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_10185;
  wire eq_10190;
  wire ne_10174;
  wire and_10191;
  wire or_10188;
  wire [2:0] add_10182;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_10177;
  wire popped;
  wire [1:0] sub_10203;
  wire [1:0] add_10205;
  wire [2:0] umod_10183;
  wire [2:0] umod_10178;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_10207;
  wire [127:0] array_update_10214[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_10185 = pop_ready & push_valid;
  assign eq_10190 = head == tail;
  assign ne_10174 = head != tail;
  assign and_10191 = eq_10190 & and_10185;
  assign or_10188 = ne_10174 | push_valid;
  assign add_10182 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_10177 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_10188;
  assign sub_10203 = slots - 2'h1;
  assign add_10205 = slots + 2'h1;
  assign umod_10183 = add_10182 % long_buf_size_lit;
  assign umod_10178 = add_10177 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_10183[1:0];
  assign did_push_occur = (can_do_push | and_10185) & push_valid & ~and_10191 & ~is_full_bool;
  assign next_tail_if_pop = umod_10178[1:0];
  assign did_pop_occur = (ne_10174 | and_10185) & pop_ready & ~and_10191;
  assign sel_10207 = pushed ? (popped ? slots : add_10205) : (popped ? sub_10203 : slots);
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
      slots <= sel_10207;
      buf__1[0] <= did_push_occur ? array_update_10214[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10214[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_10188;
  assign pop_data = eq_10190 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10214_0
    assign array_update_10214[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_10242;
  wire eq_10247;
  wire ne_10231;
  wire and_10248;
  wire or_10245;
  wire [2:0] add_10239;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_10234;
  wire popped;
  wire [1:0] sub_10260;
  wire [1:0] add_10262;
  wire [2:0] umod_10240;
  wire [2:0] umod_10235;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_10264;
  wire [127:0] array_update_10271[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_10242 = pop_ready & push_valid;
  assign eq_10247 = head == tail;
  assign ne_10231 = head != tail;
  assign and_10248 = eq_10247 & and_10242;
  assign or_10245 = ne_10231 | push_valid;
  assign add_10239 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_10234 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_10245;
  assign sub_10260 = slots - 2'h1;
  assign add_10262 = slots + 2'h1;
  assign umod_10240 = add_10239 % long_buf_size_lit;
  assign umod_10235 = add_10234 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_10240[1:0];
  assign did_push_occur = (can_do_push | and_10242) & push_valid & ~and_10248 & ~is_full_bool;
  assign next_tail_if_pop = umod_10235[1:0];
  assign did_pop_occur = (ne_10231 | and_10242) & pop_ready & ~and_10248;
  assign sel_10264 = pushed ? (popped ? slots : add_10262) : (popped ? sub_10260 : slots);
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
      slots <= sel_10264;
      buf__1[0] <= did_push_occur ? array_update_10271[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10271[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_10245;
  assign pop_data = eq_10247 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10271_0
    assign array_update_10271[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_9738;
  wire instantiation_output_9763;
  wire [127:0] instantiation_output_9787;
  wire instantiation_output_9788;
  wire instantiation_output_9776;
  wire [32:0] instantiation_output_9780;
  wire instantiation_output_9781;
  wire instantiation_output_9751;
  wire [32:0] instantiation_output_9755;
  wire instantiation_output_9756;
  wire instantiation_output_9827;
  wire [32:0] instantiation_output_9831;
  wire instantiation_output_9832;
  wire instantiation_output_9808;
  wire [32:0] instantiation_output_9812;
  wire instantiation_output_9813;
  wire instantiation_output_9730;
  wire instantiation_output_9731;
  wire [127:0] instantiation_output_9743;
  wire instantiation_output_9744;
  wire [127:0] instantiation_output_9768;
  wire instantiation_output_9769;
  wire instantiation_output_9795;
  wire [127:0] instantiation_output_9800;
  wire instantiation_output_9801;
  wire [127:0] instantiation_output_9819;
  wire instantiation_output_9820;
  wire instantiation_output_10279;
  wire instantiation_output_10280;
  wire instantiation_output_10281;
  wire instantiation_output_10286;
  wire [127:0] instantiation_output_10287;
  wire instantiation_output_10288;
  wire instantiation_output_10293;
  wire [127:0] instantiation_output_10294;
  wire instantiation_output_10295;
  wire instantiation_output_10300;
  wire [127:0] instantiation_output_10301;
  wire instantiation_output_10302;
  wire instantiation_output_10307;
  wire [127:0] instantiation_output_10308;
  wire instantiation_output_10309;
  wire instantiation_output_10314;
  wire [127:0] instantiation_output_10315;
  wire instantiation_output_10316;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_10280),
    .phi_halo_cell__admit_vld(instantiation_output_10281),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_10300),
    .phi_halo_cell__admit_rdy(instantiation_output_9738),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_9763),
    .phi_halo_cell__req(instantiation_output_9787),
    .phi_halo_cell__req_vld(instantiation_output_9788),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_10294),
    .phi_halo_cell__north_vld(instantiation_output_10295),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_9776),
    .phi_halo_cell__north_send(instantiation_output_9780),
    .phi_halo_cell__north_send_vld(instantiation_output_9781),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_10287),
    .phi_halo_cell__east_vld(instantiation_output_10288),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_9751),
    .phi_halo_cell__east_send(instantiation_output_9755),
    .phi_halo_cell__east_send_vld(instantiation_output_9756),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_10315),
    .phi_halo_cell__west_vld(instantiation_output_10316),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_9827),
    .phi_halo_cell__west_send(instantiation_output_9831),
    .phi_halo_cell__west_send_vld(instantiation_output_9832),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_10308),
    .phi_halo_cell__south_vld(instantiation_output_10309),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_9808),
    .phi_halo_cell__south_send(instantiation_output_9812),
    .phi_halo_cell__south_send_vld(instantiation_output_9813),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_10279),
    .phi_halo_cell__east_rdy(instantiation_output_10286),
    .phi_halo_cell__north_rdy(instantiation_output_10293),
    .phi_halo_cell__req(instantiation_output_10301),
    .phi_halo_cell__req_vld(instantiation_output_10302),
    .phi_halo_cell__south_rdy(instantiation_output_10307),
    .phi_halo_cell__west_rdy(instantiation_output_10314),
    .phi_halo_cell__admit(instantiation_output_9730),
    .phi_halo_cell__admit_vld(instantiation_output_9731),
    .phi_halo_cell__east(instantiation_output_9743),
    .phi_halo_cell__east_vld(instantiation_output_9744),
    .phi_halo_cell__north(instantiation_output_9768),
    .phi_halo_cell__north_vld(instantiation_output_9769),
    .phi_halo_cell__req_rdy(instantiation_output_9795),
    .phi_halo_cell__south(instantiation_output_9800),
    .phi_halo_cell__south_vld(instantiation_output_9801),
    .phi_halo_cell__west(instantiation_output_9819),
    .phi_halo_cell__west_vld(instantiation_output_9820),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_9730),
    .push_valid(instantiation_output_9731),
    .pop_ready(instantiation_output_9738),
    .push_ready(instantiation_output_10279),
    .pop_data(instantiation_output_10280),
    .pop_valid(instantiation_output_10281),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_9743),
    .push_valid(instantiation_output_9744),
    .pop_ready(instantiation_output_9751),
    .push_ready(instantiation_output_10286),
    .pop_data(instantiation_output_10287),
    .pop_valid(instantiation_output_10288),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_9768),
    .push_valid(instantiation_output_9769),
    .pop_ready(instantiation_output_9776),
    .push_ready(instantiation_output_10293),
    .pop_data(instantiation_output_10294),
    .pop_valid(instantiation_output_10295),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_9787),
    .push_valid(instantiation_output_9788),
    .pop_ready(instantiation_output_9795),
    .push_ready(instantiation_output_10300),
    .pop_data(instantiation_output_10301),
    .pop_valid(instantiation_output_10302),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_9800),
    .push_valid(instantiation_output_9801),
    .pop_ready(instantiation_output_9808),
    .push_ready(instantiation_output_10307),
    .pop_data(instantiation_output_10308),
    .pop_valid(instantiation_output_10309),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_9819),
    .push_valid(instantiation_output_9820),
    .pop_ready(instantiation_output_9827),
    .push_ready(instantiation_output_10314),
    .pop_data(instantiation_output_10315),
    .pop_valid(instantiation_output_10316),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_9755;
  assign phi_halo_cell__east_send_vld = instantiation_output_9756;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_9763;
  assign phi_halo_cell__north_send = instantiation_output_9780;
  assign phi_halo_cell__north_send_vld = instantiation_output_9781;
  assign phi_halo_cell__south_send = instantiation_output_9812;
  assign phi_halo_cell__south_send_vld = instantiation_output_9813;
  assign phi_halo_cell__west_send = instantiation_output_9831;
  assign phi_halo_cell__west_send_vld = instantiation_output_9832;
endmodule
