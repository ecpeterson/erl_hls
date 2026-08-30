module __axis__Top__ReservedRx_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_data_cell__admit,
  input wire phenom_data_cell__admit_vld,
  input wire [32:0] phenom_data_cell__ext_recv,
  input wire phenom_data_cell__ext_recv_vld,
  input wire phenom_data_cell__req_rdy,
  output wire phenom_data_cell__admit_rdy,
  output wire phenom_data_cell__ext_recv_rdy,
  output wire [127:0] phenom_data_cell__req,
  output wire phenom_data_cell__req_vld
);
  wire [32:0] __phenom_data_cell__ext_recv_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] __phenom_data_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] literal_8001 = {1'h0, 32'h0000_0000};
  reg ____state_0;
  reg [7:0] ____state_2;
  reg [127:0] ____state_1;
  reg [32:0] __phenom_data_cell__ext_recv_reg;
  reg __phenom_data_cell__ext_recv_valid_reg;
  reg __phenom_data_cell__admit_reg;
  reg __phenom_data_cell__admit_valid_reg;
  reg [127:0] __phenom_data_cell__req_reg;
  reg __phenom_data_cell__req_valid_reg;
  wire [32:0] phenom_data_cell__ext_recv_select;
  wire beat_tlast;
  wire p0_all_active_inputs_valid;
  wire and_8011;
  wire phenom_data_cell__req_valid_inv;
  wire __phenom_data_cell__req_vld_buf;
  wire phenom_data_cell__req_valid_load_en;
  wire nor_8010;
  wire phenom_data_cell__req_not_pred;
  wire phenom_data_cell__req_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [2:0] one_hot_8023;
  wire [31:0] beat_word;
  wire p0_stage_done;
  wire [31:0] sel_9574;
  wire phenom_data_cell__admit_valid_inv;
  wire phenom_data_cell__ext_recv_valid_inv;
  wire [31:0] sel_9573;
  wire [31:0] sel_9572;
  wire [31:0] sel_9571;
  wire phenom_data_cell__admit_valid_load_en;
  wire phenom_data_cell__ext_recv_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire [1:0] concat_8068;
  wire [127:0] payload;
  wire [7:0] words_seen;
  wire phenom_data_cell__admit_load_en;
  wire phenom_data_cell__ext_recv_load_en;
  wire or_9582;
  wire nand_8039;
  wire [127:0] one_hot_sel_8069;
  wire and_8083;
  wire [7:0] one_hot_sel_8076;
  wire [127:0] __phenom_data_cell__req_buf;
  assign phenom_data_cell__ext_recv_select = ____state_0 ? __phenom_data_cell__ext_recv_reg : literal_8001;
  assign beat_tlast = phenom_data_cell__ext_recv_select[32:32];
  assign p0_all_active_inputs_valid = (~____state_0 | __phenom_data_cell__ext_recv_valid_reg) & (____state_0 | __phenom_data_cell__admit_valid_reg);
  assign and_8011 = ____state_0 & beat_tlast;
  assign phenom_data_cell__req_valid_inv = ~__phenom_data_cell__req_valid_reg;
  assign __phenom_data_cell__req_vld_buf = p0_all_active_inputs_valid & and_8011;
  assign phenom_data_cell__req_valid_load_en = phenom_data_cell__req_rdy | phenom_data_cell__req_valid_inv;
  assign nor_8010 = ~(~____state_0 | beat_tlast);
  assign phenom_data_cell__req_not_pred = ~and_8011;
  assign phenom_data_cell__req_load_en = __phenom_data_cell__req_vld_buf & phenom_data_cell__req_valid_load_en;
  assign ____state_1__next_value_predicates = {nor_8010, and_8011};
  assign one_hot_8023 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign beat_word = phenom_data_cell__ext_recv_select[31:0];
  assign p0_stage_done = p0_all_active_inputs_valid & (phenom_data_cell__req_not_pred | phenom_data_cell__req_load_en);
  assign sel_9574 = ____state_2[2:0] == 3'h0 ? beat_word : ____state_1[31:0];
  assign phenom_data_cell__admit_valid_inv = ~__phenom_data_cell__admit_valid_reg;
  assign phenom_data_cell__ext_recv_valid_inv = ~__phenom_data_cell__ext_recv_valid_reg;
  assign sel_9573 = ____state_2[2:0] == 3'h3 ? beat_word : ____state_1[127:96];
  assign sel_9572 = ____state_2[2:0] == 3'h2 ? beat_word : ____state_1[95:64];
  assign sel_9571 = ____state_2[2:0] == 3'h1 ? beat_word : ____state_1[63:32];
  assign phenom_data_cell__admit_valid_load_en = p0_stage_done & ~____state_0 | phenom_data_cell__admit_valid_inv;
  assign phenom_data_cell__ext_recv_valid_load_en = p0_stage_done & ____state_0 | phenom_data_cell__ext_recv_valid_inv;
  assign ____state_1__at_most_one_next_value = nor_8010 == one_hot_8023[1] & and_8011 == one_hot_8023[0];
  assign concat_8068 = {nor_8010 & p0_stage_done, and_8011 & p0_stage_done};
  assign payload = {sel_9573, sel_9572, sel_9571, sel_9574};
  assign words_seen = ____state_2 + 8'h01;
  assign phenom_data_cell__admit_load_en = phenom_data_cell__admit_vld & phenom_data_cell__admit_valid_load_en;
  assign phenom_data_cell__ext_recv_load_en = phenom_data_cell__ext_recv_vld & phenom_data_cell__ext_recv_valid_load_en;
  assign or_9582 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign nand_8039 = ~(____state_0 & beat_tlast);
  assign one_hot_sel_8069 = 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8068[0]}} | payload & {128{concat_8068[1]}};
  assign and_8083 = (nor_8010 | and_8011) & p0_stage_done;
  assign one_hot_sel_8076 = 8'h00 & {8{concat_8068[0]}} | words_seen & {8{concat_8068[1]}};
  assign __phenom_data_cell__req_buf = {{sel_9574[7:0], sel_9574[15:8], sel_9574[23:16], sel_9574[31:24]}, {sel_9573, sel_9572, sel_9571}};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_2 <= 8'h00;
      ____state_1 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_data_cell__ext_recv_reg <= __phenom_data_cell__ext_recv_reg_init;
      __phenom_data_cell__ext_recv_valid_reg <= 1'h0;
      __phenom_data_cell__admit_reg <= 1'h0;
      __phenom_data_cell__admit_valid_reg <= 1'h0;
      __phenom_data_cell__req_reg <= __phenom_data_cell__req_reg_init;
      __phenom_data_cell__req_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? nand_8039 : ____state_0;
      ____state_2 <= and_8083 ? one_hot_sel_8076 : ____state_2;
      ____state_1 <= and_8083 ? one_hot_sel_8069 : ____state_1;
      __phenom_data_cell__ext_recv_reg <= phenom_data_cell__ext_recv_load_en ? phenom_data_cell__ext_recv : __phenom_data_cell__ext_recv_reg;
      __phenom_data_cell__ext_recv_valid_reg <= phenom_data_cell__ext_recv_valid_load_en ? phenom_data_cell__ext_recv_vld : __phenom_data_cell__ext_recv_valid_reg;
      __phenom_data_cell__admit_reg <= phenom_data_cell__admit_load_en ? phenom_data_cell__admit : __phenom_data_cell__admit_reg;
      __phenom_data_cell__admit_valid_reg <= phenom_data_cell__admit_valid_load_en ? phenom_data_cell__admit_vld : __phenom_data_cell__admit_valid_reg;
      __phenom_data_cell__req_reg <= phenom_data_cell__req_load_en ? __phenom_data_cell__req_buf : __phenom_data_cell__req_reg;
      __phenom_data_cell__req_valid_reg <= phenom_data_cell__req_valid_load_en ? __phenom_data_cell__req_vld_buf : __phenom_data_cell__req_valid_reg;
    end
  end
  assign phenom_data_cell__admit_rdy = phenom_data_cell__admit_load_en;
  assign phenom_data_cell__ext_recv_rdy = phenom_data_cell__ext_recv_load_en;
  assign phenom_data_cell__req = __phenom_data_cell__req_reg;
  assign phenom_data_cell__req_vld = __phenom_data_cell__req_valid_reg;
endmodule


module __axis__Top__Tx_0_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_data_cell__north,
  input wire phenom_data_cell__north_vld,
  input wire phenom_data_cell__north_send_rdy,
  output wire phenom_data_cell__north_rdy,
  output wire [32:0] phenom_data_cell__north_send,
  output wire phenom_data_cell__north_send_vld
);
  wire [127:0] __phenom_data_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_data_cell__north_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_8139 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_data_cell__north_reg;
  reg __phenom_data_cell__north_valid_reg;
  reg [32:0] __phenom_data_cell__north_send_reg;
  reg __phenom_data_cell__north_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_data_cell__north_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_data_cell__north_send_valid_inv;
  wire nor_8151;
  wire not_8152;
  wire __phenom_data_cell__north_send_vld_buf;
  wire phenom_data_cell__north_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_data_cell__north_send_load_en;
  wire [2:0] one_hot_8161;
  wire [2:0] one_hot_8162;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_data_cell__north_valid_inv;
  wire and_8201;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_data_cell__north_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8204;
  wire [127:0] payload;
  wire [1:0] concat_8217;
  wire [7:0] beats_sent;
  wire phenom_data_cell__north_load_en;
  wire or_9586;
  wire or_9590;
  wire [7:0] one_hot_sel_8205;
  wire and_8225;
  wire [127:0] one_hot_sel_8212;
  wire [7:0] one_hot_sel_8218;
  wire [32:0] __phenom_data_cell__north_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_data_cell__north_select = state2_header_payload_words_0_case_cmp ? __phenom_data_cell__north_reg : literal_8139;
  assign frame_header__1 = phenom_data_cell__north_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_data_cell__north_send_valid_inv = ~__phenom_data_cell__north_send_valid_reg;
  assign nor_8151 = ~(last | ____state_0);
  assign not_8152 = ~last;
  assign __phenom_data_cell__north_send_vld_buf = ____state_0 | __phenom_data_cell__north_valid_reg;
  assign phenom_data_cell__north_send_valid_load_en = phenom_data_cell__north_send_rdy | phenom_data_cell__north_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8151};
  assign ____state_6__next_value_predicates = {not_8152, last};
  assign phenom_data_cell__north_send_load_en = __phenom_data_cell__north_send_vld_buf & phenom_data_cell__north_send_valid_load_en;
  assign one_hot_8161 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8162 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_data_cell__north_send_vld_buf & phenom_data_cell__north_send_load_en;
  assign phenom_data_cell__north_valid_inv = ~__phenom_data_cell__north_valid_reg;
  assign and_8201 = last & p0_stage_done;
  assign frame_payload__1 = phenom_data_cell__north_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_data_cell__north_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_data_cell__north_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8161[1] & nor_8151 == one_hot_8161[0];
  assign ____state_6__at_most_one_next_value = not_8152 == one_hot_8162[1] & last == one_hot_8162[0];
  assign concat_8204 = {and_8201, nor_8151 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8217 = {not_8152 & p0_stage_done, and_8201};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_data_cell__north_load_en = phenom_data_cell__north_vld & phenom_data_cell__north_valid_load_en;
  assign or_9586 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9590 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8205 = frame_header_payload_words__1 & {8{concat_8204[0]}} | 8'h00 & {8{concat_8204[1]}};
  assign and_8225 = (last | nor_8151) & p0_stage_done;
  assign one_hot_sel_8212 = payload & {128{concat_8204[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8204[1]}};
  assign one_hot_sel_8218 = 8'h00 & {8{concat_8217[0]}} | beats_sent & {8{concat_8217[1]}};
  assign __phenom_data_cell__north_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_data_cell__north_reg <= __phenom_data_cell__north_reg_init;
      __phenom_data_cell__north_valid_reg <= 1'h0;
      __phenom_data_cell__north_send_reg <= __phenom_data_cell__north_send_reg_init;
      __phenom_data_cell__north_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_8152 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8218 : ____state_6;
      ____state_1 <= and_8225 ? one_hot_sel_8205 : ____state_1;
      ____state_5 <= and_8225 ? one_hot_sel_8212 : ____state_5;
      __phenom_data_cell__north_reg <= phenom_data_cell__north_load_en ? phenom_data_cell__north : __phenom_data_cell__north_reg;
      __phenom_data_cell__north_valid_reg <= phenom_data_cell__north_valid_load_en ? phenom_data_cell__north_vld : __phenom_data_cell__north_valid_reg;
      __phenom_data_cell__north_send_reg <= phenom_data_cell__north_send_load_en ? __phenom_data_cell__north_send_buf : __phenom_data_cell__north_send_reg;
      __phenom_data_cell__north_send_valid_reg <= phenom_data_cell__north_send_valid_load_en ? __phenom_data_cell__north_send_vld_buf : __phenom_data_cell__north_send_valid_reg;
    end
  end
  assign phenom_data_cell__north_rdy = phenom_data_cell__north_load_en;
  assign phenom_data_cell__north_send = __phenom_data_cell__north_send_reg;
  assign phenom_data_cell__north_send_vld = __phenom_data_cell__north_send_valid_reg;
endmodule


module __axis__Top__Tx_1_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_data_cell__east,
  input wire phenom_data_cell__east_vld,
  input wire phenom_data_cell__east_send_rdy,
  output wire phenom_data_cell__east_rdy,
  output wire [32:0] phenom_data_cell__east_send,
  output wire phenom_data_cell__east_send_vld
);
  wire [127:0] __phenom_data_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_data_cell__east_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_8274 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_data_cell__east_reg;
  reg __phenom_data_cell__east_valid_reg;
  reg [32:0] __phenom_data_cell__east_send_reg;
  reg __phenom_data_cell__east_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_data_cell__east_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_data_cell__east_send_valid_inv;
  wire nor_8286;
  wire not_8287;
  wire __phenom_data_cell__east_send_vld_buf;
  wire phenom_data_cell__east_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_data_cell__east_send_load_en;
  wire [2:0] one_hot_8296;
  wire [2:0] one_hot_8297;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_data_cell__east_valid_inv;
  wire and_8336;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_data_cell__east_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8339;
  wire [127:0] payload;
  wire [1:0] concat_8352;
  wire [7:0] beats_sent;
  wire phenom_data_cell__east_load_en;
  wire or_9592;
  wire or_9596;
  wire [7:0] one_hot_sel_8340;
  wire and_8360;
  wire [127:0] one_hot_sel_8347;
  wire [7:0] one_hot_sel_8353;
  wire [32:0] __phenom_data_cell__east_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_data_cell__east_select = state2_header_payload_words_0_case_cmp ? __phenom_data_cell__east_reg : literal_8274;
  assign frame_header__1 = phenom_data_cell__east_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_data_cell__east_send_valid_inv = ~__phenom_data_cell__east_send_valid_reg;
  assign nor_8286 = ~(last | ____state_0);
  assign not_8287 = ~last;
  assign __phenom_data_cell__east_send_vld_buf = ____state_0 | __phenom_data_cell__east_valid_reg;
  assign phenom_data_cell__east_send_valid_load_en = phenom_data_cell__east_send_rdy | phenom_data_cell__east_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8286};
  assign ____state_6__next_value_predicates = {not_8287, last};
  assign phenom_data_cell__east_send_load_en = __phenom_data_cell__east_send_vld_buf & phenom_data_cell__east_send_valid_load_en;
  assign one_hot_8296 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8297 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_data_cell__east_send_vld_buf & phenom_data_cell__east_send_load_en;
  assign phenom_data_cell__east_valid_inv = ~__phenom_data_cell__east_valid_reg;
  assign and_8336 = last & p0_stage_done;
  assign frame_payload__1 = phenom_data_cell__east_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_data_cell__east_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_data_cell__east_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8296[1] & nor_8286 == one_hot_8296[0];
  assign ____state_6__at_most_one_next_value = not_8287 == one_hot_8297[1] & last == one_hot_8297[0];
  assign concat_8339 = {and_8336, nor_8286 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8352 = {not_8287 & p0_stage_done, and_8336};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_data_cell__east_load_en = phenom_data_cell__east_vld & phenom_data_cell__east_valid_load_en;
  assign or_9592 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9596 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8340 = frame_header_payload_words__1 & {8{concat_8339[0]}} | 8'h00 & {8{concat_8339[1]}};
  assign and_8360 = (last | nor_8286) & p0_stage_done;
  assign one_hot_sel_8347 = payload & {128{concat_8339[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8339[1]}};
  assign one_hot_sel_8353 = 8'h00 & {8{concat_8352[0]}} | beats_sent & {8{concat_8352[1]}};
  assign __phenom_data_cell__east_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_data_cell__east_reg <= __phenom_data_cell__east_reg_init;
      __phenom_data_cell__east_valid_reg <= 1'h0;
      __phenom_data_cell__east_send_reg <= __phenom_data_cell__east_send_reg_init;
      __phenom_data_cell__east_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_8287 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8353 : ____state_6;
      ____state_1 <= and_8360 ? one_hot_sel_8340 : ____state_1;
      ____state_5 <= and_8360 ? one_hot_sel_8347 : ____state_5;
      __phenom_data_cell__east_reg <= phenom_data_cell__east_load_en ? phenom_data_cell__east : __phenom_data_cell__east_reg;
      __phenom_data_cell__east_valid_reg <= phenom_data_cell__east_valid_load_en ? phenom_data_cell__east_vld : __phenom_data_cell__east_valid_reg;
      __phenom_data_cell__east_send_reg <= phenom_data_cell__east_send_load_en ? __phenom_data_cell__east_send_buf : __phenom_data_cell__east_send_reg;
      __phenom_data_cell__east_send_valid_reg <= phenom_data_cell__east_send_valid_load_en ? __phenom_data_cell__east_send_vld_buf : __phenom_data_cell__east_send_valid_reg;
    end
  end
  assign phenom_data_cell__east_rdy = phenom_data_cell__east_load_en;
  assign phenom_data_cell__east_send = __phenom_data_cell__east_send_reg;
  assign phenom_data_cell__east_send_vld = __phenom_data_cell__east_send_valid_reg;
endmodule


module __axis__Top__Tx_2_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_data_cell__west,
  input wire phenom_data_cell__west_vld,
  input wire phenom_data_cell__west_send_rdy,
  output wire phenom_data_cell__west_rdy,
  output wire [32:0] phenom_data_cell__west_send,
  output wire phenom_data_cell__west_send_vld
);
  wire [127:0] __phenom_data_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_data_cell__west_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_8409 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_data_cell__west_reg;
  reg __phenom_data_cell__west_valid_reg;
  reg [32:0] __phenom_data_cell__west_send_reg;
  reg __phenom_data_cell__west_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_data_cell__west_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_data_cell__west_send_valid_inv;
  wire nor_8421;
  wire not_8422;
  wire __phenom_data_cell__west_send_vld_buf;
  wire phenom_data_cell__west_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_data_cell__west_send_load_en;
  wire [2:0] one_hot_8431;
  wire [2:0] one_hot_8432;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_data_cell__west_valid_inv;
  wire and_8471;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_data_cell__west_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8474;
  wire [127:0] payload;
  wire [1:0] concat_8487;
  wire [7:0] beats_sent;
  wire phenom_data_cell__west_load_en;
  wire or_9598;
  wire or_9602;
  wire [7:0] one_hot_sel_8475;
  wire and_8495;
  wire [127:0] one_hot_sel_8482;
  wire [7:0] one_hot_sel_8488;
  wire [32:0] __phenom_data_cell__west_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_data_cell__west_select = state2_header_payload_words_0_case_cmp ? __phenom_data_cell__west_reg : literal_8409;
  assign frame_header__1 = phenom_data_cell__west_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_data_cell__west_send_valid_inv = ~__phenom_data_cell__west_send_valid_reg;
  assign nor_8421 = ~(last | ____state_0);
  assign not_8422 = ~last;
  assign __phenom_data_cell__west_send_vld_buf = ____state_0 | __phenom_data_cell__west_valid_reg;
  assign phenom_data_cell__west_send_valid_load_en = phenom_data_cell__west_send_rdy | phenom_data_cell__west_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8421};
  assign ____state_6__next_value_predicates = {not_8422, last};
  assign phenom_data_cell__west_send_load_en = __phenom_data_cell__west_send_vld_buf & phenom_data_cell__west_send_valid_load_en;
  assign one_hot_8431 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8432 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_data_cell__west_send_vld_buf & phenom_data_cell__west_send_load_en;
  assign phenom_data_cell__west_valid_inv = ~__phenom_data_cell__west_valid_reg;
  assign and_8471 = last & p0_stage_done;
  assign frame_payload__1 = phenom_data_cell__west_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_data_cell__west_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_data_cell__west_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8431[1] & nor_8421 == one_hot_8431[0];
  assign ____state_6__at_most_one_next_value = not_8422 == one_hot_8432[1] & last == one_hot_8432[0];
  assign concat_8474 = {and_8471, nor_8421 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8487 = {not_8422 & p0_stage_done, and_8471};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_data_cell__west_load_en = phenom_data_cell__west_vld & phenom_data_cell__west_valid_load_en;
  assign or_9598 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9602 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8475 = frame_header_payload_words__1 & {8{concat_8474[0]}} | 8'h00 & {8{concat_8474[1]}};
  assign and_8495 = (last | nor_8421) & p0_stage_done;
  assign one_hot_sel_8482 = payload & {128{concat_8474[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8474[1]}};
  assign one_hot_sel_8488 = 8'h00 & {8{concat_8487[0]}} | beats_sent & {8{concat_8487[1]}};
  assign __phenom_data_cell__west_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_data_cell__west_reg <= __phenom_data_cell__west_reg_init;
      __phenom_data_cell__west_valid_reg <= 1'h0;
      __phenom_data_cell__west_send_reg <= __phenom_data_cell__west_send_reg_init;
      __phenom_data_cell__west_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_8422 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8488 : ____state_6;
      ____state_1 <= and_8495 ? one_hot_sel_8475 : ____state_1;
      ____state_5 <= and_8495 ? one_hot_sel_8482 : ____state_5;
      __phenom_data_cell__west_reg <= phenom_data_cell__west_load_en ? phenom_data_cell__west : __phenom_data_cell__west_reg;
      __phenom_data_cell__west_valid_reg <= phenom_data_cell__west_valid_load_en ? phenom_data_cell__west_vld : __phenom_data_cell__west_valid_reg;
      __phenom_data_cell__west_send_reg <= phenom_data_cell__west_send_load_en ? __phenom_data_cell__west_send_buf : __phenom_data_cell__west_send_reg;
      __phenom_data_cell__west_send_valid_reg <= phenom_data_cell__west_send_valid_load_en ? __phenom_data_cell__west_send_vld_buf : __phenom_data_cell__west_send_valid_reg;
    end
  end
  assign phenom_data_cell__west_rdy = phenom_data_cell__west_load_en;
  assign phenom_data_cell__west_send = __phenom_data_cell__west_send_reg;
  assign phenom_data_cell__west_send_vld = __phenom_data_cell__west_send_valid_reg;
endmodule


module __axis__Top__Tx_3_next(
  input wire clk,
  input wire reset,
  input wire [127:0] phenom_data_cell__south,
  input wire phenom_data_cell__south_vld,
  input wire phenom_data_cell__south_send_rdy,
  output wire phenom_data_cell__south_rdy,
  output wire [32:0] phenom_data_cell__south_send,
  output wire phenom_data_cell__south_send_vld
);
  wire [127:0] __phenom_data_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [32:0] __phenom_data_cell__south_send_reg_init = {1'h0, 32'h0000_0000};
  wire [127:0] literal_8544 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  reg ____state_0;
  reg [7:0] ____state_6;
  reg [7:0] ____state_1;
  reg [127:0] ____state_5;
  reg [127:0] __phenom_data_cell__south_reg;
  reg __phenom_data_cell__south_valid_reg;
  reg [32:0] __phenom_data_cell__south_send_reg;
  reg __phenom_data_cell__south_send_valid_reg;
  wire state2_header_payload_words_0_case_cmp;
  wire [127:0] phenom_data_cell__south_select;
  wire [31:0] frame_header__1;
  wire [7:0] frame_header_payload_words__1;
  wire [7:0] state2_beats_sent__2;
  wire [7:0] state2_header_payload_words;
  wire last;
  wire phenom_data_cell__south_send_valid_inv;
  wire nor_8556;
  wire not_8557;
  wire __phenom_data_cell__south_send_vld_buf;
  wire phenom_data_cell__south_send_valid_load_en;
  wire [1:0] ____state_1__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire phenom_data_cell__south_send_load_en;
  wire [2:0] one_hot_8566;
  wire [2:0] one_hot_8567;
  wire [7:0] frame_header_op__1;
  wire [7:0] frame_header_flags__1;
  wire [7:0] frame_header_txid__1;
  wire p0_stage_done;
  wire phenom_data_cell__south_valid_inv;
  wire and_8606;
  wire [95:0] frame_payload__1;
  wire [31:0] state2_payload__1;
  wire phenom_data_cell__south_valid_load_en;
  wire ____state_1__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire [1:0] concat_8609;
  wire [127:0] payload;
  wire [1:0] concat_8622;
  wire [7:0] beats_sent;
  wire phenom_data_cell__south_load_en;
  wire or_9604;
  wire or_9608;
  wire [7:0] one_hot_sel_8610;
  wire and_8630;
  wire [127:0] one_hot_sel_8617;
  wire [7:0] one_hot_sel_8623;
  wire [32:0] __phenom_data_cell__south_send_buf;
  assign state2_header_payload_words_0_case_cmp = ~____state_0;
  assign phenom_data_cell__south_select = state2_header_payload_words_0_case_cmp ? __phenom_data_cell__south_reg : literal_8544;
  assign frame_header__1 = phenom_data_cell__south_select[127:96];
  assign frame_header_payload_words__1 = frame_header__1[31:24];
  assign state2_beats_sent__2 = ____state_6 & {8{____state_0}};
  assign state2_header_payload_words = ____state_0 ? ____state_1 : frame_header_payload_words__1;
  assign last = state2_beats_sent__2 == state2_header_payload_words;
  assign phenom_data_cell__south_send_valid_inv = ~__phenom_data_cell__south_send_valid_reg;
  assign nor_8556 = ~(last | ____state_0);
  assign not_8557 = ~last;
  assign __phenom_data_cell__south_send_vld_buf = ____state_0 | __phenom_data_cell__south_valid_reg;
  assign phenom_data_cell__south_send_valid_load_en = phenom_data_cell__south_send_rdy | phenom_data_cell__south_send_valid_inv;
  assign ____state_1__next_value_predicates = {last, nor_8556};
  assign ____state_6__next_value_predicates = {not_8557, last};
  assign phenom_data_cell__south_send_load_en = __phenom_data_cell__south_send_vld_buf & phenom_data_cell__south_send_valid_load_en;
  assign one_hot_8566 = {____state_1__next_value_predicates[1:0] == 2'h0, ____state_1__next_value_predicates[1] && !____state_1__next_value_predicates[0], ____state_1__next_value_predicates[0]};
  assign one_hot_8567 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign frame_header_op__1 = frame_header__1[7:0];
  assign frame_header_flags__1 = frame_header__1[15:8];
  assign frame_header_txid__1 = frame_header__1[23:16];
  assign p0_stage_done = __phenom_data_cell__south_send_vld_buf & phenom_data_cell__south_send_load_en;
  assign phenom_data_cell__south_valid_inv = ~__phenom_data_cell__south_valid_reg;
  assign and_8606 = last & p0_stage_done;
  assign frame_payload__1 = phenom_data_cell__south_select[95:0];
  assign state2_payload__1 = ____state_0 ? ____state_5[31:0] : {frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign phenom_data_cell__south_valid_load_en = p0_stage_done & state2_header_payload_words_0_case_cmp | phenom_data_cell__south_valid_inv;
  assign ____state_1__at_most_one_next_value = last == one_hot_8566[1] & nor_8556 == one_hot_8566[0];
  assign ____state_6__at_most_one_next_value = not_8557 == one_hot_8567[1] & last == one_hot_8567[0];
  assign concat_8609 = {and_8606, nor_8556 & p0_stage_done};
  assign payload = {frame_payload__1, frame_header_op__1, frame_header_flags__1, frame_header_txid__1, frame_header_payload_words__1};
  assign concat_8622 = {not_8557 & p0_stage_done, and_8606};
  assign beats_sent = state2_beats_sent__2 + 8'h01;
  assign phenom_data_cell__south_load_en = phenom_data_cell__south_vld & phenom_data_cell__south_valid_load_en;
  assign or_9604 = ~p0_stage_done | ____state_1__at_most_one_next_value | reset;
  assign or_9608 = ~p0_stage_done | ____state_6__at_most_one_next_value | reset;
  assign one_hot_sel_8610 = frame_header_payload_words__1 & {8{concat_8609[0]}} | 8'h00 & {8{concat_8609[1]}};
  assign and_8630 = (last | nor_8556) & p0_stage_done;
  assign one_hot_sel_8617 = payload & {128{concat_8609[0]}} | 128'h0000_0000_0000_0000_0000_0000_0000_0000 & {128{concat_8609[1]}};
  assign one_hot_sel_8623 = 8'h00 & {8{concat_8622[0]}} | beats_sent & {8{concat_8622[1]}};
  assign __phenom_data_cell__south_send_buf = {last, state2_beats_sent__2[2:0] == 3'h0 ? state2_payload__1 : (state2_beats_sent__2[2:0] == 3'h1 ? ____state_5[63:32] : (state2_beats_sent__2[2:0] == 3'h2 ? ____state_5[95:64] : (state2_beats_sent__2[2:0] == 3'h3 ? ____state_5[127:96] : 32'h0000_0000)))};
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0 <= 1'h0;
      ____state_6 <= 8'h00;
      ____state_1 <= 8'h00;
      ____state_5 <= 128'h0000_0000_0000_0000_0000_0000_0000_0000;
      __phenom_data_cell__south_reg <= __phenom_data_cell__south_reg_init;
      __phenom_data_cell__south_valid_reg <= 1'h0;
      __phenom_data_cell__south_send_reg <= __phenom_data_cell__south_send_reg_init;
      __phenom_data_cell__south_send_valid_reg <= 1'h0;
    end else begin
      ____state_0 <= p0_stage_done ? not_8557 : ____state_0;
      ____state_6 <= p0_stage_done ? one_hot_sel_8623 : ____state_6;
      ____state_1 <= and_8630 ? one_hot_sel_8610 : ____state_1;
      ____state_5 <= and_8630 ? one_hot_sel_8617 : ____state_5;
      __phenom_data_cell__south_reg <= phenom_data_cell__south_load_en ? phenom_data_cell__south : __phenom_data_cell__south_reg;
      __phenom_data_cell__south_valid_reg <= phenom_data_cell__south_valid_load_en ? phenom_data_cell__south_vld : __phenom_data_cell__south_valid_reg;
      __phenom_data_cell__south_send_reg <= phenom_data_cell__south_send_load_en ? __phenom_data_cell__south_send_buf : __phenom_data_cell__south_send_reg;
      __phenom_data_cell__south_send_valid_reg <= phenom_data_cell__south_send_valid_load_en ? __phenom_data_cell__south_send_vld_buf : __phenom_data_cell__south_send_valid_reg;
    end
  end
  assign phenom_data_cell__south_rdy = phenom_data_cell__south_load_en;
  assign phenom_data_cell__south_send = __phenom_data_cell__south_send_reg;
  assign phenom_data_cell__south_send_vld = __phenom_data_cell__south_send_valid_reg;
endmodule


module __phenom_data_cell__Top_0_next__1(
  input wire clk,
  input wire reset
);

endmodule


module __phenom_data_cell__Top__Service_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_data_cell__admit_rdy,
  input wire phenom_data_cell__east_rdy,
  input wire phenom_data_cell__north_rdy,
  input wire [127:0] phenom_data_cell__req,
  input wire phenom_data_cell__req_vld,
  input wire phenom_data_cell__south_rdy,
  input wire phenom_data_cell__west_rdy,
  output wire phenom_data_cell__admit,
  output wire phenom_data_cell__admit_vld,
  output wire [127:0] phenom_data_cell__east,
  output wire phenom_data_cell__east_vld,
  output wire [127:0] phenom_data_cell__north,
  output wire phenom_data_cell__north_vld,
  output wire phenom_data_cell__req_rdy,
  output wire [127:0] phenom_data_cell__south,
  output wire phenom_data_cell__south_vld,
  output wire [127:0] phenom_data_cell__west,
  output wire phenom_data_cell__west_vld
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
  function automatic [1:0] priority_sel_2b_4way (input reg [3:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] case3, input reg [1:0] default_value);
    begin
      casez (sel)
        4'b???1: begin
          priority_sel_2b_4way = case0;
        end
        4'b??10: begin
          priority_sel_2b_4way = case1;
        end
        4'b?100: begin
          priority_sel_2b_4way = case2;
        end
        4'b1000: begin
          priority_sel_2b_4way = case3;
        end
        4'b0000: begin
          priority_sel_2b_4way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_4way = 2'dx;
        end
      endcase
    end
  endfunction
  function automatic [1:0] priority_sel_2b_6way (input reg [5:0] sel, input reg [1:0] case0, input reg [1:0] case1, input reg [1:0] case2, input reg [1:0] case3, input reg [1:0] case4, input reg [1:0] case5, input reg [1:0] default_value);
    begin
      casez (sel)
        6'b?????1: begin
          priority_sel_2b_6way = case0;
        end
        6'b????10: begin
          priority_sel_2b_6way = case1;
        end
        6'b???100: begin
          priority_sel_2b_6way = case2;
        end
        6'b??1000: begin
          priority_sel_2b_6way = case3;
        end
        6'b?10000: begin
          priority_sel_2b_6way = case4;
        end
        6'b100000: begin
          priority_sel_2b_6way = case5;
        end
        6'b00_0000: begin
          priority_sel_2b_6way = default_value;
        end
        default: begin
          // Propagate X
          priority_sel_2b_6way = 2'dx;
        end
      endcase
    end
  endfunction
  wire ____state_7_tuple_element_0_init[0:4];
  assign ____state_7_tuple_element_0_init[0] = 1'h0;
  assign ____state_7_tuple_element_0_init[1] = 1'h0;
  assign ____state_7_tuple_element_0_init[2] = 1'h0;
  assign ____state_7_tuple_element_0_init[3] = 1'h0;
  assign ____state_7_tuple_element_0_init[4] = 1'h0;
  wire [95:0] ____state_7_tuple_element_1_tuple_element_1_init[0:4];
  assign ____state_7_tuple_element_1_tuple_element_1_init[0] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_7_tuple_element_1_tuple_element_1_init[1] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_7_tuple_element_1_tuple_element_1_init[2] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_7_tuple_element_1_tuple_element_1_init[3] = 96'h0000_0000_0000_0000_0000_0000;
  assign ____state_7_tuple_element_1_tuple_element_1_init[4] = 96'h0000_0000_0000_0000_0000_0000;
  wire [7:0] ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[0:4];
  assign ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[0] = 8'h00;
  assign ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[1] = 8'h00;
  assign ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[2] = 8'h00;
  assign ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[3] = 8'h00;
  assign ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[4] = 8'h00;
  wire [127:0] __phenom_data_cell__req_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_data_cell__north_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_data_cell__east_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_data_cell__west_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] __phenom_data_cell__south_reg_init = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire [127:0] literal_8741 = {{8'h00, 8'h00, 8'h00, 8'h00}, 96'h0000_0000_0000_0000_0000_0000};
  wire unblocked_slots_tuple_idx_0[0:4];
  assign unblocked_slots_tuple_idx_0[0] = 1'h0;
  assign unblocked_slots_tuple_idx_0[1] = 1'h0;
  assign unblocked_slots_tuple_idx_0[2] = 1'h0;
  assign unblocked_slots_tuple_idx_0[3] = 1'h0;
  assign unblocked_slots_tuple_idx_0[4] = 1'h0;
  wire [31:0] literal_8701 = {8'h03, 8'h00, 8'h00, 8'h09};
  reg ____state_10;
  reg ____state_11;
  reg ____state_9;
  reg ____state_7_tuple_element_0[0:4];
  reg [7:0] ____state_8;
  reg [95:0] ____state_7_tuple_element_1_tuple_element_1[0:4];
  reg [31:0] ____state_3;
  reg [7:0] ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[0:4];
  reg [31:0] ____state_2;
  reg [31:0] ____state_6;
  reg [1:0] ____state_0;
  reg [31:0] ____state_4;
  reg ____state_5;
  reg __phenom_data_cell__admit_has_been_sent_reg;
  reg __phenom_data_cell__north_has_been_sent_reg;
  reg __phenom_data_cell__east_has_been_sent_reg;
  reg __phenom_data_cell__west_has_been_sent_reg;
  reg __phenom_data_cell__south_has_been_sent_reg;
  reg [127:0] __phenom_data_cell__req_reg;
  reg __phenom_data_cell__req_valid_reg;
  reg __phenom_data_cell__admit_reg;
  reg __phenom_data_cell__admit_valid_reg;
  reg [127:0] __phenom_data_cell__north_reg;
  reg __phenom_data_cell__north_valid_reg;
  reg [127:0] __phenom_data_cell__east_reg;
  reg __phenom_data_cell__east_valid_reg;
  reg [127:0] __phenom_data_cell__west_reg;
  reg __phenom_data_cell__west_valid_reg;
  reg [127:0] __phenom_data_cell__south_reg;
  reg __phenom_data_cell__south_valid_reg;
  wire nor_8739;
  wire received;
  wire [127:0] phenom_data_cell__req_select;
  wire [31:0] frame_header;
  wire [7:0] frame_header_op;
  wire [7:0] frame_header__1_payload_words;
  wire [7:0] MAILBOX_CAPACITY;
  wire eq_8750;
  wire eq_8752;
  wire tag_ok;
  wire accepted;
  wire [7:0] admitted_occupied;
  wire and_8777;
  wire [31:0] concat_8778;
  wire ugt_8780;
  wire admitted_slots_tuple_idx_0[0:4];
  wire or_reduce_8782;
  wire postponed__4;
  wire ugt_8786;
  wire postponed__3;
  wire eligible_4;
  wire [1:0] unexpand_for_next_value_1354_0_case_0_case_5_case_0;
  wire or_reduce_8790;
  wire postponed__2;
  wire eligible_3;
  wire postponed__1;
  wire eligible_2;
  wire [7:0] compacted_4_tup1_tup0_tup0;
  wire eligible_1;
  wire eq_8801;
  wire postponed;
  wire [95:0] sel_8810;
  wire [7:0] selected;
  wire [95:0] admitted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [2:0] bit_slice_8813;
  wire [95:0] selected_slot_tuple_idx_1_tuple_idx_1;
  wire [31:0] Xls_clause_1_Source_1;
  wire [31:0] _4__4_source;
  wire [31:0] _4__3_source;
  wire [31:0] _4__2_source;
  wire [31:0] _4__1_source;
  wire [31:0] Xls_clause_1_Seed_1;
  wire _0__4;
  wire _1__1;
  wire _2__1;
  wire [31:0] _7;
  wire or_8827;
  wire _8;
  wire [31:0] _0__5;
  wire and_8831;
  wire [7:0] sel_8829;
  wire _2__2;
  wire [1:0] unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0;
  wire [1:0] unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1;
  wire [7:0] admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [7:0] selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3;
  wire eq_8847;
  wire eq_8848;
  wire nor_8849;
  wire [1:0] and_8853;
  wire and_8854;
  wire _0;
  wire [2:0] concat_8861;
  wire postponed_slot_tup0;
  wire [1:0] concat_8873;
  wire eligible_0;
  wire invalid_input;
  wire eq_8846;
  wire eq_8862;
  wire eq_8850;
  wire or_8883;
  wire invalid_repeat;
  wire found;
  wire dispatchable;
  wire [18:0] _14__2;
  wire [31:0] Xls_clause_1_NewSeen_1;
  wire [1:0] priority_sel_8901;
  wire _12;
  wire [1:0] directive;
  wire nand_8884;
  wire candidate_slots_0_case_cmp;
  wire [14:0] _15__2;
  wire candidate_occupied_1_case_cmp;
  wire [7:0] add_8929;
  wire [1:0] priority_sel_8900;
  wire failed;
  wire [7:0] candidate_occupied;
  wire [1:0] candidate_phase_squeezed;
  wire [16:0] Xls_clause_1_NextRandom_1__3;
  wire [9:0] Xls_clause_1_NextRandom_1__2;
  wire [4:0] Xls_clause_1_NextRandom_1__1;
  wire phase_changed;
  wire reserve__1;
  wire reserve;
  wire and_8917;
  wire [31:0] Xls_clause_1_NextRandom_1;
  wire and_8922;
  wire _18;
  wire nor_8925;
  wire eq_8926;
  wire nor_8927;
  wire __phenom_data_cell__admit_buf;
  wire __phenom_data_cell__admit_not_has_been_sent;
  wire phenom_data_cell__admit_valid_inv;
  wire __phenom_data_cell__east_vld_buf;
  wire __phenom_data_cell__north_not_has_been_sent;
  wire phenom_data_cell__north_valid_inv;
  wire __phenom_data_cell__east_not_has_been_sent;
  wire phenom_data_cell__east_valid_inv;
  wire __phenom_data_cell__west_not_has_been_sent;
  wire phenom_data_cell__west_valid_inv;
  wire __phenom_data_cell__south_not_has_been_sent;
  wire phenom_data_cell__south_valid_inv;
  wire and_8930;
  wire and_8931;
  wire nor_8932;
  wire candidate_occupied_0_case_cmp;
  wire and_8935;
  wire Xls_clause_1_Event_1_0_case_cmp;
  wire and_8937;
  wire transition_slots_predicate_piece_0;
  wire or_8940;
  wire and_8941;
  wire __phenom_data_cell__admit_valid_and_not_has_been_sent;
  wire phenom_data_cell__admit_valid_load_en;
  wire __phenom_data_cell__north_valid_and_not_has_been_sent;
  wire phenom_data_cell__north_valid_load_en;
  wire __phenom_data_cell__east_valid_and_not_has_been_sent;
  wire phenom_data_cell__east_valid_load_en;
  wire __phenom_data_cell__west_valid_and_not_has_been_sent;
  wire phenom_data_cell__west_valid_load_en;
  wire __phenom_data_cell__south_valid_and_not_has_been_sent;
  wire phenom_data_cell__south_valid_load_en;
  wire and_8945;
  wire and_8946;
  wire and_8947;
  wire and_8948;
  wire and_8949;
  wire nor_8950;
  wire and_8951;
  wire and_8952;
  wire and_8953;
  wire and_8954;
  wire and_8955;
  wire and_8956;
  wire and_8957;
  wire and_8958;
  wire and_8959;
  wire and_8960;
  wire and_8961;
  wire and_8962;
  wire and_8963;
  wire and_8964;
  wire phenom_data_cell__admit_not_pred;
  wire phenom_data_cell__admit_load_en;
  wire phenom_data_cell__east_not_pred;
  wire phenom_data_cell__north_load_en;
  wire phenom_data_cell__east_load_en;
  wire phenom_data_cell__west_load_en;
  wire phenom_data_cell__south_load_en;
  wire [1:0] ____state_3__next_value_predicates;
  wire [1:0] ____state_6__next_value_predicates;
  wire [1:0] ____state_8__next_value_predicates;
  wire [1:0] ____state_10__next_value_predicates;
  wire [6:0] ____state_0__next_value_predicates;
  wire [2:0] ____state_5__next_value_predicates;
  wire [4:0] ____state_7_tuple_element_0__next_value_predicates;
  wire [7:0] ____state_7_tuple_element_1_tuple_element_1__next_value_predicates;
  wire [2:0] one_hot_8997;
  wire [2:0] one_hot_8998;
  wire [2:0] one_hot_8999;
  wire [2:0] one_hot_9000;
  wire [7:0] one_hot_9001;
  wire [3:0] one_hot_9002;
  wire [5:0] one_hot_9003;
  wire [8:0] one_hot_9004;
  wire [95:0] array_index_8981;
  wire [95:0] array_index_8983;
  wire [95:0] array_index_8985;
  wire [7:0] array_index_8989;
  wire [7:0] array_index_8991;
  wire [7:0] array_index_8993;
  wire p0_all_active_outputs_ready;
  wire ne_9011;
  wire or_reduce_9013;
  wire ugt_9015;
  wire [2:0] one_hot_9575;
  wire phenom_data_cell__req_valid_inv;
  wire and_9195;
  wire and_9204;
  wire and_9205;
  wire admission_pending;
  wire and_9250;
  wire and_9251;
  wire and_9252;
  wire and_9253;
  wire [31:0] concat_9073;
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
  wire [30:0] leading_bits___state_5;
  wire phenom_data_cell__req_valid_load_en;
  wire ____state_3__at_most_one_next_value;
  wire ____state_6__at_most_one_next_value;
  wire ____state_8__at_most_one_next_value;
  wire ____state_10__at_most_one_next_value;
  wire ____state_0__at_most_one_next_value;
  wire ____state_5__at_most_one_next_value;
  wire ____state_7_tuple_element_0__at_most_one_next_value;
  wire ____state_7_tuple_element_1_tuple_element_1__at_most_one_next_value;
  wire [1:0] concat_9197;
  wire [1:0] concat_9207;
  wire [1:0] concat_9214;
  wire [1:0] concat_9224;
  wire [6:0] concat_9237;
  wire [2:0] concat_9245;
  wire [4:0] concat_9255;
  wire postponed_slots_tuple_idx_0[0:4];
  wire compacted_slots_tuple_idx_0[0:4];
  wire [7:0] concat_9268;
  wire [95:0] postponed_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [95:0] compacted_slots_tuple_idx_1_tuple_idx_1[0:4];
  wire [7:0] postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire [7:0] compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0:4];
  wire __phenom_data_cell__admit_valid_and_all_active_outputs_ready;
  wire __phenom_data_cell__admit_valid_and_ready_txfr;
  wire __phenom_data_cell__east_valid_and_all_active_outputs_ready;
  wire __phenom_data_cell__north_valid_and_ready_txfr;
  wire __phenom_data_cell__east_valid_and_ready_txfr;
  wire __phenom_data_cell__west_valid_and_ready_txfr;
  wire __phenom_data_cell__south_valid_and_ready_txfr;
  wire phenom_data_cell__req_load_en;
  wire or_9610;
  wire or_9612;
  wire or_9614;
  wire or_9616;
  wire or_9618;
  wire or_9620;
  wire or_9622;
  wire or_9624;
  wire and_9291;
  wire [31:0] one_hot_sel_9198;
  wire and_9294;
  wire and_9296;
  wire [31:0] one_hot_sel_9208;
  wire and_9299;
  wire [7:0] one_hot_sel_9215;
  wire and_9302;
  wire and_9120;
  wire and_9304;
  wire one_hot_sel_9225;
  wire and_9307;
  wire or_9118;
  wire [1:0] one_hot_sel_9238;
  wire and_9311;
  wire one_hot_sel_9246;
  wire and_9314;
  wire one_hot_sel_9256[0:4];
  wire and_9317;
  wire [95:0] one_hot_sel_9269[0:4];
  wire and_9320;
  wire [7:0] one_hot_sel_9282[0:4];
  wire __phenom_data_cell__admit_not_stage_load;
  wire __phenom_data_cell__admit_has_been_sent_reg_load_en;
  wire __phenom_data_cell__east_not_stage_load;
  wire __phenom_data_cell__north_has_been_sent_reg_load_en;
  wire __phenom_data_cell__east_has_been_sent_reg_load_en;
  wire __phenom_data_cell__west_has_been_sent_reg_load_en;
  wire __phenom_data_cell__south_has_been_sent_reg_load_en;
  wire [127:0] effects_north;
  wire [127:0] effects_east;
  wire [127:0] effects_west;
  wire [127:0] effects_south;
  wire or_9628;
  assign nor_8739 = ~(____state_11 | ____state_9 | ~____state_10);
  assign received = nor_8739 & __phenom_data_cell__req_valid_reg;
  assign phenom_data_cell__req_select = received ? __phenom_data_cell__req_reg : literal_8741;
  assign frame_header = phenom_data_cell__req_select[127:96];
  assign frame_header_op = frame_header[7:0];
  assign frame_header__1_payload_words = frame_header[31:24];
  assign MAILBOX_CAPACITY = 8'h05;
  assign eq_8750 = frame_header__1_payload_words == 8'h03;
  assign eq_8752 = frame_header__1_payload_words == 8'h02;
  assign tag_ok = frame_header_op == 8'h03 & eq_8750 | frame_header_op == 8'h04 & eq_8752 | frame_header_op == MAILBOX_CAPACITY & eq_8750 | frame_header_op == 8'h06 & eq_8752 | frame_header_op == 8'h07 & frame_header__1_payload_words == 8'h01 | frame_header_op == 8'h08 & eq_8752 | frame_header_op == 8'h09 & eq_8750 | frame_header_op == 8'h0a & eq_8752;
  assign accepted = received & tag_ok;
  assign admitted_occupied = ____state_8 + {7'h00, accepted};
  assign and_8777 = ~accepted & ____state_7_tuple_element_0[____state_8 > 8'h04 ? 3'h4 : ____state_8[2:0]];
  assign concat_8778 = {24'h00_0000, ____state_8};
  assign ugt_8780 = admitted_occupied > 8'h04;
  assign or_reduce_8782 = |admitted_occupied[7:2];
  assign postponed__4 = admitted_slots_tuple_idx_0[3'h4];
  assign ugt_8786 = admitted_occupied > 8'h02;
  assign postponed__3 = admitted_slots_tuple_idx_0[3'h3];
  assign eligible_4 = ~(~ugt_8780 | postponed__4);
  assign unexpand_for_next_value_1354_0_case_0_case_5_case_0 = 2'h0;
  assign or_reduce_8790 = |admitted_occupied[7:1];
  assign postponed__2 = admitted_slots_tuple_idx_0[3'h2];
  assign eligible_3 = ~(~or_reduce_8782 | postponed__3);
  assign postponed__1 = admitted_slots_tuple_idx_0[3'h1];
  assign eligible_2 = ~(~ugt_8786 | postponed__2);
  assign compacted_4_tup1_tup0_tup0 = 8'h00;
  assign eligible_1 = ~(~or_reduce_8790 | postponed__1);
  assign eq_8801 = admitted_occupied == compacted_4_tup1_tup0_tup0;
  assign postponed = admitted_slots_tuple_idx_0[3'h0];
  assign sel_8810 = accepted ? phenom_data_cell__req_select[95:0] : ____state_7_tuple_element_1_tuple_element_1[____state_8 > 8'h04 ? 3'h4 : ____state_8[2:0]];
  assign selected = {5'h00, eligible_1 ? 3'h1 : (eligible_2 ? 3'h2 : (eligible_3 ? 3'h3 : {eligible_4, unexpand_for_next_value_1354_0_case_0_case_5_case_0}))} & {8{eq_8801 | postponed}};
  assign bit_slice_8813 = selected[2:0];
  assign selected_slot_tuple_idx_1_tuple_idx_1 = admitted_slots_tuple_idx_1_tuple_idx_1[bit_slice_8813 > 3'h4 ? 3'h4 : bit_slice_8813];
  assign Xls_clause_1_Source_1 = selected_slot_tuple_idx_1_tuple_idx_1[63:32];
  assign _4__4_source = 32'h0000_0001;
  assign _4__3_source = 32'h0000_0002;
  assign _4__2_source = 32'h0000_0004;
  assign _4__1_source = 32'h0000_0008;
  assign Xls_clause_1_Seed_1 = selected_slot_tuple_idx_1_tuple_idx_1[31:0];
  assign _0__4 = Xls_clause_1_Source_1 == _4__4_source;
  assign _1__1 = Xls_clause_1_Source_1 == _4__3_source;
  assign _2__1 = Xls_clause_1_Source_1 == _4__2_source;
  assign _7 = ____state_3 & Xls_clause_1_Source_1;
  assign or_8827 = _0__4 | _1__1 | _2__1 | Xls_clause_1_Source_1 == _4__1_source;
  assign _8 = _7 == 32'h0000_0000;
  assign _0__5 = ____state_2 + _4__4_source;
  assign and_8831 = Xls_clause_1_Seed_1 == ____state_2 & or_8827 & _8;
  assign sel_8829 = accepted ? frame_header_op : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[____state_8 > 8'h04 ? 3'h4 : ____state_8[2:0]];
  assign _2__2 = Xls_clause_1_Seed_1 == _0__5;
  assign unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0 = 2'h2;
  assign unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 = 2'h1;
  assign selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[bit_slice_8813 > 3'h4 ? 3'h4 : bit_slice_8813];
  assign eq_8847 = ____state_0 == unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0;
  assign eq_8848 = ____state_0 == unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1;
  assign nor_8849 = ~(____state_0[0] | ____state_0[1]);
  assign and_8853 = (_2__2 ? unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 : unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0) & {2{~and_8831}};
  assign and_8854 = _2__2 & or_8827;
  assign _0 = Xls_clause_1_Seed_1 != 32'h0000_0000;
  assign concat_8861 = {eq_8847, eq_8848, nor_8849};
  assign postponed_slot_tup0 = 1'h1;
  assign concat_8873 = {eq_8848, nor_8849};
  assign eligible_0 = ~(eq_8801 | postponed);
  assign invalid_input = received & ~tag_ok;
  assign eq_8846 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h08;
  assign eq_8862 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h07;
  assign eq_8850 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h06;
  assign or_8883 = selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == MAILBOX_CAPACITY | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h04 | selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 == 8'h03;
  assign invalid_repeat = 1'h0;
  assign found = eligible_0 | eligible_1 | eligible_2 | eligible_3 | eligible_4;
  assign dispatchable = found & ~invalid_input;
  assign _14__2 = ____state_6[31:13] ^ ____state_6[18:0];
  assign Xls_clause_1_NewSeen_1 = ____state_3 | Xls_clause_1_Source_1;
  assign priority_sel_8901 = priority_sel_2b_4way({eq_8846, eq_8862, eq_8850, or_8883}, unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0, {~(~____state_0[0] & ~____state_0[1] & _0), invalid_repeat}, unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0, {priority_sel_1b_3way(concat_8861, _0, and_8853[1], ~and_8854, postponed_slot_tup0), ~_0 & concat_8873[0] | and_8853[0] & concat_8873[1]}, unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0);
  assign _12 = Xls_clause_1_NewSeen_1 == 32'h0000_000f;
  assign directive = priority_sel_8901 & {2{dispatchable}};
  assign nand_8884 = ~(and_8831 & _12);
  assign candidate_slots_0_case_cmp = ~dispatchable;
  assign _15__2 = {_14__2[1:0], ____state_6[12:0]} ^ _14__2[18:4];
  assign candidate_occupied_1_case_cmp = ~(candidate_slots_0_case_cmp | directive[0] | directive[1]);
  assign add_8929 = admitted_occupied + 8'hff;
  assign priority_sel_8900 = priority_sel_2b_6way({{3{eq_8846}} & concat_8861, eq_8862 | eq_8850 & (____state_0[0] | ____state_0[1]), ~(~eq_8850 | ____state_0[0] | ____state_0[1]), or_8883}, ____state_0, {invalid_repeat, _0}, ____state_0, unexpand_for_next_value_1354_0_case_0_case_5_case_0, nand_8884 ? unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 : unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0, and_8854 ? unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 : unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0, ____state_0);
  assign failed = invalid_input | directive == unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0;
  assign candidate_occupied = candidate_occupied_1_case_cmp ? add_8929 : admitted_occupied;
  assign candidate_phase_squeezed = dispatchable ? priority_sel_8900 : ____state_0;
  assign Xls_clause_1_NextRandom_1__3 = _14__2[18:2] ^ {_14__2[13:2], _15__2[14:10]};
  assign Xls_clause_1_NextRandom_1__2 = _15__2[14:5] ^ _15__2[9:0];
  assign Xls_clause_1_NextRandom_1__1 = _15__2[4:0];
  assign phase_changed = candidate_phase_squeezed != ____state_0;
  assign reserve__1 = ~failed & ~received & ~(____state_10 & ~received) & candidate_occupied < MAILBOX_CAPACITY;
  assign reserve = ~(____state_10 | ____state_8 > 8'h04);
  assign and_8917 = ~(____state_11 | ____state_9 | candidate_slots_0_case_cmp) & eq_8846;
  assign Xls_clause_1_NextRandom_1 = {Xls_clause_1_NextRandom_1__3, Xls_clause_1_NextRandom_1__2, Xls_clause_1_NextRandom_1__1};
  assign and_8922 = and_8917 & eq_8848;
  assign _18 = Xls_clause_1_NextRandom_1 < ____state_4;
  assign nor_8925 = ~(____state_11 | ____state_9 | phase_changed);
  assign eq_8926 = priority_sel_8901 == unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1;
  assign nor_8927 = ~(____state_11 | ____state_9 | ~phase_changed);
  assign __phenom_data_cell__admit_buf = ~____state_11 & ~____state_9 & reserve__1 | ~____state_11 & ____state_9 & reserve;
  assign __phenom_data_cell__admit_not_has_been_sent = ~__phenom_data_cell__admit_has_been_sent_reg;
  assign phenom_data_cell__admit_valid_inv = ~__phenom_data_cell__admit_valid_reg;
  assign __phenom_data_cell__east_vld_buf = ~(____state_11 | ~____state_9 | ~____state_0[1]);
  assign __phenom_data_cell__north_not_has_been_sent = ~__phenom_data_cell__north_has_been_sent_reg;
  assign phenom_data_cell__north_valid_inv = ~__phenom_data_cell__north_valid_reg;
  assign __phenom_data_cell__east_not_has_been_sent = ~__phenom_data_cell__east_has_been_sent_reg;
  assign phenom_data_cell__east_valid_inv = ~__phenom_data_cell__east_valid_reg;
  assign __phenom_data_cell__west_not_has_been_sent = ~__phenom_data_cell__west_has_been_sent_reg;
  assign phenom_data_cell__west_valid_inv = ~__phenom_data_cell__west_valid_reg;
  assign __phenom_data_cell__south_not_has_been_sent = ~__phenom_data_cell__south_has_been_sent_reg;
  assign phenom_data_cell__south_valid_inv = ~__phenom_data_cell__south_valid_reg;
  assign and_8930 = and_8917 & eq_8847;
  assign and_8931 = ~(____state_11 | ____state_9 | candidate_slots_0_case_cmp) & eq_8850 & nor_8849;
  assign nor_8932 = ~(____state_11 | ____state_9);
  assign candidate_occupied_0_case_cmp = ~candidate_occupied_1_case_cmp;
  assign and_8935 = and_8922 & ~nand_8884;
  assign Xls_clause_1_Event_1_0_case_cmp = ~_18;
  assign and_8937 = nor_8925 & dispatchable;
  assign transition_slots_predicate_piece_0 = ~(directive[0] | directive[1]);
  assign or_8940 = directive[0] | directive[1];
  assign and_8941 = nor_8927 & dispatchable;
  assign __phenom_data_cell__admit_valid_and_not_has_been_sent = __phenom_data_cell__admit_buf & __phenom_data_cell__admit_not_has_been_sent;
  assign phenom_data_cell__admit_valid_load_en = phenom_data_cell__admit_rdy | phenom_data_cell__admit_valid_inv;
  assign __phenom_data_cell__north_valid_and_not_has_been_sent = __phenom_data_cell__east_vld_buf & __phenom_data_cell__north_not_has_been_sent;
  assign phenom_data_cell__north_valid_load_en = phenom_data_cell__north_rdy | phenom_data_cell__north_valid_inv;
  assign __phenom_data_cell__east_valid_and_not_has_been_sent = __phenom_data_cell__east_vld_buf & __phenom_data_cell__east_not_has_been_sent;
  assign phenom_data_cell__east_valid_load_en = phenom_data_cell__east_rdy | phenom_data_cell__east_valid_inv;
  assign __phenom_data_cell__west_valid_and_not_has_been_sent = __phenom_data_cell__east_vld_buf & __phenom_data_cell__west_not_has_been_sent;
  assign phenom_data_cell__west_valid_load_en = phenom_data_cell__west_rdy | phenom_data_cell__west_valid_inv;
  assign __phenom_data_cell__south_valid_and_not_has_been_sent = __phenom_data_cell__east_vld_buf & __phenom_data_cell__south_not_has_been_sent;
  assign phenom_data_cell__south_valid_load_en = phenom_data_cell__south_rdy | phenom_data_cell__south_valid_inv;
  assign and_8945 = and_8922 & and_8831;
  assign and_8946 = and_8930 & and_8854;
  assign and_8947 = and_8931 & _0;
  assign and_8948 = nor_8932 & candidate_occupied_0_case_cmp;
  assign and_8949 = nor_8932 & candidate_occupied_1_case_cmp;
  assign nor_8950 = ~(____state_11 | ~____state_9);
  assign and_8951 = and_8917 & nor_8849;
  assign and_8952 = and_8931 & ~_0;
  assign and_8953 = and_8922 & nand_8884;
  assign and_8954 = and_8930 & ~and_8854;
  assign and_8955 = and_8935 & Xls_clause_1_Event_1_0_case_cmp;
  assign and_8956 = and_8935 & _18;
  assign and_8957 = nor_8925 & candidate_slots_0_case_cmp;
  assign and_8958 = and_8937 & transition_slots_predicate_piece_0;
  assign and_8959 = and_8937 & eq_8926;
  assign and_8960 = and_8937 & ~eq_8926 & or_8940;
  assign and_8961 = nor_8927 & candidate_slots_0_case_cmp;
  assign and_8962 = and_8941 & transition_slots_predicate_piece_0;
  assign and_8963 = and_8941 & eq_8926 & or_8940;
  assign and_8964 = and_8941 & ~eq_8926 & or_8940;
  assign phenom_data_cell__admit_not_pred = ~__phenom_data_cell__admit_buf;
  assign phenom_data_cell__admit_load_en = __phenom_data_cell__admit_valid_and_not_has_been_sent & phenom_data_cell__admit_valid_load_en;
  assign phenom_data_cell__east_not_pred = ~__phenom_data_cell__east_vld_buf;
  assign phenom_data_cell__north_load_en = __phenom_data_cell__north_valid_and_not_has_been_sent & phenom_data_cell__north_valid_load_en;
  assign phenom_data_cell__east_load_en = __phenom_data_cell__east_valid_and_not_has_been_sent & phenom_data_cell__east_valid_load_en;
  assign phenom_data_cell__west_load_en = __phenom_data_cell__west_valid_and_not_has_been_sent & phenom_data_cell__west_valid_load_en;
  assign phenom_data_cell__south_load_en = __phenom_data_cell__south_valid_and_not_has_been_sent & phenom_data_cell__south_valid_load_en;
  assign ____state_3__next_value_predicates = {and_8945, and_8946};
  assign ____state_6__next_value_predicates = {and_8947, and_8935};
  assign ____state_8__next_value_predicates = {and_8948, and_8949};
  assign ____state_10__next_value_predicates = {nor_8932, nor_8950};
  assign ____state_0__next_value_predicates = {and_8951, and_8952, and_8947, and_8935, and_8953, and_8954, and_8946};
  assign ____state_5__next_value_predicates = {and_8946, and_8955, and_8956};
  assign ____state_7_tuple_element_0__next_value_predicates = {nor_8927, and_8957, and_8958, and_8959, and_8960};
  assign ____state_7_tuple_element_1_tuple_element_1__next_value_predicates = {and_8957, and_8958, and_8959, and_8960, and_8961, and_8962, and_8963, and_8964};
  assign one_hot_8997 = {____state_3__next_value_predicates[1:0] == 2'h0, ____state_3__next_value_predicates[1] && !____state_3__next_value_predicates[0], ____state_3__next_value_predicates[0]};
  assign one_hot_8998 = {____state_6__next_value_predicates[1:0] == 2'h0, ____state_6__next_value_predicates[1] && !____state_6__next_value_predicates[0], ____state_6__next_value_predicates[0]};
  assign one_hot_8999 = {____state_8__next_value_predicates[1:0] == 2'h0, ____state_8__next_value_predicates[1] && !____state_8__next_value_predicates[0], ____state_8__next_value_predicates[0]};
  assign one_hot_9000 = {____state_10__next_value_predicates[1:0] == 2'h0, ____state_10__next_value_predicates[1] && !____state_10__next_value_predicates[0], ____state_10__next_value_predicates[0]};
  assign one_hot_9001 = {____state_0__next_value_predicates[6:0] == 7'h00, ____state_0__next_value_predicates[6] && ____state_0__next_value_predicates[5:0] == 6'h00, ____state_0__next_value_predicates[5] && ____state_0__next_value_predicates[4:0] == 5'h00, ____state_0__next_value_predicates[4] && ____state_0__next_value_predicates[3:0] == 4'h0, ____state_0__next_value_predicates[3] && ____state_0__next_value_predicates[2:0] == 3'h0, ____state_0__next_value_predicates[2] && ____state_0__next_value_predicates[1:0] == 2'h0, ____state_0__next_value_predicates[1] && !____state_0__next_value_predicates[0], ____state_0__next_value_predicates[0]};
  assign one_hot_9002 = {____state_5__next_value_predicates[2:0] == 3'h0, ____state_5__next_value_predicates[2] && ____state_5__next_value_predicates[1:0] == 2'h0, ____state_5__next_value_predicates[1] && !____state_5__next_value_predicates[0], ____state_5__next_value_predicates[0]};
  assign one_hot_9003 = {____state_7_tuple_element_0__next_value_predicates[4:0] == 5'h00, ____state_7_tuple_element_0__next_value_predicates[4] && ____state_7_tuple_element_0__next_value_predicates[3:0] == 4'h0, ____state_7_tuple_element_0__next_value_predicates[3] && ____state_7_tuple_element_0__next_value_predicates[2:0] == 3'h0, ____state_7_tuple_element_0__next_value_predicates[2] && ____state_7_tuple_element_0__next_value_predicates[1:0] == 2'h0, ____state_7_tuple_element_0__next_value_predicates[1] && !____state_7_tuple_element_0__next_value_predicates[0], ____state_7_tuple_element_0__next_value_predicates[0]};
  assign one_hot_9004 = {____state_7_tuple_element_1_tuple_element_1__next_value_predicates[7:0] == 8'h00, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[7] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[6:0] == 7'h00, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[6] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[5:0] == 6'h00, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[5] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[4:0] == 5'h00, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[4] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[3:0] == 4'h0, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[3] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[2:0] == 3'h0, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[2] && ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[1:0] == 2'h0, ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[1] && !____state_7_tuple_element_1_tuple_element_1__next_value_predicates[0], ____state_7_tuple_element_1_tuple_element_1__next_value_predicates[0]};
  assign array_index_8981 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h1];
  assign array_index_8983 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h2];
  assign array_index_8985 = admitted_slots_tuple_idx_1_tuple_idx_1[3'h3];
  assign array_index_8989 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h1];
  assign array_index_8991 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h2];
  assign array_index_8993 = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h3];
  assign p0_all_active_outputs_ready = (phenom_data_cell__admit_not_pred | phenom_data_cell__admit_load_en | __phenom_data_cell__admit_has_been_sent_reg) & (phenom_data_cell__east_not_pred | phenom_data_cell__north_load_en | __phenom_data_cell__north_has_been_sent_reg) & (phenom_data_cell__east_not_pred | phenom_data_cell__east_load_en | __phenom_data_cell__east_has_been_sent_reg) & (phenom_data_cell__east_not_pred | phenom_data_cell__west_load_en | __phenom_data_cell__west_has_been_sent_reg) & (phenom_data_cell__east_not_pred | phenom_data_cell__south_load_en | __phenom_data_cell__south_has_been_sent_reg);
  assign ne_9011 = bit_slice_8813 != 3'h0;
  assign or_reduce_9013 = |selected[7:1];
  assign ugt_9015 = bit_slice_8813 > 3'h2;
  assign one_hot_9575 = {concat_8873[1:0] == 2'h0, concat_8873[1] && !concat_8873[0], concat_8873[0]};
  assign phenom_data_cell__req_valid_inv = ~__phenom_data_cell__req_valid_reg;
  assign and_9195 = and_8946 & p0_all_active_outputs_ready;
  assign and_9204 = and_8947 & p0_all_active_outputs_ready;
  assign and_9205 = and_8935 & p0_all_active_outputs_ready;
  assign admission_pending = ~(~____state_10 | received);
  assign and_9250 = and_8957 & p0_all_active_outputs_ready;
  assign and_9251 = and_8958 & p0_all_active_outputs_ready;
  assign and_9252 = and_8959 & p0_all_active_outputs_ready;
  assign and_9253 = and_8960 & p0_all_active_outputs_ready;
  assign concat_9073 = {24'h00_0000, selected};
  assign compacted_0_tup0 = ne_9011 ? postponed : or_reduce_8790 & postponed__1;
  assign compacted_1_tup0 = or_reduce_9013 ? postponed__1 : ugt_8786 & postponed__2;
  assign compacted_2_tup0 = ugt_9015 ? postponed__2 : or_reduce_8782 & postponed__3;
  assign compacted_3_tup0 = selected[2] ? postponed__3 : ugt_8780 & postponed__4;
  assign compacted_0_tup1_tup1 = ne_9011 ? admitted_slots_tuple_idx_1_tuple_idx_1[3'h0] : array_index_8981 & {96{or_reduce_8790}};
  assign compacted_1_tup1_tup1 = or_reduce_9013 ? array_index_8981 : array_index_8983 & {96{ugt_8786}};
  assign compacted_2_tup1_tup1 = ugt_9015 ? array_index_8983 : array_index_8985 & {96{or_reduce_8782}};
  assign compacted_3_tup1_tup1 = selected[2] ? array_index_8985 : admitted_slots_tuple_idx_1_tuple_idx_1[3'h4] & {96{ugt_8780}};
  assign compacted_4_tup1_tup1 = 96'h0000_0000_0000_0000_0000_0000;
  assign compacted_0_tup1_tup0_tup3 = ne_9011 ? admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h0] : array_index_8989 & {8{or_reduce_8790}};
  assign compacted_1_tup1_tup0_tup3 = or_reduce_9013 ? array_index_8989 : array_index_8991 & {8{ugt_8786}};
  assign compacted_2_tup1_tup0_tup3 = ugt_9015 ? array_index_8991 : array_index_8993 & {8{or_reduce_8782}};
  assign compacted_3_tup1_tup0_tup3 = selected[2] ? array_index_8993 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3'h4] & {8{ugt_8780}};
  assign leading_bits___state_5 = 31'h0000_0000;
  assign phenom_data_cell__req_valid_load_en = p0_all_active_outputs_ready & nor_8739 | phenom_data_cell__req_valid_inv;
  assign ____state_3__at_most_one_next_value = and_8945 == one_hot_8997[1] & and_8946 == one_hot_8997[0];
  assign ____state_6__at_most_one_next_value = and_8947 == one_hot_8998[1] & and_8935 == one_hot_8998[0];
  assign ____state_8__at_most_one_next_value = and_8948 == one_hot_8999[1] & and_8949 == one_hot_8999[0];
  assign ____state_10__at_most_one_next_value = nor_8932 == one_hot_9000[1] & nor_8950 == one_hot_9000[0];
  assign ____state_0__at_most_one_next_value = and_8951 == one_hot_9001[6] & and_8952 == one_hot_9001[5] & and_8947 == one_hot_9001[4] & and_8935 == one_hot_9001[3] & and_8953 == one_hot_9001[2] & and_8954 == one_hot_9001[1] & and_8946 == one_hot_9001[0];
  assign ____state_5__at_most_one_next_value = and_8946 == one_hot_9002[2] & and_8955 == one_hot_9002[1] & and_8956 == one_hot_9002[0];
  assign ____state_7_tuple_element_0__at_most_one_next_value = nor_8927 == one_hot_9003[4] & and_8957 == one_hot_9003[3] & and_8958 == one_hot_9003[2] & and_8959 == one_hot_9003[1] & and_8960 == one_hot_9003[0];
  assign ____state_7_tuple_element_1_tuple_element_1__at_most_one_next_value = and_8957 == one_hot_9004[7] & and_8958 == one_hot_9004[6] & and_8959 == one_hot_9004[5] & and_8960 == one_hot_9004[4] & and_8961 == one_hot_9004[3] & and_8962 == one_hot_9004[2] & and_8963 == one_hot_9004[1] & and_8964 == one_hot_9004[0];
  assign concat_9197 = {and_8945 & p0_all_active_outputs_ready, and_9195};
  assign concat_9207 = {and_9204, and_9205};
  assign concat_9214 = {and_8948 & p0_all_active_outputs_ready, and_8949 & p0_all_active_outputs_ready};
  assign concat_9224 = {nor_8932 & p0_all_active_outputs_ready, nor_8950 & p0_all_active_outputs_ready};
  assign concat_9237 = {and_8951 & p0_all_active_outputs_ready, and_8952 & p0_all_active_outputs_ready, and_9204, and_9205, and_8953 & p0_all_active_outputs_ready, and_8954 & p0_all_active_outputs_ready, and_9195};
  assign concat_9245 = {and_9195, and_8955 & p0_all_active_outputs_ready, and_8956 & p0_all_active_outputs_ready};
  assign concat_9255 = {nor_8927 & p0_all_active_outputs_ready, and_9250, and_9251, and_9252, and_9253};
  assign compacted_slots_tuple_idx_0[0] = compacted_0_tup0;
  assign compacted_slots_tuple_idx_0[1] = compacted_1_tup0;
  assign compacted_slots_tuple_idx_0[2] = compacted_2_tup0;
  assign compacted_slots_tuple_idx_0[3] = compacted_3_tup0;
  assign compacted_slots_tuple_idx_0[4] = invalid_repeat;
  assign concat_9268 = {and_9250, and_9251, and_9252, and_9253, and_8961 & p0_all_active_outputs_ready, and_8962 & p0_all_active_outputs_ready, and_8963 & p0_all_active_outputs_ready, and_8964 & p0_all_active_outputs_ready};
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
  assign __phenom_data_cell__admit_valid_and_all_active_outputs_ready = __phenom_data_cell__admit_buf & p0_all_active_outputs_ready;
  assign __phenom_data_cell__admit_valid_and_ready_txfr = __phenom_data_cell__admit_valid_and_not_has_been_sent & phenom_data_cell__admit_load_en;
  assign __phenom_data_cell__east_valid_and_all_active_outputs_ready = __phenom_data_cell__east_vld_buf & p0_all_active_outputs_ready;
  assign __phenom_data_cell__north_valid_and_ready_txfr = __phenom_data_cell__north_valid_and_not_has_been_sent & phenom_data_cell__north_load_en;
  assign __phenom_data_cell__east_valid_and_ready_txfr = __phenom_data_cell__east_valid_and_not_has_been_sent & phenom_data_cell__east_load_en;
  assign __phenom_data_cell__west_valid_and_ready_txfr = __phenom_data_cell__west_valid_and_not_has_been_sent & phenom_data_cell__west_load_en;
  assign __phenom_data_cell__south_valid_and_ready_txfr = __phenom_data_cell__south_valid_and_not_has_been_sent & phenom_data_cell__south_load_en;
  assign phenom_data_cell__req_load_en = phenom_data_cell__req_vld & phenom_data_cell__req_valid_load_en;
  assign or_9610 = ~p0_all_active_outputs_ready | ____state_3__at_most_one_next_value | reset;
  assign or_9612 = ~p0_all_active_outputs_ready | ____state_6__at_most_one_next_value | reset;
  assign or_9614 = ~p0_all_active_outputs_ready | ____state_8__at_most_one_next_value | reset;
  assign or_9616 = ~p0_all_active_outputs_ready | ____state_10__at_most_one_next_value | reset;
  assign or_9618 = ~p0_all_active_outputs_ready | ____state_0__at_most_one_next_value | reset;
  assign or_9620 = ~p0_all_active_outputs_ready | ____state_5__at_most_one_next_value | reset;
  assign or_9622 = ~p0_all_active_outputs_ready | ____state_7_tuple_element_0__at_most_one_next_value | reset;
  assign or_9624 = ~p0_all_active_outputs_ready | ____state_7_tuple_element_1_tuple_element_1__at_most_one_next_value | reset;
  assign and_9291 = and_8946 & p0_all_active_outputs_ready;
  assign one_hot_sel_9198 = Xls_clause_1_Source_1 & {32{concat_9197[0]}} | Xls_clause_1_NewSeen_1 & {32{concat_9197[1]}};
  assign and_9294 = (and_8945 | and_8946) & p0_all_active_outputs_ready;
  assign and_9296 = and_8947 & p0_all_active_outputs_ready;
  assign one_hot_sel_9208 = Xls_clause_1_NextRandom_1 & {32{concat_9207[0]}} | Xls_clause_1_Seed_1 & {32{concat_9207[1]}};
  assign and_9299 = (and_8947 | and_8935) & p0_all_active_outputs_ready;
  assign one_hot_sel_9215 = add_8929 & {8{concat_9214[0]}} | admitted_occupied & {8{concat_9214[1]}};
  assign and_9302 = (and_8948 | and_8949) & p0_all_active_outputs_ready;
  assign and_9120 = ~____state_9 & dispatchable & phase_changed & ~failed;
  assign and_9304 = ~____state_11 & p0_all_active_outputs_ready;
  assign one_hot_sel_9225 = (____state_10 | ____state_8 < MAILBOX_CAPACITY) & concat_9224[0] | (admission_pending | reserve__1) & concat_9224[1];
  assign and_9307 = (nor_8932 | nor_8950) & p0_all_active_outputs_ready;
  assign or_9118 = ____state_11 | (____state_9 ? ____state_11 : failed);
  assign one_hot_sel_9238 = unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 & {2{concat_9237[0]}} | unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0 & {2{concat_9237[1]}} | unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 & {2{concat_9237[2]}} | unexpand_for_next_value_1354_0_case_0_case_5_case_1_case_0 & {2{concat_9237[3]}} | unexpand_for_next_value_1354_0_case_0_case_3_case_0_case_1 & {2{concat_9237[4]}} | unexpand_for_next_value_1354_0_case_0_case_5_case_0 & {2{concat_9237[5]}} | unexpand_for_next_value_1354_0_case_0_case_5_case_0 & {2{concat_9237[6]}};
  assign and_9311 = (and_8951 | and_8952 | and_8947 | and_8935 | and_8953 | and_8954 | and_8946) & p0_all_active_outputs_ready;
  assign one_hot_sel_9246 = postponed_slot_tup0 & concat_9245[0] | invalid_repeat & concat_9245[1] | invalid_repeat & concat_9245[2];
  assign and_9314 = (and_8946 | and_8955 | and_8956) & p0_all_active_outputs_ready;
  assign one_hot_sel_9256[0] = admitted_slots_tuple_idx_0[0] & concat_9255[0] | postponed_slots_tuple_idx_0[0] & concat_9255[1] | compacted_slots_tuple_idx_0[0] & concat_9255[2] | admitted_slots_tuple_idx_0[0] & concat_9255[3] | unblocked_slots_tuple_idx_0[0] & concat_9255[4];
  assign one_hot_sel_9256[1] = admitted_slots_tuple_idx_0[1] & concat_9255[0] | postponed_slots_tuple_idx_0[1] & concat_9255[1] | compacted_slots_tuple_idx_0[1] & concat_9255[2] | admitted_slots_tuple_idx_0[1] & concat_9255[3] | unblocked_slots_tuple_idx_0[1] & concat_9255[4];
  assign one_hot_sel_9256[2] = admitted_slots_tuple_idx_0[2] & concat_9255[0] | postponed_slots_tuple_idx_0[2] & concat_9255[1] | compacted_slots_tuple_idx_0[2] & concat_9255[2] | admitted_slots_tuple_idx_0[2] & concat_9255[3] | unblocked_slots_tuple_idx_0[2] & concat_9255[4];
  assign one_hot_sel_9256[3] = admitted_slots_tuple_idx_0[3] & concat_9255[0] | postponed_slots_tuple_idx_0[3] & concat_9255[1] | compacted_slots_tuple_idx_0[3] & concat_9255[2] | admitted_slots_tuple_idx_0[3] & concat_9255[3] | unblocked_slots_tuple_idx_0[3] & concat_9255[4];
  assign one_hot_sel_9256[4] = admitted_slots_tuple_idx_0[4] & concat_9255[0] | postponed_slots_tuple_idx_0[4] & concat_9255[1] | compacted_slots_tuple_idx_0[4] & concat_9255[2] | admitted_slots_tuple_idx_0[4] & concat_9255[3] | unblocked_slots_tuple_idx_0[4] & concat_9255[4];
  assign and_9317 = (nor_8927 | and_8957 | and_8958 | and_8959 | and_8960) & p0_all_active_outputs_ready;
  assign one_hot_sel_9269[0] = admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[0] & {96{concat_9268[7]}};
  assign one_hot_sel_9269[1] = admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[1] & {96{concat_9268[7]}};
  assign one_hot_sel_9269[2] = admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[2] & {96{concat_9268[7]}};
  assign one_hot_sel_9269[3] = admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[3] & {96{concat_9268[7]}};
  assign one_hot_sel_9269[4] = admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_1[4] & {96{concat_9268[7]}};
  assign and_9320 = (and_8957 | and_8958 | and_8959 | and_8960 | and_8961 | and_8962 | and_8963 | and_8964) & p0_all_active_outputs_ready;
  assign one_hot_sel_9282[0] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[0] & {8{concat_9268[7]}};
  assign one_hot_sel_9282[1] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[1] & {8{concat_9268[7]}};
  assign one_hot_sel_9282[2] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[2] & {8{concat_9268[7]}};
  assign one_hot_sel_9282[3] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[3] & {8{concat_9268[7]}};
  assign one_hot_sel_9282[4] = admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[0]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[1]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[2]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[3]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[4]}} | postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[5]}} | compacted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[6]}} | admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[4] & {8{concat_9268[7]}};
  assign __phenom_data_cell__admit_not_stage_load = ~__phenom_data_cell__admit_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__admit_has_been_sent_reg_load_en = __phenom_data_cell__admit_valid_and_ready_txfr | __phenom_data_cell__admit_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__east_not_stage_load = ~__phenom_data_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__north_has_been_sent_reg_load_en = __phenom_data_cell__north_valid_and_ready_txfr | __phenom_data_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__east_has_been_sent_reg_load_en = __phenom_data_cell__east_valid_and_ready_txfr | __phenom_data_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__west_has_been_sent_reg_load_en = __phenom_data_cell__west_valid_and_ready_txfr | __phenom_data_cell__east_valid_and_all_active_outputs_ready;
  assign __phenom_data_cell__south_has_been_sent_reg_load_en = __phenom_data_cell__south_valid_and_ready_txfr | __phenom_data_cell__east_valid_and_all_active_outputs_ready;
  assign effects_north = {literal_8701, {leading_bits___state_5, ____state_5, _4__1_source, ____state_2}};
  assign effects_east = {literal_8701, {leading_bits___state_5, ____state_5, _4__2_source, ____state_2}};
  assign effects_west = {literal_8701, {leading_bits___state_5, ____state_5, _4__3_source, ____state_2}};
  assign effects_south = {literal_8701, {leading_bits___state_5, ____state_5, _4__4_source, ____state_2}};
  assign or_9628 = ~p0_all_active_outputs_ready | concat_8873 == one_hot_9575[1:0] | reset;
  always @ (posedge clk) begin
    if (reset) begin
      ____state_10 <= 1'h0;
      ____state_11 <= 1'h0;
      ____state_9 <= 1'h1;
      ____state_7_tuple_element_0[0] <= ____state_7_tuple_element_0_init[0];
      ____state_7_tuple_element_0[1] <= ____state_7_tuple_element_0_init[1];
      ____state_7_tuple_element_0[2] <= ____state_7_tuple_element_0_init[2];
      ____state_7_tuple_element_0[3] <= ____state_7_tuple_element_0_init[3];
      ____state_7_tuple_element_0[4] <= ____state_7_tuple_element_0_init[4];
      ____state_8 <= 8'h00;
      ____state_7_tuple_element_1_tuple_element_1[0] <= ____state_7_tuple_element_1_tuple_element_1_init[0];
      ____state_7_tuple_element_1_tuple_element_1[1] <= ____state_7_tuple_element_1_tuple_element_1_init[1];
      ____state_7_tuple_element_1_tuple_element_1[2] <= ____state_7_tuple_element_1_tuple_element_1_init[2];
      ____state_7_tuple_element_1_tuple_element_1[3] <= ____state_7_tuple_element_1_tuple_element_1_init[3];
      ____state_7_tuple_element_1_tuple_element_1[4] <= ____state_7_tuple_element_1_tuple_element_1_init[4];
      ____state_3 <= 32'h0000_0000;
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[0] <= ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[0];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[1] <= ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[1];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[2] <= ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[2];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[3] <= ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[3];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[4] <= ____state_7_tuple_element_1_tuple_element_0_tuple_element_3_init[4];
      ____state_2 <= 32'h0000_0000;
      ____state_6 <= 32'h0000_0000;
      ____state_0 <= 2'h0;
      ____state_4 <= 32'h0000_0000;
      ____state_5 <= 1'h0;
      __phenom_data_cell__admit_has_been_sent_reg <= 1'h0;
      __phenom_data_cell__north_has_been_sent_reg <= 1'h0;
      __phenom_data_cell__east_has_been_sent_reg <= 1'h0;
      __phenom_data_cell__west_has_been_sent_reg <= 1'h0;
      __phenom_data_cell__south_has_been_sent_reg <= 1'h0;
      __phenom_data_cell__req_reg <= __phenom_data_cell__req_reg_init;
      __phenom_data_cell__req_valid_reg <= 1'h0;
      __phenom_data_cell__admit_reg <= 1'h0;
      __phenom_data_cell__admit_valid_reg <= 1'h0;
      __phenom_data_cell__north_reg <= __phenom_data_cell__north_reg_init;
      __phenom_data_cell__north_valid_reg <= 1'h0;
      __phenom_data_cell__east_reg <= __phenom_data_cell__east_reg_init;
      __phenom_data_cell__east_valid_reg <= 1'h0;
      __phenom_data_cell__west_reg <= __phenom_data_cell__west_reg_init;
      __phenom_data_cell__west_valid_reg <= 1'h0;
      __phenom_data_cell__south_reg <= __phenom_data_cell__south_reg_init;
      __phenom_data_cell__south_valid_reg <= 1'h0;
    end else begin
      ____state_10 <= and_9307 ? one_hot_sel_9225 : ____state_10;
      ____state_11 <= p0_all_active_outputs_ready ? or_9118 : ____state_11;
      ____state_9 <= and_9304 ? and_9120 : ____state_9;
      ____state_7_tuple_element_0[0] <= and_9317 ? one_hot_sel_9256[0] : ____state_7_tuple_element_0[0];
      ____state_7_tuple_element_0[1] <= and_9317 ? one_hot_sel_9256[1] : ____state_7_tuple_element_0[1];
      ____state_7_tuple_element_0[2] <= and_9317 ? one_hot_sel_9256[2] : ____state_7_tuple_element_0[2];
      ____state_7_tuple_element_0[3] <= and_9317 ? one_hot_sel_9256[3] : ____state_7_tuple_element_0[3];
      ____state_7_tuple_element_0[4] <= and_9317 ? one_hot_sel_9256[4] : ____state_7_tuple_element_0[4];
      ____state_8 <= and_9302 ? one_hot_sel_9215 : ____state_8;
      ____state_7_tuple_element_1_tuple_element_1[0] <= and_9320 ? one_hot_sel_9269[0] : ____state_7_tuple_element_1_tuple_element_1[0];
      ____state_7_tuple_element_1_tuple_element_1[1] <= and_9320 ? one_hot_sel_9269[1] : ____state_7_tuple_element_1_tuple_element_1[1];
      ____state_7_tuple_element_1_tuple_element_1[2] <= and_9320 ? one_hot_sel_9269[2] : ____state_7_tuple_element_1_tuple_element_1[2];
      ____state_7_tuple_element_1_tuple_element_1[3] <= and_9320 ? one_hot_sel_9269[3] : ____state_7_tuple_element_1_tuple_element_1[3];
      ____state_7_tuple_element_1_tuple_element_1[4] <= and_9320 ? one_hot_sel_9269[4] : ____state_7_tuple_element_1_tuple_element_1[4];
      ____state_3 <= and_9294 ? one_hot_sel_9198 : ____state_3;
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[0] <= and_9320 ? one_hot_sel_9282[0] : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[0];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[1] <= and_9320 ? one_hot_sel_9282[1] : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[1];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[2] <= and_9320 ? one_hot_sel_9282[2] : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[2];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[3] <= and_9320 ? one_hot_sel_9282[3] : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[3];
      ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[4] <= and_9320 ? one_hot_sel_9282[4] : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[4];
      ____state_2 <= and_9291 ? Xls_clause_1_Seed_1 : ____state_2;
      ____state_6 <= and_9299 ? one_hot_sel_9208 : ____state_6;
      ____state_0 <= and_9311 ? one_hot_sel_9238 : ____state_0;
      ____state_4 <= and_9296 ? Xls_clause_1_Source_1 : ____state_4;
      ____state_5 <= and_9314 ? one_hot_sel_9246 : ____state_5;
      __phenom_data_cell__admit_has_been_sent_reg <= __phenom_data_cell__admit_has_been_sent_reg_load_en ? __phenom_data_cell__admit_not_stage_load : __phenom_data_cell__admit_has_been_sent_reg;
      __phenom_data_cell__north_has_been_sent_reg <= __phenom_data_cell__north_has_been_sent_reg_load_en ? __phenom_data_cell__east_not_stage_load : __phenom_data_cell__north_has_been_sent_reg;
      __phenom_data_cell__east_has_been_sent_reg <= __phenom_data_cell__east_has_been_sent_reg_load_en ? __phenom_data_cell__east_not_stage_load : __phenom_data_cell__east_has_been_sent_reg;
      __phenom_data_cell__west_has_been_sent_reg <= __phenom_data_cell__west_has_been_sent_reg_load_en ? __phenom_data_cell__east_not_stage_load : __phenom_data_cell__west_has_been_sent_reg;
      __phenom_data_cell__south_has_been_sent_reg <= __phenom_data_cell__south_has_been_sent_reg_load_en ? __phenom_data_cell__east_not_stage_load : __phenom_data_cell__south_has_been_sent_reg;
      __phenom_data_cell__req_reg <= phenom_data_cell__req_load_en ? phenom_data_cell__req : __phenom_data_cell__req_reg;
      __phenom_data_cell__req_valid_reg <= phenom_data_cell__req_valid_load_en ? phenom_data_cell__req_vld : __phenom_data_cell__req_valid_reg;
      __phenom_data_cell__admit_reg <= phenom_data_cell__admit_load_en ? __phenom_data_cell__admit_buf : __phenom_data_cell__admit_reg;
      __phenom_data_cell__admit_valid_reg <= phenom_data_cell__admit_valid_load_en ? __phenom_data_cell__admit_valid_and_not_has_been_sent : __phenom_data_cell__admit_valid_reg;
      __phenom_data_cell__north_reg <= phenom_data_cell__north_load_en ? effects_north : __phenom_data_cell__north_reg;
      __phenom_data_cell__north_valid_reg <= phenom_data_cell__north_valid_load_en ? __phenom_data_cell__north_valid_and_not_has_been_sent : __phenom_data_cell__north_valid_reg;
      __phenom_data_cell__east_reg <= phenom_data_cell__east_load_en ? effects_east : __phenom_data_cell__east_reg;
      __phenom_data_cell__east_valid_reg <= phenom_data_cell__east_valid_load_en ? __phenom_data_cell__east_valid_and_not_has_been_sent : __phenom_data_cell__east_valid_reg;
      __phenom_data_cell__west_reg <= phenom_data_cell__west_load_en ? effects_west : __phenom_data_cell__west_reg;
      __phenom_data_cell__west_valid_reg <= phenom_data_cell__west_valid_load_en ? __phenom_data_cell__west_valid_and_not_has_been_sent : __phenom_data_cell__west_valid_reg;
      __phenom_data_cell__south_reg <= phenom_data_cell__south_load_en ? effects_south : __phenom_data_cell__south_reg;
      __phenom_data_cell__south_valid_reg <= phenom_data_cell__south_valid_load_en ? __phenom_data_cell__south_valid_and_not_has_been_sent : __phenom_data_cell__south_valid_reg;
    end
  end
  assign phenom_data_cell__admit = __phenom_data_cell__admit_reg;
  assign phenom_data_cell__admit_vld = __phenom_data_cell__admit_valid_reg;
  assign phenom_data_cell__east = __phenom_data_cell__east_reg;
  assign phenom_data_cell__east_vld = __phenom_data_cell__east_valid_reg;
  assign phenom_data_cell__north = __phenom_data_cell__north_reg;
  assign phenom_data_cell__north_vld = __phenom_data_cell__north_valid_reg;
  assign phenom_data_cell__req_rdy = phenom_data_cell__req_load_en;
  assign phenom_data_cell__south = __phenom_data_cell__south_reg;
  assign phenom_data_cell__south_vld = __phenom_data_cell__south_valid_reg;
  assign phenom_data_cell__west = __phenom_data_cell__west_reg;
  assign phenom_data_cell__west_vld = __phenom_data_cell__west_valid_reg;
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_0_0
    assign admitted_slots_tuple_idx_0[__i0] = concat_8778 == __i0 ? and_8777 : ____state_7_tuple_element_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_1_0
    assign admitted_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_8778 == __i0 ? sel_8810 : ____state_7_tuple_element_1_tuple_element_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_8778 == __i0 ? sel_8829 : ____state_7_tuple_element_1_tuple_element_0_tuple_element_3[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_0_0
    assign postponed_slots_tuple_idx_0[__i0] = concat_9073 == __i0 ? postponed_slot_tup0 : admitted_slots_tuple_idx_0[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_1_0
    assign postponed_slots_tuple_idx_1_tuple_idx_1[__i0] = concat_9073 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_1 : admitted_slots_tuple_idx_1_tuple_idx_1[__i0];
  end
  for (genvar __i0 = 0; __i0 < 5; __i0 = __i0 + 1) begin : gen__postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3_0
    assign postponed_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0] = concat_9073 == __i0 ? selected_slot_tuple_idx_1_tuple_idx_0_tuple_idx_3 : admitted_slots_tuple_idx_1_tuple_idx_0_tuple_idx_3[__i0];
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
  wire and_9689;
  wire eq_9694;
  wire ne_9678;
  wire and_9695;
  wire or_9692;
  wire [2:0] add_9686;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9681;
  wire popped;
  wire [1:0] sub_9707;
  wire [1:0] add_9709;
  wire [2:0] umod_9687;
  wire [2:0] umod_9682;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9711;
  wire array_update_9718[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9689 = pop_ready & push_valid;
  assign eq_9694 = head == tail;
  assign ne_9678 = head != tail;
  assign and_9695 = eq_9694 & and_9689;
  assign or_9692 = ne_9678 | push_valid;
  assign add_9686 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9681 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9692;
  assign sub_9707 = slots - 2'h1;
  assign add_9709 = slots + 2'h1;
  assign umod_9687 = add_9686 % long_buf_size_lit;
  assign umod_9682 = add_9681 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9687[1:0];
  assign did_push_occur = (can_do_push | and_9689) & push_valid & ~and_9695 & ~is_full_bool;
  assign next_tail_if_pop = umod_9682[1:0];
  assign did_pop_occur = (ne_9678 | and_9689) & pop_ready & ~and_9695;
  assign sel_9711 = pushed ? (popped ? slots : add_9709) : (popped ? sub_9707 : slots);
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
      slots <= sel_9711;
      buf__1[0] <= did_push_occur ? array_update_9718[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9718[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9692;
  assign pop_data = eq_9694 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9718_0
    assign array_update_9718[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9746;
  wire eq_9751;
  wire ne_9735;
  wire and_9752;
  wire or_9749;
  wire [2:0] add_9743;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9738;
  wire popped;
  wire [1:0] sub_9764;
  wire [1:0] add_9766;
  wire [2:0] umod_9744;
  wire [2:0] umod_9739;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9768;
  wire [127:0] array_update_9775[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9746 = pop_ready & push_valid;
  assign eq_9751 = head == tail;
  assign ne_9735 = head != tail;
  assign and_9752 = eq_9751 & and_9746;
  assign or_9749 = ne_9735 | push_valid;
  assign add_9743 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9738 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9749;
  assign sub_9764 = slots - 2'h1;
  assign add_9766 = slots + 2'h1;
  assign umod_9744 = add_9743 % long_buf_size_lit;
  assign umod_9739 = add_9738 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9744[1:0];
  assign did_push_occur = (can_do_push | and_9746) & push_valid & ~and_9752 & ~is_full_bool;
  assign next_tail_if_pop = umod_9739[1:0];
  assign did_pop_occur = (ne_9735 | and_9746) & pop_ready & ~and_9752;
  assign sel_9768 = pushed ? (popped ? slots : add_9766) : (popped ? sub_9764 : slots);
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
      slots <= sel_9768;
      buf__1[0] <= did_push_occur ? array_update_9775[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9775[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9749;
  assign pop_data = eq_9751 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9775_0
    assign array_update_9775[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9803;
  wire eq_9808;
  wire ne_9792;
  wire and_9809;
  wire or_9806;
  wire [2:0] add_9800;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9795;
  wire popped;
  wire [1:0] sub_9821;
  wire [1:0] add_9823;
  wire [2:0] umod_9801;
  wire [2:0] umod_9796;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9825;
  wire [127:0] array_update_9832[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9803 = pop_ready & push_valid;
  assign eq_9808 = head == tail;
  assign ne_9792 = head != tail;
  assign and_9809 = eq_9808 & and_9803;
  assign or_9806 = ne_9792 | push_valid;
  assign add_9800 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9795 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9806;
  assign sub_9821 = slots - 2'h1;
  assign add_9823 = slots + 2'h1;
  assign umod_9801 = add_9800 % long_buf_size_lit;
  assign umod_9796 = add_9795 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9801[1:0];
  assign did_push_occur = (can_do_push | and_9803) & push_valid & ~and_9809 & ~is_full_bool;
  assign next_tail_if_pop = umod_9796[1:0];
  assign did_pop_occur = (ne_9792 | and_9803) & pop_ready & ~and_9809;
  assign sel_9825 = pushed ? (popped ? slots : add_9823) : (popped ? sub_9821 : slots);
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
      slots <= sel_9825;
      buf__1[0] <= did_push_occur ? array_update_9832[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9832[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9806;
  assign pop_data = eq_9808 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9832_0
    assign array_update_9832[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9860;
  wire eq_9865;
  wire ne_9849;
  wire and_9866;
  wire or_9863;
  wire [2:0] add_9857;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9852;
  wire popped;
  wire [1:0] sub_9878;
  wire [1:0] add_9880;
  wire [2:0] umod_9858;
  wire [2:0] umod_9853;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9882;
  wire [127:0] array_update_9889[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9860 = pop_ready & push_valid;
  assign eq_9865 = head == tail;
  assign ne_9849 = head != tail;
  assign and_9866 = eq_9865 & and_9860;
  assign or_9863 = ne_9849 | push_valid;
  assign add_9857 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9852 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9863;
  assign sub_9878 = slots - 2'h1;
  assign add_9880 = slots + 2'h1;
  assign umod_9858 = add_9857 % long_buf_size_lit;
  assign umod_9853 = add_9852 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9858[1:0];
  assign did_push_occur = (can_do_push | and_9860) & push_valid & ~and_9866 & ~is_full_bool;
  assign next_tail_if_pop = umod_9853[1:0];
  assign did_pop_occur = (ne_9849 | and_9860) & pop_ready & ~and_9866;
  assign sel_9882 = pushed ? (popped ? slots : add_9880) : (popped ? sub_9878 : slots);
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
      slots <= sel_9882;
      buf__1[0] <= did_push_occur ? array_update_9889[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9889[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9863;
  assign pop_data = eq_9865 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9889_0
    assign array_update_9889[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9917;
  wire eq_9922;
  wire ne_9906;
  wire and_9923;
  wire or_9920;
  wire [2:0] add_9914;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9909;
  wire popped;
  wire [1:0] sub_9935;
  wire [1:0] add_9937;
  wire [2:0] umod_9915;
  wire [2:0] umod_9910;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9939;
  wire [127:0] array_update_9946[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9917 = pop_ready & push_valid;
  assign eq_9922 = head == tail;
  assign ne_9906 = head != tail;
  assign and_9923 = eq_9922 & and_9917;
  assign or_9920 = ne_9906 | push_valid;
  assign add_9914 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9909 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9920;
  assign sub_9935 = slots - 2'h1;
  assign add_9937 = slots + 2'h1;
  assign umod_9915 = add_9914 % long_buf_size_lit;
  assign umod_9910 = add_9909 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9915[1:0];
  assign did_push_occur = (can_do_push | and_9917) & push_valid & ~and_9923 & ~is_full_bool;
  assign next_tail_if_pop = umod_9910[1:0];
  assign did_pop_occur = (ne_9906 | and_9917) & pop_ready & ~and_9923;
  assign sel_9939 = pushed ? (popped ? slots : add_9937) : (popped ? sub_9935 : slots);
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
      slots <= sel_9939;
      buf__1[0] <= did_push_occur ? array_update_9946[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_9946[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9920;
  assign pop_data = eq_9922 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_9946_0
    assign array_update_9946[__i0] = head == __i0 ? push_data : buf__1[__i0];
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
  wire and_9974;
  wire eq_9979;
  wire ne_9963;
  wire and_9980;
  wire or_9977;
  wire [2:0] add_9971;
  wire [2:0] long_buf_size_lit;
  wire [2:0] add_9966;
  wire popped;
  wire [1:0] sub_9992;
  wire [1:0] add_9994;
  wire [2:0] umod_9972;
  wire [2:0] umod_9967;
  wire pushed;
  wire [1:0] next_head_if_push;
  wire did_push_occur;
  wire [1:0] next_tail_if_pop;
  wire did_pop_occur;
  wire [1:0] sel_9996;
  wire [127:0] array_update_10003[0:1];
  assign is_full_bool = slots == 2'h1;
  assign can_do_push = ~is_full_bool | pop_ready;
  assign and_9974 = pop_ready & push_valid;
  assign eq_9979 = head == tail;
  assign ne_9963 = head != tail;
  assign and_9980 = eq_9979 & and_9974;
  assign or_9977 = ne_9963 | push_valid;
  assign add_9971 = {1'h0, head} + {1'h0, 2'h1};
  assign long_buf_size_lit = 3'h2;
  assign add_9966 = {1'h0, tail} + {1'h0, 2'h1};
  assign popped = pop_ready & or_9977;
  assign sub_9992 = slots - 2'h1;
  assign add_9994 = slots + 2'h1;
  assign umod_9972 = add_9971 % long_buf_size_lit;
  assign umod_9967 = add_9966 % long_buf_size_lit;
  assign pushed = ~is_full_bool & push_valid;
  assign next_head_if_push = umod_9972[1:0];
  assign did_push_occur = (can_do_push | and_9974) & push_valid & ~and_9980 & ~is_full_bool;
  assign next_tail_if_pop = umod_9967[1:0];
  assign did_pop_occur = (ne_9963 | and_9974) & pop_ready & ~and_9980;
  assign sel_9996 = pushed ? (popped ? slots : add_9994) : (popped ? sub_9992 : slots);
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
      slots <= sel_9996;
      buf__1[0] <= did_push_occur ? array_update_10003[0] : buf__1[0];
      buf__1[1] <= did_push_occur ? array_update_10003[1] : buf__1[1];
    end
  end
  assign push_ready = ~is_full_bool;
  assign pop_valid = or_9977;
  assign pop_data = eq_9979 ? push_data : buf__1[tail > 2'h1 ? 1'h1 : tail[0:0]];
  for (genvar __i0 = 0; __i0 < 2; __i0 = __i0 + 1) begin : gen__array_update_10003_0
    assign array_update_10003[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
endmodule


module __phenom_data_cell__Top_0_next(
  input wire clk,
  input wire reset,
  input wire phenom_data_cell__east_send_rdy,
  input wire [32:0] phenom_data_cell__ext_recv,
  input wire phenom_data_cell__ext_recv_vld,
  input wire phenom_data_cell__north_send_rdy,
  input wire phenom_data_cell__south_send_rdy,
  input wire phenom_data_cell__west_send_rdy,
  output wire [32:0] phenom_data_cell__east_send,
  output wire phenom_data_cell__east_send_vld,
  output wire phenom_data_cell__ext_recv_rdy,
  output wire [32:0] phenom_data_cell__north_send,
  output wire phenom_data_cell__north_send_vld,
  output wire [32:0] phenom_data_cell__south_send,
  output wire phenom_data_cell__south_send_vld,
  output wire [32:0] phenom_data_cell__west_send,
  output wire phenom_data_cell__west_send_vld
);
  wire instantiation_output_9472;
  wire instantiation_output_9497;
  wire [127:0] instantiation_output_9521;
  wire instantiation_output_9522;
  wire instantiation_output_9510;
  wire [32:0] instantiation_output_9514;
  wire instantiation_output_9515;
  wire instantiation_output_9485;
  wire [32:0] instantiation_output_9489;
  wire instantiation_output_9490;
  wire instantiation_output_9561;
  wire [32:0] instantiation_output_9565;
  wire instantiation_output_9566;
  wire instantiation_output_9542;
  wire [32:0] instantiation_output_9546;
  wire instantiation_output_9547;
  wire instantiation_output_9464;
  wire instantiation_output_9465;
  wire [127:0] instantiation_output_9477;
  wire instantiation_output_9478;
  wire [127:0] instantiation_output_9502;
  wire instantiation_output_9503;
  wire instantiation_output_9529;
  wire [127:0] instantiation_output_9534;
  wire instantiation_output_9535;
  wire [127:0] instantiation_output_9553;
  wire instantiation_output_9554;
  wire instantiation_output_10011;
  wire instantiation_output_10012;
  wire instantiation_output_10013;
  wire instantiation_output_10018;
  wire [127:0] instantiation_output_10019;
  wire instantiation_output_10020;
  wire instantiation_output_10025;
  wire [127:0] instantiation_output_10026;
  wire instantiation_output_10027;
  wire instantiation_output_10032;
  wire [127:0] instantiation_output_10033;
  wire instantiation_output_10034;
  wire instantiation_output_10039;
  wire [127:0] instantiation_output_10040;
  wire instantiation_output_10041;
  wire instantiation_output_10046;
  wire [127:0] instantiation_output_10047;
  wire instantiation_output_10048;

  // ===== Instantiations
  __axis__Top__ReservedRx_0_next __axis__Top__ReservedRx_0_next_inst0 (
    .reset(reset),
    .phenom_data_cell__admit(instantiation_output_10012),
    .phenom_data_cell__admit_vld(instantiation_output_10013),
    .phenom_data_cell__ext_recv(phenom_data_cell__ext_recv),
    .phenom_data_cell__ext_recv_vld(phenom_data_cell__ext_recv_vld),
    .phenom_data_cell__req_rdy(instantiation_output_10032),
    .phenom_data_cell__admit_rdy(instantiation_output_9472),
    .phenom_data_cell__ext_recv_rdy(instantiation_output_9497),
    .phenom_data_cell__req(instantiation_output_9521),
    .phenom_data_cell__req_vld(instantiation_output_9522),
    .clk(clk)
  );
  __axis__Top__Tx_0_next __axis__Top__Tx_0_next_inst1 (
    .reset(reset),
    .phenom_data_cell__north(instantiation_output_10026),
    .phenom_data_cell__north_vld(instantiation_output_10027),
    .phenom_data_cell__north_send_rdy(phenom_data_cell__north_send_rdy),
    .phenom_data_cell__north_rdy(instantiation_output_9510),
    .phenom_data_cell__north_send(instantiation_output_9514),
    .phenom_data_cell__north_send_vld(instantiation_output_9515),
    .clk(clk)
  );
  __axis__Top__Tx_1_next __axis__Top__Tx_1_next_inst2 (
    .reset(reset),
    .phenom_data_cell__east(instantiation_output_10019),
    .phenom_data_cell__east_vld(instantiation_output_10020),
    .phenom_data_cell__east_send_rdy(phenom_data_cell__east_send_rdy),
    .phenom_data_cell__east_rdy(instantiation_output_9485),
    .phenom_data_cell__east_send(instantiation_output_9489),
    .phenom_data_cell__east_send_vld(instantiation_output_9490),
    .clk(clk)
  );
  __axis__Top__Tx_2_next __axis__Top__Tx_2_next_inst3 (
    .reset(reset),
    .phenom_data_cell__west(instantiation_output_10047),
    .phenom_data_cell__west_vld(instantiation_output_10048),
    .phenom_data_cell__west_send_rdy(phenom_data_cell__west_send_rdy),
    .phenom_data_cell__west_rdy(instantiation_output_9561),
    .phenom_data_cell__west_send(instantiation_output_9565),
    .phenom_data_cell__west_send_vld(instantiation_output_9566),
    .clk(clk)
  );
  __axis__Top__Tx_3_next __axis__Top__Tx_3_next_inst4 (
    .reset(reset),
    .phenom_data_cell__south(instantiation_output_10040),
    .phenom_data_cell__south_vld(instantiation_output_10041),
    .phenom_data_cell__south_send_rdy(phenom_data_cell__south_send_rdy),
    .phenom_data_cell__south_rdy(instantiation_output_9542),
    .phenom_data_cell__south_send(instantiation_output_9546),
    .phenom_data_cell__south_send_vld(instantiation_output_9547),
    .clk(clk)
  );
  __phenom_data_cell__Top_0_next__1 __phenom_data_cell__Top_0_next__1_inst5 (
    .reset(reset),
    .clk(clk)
  );
  __phenom_data_cell__Top__Service_0_next __phenom_data_cell__Top__Service_0_next_inst6 (
    .reset(reset),
    .phenom_data_cell__admit_rdy(instantiation_output_10011),
    .phenom_data_cell__east_rdy(instantiation_output_10018),
    .phenom_data_cell__north_rdy(instantiation_output_10025),
    .phenom_data_cell__req(instantiation_output_10033),
    .phenom_data_cell__req_vld(instantiation_output_10034),
    .phenom_data_cell__south_rdy(instantiation_output_10039),
    .phenom_data_cell__west_rdy(instantiation_output_10046),
    .phenom_data_cell__admit(instantiation_output_9464),
    .phenom_data_cell__admit_vld(instantiation_output_9465),
    .phenom_data_cell__east(instantiation_output_9477),
    .phenom_data_cell__east_vld(instantiation_output_9478),
    .phenom_data_cell__north(instantiation_output_9502),
    .phenom_data_cell__north_vld(instantiation_output_9503),
    .phenom_data_cell__req_rdy(instantiation_output_9529),
    .phenom_data_cell__south(instantiation_output_9534),
    .phenom_data_cell__south_vld(instantiation_output_9535),
    .phenom_data_cell__west(instantiation_output_9553),
    .phenom_data_cell__west_vld(instantiation_output_9554),
    .clk(clk)
  );
  fifo_for_depth_1_ty_bits_1__with_bypass_register_push materialized_fifo_fifo_phenom_data_cell__admit_ (
    .reset(reset),
    .push_data(instantiation_output_9464),
    .push_valid(instantiation_output_9465),
    .pop_ready(instantiation_output_9472),
    .push_ready(instantiation_output_10011),
    .pop_data(instantiation_output_10012),
    .pop_valid(instantiation_output_10013),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push materialized_fifo_fifo_phenom_data_cell__east_ (
    .reset(reset),
    .push_data(instantiation_output_9477),
    .push_valid(instantiation_output_9478),
    .pop_ready(instantiation_output_9485),
    .push_ready(instantiation_output_10018),
    .pop_data(instantiation_output_10019),
    .pop_valid(instantiation_output_10020),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___1 materialized_fifo_fifo_phenom_data_cell__north_ (
    .reset(reset),
    .push_data(instantiation_output_9502),
    .push_valid(instantiation_output_9503),
    .pop_ready(instantiation_output_9510),
    .push_ready(instantiation_output_10025),
    .pop_data(instantiation_output_10026),
    .pop_valid(instantiation_output_10027),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___2 materialized_fifo_fifo_phenom_data_cell__req_ (
    .reset(reset),
    .push_data(instantiation_output_9521),
    .push_valid(instantiation_output_9522),
    .pop_ready(instantiation_output_9529),
    .push_ready(instantiation_output_10032),
    .pop_data(instantiation_output_10033),
    .pop_valid(instantiation_output_10034),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___3 materialized_fifo_fifo_phenom_data_cell__south_ (
    .reset(reset),
    .push_data(instantiation_output_9534),
    .push_valid(instantiation_output_9535),
    .pop_ready(instantiation_output_9542),
    .push_ready(instantiation_output_10039),
    .pop_data(instantiation_output_10040),
    .pop_valid(instantiation_output_10041),
    .clk(clk)
  );
  fifo_for_depth_1_ty___bits_8___bits_8___bits_8___bits_8____bits_96___with_bypass_register_push___4 materialized_fifo_fifo_phenom_data_cell__west_ (
    .reset(reset),
    .push_data(instantiation_output_9553),
    .push_valid(instantiation_output_9554),
    .pop_ready(instantiation_output_9561),
    .push_ready(instantiation_output_10046),
    .pop_data(instantiation_output_10047),
    .pop_valid(instantiation_output_10048),
    .clk(clk)
  );
  assign phenom_data_cell__east_send = instantiation_output_9489;
  assign phenom_data_cell__east_send_vld = instantiation_output_9490;
  assign phenom_data_cell__ext_recv_rdy = instantiation_output_9497;
  assign phenom_data_cell__north_send = instantiation_output_9514;
  assign phenom_data_cell__north_send_vld = instantiation_output_9515;
  assign phenom_data_cell__south_send = instantiation_output_9546;
  assign phenom_data_cell__south_send_vld = instantiation_output_9547;
  assign phenom_data_cell__west_send = instantiation_output_9565;
  assign phenom_data_cell__west_send_vld = instantiation_output_9566;
endmodule
