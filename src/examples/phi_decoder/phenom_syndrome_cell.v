module __axis__Top__ReservedRx_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_syndrome_cell__admit,
  input wire phenom_syndrome_cell__admit_vld,
  input wire [32:0] phenom_syndrome_cell__ext_recv,
  input wire phenom_syndrome_cell__ext_recv_vld,
  input wire phenom_syndrome_cell__req_rdy,
  output wire phenom_syndrome_cell__admit_rdy,
  output wire phenom_syndrome_cell__ext_recv_rdy,
  output wire [127:0] phenom_syndrome_cell__req,
  output wire phenom_syndrome_cell__req_vld
);
  wire [32:0] __phenom_syndrome_cell__ext_recv_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] __phenom_syndrome_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] literal_10370 = {1'h0, 32'h0000_0000};
  reg ____state_0;
  reg [7:0] ____state_2;
  reg [127:0] ____state_1;
  reg [32:0] __phenom_syndrome_cell__ext_recv_reg;
  reg __phenom_syndrome_cell__ext_recv_valid_reg;
  reg __phenom_syndrome_cell__admit_reg;
  reg __phenom_syndrome_cell__admit_valid_reg;
  reg [127:0] __phenom_syndrome_cell__req_reg;
  reg __phenom_syndrome_cell__req_valid_reg;
  wire [32:0] phenom_syndrome_cell__ext_recv_select;
  wire beat_tlast;
  wire p0_all_active_inputs_valid;
  wire and_10380;
  wire phenom_syndrome_cell__req_valid_inv;
  wire __phenom_syndrome_cell__req_vld_buf;
  wire phenom_syndrome_cell__req_valid_load_en;
  wire nor_10379;
  wire phenom_syndrome_cell__req_not_pred;
  wire phenom_syndrome_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_10392;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_12239;
  wire phenom_syndrome_cell__admit_valid_inv;
  wire phenom_syndrome_cell__ext_recv_valid_inv;
  wire [31:0] sel_12238;
  wire [31:0] sel_12237;
  wire [31:0] sel_12236;
  wire phenom_syndrome_cell__admit_valid_load_en;
  wire phenom_syndrome_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_10437;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phenom_syndrome_cell__admit_load_en;
  wire phenom_syndrome_cell__ext_recv_load_en;
  wire or_12248;
  wire nand_10408;
  wire [127:0] one_hot_sel_10438;
  wire and_10452;
  wire [7:0] one_hot_sel_10445;
  wire [127:0] __phenom_syndrome_cell__req_buf;
  assign phenom_syndrome_cell__ext_recv_select = ____state_0 ? __phenom_syndrome_cell__ext_recv_reg : literal_10370;
  assign beat_tlast = phenom_syndrome_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phenom_syndrome_cell__ext_recv_valid_reg) & (____state_0 | __phenom_syndrome_cell__admit_valid_reg);
  assign and_10380 = ____state_0 & beat_tlast;
  assign phenom_syndrome_cell__req_valid_inv = ~__phenom_syndrome_cell__req_valid_reg;
  assign __phenom_syndrome_cell__req_vld_buf = p0_all_active_inputs_valid & and_10380;
  assign phenom_syndrome_cell__req_valid_load_en = phenom_syndrome_cell__req_rdy | phenom_syndrome_cell__req_valid_inv;
  assign nor_10379 = ~(~____state_0 | beat_tlast);
  assign phenom_syndrome_cell__req_not_pred = ~and_10380;
  assign phenom_syndrome_cell__req_load_en = __phenom_syndrome_cell__req_vld_buf & phenom_syndrome_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_10379, and_10380};
  assign one_hot_10392 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phenom_syndrome_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phenom_syndrome_cell__req_not_pred | phenom_syndrome_cell__req_load_en);
  assign sel_12239 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phenom_syndrome_cell__admit_valid_inv = ~__phenom_syndrome_cell__admit_valid_reg;
  assign phenom_syndrome_cell__ext_recv_valid_inv = ~__phenom_syndrome_cell__ext_recv_valid_reg;
  assign sel_12238 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_12237 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_12236 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phenom_syndrome_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phenom_syndrome_cell__admit_valid_inv;
  assign phenom_syndrome_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phenom_syndrome_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_10379 == one_hot_10392[1] & and_10380 == one_hot_10392[0];
  assign concat_10437 = {nor_10379 & p0_stage_done, and_10380 & p0_stage_done};
  assign payload = {sel_12238, sel_12237, sel_12236, sel_12239};
  assign words_seen = ____state_2 + 8'h01;
  assign phenom_syndrome_cell__admit_load_en = phenom_syndrome_cell__admit_vld & phenom_syndrome_cell__admit_valid_load_en;
  assign phenom_syndrome_cell__ext_recv_load_en = phenom_syndrome_cell__ext_recv_vld & phenom_syndrome_cell__ext_recv_valid_load_en;
  assign or_12248 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_10408 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_10438 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_10437[0]}} | payload & {128{concat_10437[1]}};
  assign and_10452 = (nor_10379 | and_10380) & p0_stage_done;
  assign one_hot_sel_10445 = 8'h00 & {8{concat_10437[0]}} | words_seen & {8{concat_10437[1]}};
  assign __phenom_syndrome_cell__req_buf = {{sel_12239[7:0], sel_12239[15:8], sel_12239[23:16], sel_12239[31:24]}, {sel_12238, sel_12237, sel_12236}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_2 <= 8'h00;
      ____state_1 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__ext_recv_reg <= __phenom_syndrome_cell__ext_recv_reg_init;
      __phenom_syndrome_cell__ext_recv_valid_reg <= 1'h0;
      __phenom_syndrome_cell__admit_reg <= 1'h0;
      __phenom_syndrome_cell__admit_valid_reg <= 1'h0;
      __phenom_syndrome_cell__req_reg <= __phenom_syndrome_cell__req_reg_init;
      __phenom_syndrome_cell__req_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? nand_10408 : ____state_0;
      ____state_2 <= and_10452 ? one_hot_sel_10445 : ____state_2;
      ____state_1 <= and_10452 ? one_hot_sel_10438 : ____state_1;
      __phenom_syndrome_cell__ext_recv_reg <= phenom_syndrome_cell__ext_recv_load_en ? phenom_syndrome_cell__ext_recv : __phenom_syndrome_cell__ext_recv_reg;
      __phenom_syndrome_cell__ext_recv_valid_reg <= phenom_syndrome_cell__ext_recv_valid_load_en ? phenom_syndrome_cell__ext_recv_vld : __phenom_syndrome_cell__ext_recv_valid_reg;
      __phenom_syndrome_cell__admit_reg <= phenom_syndrome_cell__admit_load_en ? phenom_syndrome_cell__admit : __phenom_syndrome_cell__admit_reg;
      __phenom_syndrome_cell__admit_valid_reg <= phenom_syndrome_cell__admit_valid_load_en ? phenom_syndrome_cell__admit_vld : __phenom_syndrome_cell__admit_valid_reg;
      __phenom_syndrome_cell__req_reg <= phenom_syndrome_cell__req_load_en ? __phenom_syndrome_cell__req_buf : __phenom_syndrome_cell__req_reg;
      __phenom_syndrome_cell__req_valid_reg <= phenom_syndrome_cell__req_valid_load_en ? __phenom_syndrome_cell__req_vld_buf : __phenom_syndrome_cell__req_valid_reg;
    end
  end
  assign phenom_syndrome_cell__admit_rdy = phenom_syndrome_cell__admit_load_en;
  assign phenom_syndrome_cell__ext_recv_rdy = phenom_syndrome_cell__ext_recv_load_en;
  assign phenom_syndrome_cell__req = __phenom_syndrome_cell__req_reg;
  assign phenom_syndrome_cell__req_vld = __phenom_syndrome_cell__req_valid_reg;
endmodule


module __axis__Top__Tx_0_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_syndrome_cell__north,
  input wire phenom_syndrome_cell__north_vld,
  input wire phenom_syndrome_cell__north_send_rdy,
  output wire phenom_syndrome_cell__north_rdy,
  output wire [32:0] phenom_syndrome_cell__north_send,
  output wire phenom_syndrome_cell__north_send_vld
);
  wire [127:0] __phenom_syndrome_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_syndrome_cell__north_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_10508 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_syndrome_cell__north_reg;
  reg __phenom_syndrome_cell__north_valid_reg;
  reg [32:0] __phenom_syndrome_cell__north_send_reg;
  reg __phenom_syndrome_cell__north_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_syndrome_cell__north_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_syndrome_cell__north_send_valid_inv;
  wire nor_10520;
  wire not_10521;
  wire __phenom_syndrome_cell__north_send_vld_buf;
  wire phenom_syndrome_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_syndrome_cell__north_send_load_en;
  wire [2:0] one_hot_10530;
  wire [2:0] one_hot_10531;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_syndrome_cell__north_valid_inv;
  wire and_10570;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_syndrome_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_10573;
  wire [127:0] payload;
  wire [1:0] concat_10586;
  wire [7:0] beats_sent;
  wire phenom_syndrome_cell__north_load_en;
  wire or_12252;
  wire or_12256;
  wire [7:0] one_hot_sel_10574;
  wire and_10594;
  wire [127:0] one_hot_sel_10581;
  wire [7:0] one_hot_sel_10587;
  wire [32:0] __phenom_syndrome_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_syndrome_cell__north_select = state2_header_payload_words_0_case_cmp ? __phenom_syndrome_cell__north_reg : literal_10508;
  assign frame_header__1 = phenom_syndrome_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_syndrome_cell__north_send_valid_inv = ~__phenom_syndrome_cell__north_send_valid_reg;
  assign nor_10520 = ~(last | ____state_0);
  assign not_10521 = ~last;
  assign __phenom_syndrome_cell__north_send_vld_buf = ____state_0 | __phenom_syndrome_cell__north_valid_reg;
  assign phenom_syndrome_cell__north_send_valid_load_en = phenom_syndrome_cell__north_send_rdy | phenom_syndrome_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_10520};
  assign ____state_6__next_value_predicates = {not_10521, last};
  assign phenom_syndrome_cell__north_send_load_en = __phenom_syndrome_cell__north_send_vld_buf & phenom_syndrome_cell__north_send_valid_load_en;
  assign one_hot_10530 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_10531 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_syndrome_cell__north_send_vld_buf & phenom_syndrome_cell__north_send_load_en;
  assign phenom_syndrome_cell__north_valid_inv = ~__phenom_syndrome_cell__north_valid_reg;
  assign and_10570 = last & p0_stage_done;
  assign frame_payload__1 = phenom_syndrome_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_syndrome_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_syndrome_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_10530[1] & nor_10520 == one_hot_10530[0];
  assign ____state_6__at_most_one_next_value = not_10521 == one_hot_10531[1] & last == one_hot_10531[0];
  assign concat_10573 = {and_10570, nor_10520 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_10586 = {not_10521 & p0_stage_done, and_10570};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_syndrome_cell__north_load_en = phenom_syndrome_cell__north_vld & phenom_syndrome_cell__north_valid_load_en;
  assign or_12252 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12256 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_10574 = frame_header_payload_words__1 & {8{concat_10573[0]}} | 8'h00 & {8{concat_10573[1]}};
  assign and_10594 = (last | nor_10520) & p0_stage_done;
  assign one_hot_sel_10581 = payload & {128{concat_10573[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_10573[1]}};
  assign one_hot_sel_10587 = 8'h00 & {8{concat_10586[0]}} | beats_sent & {8{concat_10586[1]}};
  assign __phenom_syndrome_cell__north_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__north_reg <= __phenom_syndrome_cell__north_reg_init;
      __phenom_syndrome_cell__north_valid_reg <= 1'h0;
      __phenom_syndrome_cell__north_send_reg <= __phenom_syndrome_cell__north_send_reg_init;
      __phenom_syndrome_cell__north_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_10521 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_10587 : ____state_6;
      ____state_1 <= and_10594 ? one_hot_sel_10574 : ____state_1;
      ____state_5 <= and_10594 ? one_hot_sel_10581 : ____state_5;
      __phenom_syndrome_cell__north_reg <= phenom_syndrome_cell__north_load_en ? phenom_syndrome_cell__north : __phenom_syndrome_cell__north_reg;
      __phenom_syndrome_cell__north_valid_reg <= phenom_syndrome_cell__north_valid_load_en ? phenom_syndrome_cell__north_vld : __phenom_syndrome_cell__north_valid_reg;
      __phenom_syndrome_cell__north_send_reg <= phenom_syndrome_cell__north_send_load_en ? __phenom_syndrome_cell__north_send_buf : __phenom_syndrome_cell__north_send_reg;
      __phenom_syndrome_cell__north_send_valid_reg <= phenom_syndrome_cell__north_send_valid_load_en ? __phenom_syndrome_cell__north_send_vld_buf : __phenom_syndrome_cell__north_send_valid_reg;
    end
  end
  assign phenom_syndrome_cell__north_rdy = phenom_syndrome_cell__north_load_en;
  assign phenom_syndrome_cell__north_send = __phenom_syndrome_cell__north_send_reg;
  assign phenom_syndrome_cell__north_send_vld = __phenom_syndrome_cell__north_send_valid_reg;
endmodule


module __axis__Top__Tx_1_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_syndrome_cell__east,
  input wire phenom_syndrome_cell__east_vld,
  input wire phenom_syndrome_cell__east_send_rdy,
  output wire phenom_syndrome_cell__east_rdy,
  output wire [32:0] phenom_syndrome_cell__east_send,
  output wire phenom_syndrome_cell__east_send_vld
);
  wire [127:0] __phenom_syndrome_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_syndrome_cell__east_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_10643 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_syndrome_cell__east_reg;
  reg __phenom_syndrome_cell__east_valid_reg;
  reg [32:0] __phenom_syndrome_cell__east_send_reg;
  reg __phenom_syndrome_cell__east_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_syndrome_cell__east_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_syndrome_cell__east_send_valid_inv;
  wire nor_10655;
  wire not_10656;
  wire __phenom_syndrome_cell__east_send_vld_buf;
  wire phenom_syndrome_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_syndrome_cell__east_send_load_en;
  wire [2:0] one_hot_10665;
  wire [2:0] one_hot_10666;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_syndrome_cell__east_valid_inv;
  wire and_10705;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_syndrome_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_10708;
  wire [127:0] payload;
  wire [1:0] concat_10721;
  wire [7:0] beats_sent;
  wire phenom_syndrome_cell__east_load_en;
  wire or_12258;
  wire or_12262;
  wire [7:0] one_hot_sel_10709;
  wire and_10729;
  wire [127:0] one_hot_sel_10716;
  wire [7:0] one_hot_sel_10722;
  wire [32:0] __phenom_syndrome_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_syndrome_cell__east_select = state2_header_payload_words_0_case_cmp ? __phenom_syndrome_cell__east_reg : literal_10643;
  assign frame_header__1 = phenom_syndrome_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_syndrome_cell__east_send_valid_inv = ~__phenom_syndrome_cell__east_send_valid_reg;
  assign nor_10655 = ~(last | ____state_0);
  assign not_10656 = ~last;
  assign __phenom_syndrome_cell__east_send_vld_buf = ____state_0 | __phenom_syndrome_cell__east_valid_reg;
  assign phenom_syndrome_cell__east_send_valid_load_en = phenom_syndrome_cell__east_send_rdy | phenom_syndrome_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_10655};
  assign ____state_6__next_value_predicates = {not_10656, last};
  assign phenom_syndrome_cell__east_send_load_en = __phenom_syndrome_cell__east_send_vld_buf & phenom_syndrome_cell__east_send_valid_load_en;
  assign one_hot_10665 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_10666 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_syndrome_cell__east_send_vld_buf & phenom_syndrome_cell__east_send_load_en;
  assign phenom_syndrome_cell__east_valid_inv = ~__phenom_syndrome_cell__east_valid_reg;
  assign and_10705 = last & p0_stage_done;
  assign frame_payload__1 = phenom_syndrome_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_syndrome_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_syndrome_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_10665[1] & nor_10655 == one_hot_10665[0];
  assign ____state_6__at_most_one_next_value = not_10656 == one_hot_10666[1] & last == one_hot_10666[0];
  assign concat_10708 = {and_10705, nor_10655 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_10721 = {not_10656 & p0_stage_done, and_10705};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_syndrome_cell__east_load_en = phenom_syndrome_cell__east_vld & phenom_syndrome_cell__east_valid_load_en;
  assign or_12258 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12262 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_10709 = frame_header_payload_words__1 & {8{concat_10708[0]}} | 8'h00 & {8{concat_10708[1]}};
  assign and_10729 = (last | nor_10655) & p0_stage_done;
  assign one_hot_sel_10716 = payload & {128{concat_10708[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_10708[1]}};
  assign one_hot_sel_10722 = 8'h00 & {8{concat_10721[0]}} | beats_sent & {8{concat_10721[1]}};
  assign __phenom_syndrome_cell__east_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__east_reg <= __phenom_syndrome_cell__east_reg_init;
      __phenom_syndrome_cell__east_valid_reg <= 1'h0;
      __phenom_syndrome_cell__east_send_reg <= __phenom_syndrome_cell__east_send_reg_init;
      __phenom_syndrome_cell__east_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_10656 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_10722 : ____state_6;
      ____state_1 <= and_10729 ? one_hot_sel_10709 : ____state_1;
      ____state_5 <= and_10729 ? one_hot_sel_10716 : ____state_5;
      __phenom_syndrome_cell__east_reg <= phenom_syndrome_cell__east_load_en ? phenom_syndrome_cell__east : __phenom_syndrome_cell__east_reg;
      __phenom_syndrome_cell__east_valid_reg <= phenom_syndrome_cell__east_valid_load_en ? phenom_syndrome_cell__east_vld : __phenom_syndrome_cell__east_valid_reg;
      __phenom_syndrome_cell__east_send_reg <= phenom_syndrome_cell__east_send_load_en ? __phenom_syndrome_cell__east_send_buf : __phenom_syndrome_cell__east_send_reg;
      __phenom_syndrome_cell__east_send_valid_reg <= phenom_syndrome_cell__east_send_valid_load_en ? __phenom_syndrome_cell__east_send_vld_buf : __phenom_syndrome_cell__east_send_valid_reg;
    end
  end
  assign phenom_syndrome_cell__east_rdy = phenom_syndrome_cell__east_load_en;
  assign phenom_syndrome_cell__east_send = __phenom_syndrome_cell__east_send_reg;
  assign phenom_syndrome_cell__east_send_vld = __phenom_syndrome_cell__east_send_valid_reg;
endmodule


module __axis__Top__Tx_2_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_syndrome_cell__west,
  input wire phenom_syndrome_cell__west_vld,
  input wire phenom_syndrome_cell__west_send_rdy,
  output wire phenom_syndrome_cell__west_rdy,
  output wire [32:0] phenom_syndrome_cell__west_send,
  output wire phenom_syndrome_cell__west_send_vld
);
  wire [127:0] __phenom_syndrome_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_syndrome_cell__west_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_10778 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_syndrome_cell__west_reg;
  reg __phenom_syndrome_cell__west_valid_reg;
  reg [32:0] __phenom_syndrome_cell__west_send_reg;
  reg __phenom_syndrome_cell__west_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_syndrome_cell__west_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_syndrome_cell__west_send_valid_inv;
  wire nor_10790;
  wire not_10791;
  wire __phenom_syndrome_cell__west_send_vld_buf;
  wire phenom_syndrome_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_syndrome_cell__west_send_load_en;
  wire [2:0] one_hot_10800;
  wire [2:0] one_hot_10801;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_syndrome_cell__west_valid_inv;
  wire and_10840;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_syndrome_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_10843;
  wire [127:0] payload;
  wire [1:0] concat_10856;
  wire [7:0] beats_sent;
  wire phenom_syndrome_cell__west_load_en;
  wire or_12264;
  wire or_12268;
  wire [7:0] one_hot_sel_10844;
  wire and_10864;
  wire [127:0] one_hot_sel_10851;
  wire [7:0] one_hot_sel_10857;
  wire [32:0] __phenom_syndrome_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_syndrome_cell__west_select = state2_header_payload_words_0_case_cmp ? __phenom_syndrome_cell__west_reg : literal_10778;
  assign frame_header__1 = phenom_syndrome_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_syndrome_cell__west_send_valid_inv = ~__phenom_syndrome_cell__west_send_valid_reg;
  assign nor_10790 = ~(last | ____state_0);
  assign not_10791 = ~last;
  assign __phenom_syndrome_cell__west_send_vld_buf = ____state_0 | __phenom_syndrome_cell__west_valid_reg;
  assign phenom_syndrome_cell__west_send_valid_load_en = phenom_syndrome_cell__west_send_rdy | phenom_syndrome_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_10790};
  assign ____state_6__next_value_predicates = {not_10791, last};
  assign phenom_syndrome_cell__west_send_load_en = __phenom_syndrome_cell__west_send_vld_buf & phenom_syndrome_cell__west_send_valid_load_en;
  assign one_hot_10800 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_10801 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_syndrome_cell__west_send_vld_buf & phenom_syndrome_cell__west_send_load_en;
  assign phenom_syndrome_cell__west_valid_inv = ~__phenom_syndrome_cell__west_valid_reg;
  assign and_10840 = last & p0_stage_done;
  assign frame_payload__1 = phenom_syndrome_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_syndrome_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_syndrome_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_10800[1] & nor_10790 == one_hot_10800[0];
  assign ____state_6__at_most_one_next_value = not_10791 == one_hot_10801[1] & last == one_hot_10801[0];
  assign concat_10843 = {and_10840, nor_10790 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_10856 = {not_10791 & p0_stage_done, and_10840};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_syndrome_cell__west_load_en = phenom_syndrome_cell__west_vld & phenom_syndrome_cell__west_valid_load_en;
  assign or_12264 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12268 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_10844 = frame_header_payload_words__1 & {8{concat_10843[0]}} | 8'h00 & {8{concat_10843[1]}};
  assign and_10864 = (last | nor_10790) & p0_stage_done;
  assign one_hot_sel_10851 = payload & {128{concat_10843[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_10843[1]}};
  assign one_hot_sel_10857 = 8'h00 & {8{concat_10856[0]}} | beats_sent & {8{concat_10856[1]}};
  assign __phenom_syndrome_cell__west_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__west_reg <= __phenom_syndrome_cell__west_reg_init;
      __phenom_syndrome_cell__west_valid_reg <= 1'h0;
      __phenom_syndrome_cell__west_send_reg <= __phenom_syndrome_cell__west_send_reg_init;
      __phenom_syndrome_cell__west_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_10791 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_10857 : ____state_6;
      ____state_1 <= and_10864 ? one_hot_sel_10844 : ____state_1;
      ____state_5 <= and_10864 ? one_hot_sel_10851 : ____state_5;
      __phenom_syndrome_cell__west_reg <= phenom_syndrome_cell__west_load_en ? phenom_syndrome_cell__west : __phenom_syndrome_cell__west_reg;
      __phenom_syndrome_cell__west_valid_reg <= phenom_syndrome_cell__west_valid_load_en ? phenom_syndrome_cell__west_vld : __phenom_syndrome_cell__west_valid_reg;
      __phenom_syndrome_cell__west_send_reg <= phenom_syndrome_cell__west_send_load_en ? __phenom_syndrome_cell__west_send_buf : __phenom_syndrome_cell__west_send_reg;
      __phenom_syndrome_cell__west_send_valid_reg <= phenom_syndrome_cell__west_send_valid_load_en ? __phenom_syndrome_cell__west_send_vld_buf : __phenom_syndrome_cell__west_send_valid_reg;
    end
  end
  assign phenom_syndrome_cell__west_rdy = phenom_syndrome_cell__west_load_en;
  assign phenom_syndrome_cell__west_send = __phenom_syndrome_cell__west_send_reg;
  assign phenom_syndrome_cell__west_send_vld = __phenom_syndrome_cell__west_send_valid_reg;
endmodule


module __axis__Top__Tx_3_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_syndrome_cell__south,
  input wire phenom_syndrome_cell__south_vld,
  input wire phenom_syndrome_cell__south_send_rdy,
  output wire phenom_syndrome_cell__south_rdy,
  output wire [32:0] phenom_syndrome_cell__south_send,
  output wire phenom_syndrome_cell__south_send_vld
);
  wire [127:0] __phenom_syndrome_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_syndrome_cell__south_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_10913 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_syndrome_cell__south_reg;
  reg __phenom_syndrome_cell__south_valid_reg;
  reg [32:0] __phenom_syndrome_cell__south_send_reg;
  reg __phenom_syndrome_cell__south_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_syndrome_cell__south_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_syndrome_cell__south_send_valid_inv;
  wire nor_10925;
  wire not_10926;
  wire __phenom_syndrome_cell__south_send_vld_buf;
  wire phenom_syndrome_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_syndrome_cell__south_send_load_en;
  wire [2:0] one_hot_10935;
  wire [2:0] one_hot_10936;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_syndrome_cell__south_valid_inv;
  wire and_10975;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_syndrome_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_10978;
  wire [127:0] payload;
  wire [1:0] concat_10991;
  wire [7:0] beats_sent;
  wire phenom_syndrome_cell__south_load_en;
  wire or_12270;
  wire or_12274;
  wire [7:0] one_hot_sel_10979;
  wire and_10999;
  wire [127:0] one_hot_sel_10986;
  wire [7:0] one_hot_sel_10992;
  wire [32:0] __phenom_syndrome_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_syndrome_cell__south_select = state2_header_payload_words_0_case_cmp ? __phenom_syndrome_cell__south_reg : literal_10913;
  assign frame_header__1 = phenom_syndrome_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_syndrome_cell__south_send_valid_inv = ~__phenom_syndrome_cell__south_send_valid_reg;
  assign nor_10925 = ~(last | ____state_0);
  assign not_10926 = ~last;
  assign __phenom_syndrome_cell__south_send_vld_buf = ____state_0 | __phenom_syndrome_cell__south_valid_reg;
  assign phenom_syndrome_cell__south_send_valid_load_en = phenom_syndrome_cell__south_send_rdy | phenom_syndrome_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_10925};
  assign ____state_6__next_value_predicates = {not_10926, last};
  assign phenom_syndrome_cell__south_send_load_en = __phenom_syndrome_cell__south_send_vld_buf & phenom_syndrome_cell__south_send_valid_load_en;
  assign one_hot_10935 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_10936 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_syndrome_cell__south_send_vld_buf & phenom_syndrome_cell__south_send_load_en;
  assign phenom_syndrome_cell__south_valid_inv = ~__phenom_syndrome_cell__south_valid_reg;
  assign and_10975 = last & p0_stage_done;
  assign frame_payload__1 = phenom_syndrome_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_syndrome_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_syndrome_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_10935[1] & nor_10925 == one_hot_10935[0];
  assign ____state_6__at_most_one_next_value = not_10926 == one_hot_10936[1] & last == one_hot_10936[0];
  assign concat_10978 = {and_10975, nor_10925 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_10991 = {not_10926 & p0_stage_done, and_10975};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_syndrome_cell__south_load_en = phenom_syndrome_cell__south_vld & phenom_syndrome_cell__south_valid_load_en;
  assign or_12270 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12274 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_10979 = frame_header_payload_words__1 & {8{concat_10978[0]}} | 8'h00 & {8{concat_10978[1]}};
  assign and_10999 = (last | nor_10925) & p0_stage_done;
  assign one_hot_sel_10986 = payload & {128{concat_10978[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_10978[1]}};
  assign one_hot_sel_10992 = 8'h00 & {8{concat_10991[0]}} | beats_sent & {8{concat_10991[1]}};
  assign __phenom_syndrome_cell__south_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__south_reg <= __phenom_syndrome_cell__south_reg_init;
      __phenom_syndrome_cell__south_valid_reg <= 1'h0;
      __phenom_syndrome_cell__south_send_reg <= __phenom_syndrome_cell__south_send_reg_init;
      __phenom_syndrome_cell__south_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_10926 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_10992 : ____state_6;
      ____state_1 <= and_10999 ? one_hot_sel_10979 : ____state_1;
      ____state_5 <= and_10999 ? one_hot_sel_10986 : ____state_5;
      __phenom_syndrome_cell__south_reg <= phenom_syndrome_cell__south_load_en ? phenom_syndrome_cell__south : __phenom_syndrome_cell__south_reg;
      __phenom_syndrome_cell__south_valid_reg <= phenom_syndrome_cell__south_valid_load_en ? phenom_syndrome_cell__south_vld : __phenom_syndrome_cell__south_valid_reg;
      __phenom_syndrome_cell__south_send_reg <= phenom_syndrome_cell__south_send_load_en ? __phenom_syndrome_cell__south_send_buf : __phenom_syndrome_cell__south_send_reg;
      __phenom_syndrome_cell__south_send_valid_reg <= phenom_syndrome_cell__south_send_valid_load_en ? __phenom_syndrome_cell__south_send_vld_buf : __phenom_syndrome_cell__south_send_valid_reg;
    end
  end
  assign phenom_syndrome_cell__south_rdy = phenom_syndrome_cell__south_load_en;
  assign phenom_syndrome_cell__south_send = __phenom_syndrome_cell__south_send_reg;
  assign phenom_syndrome_cell__south_send_vld = __phenom_syndrome_cell__south_send_valid_reg;
endmodule


module __axis__Top__Tx_4_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_syndrome_cell__phi,
  input wire phenom_syndrome_cell__phi_vld,
  input wire phenom_syndrome_cell__phi_send_rdy,
  output wire phenom_syndrome_cell__phi_rdy,
  output wire [32:0] phenom_syndrome_cell__phi_send,
  output wire phenom_syndrome_cell__phi_send_vld
);
  wire [127:0] __phenom_syndrome_cell__phi_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_syndrome_cell__phi_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_11048 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_syndrome_cell__phi_reg;
  reg __phenom_syndrome_cell__phi_valid_reg;
  reg [32:0] __phenom_syndrome_cell__phi_send_reg;
  reg __phenom_syndrome_cell__phi_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_syndrome_cell__phi_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_syndrome_cell__phi_send_valid_inv;
  wire nor_11060;
  wire not_11061;
  wire __phenom_syndrome_cell__phi_send_vld_buf;
  wire phenom_syndrome_cell__phi_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_syndrome_cell__phi_send_load_en;
  wire [2:0] one_hot_11070;
  wire [2:0] one_hot_11071;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_syndrome_cell__phi_valid_inv;
  wire and_11110;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_syndrome_cell__phi_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_11113;
  wire [127:0] payload;
  wire [1:0] concat_11126;
  wire [7:0] beats_sent;
  wire phenom_syndrome_cell__phi_load_en;
  wire or_12276;
  wire or_12280;
  wire [7:0] one_hot_sel_11114;
  wire and_11134;
  wire [127:0] one_hot_sel_11121;
  wire [7:0] one_hot_sel_11127;
  wire [32:0] __phenom_syndrome_cell__phi_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_syndrome_cell__phi_select = state2_header_payload_words_0_case_cmp ? __phenom_syndrome_cell__phi_reg : literal_11048;
  assign frame_header__1 = phenom_syndrome_cell__phi_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_syndrome_cell__phi_send_valid_inv = ~__phenom_syndrome_cell__phi_send_valid_reg;
  assign nor_11060 = ~(last | ____state_0);
  assign not_11061 = ~last;
  assign __phenom_syndrome_cell__phi_send_vld_buf = ____state_0 | __phenom_syndrome_cell__phi_valid_reg;
  assign phenom_syndrome_cell__phi_send_valid_load_en = phenom_syndrome_cell__phi_send_rdy | phenom_syndrome_cell__phi_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_11060};
  assign ____state_6__next_value_predicates = {not_11061, last};
  assign phenom_syndrome_cell__phi_send_load_en = __phenom_syndrome_cell__phi_send_vld_buf & phenom_syndrome_cell__phi_send_valid_load_en;
  assign one_hot_11070 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_11071 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_syndrome_cell__phi_send_vld_buf & phenom_syndrome_cell__phi_send_load_en;
  assign phenom_syndrome_cell__phi_valid_inv = ~__phenom_syndrome_cell__phi_valid_reg;
  assign and_11110 = last & p0_stage_done;
  assign frame_payload__1 = phenom_syndrome_cell__phi_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_syndrome_cell__phi_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_syndrome_cell__phi_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_11070[1] & nor_11060 == one_hot_11070[0];
  assign ____state_6__at_most_one_next_value = not_11061 == one_hot_11071[1] & last == one_hot_11071[0];
  assign concat_11113 = {and_11110, nor_11060 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_11126 = {not_11061 & p0_stage_done, and_11110};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_syndrome_cell__phi_load_en = phenom_syndrome_cell__phi_vld & phenom_syndrome_cell__phi_valid_load_en;
  assign or_12276 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12280 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_11114 = frame_header_payload_words__1 & {8{concat_11113[0]}} | 8'h00 & {8{concat_11113[1]}};
  assign and_11134 = (last | nor_11060) & p0_stage_done;
  assign one_hot_sel_11121 = payload & {128{concat_11113[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11113[1]}};
  assign one_hot_sel_11127 = 8'h00 & {8{concat_11126[0]}} | beats_sent & {8{concat_11126[1]}};
  assign __phenom_syndrome_cell__phi_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_syndrome_cell__phi_reg <= __phenom_syndrome_cell__phi_reg_init;
      __phenom_syndrome_cell__phi_valid_reg <= 1'h0;
      __phenom_syndrome_cell__phi_send_reg <= __phenom_syndrome_cell__phi_send_reg_init;
      __phenom_syndrome_cell__phi_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_11061 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_11127 : ____state_6;
      ____state_1 <= and_11134 ? one_hot_sel_11114 : ____state_1;
      ____state_5 <= and_11134 ? one_hot_sel_11121 : ____state_5;
      __phenom_syndrome_cell__phi_reg <= phenom_syndrome_cell__phi_load_en ? phenom_syndrome_cell__phi : __phenom_syndrome_cell__phi_reg;
      __phenom_syndrome_cell__phi_valid_reg <= phenom_syndrome_cell__phi_valid_load_en ? phenom_syndrome_cell__phi_vld : __phenom_syndrome_cell__phi_valid_reg;
      __phenom_syndrome_cell__phi_send_reg <= phenom_syndrome_cell__phi_send_load_en ? __phenom_syndrome_cell__phi_send_buf : __phenom_syndrome_cell__phi_send_reg;
      __phenom_syndrome_cell__phi_send_valid_reg <= phenom_syndrome_cell__phi_send_valid_load_en ? __phenom_syndrome_cell__phi_send_vld_buf : __phenom_syndrome_cell__phi_send_valid_reg;
    end
  end
  assign phenom_syndrome_cell__phi_rdy = phenom_syndrome_cell__phi_load_en;
  assign phenom_syndrome_cell__phi_send = __phenom_syndrome_cell__phi_send_reg;
  assign phenom_syndrome_cell__phi_send_vld = __phenom_syndrome_cell__phi_send_valid_reg;
endmodule


module __phenom_syndrome_cell__Top_0_next__1(
  input wire clk,
  input wire reset
);

endmodule


module __phenom_syndrome_cell__Top__Service_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_syndrome_cell__admit_rdy,
  input wire phenom_syndrome_cell__east_rdy,
  input wire phenom_syndrome_cell__north_rdy,
  input wire phenom_syndrome_cell__phi_rdy,
  input wire [127:0] phenom_syndrome_cell__req,
  input wire phenom_syndrome_cell__req_vld,
  input wire phenom_syndrome_cell__south_rdy,
  input wire phenom_syndrome_cell__west_rdy,
  output wire phenom_syndrome_cell__admit,
  output wire phenom_syndrome_cell__admit_vld,
  output wire [127:0] phenom_syndrome_cell__east,
  output wire phenom_syndrome_cell__east_vld,
  output wire [127:0] phenom_syndrome_cell__north,
  output wire phenom_syndrome_cell__north_vld,
  output wire [127:0] phenom_syndrome_cell__phi,
  output wire phenom_syndrome_cell__phi_vld,
  output wire phenom_syndrome_cell__req_rdy,
  output wire [127:0] phenom_syndrome_cell__south,
  output wire phenom_syndrome_cell__south_vld,
  output wire [127:0] phenom_syndrome_cell__west,
  output wire phenom_syndrome_cell__west_vld
);
  function automatic priority_sel_1b_3way (input reg [2:0] sel, input reg case0, input reg case1, input reg case2, input reg default_value);
    begin
      casez (sel)
        3'b??1: begin
          priority_sel_1b_3way = case0;
        end
        3'b?10: begin
          priority_sel_1b_3way = case1;
        end
        3'b100: begin
          priority_sel_1b_3way = case2;
        end
        3'b000: begin
          priority_sel_1b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_1b_3way = 1'dx;
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
  wire [127:0] __phenom_syndrome_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_syndrome_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_syndrome_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_syndrome_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_syndrome_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_syndrome_cell__phi_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_11259 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire literal_11208[0:3];
  assign literal_11208[0] = 1'h0;
  assign literal_11208[1] = 1'h0;
  assign literal_11208[2] = 1'h1;
  assign literal_11208[3] = 1'h0;
  wire literal_11213[0:3];
  assign literal_11213[0] = 1'h0;
  assign literal_11213[1] = 1'h0;
  assign literal_11213[2] = 1'h0;
  assign literal_11213[3] = 1'h1;
  wire [1:0] literal_11205[0:3];
  assign literal_11205[0] = 2'h0;
  assign literal_11205[1] = 2'h0;
  assign literal_11205[2] = 2'h0;
  assign literal_11205[3] = 2'h3;
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  wire [31:0] literal_11214 = {8'h02, 8'h00, 8'h00, 8'h08};
  reg ____state_12;
  reg ____state_13;
  reg ____state_11;
  reg ____state_9_tuple_element_0[0:4];
  reg [7:0] ____state_10;
  reg [95:0] ____state_9_tuple_element_1_tuple_element_1[0:4];
  reg [7:0] ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0:4];
  reg [31:0] ____state_3;
  reg [31:0] ____state_2;
  reg [31:0] ____state_7;
  reg [1:0] ____state_0;
  reg [31:0] ____state_8;
  reg [31:0] ____state_6;
  reg [31:0] ____state_4;
  reg ____state_5;
  reg __phenom_syndrome_cell__admit_has_been_sent_reg;
  reg __phenom_syndrome_cell__north_has_been_sent_reg;
  reg __phenom_syndrome_cell__east_has_been_sent_reg;
  reg __phenom_syndrome_cell__west_has_been_sent_reg;
  reg __phenom_syndrome_cell__south_has_been_sent_reg;
  reg __phenom_syndrome_cell__phi_has_been_sent_reg;
  reg [127:0] __phenom_syndrome_cell__req_reg;
  reg __phenom_syndrome_cell__req_valid_reg;
  reg __phenom_syndrome_cell__admit_reg;
  reg __phenom_syndrome_cell__admit_valid_reg;
  reg [127:0] __phenom_syndrome_cell__north_reg;
  reg __phenom_syndrome_cell__north_valid_reg;
  reg [127:0] __phenom_syndrome_cell__east_reg;
  reg __phenom_syndrome_cell__east_valid_reg;
  reg [127:0] __phenom_syndrome_cell__west_reg;
  reg __phenom_syndrome_cell__west_valid_reg;
  reg [127:0] __phenom_syndrome_cell__south_reg;
  reg __phenom_syndrome_cell__south_valid_reg;
  reg [127:0] __phenom_syndrome_cell__phi_reg;
  reg __phenom_syndrome_cell__phi_valid_reg;
  wire nor_11257;
  wire received;
  wire [127:0] phenom_syndrome_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_11268;
  wire eq_11270;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_11295;
  wire [31:0] concat_11296;
  wire ugt_11298;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_11300;
  wire postponed__4;
  wire ugt_11304;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_1744_0_case_0_case_4_case_0;
  wire or_reduce_11308;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_11319;
  wire postponed;
  wire [95:0] sel_11328;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_11331;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Source_1;
  wire [7:0] sel_11346;
  wire [31:0] Xls_clause_1_Seed_1;
  wire _0__16;
  wire _1__4;
  wire _2__4;
  wire [31:0] _7__1;
  wire [30:0] leading_bits___state_5;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [31:0] _0__9;
  wire [1:0] unexpand_for_next_value_1744_0_case_0_case_3_case_2;
  wire [1:0] unexpand_for_next_value_1744_0_case_0_case_3_case_1;
  wire eq_11348;
  wire _8__1;
  wire _9__1;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire _2__2;
  wire eq_11364;
  wire eq_11365;
  wire nor_11366;
  wire and_11359;
  wire _0;
  wire [2:0] concat_11376;
  wire invalid_repeat;
  wire postponed_slot_tup0;
  wire eligible_0;
  wire invalid_input;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire eq_11389;
  wire eq_11391;
  wire eq_11392;
  wire found;
  wire _15;
  wire [4:0] concat_11405;
  wire dispatchable;
  wire [18:0] _16__2;
  wire nand_11368;
  wire [1:0] priority_sel_11416;
  wire [1:0] directive;
  wire candidate_slots_0_case_cmp;
  wire transition_slots_default_case_cmp;
  wire [14:0] _17__1;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_11446;
  wire failed;
  wire [7:0] candidate_occupied;
  wire [1:0] candidate_phase_squeezed;
  wire [16:0] Xls_clause_1_NextRandom_1__3;
  wire [9:0] Xls_clause_1_NextRandom_1__2;
  wire [4:0] Xls_clause_1_NextRandom_1__1;
  wire phase_changed;
  wire reserve__1;
  wire reserve;
  wire effects_north_valid;
  wire effects_phi_valid;
  wire [1:0] unexpand_for_next_value_1744_0_case_0_case_3_case_3;
  wire and_11432;
  wire [31:0] Xls_clause_1_NextRandom_1;
  wire and_11436;
  wire eq_11437;
  wire and_11438;
  wire and_11440;
  wire _19;
  wire nor_11442;
  wire nor_11443;
  wire eq_11444;
  wire __phenom_syndrome_cell__admit_buf;
  wire __phenom_syndrome_cell__admit_not_has_been_sent;
  wire phenom_syndrome_cell__admit_valid_inv;
  wire __phenom_syndrome_cell__east_vld_buf;
  wire __phenom_syndrome_cell__north_not_has_been_sent;
  wire phenom_syndrome_cell__north_valid_inv;
  wire __phenom_syndrome_cell__east_not_has_been_sent;
  wire phenom_syndrome_cell__east_valid_inv;
  wire __phenom_syndrome_cell__west_not_has_been_sent;
  wire phenom_syndrome_cell__west_valid_inv;
  wire __phenom_syndrome_cell__south_not_has_been_sent;
  wire phenom_syndrome_cell__south_valid_inv;
  wire __phenom_syndrome_cell__phi_vld_buf;
  wire __phenom_syndrome_cell__phi_not_has_been_sent;
  wire phenom_syndrome_cell__phi_valid_inv;
  wire and_11447;
  wire and_11448;
  wire and_11449;
  wire nor_11450;
  wire candidate_occupied_0_case_cmp;
  wire and_11454;
  wire Xls_clause_1_Measurement_1_0_case_cmp;
  wire and_11456;
  wire transition_slots_predicate_piece_0;
  wire and_11458;
  wire or_11459;
  wire __phenom_syndrome_cell__admit_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__admit_valid_load_en;
  wire __phenom_syndrome_cell__north_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__north_valid_load_en;
  wire __phenom_syndrome_cell__east_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__east_valid_load_en;
  wire __phenom_syndrome_cell__west_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__west_valid_load_en;
  wire __phenom_syndrome_cell__south_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__south_valid_load_en;
  wire __phenom_syndrome_cell__phi_valid_and_not_has_been_sent;
  wire phenom_syndrome_cell__phi_valid_load_en;
  wire and_11464;
  wire and_11465;
  wire and_11466;
  wire and_11467;
  wire and_11468;
  wire and_11469;
  wire nor_11470;
  wire and_11471;
  wire and_11472;
  wire and_11473;
  wire and_11474;
  wire and_11475;
  wire and_11476;
  wire and_11477;
  wire and_11478;
  wire and_11479;
  wire and_11480;
  wire and_11481;
  wire and_11482;
  wire and_11483;
  wire and_11484;
  wire and_11485;
  wire and_11486;
  wire and_11487;
  wire and_11488;
  wire and_11489;
  wire and_11490;
  wire and_11491;
  wire and_11492;
  wire phenom_syndrome_cell__admit_not_pred;
  wire phenom_syndrome_cell__admit_load_en;
  wire phenom_syndrome_cell__east_not_pred;
  wire phenom_syndrome_cell__north_load_en;
  wire phenom_syndrome_cell__east_load_en;
  wire phenom_syndrome_cell__west_load_en;
  wire phenom_syndrome_cell__south_load_en;
  wire phenom_syndrome_cell__phi_not_pred;
  wire phenom_syndrome_cell__phi_load_en;
  wire [2:0] ____state_3__next_value_predicates;
  wire [2:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_7__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [1:0] ____state_12__next_value_predicates;
  wire [15:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_5__next_value_predicates;
  wire [4:0] ____state_9_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_9_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [3:0] one_hot_11530;
  wire [3:0] one_hot_11531;
  wire [2:0] one_hot_11532;
  wire [2:0] one_hot_11533;
  wire [2:0] one_hot_11534;
  wire [16:0] one_hot_11535;
  wire [2:0] one_hot_11536;
  wire [5:0] one_hot_11537;
  wire [8:0] one_hot_11538;
  wire [95:0] array_index_11514;
  wire [95:0] array_index_11516;
  wire [95:0] array_index_11518;
  wire [7:0] array_index_11522;
  wire [7:0] array_index_11524;
  wire [7:0] array_index_11526;
  wire [1:0] array_index_11493;
  wire p0_all_active_outputs_ready;
  wire [31:0] Xls_clause_1_Present_1;
  wire ne_11557;
  wire or_reduce_11559;
  wire ugt_11561;
  wire [3:0] one_hot_12240;
  wire phenom_syndrome_cell__req_valid_inv;
  wire and_11783;
  wire and_11784;
  wire and_11801;
  wire [31:0] Xls_clause_1_NewParity_1;
  wire [31:0] Xls_clause_1_Measurement_1__1;
  wire [31:0] extended___state_5;
  wire and_11807;
  wire admission_pending;
  wire and_11864;
  wire and_11865;
  wire and_11866;
  wire and_11867;
  wire [31:0] concat_11638;
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
  wire [95:0] sign_ext_11540;
  wire phenom_syndrome_cell__req_valid_load_en;
  wire ____state_3__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_7__at_most_one_next_value;
  wire ____state_10__at_most_one_next_value;
  wire ____state_12__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_5__at_most_one_next_value;
  wire ____state_9_tuple_element_0__at_most_one_next_value;
  wire ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value;
  wire [2:0] concat_11787;
  wire [2:0] concat_11803;
  wire [31:0] Xls_clause_1_Detection_1;
  wire [1:0] concat_11810;
  wire [1:0] concat_11820;
  wire [1:0] concat_11830;
  wire [15:0] concat_11852;
  wire [1:0] concat_11859;
  wire [4:0] concat_11869;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_11882;
  wire [95:0] postponed_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [95:0] compacted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [7:0] postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [7:0] compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire __phenom_syndrome_cell__admit_valid_and_all_active_outputs_ready;
  wire __phenom_syndrome_cell__admit_valid_and_ready_txfr;
  wire __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  wire __phenom_syndrome_cell__north_valid_and_ready_txfr;
  wire __phenom_syndrome_cell__east_valid_and_ready_txfr;
  wire __phenom_syndrome_cell__west_valid_and_ready_txfr;
  wire __phenom_syndrome_cell__south_valid_and_ready_txfr;
  wire __phenom_syndrome_cell__phi_valid_and_all_active_outputs_ready;
  wire __phenom_syndrome_cell__phi_valid_and_ready_txfr;
  wire phenom_syndrome_cell__req_load_en;
  wire or_12282;
  wire or_12286;
  wire or_12288;
  wire or_12290;
  wire or_12292;
  wire or_12294;
  wire or_12296;
  wire or_12298;
  wire or_12300;
  wire and_11906;
  wire [31:0] one_hot_sel_11788;
  wire and_11909;
  wire [31:0] one_hot_sel_11796;
  wire [31:0] one_hot_sel_11804;
  wire and_11915;
  wire [31:0] one_hot_sel_11811;
  wire and_11918;
  wire and_11920;
  wire [7:0] one_hot_sel_11821;
  wire and_11923;
  wire and_11699;
  wire and_11925;
  wire one_hot_sel_11831;
  wire and_11928;
  wire or_11697;
  wire [1:0] one_hot_sel_11853;
  wire and_11932;
  wire one_hot_sel_11860;
  wire and_11935;
  wire one_hot_sel_11870[0:4];
  wire and_11938;
  wire [95:0] one_hot_sel_11883[0:4];
  wire and_11941;
  wire [7:0] one_hot_sel_11896[0:4];
  wire __phenom_syndrome_cell__admit_not_stage_load;
  wire __phenom_syndrome_cell__admit_has_been_sent_reg_load_en;
  wire __phenom_syndrome_cell__east_not_stage_load;
  wire __phenom_syndrome_cell__north_has_been_sent_reg_load_en;
  wire __phenom_syndrome_cell__east_has_been_sent_reg_load_en;
  wire __phenom_syndrome_cell__west_has_been_sent_reg_load_en;
  wire __phenom_syndrome_cell__south_has_been_sent_reg_load_en;
  wire __phenom_syndrome_cell__phi_not_stage_load;
  wire __phenom_syndrome_cell__phi_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire [127:0] effects_east;
  wire [127:0] effects_west;
  wire [127:0] effects_south;
  wire [127:0] effects_phi;
  wire or_12304;
  assign nor_11257 = ~(____state_13 | ____state_11 | ~____state_12);
  assign received = nor_11257 & __phenom_syndrome_cell__req_valid_reg;
  assign phenom_syndrome_cell__req_select = received ? __phenom_syndrome_cell__req_reg : literal_11259;
  assign frame_header = phenom_syndrome_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_11268 = frame_header__1_payload_words == 8'h03;
  assign eq_11270 = frame_header__1_payload_words == 8'h02;
  assign tag_ok = frame_header_op == 8'h03 & eq_11268 | frame_header_op == 8'h04 & eq_11270 | frame_header_op == MAILBOX_CAPACITY & eq_11268 | frame_header_op == 8'h06 & eq_11270 | frame_header_op == 8'h07 & frame_header__1_payload_words == 8'h01 | frame_header_op == 8'h08 & eq_11270 | frame_header_op == 8'h09 & eq_11268 | frame_header_op == 8'h0a & eq_11270;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_10 + {7'h00, accepted};
  assign and_11295 = ~accepted & ____state_9_tuple_element_0[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign concat_11296 = {24'h00_0000, ____state_10};
  assign ugt_11298 = admitted_occupied > 8'h04;
  assign or_reduce_11300 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_11304 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_11298 | postponed__4);
  assign unexpand_for_next_value_1744_0_case_0_case_4_case_0 = 2'h0;
  assign or_reduce_11308 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_11300 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_11304 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_11308 | postponed__1);
  assign eq_11319 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_11328 = accepted ? phenom_syndrome_cell__req_select[95:0] : ____state_9_tuple_element_1_tuple_element_1[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_1744_0_case_0_case_4_case_0}))} & {8{eq_11319 | postponed}};
  assign bit_slice_11331 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_11331 > 3'h4 ? 3'h4 : bit_slice_11331];
  assign Xls_clause_1_Source_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign sel_11346 = accepted ? frame_header_op : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[____state_10 > 8'h04 ? 3'h4 : ____state_10[2:0]];
  assign Xls_clause_1_Seed_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__16 = Xls_clause_1_Source_1 == 32'h0000_0001;
  assign _1__4 = Xls_clause_1_Source_1 == 32'h0000_0002;
  assign _2__4 = Xls_clause_1_Source_1 == 32'h0000_0004;
  assign _7__1 = ____state_3 & Xls_clause_1_Source_1;
  assign leading_bits___state_5 = 31'h0000_0000;
  assign _0__9 = ____state_2 + 32'h0000_0001;
  assign unexpand_for_next_value_1744_0_case_0_case_3_case_2 = 2'h2;
  assign unexpand_for_next_value_1744_0_case_0_case_3_case_1 = 2'h1;
  assign eq_11348 = Xls_clause_1_Seed_1 == ____state_2;
  assign _8__1 = _7__1 == 32'h0000_0000;
  assign _9__1 = selected_slot_tuple_idx_1_tuple_idx_1[95:65] == leading_bits___state_5;
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_11331 > 3'h4 ? 3'h4 : bit_slice_11331];
  assign _2__2 = Xls_clause_1_Seed_1 == _0__9;
  assign eq_11364 = ____state_0 == unexpand_for_next_value_1744_0_case_0_case_3_case_2;
  assign eq_11365 = ____state_0 == unexpand_for_next_value_1744_0_case_0_case_3_case_1;
  assign nor_11366 = ~(____state_0[0] | ____state_0[1]);
  assign and_11359 = eq_11348 & (_0__16 | _1__4 | _2__4 | Xls_clause_1_Source_1 == 32'h0000_0008) & _8__1 & _9__1;
  assign _0 = Xls_clause_1_Seed_1 != 32'h0000_0000;
  assign concat_11376 = {eq_11364, eq_11365, nor_11366};
  assign invalid_repeat = 1'h0;
  assign postponed_slot_tup0 = 1'h1;
  assign eligible_0 = ~(eq_11319 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign Xls_clause_1_NewSeen_1 = ____state_3 | Xls_clause_1_Source_1;
  assign eq_11389 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h09;
  assign eq_11391 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h07;
  assign eq_11392 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h06;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign _15 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign concat_11405 = {eq_11389, selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h08, eq_11391, eq_11392, selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04 | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03};
  assign dispatchable = found & ~invalid_input;
  assign _16__2 = ____state_7[31:13] ^ ____state_7[18:0];
  assign nand_11368 = ~(and_11359 & _15);
  assign priority_sel_11416 = priority_sel_2b_5way(concat_11405, unexpand_for_next_value_1744_0_case_0_case_3_case_2, {~(~____state_0[0] & ~____state_0[1] & _0), invalid_repeat}, {____state_0[1] ? ~_2__2 : ~eq_11348, eq_11348 & concat_11376[0] | invalid_repeat & concat_11376[1] | _2__2 & concat_11376[2]}, unexpand_for_next_value_1744_0_case_0_case_3_case_2, {priority_sel_1b_3way(concat_11376, postponed_slot_tup0, ~eq_11348, ~and_11359, ~_2__2), priority_sel_1b_3way(concat_11376, invalid_repeat, eq_11348, invalid_repeat, _2__2)}, unexpand_for_next_value_1744_0_case_0_case_3_case_2);
  assign directive = priority_sel_11416 & {2{dispatchable}};
  assign candidate_slots_0_case_cmp = ~dispatchable;
  assign transition_slots_default_case_cmp = directive[1];
  assign _17__1 = {_16__2[1:0], ____state_7[12:0]} ^ _16__2[18:4];
  assign candidate_occupied_1_case_cmp = ~(candidate_slots_0_case_cmp | directive[0] | transition_slots_default_case_cmp);
  assign add_11446 = admitted_occupied + 8'hff;
  assign failed = invalid_input | directive == unexpand_for_next_value_1744_0_case_0_case_3_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_11446 : admitted_occupied;
  assign candidate_phase_squeezed = dispatchable ? priority_sel_2b_5way(concat_11405, ____state_0, {____state_0[1], priority_sel_1b_3way(concat_11376, _0, postponed_slot_tup0, invalid_repeat, postponed_slot_tup0)}, {priority_sel_1b_2way({eq_11365, nor_11366}, invalid_repeat, eq_11348, postponed_slot_tup0), priority_sel_1b_3way(concat_11376, invalid_repeat, ~eq_11348, invalid_repeat, ~_2__2)}, ____state_0, {____state_0[1], priority_sel_1b_3way(concat_11376, invalid_repeat, postponed_slot_tup0, ~nand_11368, postponed_slot_tup0)}, ____state_0) : ____state_0;
  assign Xls_clause_1_NextRandom_1__3 = _16__2[18:2] ^ {_16__2[13:2], _17__1[14:10]};
  assign Xls_clause_1_NextRandom_1__2 = _17__1[14:5] ^ _17__1[9:0];
  assign Xls_clause_1_NextRandom_1__1 = _17__1[4:0];
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign reserve__1 = ~failed & ~received & ~(____state_12 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_12 | ____state_10 > 8'h04);
  assign effects_north_valid = literal_11208[____state_0];
  assign effects_phi_valid = literal_11213[____state_0];
  assign unexpand_for_next_value_1744_0_case_0_case_3_case_3 = 2'h3;
  assign and_11432 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_11389;
  assign Xls_clause_1_NextRandom_1 = {Xls_clause_1_NextRandom_1__3, Xls_clause_1_NextRandom_1__2, Xls_clause_1_NextRandom_1__1};
  assign and_11436 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_11391;
  assign eq_11437 = ____state_0 == unexpand_for_next_value_1744_0_case_0_case_3_case_3;
  assign and_11438 = ~(____state_13 | ____state_11 | candidate_slots_0_case_cmp) & eq_11392;
  assign and_11440 = and_11432 & eq_11364;
  assign _19 = Xls_clause_1_NextRandom_1 < ____state_8;
  assign nor_11442 = ~(____state_13 | ____state_11 | phase_changed);
  assign nor_11443 = ~(____state_13 | ____state_11 | ~phase_changed);
  assign eq_11444 = priority_sel_11416 == unexpand_for_next_value_1744_0_case_0_case_3_case_1;
  assign __phenom_syndrome_cell__admit_buf = ~____state_13 & ~____state_11 & reserve__1 | ~____state_13 & ____state_11 & reserve;
  assign __phenom_syndrome_cell__admit_not_has_been_sent = ~__phenom_syndrome_cell__admit_has_been_sent_reg;
  assign phenom_syndrome_cell__admit_valid_inv = ~__phenom_syndrome_cell__admit_valid_reg;
  assign __phenom_syndrome_cell__east_vld_buf = ~(____state_13 | ~____state_11 | ~effects_north_valid);
  assign __phenom_syndrome_cell__north_not_has_been_sent = ~__phenom_syndrome_cell__north_has_been_sent_reg;
  assign phenom_syndrome_cell__north_valid_inv = ~__phenom_syndrome_cell__north_valid_reg;
  assign __phenom_syndrome_cell__east_not_has_been_sent = ~__phenom_syndrome_cell__east_has_been_sent_reg;
  assign phenom_syndrome_cell__east_valid_inv = ~__phenom_syndrome_cell__east_valid_reg;
  assign __phenom_syndrome_cell__west_not_has_been_sent = ~__phenom_syndrome_cell__west_has_been_sent_reg;
  assign phenom_syndrome_cell__west_valid_inv = ~__phenom_syndrome_cell__west_valid_reg;
  assign __phenom_syndrome_cell__south_not_has_been_sent = ~__phenom_syndrome_cell__south_has_been_sent_reg;
  assign phenom_syndrome_cell__south_valid_inv = ~__phenom_syndrome_cell__south_valid_reg;
  assign __phenom_syndrome_cell__phi_vld_buf = ~(____state_13 | ~____state_11 | ~effects_phi_valid);
  assign __phenom_syndrome_cell__phi_not_has_been_sent = ~__phenom_syndrome_cell__phi_has_been_sent_reg;
  assign phenom_syndrome_cell__phi_valid_inv = ~__phenom_syndrome_cell__phi_valid_reg;
  assign and_11447 = and_11436 & eq_11365;
  assign and_11448 = and_11436 & eq_11437;
  assign and_11449 = and_11438 & nor_11366;
  assign nor_11450 = ~(____state_13 | ____state_11);
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_11454 = and_11440 & ~nand_11368;
  assign Xls_clause_1_Measurement_1_0_case_cmp = ~_19;
  assign and_11456 = nor_11442 & dispatchable;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign and_11458 = nor_11443 & dispatchable;
  assign or_11459 = directive[0] | transition_slots_default_case_cmp;
  assign __phenom_syndrome_cell__admit_valid_and_not_has_been_sent = __phenom_syndrome_cell__admit_buf & __phenom_syndrome_cell__admit_not_has_been_sent;
  assign phenom_syndrome_cell__admit_valid_load_en = phenom_syndrome_cell__admit_rdy | phenom_syndrome_cell__admit_valid_inv;
  assign __phenom_syndrome_cell__north_valid_and_not_has_been_sent = __phenom_syndrome_cell__east_vld_buf & __phenom_syndrome_cell__north_not_has_been_sent;
  assign phenom_syndrome_cell__north_valid_load_en = phenom_syndrome_cell__north_rdy | phenom_syndrome_cell__north_valid_inv;
  assign __phenom_syndrome_cell__east_valid_and_not_has_been_sent = __phenom_syndrome_cell__east_vld_buf & __phenom_syndrome_cell__east_not_has_been_sent;
  assign phenom_syndrome_cell__east_valid_load_en = phenom_syndrome_cell__east_rdy | phenom_syndrome_cell__east_valid_inv;
  assign __phenom_syndrome_cell__west_valid_and_not_has_been_sent = __phenom_syndrome_cell__east_vld_buf & __phenom_syndrome_cell__west_not_has_been_sent;
  assign phenom_syndrome_cell__west_valid_load_en = phenom_syndrome_cell__west_rdy | phenom_syndrome_cell__west_valid_inv;
  assign __phenom_syndrome_cell__south_valid_and_not_has_been_sent = __phenom_syndrome_cell__east_vld_buf & __phenom_syndrome_cell__south_not_has_been_sent;
  assign phenom_syndrome_cell__south_valid_load_en = phenom_syndrome_cell__south_rdy | phenom_syndrome_cell__south_valid_inv;
  assign __phenom_syndrome_cell__phi_valid_and_not_has_been_sent = __phenom_syndrome_cell__phi_vld_buf & __phenom_syndrome_cell__phi_not_has_been_sent;
  assign phenom_syndrome_cell__phi_valid_load_en = phenom_syndrome_cell__phi_rdy | phenom_syndrome_cell__phi_valid_inv;
  assign and_11464 = and_11447 & eq_11348;
  assign and_11465 = and_11448 & _2__2;
  assign and_11466 = and_11440 & and_11359;
  assign and_11467 = and_11449 & _0;
  assign and_11468 = nor_11450 & candidate_occupied_0_case_cmp;
  assign and_11469 = nor_11450 & candidate_occupied_1_case_cmp;
  assign nor_11470 = ~(____state_13 | ~____state_11);
  assign and_11471 = and_11438 & eq_11365;
  assign and_11472 = and_11438 & eq_11364;
  assign and_11473 = and_11438 & eq_11437;
  assign and_11474 = and_11436 & nor_11366;
  assign and_11475 = and_11436 & eq_11364;
  assign and_11476 = and_11432 & nor_11366;
  assign and_11477 = and_11432 & eq_11365;
  assign and_11478 = and_11432 & eq_11437;
  assign and_11479 = and_11449 & ~_0;
  assign and_11480 = and_11447 & ~eq_11348;
  assign and_11481 = and_11448 & ~_2__2;
  assign and_11482 = and_11440 & nand_11368;
  assign and_11483 = and_11454 & Xls_clause_1_Measurement_1_0_case_cmp;
  assign and_11484 = and_11454 & _19;
  assign and_11485 = nor_11442 & candidate_slots_0_case_cmp;
  assign and_11486 = and_11456 & transition_slots_predicate_piece_0;
  assign and_11487 = and_11456 & eq_11444;
  assign and_11488 = and_11456 & transition_slots_default_case_cmp;
  assign and_11489 = nor_11443 & candidate_slots_0_case_cmp;
  assign and_11490 = and_11458 & transition_slots_predicate_piece_0;
  assign and_11491 = and_11458 & eq_11444 & or_11459;
  assign and_11492 = and_11458 & ~eq_11444 & or_11459;
  assign phenom_syndrome_cell__admit_not_pred = ~__phenom_syndrome_cell__admit_buf;
  assign phenom_syndrome_cell__admit_load_en = __phenom_syndrome_cell__admit_valid_and_not_has_been_sent & phenom_syndrome_cell__admit_valid_load_en;
  assign phenom_syndrome_cell__east_not_pred = ~__phenom_syndrome_cell__east_vld_buf;
  assign phenom_syndrome_cell__north_load_en = __phenom_syndrome_cell__north_valid_and_not_has_been_sent & phenom_syndrome_cell__north_valid_load_en;
  assign phenom_syndrome_cell__east_load_en = __phenom_syndrome_cell__east_valid_and_not_has_been_sent & phenom_syndrome_cell__east_valid_load_en;
  assign phenom_syndrome_cell__west_load_en = __phenom_syndrome_cell__west_valid_and_not_has_been_sent & phenom_syndrome_cell__west_valid_load_en;
  assign phenom_syndrome_cell__south_load_en = __phenom_syndrome_cell__south_valid_and_not_has_been_sent & phenom_syndrome_cell__south_valid_load_en;
  assign phenom_syndrome_cell__phi_not_pred = ~__phenom_syndrome_cell__phi_vld_buf;
  assign phenom_syndrome_cell__phi_load_en = __phenom_syndrome_cell__phi_valid_and_not_has_been_sent & phenom_syndrome_cell__phi_valid_load_en;
  assign ____state_3__next_value_predicates = {and_11464, and_11465, and_11466};
  assign ____state_6__next_value_predicates = {and_11464, and_11465, and_11454};
  assign ____state_7__next_value_predicates = {and_11467, and_11454};
  assign ____state_10__next_value_predicates = {and_11468, and_11469};
  assign ____state_12__next_value_predicates = {nor_11450, nor_11470};
  assign ____state_0__next_value_predicates = {and_11471, and_11472, and_11473, and_11474, and_11475, and_11476, and_11477, and_11478, and_11479, and_11467, and_11480, and_11464, and_11481, and_11465, and_11454, and_11482};
  assign ____state_5__next_value_predicates = {and_11483, and_11484};
  assign ____state_9_tuple_element_0__next_value_predicates = {nor_11443, and_11485, and_11486, and_11487, and_11488};
  assign ____state_9_tuple_element_1_tuple_element_1__next_value_predicates = {and_11485, and_11486, and_11487, and_11488, and_11489, and_11490, and_11491, and_11492};
  assign one_hot_11530 = {____state_3__next_value_predicates[2:0] == 3'h0, ____state_3__next_value_predicates[2] && ____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_11531 = {____state_6__next_value_predicates[2:0] == 3'h0, ____state_6__next_value_predicates[2] && ____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_11532 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_11533 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_11534 = {____state_12__next_value_predicates[1:0] == 2'h0, ____state_12__next_value_predicates[1] && !____state_12__next_value_predicates[0], ____state_12__next_value_predicates[0]};
  assign one_hot_11535 = {____state_0__next_value_predicates[15:0] == 16'h0000, ____state_0__next_value_predicates[15] && ____state_0__next_value_predicates[14:0] == 15'h0000, ____state_0__next_value_predicates[14] && ____state_0__next_value_predicates[13:0] == 14'h0000, ____state_0__next_value_predicates[13] && ____state_0__next_value_predicates[12:0] == 13'h0000, ____state_0__next_value_predicates[12] && ____state_0__next_value_predicates[11:0] == 12'h000, ____state_0__next_value_predicates[11] && ____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_11536 = {____state_5__next_value_predicates[1:0] == 2'h0, ____state_5__next_value_predicates[1] && !____state_5__next_value_predicates[0], ____state_5__next_value_predicates[0]};
  assign one_hot_11537 = {____state_9_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_9_tuple_element_0__next_value_predicates[4] && ____state_9_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_9_tuple_element_0__next_value_predicates[3] && ____state_9_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_9_tuple_element_0__next_value_predicates[2] && ____state_9_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_9_tuple_element_0__next_value_predicates[1] && !____state_9_tuple_element_0__next_value_predicates[0], ____state_9_tuple_element_0__next_value_predicates[0]};
  assign one_hot_11538 = {____state_9_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_9_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_9_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign array_index_11514 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_11516 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_11518 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_11522 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_11524 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_11526 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign array_index_11493 = literal_11205[____state_0];
  assign p0_all_active_outputs_ready = (phenom_syndrome_cell__admit_not_pred | phenom_syndrome_cell__admit_load_en | __phenom_syndrome_cell__admit_has_been_sent_reg) & (phenom_syndrome_cell__east_not_pred | phenom_syndrome_cell__north_load_en | __phenom_syndrome_cell__north_has_been_sent_reg) & (phenom_syndrome_cell__east_not_pred | phenom_syndrome_cell__east_load_en | __phenom_syndrome_cell__east_has_been_sent_reg) & (phenom_syndrome_cell__east_not_pred | phenom_syndrome_cell__west_load_en | __phenom_syndrome_cell__west_has_been_sent_reg) & (phenom_syndrome_cell__east_not_pred | phenom_syndrome_cell__south_load_en | __phenom_syndrome_cell__south_has_been_sent_reg) & (phenom_syndrome_cell__phi_not_pred | phenom_syndrome_cell__phi_load_en | __phenom_syndrome_cell__phi_has_been_sent_reg);
  assign Xls_clause_1_Present_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign ne_11557 = bit_slice_11331 != 3'h0;
  assign or_reduce_11559 = |selected[7:1];
  assign ugt_11561 = bit_slice_11331 > 3'h2;
  assign one_hot_12240 = {concat_11376[2:0] == 3'h0, concat_11376[2] && concat_11376[1:0] == 2'h0, concat_11376[1] && !concat_11376[0], concat_11376[0]};
  assign phenom_syndrome_cell__req_valid_inv = ~__phenom_syndrome_cell__req_valid_reg;
  assign and_11783 = and_11464 & p0_all_active_outputs_ready;
  assign and_11784 = and_11465 & p0_all_active_outputs_ready;
  assign and_11801 = and_11454 & p0_all_active_outputs_ready;
  assign Xls_clause_1_NewParity_1 = ____state_4 ^ Xls_clause_1_Present_1;
  assign Xls_clause_1_Measurement_1__1 = {leading_bits___state_5, _19};
  assign extended___state_5 = {leading_bits___state_5, ____state_5};
  assign and_11807 = and_11467 & p0_all_active_outputs_ready;
  assign admission_pending = ~(~____state_12 | received);
  assign and_11864 = and_11485 & p0_all_active_outputs_ready;
  assign and_11865 = and_11486 & p0_all_active_outputs_ready;
  assign and_11866 = and_11487 & p0_all_active_outputs_ready;
  assign and_11867 = and_11488 & p0_all_active_outputs_ready;
  assign concat_11638 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_11557 ? postponed : or_reduce_11308 & postponed__1;
  assign compacted_1_tup0 = or_reduce_11559 ? postponed__1 : ugt_11304 & postponed__2;
  assign compacted_2_tup0 = ugt_11561 ? postponed__2 : or_reduce_11300 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_11298 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_11557 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_11514 & {96{or_reduce_11308}};
  assign compacted_1_tup1_tup1 = or_reduce_11559 ? array_index_11514 : array_index_11516 & {96{ugt_11304}};
  assign compacted_2_tup1_tup1 = ugt_11561 ? array_index_11516 : array_index_11518 & {96{or_reduce_11300}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_11518 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_11298}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_11557 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_11522 & {8{or_reduce_11308}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_11559 ? array_index_11522 : array_index_11524 & {8{ugt_11304}};
  assign compacted_2_tup1_tup0_tup3 = ugt_11561 ? array_index_11524 : array_index_11526 & {8{or_reduce_11300}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_11526 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_11298}};
  assign sign_ext_11540 = {96{eq_11364}};
  assign phenom_syndrome_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_11257 | phenom_syndrome_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_11464 == one_hot_11530[2] & and_11465 == one_hot_11530[1] & and_11466 == one_hot_11530[0];
  assign ____state_6__at_most_one_next_value = and_11464 == one_hot_11531[2] & and_11465 == one_hot_11531[1] & and_11454 == one_hot_11531[0];
  assign ____state_7__at_most_one_next_value = and_11467 == one_hot_11532[1] & and_11454 == one_hot_11532[0];
  assign ____state_10__at_most_one_next_value = and_11468 == one_hot_11533[1] & and_11469 == one_hot_11533[0];
  assign ____state_12__at_most_one_next_value = nor_11450 == one_hot_11534[1] & nor_11470 == one_hot_11534[0];
  assign ____state_0__at_most_one_next_value = and_11471 == one_hot_11535[15] & and_11472 == one_hot_11535[14] & and_11473 == one_hot_11535[13] & and_11474 == one_hot_11535[12] & and_11475 == one_hot_11535[11] & and_11476 == one_hot_11535[10] & and_11477 == one_hot_11535[9] & and_11478 == one_hot_11535[8] & and_11479 == one_hot_11535[7] & and_11467 == one_hot_11535[6] & and_11480 == one_hot_11535[5] & and_11464 == one_hot_11535[4] & and_11481 == one_hot_11535[3] & and_11465 == one_hot_11535[2] & and_11454 == one_hot_11535[1] & and_11482 == one_hot_11535[0];
  assign ____state_5__at_most_one_next_value = and_11483 == one_hot_11536[1] & and_11484 == one_hot_11536[0];
  assign ____state_9_tuple_element_0__at_most_one_next_value = nor_11443 == one_hot_11537[4] & and_11485 == one_hot_11537[3] & and_11486 == one_hot_11537[2] & and_11487 == one_hot_11537[1] & and_11488 == one_hot_11537[0];
  assign ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value = and_11485 == one_hot_11538[7] & and_11486 == one_hot_11538[6] & and_11487 == one_hot_11538[5] & and_11488 == one_hot_11538[4] & and_11489 == one_hot_11538[3] & and_11490 == one_hot_11538[2] & and_11491 == one_hot_11538[1] & and_11492 == one_hot_11538[0];
  assign concat_11787 = {and_11783, and_11784, and_11466 & p0_all_active_outputs_ready};
  assign concat_11803 = {and_11783, and_11784, and_11801};
  assign Xls_clause_1_Detection_1 = Xls_clause_1_NewParity_1 ^ Xls_clause_1_Measurement_1__1 ^ extended___state_5;
  assign concat_11810 = {and_11807, and_11801};
  assign concat_11820 = {and_11468 & p0_all_active_outputs_ready, and_11469 & p0_all_active_outputs_ready};
  assign concat_11830 = {nor_11450 & p0_all_active_outputs_ready, nor_11470 & p0_all_active_outputs_ready};
  assign concat_11852 = {and_11471 & p0_all_active_outputs_ready, and_11472 & p0_all_active_outputs_ready, and_11473 & p0_all_active_outputs_ready, and_11474 & p0_all_active_outputs_ready, and_11475 & p0_all_active_outputs_ready, and_11476 & p0_all_active_outputs_ready, and_11477 & p0_all_active_outputs_ready, and_11478 & p0_all_active_outputs_ready, and_11479 & p0_all_active_outputs_ready, and_11807, and_11480 & p0_all_active_outputs_ready, and_11783, and_11481 & p0_all_active_outputs_ready, and_11784, and_11801, and_11482 & p0_all_active_outputs_ready};
  assign concat_11859 = {and_11483 & p0_all_active_outputs_ready, and_11484 & p0_all_active_outputs_ready};
  assign concat_11869 = {nor_11443 & p0_all_active_outputs_ready, and_11864, and_11865, and_11866, and_11867};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = invalid_repeat;
  assign concat_11882 = {and_11864, and_11865, and_11866, and_11867, and_11489 & p0_all_active_outputs_ready, and_11490 & p0_all_active_outputs_ready, and_11491 & p0_all_active_outputs_ready, and_11492 & p0_all_active_outputs_ready};
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
  assign __phenom_syndrome_cell__admit_valid_and_all_active_outputs_ready = __phenom_syndrome_cell__admit_buf & p0_all_active_outputs_ready;
  assign __phenom_syndrome_cell__admit_valid_and_ready_txfr = __phenom_syndrome_cell__admit_valid_and_not_has_been_sent & phenom_syndrome_cell__admit_load_en;
  assign __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready = __phenom_syndrome_cell__east_vld_buf & p0_all_active_outputs_ready;
  assign __phenom_syndrome_cell__north_valid_and_ready_txfr = __phenom_syndrome_cell__north_valid_and_not_has_been_sent & phenom_syndrome_cell__north_load_en;
  assign __phenom_syndrome_cell__east_valid_and_ready_txfr = __phenom_syndrome_cell__east_valid_and_not_has_been_sent & phenom_syndrome_cell__east_load_en;
  assign __phenom_syndrome_cell__west_valid_and_ready_txfr = __phenom_syndrome_cell__west_valid_and_not_has_been_sent & phenom_syndrome_cell__west_load_en;
  assign __phenom_syndrome_cell__south_valid_and_ready_txfr = __phenom_syndrome_cell__south_valid_and_not_has_been_sent & phenom_syndrome_cell__south_load_en;
  assign __phenom_syndrome_cell__phi_valid_and_all_active_outputs_ready = __phenom_syndrome_cell__phi_vld_buf & p0_all_active_outputs_ready;
  assign __phenom_syndrome_cell__phi_valid_and_ready_txfr = __phenom_syndrome_cell__phi_valid_and_not_has_been_sent & phenom_syndrome_cell__phi_load_en;
  assign phenom_syndrome_cell__req_load_en = phenom_syndrome_cell__req_vld & phenom_syndrome_cell__req_valid_load_en;
  assign or_12282 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_12286 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_12288 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_12290 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_12292 = ~p0_all_active_outputs_ready | ____state_12__at_most_one_next_value | reset;
  assign or_12294 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_12296 = ~p0_all_active_outputs_ready | ____state_5__at_most_one_next_value | reset;
  assign or_12298 = ~p0_all_active_outputs_ready | ____state_9_tuple_element_0__at_most_one_next_value | reset;
  assign or_12300 = ~p0_all_active_outputs_ready | ____state_9_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign and_11906 = and_11465 & p0_all_active_outputs_ready;
  assign one_hot_sel_11788 = Xls_clause_1_NewSeen_1 & {32{concat_11787[0]}} | 32'h0000_0000 & {32{concat_11787[1]}} | 32'h0000_0000 & {32{concat_11787[2]}};
  assign and_11909 = (and_11464 | and_11465 | and_11466) & p0_all_active_outputs_ready;
  assign one_hot_sel_11796 = Xls_clause_1_NewParity_1 & {32{concat_11787[0]}} | 32'h0000_0000 & {32{concat_11787[1]}} | 32'h0000_0000 & {32{concat_11787[2]}};
  assign one_hot_sel_11804 = Xls_clause_1_Detection_1 & {32{concat_11803[0]}} | 32'h0000_0000 & {32{concat_11803[1]}} | 32'h0000_0000 & {32{concat_11803[2]}};
  assign and_11915 = (and_11464 | and_11465 | and_11454) & p0_all_active_outputs_ready;
  assign one_hot_sel_11811 = Xls_clause_1_NextRandom_1 & {32{concat_11810[0]}} | Xls_clause_1_Seed_1 & {32{concat_11810[1]}};
  assign and_11918 = (and_11467 | and_11454) & p0_all_active_outputs_ready;
  assign and_11920 = and_11467 & p0_all_active_outputs_ready;
  assign one_hot_sel_11821 = add_11446 & {8{concat_11820[0]}} | admitted_occupied & {8{concat_11820[1]}};
  assign and_11923 = (and_11468 | and_11469) & p0_all_active_outputs_ready;
  assign and_11699 = ~____state_11 & dispatchable & phase_changed & ~failed;
  assign and_11925 = ~____state_13 & p0_all_active_outputs_ready;
  assign one_hot_sel_11831 = (____state_12 | ____state_10 < MAILBOX_CAPACITY) & concat_11830[0] | (admission_pending | reserve__1) & concat_11830[1];
  assign and_11928 = (nor_11450 | nor_11470) & p0_all_active_outputs_ready;
  assign or_11697 = ____state_13 | (____state_11 ? ____state_13 : failed);
  assign one_hot_sel_11853 = unexpand_for_next_value_1744_0_case_0_case_3_case_2 & {2{concat_11852[0]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_3 & {2{concat_11852[1]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_2 & {2{concat_11852[2]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_3 & {2{concat_11852[3]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_2 & {2{concat_11852[4]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_1 & {2{concat_11852[5]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_1 & {2{concat_11852[6]}} | unexpand_for_next_value_1744_0_case_0_case_4_case_0 & {2{concat_11852[7]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_3 & {2{concat_11852[8]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_1 & {2{concat_11852[9]}} | unexpand_for_next_value_1744_0_case_0_case_4_case_0 & {2{concat_11852[10]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_2 & {2{concat_11852[11]}} | unexpand_for_next_value_1744_0_case_0_case_4_case_0 & {2{concat_11852[12]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_3 & {2{concat_11852[13]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_2 & {2{concat_11852[14]}} | unexpand_for_next_value_1744_0_case_0_case_3_case_1 & {2{concat_11852[15]}};
  assign and_11932 = (and_11471 | and_11472 | and_11473 | and_11474 | and_11475 | and_11476 | and_11477 | and_11478 | and_11479 | and_11467 | and_11480 | and_11464 | and_11481 | and_11465 | and_11454 | and_11482) & p0_all_active_outputs_ready;
  assign one_hot_sel_11860 = postponed_slot_tup0 & concat_11859[0] | invalid_repeat & concat_11859[1];
  assign and_11935 = (and_11483 | and_11484) & p0_all_active_outputs_ready;
  assign one_hot_sel_11870[0] = admitted_slots_tuple_idx_0[0] & concat_11869[0] | postponed_slots_tuple_idx_0[0] & concat_11869[1] | compacted_slots_tuple_idx_0[0] & concat_11869[2] | admitted_slots_tuple_idx_0[0] & concat_11869[3] | unblocked_slots_tuple_idx_0[0] & concat_11869[4];
  assign one_hot_sel_11870[1] = admitted_slots_tuple_idx_0[1] & concat_11869[0] | postponed_slots_tuple_idx_0[1] & concat_11869[1] | compacted_slots_tuple_idx_0[1] & concat_11869[2] | admitted_slots_tuple_idx_0[1] & concat_11869[3] | unblocked_slots_tuple_idx_0[1] & concat_11869[4];
  assign one_hot_sel_11870[2] = admitted_slots_tuple_idx_0[2] & concat_11869[0] | postponed_slots_tuple_idx_0[2] & concat_11869[1] | compacted_slots_tuple_idx_0[2] & concat_11869[2] | admitted_slots_tuple_idx_0[2] & concat_11869[3] | unblocked_slots_tuple_idx_0[2] & concat_11869[4];
  assign one_hot_sel_11870[3] = admitted_slots_tuple_idx_0[3] & concat_11869[0] | postponed_slots_tuple_idx_0[3] & concat_11869[1] | compacted_slots_tuple_idx_0[3] & concat_11869[2] | admitted_slots_tuple_idx_0[3] & concat_11869[3] | unblocked_slots_tuple_idx_0[3] & concat_11869[4];
  assign one_hot_sel_11870[4] = admitted_slots_tuple_idx_0[4] & concat_11869[0] | postponed_slots_tuple_idx_0[4] & concat_11869[1] | compacted_slots_tuple_idx_0[4] & concat_11869[2] | admitted_slots_tuple_idx_0[4] & concat_11869[3] | unblocked_slots_tuple_idx_0[4] & concat_11869[4];
  assign and_11938 = (nor_11443 | and_11485 | and_11486 | and_11487 | and_11488) & p0_all_active_outputs_ready;
  assign one_hot_sel_11883[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_11882[7]}};
  assign one_hot_sel_11883[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_11882[7]}};
  assign one_hot_sel_11883[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_11882[7]}};
  assign one_hot_sel_11883[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_11882[7]}};
  assign one_hot_sel_11883[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_11882[7]}};
  assign and_11941 = (and_11485 | and_11486 | and_11487 | and_11488 | and_11489 | and_11490 | and_11491 | and_11492) & p0_all_active_outputs_ready;
  assign one_hot_sel_11896[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_11882[7]}};
  assign one_hot_sel_11896[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_11882[7]}};
  assign one_hot_sel_11896[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_11882[7]}};
  assign one_hot_sel_11896[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_11882[7]}};
  assign one_hot_sel_11896[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_11882[7]}};
  assign __phenom_syndrome_cell__admit_not_stage_load = ~__phenom_syndrome_cell__admit_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__admit_has_been_sent_reg_load_en = __phenom_syndrome_cell__admit_valid_and_ready_txfr | __phenom_syndrome_cell__admit_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__east_not_stage_load = ~__phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__north_has_been_sent_reg_load_en = __phenom_syndrome_cell__north_valid_and_ready_txfr | __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__east_has_been_sent_reg_load_en = __phenom_syndrome_cell__east_valid_and_ready_txfr | __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__west_has_been_sent_reg_load_en = __phenom_syndrome_cell__west_valid_and_ready_txfr | __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__south_has_been_sent_reg_load_en = __phenom_syndrome_cell__south_valid_and_ready_txfr | __phenom_syndrome_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__phi_not_stage_load = ~__phenom_syndrome_cell__phi_valid_and_all_active_outputs_ready;
  assign __phenom_syndrome_cell__phi_has_been_sent_reg_load_en = __phenom_syndrome_cell__phi_valid_and_ready_txfr | __phenom_syndrome_cell__phi_valid_and_all_active_outputs_ready;
  assign effects_north = {literal_11214, {64'h0000_0000_0000_0008, ____state_2} & sign_ext_11540};
  assign effects_east = {literal_11214, {64'h0000_0000_0000_0004, ____state_2} & sign_ext_11540};
  assign effects_west = {literal_11214, {64'h0000_0000_0000_0002, ____state_2} & sign_ext_11540};
  assign effects_south = {literal_11214, {64'h0000_0000_0000_0001, ____state_2} & sign_ext_11540};
  assign effects_phi = {{8'h02, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {4'h0, array_index_11493[1], invalid_repeat, array_index_11493[0], invalid_repeat}}, {32'h0000_0000, ____state_6, ____state_2} & {96{eq_11437}}};
  assign or_12304 = ~p0_all_active_outputs_ready | concat_11376 == one_hot_12240[2:0] | reset;
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
      ____state_3 <= 32'h0000_0000;
      ____state_2 <= 32'h0000_0000;
      ____state_7 <= 32'h0000_0000;
      ____state_0 <= 2'h0;
      ____state_8 <= 32'h0000_0000;
      ____state_6 <= 32'h0000_0000;
      ____state_4 <= 32'h0000_0000;
      ____state_5 <= 1'h0;
      __phenom_syndrome_cell__admit_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__north_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__east_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__west_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__south_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__phi_has_been_sent_reg <= 1'h0;
      __phenom_syndrome_cell__req_reg <= __phenom_syndrome_cell__req_reg_init;
      __phenom_syndrome_cell__req_valid_reg <= 1'h0;
      __phenom_syndrome_cell__admit_reg <= 1'h0;
      __phenom_syndrome_cell__admit_valid_reg <= 1'h0;
      __phenom_syndrome_cell__north_reg <= __phenom_syndrome_cell__north_reg_init;
      __phenom_syndrome_cell__north_valid_reg <= 1'h0;
      __phenom_syndrome_cell__east_reg <= __phenom_syndrome_cell__east_reg_init;
      __phenom_syndrome_cell__east_valid_reg <= 1'h0;
      __phenom_syndrome_cell__west_reg <= __phenom_syndrome_cell__west_reg_init;
      __phenom_syndrome_cell__west_valid_reg <= 1'h0;
      __phenom_syndrome_cell__south_reg <= __phenom_syndrome_cell__south_reg_init;
      __phenom_syndrome_cell__south_valid_reg <= 1'h0;
      __phenom_syndrome_cell__phi_reg <= __phenom_syndrome_cell__phi_reg_init;
      __phenom_syndrome_cell__phi_valid_reg <= 1'h0;
    end else begin
      ____state_12 <= and_11928 ? one_hot_sel_11831 : ____state_12;
      ____state_13 <= p0_all_active_outputs_ready ? or_11697 : ____state_13;
      ____state_11 <= and_11925 ? and_11699 : ____state_11;
      ____state_9_tuple_element_0[0] <= and_11938 ? one_hot_sel_11870[0] : ____state_9_tuple_element_0[0];
      ____state_9_tuple_element_0[1] <= and_11938 ? one_hot_sel_11870[1] : ____state_9_tuple_element_0[1];
      ____state_9_tuple_element_0[2] <= and_11938 ? one_hot_sel_11870[2] : ____state_9_tuple_element_0[2];
      ____state_9_tuple_element_0[3] <= and_11938 ? one_hot_sel_11870[3] : ____state_9_tuple_element_0[3];
      ____state_9_tuple_element_0[4] <= and_11938 ? one_hot_sel_11870[4] : ____state_9_tuple_element_0[4];
      ____state_10 <= and_11923 ? one_hot_sel_11821 : ____state_10;
      ____state_9_tuple_element_1_tuple_element_1[0] <= and_11941 ? one_hot_sel_11883[0] : ____state_9_tuple_element_1_tuple_element_1[0];
      ____state_9_tuple_element_1_tuple_element_1[1] <= and_11941 ? one_hot_sel_11883[1] : ____state_9_tuple_element_1_tuple_element_1[1];
      ____state_9_tuple_element_1_tuple_element_1[2] <= and_11941 ? one_hot_sel_11883[2] : ____state_9_tuple_element_1_tuple_element_1[2];
      ____state_9_tuple_element_1_tuple_element_1[3] <= and_11941 ? one_hot_sel_11883[3] : ____state_9_tuple_element_1_tuple_element_1[3];
      ____state_9_tuple_element_1_tuple_element_1[4] <= and_11941 ? one_hot_sel_11883[4] : ____state_9_tuple_element_1_tuple_element_1[4];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_11941 ? one_hot_sel_11896[0] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_11941 ? one_hot_sel_11896[1] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_11941 ? one_hot_sel_11896[2] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_11941 ? one_hot_sel_11896[3] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_11941 ? one_hot_sel_11896[4] : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_3 <= and_11909 ? one_hot_sel_11788 : ____state_3;
      ____state_2 <= and_11906 ? Xls_clause_1_Seed_1 : ____state_2;
      ____state_7 <= and_11918 ? one_hot_sel_11811 : ____state_7;
      ____state_0 <= and_11932 ? one_hot_sel_11853 : ____state_0;
      ____state_8 <= and_11920 ? Xls_clause_1_Source_1 : ____state_8;
      ____state_6 <= and_11915 ? one_hot_sel_11804 : ____state_6;
      ____state_4 <= and_11909 ? one_hot_sel_11796 : ____state_4;
      ____state_5 <= and_11935 ? one_hot_sel_11860 : ____state_5;
      __phenom_syndrome_cell__admit_has_been_sent_reg <= __phenom_syndrome_cell__admit_has_been_sent_reg_load_en ? __phenom_syndrome_cell__admit_not_stage_load : __phenom_syndrome_cell__admit_has_been_sent_reg;
      __phenom_syndrome_cell__north_has_been_sent_reg <= __phenom_syndrome_cell__north_has_been_sent_reg_load_en ? __phenom_syndrome_cell__east_not_stage_load : __phenom_syndrome_cell__north_has_been_sent_reg;
      __phenom_syndrome_cell__east_has_been_sent_reg <= __phenom_syndrome_cell__east_has_been_sent_reg_load_en ? __phenom_syndrome_cell__east_not_stage_load : __phenom_syndrome_cell__east_has_been_sent_reg;
      __phenom_syndrome_cell__west_has_been_sent_reg <= __phenom_syndrome_cell__west_has_been_sent_reg_load_en ? __phenom_syndrome_cell__east_not_stage_load : __phenom_syndrome_cell__west_has_been_sent_reg;
      __phenom_syndrome_cell__south_has_been_sent_reg <= __phenom_syndrome_cell__south_has_been_sent_reg_load_en ? __phenom_syndrome_cell__east_not_stage_load : __phenom_syndrome_cell__south_has_been_sent_reg;
      __phenom_syndrome_cell__phi_has_been_sent_reg <= __phenom_syndrome_cell__phi_has_been_sent_reg_load_en ? __phenom_syndrome_cell__phi_not_stage_load : __phenom_syndrome_cell__phi_has_been_sent_reg;
      __phenom_syndrome_cell__req_reg <= phenom_syndrome_cell__req_load_en ? phenom_syndrome_cell__req : __phenom_syndrome_cell__req_reg;
      __phenom_syndrome_cell__req_valid_reg <= phenom_syndrome_cell__req_valid_load_en ? phenom_syndrome_cell__req_vld : __phenom_syndrome_cell__req_valid_reg;
      __phenom_syndrome_cell__admit_reg <= phenom_syndrome_cell__admit_load_en ? __phenom_syndrome_cell__admit_buf : __phenom_syndrome_cell__admit_reg;
      __phenom_syndrome_cell__admit_valid_reg <= phenom_syndrome_cell__admit_valid_load_en ? __phenom_syndrome_cell__admit_valid_and_not_has_been_sent : __phenom_syndrome_cell__admit_valid_reg;
      __phenom_syndrome_cell__north_reg <= phenom_syndrome_cell__north_load_en ? effects_north : __phenom_syndrome_cell__north_reg;
      __phenom_syndrome_cell__north_valid_reg <= phenom_syndrome_cell__north_valid_load_en ? __phenom_syndrome_cell__north_valid_and_not_has_been_sent : __phenom_syndrome_cell__north_valid_reg;
      __phenom_syndrome_cell__east_reg <= phenom_syndrome_cell__east_load_en ? effects_east : __phenom_syndrome_cell__east_reg;
      __phenom_syndrome_cell__east_valid_reg <= phenom_syndrome_cell__east_valid_load_en ? __phenom_syndrome_cell__east_valid_and_not_has_been_sent : __phenom_syndrome_cell__east_valid_reg;
      __phenom_syndrome_cell__west_reg <= phenom_syndrome_cell__west_load_en ? effects_west : __phenom_syndrome_cell__west_reg;
      __phenom_syndrome_cell__west_valid_reg <= phenom_syndrome_cell__west_valid_load_en ? __phenom_syndrome_cell__west_valid_and_not_has_been_sent : __phenom_syndrome_cell__west_valid_reg;
      __phenom_syndrome_cell__south_reg <= phenom_syndrome_cell__south_load_en ? effects_south : __phenom_syndrome_cell__south_reg;
      __phenom_syndrome_cell__south_valid_reg <= phenom_syndrome_cell__south_valid_load_en ? __phenom_syndrome_cell__south_valid_and_not_has_been_sent : __phenom_syndrome_cell__south_valid_reg;
      __phenom_syndrome_cell__phi_reg <= phenom_syndrome_cell__phi_load_en ? effects_phi : __phenom_syndrome_cell__phi_reg;
      __phenom_syndrome_cell__phi_valid_reg <= phenom_syndrome_cell__phi_valid_load_en ? __phenom_syndrome_cell__phi_valid_and_not_has_been_sent : __phenom_syndrome_cell__phi_valid_reg;
    end
  end
  assign phenom_syndrome_cell__admit = __phenom_syndrome_cell__admit_reg;
  assign phenom_syndrome_cell__admit_vld = __phenom_syndrome_cell__admit_valid_reg;
  assign phenom_syndrome_cell__east = __phenom_syndrome_cell__east_reg;
  assign phenom_syndrome_cell__east_vld = __phenom_syndrome_cell__east_valid_reg;
  assign phenom_syndrome_cell__north = __phenom_syndrome_cell__north_reg;
  assign phenom_syndrome_cell__north_vld = __phenom_syndrome_cell__north_valid_reg;
  assign phenom_syndrome_cell__phi = __phenom_syndrome_cell__phi_reg;
  assign phenom_syndrome_cell__phi_vld = __phenom_syndrome_cell__phi_valid_reg;
  assign phenom_syndrome_cell__req_rdy = phenom_syndrome_cell__req_load_en;
  assign phenom_syndrome_cell__south = __phenom_syndrome_cell__south_reg;
  assign phenom_syndrome_cell__south_vld = __phenom_syndrome_cell__south_valid_reg;
  assign phenom_syndrome_cell__west = __phenom_syndrome_cell__west_reg;
  assign phenom_syndrome_cell__west_vld = __phenom_syndrome_cell__west_valid_reg;
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_11296 == __i0 ? and_11295 : ____state_9_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_11296 == __i0 ? sel_11328 : ____state_9_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_11296 == __i0 ? sel_11346 : ____state_9_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_11638 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_11638 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_11638 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_12372;
  wire eq_12377;
  wire ne_12361;
  wire and_12378;
  wire or_12375;
  wire [2:0] add_12369;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12364;
  wire popped;
  wire [1:0] sub_12390;
  wire [1:0] add_12392;
  wire [2:0] umod_12370;
  wire [2:0] umod_12365;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12394;
  wire array_update_12401[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12372 = pop_ready & push_valid;
  assign eq_12377 = head == tail;
  assign ne_12361 = head != tail;
  assign and_12378 = eq_12377 & and_12372;
  assign or_12375 = ne_12361 | push_valid;
  assign add_12369 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12364 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12375;
  assign sub_12390 = slots - 2'h1;
  assign add_12392 = slots + 2'h1;
  assign umod_12370 = add_12369 % long_buf_size_lit;
  assign umod_12365 = add_12364 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12370[1:0];
  assign did_push_occur = (can_do_push | and_12372) & push_valid & ~and_12378 & ~is_full_bool;
  assign next_tail_if_pop = umod_12365[1:0];
  assign did_pop_occur = (ne_12361 | and_12372) & pop_ready & ~and_12378;
  assign sel_12394 = pushed ? (popped ? slots : add_12392) : (popped ? sub_12390 : slots);
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
      slots <= sel_12394;
      buf__1[0] <= did_push_occur ? array_update_12401[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12401[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12375;
  assign pop_data = eq_12377 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12401_0
    assign array_update_12401[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_12429;
  wire eq_12434;
  wire ne_12418;
  wire and_12435;
  wire or_12432;
  wire [2:0] add_12426;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12421;
  wire popped;
  wire [1:0] sub_12447;
  wire [1:0] add_12449;
  wire [2:0] umod_12427;
  wire [2:0] umod_12422;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12451;
  wire [127:0] array_update_12458[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12429 = pop_ready & push_valid;
  assign eq_12434 = head == tail;
  assign ne_12418 = head != tail;
  assign and_12435 = eq_12434 & and_12429;
  assign or_12432 = ne_12418 | push_valid;
  assign add_12426 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12421 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12432;
  assign sub_12447 = slots - 2'h1;
  assign add_12449 = slots + 2'h1;
  assign umod_12427 = add_12426 % long_buf_size_lit;
  assign umod_12422 = add_12421 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12427[1:0];
  assign did_push_occur = (can_do_push | and_12429) & push_valid & ~and_12435 & ~is_full_bool;
  assign next_tail_if_pop = umod_12422[1:0];
  assign did_pop_occur = (ne_12418 | and_12429) & pop_ready & ~and_12435;
  assign sel_12451 = pushed ? (popped ? slots : add_12449) : (popped ? sub_12447 : slots);
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
      slots <= sel_12451;
      buf__1[0] <= did_push_occur ? array_update_12458[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12458[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12432;
  assign pop_data = eq_12434 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12458_0
    assign array_update_12458[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_12486;
  wire eq_12491;
  wire ne_12475;
  wire and_12492;
  wire or_12489;
  wire [2:0] add_12483;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12478;
  wire popped;
  wire [1:0] sub_12504;
  wire [1:0] add_12506;
  wire [2:0] umod_12484;
  wire [2:0] umod_12479;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12508;
  wire [127:0] array_update_12515[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12486 = pop_ready & push_valid;
  assign eq_12491 = head == tail;
  assign ne_12475 = head != tail;
  assign and_12492 = eq_12491 & and_12486;
  assign or_12489 = ne_12475 | push_valid;
  assign add_12483 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12478 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12489;
  assign sub_12504 = slots - 2'h1;
  assign add_12506 = slots + 2'h1;
  assign umod_12484 = add_12483 % long_buf_size_lit;
  assign umod_12479 = add_12478 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12484[1:0];
  assign did_push_occur = (can_do_push | and_12486) & push_valid & ~and_12492 & ~is_full_bool;
  assign next_tail_if_pop = umod_12479[1:0];
  assign did_pop_occur = (ne_12475 | and_12486) & pop_ready & ~and_12492;
  assign sel_12508 = pushed ? (popped ? slots : add_12506) : (popped ? sub_12504 : slots);
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
      slots <= sel_12508;
      buf__1[0] <= did_push_occur ? array_update_12515[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12515[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12489;
  assign pop_data = eq_12491 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12515_0
    assign array_update_12515[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_12543;
  wire eq_12548;
  wire ne_12532;
  wire and_12549;
  wire or_12546;
  wire [2:0] add_12540;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12535;
  wire popped;
  wire [1:0] sub_12561;
  wire [1:0] add_12563;
  wire [2:0] umod_12541;
  wire [2:0] umod_12536;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12565;
  wire [127:0] array_update_12572[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12543 = pop_ready & push_valid;
  assign eq_12548 = head == tail;
  assign ne_12532 = head != tail;
  assign and_12549 = eq_12548 & and_12543;
  assign or_12546 = ne_12532 | push_valid;
  assign add_12540 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12535 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12546;
  assign sub_12561 = slots - 2'h1;
  assign add_12563 = slots + 2'h1;
  assign umod_12541 = add_12540 % long_buf_size_lit;
  assign umod_12536 = add_12535 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12541[1:0];
  assign did_push_occur = (can_do_push | and_12543) & push_valid & ~and_12549 & ~is_full_bool;
  assign next_tail_if_pop = umod_12536[1:0];
  assign did_pop_occur = (ne_12532 | and_12543) & pop_ready & ~and_12549;
  assign sel_12565 = pushed ? (popped ? slots : add_12563) : (popped ? sub_12561 : slots);
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
      slots <= sel_12565;
      buf__1[0] <= did_push_occur ? array_update_12572[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12572[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12546;
  assign pop_data = eq_12548 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12572_0
    assign array_update_12572[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_12600;
  wire eq_12605;
  wire ne_12589;
  wire and_12606;
  wire or_12603;
  wire [2:0] add_12597;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12592;
  wire popped;
  wire [1:0] sub_12618;
  wire [1:0] add_12620;
  wire [2:0] umod_12598;
  wire [2:0] umod_12593;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12622;
  wire [127:0] array_update_12629[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12600 = pop_ready & push_valid;
  assign eq_12605 = head == tail;
  assign ne_12589 = head != tail;
  assign and_12606 = eq_12605 & and_12600;
  assign or_12603 = ne_12589 | push_valid;
  assign add_12597 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12592 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12603;
  assign sub_12618 = slots - 2'h1;
  assign add_12620 = slots + 2'h1;
  assign umod_12598 = add_12597 % long_buf_size_lit;
  assign umod_12593 = add_12592 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12598[1:0];
  assign did_push_occur = (can_do_push | and_12600) & push_valid & ~and_12606 & ~is_full_bool;
  assign next_tail_if_pop = umod_12593[1:0];
  assign did_pop_occur = (ne_12589 | and_12600) & pop_ready & ~and_12606;
  assign sel_12622 = pushed ? (popped ? slots : add_12620) : (popped ? sub_12618 : slots);
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
      slots <= sel_12622;
      buf__1[0] <= did_push_occur ? array_update_12629[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12629[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12603;
  assign pop_data = eq_12605 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12629_0
    assign array_update_12629[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_12657;
  wire eq_12662;
  wire ne_12646;
  wire and_12663;
  wire or_12660;
  wire [2:0] add_12654;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12649;
  wire popped;
  wire [1:0] sub_12675;
  wire [1:0] add_12677;
  wire [2:0] umod_12655;
  wire [2:0] umod_12650;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12679;
  wire [127:0] array_update_12686[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12657 = pop_ready & push_valid;
  assign eq_12662 = head == tail;
  assign ne_12646 = head != tail;
  assign and_12663 = eq_12662 & and_12657;
  assign or_12660 = ne_12646 | push_valid;
  assign add_12654 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12649 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12660;
  assign sub_12675 = slots - 2'h1;
  assign add_12677 = slots + 2'h1;
  assign umod_12655 = add_12654 % long_buf_size_lit;
  assign umod_12650 = add_12649 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12655[1:0];
  assign did_push_occur = (can_do_push | and_12657) & push_valid & ~and_12663 & ~is_full_bool;
  assign next_tail_if_pop = umod_12650[1:0];
  assign did_pop_occur = (ne_12646 | and_12657) & pop_ready & ~and_12663;
  assign sel_12679 = pushed ? (popped ? slots : add_12677) : (popped ? sub_12675 : slots);
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
      slots <= sel_12679;
      buf__1[0] <= did_push_occur ? array_update_12686[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12686[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12660;
  assign pop_data = eq_12662 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12686_0
    assign array_update_12686[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___5(
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
  wire and_12714;
  wire eq_12719;
  wire ne_12703;
  wire and_12720;
  wire or_12717;
  wire [2:0] add_12711;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_12706;
  wire popped;
  wire [1:0] sub_12732;
  wire [1:0] add_12734;
  wire [2:0] umod_12712;
  wire [2:0] umod_12707;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_12736;
  wire [127:0] array_update_12743[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_12714 = pop_ready & push_valid;
  assign eq_12719 = head == tail;
  assign ne_12703 = head != tail;
  assign and_12720 = eq_12719 & and_12714;
  assign or_12717 = ne_12703 | push_valid;
  assign add_12711 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_12706 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_12717;
  assign sub_12732 = slots - 2'h1;
  assign add_12734 = slots + 2'h1;
  assign umod_12712 = add_12711 % long_buf_size_lit;
  assign umod_12707 = add_12706 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_12712[1:0];
  assign did_push_occur = (can_do_push | and_12714) & push_valid & ~and_12720 & ~is_full_bool;
  assign next_tail_if_pop = umod_12707[1:0];
  assign did_pop_occur = (ne_12703 | and_12714) & pop_ready & ~and_12720;
  assign sel_12736 = pushed ? (popped ? slots : add_12734) : (popped ? sub_12732 : slots);
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
      slots <= sel_12736;
      buf__1[0] <= did_push_occur ? array_update_12743[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_12743[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_12717;
  assign pop_data = eq_12719 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_12743_0
    assign array_update_12743[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __phenom_syndrome_cell__Top_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_syndrome_cell__east_send_rdy,
  input wire [32:0] phenom_syndrome_cell__ext_recv,
  input wire phenom_syndrome_cell__ext_recv_vld,
  input wire phenom_syndrome_cell__north_send_rdy,
  input wire phenom_syndrome_cell__phi_send_rdy,
  input wire phenom_syndrome_cell__south_send_rdy,
  input wire phenom_syndrome_cell__west_send_rdy,
  output wire [32:0] phenom_syndrome_cell__east_send,
  output wire phenom_syndrome_cell__east_send_vld,
  output wire phenom_syndrome_cell__ext_recv_rdy,
  output wire [32:0] phenom_syndrome_cell__north_send,
  output wire phenom_syndrome_cell__north_send_vld,
  output wire [32:0] phenom_syndrome_cell__phi_send,
  output wire phenom_syndrome_cell__phi_send_vld,
  output wire [32:0] phenom_syndrome_cell__south_send,
  output wire phenom_syndrome_cell__south_send_vld,
  output wire [32:0] phenom_syndrome_cell__west_send,
  output wire phenom_syndrome_cell__west_send_vld
);
  wire instantiation_output_12118;
  wire instantiation_output_12143;
  wire [127:0] instantiation_output_12186;
  wire instantiation_output_12187;
  wire instantiation_output_12156;
  wire [32:0] instantiation_output_12160;
  wire instantiation_output_12161;
  wire instantiation_output_12131;
  wire [32:0] instantiation_output_12135;
  wire instantiation_output_12136;
  wire instantiation_output_12226;
  wire [32:0] instantiation_output_12230;
  wire instantiation_output_12231;
  wire instantiation_output_12207;
  wire [32:0] instantiation_output_12211;
  wire instantiation_output_12212;
  wire instantiation_output_12175;
  wire [32:0] instantiation_output_12179;
  wire instantiation_output_12180;
  wire instantiation_output_12110;
  wire instantiation_output_12111;
  wire [127:0] instantiation_output_12123;
  wire instantiation_output_12124;
  wire [127:0] instantiation_output_12148;
  wire instantiation_output_12149;
  wire [127:0] instantiation_output_12167;
  wire instantiation_output_12168;
  wire instantiation_output_12194;
  wire [127:0] instantiation_output_12199;
  wire instantiation_output_12200;
  wire [127:0] instantiation_output_12218;
  wire instantiation_output_12219;
  wire instantiation_output_12751;
  wire instantiation_output_12752;
  wire instantiation_output_12753;
  wire instantiation_output_12758;
  wire [127:0] instantiation_output_12759;
  wire instantiation_output_12760;
  wire instantiation_output_12765;
  wire [127:0] instantiation_output_12766;
  wire instantiation_output_12767;
  wire instantiation_output_12772;
  wire [127:0] instantiation_output_12773;
  wire instantiation_output_12774;
  wire instantiation_output_12779;
  wire [127:0] instantiation_output_12780;
  wire instantiation_output_12781;
  wire instantiation_output_12786;
  wire [127:0] instantiation_output_12787;
  wire instantiation_output_12788;
  wire instantiation_output_12793;
  wire [127:0] instantiation_output_12794;
  wire instantiation_output_12795;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phenom_syndrome_cell__admit(instantiation_output_12752),
    .phenom_syndrome_cell__admit_vld(instantiation_output_12753),
    .phenom_syndrome_cell__ext_recv(phenom_syndrome_cell__ext_recv),
    .phenom_syndrome_cell__ext_recv_vld(phenom_syndrome_cell__ext_recv_vld),
    .phenom_syndrome_cell__req_rdy(instantiation_output_12779),
    .phenom_syndrome_cell__admit_rdy(instantiation_output_12118),
    .phenom_syndrome_cell__ext_recv_rdy(instantiation_output_12143),
    .phenom_syndrome_cell__req(instantiation_output_12186),
    .phenom_syndrome_cell__req_vld(instantiation_output_12187),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phenom_syndrome_cell__north(instantiation_output_12766),
    .phenom_syndrome_cell__north_vld(instantiation_output_12767),
    .phenom_syndrome_cell__north_send_rdy(phenom_syndrome_cell__north_send_rdy),
    .phenom_syndrome_cell__north_rdy(instantiation_output_12156),
    .phenom_syndrome_cell__north_send(instantiation_output_12160),
    .phenom_syndrome_cell__north_send_vld(instantiation_output_12161),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phenom_syndrome_cell__east(instantiation_output_12759),
    .phenom_syndrome_cell__east_vld(instantiation_output_12760),
    .phenom_syndrome_cell__east_send_rdy(phenom_syndrome_cell__east_send_rdy),
    .phenom_syndrome_cell__east_rdy(instantiation_output_12131),
    .phenom_syndrome_cell__east_send(instantiation_output_12135),
    .phenom_syndrome_cell__east_send_vld(instantiation_output_12136),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phenom_syndrome_cell__west(instantiation_output_12794),
    .phenom_syndrome_cell__west_vld(instantiation_output_12795),
    .phenom_syndrome_cell__west_send_rdy(phenom_syndrome_cell__west_send_rdy),
    .phenom_syndrome_cell__west_rdy(instantiation_output_12226),
    .phenom_syndrome_cell__west_send(instantiation_output_12230),
    .phenom_syndrome_cell__west_send_vld(instantiation_output_12231),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phenom_syndrome_cell__south(instantiation_output_12787),
    .phenom_syndrome_cell__south_vld(instantiation_output_12788),
    .phenom_syndrome_cell__south_send_rdy(phenom_syndrome_cell__south_send_rdy),
    .phenom_syndrome_cell__south_rdy(instantiation_output_12207),
    .phenom_syndrome_cell__south_send(instantiation_output_12211),
    .phenom_syndrome_cell__south_send_vld(instantiation_output_12212),
    .clk(clk)
  );
  __axis__Top__Tx_4_next __axis__Top__Tx_4_next_inst5 (
    .reset(reset),
    .phenom_syndrome_cell__phi(instantiation_output_12773),
    .phenom_syndrome_cell__phi_vld(instantiation_output_12774),
    .phenom_syndrome_cell__phi_send_rdy(phenom_syndrome_cell__phi_send_rdy),
    .phenom_syndrome_cell__phi_rdy(instantiation_output_12175),
    .phenom_syndrome_cell__phi_send(instantiation_output_12179),
    .phenom_syndrome_cell__phi_send_vld(instantiation_output_12180),
    .clk(clk)
  );
  __phenom_syndrome_cell__Top_0_next__1 __phenom_syndrome_cell__Top_0_next__1_inst6 (
    .reset(reset),
    .clk(clk)
  );
  __phenom_syndrome_cell__Top__Service_0_next __phenom_syndrome_cell__Top__Service_0_next_inst7 (
    .reset(reset),
    .phenom_syndrome_cell__admit_rdy(instantiation_output_12751),
    .phenom_syndrome_cell__east_rdy(instantiation_output_12758),
    .phenom_syndrome_cell__north_rdy(instantiation_output_12765),
    .phenom_syndrome_cell__phi_rdy(instantiation_output_12772),
    .phenom_syndrome_cell__req(instantiation_output_12780),
    .phenom_syndrome_cell__req_vld(instantiation_output_12781),
    .phenom_syndrome_cell__south_rdy(instantiation_output_12786),
    .phenom_syndrome_cell__west_rdy(instantiation_output_12793),
    .phenom_syndrome_cell__admit(instantiation_output_12110),
    .phenom_syndrome_cell__admit_vld(instantiation_output_12111),
    .phenom_syndrome_cell__east(instantiation_output_12123),
    .phenom_syndrome_cell__east_vld(instantiation_output_12124),
    .phenom_syndrome_cell__north(instantiation_output_12148),
    .phenom_syndrome_cell__north_vld(instantiation_output_12149),
    .phenom_syndrome_cell__phi(instantiation_output_12167),
    .phenom_syndrome_cell__phi_vld(instantiation_output_12168),
    .phenom_syndrome_cell__req_rdy(instantiation_output_12194),
    .phenom_syndrome_cell__south(instantiation_output_12199),
    .phenom_syndrome_cell__south_vld(instantiation_output_12200),
    .phenom_syndrome_cell__west(instantiation_output_12218),
    .phenom_syndrome_cell__west_vld(instantiation_output_12219),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phenom_syndrome_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_12110),
    .push_valid(instantiation_output_12111),
    .pop_ready(instantiation_output_12118),
    .push_ready(instantiation_output_12751),
    .pop_data(instantiation_output_12752),
    .pop_valid(instantiation_output_12753),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phenom_syndrome_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_12123),
    .push_valid(instantiation_output_12124),
    .pop_ready(instantiation_output_12131),
    .push_ready(instantiation_output_12758),
    .pop_data(instantiation_output_12759),
    .pop_valid(instantiation_output_12760),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phenom_syndrome_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_12148),
    .push_valid(instantiation_output_12149),
    .pop_ready(instantiation_output_12156),
    .push_ready(instantiation_output_12765),
    .pop_data(instantiation_output_12766),
    .pop_valid(instantiation_output_12767),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phenom_syndrome_cell__phi_ (
    .reset(reset),
    .push_data(instantiation_output_12167),
    .push_valid(instantiation_output_12168),
    .pop_ready(instantiation_output_12175),
    .push_ready(instantiation_output_12772),
    .pop_data(instantiation_output_12773),
    .pop_valid(instantiation_output_12774),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phenom_syndrome_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_12186),
    .push_valid(instantiation_output_12187),
    .pop_ready(instantiation_output_12194),
    .push_ready(instantiation_output_12779),
    .pop_data(instantiation_output_12780),
    .pop_valid(instantiation_output_12781),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phenom_syndrome_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_12199),
    .push_valid(instantiation_output_12200),
    .pop_ready(instantiation_output_12207),
    .push_ready(instantiation_output_12786),
    .pop_data(instantiation_output_12787),
    .pop_valid(instantiation_output_12788),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___5 materialized_fifo_fifo_phenom_syndrome_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_12218),
    .push_valid(instantiation_output_12219),
    .pop_ready(instantiation_output_12226),
    .push_ready(instantiation_output_12793),
    .pop_data(instantiation_output_12794),
    .pop_valid(instantiation_output_12795),
    .clk(clk)
  );
  assign phenom_syndrome_cell__east_send = instantiation_output_12135;
  assign phenom_syndrome_cell__east_send_vld = instantiation_output_12136;
  assign phenom_syndrome_cell__ext_recv_rdy = instantiation_output_12143;
  assign phenom_syndrome_cell__north_send = instantiation_output_12160;
  assign phenom_syndrome_cell__north_send_vld = instantiation_output_12161;
  assign phenom_syndrome_cell__phi_send = instantiation_output_12179;
  assign phenom_syndrome_cell__phi_send_vld = instantiation_output_12180;
  assign phenom_syndrome_cell__south_send = instantiation_output_12211;
  assign phenom_syndrome_cell__south_send_vld = instantiation_output_12212;
  assign phenom_syndrome_cell__west_send = instantiation_output_12230;
  assign phenom_syndrome_cell__west_send_vld = instantiation_output_12231;
endmodule
