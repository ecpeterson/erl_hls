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
  wire [32:0] literal_11254 = {1'h0, 32'h0000_0000};
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
  wire and_11264;
  wire phi_halo_cell__req_valid_inv;
  wire __phi_halo_cell__req_vld_buf;
  wire phi_halo_cell__req_valid_load_en;
  wire nor_11263;
  wire phi_halo_cell__req_not_pred;
  wire phi_halo_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_11276;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_12944;
  wire phi_halo_cell__admit_valid_inv;
  wire phi_halo_cell__ext_recv_valid_inv;
  wire [31:0] sel_12943;
  wire [31:0] sel_12942;
  wire [31:0] sel_12941;
  wire phi_halo_cell__admit_valid_load_en;
  wire phi_halo_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_11321;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__ext_recv_load_en;
  wire or_12947;
  wire nand_11292;
  wire [127:0] one_hot_sel_11322;
  wire and_11336;
  wire [7:0] one_hot_sel_11329;
  wire [127:0] __phi_halo_cell__req_buf;
  assign phi_halo_cell__ext_recv_select = ____state_0 ? __phi_halo_cell__ext_recv_reg : literal_11254;
  assign beat_tlast = phi_halo_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phi_halo_cell__ext_recv_valid_reg) & (____state_0 | __phi_halo_cell__admit_valid_reg);
  assign and_11264 = ____state_0 & beat_tlast;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign __phi_halo_cell__req_vld_buf = p0_all_active_inputs_valid & and_11264;
  assign phi_halo_cell__req_valid_load_en = phi_halo_cell__req_rdy | phi_halo_cell__req_valid_inv;
  assign nor_11263 = ~(~____state_0 | beat_tlast);
  assign phi_halo_cell__req_not_pred = ~and_11264;
  assign phi_halo_cell__req_load_en = __phi_halo_cell__req_vld_buf & phi_halo_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_11263, and_11264};
  assign one_hot_11276 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phi_halo_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phi_halo_cell__req_not_pred | phi_halo_cell__req_load_en);
  assign sel_12944 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign phi_halo_cell__ext_recv_valid_inv = ~__phi_halo_cell__ext_recv_valid_reg;
  assign sel_12943 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_12942 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_12941 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phi_halo_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phi_halo_cell__admit_valid_inv;
  assign phi_halo_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phi_halo_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_11263 == one_hot_11276[1] & and_11264 == one_hot_11276[0];
  assign concat_11321 = {nor_11263 & p0_stage_done, and_11264 & p0_stage_done};
  assign payload = {sel_12943, sel_12942, sel_12941, sel_12944};
  assign words_seen = ____state_2 + 8'h01;
  assign phi_halo_cell__admit_load_en = phi_halo_cell__admit_vld & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__ext_recv_load_en = phi_halo_cell__ext_recv_vld & phi_halo_cell__ext_recv_valid_load_en;
  assign or_12947 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_11292 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_11322 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11321[0]}} | payload & {128{concat_11321[1]}};
  assign and_11336 = (nor_11263 | and_11264) & p0_stage_done;
  assign one_hot_sel_11329 = 8'h00 & {8{concat_11321[0]}} | words_seen & {8{concat_11321[1]}};
  assign __phi_halo_cell__req_buf = {{sel_12944[7:0], sel_12944[15:8], sel_12944[23:16], sel_12944[31:24]}, {sel_12943, sel_12942, sel_12941}};
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
      ____state_0 <= p0_stage_done ? nand_11292 : ____state_0;
      ____state_2 <= and_11336 ? one_hot_sel_11329 : ____state_2;
      ____state_1 <= and_11336 ? one_hot_sel_11322 : ____state_1;
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
  wire [127:0] literal_11392 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_11404;
  wire not_11405;
  wire __phi_halo_cell__north_send_vld_buf;
  wire phi_halo_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__north_send_load_en;
  wire [2:0] one_hot_11414;
  wire [2:0] one_hot_11415;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__north_valid_inv;
  wire and_11454;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_11457;
  wire [127:0] payload;
  wire [1:0] concat_11470;
  wire [7:0] beats_sent;
  wire phi_halo_cell__north_load_en;
  wire or_12951;
  wire or_12955;
  wire [7:0] one_hot_sel_11458;
  wire and_11478;
  wire [127:0] one_hot_sel_11465;
  wire [7:0] one_hot_sel_11471;
  wire [32:0] __phi_halo_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__north_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__north_reg : literal_11392;
  assign frame_header__1 = phi_halo_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__north_send_valid_inv = ~__phi_halo_cell__north_send_valid_reg;
  assign nor_11404 = ~(last | ____state_0);
  assign not_11405 = ~last;
  assign __phi_halo_cell__north_send_vld_buf = ____state_0 | __phi_halo_cell__north_valid_reg;
  assign phi_halo_cell__north_send_valid_load_en = phi_halo_cell__north_send_rdy | phi_halo_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_11404};
  assign ____state_6__next_value_predicates = {not_11405, last};
  assign phi_halo_cell__north_send_load_en = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_valid_load_en;
  assign one_hot_11414 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_11415 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__north_send_vld_buf & phi_halo_cell__north_send_load_en;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign and_11454 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_11414[1] & nor_11404 == one_hot_11414[0];
  assign ____state_6__at_most_one_next_value = not_11405 == one_hot_11415[1] & last == one_hot_11415[0];
  assign concat_11457 = {and_11454, nor_11404 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_11470 = {not_11405 & p0_stage_done, and_11454};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__north_load_en = phi_halo_cell__north_vld & phi_halo_cell__north_valid_load_en;
  assign or_12951 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12955 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_11458 = frame_header_payload_words__1 & {8{concat_11457[0]}} | 8'h00 & {8{concat_11457[1]}};
  assign and_11478 = (last | nor_11404) & p0_stage_done;
  assign one_hot_sel_11465 = payload & {128{concat_11457[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11457[1]}};
  assign one_hot_sel_11471 = 8'h00 & {8{concat_11470[0]}} | beats_sent & {8{concat_11470[1]}};
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
      ____state_0 <= p0_stage_done ? not_11405 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_11471 : ____state_6;
      ____state_1 <= and_11478 ? one_hot_sel_11458 : ____state_1;
      ____state_5 <= and_11478 ? one_hot_sel_11465 : ____state_5;
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
  wire [127:0] literal_11527 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_11539;
  wire not_11540;
  wire __phi_halo_cell__east_send_vld_buf;
  wire phi_halo_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__east_send_load_en;
  wire [2:0] one_hot_11549;
  wire [2:0] one_hot_11550;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__east_valid_inv;
  wire and_11589;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_11592;
  wire [127:0] payload;
  wire [1:0] concat_11605;
  wire [7:0] beats_sent;
  wire phi_halo_cell__east_load_en;
  wire or_12957;
  wire or_12961;
  wire [7:0] one_hot_sel_11593;
  wire and_11613;
  wire [127:0] one_hot_sel_11600;
  wire [7:0] one_hot_sel_11606;
  wire [32:0] __phi_halo_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__east_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__east_reg : literal_11527;
  assign frame_header__1 = phi_halo_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__east_send_valid_inv = ~__phi_halo_cell__east_send_valid_reg;
  assign nor_11539 = ~(last | ____state_0);
  assign not_11540 = ~last;
  assign __phi_halo_cell__east_send_vld_buf = ____state_0 | __phi_halo_cell__east_valid_reg;
  assign phi_halo_cell__east_send_valid_load_en = phi_halo_cell__east_send_rdy | phi_halo_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_11539};
  assign ____state_6__next_value_predicates = {not_11540, last};
  assign phi_halo_cell__east_send_load_en = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_valid_load_en;
  assign one_hot_11549 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_11550 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__east_send_vld_buf & phi_halo_cell__east_send_load_en;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign and_11589 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_11549[1] & nor_11539 == one_hot_11549[0];
  assign ____state_6__at_most_one_next_value = not_11540 == one_hot_11550[1] & last == one_hot_11550[0];
  assign concat_11592 = {and_11589, nor_11539 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_11605 = {not_11540 & p0_stage_done, and_11589};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__east_load_en = phi_halo_cell__east_vld & phi_halo_cell__east_valid_load_en;
  assign or_12957 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12961 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_11593 = frame_header_payload_words__1 & {8{concat_11592[0]}} | 8'h00 & {8{concat_11592[1]}};
  assign and_11613 = (last | nor_11539) & p0_stage_done;
  assign one_hot_sel_11600 = payload & {128{concat_11592[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11592[1]}};
  assign one_hot_sel_11606 = 8'h00 & {8{concat_11605[0]}} | beats_sent & {8{concat_11605[1]}};
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
      ____state_0 <= p0_stage_done ? not_11540 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_11606 : ____state_6;
      ____state_1 <= and_11613 ? one_hot_sel_11593 : ____state_1;
      ____state_5 <= and_11613 ? one_hot_sel_11600 : ____state_5;
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
  wire [127:0] literal_11662 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_11674;
  wire not_11675;
  wire __phi_halo_cell__west_send_vld_buf;
  wire phi_halo_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__west_send_load_en;
  wire [2:0] one_hot_11684;
  wire [2:0] one_hot_11685;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__west_valid_inv;
  wire and_11724;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_11727;
  wire [127:0] payload;
  wire [1:0] concat_11740;
  wire [7:0] beats_sent;
  wire phi_halo_cell__west_load_en;
  wire or_12963;
  wire or_12967;
  wire [7:0] one_hot_sel_11728;
  wire and_11748;
  wire [127:0] one_hot_sel_11735;
  wire [7:0] one_hot_sel_11741;
  wire [32:0] __phi_halo_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__west_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__west_reg : literal_11662;
  assign frame_header__1 = phi_halo_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__west_send_valid_inv = ~__phi_halo_cell__west_send_valid_reg;
  assign nor_11674 = ~(last | ____state_0);
  assign not_11675 = ~last;
  assign __phi_halo_cell__west_send_vld_buf = ____state_0 | __phi_halo_cell__west_valid_reg;
  assign phi_halo_cell__west_send_valid_load_en = phi_halo_cell__west_send_rdy | phi_halo_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_11674};
  assign ____state_6__next_value_predicates = {not_11675, last};
  assign phi_halo_cell__west_send_load_en = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_valid_load_en;
  assign one_hot_11684 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_11685 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__west_send_vld_buf & phi_halo_cell__west_send_load_en;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign and_11724 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_11684[1] & nor_11674 == one_hot_11684[0];
  assign ____state_6__at_most_one_next_value = not_11675 == one_hot_11685[1] & last == one_hot_11685[0];
  assign concat_11727 = {and_11724, nor_11674 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_11740 = {not_11675 & p0_stage_done, and_11724};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__west_load_en = phi_halo_cell__west_vld & phi_halo_cell__west_valid_load_en;
  assign or_12963 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12967 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_11728 = frame_header_payload_words__1 & {8{concat_11727[0]}} | 8'h00 & {8{concat_11727[1]}};
  assign and_11748 = (last | nor_11674) & p0_stage_done;
  assign one_hot_sel_11735 = payload & {128{concat_11727[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11727[1]}};
  assign one_hot_sel_11741 = 8'h00 & {8{concat_11740[0]}} | beats_sent & {8{concat_11740[1]}};
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
      ____state_0 <= p0_stage_done ? not_11675 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_11741 : ____state_6;
      ____state_1 <= and_11748 ? one_hot_sel_11728 : ____state_1;
      ____state_5 <= and_11748 ? one_hot_sel_11735 : ____state_5;
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
  wire [127:0] literal_11797 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
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
  wire nor_11809;
  wire not_11810;
  wire __phi_halo_cell__south_send_vld_buf;
  wire phi_halo_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phi_halo_cell__south_send_load_en;
  wire [2:0] one_hot_11819;
  wire [2:0] one_hot_11820;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phi_halo_cell__south_valid_inv;
  wire and_11859;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phi_halo_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_11862;
  wire [127:0] payload;
  wire [1:0] concat_11875;
  wire [7:0] beats_sent;
  wire phi_halo_cell__south_load_en;
  wire or_12969;
  wire or_12973;
  wire [7:0] one_hot_sel_11863;
  wire and_11883;
  wire [127:0] one_hot_sel_11870;
  wire [7:0] one_hot_sel_11876;
  wire [32:0] __phi_halo_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phi_halo_cell__south_select = state2_header_payload_words_0_case_cmp ? __phi_halo_cell__south_reg : literal_11797;
  assign frame_header__1 = phi_halo_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phi_halo_cell__south_send_valid_inv = ~__phi_halo_cell__south_send_valid_reg;
  assign nor_11809 = ~(last | ____state_0);
  assign not_11810 = ~last;
  assign __phi_halo_cell__south_send_vld_buf = ____state_0 | __phi_halo_cell__south_valid_reg;
  assign phi_halo_cell__south_send_valid_load_en = phi_halo_cell__south_send_rdy | phi_halo_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_11809};
  assign ____state_6__next_value_predicates = {not_11810, last};
  assign phi_halo_cell__south_send_load_en = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_valid_load_en;
  assign one_hot_11819 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_11820 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phi_halo_cell__south_send_vld_buf & phi_halo_cell__south_send_load_en;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_11859 = last & p0_stage_done;
  assign frame_payload__1 = phi_halo_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phi_halo_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phi_halo_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_11819[1] & nor_11809 == one_hot_11819[0];
  assign ____state_6__at_most_one_next_value = not_11810 == one_hot_11820[1] & last == one_hot_11820[0];
  assign concat_11862 = {and_11859, nor_11809 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_11875 = {not_11810 & p0_stage_done, and_11859};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phi_halo_cell__south_load_en = phi_halo_cell__south_vld & phi_halo_cell__south_valid_load_en;
  assign or_12969 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_12973 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_11863 = frame_header_payload_words__1 & {8{concat_11862[0]}} | 8'h00 & {8{concat_11862[1]}};
  assign and_11883 = (last | nor_11809) & p0_stage_done;
  assign one_hot_sel_11870 = payload & {128{concat_11862[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_11862[1]}};
  assign one_hot_sel_11876 = 8'h00 & {8{concat_11875[0]}} | beats_sent & {8{concat_11875[1]}};
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
      ____state_0 <= p0_stage_done ? not_11810 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_11876 : ____state_6;
      ____state_1 <= and_11883 ? one_hot_sel_11863 : ____state_1;
      ____state_5 <= and_11883 ? one_hot_sel_11870 : ____state_5;
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
  wire ____state_12_tuple_element_0_init[0:4];
  assign ____state_12_tuple_element_0_init[0] = 1'h0;
  assign ____state_12_tuple_element_0_init[1] = 1'h0;
  assign ____state_12_tuple_element_0_init[2] = 1'h0;
  assign ____state_12_tuple_element_0_init[3] = 1'h0;
  assign ____state_12_tuple_element_0_init[4] = 1'h0;
  wire [95:0] ____state_12_tuple_element_1_tuple_element_1_init[0:4];
  assign ____state_12_tuple_element_1_tuple_element_1_init[0] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_12_tuple_element_1_tuple_element_1_init[1] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_12_tuple_element_1_tuple_element_1_init[2] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_12_tuple_element_1_tuple_element_1_init[3] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_12_tuple_element_1_tuple_element_1_init[4] = 96'h0000_0000_0000_0000_0000_0000;
  wire [7:0] ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[0:4];
  assign ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[0] = 8'h00;
  assign ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[1] = 8'h00;
  assign ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[2] = 8'h00;
  assign ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[3] = 8'h00;
  assign ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[4] = 8'h00;
  wire [127:0] __phi_halo_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phi_halo_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_11991 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  reg ____state_15;
  reg ____state_16;
  reg ____state_14;
  reg ____state_12_tuple_element_0[0:4];
  reg [7:0] ____state_13;
  reg [95:0] ____state_12_tuple_element_1_tuple_element_1[0:4];
  reg [7:0] ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[0:4];
  reg [31:0] ____state_7;
  reg [31:0] ____state_2;
  reg [31:0] ____state_3;
  reg [1:0] ____state_0;
  reg [1:0] ____state_10;
  reg [1:0] ____state_6;
  reg [31:0] ____state_5_1;
  reg [31:0] ____state_5_0;
  reg [31:0] ____state_4_1;
  reg [31:0] ____state_4_0;
  reg [31:0] ____state_11;
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
  wire nor_11989;
  wire received;
  wire [127:0] phi_halo_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_12000;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_12016;
  wire [31:0] concat_12017;
  wire ugt_12019;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_12021;
  wire postponed__4;
  wire ugt_12025;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_2029_0__2_case_0_case_1_case_0;
  wire or_reduce_12029;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_12040;
  wire postponed;
  wire [95:0] sel_12049;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_12052;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Value1_1;
  wire [31:0] _12_source;
  wire [31:0] _9_source;
  wire [31:0] _6__5_source;
  wire [31:0] _3__5_source;
  wire [7:0] sel_12061;
  wire [31:0] Xls_clause_2_Epoch_1;
  wire _0__15;
  wire _1__5;
  wire _2__5;
  wire [31:0] _7__3;
  wire [1:0] unexpand_for_next_value_2029_0__2_case_0_case_0_case_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire eq_12073;
  wire _8__3;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [1:0] unexpand_for_next_value_2029_0__2_case_0_case_0_case_2;
  wire [30:0] add_12077;
  wire eq_12079;
  wire nor_12080;
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire and_12082;
  wire _21__2;
  wire eq_12084;
  wire [31:0] _1;
  wire or_12089;
  wire eq_12090;
  wire nand_12091;
  wire eq_12092;
  wire [31:0] _2__1;
  wire eq_12097;
  wire eq_12098;
  wire _0__11;
  wire [1:0] concat_12104;
  wire [1:0] concat_12106;
  wire and_12108;
  wire _4__1;
  wire postponed_slot_tup0;
  wire eligible_0;
  wire invalid_input;
  wire eq_12121;
  wire _6__1;
  wire [1:0] priority_sel_12125;
  wire _3;
  wire _19;
  wire _47;
  wire found;
  wire compacted_4_tup0;
  wire nand_12141;
  wire and_12144;
  wire dispatchable;
  wire [1:0] priority_sel_12154;
  wire [1:0] concat_12156;
  wire [1:0] directive;
  wire [1:0] next_phase_squeezed;
  wire repeat_phase;
  wire invalid_repeat;
  wire transition_slots_default_case_cmp;
  wire effective;
  wire transition_slots_predicate_piece_0;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_12191;
  wire candidate_slots_0_case_cmp;
  wire [1:0] candidate_phase_squeezed;
  wire failed;
  wire [7:0] candidate_occupied;
  wire phase_changed;
  wire phase_boundary;
  wire reserve__1;
  wire reserve;
  wire and_12178;
  wire nor_12179;
  wire final_slots_0_case_cmp;
  wire and_12183;
  wire and_12184;
  wire and_12186;
  wire and_12187;
  wire and_12188;
  wire eq_12189;
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
  wire and_12197;
  wire and_12198;
  wire candidate_occupied_0_case_cmp;
  wire and_12203;
  wire and_12205;
  wire and_12206;
  wire or_12207;
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
  wire and_12216;
  wire and_12217;
  wire and_12218;
  wire and_12219;
  wire and_12220;
  wire and_12221;
  wire and_12223;
  wire and_12224;
  wire and_12225;
  wire and_12226;
  wire and_12227;
  wire and_12228;
  wire and_12229;
  wire and_12230;
  wire and_12231;
  wire and_12232;
  wire and_12233;
  wire and_12234;
  wire and_12235;
  wire and_12236;
  wire and_12237;
  wire and_12238;
  wire and_12239;
  wire and_12240;
  wire and_12241;
  wire [31:0] Xls_clause_1_Value_1;
  wire [31:0] _12;
  wire phi_halo_cell__admit_not_pred;
  wire phi_halo_cell__admit_load_en;
  wire phi_halo_cell__east_not_pred;
  wire phi_halo_cell__north_load_en;
  wire phi_halo_cell__east_load_en;
  wire phi_halo_cell__west_load_en;
  wire phi_halo_cell__south_load_en;
  wire [1:0] ____state_3__next_value_predicates;
  wire [1:0] ____state_7__next_value_predicates;
  wire [1:0] ____state_13__next_value_predicates;
  wire [1:0] ____state_15__next_value_predicates;
  wire [10:0] ____state_0__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [4:0] ____state_12_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_12_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [31:0] _8;
  wire [31:0] _35;
  wire [2:0] one_hot_12286;
  wire [2:0] one_hot_12287;
  wire [2:0] one_hot_12288;
  wire [2:0] one_hot_12289;
  wire [11:0] one_hot_12290;
  wire [2:0] one_hot_12291;
  wire [2:0] one_hot_12292;
  wire [5:0] one_hot_12293;
  wire [8:0] one_hot_12294;
  wire [30:0] add_12249;
  wire [63:0] umul_12250;
  wire [95:0] array_index_12265;
  wire [95:0] array_index_12267;
  wire [95:0] array_index_12269;
  wire [7:0] array_index_12273;
  wire [7:0] array_index_12275;
  wire [7:0] array_index_12277;
  wire p0_all_active_outputs_ready;
  wire [30:0] add_12283;
  wire ne_12308;
  wire or_reduce_12310;
  wire ugt_12312;
  wire phi_halo_cell__req_valid_inv;
  wire and_12531;
  wire and_12532;
  wire and_12538;
  wire admission_pending;
  wire [15:0] add_12326;
  wire and_12609;
  wire and_12610;
  wire and_12611;
  wire and_12612;
  wire [31:0] concat_12381;
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
  wire [95:0] concat_12297;
  wire [95:0] concat_12299;
  wire phi_halo_cell__req_valid_load_en;
  wire ____state_3__at_most_one_next_value;
  wire ____state_7__at_most_one_next_value;
  wire ____state_13__at_most_one_next_value;
  wire ____state_15__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_10__at_most_one_next_value;
  wire ____state_12_tuple_element_0__at_most_one_next_value;
  wire ____state_12_tuple_element_1_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_12534;
  wire [31:0] _42;
  wire [1:0] concat_12541;
  wire [1:0] concat_12551;
  wire [1:0] concat_12561;
  wire [31:0] _27;
  wire [31:0] _30;
  wire [30:0] add_12392;
  wire [31:0] sign_ext_12393;
  wire [10:0] concat_12590;
  wire [1:0] concat_12597;
  wire [1:0] unexpand_for_next_value_2029_6__2_case_0_case_0_case_0_case_1_case_0;
  wire [1:0] concat_12604;
  wire [1:0] unexpand_for_next_value_2029_10__2_case_0_case_1_case_2_case_1_case_0;
  wire [4:0] concat_12614;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_12627;
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
  wire [31:0] tuple_12367;
  wire phi_halo_cell__req_load_en;
  wire or_12975;
  wire or_12977;
  wire or_12979;
  wire or_12981;
  wire or_12983;
  wire or_12985;
  wire or_12987;
  wire or_12989;
  wire or_12991;
  wire [31:0] _8__1;
  wire and_12650;
  wire [31:0] one_hot_sel_12535;
  wire and_12653;
  wire [31:0] one_hot_sel_12542;
  wire and_12656;
  wire [31:0] Xls_clause_1_NextAnyon_1;
  wire and_12658;
  wire [7:0] one_hot_sel_12552;
  wire and_12661;
  wire and_12438;
  wire and_12663;
  wire one_hot_sel_12562;
  wire and_12666;
  wire or_12436;
  wire [31:0] _31;
  wire and_12669;
  wire [31:0] _37;
  wire [31:0] and_12454;
  wire and_12673;
  wire [31:0] and_12455;
  wire [1:0] one_hot_sel_12591;
  wire and_12678;
  wire [1:0] one_hot_sel_12598;
  wire and_12681;
  wire [1:0] one_hot_sel_12605;
  wire and_12684;
  wire one_hot_sel_12615[0:4];
  wire and_12687;
  wire [95:0] one_hot_sel_12628[0:4];
  wire and_12690;
  wire [7:0] one_hot_sel_12641[0:4];
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
  assign nor_11989 = ~(____state_16 | ____state_14 | ~____state_15);
  assign received = nor_11989 & __phi_halo_cell__req_valid_reg;
  assign phi_halo_cell__req_select = received ? __phi_halo_cell__req_reg : literal_11991;
  assign frame_header = phi_halo_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_12000 = frame_header__1_payload_words == 8'h03;
  assign tag_ok = frame_header_op == 8'h03 & eq_12000 | frame_header_op == 8'h04 & frame_header__1_payload_words == 8'h02 | frame_header_op == MAILBOX_CAPACITY & eq_12000;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_13 + {7'h00, accepted};
  assign and_12016 = ~accepted & ____state_12_tuple_element_0[____state_13 > 8'h04 ? 3'h4 : ____state_13[2:0]];
  assign concat_12017 = {24'h00_0000, ____state_13};
  assign ugt_12019 = admitted_occupied > 8'h04;
  assign or_reduce_12021 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_12025 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_12019 | postponed__4);
  assign unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 = 2'h0;
  assign or_reduce_12029 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_12021 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_12025 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_12029 | postponed__1);
  assign eq_12040 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_12049 = accepted ? phi_halo_cell__req_select[95:0] : ____state_12_tuple_element_1_tuple_element_1[____state_13 > 8'h04 ? 3'h4 : ____state_13[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_2029_0__2_case_0_case_1_case_0}))} & {8{eq_12040 | postponed}};
  assign bit_slice_12052 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_12052 > 3'h4 ? 3'h4 : bit_slice_12052];
  assign Xls_clause_1_Value1_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _12_source = 32'h0000_0001;
  assign _9_source = 32'h0000_0002;
  assign _6__5_source = 32'h0000_0004;
  assign _3__5_source = 32'h0000_0008;
  assign sel_12061 = accepted ? frame_header_op : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[____state_13 > 8'h04 ? 3'h4 : ____state_13[2:0]];
  assign Xls_clause_2_Epoch_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__15 = Xls_clause_1_Value1_1 == _12_source;
  assign _1__5 = Xls_clause_1_Value1_1 == _9_source;
  assign _2__5 = Xls_clause_1_Value1_1 == _6__5_source;
  assign _7__3 = ____state_7 & Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 = 2'h1;
  assign eq_12073 = Xls_clause_2_Epoch_1 == ____state_2;
  assign _8__3 = _7__3 == 32'h0000_0000;
  assign Xls_clause_1_NewSeen_1 = ____state_7 | Xls_clause_1_Value1_1;
  assign unexpand_for_next_value_2029_0__2_case_0_case_0_case_2 = 2'h2;
  assign add_12077 = ____state_2[30:0] + ____state_3[31:1];
  assign eq_12079 = ____state_0 == unexpand_for_next_value_2029_0__2_case_0_case_0_case_1;
  assign nor_12080 = ~(____state_0[0] | ____state_0[1]);
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_12052 > 3'h4 ? 3'h4 : bit_slice_12052];
  assign and_12082 = eq_12073 & (_0__15 | _1__5 | _2__5 | Xls_clause_1_Value1_1 == _3__5_source) & _8__3;
  assign _21__2 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign eq_12084 = ____state_0 == unexpand_for_next_value_2029_0__2_case_0_case_0_case_2;
  assign _1 = {add_12077, ____state_3[0]};
  assign or_12089 = eq_12079 | nor_12080;
  assign eq_12090 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04;
  assign nand_12091 = ~(and_12082 & _21__2);
  assign eq_12092 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign _2__1 = _1 + _12_source;
  assign eq_12097 = add_12077 == selected_slot_tuple_idx_1_tuple_idx_1[31:1];
  assign eq_12098 = ____state_3[0] == selected_slot_tuple_idx_1_tuple_idx_1[0];
  assign _0__11 = selected_slot_tuple_idx_1_tuple_idx_1[63:33] == 31'h0000_0000;
  assign concat_12104 = {eq_12084, or_12089};
  assign concat_12106 = {eq_12079, nor_12080};
  assign and_12108 = eq_12092 & ~(eq_12084 | eq_12079) & (____state_0[0] | ____state_0[1]);
  assign _4__1 = Xls_clause_2_Epoch_1 == _2__1;
  assign postponed_slot_tup0 = 1'h1;
  assign eligible_0 = ~(eq_12040 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign eq_12121 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY;
  assign _6__1 = ____state_10 == 2'h3;
  assign priority_sel_12125 = priority_sel_2b_2way(concat_12106, unexpand_for_next_value_2029_0__2_case_0_case_1_case_0, nand_12091 ? unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2029_0__2_case_0_case_0_case_2, ____state_0);
  assign _3 = eq_12097 & eq_12098;
  assign _19 = ____state_6 == 2'h3;
  assign _47 = ____state_3 == _12_source;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign compacted_4_tup0 = 1'h0;
  assign nand_12141 = ~(eq_12073 & _0__11 & _6__1);
  assign and_12144 = _3 & _19 & _47;
  assign dispatchable = found & ~invalid_input;
  assign priority_sel_12154 = priority_sel_2b_5way({eq_12121, eq_12090, and_12108, {2{eq_12092}} & {eq_12084 | eq_12079, nor_12080}}, (_4__1 ? unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2029_0__2_case_0_case_0_case_2) & {2{~(eq_12097 & eq_12098)}}, _3 ? unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2029_0__2_case_0_case_0_case_2, unexpand_for_next_value_2029_0__2_case_0_case_0_case_2, {priority_sel_1b_2way(concat_12104, ~eq_12073, ~(eq_12073 & _0__11), postponed_slot_tup0), eq_12073 & or_12089}, {priority_sel_1b_2way(concat_12106, ~eq_12073, ~and_12082, postponed_slot_tup0), ~(~eq_12073 | ____state_0[0] | ____state_0[1])}, unexpand_for_next_value_2029_0__2_case_0_case_0_case_2);
  assign concat_12156 = {priority_sel_1b_5way({eq_12121, eq_12090 & ~eq_12084 & ~or_12089, {2{eq_12090}} & concat_12104, eq_12092}, ____state_0[1], compacted_4_tup0, nand_12141, ____state_0[1], priority_sel_12125[1], ____state_0[1]), priority_sel_1b_5way({eq_12121, eq_12090 | and_12108, {3{eq_12092}} & {eq_12084, eq_12079, nor_12080}}, and_12144, postponed_slot_tup0, compacted_4_tup0, ____state_0[0], priority_sel_12125[0], ____state_0[0])};
  assign directive = priority_sel_12154 & {2{dispatchable}};
  assign next_phase_squeezed = dispatchable ? concat_12156 : ____state_0;
  assign repeat_phase = dispatchable & eq_12092 & nor_12080 & _3 & ~(~_19 | _47);
  assign invalid_repeat = repeat_phase & (directive != unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 | next_phase_squeezed != ____state_0);
  assign transition_slots_default_case_cmp = directive[1];
  assign effective = dispatchable & ~invalid_repeat;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | transition_slots_default_case_cmp);
  assign candidate_occupied_1_case_cmp = effective & transition_slots_predicate_piece_0;
  assign add_12191 = admitted_occupied + 8'hff;
  assign candidate_slots_0_case_cmp = ~effective;
  assign candidate_phase_squeezed = effective ? concat_12156 : ____state_0;
  assign failed = invalid_input | invalid_repeat | effective & directive == unexpand_for_next_value_2029_0__2_case_0_case_0_case_2;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_12191 : admitted_occupied;
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign phase_boundary = phase_changed | effective & repeat_phase;
  assign reserve__1 = ~failed & ~received & ~(____state_15 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_15 | ____state_13 > 8'h04);
  assign and_12178 = ~(____state_16 | ____state_14 | candidate_slots_0_case_cmp) & eq_12090;
  assign nor_12179 = ~(____state_16 | ____state_14);
  assign final_slots_0_case_cmp = ~phase_boundary;
  assign and_12183 = ~(____state_16 | ____state_14 | candidate_slots_0_case_cmp) & eq_12092;
  assign and_12184 = ~(____state_16 | ____state_14 | candidate_slots_0_case_cmp) & eq_12121;
  assign and_12186 = and_12178 & eq_12084;
  assign and_12187 = nor_12179 & final_slots_0_case_cmp;
  assign and_12188 = nor_12179 & phase_boundary;
  assign eq_12189 = priority_sel_12154 == unexpand_for_next_value_2029_0__2_case_0_case_0_case_1;
  assign __phi_halo_cell__admit_buf = ~____state_16 & ~____state_14 & reserve__1 | ~____state_16 & ____state_14 & reserve;
  assign __phi_halo_cell__admit_not_has_been_sent = ~__phi_halo_cell__admit_has_been_sent_reg;
  assign phi_halo_cell__admit_valid_inv = ~__phi_halo_cell__admit_valid_reg;
  assign __phi_halo_cell__east_vld_buf = ~(____state_16 | ~____state_14);
  assign __phi_halo_cell__north_not_has_been_sent = ~__phi_halo_cell__north_has_been_sent_reg;
  assign phi_halo_cell__north_valid_inv = ~__phi_halo_cell__north_valid_reg;
  assign __phi_halo_cell__east_not_has_been_sent = ~__phi_halo_cell__east_has_been_sent_reg;
  assign phi_halo_cell__east_valid_inv = ~__phi_halo_cell__east_valid_reg;
  assign __phi_halo_cell__west_not_has_been_sent = ~__phi_halo_cell__west_has_been_sent_reg;
  assign phi_halo_cell__west_valid_inv = ~__phi_halo_cell__west_valid_reg;
  assign __phi_halo_cell__south_not_has_been_sent = ~__phi_halo_cell__south_has_been_sent_reg;
  assign phi_halo_cell__south_valid_inv = ~__phi_halo_cell__south_valid_reg;
  assign and_12197 = and_12183 & nor_12080;
  assign and_12198 = and_12184 & eq_12079;
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_12203 = and_12186 & eq_12073 & _0__11;
  assign and_12205 = and_12187 & effective;
  assign and_12206 = and_12188 & effective;
  assign or_12207 = directive[0] | transition_slots_default_case_cmp;
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
  assign and_12216 = and_12197 & _3 & _19;
  assign and_12217 = and_12186 & eq_12073 & _0__11 & _6__1;
  assign and_12218 = and_12197 & and_12144;
  assign and_12219 = and_12198 & and_12082;
  assign and_12220 = nor_12179 & candidate_occupied_0_case_cmp;
  assign and_12221 = nor_12179 & candidate_occupied_1_case_cmp;
  assign and_12223 = and_12183 & eq_12079;
  assign and_12224 = and_12183 & eq_12084;
  assign and_12225 = and_12178 & nor_12080;
  assign and_12226 = and_12178 & eq_12079;
  assign and_12227 = and_12184 & nor_12080;
  assign and_12228 = and_12197 & ~(_3 & _19 & _47);
  assign and_12229 = and_12186 & nand_12141;
  assign and_12230 = and_12198 & ~nand_12091;
  assign and_12231 = and_12198 & nand_12091;
  assign and_12232 = and_12197 & _3 & ~_19;
  assign and_12233 = and_12203 & ~_6__1;
  assign and_12234 = and_12187 & candidate_slots_0_case_cmp;
  assign and_12235 = and_12205 & transition_slots_predicate_piece_0;
  assign and_12236 = and_12205 & eq_12189;
  assign and_12237 = and_12205 & transition_slots_default_case_cmp;
  assign and_12238 = and_12188 & candidate_slots_0_case_cmp;
  assign and_12239 = and_12206 & transition_slots_predicate_piece_0;
  assign and_12240 = and_12206 & eq_12189 & or_12207;
  assign and_12241 = and_12206 & ~eq_12189 & or_12207;
  assign Xls_clause_1_Value_1 = selected_slot_tuple_idx_1_tuple_idx_1[95:64];
  assign _12 = ____state_5_1 + Xls_clause_1_Value1_1;
  assign phi_halo_cell__admit_not_pred = ~__phi_halo_cell__admit_buf;
  assign phi_halo_cell__admit_load_en = __phi_halo_cell__admit_valid_and_not_has_been_sent & phi_halo_cell__admit_valid_load_en;
  assign phi_halo_cell__east_not_pred = ~__phi_halo_cell__east_vld_buf;
  assign phi_halo_cell__north_load_en = __phi_halo_cell__north_valid_and_not_has_been_sent & phi_halo_cell__north_valid_load_en;
  assign phi_halo_cell__east_load_en = __phi_halo_cell__east_valid_and_not_has_been_sent & phi_halo_cell__east_valid_load_en;
  assign phi_halo_cell__west_load_en = __phi_halo_cell__west_valid_and_not_has_been_sent & phi_halo_cell__west_valid_load_en;
  assign phi_halo_cell__south_load_en = __phi_halo_cell__south_valid_and_not_has_been_sent & phi_halo_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_12216, and_12217};
  assign ____state_7__next_value_predicates = {and_12218, and_12219};
  assign ____state_13__next_value_predicates = {and_12220, and_12221};
  assign ____state_15__next_value_predicates = {nor_12179, __phi_halo_cell__east_vld_buf};
  assign ____state_0__next_value_predicates = {and_12223, and_12224, and_12225, and_12226, and_12227, and_12218, and_12228, and_12217, and_12229, and_12230, and_12231};
  assign ____state_6__next_value_predicates = {and_12232, and_12216};
  assign ____state_10__next_value_predicates = {and_12233, and_12217};
  assign ____state_12_tuple_element_0__next_value_predicates = {and_12188, and_12234, and_12235, and_12236, and_12237};
  assign ____state_12_tuple_element_1_tuple_element_1__next_value_predicates = {and_12234, and_12235, and_12236, and_12237, and_12238, and_12239, and_12240, and_12241};
  assign _8 = ____state_5_0 + Xls_clause_1_Value_1;
  assign _35 = ____state_4_0 + _12;
  assign one_hot_12286 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_12287 = {____state_7__next_value_predicates[1:0] == 2'h0, ____state_7__next_value_predicates[1] && !____state_7__next_value_predicates[0], ____state_7__next_value_predicates[0]};
  assign one_hot_12288 = {____state_13__next_value_predicates[1:0] == 2'h0, ____state_13__next_value_predicates[1] && !____state_13__next_value_predicates[0], ____state_13__next_value_predicates[0]};
  assign one_hot_12289 = {____state_15__next_value_predicates[1:0] == 2'h0, ____state_15__next_value_predicates[1] && !____state_15__next_value_predicates[0], ____state_15__next_value_predicates[0]};
  assign one_hot_12290 = {____state_0__next_value_predicates[10:0] == 11'h000, ____state_0__next_value_predicates[10] && ____state_0__next_value_predicates[9:0] == 10'h000, ____state_0__next_value_predicates[9] && ____state_0__next_value_predicates[8:0] == 9'h000, ____state_0__next_value_predicates[8] && ____state_0__next_value_predicates[7:0] == 8'h00, ____state_0__next_value_predicates[7] && ____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_12291 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_12292 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_12293 = {____state_12_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_12_tuple_element_0__next_value_predicates[4] && ____state_12_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_12_tuple_element_0__next_value_predicates[3] && ____state_12_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_12_tuple_element_0__next_value_predicates[2] && ____state_12_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_12_tuple_element_0__next_value_predicates[1] && !____state_12_tuple_element_0__next_value_predicates[0], ____state_12_tuple_element_0__next_value_predicates[0]};
  assign one_hot_12294 = {____state_12_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_12_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_12_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign add_12249 = ____state_4_1[31:1] + ____state_4_1[30:0];
  assign umul_12250 = umul64b_32b_x_32b(_35, 32'hcccc_cccd);
  assign array_index_12265 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_12267 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_12269 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_12273 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_12275 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_12277 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phi_halo_cell__admit_not_pred | phi_halo_cell__admit_load_en | __phi_halo_cell__admit_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__north_load_en | __phi_halo_cell__north_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__east_load_en | __phi_halo_cell__east_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__west_load_en | __phi_halo_cell__west_has_been_sent_reg) & (phi_halo_cell__east_not_pred | phi_halo_cell__south_load_en | __phi_halo_cell__south_has_been_sent_reg);
  assign add_12283 = ____state_4_1[30:0] + _8[31:1];
  assign ne_12308 = bit_slice_12052 != 3'h0;
  assign or_reduce_12310 = |selected[7:1];
  assign ugt_12312 = bit_slice_12052 > 3'h2;
  assign phi_halo_cell__req_valid_inv = ~__phi_halo_cell__req_valid_reg;
  assign and_12531 = and_12216 & p0_all_active_outputs_ready;
  assign and_12532 = and_12217 & p0_all_active_outputs_ready;
  assign and_12538 = and_12218 & p0_all_active_outputs_ready;
  assign admission_pending = ~(~____state_15 | received);
  assign add_12326 = ____state_11[15:0] + {unexpand_for_next_value_2029_0__2_case_0_case_1_case_0, ____state_4_0[31:18]};
  assign and_12609 = and_12234 & p0_all_active_outputs_ready;
  assign and_12610 = and_12235 & p0_all_active_outputs_ready;
  assign and_12611 = and_12236 & p0_all_active_outputs_ready;
  assign and_12612 = and_12237 & p0_all_active_outputs_ready;
  assign concat_12381 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_12308 ? postponed : or_reduce_12029 & postponed__1;
  assign compacted_1_tup0 = or_reduce_12310 ? postponed__1 : ugt_12025 & postponed__2;
  assign compacted_2_tup0 = ugt_12312 ? postponed__2 : or_reduce_12021 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_12019 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_12308 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_12265 & {96{or_reduce_12029}};
  assign compacted_1_tup1_tup1 = or_reduce_12310 ? array_index_12265 : array_index_12267 & {96{ugt_12025}};
  assign compacted_2_tup1_tup1 = ugt_12312 ? array_index_12267 : array_index_12269 & {96{or_reduce_12021}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_12269 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_12019}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_12308 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_12273 & {8{or_reduce_12029}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_12310 ? array_index_12273 : array_index_12275 & {8{ugt_12025}};
  assign compacted_2_tup1_tup0_tup3 = ugt_12312 ? array_index_12275 : array_index_12277 & {8{or_reduce_12021}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_12277 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_12019}};
  assign concat_12297 = {____state_4_0, ____state_4_1, add_12077, ____state_3[0]};
  assign concat_12299 = {64'h0000_0000_0000_0000, ____state_2};
  assign phi_halo_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_11989 | phi_halo_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_12216 == one_hot_12286[1] & and_12217 == one_hot_12286[0];
  assign ____state_7__at_most_one_next_value = and_12218 == one_hot_12287[1] & and_12219 == one_hot_12287[0];
  assign ____state_13__at_most_one_next_value = and_12220 == one_hot_12288[1] & and_12221 == one_hot_12288[0];
  assign ____state_15__at_most_one_next_value = nor_12179 == one_hot_12289[1] & __phi_halo_cell__east_vld_buf == one_hot_12289[0];
  assign ____state_0__at_most_one_next_value = and_12223 == one_hot_12290[10] & and_12224 == one_hot_12290[9] & and_12225 == one_hot_12290[8] & and_12226 == one_hot_12290[7] & and_12227 == one_hot_12290[6] & and_12218 == one_hot_12290[5] & and_12228 == one_hot_12290[4] & and_12217 == one_hot_12290[3] & and_12229 == one_hot_12290[2] & and_12230 == one_hot_12290[1] & and_12231 == one_hot_12290[0];
  assign ____state_6__at_most_one_next_value = and_12232 == one_hot_12291[1] & and_12216 == one_hot_12291[0];
  assign ____state_10__at_most_one_next_value = and_12233 == one_hot_12292[1] & and_12217 == one_hot_12292[0];
  assign ____state_12_tuple_element_0__at_most_one_next_value = and_12188 == one_hot_12293[4] & and_12234 == one_hot_12293[3] & and_12235 == one_hot_12293[2] & and_12236 == one_hot_12293[1] & and_12237 == one_hot_12293[0];
  assign ____state_12_tuple_element_1_tuple_element_1__at_most_one_next_value = and_12234 == one_hot_12294[7] & and_12235 == one_hot_12294[6] & and_12236 == one_hot_12294[5] & and_12237 == one_hot_12294[4] & and_12238 == one_hot_12294[3] & and_12239 == one_hot_12294[2] & and_12240 == one_hot_12294[1] & and_12241 == one_hot_12294[0];
  assign concat_12534 = {and_12531, and_12532};
  assign _42 = ____state_3 + _12_source;
  assign concat_12541 = {and_12538, and_12219 & p0_all_active_outputs_ready};
  assign concat_12551 = {and_12220 & p0_all_active_outputs_ready, and_12221 & p0_all_active_outputs_ready};
  assign concat_12561 = {nor_12179 & p0_all_active_outputs_ready, __phi_halo_cell__east_vld_buf & p0_all_active_outputs_ready};
  assign _27 = {add_12326, ____state_4_0[17:2]};
  assign _30 = {3'h0, add_12283[30:2]};
  assign add_12392 = {compacted_4_tup0, add_12249[30:1]} + {3'h0, umul_12250[63:36]};
  assign sign_ext_12393 = {32{~_19}};
  assign concat_12590 = {and_12223 & p0_all_active_outputs_ready, and_12224 & p0_all_active_outputs_ready, and_12225 & p0_all_active_outputs_ready, and_12226 & p0_all_active_outputs_ready, and_12227 & p0_all_active_outputs_ready, and_12538, and_12228 & p0_all_active_outputs_ready, and_12532, and_12229 & p0_all_active_outputs_ready, and_12230 & p0_all_active_outputs_ready, and_12231 & p0_all_active_outputs_ready};
  assign concat_12597 = {and_12232 & p0_all_active_outputs_ready, and_12531};
  assign unexpand_for_next_value_2029_6__2_case_0_case_0_case_0_case_1_case_0 = ____state_6 + unexpand_for_next_value_2029_0__2_case_0_case_0_case_1;
  assign concat_12604 = {and_12233 & p0_all_active_outputs_ready, and_12532};
  assign unexpand_for_next_value_2029_10__2_case_0_case_1_case_2_case_1_case_0 = ____state_10 + unexpand_for_next_value_2029_0__2_case_0_case_0_case_1;
  assign concat_12614 = {and_12188 & p0_all_active_outputs_ready, and_12609, and_12610, and_12611, and_12612};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = compacted_4_tup0;
  assign concat_12627 = {and_12609, and_12610, and_12611, and_12612, and_12238 & p0_all_active_outputs_ready, and_12239 & p0_all_active_outputs_ready, and_12240 & p0_all_active_outputs_ready, and_12241 & p0_all_active_outputs_ready};
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
  assign tuple_12367 = {{7'h01, or_12089}, compacted_4_tup1_tup0_tup0, compacted_4_tup1_tup0_tup0, {5'h00, nor_12080 ? unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 : unexpand_for_next_value_2029_0__2_case_0_case_0_case_2, or_12089}};
  assign phi_halo_cell__req_load_en = phi_halo_cell__req_vld & phi_halo_cell__req_valid_load_en;
  assign or_12975 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_12977 = ~p0_all_active_outputs_ready | ____state_7__at_most_one_next_value | reset;
  assign or_12979 = ~p0_all_active_outputs_ready | ____state_13__at_most_one_next_value | reset;
  assign or_12981 = ~p0_all_active_outputs_ready | ____state_15__at_most_one_next_value | reset;
  assign or_12983 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_12985 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_12987 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_12989 = ~p0_all_active_outputs_ready | ____state_12_tuple_element_0__at_most_one_next_value | reset;
  assign or_12991 = ~p0_all_active_outputs_ready | ____state_12_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign _8__1 = ____state_2 + _12_source;
  assign and_12650 = and_12217 & p0_all_active_outputs_ready;
  assign one_hot_sel_12535 = 32'h0000_0000 & {32{concat_12534[0]}} | _42 & {32{concat_12534[1]}};
  assign and_12653 = (and_12216 | and_12217) & p0_all_active_outputs_ready;
  assign one_hot_sel_12542 = Xls_clause_1_NewSeen_1 & {32{concat_12541[0]}} | 32'h0000_0000 & {32{concat_12541[1]}};
  assign and_12656 = (and_12218 | and_12219) & p0_all_active_outputs_ready;
  assign Xls_clause_1_NextAnyon_1 = ____state_11 ^ Xls_clause_1_Value1_1;
  assign and_12658 = and_12203 & p0_all_active_outputs_ready;
  assign one_hot_sel_12552 = add_12191 & {8{concat_12551[0]}} | admitted_occupied & {8{concat_12551[1]}};
  assign and_12661 = (and_12220 | and_12221) & p0_all_active_outputs_ready;
  assign and_12438 = ~____state_14 & effective & phase_boundary & ~failed;
  assign and_12663 = ~____state_16 & p0_all_active_outputs_ready;
  assign one_hot_sel_12562 = (____state_15 | ____state_13 < MAILBOX_CAPACITY) & concat_12561[0] | (admission_pending | reserve__1) & concat_12561[1];
  assign and_12666 = (nor_12179 | __phi_halo_cell__east_vld_buf) & p0_all_active_outputs_ready;
  assign or_12436 = ____state_16 | (____state_14 ? ____state_16 : failed);
  assign _31 = _27 + _30;
  assign and_12669 = ~(____state_16 | ____state_14 | candidate_slots_0_case_cmp) & eq_12092 & nor_12080 & eq_12097 & eq_12098 & _19 & p0_all_active_outputs_ready;
  assign _37 = {compacted_4_tup0, add_12392};
  assign and_12454 = _8 & sign_ext_12393;
  assign and_12673 = ~(____state_16 | ____state_14 | candidate_slots_0_case_cmp) & eq_12092 & nor_12080 & _3 & p0_all_active_outputs_ready;
  assign and_12455 = _12 & sign_ext_12393;
  assign one_hot_sel_12591 = unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 & {2{concat_12590[0]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_2 & {2{concat_12590[1]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_2 & {2{concat_12590[2]}} | unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12590[3]}} | unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12590[4]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 & {2{concat_12590[5]}} | unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12590[6]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 & {2{concat_12590[7]}} | unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12590[8]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_2 & {2{concat_12590[9]}} | unexpand_for_next_value_2029_0__2_case_0_case_0_case_1 & {2{concat_12590[10]}};
  assign and_12678 = (and_12223 | and_12224 | and_12225 | and_12226 | and_12227 | and_12218 | and_12228 | and_12217 | and_12229 | and_12230 | and_12231) & p0_all_active_outputs_ready;
  assign one_hot_sel_12598 = unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12597[0]}} | unexpand_for_next_value_2029_6__2_case_0_case_0_case_0_case_1_case_0 & {2{concat_12597[1]}};
  assign and_12681 = (and_12232 | and_12216) & p0_all_active_outputs_ready;
  assign one_hot_sel_12605 = unexpand_for_next_value_2029_0__2_case_0_case_1_case_0 & {2{concat_12604[0]}} | unexpand_for_next_value_2029_10__2_case_0_case_1_case_2_case_1_case_0 & {2{concat_12604[1]}};
  assign and_12684 = (and_12233 | and_12217) & p0_all_active_outputs_ready;
  assign one_hot_sel_12615[0] = admitted_slots_tuple_idx_0[0] & concat_12614[0] | postponed_slots_tuple_idx_0[0] & concat_12614[1] | compacted_slots_tuple_idx_0[0] & concat_12614[2] | admitted_slots_tuple_idx_0[0] & concat_12614[3] | unblocked_slots_tuple_idx_0[0] & concat_12614[4];
  assign one_hot_sel_12615[1] = admitted_slots_tuple_idx_0[1] & concat_12614[0] | postponed_slots_tuple_idx_0[1] & concat_12614[1] | compacted_slots_tuple_idx_0[1] & concat_12614[2] | admitted_slots_tuple_idx_0[1] & concat_12614[3] | unblocked_slots_tuple_idx_0[1] & concat_12614[4];
  assign one_hot_sel_12615[2] = admitted_slots_tuple_idx_0[2] & concat_12614[0] | postponed_slots_tuple_idx_0[2] & concat_12614[1] | compacted_slots_tuple_idx_0[2] & concat_12614[2] | admitted_slots_tuple_idx_0[2] & concat_12614[3] | unblocked_slots_tuple_idx_0[2] & concat_12614[4];
  assign one_hot_sel_12615[3] = admitted_slots_tuple_idx_0[3] & concat_12614[0] | postponed_slots_tuple_idx_0[3] & concat_12614[1] | compacted_slots_tuple_idx_0[3] & concat_12614[2] | admitted_slots_tuple_idx_0[3] & concat_12614[3] | unblocked_slots_tuple_idx_0[3] & concat_12614[4];
  assign one_hot_sel_12615[4] = admitted_slots_tuple_idx_0[4] & concat_12614[0] | postponed_slots_tuple_idx_0[4] & concat_12614[1] | compacted_slots_tuple_idx_0[4] & concat_12614[2] | admitted_slots_tuple_idx_0[4] & concat_12614[3] | unblocked_slots_tuple_idx_0[4] & concat_12614[4];
  assign and_12687 = (and_12188 | and_12234 | and_12235 | and_12236 | and_12237) & p0_all_active_outputs_ready;
  assign one_hot_sel_12628[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_12627[7]}};
  assign one_hot_sel_12628[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_12627[7]}};
  assign one_hot_sel_12628[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_12627[7]}};
  assign one_hot_sel_12628[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_12627[7]}};
  assign one_hot_sel_12628[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_12627[7]}};
  assign and_12690 = (and_12234 | and_12235 | and_12236 | and_12237 | and_12238 | and_12239 | and_12240 | and_12241) & p0_all_active_outputs_ready;
  assign one_hot_sel_12641[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_12627[7]}};
  assign one_hot_sel_12641[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_12627[7]}};
  assign one_hot_sel_12641[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_12627[7]}};
  assign one_hot_sel_12641[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_12627[7]}};
  assign one_hot_sel_12641[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_12627[7]}};
  assign __phi_halo_cell__admit_not_stage_load = ~__phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__admit_has_been_sent_reg_load_en = __phi_halo_cell__admit_valid_and_ready_txfr | __phi_halo_cell__admit_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_not_stage_load = ~__phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__north_has_been_sent_reg_load_en = __phi_halo_cell__north_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__east_has_been_sent_reg_load_en = __phi_halo_cell__east_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__west_has_been_sent_reg_load_en = __phi_halo_cell__west_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign __phi_halo_cell__south_has_been_sent_reg_load_en = __phi_halo_cell__south_valid_and_ready_txfr | __phi_halo_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {tuple_12367, priority_sel_96b_2way(concat_12106, concat_12297, {____state_4_0, _3__5_source, ____state_2}, concat_12299)};
  assign effects_east = {tuple_12367, priority_sel_96b_2way(concat_12106, concat_12297, {____state_4_0, _6__5_source, ____state_2}, concat_12299)};
  assign effects_west = {tuple_12367, priority_sel_96b_2way(concat_12106, concat_12297, {____state_4_0, _9_source, ____state_2}, concat_12299)};
  assign effects_south = {tuple_12367, priority_sel_96b_2way(concat_12106, concat_12297, {____state_4_0, _12_source, ____state_2}, concat_12299)};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_15 <= 1'h0;
      ____state_16 <= 1'h0;
      ____state_14 <= 1'h1;
      ____state_12_tuple_element_0[0] <= ____state_12_tuple_element_0_init[0];
      ____state_12_tuple_element_0[1] <= ____state_12_tuple_element_0_init[1];
      ____state_12_tuple_element_0[2] <= ____state_12_tuple_element_0_init[2];
      ____state_12_tuple_element_0[3] <= ____state_12_tuple_element_0_init[3];
      ____state_12_tuple_element_0[4] <= ____state_12_tuple_element_0_init[4];
      ____state_13 <= 8'h00;
      ____state_12_tuple_element_1_tuple_element_1[0] <= ____state_12_tuple_element_1_tuple_element_1_init[0];
      ____state_12_tuple_element_1_tuple_element_1[1] <= ____state_12_tuple_element_1_tuple_element_1_init[1];
      ____state_12_tuple_element_1_tuple_element_1[2] <= ____state_12_tuple_element_1_tuple_element_1_init[2];
      ____state_12_tuple_element_1_tuple_element_1[3] <= ____state_12_tuple_element_1_tuple_element_1_init[3];
      ____state_12_tuple_element_1_tuple_element_1[4] <= ____state_12_tuple_element_1_tuple_element_1_init[4];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[0] <= ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[0];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[1] <= ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[1];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[2] <= ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[2];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[3] <= ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[3];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[4] <= ____state_12_tuple_element_1_tuple_element_0_tuple_element_3_init[4];
      ____state_7 <= 32'h0000_0000;
      ____state_2 <= 32'h0000_0000;
      ____state_3 <= 32'h0000_0000;
      ____state_0 <= 2'h0;
      ____state_10 <= 2'h0;
      ____state_6 <= 2'h0;
      ____state_5_1 <= 32'h0000_0000;
      ____state_5_0 <= 32'h0000_0000;
      ____state_4_1 <= 32'h0000_0000;
      ____state_4_0 <= 32'h0000_0000;
      ____state_11 <= 32'h0000_0000;
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
      ____state_15 <= and_12666 ? one_hot_sel_12562 : ____state_15;
      ____state_16 <= p0_all_active_outputs_ready ? or_12436 : ____state_16;
      ____state_14 <= and_12663 ? and_12438 : ____state_14;
      ____state_12_tuple_element_0[0] <= and_12687 ? one_hot_sel_12615[0] : ____state_12_tuple_element_0[0];
      ____state_12_tuple_element_0[1] <= and_12687 ? one_hot_sel_12615[1] : ____state_12_tuple_element_0[1];
      ____state_12_tuple_element_0[2] <= and_12687 ? one_hot_sel_12615[2] : ____state_12_tuple_element_0[2];
      ____state_12_tuple_element_0[3] <= and_12687 ? one_hot_sel_12615[3] : ____state_12_tuple_element_0[3];
      ____state_12_tuple_element_0[4] <= and_12687 ? one_hot_sel_12615[4] : ____state_12_tuple_element_0[4];
      ____state_13 <= and_12661 ? one_hot_sel_12552 : ____state_13;
      ____state_12_tuple_element_1_tuple_element_1[0] <= and_12690 ? one_hot_sel_12628[0] : ____state_12_tuple_element_1_tuple_element_1[0];
      ____state_12_tuple_element_1_tuple_element_1[1] <= and_12690 ? one_hot_sel_12628[1] : ____state_12_tuple_element_1_tuple_element_1[1];
      ____state_12_tuple_element_1_tuple_element_1[2] <= and_12690 ? one_hot_sel_12628[2] : ____state_12_tuple_element_1_tuple_element_1[2];
      ____state_12_tuple_element_1_tuple_element_1[3] <= and_12690 ? one_hot_sel_12628[3] : ____state_12_tuple_element_1_tuple_element_1[3];
      ____state_12_tuple_element_1_tuple_element_1[4] <= and_12690 ? one_hot_sel_12628[4] : ____state_12_tuple_element_1_tuple_element_1[4];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_12690 ? one_hot_sel_12641[0] : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_12690 ? one_hot_sel_12641[1] : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_12690 ? one_hot_sel_12641[2] : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_12690 ? one_hot_sel_12641[3] : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_12690 ? one_hot_sel_12641[4] : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_7 <= and_12656 ? one_hot_sel_12542 : ____state_7;
      ____state_2 <= and_12650 ? _8__1 : ____state_2;
      ____state_3 <= and_12653 ? one_hot_sel_12535 : ____state_3;
      ____state_0 <= and_12678 ? one_hot_sel_12591 : ____state_0;
      ____state_10 <= and_12684 ? one_hot_sel_12605 : ____state_10;
      ____state_6 <= and_12681 ? one_hot_sel_12598 : ____state_6;
      ____state_5_1 <= and_12673 ? and_12455 : ____state_5_1;
      ____state_5_0 <= and_12673 ? and_12454 : ____state_5_0;
      ____state_4_1 <= and_12669 ? _37 : ____state_4_1;
      ____state_4_0 <= and_12669 ? _31 : ____state_4_0;
      ____state_11 <= and_12658 ? Xls_clause_1_NextAnyon_1 : ____state_11;
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
    assign admitted_slots_tuple_idx_0[__i0] = concat_12017 == __i0 ? and_12016 : ____state_12_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_12017 == __i0 ? sel_12049 : ____state_12_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_12017 == __i0 ? sel_12061 : ____state_12_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_12381 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_12381 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_12381 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_13054;
  wire eq_13059;
  wire ne_13043;
  wire and_13060;
  wire or_13057;
  wire [2:0] add_13051;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13046;
  wire popped;
  wire [1:0] sub_13072;
  wire [1:0] add_13074;
  wire [2:0] umod_13052;
  wire [2:0] umod_13047;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13076;
  wire array_update_13083[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13054 = pop_ready & push_valid;
  assign eq_13059 = head == tail;
  assign ne_13043 = head != tail;
  assign and_13060 = eq_13059 & and_13054;
  assign or_13057 = ne_13043 | push_valid;
  assign add_13051 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13046 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13057;
  assign sub_13072 = slots - 2'h1;
  assign add_13074 = slots + 2'h1;
  assign umod_13052 = add_13051 % long_buf_size_lit;
  assign umod_13047 = add_13046 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13052[1:0];
  assign did_push_occur = (can_do_push | and_13054) & push_valid & ~and_13060 & ~is_full_bool;
  assign next_tail_if_pop = umod_13047[1:0];
  assign did_pop_occur = (ne_13043 | and_13054) & pop_ready & ~and_13060;
  assign sel_13076 = pushed ? (popped ? slots : add_13074) : (popped ? sub_13072 : slots);
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
      slots <= sel_13076;
      buf__1[0] <= did_push_occur ? array_update_13083[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13083[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13057;
  assign pop_data = eq_13059 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13083_0
    assign array_update_13083[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_13111;
  wire eq_13116;
  wire ne_13100;
  wire and_13117;
  wire or_13114;
  wire [2:0] add_13108;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13103;
  wire popped;
  wire [1:0] sub_13129;
  wire [1:0] add_13131;
  wire [2:0] umod_13109;
  wire [2:0] umod_13104;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13133;
  wire [127:0] array_update_13140[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13111 = pop_ready & push_valid;
  assign eq_13116 = head == tail;
  assign ne_13100 = head != tail;
  assign and_13117 = eq_13116 & and_13111;
  assign or_13114 = ne_13100 | push_valid;
  assign add_13108 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13103 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13114;
  assign sub_13129 = slots - 2'h1;
  assign add_13131 = slots + 2'h1;
  assign umod_13109 = add_13108 % long_buf_size_lit;
  assign umod_13104 = add_13103 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13109[1:0];
  assign did_push_occur = (can_do_push | and_13111) & push_valid & ~and_13117 & ~is_full_bool;
  assign next_tail_if_pop = umod_13104[1:0];
  assign did_pop_occur = (ne_13100 | and_13111) & pop_ready & ~and_13117;
  assign sel_13133 = pushed ? (popped ? slots : add_13131) : (popped ? sub_13129 : slots);
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
      slots <= sel_13133;
      buf__1[0] <= did_push_occur ? array_update_13140[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13140[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13114;
  assign pop_data = eq_13116 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13140_0
    assign array_update_13140[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_13168;
  wire eq_13173;
  wire ne_13157;
  wire and_13174;
  wire or_13171;
  wire [2:0] add_13165;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13160;
  wire popped;
  wire [1:0] sub_13186;
  wire [1:0] add_13188;
  wire [2:0] umod_13166;
  wire [2:0] umod_13161;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13190;
  wire [127:0] array_update_13197[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13168 = pop_ready & push_valid;
  assign eq_13173 = head == tail;
  assign ne_13157 = head != tail;
  assign and_13174 = eq_13173 & and_13168;
  assign or_13171 = ne_13157 | push_valid;
  assign add_13165 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13160 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13171;
  assign sub_13186 = slots - 2'h1;
  assign add_13188 = slots + 2'h1;
  assign umod_13166 = add_13165 % long_buf_size_lit;
  assign umod_13161 = add_13160 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13166[1:0];
  assign did_push_occur = (can_do_push | and_13168) & push_valid & ~and_13174 & ~is_full_bool;
  assign next_tail_if_pop = umod_13161[1:0];
  assign did_pop_occur = (ne_13157 | and_13168) & pop_ready & ~and_13174;
  assign sel_13190 = pushed ? (popped ? slots : add_13188) : (popped ? sub_13186 : slots);
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
      slots <= sel_13190;
      buf__1[0] <= did_push_occur ? array_update_13197[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13197[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13171;
  assign pop_data = eq_13173 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13197_0
    assign array_update_13197[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_13225;
  wire eq_13230;
  wire ne_13214;
  wire and_13231;
  wire or_13228;
  wire [2:0] add_13222;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13217;
  wire popped;
  wire [1:0] sub_13243;
  wire [1:0] add_13245;
  wire [2:0] umod_13223;
  wire [2:0] umod_13218;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13247;
  wire [127:0] array_update_13254[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13225 = pop_ready & push_valid;
  assign eq_13230 = head == tail;
  assign ne_13214 = head != tail;
  assign and_13231 = eq_13230 & and_13225;
  assign or_13228 = ne_13214 | push_valid;
  assign add_13222 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13217 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13228;
  assign sub_13243 = slots - 2'h1;
  assign add_13245 = slots + 2'h1;
  assign umod_13223 = add_13222 % long_buf_size_lit;
  assign umod_13218 = add_13217 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13223[1:0];
  assign did_push_occur = (can_do_push | and_13225) & push_valid & ~and_13231 & ~is_full_bool;
  assign next_tail_if_pop = umod_13218[1:0];
  assign did_pop_occur = (ne_13214 | and_13225) & pop_ready & ~and_13231;
  assign sel_13247 = pushed ? (popped ? slots : add_13245) : (popped ? sub_13243 : slots);
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
      slots <= sel_13247;
      buf__1[0] <= did_push_occur ? array_update_13254[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13254[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13228;
  assign pop_data = eq_13230 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13254_0
    assign array_update_13254[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_13282;
  wire eq_13287;
  wire ne_13271;
  wire and_13288;
  wire or_13285;
  wire [2:0] add_13279;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13274;
  wire popped;
  wire [1:0] sub_13300;
  wire [1:0] add_13302;
  wire [2:0] umod_13280;
  wire [2:0] umod_13275;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13304;
  wire [127:0] array_update_13311[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13282 = pop_ready & push_valid;
  assign eq_13287 = head == tail;
  assign ne_13271 = head != tail;
  assign and_13288 = eq_13287 & and_13282;
  assign or_13285 = ne_13271 | push_valid;
  assign add_13279 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13274 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13285;
  assign sub_13300 = slots - 2'h1;
  assign add_13302 = slots + 2'h1;
  assign umod_13280 = add_13279 % long_buf_size_lit;
  assign umod_13275 = add_13274 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13280[1:0];
  assign did_push_occur = (can_do_push | and_13282) & push_valid & ~and_13288 & ~is_full_bool;
  assign next_tail_if_pop = umod_13275[1:0];
  assign did_pop_occur = (ne_13271 | and_13282) & pop_ready & ~and_13288;
  assign sel_13304 = pushed ? (popped ? slots : add_13302) : (popped ? sub_13300 : slots);
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
      slots <= sel_13304;
      buf__1[0] <= did_push_occur ? array_update_13311[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13311[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13285;
  assign pop_data = eq_13287 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13311_0
    assign array_update_13311[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_13339;
  wire eq_13344;
  wire ne_13328;
  wire and_13345;
  wire or_13342;
  wire [2:0] add_13336;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_13331;
  wire popped;
  wire [1:0] sub_13357;
  wire [1:0] add_13359;
  wire [2:0] umod_13337;
  wire [2:0] umod_13332;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_13361;
  wire [127:0] array_update_13368[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_13339 = pop_ready & push_valid;
  assign eq_13344 = head == tail;
  assign ne_13328 = head != tail;
  assign and_13345 = eq_13344 & and_13339;
  assign or_13342 = ne_13328 | push_valid;
  assign add_13336 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_13331 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_13342;
  assign sub_13357 = slots - 2'h1;
  assign add_13359 = slots + 2'h1;
  assign umod_13337 = add_13336 % long_buf_size_lit;
  assign umod_13332 = add_13331 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_13337[1:0];
  assign did_push_occur = (can_do_push | and_13339) & push_valid & ~and_13345 & ~is_full_bool;
  assign next_tail_if_pop = umod_13332[1:0];
  assign did_pop_occur = (ne_13328 | and_13339) & pop_ready & ~and_13345;
  assign sel_13361 = pushed ? (popped ? slots : add_13359) : (popped ? sub_13357 : slots);
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
      slots <= sel_13361;
      buf__1[0] <= did_push_occur ? array_update_13368[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_13368[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_13342;
  assign pop_data = eq_13344 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_13368_0
    assign array_update_13368[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire instantiation_output_12842;
  wire instantiation_output_12867;
  wire [127:0] instantiation_output_12891;
  wire instantiation_output_12892;
  wire instantiation_output_12880;
  wire [32:0] instantiation_output_12884;
  wire instantiation_output_12885;
  wire instantiation_output_12855;
  wire [32:0] instantiation_output_12859;
  wire instantiation_output_12860;
  wire instantiation_output_12931;
  wire [32:0] instantiation_output_12935;
  wire instantiation_output_12936;
  wire instantiation_output_12912;
  wire [32:0] instantiation_output_12916;
  wire instantiation_output_12917;
  wire instantiation_output_12834;
  wire instantiation_output_12835;
  wire [127:0] instantiation_output_12847;
  wire instantiation_output_12848;
  wire [127:0] instantiation_output_12872;
  wire instantiation_output_12873;
  wire instantiation_output_12899;
  wire [127:0] instantiation_output_12904;
  wire instantiation_output_12905;
  wire [127:0] instantiation_output_12923;
  wire instantiation_output_12924;
  wire instantiation_output_13376;
  wire instantiation_output_13377;
  wire instantiation_output_13378;
  wire instantiation_output_13383;
  wire [127:0] instantiation_output_13384;
  wire instantiation_output_13385;
  wire instantiation_output_13390;
  wire [127:0] instantiation_output_13391;
  wire instantiation_output_13392;
  wire instantiation_output_13397;
  wire [127:0] instantiation_output_13398;
  wire instantiation_output_13399;
  wire instantiation_output_13404;
  wire [127:0] instantiation_output_13405;
  wire instantiation_output_13406;
  wire instantiation_output_13411;
  wire [127:0] instantiation_output_13412;
  wire instantiation_output_13413;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phi_halo_cell__admit(instantiation_output_13377),
    .phi_halo_cell__admit_vld(instantiation_output_13378),
    .phi_halo_cell__ext_recv(phi_halo_cell__ext_recv),
    .phi_halo_cell__ext_recv_vld(phi_halo_cell__ext_recv_vld),
    .phi_halo_cell__req_rdy(instantiation_output_13397),
    .phi_halo_cell__admit_rdy(instantiation_output_12842),
    .phi_halo_cell__ext_recv_rdy(instantiation_output_12867),
    .phi_halo_cell__req(instantiation_output_12891),
    .phi_halo_cell__req_vld(instantiation_output_12892),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phi_halo_cell__north(instantiation_output_13391),
    .phi_halo_cell__north_vld(instantiation_output_13392),
    .phi_halo_cell__north_send_rdy(phi_halo_cell__north_send_rdy),
    .phi_halo_cell__north_rdy(instantiation_output_12880),
    .phi_halo_cell__north_send(instantiation_output_12884),
    .phi_halo_cell__north_send_vld(instantiation_output_12885),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phi_halo_cell__east(instantiation_output_13384),
    .phi_halo_cell__east_vld(instantiation_output_13385),
    .phi_halo_cell__east_send_rdy(phi_halo_cell__east_send_rdy),
    .phi_halo_cell__east_rdy(instantiation_output_12855),
    .phi_halo_cell__east_send(instantiation_output_12859),
    .phi_halo_cell__east_send_vld(instantiation_output_12860),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phi_halo_cell__west(instantiation_output_13412),
    .phi_halo_cell__west_vld(instantiation_output_13413),
    .phi_halo_cell__west_send_rdy(phi_halo_cell__west_send_rdy),
    .phi_halo_cell__west_rdy(instantiation_output_12931),
    .phi_halo_cell__west_send(instantiation_output_12935),
    .phi_halo_cell__west_send_vld(instantiation_output_12936),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phi_halo_cell__south(instantiation_output_13405),
    .phi_halo_cell__south_vld(instantiation_output_13406),
    .phi_halo_cell__south_send_rdy(phi_halo_cell__south_send_rdy),
    .phi_halo_cell__south_rdy(instantiation_output_12912),
    .phi_halo_cell__south_send(instantiation_output_12916),
    .phi_halo_cell__south_send_vld(instantiation_output_12917),
    .clk(clk)
  );
  __phi_halo_cell__Top_0_next__1 __phi_halo_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phi_halo_cell__Top__Service_0_next __phi_halo_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phi_halo_cell__admit_rdy(instantiation_output_13376),
    .phi_halo_cell__east_rdy(instantiation_output_13383),
    .phi_halo_cell__north_rdy(instantiation_output_13390),
    .phi_halo_cell__req(instantiation_output_13398),
    .phi_halo_cell__req_vld(instantiation_output_13399),
    .phi_halo_cell__south_rdy(instantiation_output_13404),
    .phi_halo_cell__west_rdy(instantiation_output_13411),
    .phi_halo_cell__admit(instantiation_output_12834),
    .phi_halo_cell__admit_vld(instantiation_output_12835),
    .phi_halo_cell__east(instantiation_output_12847),
    .phi_halo_cell__east_vld(instantiation_output_12848),
    .phi_halo_cell__north(instantiation_output_12872),
    .phi_halo_cell__north_vld(instantiation_output_12873),
    .phi_halo_cell__req_rdy(instantiation_output_12899),
    .phi_halo_cell__south(instantiation_output_12904),
    .phi_halo_cell__south_vld(instantiation_output_12905),
    .phi_halo_cell__west(instantiation_output_12923),
    .phi_halo_cell__west_vld(instantiation_output_12924),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_12834),
    .push_valid(instantiation_output_12835),
    .pop_ready(instantiation_output_12842),
    .push_ready(instantiation_output_13376),
    .pop_data(instantiation_output_13377),
    .pop_valid(instantiation_output_13378),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phi_halo_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_12847),
    .push_valid(instantiation_output_12848),
    .pop_ready(instantiation_output_12855),
    .push_ready(instantiation_output_13383),
    .pop_data(instantiation_output_13384),
    .pop_valid(instantiation_output_13385),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phi_halo_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_12872),
    .push_valid(instantiation_output_12873),
    .pop_ready(instantiation_output_12880),
    .push_ready(instantiation_output_13390),
    .pop_data(instantiation_output_13391),
    .pop_valid(instantiation_output_13392),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phi_halo_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_12891),
    .push_valid(instantiation_output_12892),
    .pop_ready(instantiation_output_12899),
    .push_ready(instantiation_output_13397),
    .pop_data(instantiation_output_13398),
    .pop_valid(instantiation_output_13399),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phi_halo_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_12904),
    .push_valid(instantiation_output_12905),
    .pop_ready(instantiation_output_12912),
    .push_ready(instantiation_output_13404),
    .pop_data(instantiation_output_13405),
    .pop_valid(instantiation_output_13406),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phi_halo_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_12923),
    .push_valid(instantiation_output_12924),
    .pop_ready(instantiation_output_12931),
    .push_ready(instantiation_output_13411),
    .pop_data(instantiation_output_13412),
    .pop_valid(instantiation_output_13413),
    .clk(clk)
  );
  assign phi_halo_cell__east_send = instantiation_output_12859;
  assign phi_halo_cell__east_send_vld = instantiation_output_12860;
  assign phi_halo_cell__ext_recv_rdy = instantiation_output_12867;
  assign phi_halo_cell__north_send = instantiation_output_12884;
  assign phi_halo_cell__north_send_vld = instantiation_output_12885;
  assign phi_halo_cell__south_send = instantiation_output_12916;
  assign phi_halo_cell__south_send_vld = instantiation_output_12917;
  assign phi_halo_cell__west_send = instantiation_output_12935;
  assign phi_halo_cell__west_send_vld = instantiation_output_12936;
endmodule
