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
  wire [32:0] literal_15904 = {1'h0, 32'h0000_0000};
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
  wire and_15914;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_15913;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_15926;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_17990;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_17989;
  wire [31:0] sel_17988;
  wire [31:0] sel_17987;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_15971;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_17992;
  wire nand_15942;
  wire [127:0] one_hot_sel_15972;
  wire and_15986;
  wire [7:0] one_hot_sel_15979;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_15904;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_15914 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_15914;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_15913 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_15914;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_15913, and_15914};
  assign one_hot_15926 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_17990 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_17989 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_17988 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_17987 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_15913 == one_hot_15926[1] & and_15914 == one_hot_15926[0];
  assign concat_15971 = {nor_15913 & p0_stage_done, and_15914 & p0_stage_done};
  assign payload = {sel_17989, sel_17988, sel_17987, sel_17990};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_17992 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_15942 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_15972 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_15971[0]}} | payload & {128{concat_15971[1]}};
  assign and_15986 = (nor_15913 | and_15914) & p0_stage_done;
  assign one_hot_sel_15979 = 8'h00 & {8{concat_15971[0]}} | words_seen & {8{concat_15971[1]}};
  assign __phi_halo_cell__req_buf = {{sel_17990[7:0], sel_17990[15:8], sel_17990[23:16], sel_17990[31:24]}, {sel_17989, sel_17988, sel_17987}};
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
      ____state_0 <= p0_stage_done ? nand_15942 : ____state_0;
      ____state_2 <= and_15986 ? one_hot_sel_15979 : ____state_2;
      ____state_1 <= and_15986 ? one_hot_sel_15972 : ____state_1;
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
  wire [127:0] literal_16042 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_16054;
  wire not_16055;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_16064;
  wire [2:0] one_hot_16065;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_16104;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_16107;
  wire [127:0] payload;
  wire [1:0] concat_16120;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_17996;
  wire or_18000;
  wire [7:0] one_hot_sel_16108;
  wire and_16128;
  wire [127:0] one_hot_sel_16115;
  wire [7:0] one_hot_sel_16121;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_16042;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_16054 = ~(last | ____state_0);
  assign not_16055 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_16054};
  assign ____state_6__next_value_predicates = {not_16055, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_16064 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_16065 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_16104 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_16064[1] & nor_16054 == one_hot_16064[0];
  assign ____state_6__at_most_one_next_value = not_16055 == one_hot_16065[1] & last == one_hot_16065[0];
  assign concat_16107 = {and_16104, nor_16054 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_16120 = {not_16055 & p0_stage_done, and_16104};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_17996 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_18000 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_16108 = frame_header_payload_words__1 & {8{concat_16107[0]}} | 8'h00 & {8{concat_16107[1]}};
  assign and_16128 = (last | nor_16054) & p0_stage_done;
  assign one_hot_sel_16115 = payload & {128{concat_16107[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_16107[1]}};
  assign one_hot_sel_16121 = 8'h00 & {8{concat_16120[0]}} | beats_sent & {8{concat_16120[1]}};
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
      ____state_0 <= p0_stage_done ? not_16055 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_16121 : ____state_6;
      ____state_1 <= and_16128 ? one_hot_sel_16108 : ____state_1;
      ____state_5 <= and_16128 ? one_hot_sel_16115 : ____state_5;
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
  wire [127:0] literal_16177 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_16189;
  wire not_16190;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_16199;
  wire [2:0] one_hot_16200;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_16239;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_16242;
  wire [127:0] payload;
  wire [1:0] concat_16255;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_18002;
  wire or_18006;
  wire [7:0] one_hot_sel_16243;
  wire and_16263;
  wire [127:0] one_hot_sel_16250;
  wire [7:0] one_hot_sel_16256;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_16177;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_16189 = ~(last | ____state_0);
  assign not_16190 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_16189};
  assign ____state_6__next_value_predicates = {not_16190, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_16199 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_16200 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_16239 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_16199[1] & nor_16189 == one_hot_16199[0];
  assign ____state_6__at_most_one_next_value = not_16190 == one_hot_16200[1] & last == one_hot_16200[0];
  assign concat_16242 = {and_16239, nor_16189 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_16255 = {not_16190 & p0_stage_done, and_16239};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_18002 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_18006 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_16243 = frame_header_payload_words__1 & {8{concat_16242[0]}} | 8'h00 & {8{concat_16242[1]}};
  assign and_16263 = (last | nor_16189) & p0_stage_done;
  assign one_hot_sel_16250 = payload & {128{concat_16242[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_16242[1]}};
  assign one_hot_sel_16256 = 8'h00 & {8{concat_16255[0]}} | beats_sent & {8{concat_16255[1]}};
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
      ____state_0 <= p0_stage_done ? not_16190 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_16256 : ____state_6;
      ____state_1 <= and_16263 ? one_hot_sel_16243 : ____state_1;
      ____state_5 <= and_16263 ? one_hot_sel_16250 : ____state_5;
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
  wire [127:0] literal_16312 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_16324;
  wire not_16325;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_16334;
  wire [2:0] one_hot_16335;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_16374;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_16377;
  wire [127:0] payload;
  wire [1:0] concat_16390;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_18008;
  wire or_18012;
  wire [7:0] one_hot_sel_16378;
  wire and_16398;
  wire [127:0] one_hot_sel_16385;
  wire [7:0] one_hot_sel_16391;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_16312;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_16324 = ~(last | ____state_0);
  assign not_16325 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_16324};
  assign ____state_6__next_value_predicates = {not_16325, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_16334 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_16335 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_16374 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_16334[1] & nor_16324 == one_hot_16334[0];
  assign ____state_6__at_most_one_next_value = not_16325 == one_hot_16335[1] & last == one_hot_16335[0];
  assign concat_16377 = {and_16374, nor_16324 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_16390 = {not_16325 & p0_stage_done, and_16374};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_18008 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_18012 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_16378 = frame_header_payload_words__1 & {8{concat_16377[0]}} | 8'h00 & {8{concat_16377[1]}};
  assign and_16398 = (last | nor_16324) & p0_stage_done;
  assign one_hot_sel_16385 = payload & {128{concat_16377[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_16377[1]}};
  assign one_hot_sel_16391 = 8'h00 & {8{concat_16390[0]}} | beats_sent & {8{concat_16390[1]}};
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
      ____state_0 <= p0_stage_done ? not_16325 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_16391 : ____state_6;
      ____state_1 <= and_16398 ? one_hot_sel_16378 : ____state_1;
      ____state_5 <= and_16398 ? one_hot_sel_16385 : ____state_5;
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
  wire [127:0] literal_16447 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_16459;
  wire not_16460;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_16469;
  wire [2:0] one_hot_16470;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_16509;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_16512;
  wire [127:0] payload;
  wire [1:0] concat_16525;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_18014;
  wire or_18018;
  wire [7:0] one_hot_sel_16513;
  wire and_16533;
  wire [127:0] one_hot_sel_16520;
  wire [7:0] one_hot_sel_16526;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_16447;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_16459 = ~(last | ____state_0);
  assign not_16460 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_16459};
  assign ____state_6__next_value_predicates = {not_16460, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_16469 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_16470 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_16509 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_16469[1] & nor_16459 == one_hot_16469[0];
  assign ____state_6__at_most_one_next_value = not_16460 == one_hot_16470[1] & last == one_hot_16470[0];
  assign concat_16512 = {and_16509, nor_16459 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_16525 = {not_16460 & p0_stage_done, and_16509};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_18014 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_18018 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_16513 = frame_header_payload_words__1 & {8{concat_16512[0]}} | 8'h00 & {8{concat_16512[1]}};
  assign and_16533 = (last | nor_16459) & p0_stage_done;
  assign one_hot_sel_16520 = payload & {128{concat_16512[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_16512[1]}};
  assign one_hot_sel_16526 = 8'h00 & {8{concat_16525[0]}} | beats_sent & {8{concat_16525[1]}};
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
      ____state_0 <= p0_stage_done ? not_16460 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_16526 : ____state_6;
      ____state_1 <= and_16533 ? one_hot_sel_16513 : ____state_1;
      ____state_5 <= and_16533 ? one_hot_sel_16520 : ____state_5;
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


module __axis__Top__Tx_4_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phi_halo_cell__syndrome,
  input wire phi_halo_cell__syndrome_vld,
  input wire phi_halo_cell__syndrome_send_rdy,
  output wire phi_halo_cell__syndrome_rdy,
  output wire [32:0] phi_halo_cell__syndrome_send,
  output wire phi_halo_cell__syndrome_send_vld
);
  wire [127:0] __phi_halo_cell__syndrome_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phi_halo_cell__syndrome_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_16582 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phi_halo_cell__syndrome_reg;
  reg __phi_halo_cell__syndrome_valid_reg;
  reg [32:0] __phi_halo_cell__syndrome_send_reg;
  reg __phi_halo_cell__syndrome_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phi_halo_cell__syndrome_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phi_halo_cell__syndrome_send_valid_inv;
  wire nor_16594;
  wire not_16595;
  wire __phi_halo_cell__syndrome_send_vld_buf;
  wire phi_halo_cell__syndrome_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__syndrome_send_load_en;
  wire [2:0] one_hot_16604;
  wire [2:0] one_hot_16605;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__syndrome_valid_inv;
  wire and_16644;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__syndrome_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_16647;
  wire [127:0] payload;
  wire [1:0] concat_16660;
  wire [7:0] beats_sent;
  wire phi_halo_cell__syndrome_load_en;
  wire or_18020;
  wire or_18024;
  wire [7:0] one_hot_sel_16648;
  wire and_16668;
  wire [127:0] one_hot_sel_16655;
  wire [7:0] one_hot_sel_16661;
  wire [32:0] __phi_halo_cell__syndrome_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__syndrome_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__syndrome_reg : literal_16582;
  assign frame_header__1 = phi_halo_cell__syndrome_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__syndrome_send_valid_inv = ~__phi_halo_cell__syndrome_send_valid_reg;
  assign nor_16594 = ~(last | ____state_0);
  assign not_16595 = ~last;
  assign __phi_halo_cell__syndrome_send_vld_buf = ____state_0 | __phi_halo_cell__syndrome_valid_reg;
  assign phi_halo_cell__syndrome_send_valid_load_en = phi_halo_cell__syndrome_send_rdy | phi_halo_cell__syndrome_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_16594};
  assign ____state_6__next_value_predicates = {not_16595, last};
  assign phi_halo_cell__syndrome_send_load_en = __phi_halo_cell__syndrome_send_vld_buf & phi_halo_cell__syndrome_send_valid_load_en;
  assign one_hot_16604 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_16605 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__syndrome_send_vld_buf & phi_halo_cell__syndrome_send_load_en;
  assign phi_halo_cell__syndrome_valid_inv = ~__phi_halo_cell__syndrome_valid_reg;
  assign and_16644 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__syndrome_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__syndrome_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__syndrome_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_16604[1] & nor_16594 == one_hot_16604[0];
  assign ____state_6__at_most_one_next_value = not_16595 == one_hot_16605[1] & last == one_hot_16605[0];
  assign concat_16647 = {and_16644, nor_16594 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_16660 = {not_16595 & p0_stage_done, and_16644};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__syndrome_load_en = phi_halo_cell__syndrome_vld & phi_halo_cell__syndrome_valid_load_en;
  assign or_18020 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_18024 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_16648 = frame_header_payload_words__1 & {8{concat_16647[0]}} | 8'h00 & {8{concat_16647[1]}};
  assign and_16668 = (last | nor_16594) & p0_stage_done;
  assign one_hot_sel_16655 = payload & {128{concat_16647[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_16647[1]}};
  assign one_hot_sel_16661 = 8'h00 & {8{concat_16660[0]}} | beats_sent & {8{concat_16660[1]}};
  assign __phi_halo_cell__syndrome_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phi_halo_cell__syndrome_reg <= __phi_halo_cell__syndrome_reg_init;
      __phi_halo_cell__syndrome_valid_reg <= 1'h0;
      __phi_halo_cell__syndrome_send_reg <= __phi_halo_cell__syndrome_send_reg_init;
      __phi_halo_cell__syndrome_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_16595 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_16661 : ____state_6;
      ____state_1 <= and_16668 ? one_hot_sel_16648 : ____state_1;
      ____state_5 <= and_16668 ? one_hot_sel_16655 : ____state_5;
      __phi_halo_cell__syndrome_reg <= phi_halo_cell__syndrome_load_en ? phi_halo_cell__syndrome : __phi_halo_cell__syndrome_reg;
      __phi_halo_cell__syndrome_valid_reg <= phi_halo_cell__syndrome_valid_load_en ? phi_halo_cell__syndrome_vld : __phi_halo_cell__syndrome_valid_reg;
      __phi_halo_cell__syndrome_send_reg <= phi_halo_cell__syndrome_send_load_en ? __phi_halo_cell__syndrome_send_buf : __phi_halo_cell__syndrome_send_reg;
      __phi_halo_cell__syndrome_send_valid_reg <= phi_halo_cell__syndrome_send_valid_load_en ? __phi_halo_cell__syndrome_send_vld_buf : __phi_halo_cell__syndrome_send_valid_reg;
    end
  end
  assign phi_halo_cell__syndrome_rdy = phi_halo_cell__syndrome_load_en;
  assign phi_halo_cell__syndrome_send = __phi_halo_cell__syndrome_send_reg;
  assign phi_halo_cell__syndrome_send_vld = __phi_halo_cell__syndrome_send_valid_reg;
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
  input wire phi_halo_cell__syndrome_rdy,
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
  output wire [127:0] phi_halo_cell__syndrome,
  output wire phi_halo_cell__syndrome_vld,
  output wire [127:0] phi_halo_cell__west,
  output wire phi_halo_cell__west_vld
);
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
  function automatic [1:0] priority_sel_2b_10way (input reg [9:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] case3, input reg [1:0] case4, input reg [1:0] case5, input reg [1:0] case6, input reg [1:0] case7, input reg [1:0] case8, input reg [1:0] case9, input reg [1:0] default_value);
    begin
      casez (sel)
        10'b?????????1: begin
          priority_sel_2b_10way = case0;
        end
        10'b????????10: begin
          priority_sel_2b_10way = case1;
        end
        10'b???????100: begin
          priority_sel_2b_10way = case2;
        end
        10'b??????1000: begin
          priority_sel_2b_10way = case3;
        end
        10'b?????10000: begin
          priority_sel_2b_10way = case4;
        end
        10'b????100000: begin
          priority_sel_2b_10way = case5;
        end
        10'b???1000000: begin
          priority_sel_2b_10way = case6;
        end
        10'b??10000000: begin
          priority_sel_2b_10way = case7;
        end
        10'b?100000000: begin
          priority_sel_2b_10way = case8;
        end
        10'b1000000000: begin
          priority_sel_2b_10way = case9;
        end
        10'b00_0000_0000: begin
          priority_sel_2b_10way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_10way = 2'dx;
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
  function automatic [95:0] priority_sel_96b_3way (input reg [2:0] sel, input reg [95:0] case0, input reg [95:0] case1, input reg [95:0] case2, input reg [95:0] default_value);
    begin
      casez (sel)
        3'b??1: begin
          priority_sel_96b_3way = case0;
        end
        3'b?10: begin
          priority_sel_96b_3way = case1;
        end
        3'b100: begin
          priority_sel_96b_3way = case2;
        end
        3'b000: begin
          priority_sel_96b_3way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_96b_3way = 96'dx;
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
  wire [127:0] __phi_halo_cell__syndrome_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_16793 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire literal_16746[0:3];
  assign literal_16746[0] = 1'h0;
  assign literal_16746[1] = 1'h1;
  assign literal_16746[2] = 1'h1;
  assign literal_16746[3] = 1'h1;
  wire literal_16747[0:3];
  assign literal_16747[0] = 1'h1;
  assign literal_16747[1] = 1'h0;
  assign literal_16747[2] = 1'h0;
  assign literal_16747[3] = 1'h0;
  wire [1:0] literal_16741[0:3];
  assign literal_16741[0] = 2'h0;
  assign literal_16741[1] = 2'h3;
  assign literal_16741[2] = 2'h3;
  assign literal_16741[3] = 2'h2;
  wire [2:0] literal_16742[0:3];
  assign literal_16742[0] = 3'h0;
  assign literal_16742[1] = 3'h3;
  assign literal_16742[2] = 3'h5;
  assign literal_16742[3] = 3'h4;
  wire [2:0] literal_16743[0:3];
  assign literal_16743[0] = 3'h7;
  assign literal_16743[1] = 3'h0;
  assign literal_16743[2] = 3'h0;
  assign literal_16743[3] = 3'h0;
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
  reg [31:0] ____state_2;
  reg [31:0] ____state_3;
  reg [31:0] ____state_7;
  reg [1:0] ____state_0;
  reg [1:0] ____state_6;
  reg [1:0] ____state_10;
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
  reg __phi_halo_cell__syndrome_has_been_sent_reg;
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
  reg [127:0] __phi_halo_cell__syndrome_reg;
  reg __phi_halo_cell__syndrome_valid_reg;
  wire nor_16791;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_16802;
  wire eq_16804;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_16829;
  wire [31:0] concat_16830;
  wire ugt_16832;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_16834;
  wire postponed__4;
  wire ugt_16838;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_3152_0__2_case_0_case_0_case_0;
  wire or_reduce_16842;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_16853;
  wire postponed;
  wire [95:0] sel_16862;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_16865;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Value1_1;
  wire [31:0] _5__9_source;
  wire [31:0] _5__8_source;
  wire [31:0] _5__7_source;
  wire [31:0] _5__6_source;
  wire [7:0] sel_16875;
  wire [30:0] add_16876;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire _0__19;
  wire _1__6;
  wire _2__6;
  wire [31:0] _7__3;
  wire [31:0] Absent_1__1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [1:0] unexpand_for_next_value_3152_0__2_case_0_case_0_case_2;
  wire [1:0] unexpand_for_next_value_3152_0__2_case_0_case_1_case_1;
  wire eq_16888;
  wire eq_16889;
  wire [1:0] unexpand_for_next_value_3152_0__2_case_0_case_0_case_3;
  wire eq_16893;
  wire _8__3;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire eq_16898;
  wire eq_16899;
  wire [31:0] _1__1;
  wire _3__1;
  wire _19;
  wire _47;
  wire nor_16905;
  wire and_16907;
  wire _21__2;
  wire eq_16909;
  wire eq_16914;
  wire or_16916;
  wire eq_16917;
  wire [31:0] _2__2;
  wire or_16919;
  wire _0__14;
  wire nand_16922;
  wire _6__1;
  wire nand_16925;
  wire or_16927;
  wire [2:0] concat_16930;
  wire [1:0] concat_16933;
  wire _4__1;
  wire nand_16936;
  wire postponed_slot_tup0;
  wire nand_16939;
  wire [31:0] _8__1;
  wire eligible_0;
  wire invalid_input;
  wire compacted_4_tup0;
  wire nand_16945;
  wire and_16947;
  wire eq_16952;
  wire _2;
  wire _2__8;
  wire found;
  wire dispatchable;
  wire [1:0] priority_sel_16985;
  wire [1:0] priority_sel_16987;
  wire [1:0] directive;
  wire [1:0] next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_17037;
  wire [1:0] candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire nor_17002;
  wire phase_changed;
  wire [31:0] Xls_clause_1_Value_1;
  wire and_17009;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire effects_north_valid;
  wire effects_syndrome_valid;
  wire _12__2;
  wire and_17013;
  wire and_17015;
  wire eq_17016;
  wire final_slots_0_case_cmp;
  wire and_17024;
  wire and_17026;
  wire and_17027;
  wire and_17029;
  wire and_17030;
  wire eq_17031;
  wire and_17032;
  wire [18:0] _1__7;
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
  wire __phi_halo_cell__syndrome_vld_buf;
  wire __phi_halo_cell__syndrome_not_has_been_sent;
  wire phi_halo_cell__syndrome_valid_inv;
  wire and_17044;
  wire and_17046;
  wire Xls_clause_1_NewBestDirection_1_0_case_cmp;
  wire _15__1;
  wire and_17051;
  wire candidate_occupied_0_case_cmp;
  wire and_17053;
  wire candidate_slots_0_case_cmp;
  wire and_17056;
  wire or_17057;
  wire and_17059;
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
  wire __phi_halo_cell__syndrome_valid_and_not_has_been_sent;
  wire phi_halo_cell__syndrome_valid_load_en;
  wire and_17074;
  wire and_17075;
  wire and_17076;
  wire and_17077;
  wire and_17078;
  wire nor_17079;
  wire and_17080;
  wire and_17081;
  wire and_17082;
  wire nor_17083;
  wire and_17084;
  wire and_17085;
  wire and_17086;
  wire and_17087;
  wire and_17088;
  wire and_17089;
  wire and_17090;
  wire and_17091;
  wire and_17092;
  wire and_17093;
  wire and_17094;
  wire and_17095;
  wire and_17096;
  wire and_17097;
  wire and_17098;
  wire and_17099;
  wire and_17100;
  wire and_17101;
  wire and_17102;
  wire and_17103;
  wire and_17104;
  wire and_17105;
  wire and_17106;
  wire and_17107;
  wire and_17108;
  wire and_17109;
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
  wire phi_halo_cell__syndrome_not_pred;
  wire phi_halo_cell__syndrome_load_en;
  wire [1:0] ____state_3__next_value_predicates;
  wire [1:0] ____state_7__next_value_predicates;
  wire [1:0] ____state_8__next_value_predicates;
  wire [2:0] ____state_9__next_value_predicates;
  wire [2:0] ____state_11__next_value_predicates;
  wire [1:0] ____state_14__next_value_predicates;
  wire [1:0] ____state_16__next_value_predicates;
  wire [18:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [4:0] ____state_13_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_13_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [31:0] _8;
  wire [31:0] _35;
  wire Move_1__1;
  wire [2:0] one_hot_17170;
  wire [2:0] one_hot_17171;
  wire [2:0] one_hot_17172;
  wire [3:0] one_hot_17173;
  wire [3:0] one_hot_17174;
  wire [2:0] one_hot_17175;
  wire [2:0] one_hot_17176;
  wire [19:0] one_hot_17177;
  wire [2:0] one_hot_17178;
  wire [2:0] one_hot_17179;
  wire [5:0] one_hot_17180;
  wire [8:0] one_hot_17181;
  wire [14:0] _2__1;
  wire [30:0] add_17121;
  wire [63:0] umul_17122;
  wire [95:0] array_index_17149;
  wire [95:0] array_index_17151;
  wire [95:0] array_index_17153;
  wire [7:0] array_index_17157;
  wire [7:0] array_index_17159;
  wire [7:0] array_index_17161;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_17167;
  wire ne_17208;
  wire or_reduce_17210;
  wire ugt_17212;
  wire phi_halo_cell__req_valid_inv;
  wire and_17492;
  wire and_17493;
  wire and_17499;
  wire and_17507;
  wire and_17523;
  wire _22__2;
  wire admission_pending;
  wire [15:0] add_17226;
  wire and_17601;
  wire and_17602;
  wire and_17603;
  wire and_17604;
  wire [31:0] concat_17307;
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
  wire [95:0] concat_17185;
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
  wire [1:0] concat_17495;
  wire [31:0] _42;
  wire [1:0] concat_17502;
  wire [1:0] concat_17509;
  wire [2:0] concat_17517;
  wire [2:0] concat_17525;
  wire [31:0] _3__7;
  wire [31:0] _22__1;
  wire [16:0] NextRandom_1__11;
  wire [9:0] NextRandom_1__10;
  wire [4:0] NextRandom_1__9;
  wire [1:0] concat_17535;
  wire [1:0] concat_17545;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_17318;
  wire [31:0] sign_ext_17319;
  wire [18:0] concat_17582;
  wire [1:0] concat_17589;
  wire [1:0] unexpand_for_next_value_3152_6__2_case_0_case_0_case_1_case_1_case_0;
  wire [1:0] concat_17596;
  wire [1:0] unexpand_for_next_value_3152_10__2_case_0_case_1_case_3_case_1_case_0;
  wire [4:0] concat_17606;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_17619;
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
  wire __phi_halo_cell__syndrome_valid_and_all_active_outputs_ready;
  wire __phi_halo_cell__syndrome_valid_and_ready_txfr;
  wire [31:0] tuple_17284;
  wire phi_halo_cell__req_load_en;
  wire or_18026;
  wire or_18028;
  wire or_18030;
  wire or_18032;
  wire or_18034;
  wire or_18036;
  wire or_18038;
  wire or_18040;
  wire or_18042;
  wire or_18044;
  wire or_18046;
  wire or_18048;
  wire and_17643;
  wire [31:0] one_hot_sel_17496;
  wire and_17646;
  wire [31:0] one_hot_sel_17503;
  wire and_17649;
  wire [31:0] one_hot_sel_17510;
  wire and_17652;
  wire [31:0] one_hot_sel_17518;
  wire and_17655;
  wire [31:0] one_hot_sel_17526;
  wire and_17658;
  wire [31:0] NextRandom_1;
  wire and_17660;
  wire [7:0] one_hot_sel_17536;
  wire and_17663;
  wire and_17383;
  wire and_17665;
  wire one_hot_sel_17546;
  wire and_17668;
  wire or_17381;
  wire [31:0] _31;
  wire and_17671;
  wire [31:0] _37;
  wire [31:0] and_17400;
  wire and_17675;
  wire [31:0] and_17401;
  wire [1:0] one_hot_sel_17583;
  wire and_17680;
  wire [1:0] one_hot_sel_17590;
  wire and_17683;
  wire [1:0] one_hot_sel_17597;
  wire and_17686;
  wire one_hot_sel_17607[0:4];
  wire and_17689;
  wire [95:0] one_hot_sel_17620[0:4];
  wire and_17692;
  wire [7:0] one_hot_sel_17633[0:4];
  wire __phi_halo_cell__admit_not_stage_load;
  wire __phi_halo_cell__admit_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_not_stage_load;
  wire __phi_halo_cell__north_has_been_sent_reg_load_en;
  wire __phi_halo_cell__east_has_been_sent_reg_load_en;
  wire __phi_halo_cell__west_has_been_sent_reg_load_en;
  wire __phi_halo_cell__south_has_been_sent_reg_load_en;
  wire __phi_halo_cell__syndrome_not_stage_load;
  wire __phi_halo_cell__syndrome_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire [127:0] effects_east;
  wire [127:0] effects_west;
  wire [127:0] effects_south;
  wire [127:0] effects_syndrome;
  assign nor_16791 = ~(____state_17 | ____state_15 | ~____state_16);
  assign received = nor_16791 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_16793;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_16802 = frame_header__1_payload_words == 8'h03;
  assign eq_16804 = frame_header__1_payload_words == 8'h02;
  assign tag_ok = frame_header_op == 8'h03 & eq_16802 | frame_header_op == 8'h04 & eq_16804 | frame_header_op == MAILBOX_CAPACITY & eq_16802 | frame_header_op == 8'h06 & eq_16804 | frame_header_op == 8'h07 & frame_header__1_payload_words == 8'h01 | frame_header_op == 8'h08 & eq_16804 | frame_header_op == 8'h09 & eq_16802 | frame_header_op == 8'h0a & eq_16804;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_14 + {7'h00, accepted};
  assign and_16829 = ~accepted & ____state_13_tuple_element_0[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign concat_16830 = {24'h00_0000, ____state_14};
  assign ugt_16832 = admitted_occupied > 8'h04;
  assign or_reduce_16834 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_16838 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_16832 | postponed__4);
  assign unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 = 2'h0;
  assign or_reduce_16842 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_16834 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_16838 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_16842 | postponed__1);
  assign eq_16853 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_16862 = accepted ? phi_halo_cell__req_select[95:0] : ____state_13_tuple_element_1_tuple_element_1[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_3152_0__2_case_0_case_0_case_0}))} & {8{eq_16853 | postponed}};
  assign bit_slice_16865 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_16865 > 3'h4 ? 3'h4 : bit_slice_16865];
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _5__9_source = 32'h0000_0001;
  assign _5__8_source = 32'h0000_0002;
  assign _5__7_source = 32'h0000_0004;
  assign _5__6_source = 32'h0000_0008;
  assign sel_16875 = accepted ? frame_header_op : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[____state_14 > 8'h04 ? 3'h4 : ____state_14[2:0]];
  assign add_16876 = ____state_2[30:0] + ____state_3[31:1];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__19 = Xls_clause_1_Value1_1 == _5__9_source;
  assign _1__6 = Xls_clause_1_Value1_1 == _5__8_source;
  assign _2__6 = Xls_clause_1_Value1_1 == _5__7_source;
  assign _7__3 = ____state_7 & Xls_clause_1_Value1_1;
  assign Absent_1__1 = 32'h0000_0000;
  assign unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 = 2'h2;
  assign unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 = 2'h1;
  assign eq_16888 = add_16876 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_16889 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign unexpand_for_next_value_3152_0__2_case_0_case_0_case_3 = 2'h3;
  assign eq_16893 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _8__3 = _7__3 == Absent_1__1;
  assign Xls_clause_1_NewSeen_1 = ____state_7 | Xls_clause_1_Value1_1;
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_16865 > 3'h4 ? 3'h4 : bit_slice_16865];
  assign eq_16898 = ____state_0 == unexpand_for_next_value_3152_0__2_case_0_case_0_case_2;
  assign eq_16899 = ____state_0 == unexpand_for_next_value_3152_0__2_case_0_case_1_case_1;
  assign _1__1 = {add_16876, ____state_3[0]};
  assign _3__1 = eq_16888 & eq_16889;
  assign _19 = ____state_6 == unexpand_for_next_value_3152_0__2_case_0_case_0_case_3;
  assign _47 = ____state_3 == _5__9_source;
  assign nor_16905 = ~(____state_0[0] | ____state_0[1]);
  assign and_16907 = eq_16893 & (_0__19 | _1__6 | _2__6 | Xls_clause_1_Value1_1 == _5__6_source) & _8__3;
  assign _21__2 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign eq_16909 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h0a;
  assign eq_16914 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY;
  assign or_16916 = ____state_0[0] | ____state_0[1];
  assign eq_16917 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign _2__2 = _1__1 + _5__9_source;
  assign or_16919 = eq_16898 | eq_16899;
  assign _0__14 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign nand_16922 = ~(_3__1 & _19 & _47);
  assign _6__1 = ____state_10 == unexpand_for_next_value_3152_0__2_case_0_case_0_case_3;
  assign nand_16925 = ~(and_16907 & _21__2);
  assign or_16927 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h09 | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h08 | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h07 | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h06;
  assign concat_16930 = {eq_16898, eq_16899, nor_16905};
  assign concat_16933 = {eq_16899, nor_16905};
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__2;
  assign nand_16936 = ~(eq_16888 & eq_16889);
  assign postponed_slot_tup0 = 1'h1;
  assign nand_16939 = ~(eq_16893 & _0__14);
  assign _8__1 = ____state_2 + _5__9_source;
  assign eligible_0 = ~(eq_16853 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign compacted_4_tup0 = 1'h0;
  assign nand_16945 = ~(eq_16893 & _0__14 & _6__1);
  assign and_16947 = eq_16893 & _0__14;
  assign eq_16952 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign _2 = ~(____state_2[30:0] != selected_slot_tuple_idx_1_tuple_idx_1[31:1] | selected_slot_tuple_idx_1_tuple_idx_1[0]);
  assign _2__8 = Xls_clause_2_Epoch_1 == _8__1;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_16985 = priority_sel_2b_10way({eq_16909 & or_16916, ~(~eq_16909 | ____state_0[0] | ____state_0[1]), or_16927 | eq_16914 & ~(eq_16898 | eq_16899) & or_16916, {3{eq_16914}} & concat_16930, eq_16952, eq_16917 & ~eq_16899 & or_16916, {2{eq_16917}} & concat_16933}, _2 ? unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 : unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, (_4__1 ? unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 : unexpand_for_next_value_3152_0__2_case_0_case_0_case_2) & {2{nand_16936}}, _3__1 ? unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 : unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, {priority_sel_1b_2way({or_16919, nor_16905}, postponed_slot_tup0, ~eq_16893, nand_16939), eq_16893 & or_16919}, unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, eq_16893 ? unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 : unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, {~and_16907, compacted_4_tup0}, unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, {nand_16939, compacted_4_tup0}, _2__8 ? unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 : unexpand_for_next_value_3152_0__2_case_0_case_0_case_2, unexpand_for_next_value_3152_0__2_case_0_case_0_case_2);
  assign priority_sel_16987 = priority_sel_2b_5way({eq_16909, or_16927, eq_16914, eq_16952, eq_16917}, {priority_sel_1b_2way(concat_16933, compacted_4_tup0, ~nand_16922, postponed_slot_tup0), priority_sel_1b_3way(concat_16930, compacted_4_tup0, nand_16922, compacted_4_tup0, postponed_slot_tup0)}, {priority_sel_1b_2way({eq_16898, eq_16899 | nor_16905}, compacted_4_tup0, postponed_slot_tup0, nand_16945), priority_sel_1b_3way(concat_16930, compacted_4_tup0, postponed_slot_tup0, compacted_4_tup0, nand_16945)}, {____state_0[1], priority_sel_1b_3way(concat_16930, compacted_4_tup0, postponed_slot_tup0, ~nand_16925, ____state_0[0])}, ____state_0, {____state_0[1], priority_sel_1b_3way(concat_16930, and_16947, postponed_slot_tup0, compacted_4_tup0, postponed_slot_tup0)}, ____state_0);
  assign directive = priority_sel_16985 & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? priority_sel_16987 : ____state_0;
  assign repeat_phase = dispatchable & eq_16917 & ~(nand_16936 | ~_19 | _47) & eq_16899;
  assign invalid_repeat = repeat_phase & (directive[0] | directive[1] | next_phase_squeezed != ____state_0);
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | directive[1]);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_17037 = admitted_occupied + 8'hff;
  assign candidate_phase_squeezed = effective ? priority_sel_16987 : ____state_0;
  assign failed = invalid_input | invalid_repeat | effective & directive == unexpand_for_next_value_3152_0__2_case_0_case_0_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_17037 : admitted_occupied;
  assign nor_17002 = ~(____state_17 | ____state_15);
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign Xls_clause_1_Value_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign and_17009 = nor_17002 & effective;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_16 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_16 | ____state_14 > 8'h04);
  assign effects_north_valid = literal_16746[____state_0];
  assign effects_syndrome_valid = literal_16747[____state_0];
  assign _12__2 = Xls_clause_1_Value_1 > ____state_8;
  assign and_17013 = and_17009 & eq_16914;
  assign and_17015 = and_17009 & eq_16952;
  assign eq_17016 = ____state_0 == unexpand_for_next_value_3152_0__2_case_0_case_0_case_3;
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_17024 = and_17009 & eq_16917;
  assign and_17026 = and_17013 & eq_16898;
  assign and_17027 = and_17009 & eq_16909;
  assign and_17029 = and_17015 & eq_17016;
  assign and_17030 = nor_17002 & final_slots_0_case_cmp;
  assign eq_17031 = priority_sel_16985 == unexpand_for_next_value_3152_0__2_case_0_case_1_case_1;
  assign and_17032 = nor_17002 & phase_boundary;
  assign _1__7 = ____state_12[31:13] ^ ____state_12[18:0];
  assign __phi_halo_cell__admit_buf = ~____state_17 & ~____state_15 & reserve__1 | ~____state_17 & ____state_15 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign __phi_halo_cell__east_vld_buf = ~(____state_17 | ~____state_15 | ~effects_north_valid);
  assign __phi_halo_cell__north_not_has_been_sent = ~__phi_halo_cell__north_has_been_sent_reg;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign __phi_halo_cell__east_not_has_been_sent = ~__phi_halo_cell__east_has_been_sent_reg;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign __phi_halo_cell__west_not_has_been_sent = ~__phi_halo_cell__west_has_been_sent_reg;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign __phi_halo_cell__south_not_has_been_sent = ~__phi_halo_cell__south_has_been_sent_reg;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign __phi_halo_cell__syndrome_vld_buf = ~(____state_17 | ~____state_15 | ~effects_syndrome_valid);
  assign __phi_halo_cell__syndrome_not_has_been_sent = ~__phi_halo_cell__syndrome_has_been_sent_reg;
  assign phi_halo_cell__syndrome_valid_inv = ~__phi_halo_cell__syndrome_valid_reg;
  assign and_17044 = and_17024 & eq_16899;
  assign and_17046 = and_17026 & and_16907;
  assign Xls_clause_1_NewBestDirection_1_0_case_cmp = ~_12__2;
  assign _15__1 = Xls_clause_1_Value_1 == ____state_8;
  assign and_17051 = and_17027 & nor_16905;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_17053 = and_17029 & and_16947;
  assign candidate_slots_0_case_cmp = ~effective;
  assign and_17056 = and_17030 & effective;
  assign or_17057 = directive[0] | directive[1];
  assign and_17059 = and_17032 & effective;
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
  assign __phi_halo_cell__syndrome_valid_and_not_has_been_sent = __phi_halo_cell__syndrome_vld_buf & __phi_halo_cell__syndrome_not_has_been_sent;
  assign phi_halo_cell__syndrome_valid_load_en = phi_halo_cell__syndrome_rdy | phi_halo_cell__syndrome_valid_inv;
  assign and_17074 = and_17044 & _3__1 & _19;
  assign and_17075 = and_17029 & eq_16893 & _0__14 & _6__1;
  assign and_17076 = and_17044 & _3__1 & _19 & _47;
  assign and_17077 = and_17026 & ~(~(and_16907 & _12__2));
  assign and_17078 = and_17046 & Xls_clause_1_NewBestDirection_1_0_case_cmp & _15__1;
  assign nor_17079 = ~(____state_17 | ~____state_15 | ~eq_17016);
  assign and_17080 = and_17051 & and_16947;
  assign and_17081 = nor_17002 & candidate_occupied_0_case_cmp;
  assign and_17082 = nor_17002 & candidate_occupied_1_case_cmp;
  assign nor_17083 = ~(____state_17 | ~____state_15);
  assign and_17084 = and_17024 & nor_16905;
  assign and_17085 = and_17024 & eq_16898;
  assign and_17086 = and_17024 & eq_17016;
  assign and_17087 = and_17015 & nor_16905;
  assign and_17088 = and_17015 & eq_16899;
  assign and_17089 = and_17015 & eq_16898;
  assign and_17090 = and_17013 & nor_16905;
  assign and_17091 = and_17013 & eq_16899;
  assign and_17092 = and_17027 & eq_16899;
  assign and_17093 = and_17027 & eq_16898;
  assign and_17094 = and_17027 & eq_17016;
  assign and_17095 = and_17044 & nand_16922;
  assign and_17096 = and_17029 & nand_16945;
  assign and_17097 = and_17026 & ~nand_16925;
  assign and_17098 = and_17026 & nand_16925;
  assign and_17099 = and_17051 & nand_16939;
  assign and_17100 = and_17044 & _3__1 & ~_19;
  assign and_17101 = and_17053 & ~_6__1;
  assign and_17102 = and_17030 & candidate_slots_0_case_cmp;
  assign and_17103 = and_17056 & transition_slots_predicate_piece_0;
  assign and_17104 = and_17056 & eq_17031 & or_17057;
  assign and_17105 = and_17056 & ~eq_17031 & or_17057;
  assign and_17106 = and_17032 & candidate_slots_0_case_cmp;
  assign and_17107 = and_17059 & transition_slots_predicate_piece_0;
  assign and_17108 = and_17059 & eq_17031 & or_17057;
  assign and_17109 = and_17059 & ~eq_17031 & or_17057;
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign _7__9 = ____state_11 == _5__9_source;
  assign _9 = ____state_9 != Absent_1__1;
  assign NextRandom_1__5 = _1__7[18] ^ _1__7[13];
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign phi_halo_cell__syndrome_not_pred = ~__phi_halo_cell__syndrome_vld_buf;
  assign phi_halo_cell__syndrome_load_en = __phi_halo_cell__syndrome_valid_and_not_has_been_sent & phi_halo_cell__syndrome_valid_load_en;
  assign ____state_3__next_value_predicates = {and_17074, and_17075};
  assign ____state_7__next_value_predicates = {and_17076, and_17046};
  assign ____state_8__next_value_predicates = {and_17076, and_17077};
  assign ____state_9__next_value_predicates = {and_17076, and_17077, and_17078};
  assign ____state_11__next_value_predicates = {nor_17079, and_17053, and_17080};
  assign ____state_14__next_value_predicates = {and_17081, and_17082};
  assign ____state_16__next_value_predicates = {nor_17002, nor_17083};
  assign ____state_0__next_value_predicates = {and_17084, and_17085, and_17086, and_17087, and_17088, and_17089, and_17090, and_17091, and_17092, and_17093, and_17094, and_17076, and_17095, and_17075, and_17096, and_17097, and_17098, and_17099, and_17080};
  assign ____state_6__next_value_predicates = {and_17100, and_17074};
  assign ____state_10__next_value_predicates = {and_17101, and_17075};
  assign ____state_13_tuple_element_0__next_value_predicates = {and_17032, and_17102, and_17103, and_17104, and_17105};
  assign ____state_13_tuple_element_1_tuple_element_1__next_value_predicates = {and_17102, and_17103, and_17104, and_17105, and_17106, and_17107, and_17108, and_17109};
  assign _8 = ____state_5_0 + Xls_clause_1_Value_1;
  assign _35 = ____state_4_0 + _12;
  assign Move_1__1 = _7__9 & _9 & NextRandom_1__5;
  assign one_hot_17170 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_17171 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_17172 = {____state_8__next_value_predicates[1:0] == 2'h0, ____state_8__next_value_predicates[1] && !____state_8__next_value_predicates[0], ____state_8__next_value_predicates[0]};
  assign one_hot_17173 = {____state_9__next_value_predicates[2:0] == 3'h0, ____state_9__next_value_predicates[2] && ____state_9__next_value_predicates[1:0] == 2'h0, ____state_9__next_value_predicates[1] && !____state_9__next_value_predicates[0], ____state_9__next_value_predicates[0]};
  assign one_hot_17174 = {____state_11__next_value_predicates[2:0] == 3'h0, ____state_11__next_value_predicates[2] && ____state_11__next_value_predicates[1:0] == 2'h0, ____state_11__next_value_predicates[1] && !____state_11__next_value_predicates[0], ____state_11__next_value_predicates[0]};
  assign one_hot_17175 = {____state_14__next_value_predicates[1:0] == 2'h0, ____state_14__next_value_predicates[1] && !____state_14__next_value_predicates[0], ____state_14__next_value_predicates[0]};
  assign one_hot_17176 = {____state_16__next_value_predicates[1:0] == 2'h0, ____state_16__next_value_predicates[1] && !____state_16__next_value_predicates[0], ____state_16__next_value_predicates[0]};
  assign one_hot_17177 = {____state_0__next_value_predicates[18:0] == 19'h0_0000, ____state_0__next_value_predicates[18] && ____state_0__next_value_predicates[17:0] == 18'h0_0000, ____state_0__next_value_predicates[17] && ____state_0__next_value_predicates[16:0] == 17'h0_0000, ____state_0__next_value_predicates[16] && ____state_0__next_value_predicates[15:0] == 16'h0000, ____state_0__next_value_predicates[15] && ____state_0__next_value_predicates[14:0] == 15'h0000, ____state_0__next_value_predicates[14] && ____state_0__next_value_predicates[13:0] == 14'h0000, ____state_0__next_value_predicates[13] && ____state_0__next_value_predicates[12:0] == 13'h0000, ____state_0__next_value_predicates[12] && ____state_0__next_value_predicates[11:0] == 12'h000, ____state_0__next_value_predicates[11] && ____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_17178 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_17179 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_17180 = {____state_13_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_0__next_value_predicates[4] && ____state_13_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_0__next_value_predicates[3] && ____state_13_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_0__next_value_predicates[2] && ____state_13_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_0__next_value_predicates[1] && !____state_13_tuple_element_0__next_value_predicates[0], ____state_13_tuple_element_0__next_value_predicates[0]};
  assign one_hot_17181 = {____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_13_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign _2__1 = {_1__7[1:0], ____state_12[12:0]} ^ _1__7[18:4];
  assign add_17121 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_17122 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_17149 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_17151 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_17153 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_17157 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_17159 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_17161 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg) & (phi_halo_cell__syndrome_not_pred | phi_halo_cell__syndrome_load_en | __phi_halo_cell__syndrome_has_been_sent_reg);
  assign add_17167 = ____state_4_1[30:0] + _8[31:1];
  assign ne_17208 = bit_slice_16865 != 3'h0;
  assign or_reduce_17210 = |selected[7:1];
  assign ugt_17212 = bit_slice_16865 > 3'h2;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_17492 = and_17074 & p0_all_active_outputs_ready;
  assign and_17493 = and_17075 & p0_all_active_outputs_ready;
  assign and_17499 = and_17076 & p0_all_active_outputs_ready;
  assign and_17507 = and_17077 & p0_all_active_outputs_ready;
  assign and_17523 = and_17080 & p0_all_active_outputs_ready;
  assign _22__2 = ____state_11[0] ^ Move_1__1;
  assign admission_pending = ~(~____state_16 | received);
  assign add_17226 = ____state_11[15:0] + {unexpand_for_next_value_3152_0__2_case_0_case_0_case_0, ____state_4_0[31:18]};
  assign and_17601 = and_17102 & p0_all_active_outputs_ready;
  assign and_17602 = and_17103 & p0_all_active_outputs_ready;
  assign and_17603 = and_17104 & p0_all_active_outputs_ready;
  assign and_17604 = and_17105 & p0_all_active_outputs_ready;
  assign concat_17307 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_17208 ? postponed : or_reduce_16842 & postponed__1;
  assign compacted_1_tup0 = or_reduce_17210 ? postponed__1 : ugt_16838 & postponed__2;
  assign compacted_2_tup0 = ugt_17212 ? postponed__2 : or_reduce_16834 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_16832 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_17208 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_17149 & {96{or_reduce_16842}};
  assign compacted_1_tup1_tup1 = or_reduce_17210 ? array_index_17149 : array_index_17151 & {96{ugt_16838}};
  assign compacted_2_tup1_tup1 = ugt_17212 ? array_index_17151 : array_index_17153 & {96{or_reduce_16834}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_17153 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_16832}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_17208 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_17157 & {8{or_reduce_16842}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_17210 ? array_index_17157 : array_index_17159 & {8{ugt_16838}};
  assign compacted_2_tup1_tup0_tup3 = ugt_17212 ? array_index_17159 : array_index_17161 & {8{or_reduce_16834}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_17161 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_16832}};
  assign concat_17185 = {____state_4_0, ____state_4_1, add_16876, ____state_3[0]};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_16791 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_17074 == one_hot_17170[1] & and_17075 == one_hot_17170[0];
  assign ____state_7__at_most_one_next_value = and_17076 == one_hot_17171[1] & and_17046 == one_hot_17171[0];
  assign ____state_8__at_most_one_next_value = and_17076 == one_hot_17172[1] & and_17077 == one_hot_17172[0];
  assign ____state_9__at_most_one_next_value = and_17076 == one_hot_17173[2] & and_17077 == one_hot_17173[1] & and_17078 == one_hot_17173[0];
  assign ____state_11__at_most_one_next_value = nor_17079 == one_hot_17174[2] & and_17053 == one_hot_17174[1] & and_17080 == one_hot_17174[0];
  assign ____state_14__at_most_one_next_value = and_17081 == one_hot_17175[1] & and_17082 == one_hot_17175[0];
  assign ____state_16__at_most_one_next_value = nor_17002 == one_hot_17176[1] & nor_17083 == one_hot_17176[0];
  assign ____state_0__at_most_one_next_value = and_17084 == one_hot_17177[18] & and_17085 == one_hot_17177[17] & and_17086 == one_hot_17177[16] & and_17087 == one_hot_17177[15] & and_17088 == one_hot_17177[14] & and_17089 == one_hot_17177[13] & and_17090 == one_hot_17177[12] & and_17091 == one_hot_17177[11] & and_17092 == one_hot_17177[10] & and_17093 == one_hot_17177[9] & and_17094 == one_hot_17177[8] & and_17076 == one_hot_17177[7] & and_17095 == one_hot_17177[6] & and_17075 == one_hot_17177[5] & and_17096 == one_hot_17177[4] & and_17097 == one_hot_17177[3] & and_17098 == one_hot_17177[2] & and_17099 == one_hot_17177[1] & and_17080 == one_hot_17177[0];
  assign ____state_6__at_most_one_next_value = and_17100 == one_hot_17178[1] & and_17074 == one_hot_17178[0];
  assign ____state_10__at_most_one_next_value = and_17101 == one_hot_17179[1] & and_17075 == one_hot_17179[0];
  assign ____state_13_tuple_element_0__at_most_one_next_value = and_17032 == one_hot_17180[4] & and_17102 == one_hot_17180[3] & and_17103 == one_hot_17180[2] & and_17104 == one_hot_17180[1] & and_17105 == one_hot_17180[0];
  assign ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value = and_17102 == one_hot_17181[7] & and_17103 == one_hot_17181[6] & and_17104 == one_hot_17181[5] & and_17105 == one_hot_17181[4] & and_17106 == one_hot_17181[3] & and_17107 == one_hot_17181[2] & and_17108 == one_hot_17181[1] & and_17109 == one_hot_17181[0];
  assign concat_17495 = {and_17492, and_17493};
  assign _42 = ____state_3 + _5__9_source;
  assign concat_17502 = {and_17499, and_17046 & p0_all_active_outputs_ready};
  assign concat_17509 = {and_17499, and_17507};
  assign concat_17517 = {and_17499, and_17507, and_17078 & p0_all_active_outputs_ready};
  assign concat_17525 = {nor_17079 & p0_all_active_outputs_ready, and_17053 & p0_all_active_outputs_ready, and_17523};
  assign _3__7 = ____state_11 ^ Xls_clause_1_Value1_1;
  assign _22__1 = {____state_11[31:1], _22__2};
  assign NextRandom_1__11 = _1__7[18:2] ^ {_1__7[13:2], _2__1[14:10]};
  assign NextRandom_1__10 = _2__1[14:5] ^ _2__1[9:0];
  assign NextRandom_1__9 = _2__1[4:0];
  assign concat_17535 = {and_17081 & p0_all_active_outputs_ready, and_17082 & p0_all_active_outputs_ready};
  assign concat_17545 = {nor_17002 & p0_all_active_outputs_ready, nor_17083 & p0_all_active_outputs_ready};
  assign _27 = {add_17226, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_17167[30:2]};
  assign add_17318 = {compacted_4_tup0, add_17121[30:1]} + {3'h0, umul_17122[63:36]};
  assign sign_ext_17319 = {32{~_19}};
  assign concat_17582 = {and_17084 & p0_all_active_outputs_ready, and_17085 & p0_all_active_outputs_ready, and_17086 & p0_all_active_outputs_ready, and_17087 & p0_all_active_outputs_ready, and_17088 & p0_all_active_outputs_ready, and_17089 & p0_all_active_outputs_ready, and_17090 & p0_all_active_outputs_ready, and_17091 & p0_all_active_outputs_ready, and_17092 & p0_all_active_outputs_ready, and_17093 & p0_all_active_outputs_ready, and_17094 & p0_all_active_outputs_ready, and_17499, and_17095 & p0_all_active_outputs_ready, and_17493, and_17096 & p0_all_active_outputs_ready, and_17097 & p0_all_active_outputs_ready, and_17098 & p0_all_active_outputs_ready, and_17099 & p0_all_active_outputs_ready, and_17523};
  assign concat_17589 = {and_17100 & p0_all_active_outputs_ready, and_17492};
  assign unexpand_for_next_value_3152_6__2_case_0_case_0_case_1_case_1_case_0 = ____state_6 + unexpand_for_next_value_3152_0__2_case_0_case_1_case_1;
  assign concat_17596 = {and_17101 & p0_all_active_outputs_ready, and_17493};
  assign unexpand_for_next_value_3152_10__2_case_0_case_1_case_3_case_1_case_0 = ____state_10 + unexpand_for_next_value_3152_0__2_case_0_case_1_case_1;
  assign concat_17606 = {and_17032 & p0_all_active_outputs_ready, and_17601, and_17602, and_17603, and_17604};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_17619 = {and_17601, and_17602, and_17603, and_17604, and_17106 & p0_all_active_outputs_ready, and_17107 & p0_all_active_outputs_ready, and_17108 & p0_all_active_outputs_ready, and_17109 & p0_all_active_outputs_ready};
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
  assign __phi_halo_cell__syndrome_valid_and_all_active_outputs_ready = __phi_halo_cell__syndrome_vld_buf & p0_all_active_outputs_ready;
  assign __phi_halo_cell__syndrome_valid_and_ready_txfr = __phi_halo_cell__syndrome_valid_and_not_has_been_sent & phi_halo_cell__syndrome_load_en;
  assign tuple_17284 = {{6'h00, literal_16741[____state_0]}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, literal_16742[____state_0]}};
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_18026 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_18028 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_18030 = ~p0_all_active_outputs_ready | ____state_8__at_most_one_next_value | reset;
  assign or_18032 = ~p0_all_active_outputs_ready | ____state_9__at_most_one_next_value | reset;
  assign or_18034 = ~p0_all_active_outputs_ready | ____state_11__at_most_one_next_value | reset;
  assign or_18036 = ~p0_all_active_outputs_ready | ____state_14__at_most_one_next_value | reset;
  assign or_18038 = ~p0_all_active_outputs_ready | ____state_16__at_most_one_next_value | reset;
  assign or_18040 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_18042 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_18044 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_18046 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_0__at_most_one_next_value | reset;
  assign or_18048 = ~p0_all_active_outputs_ready | ____state_13_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign and_17643 = and_17075 & p0_all_active_outputs_ready;
  assign one_hot_sel_17496 = Absent_1__1 & {32{concat_17495[0]}} | _42 & {32{concat_17495[1]}};
  assign and_17646 = (and_17074 | and_17075) & p0_all_active_outputs_ready;
  assign one_hot_sel_17503 = Xls_clause_1_NewSeen_1 & {32{concat_17502[0]}} | Absent_1__1 & {32{concat_17502[1]}};
  assign and_17649 = (and_17076 | and_17046) & p0_all_active_outputs_ready;
  assign one_hot_sel_17510 = Xls_clause_1_Value_1 & {32{concat_17509[0]}} | Absent_1__1 & {32{concat_17509[1]}};
  assign and_17652 = (and_17076 | and_17077) & p0_all_active_outputs_ready;
  assign one_hot_sel_17518 = Absent_1__1 & {32{concat_17517[0]}} | Xls_clause_1_Value1_1 & {32{concat_17517[1]}} | Absent_1__1 & {32{concat_17517[2]}};
  assign and_17655 = (and_17076 | and_17077 | and_17078) & p0_all_active_outputs_ready;
  assign one_hot_sel_17526 = _3__7 & {32{concat_17525[0]}} | _3__7 & {32{concat_17525[1]}} | _22__1 & {32{concat_17525[2]}};
  assign and_17658 = (nor_17079 | and_17053 | and_17080) & p0_all_active_outputs_ready;
  assign NextRandom_1 = {NextRandom_1__11, NextRandom_1__10, NextRandom_1__9};
  assign and_17660 = nor_17079 & p0_all_active_outputs_ready;
  assign one_hot_sel_17536 = add_17037 & {8{concat_17535[0]}} | admitted_occupied & {8{concat_17535[1]}};
  assign and_17663 = (and_17081 | and_17082) & p0_all_active_outputs_ready;
  assign and_17383 = ~____state_15 & effective & phase_boundary & ~failed;
  assign and_17665 = ~____state_17 & p0_all_active_outputs_ready;
  assign one_hot_sel_17546 = (____state_16 | ____state_14 < MAILBOX_CAPACITY) & concat_17545[0] | (admission_pending | reserve__1) & concat_17545[1];
  assign and_17668 = (nor_17002 | nor_17083) & p0_all_active_outputs_ready;
  assign or_17381 = ____state_17 | (____state_15 ? ____state_17 : failed);
  assign _31 = _27 + _30;
  assign and_17671 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_16917 & eq_16899 & eq_16888 & eq_16889 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_17318};
  assign and_17400 = _8 & sign_ext_17319;
  assign and_17675 = ~(____state_17 | ____state_15 | candidate_slots_0_case_cmp) & eq_16917 & eq_16899 & _3__1 & p0_all_active_outputs_ready;
  assign and_17401 = _12 & sign_ext_17319;
  assign one_hot_sel_17583 = unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 & {2{concat_17582[0]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17582[1]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 & {2{concat_17582[2]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_3 & {2{concat_17582[3]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_3 & {2{concat_17582[4]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17582[5]}} | unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 & {2{concat_17582[6]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 & {2{concat_17582[7]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_3 & {2{concat_17582[8]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 & {2{concat_17582[9]}} | unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 & {2{concat_17582[10]}} | unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 & {2{concat_17582[11]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17582[12]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 & {2{concat_17582[13]}} | unexpand_for_next_value_3152_0__2_case_0_case_1_case_1 & {2{concat_17582[14]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17582[15]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_3 & {2{concat_17582[16]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_2 & {2{concat_17582[17]}} | unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17582[18]}};
  assign and_17680 = (and_17084 | and_17085 | and_17086 | and_17087 | and_17088 | and_17089 | and_17090 | and_17091 | and_17092 | and_17093 | and_17094 | and_17076 | and_17095 | and_17075 | and_17096 | and_17097 | and_17098 | and_17099 | and_17080) & p0_all_active_outputs_ready;
  assign one_hot_sel_17590 = unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17589[0]}} | unexpand_for_next_value_3152_6__2_case_0_case_0_case_1_case_1_case_0 & {2{concat_17589[1]}};
  assign and_17683 = (and_17100 | and_17074) & p0_all_active_outputs_ready;
  assign one_hot_sel_17597 = unexpand_for_next_value_3152_0__2_case_0_case_0_case_0 & {2{concat_17596[0]}} | unexpand_for_next_value_3152_10__2_case_0_case_1_case_3_case_1_case_0 & {2{concat_17596[1]}};
  assign and_17686 = (and_17101 | and_17075) & p0_all_active_outputs_ready;
  assign one_hot_sel_17607[0] = admitted_slots_tuple_idx_0[0] & concat_17606[0] | postponed_slots_tuple_idx_0[0] & concat_17606[1] | compacted_slots_tuple_idx_0[0] & concat_17606[2] | admitted_slots_tuple_idx_0[0] & concat_17606[3] | unblocked_slots_tuple_idx_0[0] & concat_17606[4];
  assign one_hot_sel_17607[1] = admitted_slots_tuple_idx_0[1] & concat_17606[0] | postponed_slots_tuple_idx_0[1] & concat_17606[1] | compacted_slots_tuple_idx_0[1] & concat_17606[2] | admitted_slots_tuple_idx_0[1] & concat_17606[3] | unblocked_slots_tuple_idx_0[1] & concat_17606[4];
  assign one_hot_sel_17607[2] = admitted_slots_tuple_idx_0[2] & concat_17606[0] | postponed_slots_tuple_idx_0[2] & concat_17606[1] | compacted_slots_tuple_idx_0[2] & concat_17606[2] | admitted_slots_tuple_idx_0[2] & concat_17606[3] | unblocked_slots_tuple_idx_0[2] & concat_17606[4];
  assign one_hot_sel_17607[3] = admitted_slots_tuple_idx_0[3] & concat_17606[0] | postponed_slots_tuple_idx_0[3] & concat_17606[1] | compacted_slots_tuple_idx_0[3] & concat_17606[2] | admitted_slots_tuple_idx_0[3] & concat_17606[3] | unblocked_slots_tuple_idx_0[3] & concat_17606[4];
  assign one_hot_sel_17607[4] = admitted_slots_tuple_idx_0[4] & concat_17606[0] | postponed_slots_tuple_idx_0[4] & concat_17606[1] | compacted_slots_tuple_idx_0[4] & concat_17606[2] | admitted_slots_tuple_idx_0[4] & concat_17606[3] | unblocked_slots_tuple_idx_0[4] & concat_17606[4];
  assign and_17689 = (and_17032 | and_17102 | and_17103 | and_17104 | and_17105) & p0_all_active_outputs_ready;
  assign one_hot_sel_17620[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_17619[7]}};
  assign one_hot_sel_17620[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_17619[7]}};
  assign one_hot_sel_17620[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_17619[7]}};
  assign one_hot_sel_17620[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_17619[7]}};
  assign one_hot_sel_17620[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_17619[7]}};
  assign and_17692 = (and_17102 | and_17103 | and_17104 | and_17105 | and_17106 | and_17107 | and_17108 | and_17109) & p0_all_active_outputs_ready;
  assign one_hot_sel_17633[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_17619[7]}};
  assign one_hot_sel_17633[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_17619[7]}};
  assign one_hot_sel_17633[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_17619[7]}};
  assign one_hot_sel_17633[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_17619[7]}};
  assign one_hot_sel_17633[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_17619[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__syndrome_not_stage_load = ~__phi_halo_cell__syndrome_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__syndrome_has_been_sent_reg_load_en = __phi_halo_cell__syndrome_valid_and_ready_txfr | __phi_halo_cell__syndrome_valid_and_all_active_outputs_ready;
  assign effects_north = {tuple_17284, priority_sel_96b_3way(concat_16930, compacted_4_tup1_tup1, concat_17185, {____state_4_0, _5__6_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__9_source & Move_1__1)), ____state_2})};
  assign effects_east = {tuple_17284, priority_sel_96b_3way(concat_16930, compacted_4_tup1_tup1, concat_17185, {____state_4_0, _5__7_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__8_source & Move_1__1)), ____state_2})};
  assign effects_west = {tuple_17284, priority_sel_96b_3way(concat_16930, compacted_4_tup1_tup1, concat_17185, {____state_4_0, _5__8_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__7_source & Move_1__1)), ____state_2})};
  assign effects_south = {tuple_17284, priority_sel_96b_3way(concat_16930, compacted_4_tup1_tup1, concat_17185, {____state_4_0, _5__9_source, ____state_2}, {63'h0000_0000_0000_0000, ~(~(____state_9 == _5__6_source & Move_1__1)), ____state_2})};
  assign effects_syndrome = {{8'h01, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, literal_16743[____state_0]}}, {64'h0000_0000_0000_0000, {32{nor_16905}} & ____state_2}};
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
      ____state_2 <= 32'h0000_0000;
      ____state_3 <= 32'h0000_0000;
      ____state_7 <= 32'h0000_0000;
      ____state_0 <= 2'h0;
      ____state_6 <= 2'h0;
      ____state_10 <= 2'h0;
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
      __phi_halo_cell__syndrome_has_been_sent_reg <= 1'h0;
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
      __phi_halo_cell__syndrome_reg <= __phi_halo_cell__syndrome_reg_init;
      __phi_halo_cell__syndrome_valid_reg <= 1'h0;
    end else begin
      ____state_16 <= and_17668 ? one_hot_sel_17546 : ____state_16;
      ____state_17 <= p0_all_active_outputs_ready ? or_17381 : ____state_17;
      ____state_15 <= and_17665 ? and_17383 : ____state_15;
      ____state_13_tuple_element_0[0] <= and_17689 ? one_hot_sel_17607[0] : ____state_13_tuple_element_0[0];
      ____state_13_tuple_element_0[1] <= and_17689 ? one_hot_sel_17607[1] : ____state_13_tuple_element_0[1];
      ____state_13_tuple_element_0[2] <= and_17689 ? one_hot_sel_17607[2] : ____state_13_tuple_element_0[2];
      ____state_13_tuple_element_0[3] <= and_17689 ? one_hot_sel_17607[3] : ____state_13_tuple_element_0[3];
      ____state_13_tuple_element_0[4] <= and_17689 ? one_hot_sel_17607[4] : ____state_13_tuple_element_0[4];
      ____state_14 <= and_17663 ? one_hot_sel_17536 : ____state_14;
      ____state_13_tuple_element_1_tuple_element_1[0] <= and_17692 ? one_hot_sel_17620[0] : ____state_13_tuple_element_1_tuple_element_1[0];
      ____state_13_tuple_element_1_tuple_element_1[1] <= and_17692 ? one_hot_sel_17620[1] : ____state_13_tuple_element_1_tuple_element_1[1];
      ____state_13_tuple_element_1_tuple_element_1[2] <= and_17692 ? one_hot_sel_17620[2] : ____state_13_tuple_element_1_tuple_element_1[2];
      ____state_13_tuple_element_1_tuple_element_1[3] <= and_17692 ? one_hot_sel_17620[3] : ____state_13_tuple_element_1_tuple_element_1[3];
      ____state_13_tuple_element_1_tuple_element_1[4] <= and_17692 ? one_hot_sel_17620[4] : ____state_13_tuple_element_1_tuple_element_1[4];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_17692 ? one_hot_sel_17633[0] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_17692 ? one_hot_sel_17633[1] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_17692 ? one_hot_sel_17633[2] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_17692 ? one_hot_sel_17633[3] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_17692 ? one_hot_sel_17633[4] : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_2 <= and_17643 ? _8__1 : ____state_2;
      ____state_3 <= and_17646 ? one_hot_sel_17496 : ____state_3;
      ____state_7 <= and_17649 ? one_hot_sel_17503 : ____state_7;
      ____state_0 <= and_17680 ? one_hot_sel_17583 : ____state_0;
      ____state_6 <= and_17683 ? one_hot_sel_17590 : ____state_6;
      ____state_10 <= and_17686 ? one_hot_sel_17597 : ____state_10;
      ____state_12 <= and_17660 ? NextRandom_1 : ____state_12;
      ____state_8 <= and_17652 ? one_hot_sel_17510 : ____state_8;
      ____state_11 <= and_17658 ? one_hot_sel_17526 : ____state_11;
      ____state_9 <= and_17655 ? one_hot_sel_17518 : ____state_9;
      ____state_5_1 <= and_17675 ? and_17401 : ____state_5_1;
      ____state_5_0 <= and_17675 ? and_17400 : ____state_5_0;
      ____state_4_1 <= and_17671 ? _37 : ____state_4_1;
      ____state_4_0 <= and_17671 ? _31 : ____state_4_0;
      __phi_halo_cell__admit_has_been_sent_reg <= __phi_halo_cell__admit_has_been_sent_reg_load_en ? __phi_halo_cell__admit_not_stage_load : __phi_halo_cell__admit_has_been_sent_reg;
      __phi_halo_cell__north_has_been_sent_reg <= __phi_halo_cell__north_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__north_has_been_sent_reg;
      __phi_halo_cell__east_has_been_sent_reg <= __phi_halo_cell__east_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__east_has_been_sent_reg;
      __phi_halo_cell__west_has_been_sent_reg <= __phi_halo_cell__west_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__west_has_been_sent_reg;
      __phi_halo_cell__south_has_been_sent_reg <= __phi_halo_cell__south_has_been_sent_reg_load_en ? __phi_halo_cell__east_not_stage_load : __phi_halo_cell__south_has_been_sent_reg;
      __phi_halo_cell__syndrome_has_been_sent_reg <= __phi_halo_cell__syndrome_has_been_sent_reg_load_en ? __phi_halo_cell__syndrome_not_stage_load : __phi_halo_cell__syndrome_has_been_sent_reg;
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
      __phi_halo_cell__syndrome_reg <= phi_halo_cell__syndrome_load_en ? effects_syndrome : __phi_halo_cell__syndrome_reg;
      __phi_halo_cell__syndrome_valid_reg <= phi_halo_cell__syndrome_valid_load_en ? __phi_halo_cell__syndrome_valid_and_not_has_been_sent : __phi_halo_cell__syndrome_valid_reg;
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
  assign phi_halo_cell__syndrome = __phi_halo_cell__syndrome_reg;
  assign phi_halo_cell__syndrome_vld = __phi_halo_cell__syndrome_valid_reg;
  assign phi_halo_cell__west = __phi_halo_cell__west_reg;
  assign phi_halo_cell__west_vld = __phi_halo_cell__west_valid_reg;
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_16830 == __i0 ? and_16829 : ____state_13_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_16830 == __i0 ? sel_16862 : ____state_13_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_16830 == __i0 ? sel_16875 : ____state_13_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_17307 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_17307 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_17307 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_18118;
  wire eq_18123;
  wire ne_18107;
  wire and_18124;
  wire or_18121;
  wire [2:0] add_18115;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18110;
  wire popped;
  wire [1:0] sub_18136;
  wire [1:0] add_18138;
  wire [2:0] umod_18116;
  wire [2:0] umod_18111;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18140;
  wire array_update_18147[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18118 = pop_ready & push_valid;
  assign eq_18123 = head == tail;
  assign ne_18107 = head != tail;
  assign and_18124 = eq_18123 & and_18118;
  assign or_18121 = ne_18107 | push_valid;
  assign add_18115 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18110 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18121;
  assign sub_18136 = slots - 2'h1;
  assign add_18138 = slots + 2'h1;
  assign umod_18116 = add_18115 % long_buf_size_lit;
  assign umod_18111 = add_18110 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18116[1:0];
  assign did_push_occur = (can_do_push | and_18118) & push_valid & ~and_18124 & ~is_full_bool;
  assign next_tail_if_pop = umod_18111[1:0];
  assign did_pop_occur = (ne_18107 | and_18118) & pop_ready & ~and_18124;
  assign sel_18140 = pushed ? (popped ? slots : add_18138) : (popped ? sub_18136 : slots);
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
      slots <= sel_18140;
      buf__1[0] <= did_push_occur ? array_update_18147[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18147[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18121;
  assign pop_data = eq_18123 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18147_0
    assign array_update_18147[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18175;
  wire eq_18180;
  wire ne_18164;
  wire and_18181;
  wire or_18178;
  wire [2:0] add_18172;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18167;
  wire popped;
  wire [1:0] sub_18193;
  wire [1:0] add_18195;
  wire [2:0] umod_18173;
  wire [2:0] umod_18168;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18197;
  wire [127:0] array_update_18204[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18175 = pop_ready & push_valid;
  assign eq_18180 = head == tail;
  assign ne_18164 = head != tail;
  assign and_18181 = eq_18180 & and_18175;
  assign or_18178 = ne_18164 | push_valid;
  assign add_18172 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18167 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18178;
  assign sub_18193 = slots - 2'h1;
  assign add_18195 = slots + 2'h1;
  assign umod_18173 = add_18172 % long_buf_size_lit;
  assign umod_18168 = add_18167 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18173[1:0];
  assign did_push_occur = (can_do_push | and_18175) & push_valid & ~and_18181 & ~is_full_bool;
  assign next_tail_if_pop = umod_18168[1:0];
  assign did_pop_occur = (ne_18164 | and_18175) & pop_ready & ~and_18181;
  assign sel_18197 = pushed ? (popped ? slots : add_18195) : (popped ? sub_18193 : slots);
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
      slots <= sel_18197;
      buf__1[0] <= did_push_occur ? array_update_18204[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18204[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18178;
  assign pop_data = eq_18180 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18204_0
    assign array_update_18204[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18232;
  wire eq_18237;
  wire ne_18221;
  wire and_18238;
  wire or_18235;
  wire [2:0] add_18229;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18224;
  wire popped;
  wire [1:0] sub_18250;
  wire [1:0] add_18252;
  wire [2:0] umod_18230;
  wire [2:0] umod_18225;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18254;
  wire [127:0] array_update_18261[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18232 = pop_ready & push_valid;
  assign eq_18237 = head == tail;
  assign ne_18221 = head != tail;
  assign and_18238 = eq_18237 & and_18232;
  assign or_18235 = ne_18221 | push_valid;
  assign add_18229 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18224 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18235;
  assign sub_18250 = slots - 2'h1;
  assign add_18252 = slots + 2'h1;
  assign umod_18230 = add_18229 % long_buf_size_lit;
  assign umod_18225 = add_18224 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18230[1:0];
  assign did_push_occur = (can_do_push | and_18232) & push_valid & ~and_18238 & ~is_full_bool;
  assign next_tail_if_pop = umod_18225[1:0];
  assign did_pop_occur = (ne_18221 | and_18232) & pop_ready & ~and_18238;
  assign sel_18254 = pushed ? (popped ? slots : add_18252) : (popped ? sub_18250 : slots);
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
      slots <= sel_18254;
      buf__1[0] <= did_push_occur ? array_update_18261[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18261[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18235;
  assign pop_data = eq_18237 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18261_0
    assign array_update_18261[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18289;
  wire eq_18294;
  wire ne_18278;
  wire and_18295;
  wire or_18292;
  wire [2:0] add_18286;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18281;
  wire popped;
  wire [1:0] sub_18307;
  wire [1:0] add_18309;
  wire [2:0] umod_18287;
  wire [2:0] umod_18282;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18311;
  wire [127:0] array_update_18318[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18289 = pop_ready & push_valid;
  assign eq_18294 = head == tail;
  assign ne_18278 = head != tail;
  assign and_18295 = eq_18294 & and_18289;
  assign or_18292 = ne_18278 | push_valid;
  assign add_18286 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18281 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18292;
  assign sub_18307 = slots - 2'h1;
  assign add_18309 = slots + 2'h1;
  assign umod_18287 = add_18286 % long_buf_size_lit;
  assign umod_18282 = add_18281 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18287[1:0];
  assign did_push_occur = (can_do_push | and_18289) & push_valid & ~and_18295 & ~is_full_bool;
  assign next_tail_if_pop = umod_18282[1:0];
  assign did_pop_occur = (ne_18278 | and_18289) & pop_ready & ~and_18295;
  assign sel_18311 = pushed ? (popped ? slots : add_18309) : (popped ? sub_18307 : slots);
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
      slots <= sel_18311;
      buf__1[0] <= did_push_occur ? array_update_18318[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18318[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18292;
  assign pop_data = eq_18294 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18318_0
    assign array_update_18318[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18346;
  wire eq_18351;
  wire ne_18335;
  wire and_18352;
  wire or_18349;
  wire [2:0] add_18343;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18338;
  wire popped;
  wire [1:0] sub_18364;
  wire [1:0] add_18366;
  wire [2:0] umod_18344;
  wire [2:0] umod_18339;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18368;
  wire [127:0] array_update_18375[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18346 = pop_ready & push_valid;
  assign eq_18351 = head == tail;
  assign ne_18335 = head != tail;
  assign and_18352 = eq_18351 & and_18346;
  assign or_18349 = ne_18335 | push_valid;
  assign add_18343 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18338 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18349;
  assign sub_18364 = slots - 2'h1;
  assign add_18366 = slots + 2'h1;
  assign umod_18344 = add_18343 % long_buf_size_lit;
  assign umod_18339 = add_18338 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18344[1:0];
  assign did_push_occur = (can_do_push | and_18346) & push_valid & ~and_18352 & ~is_full_bool;
  assign next_tail_if_pop = umod_18339[1:0];
  assign did_pop_occur = (ne_18335 | and_18346) & pop_ready & ~and_18352;
  assign sel_18368 = pushed ? (popped ? slots : add_18366) : (popped ? sub_18364 : slots);
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
      slots <= sel_18368;
      buf__1[0] <= did_push_occur ? array_update_18375[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18375[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18349;
  assign pop_data = eq_18351 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18375_0
    assign array_update_18375[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18403;
  wire eq_18408;
  wire ne_18392;
  wire and_18409;
  wire or_18406;
  wire [2:0] add_18400;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18395;
  wire popped;
  wire [1:0] sub_18421;
  wire [1:0] add_18423;
  wire [2:0] umod_18401;
  wire [2:0] umod_18396;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18425;
  wire [127:0] array_update_18432[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18403 = pop_ready & push_valid;
  assign eq_18408 = head == tail;
  assign ne_18392 = head != tail;
  assign and_18409 = eq_18408 & and_18403;
  assign or_18406 = ne_18392 | push_valid;
  assign add_18400 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18395 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18406;
  assign sub_18421 = slots - 2'h1;
  assign add_18423 = slots + 2'h1;
  assign umod_18401 = add_18400 % long_buf_size_lit;
  assign umod_18396 = add_18395 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18401[1:0];
  assign did_push_occur = (can_do_push | and_18403) & push_valid & ~and_18409 & ~is_full_bool;
  assign next_tail_if_pop = umod_18396[1:0];
  assign did_pop_occur = (ne_18392 | and_18403) & pop_ready & ~and_18409;
  assign sel_18425 = pushed ? (popped ? slots : add_18423) : (popped ? sub_18421 : slots);
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
      slots <= sel_18425;
      buf__1[0] <= did_push_occur ? array_update_18432[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18432[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18406;
  assign pop_data = eq_18408 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18432_0
    assign array_update_18432[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_18460;
  wire eq_18465;
  wire ne_18449;
  wire and_18466;
  wire or_18463;
  wire [2:0] add_18457;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_18452;
  wire popped;
  wire [1:0] sub_18478;
  wire [1:0] add_18480;
  wire [2:0] umod_18458;
  wire [2:0] umod_18453;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_18482;
  wire [127:0] array_update_18489[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_18460 = pop_ready & push_valid;
  assign eq_18465 = head == tail;
  assign ne_18449 = head != tail;
  assign and_18466 = eq_18465 & and_18460;
  assign or_18463 = ne_18449 | push_valid;
  assign add_18457 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_18452 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_18463;
  assign sub_18478 = slots - 2'h1;
  assign add_18480 = slots + 2'h1;
  assign umod_18458 = add_18457 % long_buf_size_lit;
  assign umod_18453 = add_18452 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_18458[1:0];
  assign did_push_occur = (can_do_push | and_18460) & push_valid & ~and_18466 & ~is_full_bool;
  assign next_tail_if_pop = umod_18453[1:0];
  assign did_pop_occur = (ne_18449 | and_18460) & pop_ready & ~and_18466;
  assign sel_18482 = pushed ? (popped ? slots : add_18480) : (popped ? sub_18478 : slots);
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
      slots <= sel_18482;
      buf__1[0] <= did_push_occur ? array_update_18489[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_18489[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_18463;
  assign pop_data = eq_18465 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_18489_0
    assign array_update_18489[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  input wire phi_halo_cell__syndrome_send_rdy,
  input wire phi_halo_cell__west_send_rdy,
  output wire [32:0] phi_halo_cell__east_send,
  output wire phi_halo_cell__east_send_vld,
  output wire phi_halo_cell__ext_recv_rdy,
  output wire [32:0] phi_halo_cell__north_send,
  output wire phi_halo_cell__north_send_vld,
  output wire [32:0] phi_halo_cell__south_send,
  output wire phi_halo_cell__south_send_vld,
  output wire [32:0] phi_halo_cell__syndrome_send,
  output wire phi_halo_cell__syndrome_send_vld,
  output wire [32:0] phi_halo_cell__west_send,
  output wire phi_halo_cell__west_send_vld
);
  wire instantiation_output_17869;
  wire instantiation_output_17894;
  wire [127:0] instantiation_output_17918;
  wire instantiation_output_17919;
  wire instantiation_output_17907;
  wire [32:0] instantiation_output_17911;
  wire instantiation_output_17912;
  wire instantiation_output_17882;
  wire [32:0] instantiation_output_17886;
  wire instantiation_output_17887;
  wire instantiation_output_17977;
  wire [32:0] instantiation_output_17981;
  wire instantiation_output_17982;
  wire instantiation_output_17939;
  wire [32:0] instantiation_output_17943;
  wire instantiation_output_17944;
  wire instantiation_output_17958;
  wire [32:0] instantiation_output_17962;
  wire instantiation_output_17963;
  wire instantiation_output_17861;
  wire instantiation_output_17862;
  wire [127:0] instantiation_output_17874;
  wire instantiation_output_17875;
  wire [127:0] instantiation_output_17899;
  wire instantiation_output_17900;
  wire instantiation_output_17926;
  wire [127:0] instantiation_output_17931;
  wire instantiation_output_17932;
  wire [127:0] instantiation_output_17950;
  wire instantiation_output_17951;
  wire [127:0] instantiation_output_17969;
  wire instantiation_output_17970;
  wire instantiation_output_18497;
  wire instantiation_output_18498;
  wire instantiation_output_18499;
  wire instantiation_output_18504;
  wire [127:0] instantiation_output_18505;
  wire instantiation_output_18506;
  wire instantiation_output_18511;
  wire [127:0] instantiation_output_18512;
  wire instantiation_output_18513;
  wire instantiation_output_18518;
  wire [127:0] instantiation_output_18519;
  wire instantiation_output_18520;
  wire instantiation_output_18525;
  wire [127:0] instantiation_output_18526;
  wire instantiation_output_18527;
  wire instantiation_output_18532;
  wire [127:0] instantiation_output_18533;
  wire instantiation_output_18534;
  wire instantiation_output_18539;
  wire [127:0] instantiation_output_18540;
  wire instantiation_output_18541;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_18498),
    .phi_halo_cell__admit_vld(instantiation_output_18499),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_18518),
    .phi_halo_cell__admit_rdy(instantiation_output_17869),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_17894),
    .phi_halo_cell__req(instantiation_output_17918),
    .phi_halo_cell__req_vld(instantiation_output_17919),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_18512),
    .phi_halo_cell__north_vld(instantiation_output_18513),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_17907),
    .phi_halo_cell__north_send(instantiation_output_17911),
    .phi_halo_cell__north_send_vld(instantiation_output_17912),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_18505),
    .phi_halo_cell__east_vld(instantiation_output_18506),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_17882),
    .phi_halo_cell__east_send(instantiation_output_17886),
    .phi_halo_cell__east_send_vld(instantiation_output_17887),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_18540),
    .phi_halo_cell__west_vld(instantiation_output_18541),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_17977),
    .phi_halo_cell__west_send(instantiation_output_17981),
    .phi_halo_cell__west_send_vld(instantiation_output_17982),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_18526),
    .phi_halo_cell__south_vld(instantiation_output_18527),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_17939),
    .phi_halo_cell__south_send(instantiation_output_17943),
    .phi_halo_cell__south_send_vld(instantiation_output_17944),
    .clk(clk)
  );
  __axis__Top__Tx_4_next __axis__Top__Tx_4_next_inst5 (
    .reset(reset),
    .phi_halo_cell__syndrome(instantiation_output_18533),
    .phi_halo_cell__syndrome_vld(instantiation_output_18534),
    .phi_halo_cell__syndrome_send_rdy(phi_halo_cell__syndrome_send_rdy),
    .phi_halo_cell__syndrome_rdy(instantiation_output_17958),
    .phi_halo_cell__syndrome_send(instantiation_output_17962),
    .phi_halo_cell__syndrome_send_vld(instantiation_output_17963),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst6 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst7 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_18497),
    .phi_halo_cell__east_rdy(instantiation_output_18504),
    .phi_halo_cell__north_rdy(instantiation_output_18511),
    .phi_halo_cell__req(instantiation_output_18519),
    .phi_halo_cell__req_vld(instantiation_output_18520),
    .phi_halo_cell__south_rdy(instantiation_output_18525),
    .phi_halo_cell__syndrome_rdy(instantiation_output_18532),
    .phi_halo_cell__west_rdy(instantiation_output_18539),
    .phi_halo_cell__admit(instantiation_output_17861),
    .phi_halo_cell__admit_vld(instantiation_output_17862),
    .phi_halo_cell__east(instantiation_output_17874),
    .phi_halo_cell__east_vld(instantiation_output_17875),
    .phi_halo_cell__north(instantiation_output_17899),
    .phi_halo_cell__north_vld(instantiation_output_17900),
    .phi_halo_cell__req_rdy(instantiation_output_17926),
    .phi_halo_cell__south(instantiation_output_17931),
    .phi_halo_cell__south_vld(instantiation_output_17932),
    .phi_halo_cell__syndrome(instantiation_output_17950),
    .phi_halo_cell__syndrome_vld(instantiation_output_17951),
    .phi_halo_cell__west(instantiation_output_17969),
    .phi_halo_cell__west_vld(instantiation_output_17970),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_17861),
    .push_valid(instantiation_output_17862),
    .pop_ready(instantiation_output_17869),
    .push_ready(instantiation_output_18497),
    .pop_data(instantiation_output_18498),
    .pop_valid(instantiation_output_18499),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_17874),
    .push_valid(instantiation_output_17875),
    .pop_ready(instantiation_output_17882),
    .push_ready(instantiation_output_18504),
    .pop_data(instantiation_output_18505),
    .pop_valid(instantiation_output_18506),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_17899),
    .push_valid(instantiation_output_17900),
    .pop_ready(instantiation_output_17907),
    .push_ready(instantiation_output_18511),
    .pop_data(instantiation_output_18512),
    .pop_valid(instantiation_output_18513),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_17918),
    .push_valid(instantiation_output_17919),
    .pop_ready(instantiation_output_17926),
    .push_ready(instantiation_output_18518),
    .pop_data(instantiation_output_18519),
    .pop_valid(instantiation_output_18520),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_17931),
    .push_valid(instantiation_output_17932),
    .pop_ready(instantiation_output_17939),
    .push_ready(instantiation_output_18525),
    .pop_data(instantiation_output_18526),
    .pop_valid(instantiation_output_18527),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__syndrome_ (
    .reset(reset),
    .push_data(instantiation_output_17950),
    .push_valid(instantiation_output_17951),
    .pop_ready(instantiation_output_17958),
    .push_ready(instantiation_output_18532),
    .pop_data(instantiation_output_18533),
    .pop_valid(instantiation_output_18534),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___5 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_17969),
    .push_valid(instantiation_output_17970),
    .pop_ready(instantiation_output_17977),
    .push_ready(instantiation_output_18539),
    .pop_data(instantiation_output_18540),
    .pop_valid(instantiation_output_18541),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_17886;
  assign phi_halo_cell__east_send_vld = instantiation_output_17887;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_17894;
  assign phi_halo_cell__north_send = instantiation_output_17911;
  assign phi_halo_cell__north_send_vld = instantiation_output_17912;
  assign phi_halo_cell__south_send = instantiation_output_17943;
  assign phi_halo_cell__south_send_vld = instantiation_output_17944;
  assign phi_halo_cell__syndrome_send = instantiation_output_17962;
  assign phi_halo_cell__syndrome_send_vld = instantiation_output_17963;
  assign phi_halo_cell__west_send = instantiation_output_17981;
  assign phi_halo_cell__west_send_vld = instantiation_output_17982;
endmodule
