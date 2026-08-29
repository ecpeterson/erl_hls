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
  wire [32:0] literal_7904 = {1'h0, 32'h0000_0000};
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
  wire and_7914;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_7913;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_7926;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_9506;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_9505;
  wire [31:0] sel_9504;
  wire [31:0] sel_9503;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_7971;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_9515;
  wire nand_7942;
  wire [127:0] one_hot_sel_7972;
  wire and_7986;
  wire [7:0] one_hot_sel_7979;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_7904;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_7914 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_7914;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_7913 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_7914;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_7913, and_7914};
  assign one_hot_7926 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_9506 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_9505 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_9504 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_9503 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_7913 == one_hot_7926[1] & and_7914 == one_hot_7926[0];
  assign concat_7971 = {nor_7913 & p0_stage_done, and_7914 & p0_stage_done};
  assign payload = {sel_9505, sel_9504, sel_9503, sel_9506};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_9515 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_7942 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_7972 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_7971[0]}} | payload & {128{concat_7971[1]}};
  assign and_7986 = (nor_7913 | and_7914) & p0_stage_done;
  assign one_hot_sel_7979 = 8'h00 & {8{concat_7971[0]}} | words_seen & {8{concat_7971[1]}};
  assign __phi_halo_cell__req_buf = {{sel_9506[7:0], sel_9506[15:8], sel_9506[23:16], sel_9506[31:24]}, {sel_9505, sel_9504, sel_9503}};
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
      ____state_0 <= p0_stage_done ? nand_7942 : ____state_0;
      ____state_2 <= and_7986 ? one_hot_sel_7979 : ____state_2;
      ____state_1 <= and_7986 ? one_hot_sel_7972 : ____state_1;
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
  wire [127:0] literal_8042 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8054;
  wire not_8055;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_8064;
  wire [2:0] one_hot_8065;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_8104;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8107;
  wire [127:0] payload;
  wire [1:0] concat_8120;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_9519;
  wire or_9523;
  wire [7:0] one_hot_sel_8108;
  wire and_8128;
  wire [127:0] one_hot_sel_8115;
  wire [7:0] one_hot_sel_8121;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_8042;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_8054 = ~(last | ____state_0);
  assign not_8055 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8054};
  assign ____state_6__next_value_predicates = {not_8055, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_8064 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8065 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_8104 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8064[1] & nor_8054 == one_hot_8064[0];
  assign ____state_6__at_most_one_next_value = not_8055 == one_hot_8065[1] & last == one_hot_8065[0];
  assign concat_8107 = {and_8104, nor_8054 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8120 = {not_8055 & p0_stage_done, and_8104};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_9519 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9523 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8108 = frame_header_payload_words__1 & {8{concat_8107[0]}} | 8'h00 & {8{concat_8107[1]}};
  assign and_8128 = (last | nor_8054) & p0_stage_done;
  assign one_hot_sel_8115 = payload & {128{concat_8107[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8107[1]}};
  assign one_hot_sel_8121 = 8'h00 & {8{concat_8120[0]}} | beats_sent & {8{concat_8120[1]}};
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
      ____state_0 <= p0_stage_done ? not_8055 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8121 : ____state_6;
      ____state_1 <= and_8128 ? one_hot_sel_8108 : ____state_1;
      ____state_5 <= and_8128 ? one_hot_sel_8115 : ____state_5;
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
  wire [127:0] literal_8177 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8189;
  wire not_8190;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_8199;
  wire [2:0] one_hot_8200;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_8239;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8242;
  wire [127:0] payload;
  wire [1:0] concat_8255;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_9525;
  wire or_9529;
  wire [7:0] one_hot_sel_8243;
  wire and_8263;
  wire [127:0] one_hot_sel_8250;
  wire [7:0] one_hot_sel_8256;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_8177;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_8189 = ~(last | ____state_0);
  assign not_8190 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8189};
  assign ____state_6__next_value_predicates = {not_8190, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_8199 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8200 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_8239 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8199[1] & nor_8189 == one_hot_8199[0];
  assign ____state_6__at_most_one_next_value = not_8190 == one_hot_8200[1] & last == one_hot_8200[0];
  assign concat_8242 = {and_8239, nor_8189 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8255 = {not_8190 & p0_stage_done, and_8239};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_9525 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9529 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8243 = frame_header_payload_words__1 & {8{concat_8242[0]}} | 8'h00 & {8{concat_8242[1]}};
  assign and_8263 = (last | nor_8189) & p0_stage_done;
  assign one_hot_sel_8250 = payload & {128{concat_8242[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8242[1]}};
  assign one_hot_sel_8256 = 8'h00 & {8{concat_8255[0]}} | beats_sent & {8{concat_8255[1]}};
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
      ____state_0 <= p0_stage_done ? not_8190 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8256 : ____state_6;
      ____state_1 <= and_8263 ? one_hot_sel_8243 : ____state_1;
      ____state_5 <= and_8263 ? one_hot_sel_8250 : ____state_5;
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
  wire [127:0] literal_8312 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8324;
  wire not_8325;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_8334;
  wire [2:0] one_hot_8335;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_8374;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8377;
  wire [127:0] payload;
  wire [1:0] concat_8390;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_9531;
  wire or_9535;
  wire [7:0] one_hot_sel_8378;
  wire and_8398;
  wire [127:0] one_hot_sel_8385;
  wire [7:0] one_hot_sel_8391;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_8312;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_8324 = ~(last | ____state_0);
  assign not_8325 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8324};
  assign ____state_6__next_value_predicates = {not_8325, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_8334 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8335 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_8374 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8334[1] & nor_8324 == one_hot_8334[0];
  assign ____state_6__at_most_one_next_value = not_8325 == one_hot_8335[1] & last == one_hot_8335[0];
  assign concat_8377 = {and_8374, nor_8324 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8390 = {not_8325 & p0_stage_done, and_8374};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_9531 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9535 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8378 = frame_header_payload_words__1 & {8{concat_8377[0]}} | 8'h00 & {8{concat_8377[1]}};
  assign and_8398 = (last | nor_8324) & p0_stage_done;
  assign one_hot_sel_8385 = payload & {128{concat_8377[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8377[1]}};
  assign one_hot_sel_8391 = 8'h00 & {8{concat_8390[0]}} | beats_sent & {8{concat_8390[1]}};
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
      ____state_0 <= p0_stage_done ? not_8325 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8391 : ____state_6;
      ____state_1 <= and_8398 ? one_hot_sel_8378 : ____state_1;
      ____state_5 <= and_8398 ? one_hot_sel_8385 : ____state_5;
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
  wire [127:0] literal_8447 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_8459;
  wire not_8460;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_8469;
  wire [2:0] one_hot_8470;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_8509;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8512;
  wire [127:0] payload;
  wire [1:0] concat_8525;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_9537;
  wire or_9541;
  wire [7:0] one_hot_sel_8513;
  wire and_8533;
  wire [127:0] one_hot_sel_8520;
  wire [7:0] one_hot_sel_8526;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_8447;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_8459 = ~(last | ____state_0);
  assign not_8460 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8459};
  assign ____state_6__next_value_predicates = {not_8460, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_8469 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8470 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_8509 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8469[1] & nor_8459 == one_hot_8469[0];
  assign ____state_6__at_most_one_next_value = not_8460 == one_hot_8470[1] & last == one_hot_8470[0];
  assign concat_8512 = {and_8509, nor_8459 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8525 = {not_8460 & p0_stage_done, and_8509};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_9537 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9541 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8513 = frame_header_payload_words__1 & {8{concat_8512[0]}} | 8'h00 & {8{concat_8512[1]}};
  assign and_8533 = (last | nor_8459) & p0_stage_done;
  assign one_hot_sel_8520 = payload & {128{concat_8512[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8512[1]}};
  assign one_hot_sel_8526 = 8'h00 & {8{concat_8525[0]}} | beats_sent & {8{concat_8525[1]}};
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
      ____state_0 <= p0_stage_done ? not_8460 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8526 : ____state_6;
      ____state_1 <= and_8533 ? one_hot_sel_8513 : ____state_1;
      ____state_5 <= and_8533 ? one_hot_sel_8520 : ____state_5;
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
  wire [127:0] literal_8635 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  reg ____state_7;
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
  wire nor_8633;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire tag_ok;
  wire accepted;
  wire [7:0] and_8658;
  wire [31:0] concat_8659;
  wire [7:0] admitted_slots_tuple_idx_1[0:4];
  wire [6:0] leading_bits___state_0;
  wire and_8662;
  wire [7:0] blocked_phase__4;
  wire [7:0] blocked_phase__3;
  wire admitted_slots_tuple_idx_0[0:4];
  wire [7:0] blocked_phase__2;
  wire [7:0] admitted_occupied;
  wire postponed__4;
  wire [7:0] blocked_phase__1;
  wire postponed__3;
  wire ugt_8684;
  wire [7:0] blocked_phase;
  wire postponed__2;
  wire or_reduce_8692;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_1;
  wire postponed__1;
  wire ugt_8701;
  wire eligible_3;
  wire [7:0] compacted_4_tup1;
  wire postponed;
  wire or_reduce_8708;
  wire eligible_2;
  wire eligible_1;
  wire eligible_0;
  wire [7:0] sel_8724;
  wire [7:0] selected;
  wire [7:0] admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0:4];
  wire [2:0] bit_slice_8729;
  wire [95:0] sel_8730;
  wire [7:0] selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3;
  wire [95:0] admitted_slots_tuple_idx_2_tuple_idx_1[0:4];
  wire eq_8733;
  wire eq_8735;
  wire [95:0] selected_slot_tuple_idx_2_tuple_idx_1;
  wire [31:0] eventstep_1;
  wire [31:0] _1__1;
  wire and_8743;
  wire nor_8744;
  wire nor_8749;
  wire and_8750;
  wire _3__1;
  wire _1__2;
  wire validpresent_1;
  wire invalid_input;
  wire postponed_slot_tup0;
  wire [2:0] concat_8761;
  wire compacted_4_tup0;
  wire found;
  wire priority_sel_8766;
  wire one_hot_sel_9513;
  wire effective;
  wire ready_1;
  wire [1:0] directive;
  wire ready_1__1;
  wire nand_8765;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_8796;
  wire candidate_slots_0_case_cmp;
  wire failed;
  wire [7:0] candidate_occupied;
  wire [7:0] MAILBOX_CAPACITY;
  wire candidate_phase_squeezed;
  wire phase_changed;
  wire reserve__1;
  wire reserve;
  wire and_8784;
  wire and_8789;
  wire and_8791;
  wire nor_8792;
  wire nor_8795;
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
  wire nor_8802;
  wire candidate_occupied_0_case_cmp;
  wire and_8805;
  wire and_8807;
  wire and_8809;
  wire nor_8810;
  wire or_8811;
  wire nand_8812;
  wire and_8813;
  wire [31:0] value1_1;
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
  wire and_8821;
  wire and_8822;
  wire and_8824;
  wire and_8825;
  wire and_8826;
  wire and_8827;
  wire and_8828;
  wire and_8829;
  wire and_8830;
  wire and_8831;
  wire and_8832;
  wire and_8833;
  wire and_8834;
  wire and_8835;
  wire and_8836;
  wire and_8837;
  wire and_8838;
  wire and_8839;
  wire [31:0] value0_1;
  wire [31:0] _10;
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
  wire [31:0] _6;
  wire [31:0] _33;
  wire [2:0] one_hot_8884;
  wire [2:0] one_hot_8885;
  wire [6:0] one_hot_8886;
  wire [2:0] one_hot_8887;
  wire [2:0] one_hot_8888;
  wire [5:0] one_hot_8889;
  wire [8:0] one_hot_8890;
  wire [30:0] add_8847;
  wire [63:0] umul_8848;
  wire [7:0] sign_ext_8863;
  wire [7:0] sign_ext_8864;
  wire [7:0] sign_ext_8865;
  wire [7:0] sign_ext_8866;
  wire [95:0] array_index_8867;
  wire [95:0] array_index_8869;
  wire [95:0] array_index_8871;
  wire [7:0] array_index_8875;
  wire [7:0] array_index_8876;
  wire [7:0] array_index_8877;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_8881;
  wire ne_8899;
  wire or_reduce_8901;
  wire ugt_8903;
  wire [3:0] one_hot_9508;
  wire phi_halo_cell__req_valid_inv;
  wire admission_pending;
  wire [14:0] add_8921;
  wire and_9134;
  wire and_9136;
  wire and_9161;
  wire and_9162;
  wire and_9163;
  wire and_9164;
  wire [31:0] concat_8969;
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
  wire [1:0] concat_9105;
  wire [1:0] concat_9115;
  wire [31:0] _25;
  wire [31:0] _28;
  wire [30:0] add_8981;
  wire [31:0] sign_ext_8982;
  wire [5:0] concat_9139;
  wire [1:0] concat_9146;
  wire [1:0] unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_9153;
  wire [1:0] unexpand_for_next_value_1148_6__2_case_0_case_1_case_1_case_1_case_0;
  wire [4:0] concat_9166;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_9179;
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
  wire or_9543;
  wire or_9545;
  wire or_9547;
  wire or_9549;
  wire or_9551;
  wire or_9553;
  wire or_9555;
  wire and_9215;
  wire [7:0] one_hot_sel_9106;
  wire and_9218;
  wire and_9015;
  wire and_9220;
  wire one_hot_sel_9116;
  wire and_9223;
  wire or_9013;
  wire [31:0] _29;
  wire and_9226;
  wire [31:0] _35;
  wire [31:0] and_9031;
  wire and_9230;
  wire [31:0] and_9032;
  wire one_hot_sel_9140;
  wire and_9235;
  wire [1:0] one_hot_sel_9147;
  wire and_9238;
  wire [1:0] one_hot_sel_9154;
  wire and_9241;
  wire _7__2;
  wire and_9243;
  wire one_hot_sel_9167[0:4];
  wire and_9246;
  wire [7:0] one_hot_sel_9180[0:4];
  wire and_9249;
  wire [95:0] one_hot_sel_9193[0:4];
  wire [7:0] one_hot_sel_9206[0:4];
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_not_stage_load;
  wire __phi_halo_cell__north_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_has_been_sent_reg_load_en;
  wire __phi_halo_cell__west_has_been_sent_reg_load_en;
  wire __phi_halo_cell__south_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire or_9561;
  assign nor_8633 = ~(____state_12 | ____state_10 | ~____state_11);
  assign received = nor_8633 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_8635;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign tag_ok = frame_header_op == 8'h03 & frame_header__1_payload_words == 8'h03 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02;
  assign accepted = received & tag_ok;
  assign and_8658 = ____state_8_tuple_element_1[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]] & {8{~accepted}};
  assign concat_8659 = {24'h00_0000, ____state_9};
  assign leading_bits___state_0 = 7'h00;
  assign and_8662 = ~accepted & ____state_8_tuple_element_0[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign blocked_phase__4 = admitted_slots_tuple_idx_1[3'h4];
  assign blocked_phase__3 = admitted_slots_tuple_idx_1[3'h3];
  assign blocked_phase__2 = admitted_slots_tuple_idx_1[3'h2];
  assign admitted_occupied = ____state_9 + {leading_bits___state_0, accepted};
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign blocked_phase__1 = admitted_slots_tuple_idx_1[3'h1];
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign ugt_8684 = admitted_occupied > 8'h04;
  assign blocked_phase = admitted_slots_tuple_idx_1[3'h0];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign or_reduce_8692 = |admitted_occupied[7:2];
  assign eligible_4 = ugt_8684 & ~(postponed__4 & blocked_phase__4[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__4[0]);
  assign unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_1 = 2'h0;
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign ugt_8701 = admitted_occupied > 8'h02;
  assign eligible_3 = or_reduce_8692 & ~(postponed__3 & blocked_phase__3[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__3[0]);
  assign compacted_4_tup1 = 8'h00;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign or_reduce_8708 = |admitted_occupied[7:1];
  assign eligible_2 = ugt_8701 & ~(postponed__2 & blocked_phase__2[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__2[0]);
  assign eligible_1 = or_reduce_8708 & ~(postponed__1 & blocked_phase__1[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase__1[0]);
  assign eligible_0 = admitted_occupied != compacted_4_tup1 & ~(postponed & blocked_phase[7:1] == leading_bits___state_0 & ____state_0 == blocked_phase[0]);
  assign sel_8724 = accepted ? frame_header_op : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_1}))} & {8{~eligible_0}};
  assign bit_slice_8729 = selected[2:0];
  assign sel_8730 = accepted ? phi_halo_cell__req_select[95:0] : ____state_8_tuple_element_2_tuple_element_1[____state_9 > 8'h04 ? 3'h4 : ____state_9[2:0]];
  assign selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[bit_slice_8729 > 3'h4 ? 3'h4 : bit_slice_8729];
  assign eq_8733 = selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign eq_8735 = selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign selected_slot_tuple_idx_2_tuple_idx_1 = admitted_slots_tuple_idx_2_tuple_idx_1[bit_slice_8729 > 3'h4 ? 3'h4 : bit_slice_8729];
  assign eventstep_1 = selected_slot_tuple_idx_2_tuple_idx_1[31:0];
  assign _1__1 = ____state_2 + 32'h0000_0001;
  assign and_8743 = eq_8735 & ____state_0;
  assign nor_8744 = ~(~eq_8733 | ____state_0);
  assign nor_8749 = ~(~eq_8735 | ____state_0);
  assign and_8750 = eq_8733 & ____state_0;
  assign _3__1 = eventstep_1 == _1__1;
  assign _1__2 = eventstep_1 == ____state_2;
  assign validpresent_1 = selected_slot_tuple_idx_2_tuple_idx_1[63:33] == 31'h0000_0000;
  assign invalid_input = received & ~tag_ok;
  assign postponed_slot_tup0 = 1'h1;
  assign concat_8761 = {nor_8749, and_8743 | nor_8744, and_8750};
  assign compacted_4_tup0 = 1'h0;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign priority_sel_8766 = priority_sel_1b_4way({nor_8749, and_8743, nor_8744, and_8750}, ~_3__1, ~_1__2, ~(_1__2 & validpresent_1), ~_1__2, postponed_slot_tup0);
  assign one_hot_sel_9513 = _3__1 & concat_8761[0] | compacted_4_tup0 & concat_8761[1] | _1__2 & concat_8761[2];
  assign effective = found & ~invalid_input;
  assign ready_1 = ____state_5 == 2'h3;
  assign directive = {priority_sel_8766, one_hot_sel_9513} & {2{effective}};
  assign ready_1__1 = ____state_6 == 2'h3;
  assign nand_8765 = ~(_1__2 & validpresent_1 & ready_1__1);
  assign transition_slots_predicate_piece_0 = ~(directive[0] | directive[1]);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_8796 = admitted_occupied + 8'hff;
  assign candidate_slots_0_case_cmp = ~effective;
  assign failed = invalid_input | directive[1];
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_8796 : admitted_occupied;
  assign MAILBOX_CAPACITY = 8'h05;
  assign candidate_phase_squeezed = effective ? priority_sel_1b_2way({eq_8735, eq_8733}, ____state_0 | ~(____state_0 | ~_1__2 | ~ready_1), ____state_0 & nand_8765, ____state_0) : ____state_0;
  assign phase_changed = candidate_phase_squeezed ^ ____state_0;
  assign reserve__1 = ~failed & ~received & ~(____state_11 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_11 | ____state_9 > 8'h04);
  assign and_8784 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8735;
  assign and_8789 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8733;
  assign and_8791 = and_8784 & ____state_0;
  assign nor_8792 = ~(____state_12 | ____state_10 | phase_changed);
  assign nor_8795 = ~(____state_12 | ____state_10 | ~phase_changed);
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
  assign nor_8802 = ~(____state_12 | ____state_10);
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_8805 = and_8789 & ~____state_0;
  assign and_8807 = and_8791 & _1__2 & validpresent_1;
  assign and_8809 = nor_8792 & effective;
  assign nor_8810 = ~(priority_sel_8766 | ~one_hot_sel_9513);
  assign or_8811 = directive[0] | directive[1];
  assign nand_8812 = ~(~priority_sel_8766 & one_hot_sel_9513);
  assign and_8813 = nor_8795 & effective;
  assign value1_1 = selected_slot_tuple_idx_2_tuple_idx_1[63:32];
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
  assign and_8821 = nor_8802 & candidate_occupied_0_case_cmp;
  assign and_8822 = nor_8802 & candidate_occupied_1_case_cmp;
  assign and_8824 = and_8789 & ____state_0;
  assign and_8825 = and_8784 & ~____state_0;
  assign and_8826 = and_8805 & _1__2 & ready_1;
  assign and_8827 = and_8805 & ~(_1__2 & ready_1);
  assign and_8828 = and_8791 & _1__2 & validpresent_1 & ready_1__1;
  assign and_8829 = and_8791 & nand_8765;
  assign and_8830 = and_8805 & _1__2 & ~ready_1;
  assign and_8831 = and_8807 & ~ready_1__1;
  assign and_8832 = nor_8792 & candidate_slots_0_case_cmp;
  assign and_8833 = and_8809 & transition_slots_predicate_piece_0;
  assign and_8834 = and_8809 & nor_8810 & or_8811;
  assign and_8835 = and_8809 & nand_8812 & or_8811;
  assign and_8836 = nor_8795 & candidate_slots_0_case_cmp;
  assign and_8837 = and_8813 & transition_slots_predicate_piece_0;
  assign and_8838 = and_8813 & nor_8810 & or_8811;
  assign and_8839 = and_8813 & nand_8812 & or_8811;
  assign value0_1 = selected_slot_tuple_idx_2_tuple_idx_1[95:64];
  assign _10 = ____state_4_1 + value1_1;
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_9__next_value_predicates = {and_8821, and_8822};
  assign ____state_11__next_value_predicates = {nor_8802, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_8824, and_8825, and_8826, and_8827, and_8828, and_8829};
  assign ____state_5__next_value_predicates = {and_8830, and_8826};
  assign ____state_6__next_value_predicates = {and_8831, and_8828};
  assign ____state_8_tuple_element_0__next_value_predicates = {nor_8795, and_8832, and_8833, and_8834, and_8835};
  assign ____state_8_tuple_element_1__next_value_predicates = {and_8832, and_8833, and_8834, and_8835, and_8836, and_8837, and_8838, and_8839};
  assign _6 = ____state_4_0 + value0_1;
  assign _33 = ____state_3_0 + _10;
  assign one_hot_8884 = {____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_8885 = {____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_8886 = {____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_8887 = {____state_5__next_value_predicates[1:0] == 2'h0, ____state_5__next_value_predicates[1] && !____state_5__next_value_predicates[0], ____state_5__next_value_predicates[0]};
  assign one_hot_8888 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_8889 = {____state_8_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_8_tuple_element_0__next_value_predicates[4] && ____state_8_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_8_tuple_element_0__next_value_predicates[3] && ____state_8_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_8_tuple_element_0__next_value_predicates[2] && ____state_8_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_8_tuple_element_0__next_value_predicates[1] && !____state_8_tuple_element_0__next_value_predicates[0], ____state_8_tuple_element_0__next_value_predicates[0]};
  assign one_hot_8890 = {____state_8_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_8_tuple_element_1__next_value_predicates[7] && ____state_8_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_8_tuple_element_1__next_value_predicates[6] && ____state_8_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_8_tuple_element_1__next_value_predicates[5] && ____state_8_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_8_tuple_element_1__next_value_predicates[4] && ____state_8_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_8_tuple_element_1__next_value_predicates[3] && ____state_8_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_8_tuple_element_1__next_value_predicates[2] && ____state_8_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_8_tuple_element_1__next_value_predicates[1] && !____state_8_tuple_element_1__next_value_predicates[0], ____state_8_tuple_element_1__next_value_predicates[0]};
  assign add_8847 = ____state_3_1[31:1] + ____state_3_1[30:0];
  assign umul_8848 = umul64b_32b_x_32b(_33, 32'hcccc_cccd);
  assign sign_ext_8863 = {8{or_reduce_8708}};
  assign sign_ext_8864 = {8{ugt_8701}};
  assign sign_ext_8865 = {8{or_reduce_8692}};
  assign sign_ext_8866 = {8{ugt_8684}};
  assign array_index_8867 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h1];
  assign array_index_8869 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h2];
  assign array_index_8871 = admitted_slots_tuple_idx_2_tuple_idx_1[3'h3];
  assign array_index_8875 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_8876 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_8877 = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_8881 = ____state_3_1[30:0] + _6[31:1];
  assign ne_8899 = bit_slice_8729 != 3'h0;
  assign or_reduce_8901 = |selected[7:1];
  assign ugt_8903 = bit_slice_8729 > 3'h2;
  assign one_hot_9508 = {concat_8761[2:0] == 3'h0, concat_8761[2] && concat_8761[1:0] == 2'h0, concat_8761[1] && !concat_8761[0], concat_8761[0]};
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign admission_pending = ~(~____state_11 | received);
  assign add_8921 = {14'h0000, ____state_7} + {compacted_4_tup0, ____state_3_0[31:18]};
  assign and_9134 = and_8826 & p0_all_active_outputs_ready;
  assign and_9136 = and_8828 & p0_all_active_outputs_ready;
  assign and_9161 = and_8832 & p0_all_active_outputs_ready;
  assign and_9162 = and_8833 & p0_all_active_outputs_ready;
  assign and_9163 = and_8834 & p0_all_active_outputs_ready;
  assign and_9164 = and_8835 & p0_all_active_outputs_ready;
  assign concat_8969 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_8899 ? postponed : or_reduce_8708 & postponed__1;
  assign compacted_1_tup0 = or_reduce_8901 ? postponed__1 : ugt_8701 & postponed__2;
  assign compacted_2_tup0 = ugt_8903 ? postponed__2 : or_reduce_8692 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_8684 & postponed__4;
  assign extended___state_0 = {leading_bits___state_0, ____state_0};
  assign compacted_0_tup1 = ne_8899 ? blocked_phase : blocked_phase__1 & sign_ext_8863;
  assign compacted_1_tup1 = or_reduce_8901 ? blocked_phase__1 : blocked_phase__2 & sign_ext_8864;
  assign compacted_2_tup1 = ugt_8903 ? blocked_phase__2 : blocked_phase__3 & sign_ext_8865;
  assign compacted_3_tup1 = selected[2] ? blocked_phase__3 : blocked_phase__4 & sign_ext_8866;
  assign compacted_0_tup2_tup1 = ne_8899 ? admitted_slots_tuple_idx_2_tuple_idx_1[3'h0] : array_index_8867 & {96{or_reduce_8708}};
  assign compacted_1_tup2_tup1 = or_reduce_8901 ? array_index_8867 : array_index_8869 & {96{ugt_8701}};
  assign compacted_2_tup2_tup1 = ugt_8903 ? array_index_8869 : array_index_8871 & {96{or_reduce_8692}};
  assign compacted_3_tup2_tup1 = selected[2] ? array_index_8871 : admitted_slots_tuple_idx_2_tuple_idx_1[3'h4] & {96{ugt_8684}};
  assign compacted_4_tup2_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup2_tup0_tup3 = ne_8899 ? admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h0] : array_index_8875 & sign_ext_8863;
  assign compacted_1_tup2_tup0_tup3 = or_reduce_8901 ? array_index_8875 : array_index_8876 & sign_ext_8864;
  assign compacted_2_tup2_tup0_tup3 = ugt_8903 ? array_index_8876 : array_index_8877 & sign_ext_8865;
  assign compacted_3_tup2_tup0_tup3 = selected[2] ? array_index_8877 : admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3'h4] & sign_ext_8866;
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_8633 | phi_halo_cell__req_valid_inv;
  assign ____state_9__at_most_one_next_value = and_8821 == one_hot_8884[1] & and_8822 == one_hot_8884[0];
  assign ____state_11__at_most_one_next_value = nor_8802 == one_hot_8885[1] & __phi_halo_cell__east_vld_buf == one_hot_8885[0];
  assign ____state_0__at_most_one_next_value = and_8824 == one_hot_8886[5] & and_8825 == one_hot_8886[4] & and_8826 == one_hot_8886[3] & and_8827 == one_hot_8886[2] & and_8828 == one_hot_8886[1] & and_8829 == one_hot_8886[0];
  assign ____state_5__at_most_one_next_value = and_8830 == one_hot_8887[1] & and_8826 == one_hot_8887[0];
  assign ____state_6__at_most_one_next_value = and_8831 == one_hot_8888[1] & and_8828 == one_hot_8888[0];
  assign ____state_8_tuple_element_0__at_most_one_next_value = nor_8795 == one_hot_8889[4] & and_8832 == one_hot_8889[3] & and_8833 == one_hot_8889[2] & and_8834 == one_hot_8889[1] & and_8835 == one_hot_8889[0];
  assign ____state_8_tuple_element_1__at_most_one_next_value = and_8832 == one_hot_8890[7] & and_8833 == one_hot_8890[6] & and_8834 == one_hot_8890[5] & and_8835 == one_hot_8890[4] & and_8836 == one_hot_8890[3] & and_8837 == one_hot_8890[2] & and_8838 == one_hot_8890[1] & and_8839 == one_hot_8890[0];
  assign concat_9105 = {and_8821 & p0_all_active_outputs_ready, and_8822 & p0_all_active_outputs_ready};
  assign concat_9115 = {nor_8802 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _25 = {compacted_4_tup0, add_8921, ____state_3_0[17:2]};
  assign _28 = {3'h0, add_8881[30:2]};
  assign add_8981 = {compacted_4_tup0, add_8847[30:1]} + {3'h0, umul_8848[63:36]};
  assign sign_ext_8982 = {32{~ready_1}};
  assign concat_9139 = {and_8824 & p0_all_active_outputs_ready, and_8825 & p0_all_active_outputs_ready, and_9134, and_8827 & p0_all_active_outputs_ready, and_9136, and_8829 & p0_all_active_outputs_ready};
  assign concat_9146 = {and_8830 & p0_all_active_outputs_ready, and_9134};
  assign unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_0 = ____state_5 + 2'h1;
  assign concat_9153 = {and_8831 & p0_all_active_outputs_ready, and_9136};
  assign unexpand_for_next_value_1148_6__2_case_0_case_1_case_1_case_1_case_0 = ____state_6 + 2'h1;
  assign concat_9166 = {nor_8795 & p0_all_active_outputs_ready, and_9161, and_9162, and_9163, and_9164};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_9179 = {and_9161, and_9162, and_9163, and_9164, and_8836 & p0_all_active_outputs_ready, and_8837 & p0_all_active_outputs_ready, and_8838 & p0_all_active_outputs_ready, and_8839 & p0_all_active_outputs_ready};
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
  assign or_9543 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_9545 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_9547 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_9549 = ~p0_all_active_outputs_ready | ____state_5__at_most_one_next_value | reset;
  assign or_9551 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_9553 = ~p0_all_active_outputs_ready | ____state_8_tuple_element_0__at_most_one_next_value | reset;
  assign or_9555 = ~p0_all_active_outputs_ready | ____state_8_tuple_element_1__at_most_one_next_value | reset;
  assign and_9215 = and_8828 & p0_all_active_outputs_ready;
  assign one_hot_sel_9106 = add_8796 & {8{concat_9105[0]}} | admitted_occupied & {8{concat_9105[1]}};
  assign and_9218 = (and_8821 | and_8822) & p0_all_active_outputs_ready;
  assign and_9015 = ~____state_10 & effective & phase_changed & ~failed;
  assign and_9220 = ~____state_12 & p0_all_active_outputs_ready;
  assign one_hot_sel_9116 = (____state_11 | ____state_9 < MAILBOX_CAPACITY) & concat_9115[0] | (admission_pending | reserve__1) & concat_9115[1];
  assign and_9223 = (nor_8802 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_9013 = ____state_12 | (____state_10 ? ____state_12 : failed);
  assign _29 = _25 + _28;
  assign and_9226 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8733 & ~____state_0 & _1__2 & ready_1 & p0_all_active_outputs_ready;
  assign _35 = {compacted_4_tup0, add_8981};
  assign and_9031 = _6 & sign_ext_8982;
  assign and_9230 = ~(____state_12 | ____state_10 | candidate_slots_0_case_cmp) & eq_8733 & ~____state_0 & _1__2 & p0_all_active_outputs_ready;
  assign and_9032 = _10 & sign_ext_8982;
  assign one_hot_sel_9140 = postponed_slot_tup0 & concat_9139[0] | compacted_4_tup0 & concat_9139[1] | compacted_4_tup0 & concat_9139[2] | postponed_slot_tup0 & concat_9139[3] | compacted_4_tup0 & concat_9139[4] | postponed_slot_tup0 & concat_9139[5];
  assign and_9235 = (and_8824 | and_8825 | and_8826 | and_8827 | and_8828 | and_8829) & p0_all_active_outputs_ready;
  assign one_hot_sel_9147 = unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9146[0]}} | unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_9146[1]}};
  assign and_9238 = (and_8830 | and_8826) & p0_all_active_outputs_ready;
  assign one_hot_sel_9154 = unexpand_for_next_value_1148_5__2_case_0_case_0_case_0_case_1_case_1 & {2{concat_9153[0]}} | unexpand_for_next_value_1148_6__2_case_0_case_1_case_1_case_1_case_0 & {2{concat_9153[1]}};
  assign and_9241 = (and_8831 | and_8828) & p0_all_active_outputs_ready;
  assign _7__2 = ____state_7 ^ selected_slot_tuple_idx_2_tuple_idx_1[32];
  assign and_9243 = and_8807 & p0_all_active_outputs_ready;
  assign one_hot_sel_9167[0] = admitted_slots_tuple_idx_0[0] & concat_9166[0] | postponed_slots_tuple_idx_0[0] & concat_9166[1] | compacted_slots_tuple_idx_0[0] & concat_9166[2] | admitted_slots_tuple_idx_0[0] & concat_9166[3] | unblocked_slots_tuple_idx_0[0] & concat_9166[4];
  assign one_hot_sel_9167[1] = admitted_slots_tuple_idx_0[1] & concat_9166[0] | postponed_slots_tuple_idx_0[1] & concat_9166[1] | compacted_slots_tuple_idx_0[1] & concat_9166[2] | admitted_slots_tuple_idx_0[1] & concat_9166[3] | unblocked_slots_tuple_idx_0[1] & concat_9166[4];
  assign one_hot_sel_9167[2] = admitted_slots_tuple_idx_0[2] & concat_9166[0] | postponed_slots_tuple_idx_0[2] & concat_9166[1] | compacted_slots_tuple_idx_0[2] & concat_9166[2] | admitted_slots_tuple_idx_0[2] & concat_9166[3] | unblocked_slots_tuple_idx_0[2] & concat_9166[4];
  assign one_hot_sel_9167[3] = admitted_slots_tuple_idx_0[3] & concat_9166[0] | postponed_slots_tuple_idx_0[3] & concat_9166[1] | compacted_slots_tuple_idx_0[3] & concat_9166[2] | admitted_slots_tuple_idx_0[3] & concat_9166[3] | unblocked_slots_tuple_idx_0[3] & concat_9166[4];
  assign one_hot_sel_9167[4] = admitted_slots_tuple_idx_0[4] & concat_9166[0] | postponed_slots_tuple_idx_0[4] & concat_9166[1] | compacted_slots_tuple_idx_0[4] & concat_9166[2] | admitted_slots_tuple_idx_0[4] & concat_9166[3] | unblocked_slots_tuple_idx_0[4] & concat_9166[4];
  assign and_9246 = (nor_8795 | and_8832 | and_8833 | and_8834 | and_8835) & p0_all_active_outputs_ready;
  assign one_hot_sel_9180[0] = admitted_slots_tuple_idx_1[0] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_1[0] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_1[0] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_1[0] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_1[0] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_1[0] & {8{concat_9179[7]}};
  assign one_hot_sel_9180[1] = admitted_slots_tuple_idx_1[1] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_1[1] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_1[1] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_1[1] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_1[1] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_1[1] & {8{concat_9179[7]}};
  assign one_hot_sel_9180[2] = admitted_slots_tuple_idx_1[2] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_1[2] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_1[2] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_1[2] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_1[2] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_1[2] & {8{concat_9179[7]}};
  assign one_hot_sel_9180[3] = admitted_slots_tuple_idx_1[3] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_1[3] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_1[3] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_1[3] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_1[3] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_1[3] & {8{concat_9179[7]}};
  assign one_hot_sel_9180[4] = admitted_slots_tuple_idx_1[4] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_1[4] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_1[4] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_1[4] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_1[4] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_1[4] & {8{concat_9179[7]}};
  assign and_9249 = (and_8832 | and_8833 | and_8834 | and_8835 | and_8836 | and_8837 | and_8838 | and_8839) & p0_all_active_outputs_ready;
  assign one_hot_sel_9193[0] = admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[0] & {96{concat_9179[7]}};
  assign one_hot_sel_9193[1] = admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[1] & {96{concat_9179[7]}};
  assign one_hot_sel_9193[2] = admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[2] & {96{concat_9179[7]}};
  assign one_hot_sel_9193[3] = admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[3] & {96{concat_9179[7]}};
  assign one_hot_sel_9193[4] = admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_1[4] & {96{concat_9179[7]}};
  assign one_hot_sel_9206[0] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[0] & {8{concat_9179[7]}};
  assign one_hot_sel_9206[1] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[1] & {8{concat_9179[7]}};
  assign one_hot_sel_9206[2] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[2] & {8{concat_9179[7]}};
  assign one_hot_sel_9206[3] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[3] & {8{concat_9179[7]}};
  assign one_hot_sel_9206[4] = admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[0]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[1]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[2]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[3]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[4]}} | postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[5]}} | compacted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[6]}} | admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[4] & {8{concat_9179[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {{{7'h01, ~____state_0}, compacted_4_tup1, compacted_4_tup1, {5'h00, ____state_0 ? 3'h4 : 3'h3}}, {{____state_3_0, ____state_3_1} & {64{~____state_0}}, ____state_2}};
  assign or_9561 = ~p0_all_active_outputs_ready | concat_8761 == one_hot_9508[2:0] | reset;
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
      ____state_7 <= 1'h0;
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
      ____state_11 <= and_9223 ? one_hot_sel_9116 : ____state_11;
      ____state_12 <= p0_all_active_outputs_ready ? or_9013 : ____state_12;
      ____state_10 <= and_9220 ? and_9015 : ____state_10;
      ____state_8_tuple_element_1[0] <= and_9249 ? one_hot_sel_9180[0] : ____state_8_tuple_element_1[0];
      ____state_8_tuple_element_1[1] <= and_9249 ? one_hot_sel_9180[1] : ____state_8_tuple_element_1[1];
      ____state_8_tuple_element_1[2] <= and_9249 ? one_hot_sel_9180[2] : ____state_8_tuple_element_1[2];
      ____state_8_tuple_element_1[3] <= and_9249 ? one_hot_sel_9180[3] : ____state_8_tuple_element_1[3];
      ____state_8_tuple_element_1[4] <= and_9249 ? one_hot_sel_9180[4] : ____state_8_tuple_element_1[4];
      ____state_9 <= and_9218 ? one_hot_sel_9106 : ____state_9;
      ____state_8_tuple_element_0[0] <= and_9246 ? one_hot_sel_9167[0] : ____state_8_tuple_element_0[0];
      ____state_8_tuple_element_0[1] <= and_9246 ? one_hot_sel_9167[1] : ____state_8_tuple_element_0[1];
      ____state_8_tuple_element_0[2] <= and_9246 ? one_hot_sel_9167[2] : ____state_8_tuple_element_0[2];
      ____state_8_tuple_element_0[3] <= and_9246 ? one_hot_sel_9167[3] : ____state_8_tuple_element_0[3];
      ____state_8_tuple_element_0[4] <= and_9246 ? one_hot_sel_9167[4] : ____state_8_tuple_element_0[4];
      ____state_0 <= and_9235 ? one_hot_sel_9140 : ____state_0;
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0] <= and_9249 ? one_hot_sel_9206[0] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[0];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[1] <= and_9249 ? one_hot_sel_9206[1] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[1];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[2] <= and_9249 ? one_hot_sel_9206[2] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[2];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[3] <= and_9249 ? one_hot_sel_9206[3] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[3];
      ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[4] <= and_9249 ? one_hot_sel_9206[4] : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[4];
      ____state_8_tuple_element_2_tuple_element_1[0] <= and_9249 ? one_hot_sel_9193[0] : ____state_8_tuple_element_2_tuple_element_1[0];
      ____state_8_tuple_element_2_tuple_element_1[1] <= and_9249 ? one_hot_sel_9193[1] : ____state_8_tuple_element_2_tuple_element_1[1];
      ____state_8_tuple_element_2_tuple_element_1[2] <= and_9249 ? one_hot_sel_9193[2] : ____state_8_tuple_element_2_tuple_element_1[2];
      ____state_8_tuple_element_2_tuple_element_1[3] <= and_9249 ? one_hot_sel_9193[3] : ____state_8_tuple_element_2_tuple_element_1[3];
      ____state_8_tuple_element_2_tuple_element_1[4] <= and_9249 ? one_hot_sel_9193[4] : ____state_8_tuple_element_2_tuple_element_1[4];
      ____state_2 <= and_9215 ? _1__1 : ____state_2;
      ____state_5 <= and_9238 ? one_hot_sel_9147 : ____state_5;
      ____state_6 <= and_9241 ? one_hot_sel_9154 : ____state_6;
      ____state_4_1 <= and_9230 ? and_9032 : ____state_4_1;
      ____state_4_0 <= and_9230 ? and_9031 : ____state_4_0;
      ____state_3_1 <= and_9226 ? _35 : ____state_3_1;
      ____state_3_0 <= and_9226 ? _29 : ____state_3_0;
      ____state_7 <= and_9243 ? _7__2 : ____state_7;
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
    assign admitted_slots_tuple_idx_1[__i0] = concat_8659 == __i0 ? and_8658 : ____state_8_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_8659 == __i0 ? and_8662 : ____state_8_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0] = concat_8659 == __i0 ? sel_8724 : ____state_8_tuple_element_2_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_2_tuple_idx_1_0
    assign admitted_slots_tuple_idx_2_tuple_idx_1[__i0] = concat_8659 == __i0 ? sel_8730 : ____state_8_tuple_element_2_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_8969 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1[__i0] = concat_8969 == __i0 ? extended___state_0 : admitted_slots_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_1_0
    assign postponed_slots_tuple_idx_2_tuple_idx_1[__i0] = concat_8969 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_1 : admitted_slots_tuple_idx_2_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0] = concat_8969 == __i0 ? selected_slot_tuple_idx_2_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_2_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_9622;
  wire eq_9627;
  wire ne_9611;
  wire and_9628;
  wire or_9625;
  wire [2:0] add_9619;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9614;
  wire popped;
  wire [1:0] sub_9640;
  wire [1:0] add_9642;
  wire [2:0] umod_9620;
  wire [2:0] umod_9615;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9644;
  wire array_update_9651[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9622 = pop_ready & push_valid;
  assign eq_9627 = head == tail;
  assign ne_9611 = head != tail;
  assign and_9628 = eq_9627 & and_9622;
  assign or_9625 = ne_9611 | push_valid;
  assign add_9619 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9614 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9625;
  assign sub_9640 = slots - 2'h1;
  assign add_9642 = slots + 2'h1;
  assign umod_9620 = add_9619 % long_buf_size_lit;
  assign umod_9615 = add_9614 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9620[1:0];
  assign did_push_occur = (can_do_push | and_9622) & push_valid & ~and_9628 & ~is_full_bool;
  assign next_tail_if_pop = umod_9615[1:0];
  assign did_pop_occur = (ne_9611 | and_9622) & pop_ready & ~and_9628;
  assign sel_9644 = pushed ? (popped ? slots : add_9642) : (popped ? sub_9640 : slots);
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
      slots <= sel_9644;
      buf__1[0] <= did_push_occur ? array_update_9651[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9651[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9625;
  assign pop_data = eq_9627 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9651_0
    assign array_update_9651[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9679;
  wire eq_9684;
  wire ne_9668;
  wire and_9685;
  wire or_9682;
  wire [2:0] add_9676;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9671;
  wire popped;
  wire [1:0] sub_9697;
  wire [1:0] add_9699;
  wire [2:0] umod_9677;
  wire [2:0] umod_9672;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9701;
  wire [127:0] array_update_9708[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9679 = pop_ready & push_valid;
  assign eq_9684 = head == tail;
  assign ne_9668 = head != tail;
  assign and_9685 = eq_9684 & and_9679;
  assign or_9682 = ne_9668 | push_valid;
  assign add_9676 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9671 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9682;
  assign sub_9697 = slots - 2'h1;
  assign add_9699 = slots + 2'h1;
  assign umod_9677 = add_9676 % long_buf_size_lit;
  assign umod_9672 = add_9671 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9677[1:0];
  assign did_push_occur = (can_do_push | and_9679) & push_valid & ~and_9685 & ~is_full_bool;
  assign next_tail_if_pop = umod_9672[1:0];
  assign did_pop_occur = (ne_9668 | and_9679) & pop_ready & ~and_9685;
  assign sel_9701 = pushed ? (popped ? slots : add_9699) : (popped ? sub_9697 : slots);
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
      slots <= sel_9701;
      buf__1[0] <= did_push_occur ? array_update_9708[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9708[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9682;
  assign pop_data = eq_9684 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9708_0
    assign array_update_9708[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9736;
  wire eq_9741;
  wire ne_9725;
  wire and_9742;
  wire or_9739;
  wire [2:0] add_9733;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9728;
  wire popped;
  wire [1:0] sub_9754;
  wire [1:0] add_9756;
  wire [2:0] umod_9734;
  wire [2:0] umod_9729;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9758;
  wire [127:0] array_update_9765[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9736 = pop_ready & push_valid;
  assign eq_9741 = head == tail;
  assign ne_9725 = head != tail;
  assign and_9742 = eq_9741 & and_9736;
  assign or_9739 = ne_9725 | push_valid;
  assign add_9733 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9728 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9739;
  assign sub_9754 = slots - 2'h1;
  assign add_9756 = slots + 2'h1;
  assign umod_9734 = add_9733 % long_buf_size_lit;
  assign umod_9729 = add_9728 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9734[1:0];
  assign did_push_occur = (can_do_push | and_9736) & push_valid & ~and_9742 & ~is_full_bool;
  assign next_tail_if_pop = umod_9729[1:0];
  assign did_pop_occur = (ne_9725 | and_9736) & pop_ready & ~and_9742;
  assign sel_9758 = pushed ? (popped ? slots : add_9756) : (popped ? sub_9754 : slots);
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
      slots <= sel_9758;
      buf__1[0] <= did_push_occur ? array_update_9765[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9765[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9739;
  assign pop_data = eq_9741 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9765_0
    assign array_update_9765[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9793;
  wire eq_9798;
  wire ne_9782;
  wire and_9799;
  wire or_9796;
  wire [2:0] add_9790;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9785;
  wire popped;
  wire [1:0] sub_9811;
  wire [1:0] add_9813;
  wire [2:0] umod_9791;
  wire [2:0] umod_9786;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9815;
  wire [127:0] array_update_9822[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9793 = pop_ready & push_valid;
  assign eq_9798 = head == tail;
  assign ne_9782 = head != tail;
  assign and_9799 = eq_9798 & and_9793;
  assign or_9796 = ne_9782 | push_valid;
  assign add_9790 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9785 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9796;
  assign sub_9811 = slots - 2'h1;
  assign add_9813 = slots + 2'h1;
  assign umod_9791 = add_9790 % long_buf_size_lit;
  assign umod_9786 = add_9785 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9791[1:0];
  assign did_push_occur = (can_do_push | and_9793) & push_valid & ~and_9799 & ~is_full_bool;
  assign next_tail_if_pop = umod_9786[1:0];
  assign did_pop_occur = (ne_9782 | and_9793) & pop_ready & ~and_9799;
  assign sel_9815 = pushed ? (popped ? slots : add_9813) : (popped ? sub_9811 : slots);
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
      slots <= sel_9815;
      buf__1[0] <= did_push_occur ? array_update_9822[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9822[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9796;
  assign pop_data = eq_9798 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9822_0
    assign array_update_9822[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9850;
  wire eq_9855;
  wire ne_9839;
  wire and_9856;
  wire or_9853;
  wire [2:0] add_9847;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9842;
  wire popped;
  wire [1:0] sub_9868;
  wire [1:0] add_9870;
  wire [2:0] umod_9848;
  wire [2:0] umod_9843;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9872;
  wire [127:0] array_update_9879[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9850 = pop_ready & push_valid;
  assign eq_9855 = head == tail;
  assign ne_9839 = head != tail;
  assign and_9856 = eq_9855 & and_9850;
  assign or_9853 = ne_9839 | push_valid;
  assign add_9847 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9842 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9853;
  assign sub_9868 = slots - 2'h1;
  assign add_9870 = slots + 2'h1;
  assign umod_9848 = add_9847 % long_buf_size_lit;
  assign umod_9843 = add_9842 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9848[1:0];
  assign did_push_occur = (can_do_push | and_9850) & push_valid & ~and_9856 & ~is_full_bool;
  assign next_tail_if_pop = umod_9843[1:0];
  assign did_pop_occur = (ne_9839 | and_9850) & pop_ready & ~and_9856;
  assign sel_9872 = pushed ? (popped ? slots : add_9870) : (popped ? sub_9868 : slots);
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
      slots <= sel_9872;
      buf__1[0] <= did_push_occur ? array_update_9879[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9879[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9853;
  assign pop_data = eq_9855 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9879_0
    assign array_update_9879[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9907;
  wire eq_9912;
  wire ne_9896;
  wire and_9913;
  wire or_9910;
  wire [2:0] add_9904;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9899;
  wire popped;
  wire [1:0] sub_9925;
  wire [1:0] add_9927;
  wire [2:0] umod_9905;
  wire [2:0] umod_9900;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9929;
  wire [127:0] array_update_9936[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9907 = pop_ready & push_valid;
  assign eq_9912 = head == tail;
  assign ne_9896 = head != tail;
  assign and_9913 = eq_9912 & and_9907;
  assign or_9910 = ne_9896 | push_valid;
  assign add_9904 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9899 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9910;
  assign sub_9925 = slots - 2'h1;
  assign add_9927 = slots + 2'h1;
  assign umod_9905 = add_9904 % long_buf_size_lit;
  assign umod_9900 = add_9899 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9905[1:0];
  assign did_push_occur = (can_do_push | and_9907) & push_valid & ~and_9913 & ~is_full_bool;
  assign next_tail_if_pop = umod_9900[1:0];
  assign did_pop_occur = (ne_9896 | and_9907) & pop_ready & ~and_9913;
  assign sel_9929 = pushed ? (popped ? slots : add_9927) : (popped ? sub_9925 : slots);
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
      slots <= sel_9929;
      buf__1[0] <= did_push_occur ? array_update_9936[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9936[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9910;
  assign pop_data = eq_9912 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9936_0
    assign array_update_9936[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_9404;
  wire instantiation_output_9429;
  wire [127:0] instantiation_output_9453;
  wire instantiation_output_9454;
  wire instantiation_output_9442;
  wire [32:0] instantiation_output_9446;
  wire instantiation_output_9447;
  wire instantiation_output_9417;
  wire [32:0] instantiation_output_9421;
  wire instantiation_output_9422;
  wire instantiation_output_9493;
  wire [32:0] instantiation_output_9497;
  wire instantiation_output_9498;
  wire instantiation_output_9474;
  wire [32:0] instantiation_output_9478;
  wire instantiation_output_9479;
  wire instantiation_output_9396;
  wire instantiation_output_9397;
  wire [127:0] instantiation_output_9409;
  wire instantiation_output_9410;
  wire [127:0] instantiation_output_9434;
  wire instantiation_output_9435;
  wire instantiation_output_9461;
  wire [127:0] instantiation_output_9466;
  wire instantiation_output_9467;
  wire [127:0] instantiation_output_9485;
  wire instantiation_output_9486;
  wire instantiation_output_9944;
  wire instantiation_output_9945;
  wire instantiation_output_9946;
  wire instantiation_output_9951;
  wire [127:0] instantiation_output_9952;
  wire instantiation_output_9953;
  wire instantiation_output_9958;
  wire [127:0] instantiation_output_9959;
  wire instantiation_output_9960;
  wire instantiation_output_9965;
  wire [127:0] instantiation_output_9966;
  wire instantiation_output_9967;
  wire instantiation_output_9972;
  wire [127:0] instantiation_output_9973;
  wire instantiation_output_9974;
  wire instantiation_output_9979;
  wire [127:0] instantiation_output_9980;
  wire instantiation_output_9981;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_9945),
    .phi_halo_cell__admit_vld(instantiation_output_9946),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_9965),
    .phi_halo_cell__admit_rdy(instantiation_output_9404),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_9429),
    .phi_halo_cell__req(instantiation_output_9453),
    .phi_halo_cell__req_vld(instantiation_output_9454),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_9959),
    .phi_halo_cell__north_vld(instantiation_output_9960),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_9442),
    .phi_halo_cell__north_send(instantiation_output_9446),
    .phi_halo_cell__north_send_vld(instantiation_output_9447),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_9952),
    .phi_halo_cell__east_vld(instantiation_output_9953),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_9417),
    .phi_halo_cell__east_send(instantiation_output_9421),
    .phi_halo_cell__east_send_vld(instantiation_output_9422),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_9980),
    .phi_halo_cell__west_vld(instantiation_output_9981),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_9493),
    .phi_halo_cell__west_send(instantiation_output_9497),
    .phi_halo_cell__west_send_vld(instantiation_output_9498),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_9973),
    .phi_halo_cell__south_vld(instantiation_output_9974),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_9474),
    .phi_halo_cell__south_send(instantiation_output_9478),
    .phi_halo_cell__south_send_vld(instantiation_output_9479),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_9944),
    .phi_halo_cell__east_rdy(instantiation_output_9951),
    .phi_halo_cell__north_rdy(instantiation_output_9958),
    .phi_halo_cell__req(instantiation_output_9966),
    .phi_halo_cell__req_vld(instantiation_output_9967),
    .phi_halo_cell__south_rdy(instantiation_output_9972),
    .phi_halo_cell__west_rdy(instantiation_output_9979),
    .phi_halo_cell__admit(instantiation_output_9396),
    .phi_halo_cell__admit_vld(instantiation_output_9397),
    .phi_halo_cell__east(instantiation_output_9409),
    .phi_halo_cell__east_vld(instantiation_output_9410),
    .phi_halo_cell__north(instantiation_output_9434),
    .phi_halo_cell__north_vld(instantiation_output_9435),
    .phi_halo_cell__req_rdy(instantiation_output_9461),
    .phi_halo_cell__south(instantiation_output_9466),
    .phi_halo_cell__south_vld(instantiation_output_9467),
    .phi_halo_cell__west(instantiation_output_9485),
    .phi_halo_cell__west_vld(instantiation_output_9486),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_9396),
    .push_valid(instantiation_output_9397),
    .pop_ready(instantiation_output_9404),
    .push_ready(instantiation_output_9944),
    .pop_data(instantiation_output_9945),
    .pop_valid(instantiation_output_9946),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_9409),
    .push_valid(instantiation_output_9410),
    .pop_ready(instantiation_output_9417),
    .push_ready(instantiation_output_9951),
    .pop_data(instantiation_output_9952),
    .pop_valid(instantiation_output_9953),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_9434),
    .push_valid(instantiation_output_9435),
    .pop_ready(instantiation_output_9442),
    .push_ready(instantiation_output_9958),
    .pop_data(instantiation_output_9959),
    .pop_valid(instantiation_output_9960),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_9453),
    .push_valid(instantiation_output_9454),
    .pop_ready(instantiation_output_9461),
    .push_ready(instantiation_output_9965),
    .pop_data(instantiation_output_9966),
    .pop_valid(instantiation_output_9967),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_9466),
    .push_valid(instantiation_output_9467),
    .pop_ready(instantiation_output_9474),
    .push_ready(instantiation_output_9972),
    .pop_data(instantiation_output_9973),
    .pop_valid(instantiation_output_9974),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_9485),
    .push_valid(instantiation_output_9486),
    .pop_ready(instantiation_output_9493),
    .push_ready(instantiation_output_9979),
    .pop_data(instantiation_output_9980),
    .pop_valid(instantiation_output_9981),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_9421;
  assign phi_halo_cell__east_send_vld = instantiation_output_9422;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_9429;
  assign phi_halo_cell__north_send = instantiation_output_9446;
  assign phi_halo_cell__north_send_vld = instantiation_output_9447;
  assign phi_halo_cell__south_send = instantiation_output_9478;
  assign phi_halo_cell__south_send_vld = instantiation_output_9479;
  assign phi_halo_cell__west_send = instantiation_output_9497;
  assign phi_halo_cell__west_send_vld = instantiation_output_9498;
endmodule
