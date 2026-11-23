// Encapsulate one complete serial-credit packet in one private Ethernet frame.
// The generated application side is 32-bit word/TLAST ready-valid at 25 MHz;
// the packet side is byte/TLAST ready-valid in independent GTX clock domains.
// Each fixed 60-byte frame carries a checked role, sequence and either one
// credit word or five data words. Any malformed/lost/reordered frame is fatal
// to the credit protocol and therefore latches a diagnostic fault until reset.
module partition_link_packets #(
    parameter [7:0] ROLE = 8'd1
) (
    input wire clock, reset_n,
    input wire tx_clock, rx_clock,
    input wire tx_active_n, rx_active_n,
    input wire [32:0] link_tx,
    input wire link_tx_valid,
    output wire link_tx_ready,
    output wire [32:0] link_rx,
    output wire link_rx_valid,
    input wire link_rx_ready,
    output wire [7:0] tx_data,
    output wire tx_valid, tx_last,
    input wire tx_ready,
    input wire [7:0] rx_data,
    input wire rx_valid, rx_last,
    output wire rx_ready,
    output wire [31:0] fault,
    output wire tx_frame_accepted,
    output wire rx_frame_accepted,
    output wire link_rx_frame_delivered
);
    localparam COLLECT = 1'b0;
    localparam EMIT = 1'b1;
    localparam [7:0] PEER = ROLE == 8'd1 ? 8'd2 : 8'd1;

    reg tx_state;
    reg [2:0] tx_count;
    reg [2:0] tx_word_count;
    reg [4:0] tx_index;
    reg [31:0] tx_sequence;
    reg [31:0] tx_words [0:4];
    reg tx_protocol_fault;
    wire link_tx_take = link_tx_valid && link_tx_ready;
    assign link_tx_ready = reset_n && tx_state == COLLECT;

    wire [31:0] frame_word =
        tx_index == 1  ? 32'h00000002 :
        tx_index == 2  ? (32'h00020000 | ({24'b0, PEER} << 8)) :
        tx_index == 3  ? ({24'b0, ROLE} << 24) :
        tx_index == 4  ? 32'h0000b588 :
        tx_index == 5  ? 32'h504c4845 :
        tx_index == 6  ? {8'b0, 5'b0, tx_word_count, ROLE, 8'd1} :
        tx_index == 7  ? tx_sequence :
        tx_index == 8  ? tx_words[0] :
        tx_index == 9  ? (tx_word_count > 1 ? tx_words[1] : 32'b0) :
        tx_index == 10 ? (tx_word_count > 2 ? tx_words[2] : 32'b0) :
        tx_index == 11 ? (tx_word_count > 3 ? tx_words[3] : 32'b0) :
        tx_index == 12 ? (tx_word_count > 4 ? tx_words[4] : 32'b0) :
        32'b0;

    wire [31:0] host_tx_data = tx_index == 0 ? 32'd60 : frame_word;
    wire host_tx_valid = tx_state == EMIT;
    wire host_tx_last = tx_index == 15;
    wire host_tx_ready;
    wire host_tx_take = host_tx_valid && host_tx_ready;
    assign tx_frame_accepted = host_tx_take && host_tx_last;

    integer i;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            tx_state <= COLLECT;
            tx_count <= 0;
            tx_word_count <= 0;
            tx_index <= 0;
            tx_sequence <= 0;
            tx_protocol_fault <= 0;
            for (i = 0; i < 5; i = i + 1) tx_words[i] <= 0;
        end else begin
            if (link_tx_take) begin
                tx_words[tx_count] <= link_tx[31:0];
                if (link_tx[32]) begin
                    if (tx_count == 0 || tx_count == 4) begin
                        tx_word_count <= tx_count + 1'b1;
                        tx_index <= 0;
                        tx_state <= EMIT;
                    end else begin
                        tx_count <= 0;
                        tx_protocol_fault <= 1;
                    end
                end else if (tx_count == 4) begin
                    tx_count <= 0;
                    tx_protocol_fault <= 1;
                end else tx_count <= tx_count + 1'b1;
            end
            if (host_tx_take) begin
                if (host_tx_last) begin
                    tx_state <= COLLECT;
                    tx_count <= 0;
                    tx_index <= 0;
                    tx_sequence <= tx_sequence + 1'b1;
                end else tx_index <= tx_index + 1'b1;
            end
        end
    end

    reg rx_state;
    reg [4:0] rx_index;
    reg [2:0] rx_word_count;
    reg [2:0] rx_output_index;
    reg [31:0] rx_expected_sequence;
    reg [31:0] rx_words [0:4];
    reg rx_bad;
    reg rx_protocol_fault;
    wire [31:0] host_rx_data;
    wire host_rx_valid, host_rx_last;
    wire host_rx_ready = reset_n && rx_state == COLLECT;
    wire host_rx_take = host_rx_valid && host_rx_ready;
    assign rx_frame_accepted = host_rx_take && host_rx_last;

    wire rx_count_ok = host_rx_data[23:16] == 8'd1 || host_rx_data[23:16] == 8'd5;
    reg rx_word_bad;
    always @* begin
        rx_word_bad = host_rx_last != (rx_index == 15);
        case (rx_index)
            0: rx_word_bad = rx_word_bad || host_rx_data != 32'd60;
            1: rx_word_bad = rx_word_bad || host_rx_data != 32'h00000002;
            2: rx_word_bad = rx_word_bad || host_rx_data !=
                (32'h00020000 | ({24'b0, ROLE} << 8));
            3: rx_word_bad = rx_word_bad || host_rx_data != ({24'b0, PEER} << 24);
            4: rx_word_bad = rx_word_bad || host_rx_data != 32'h0000b588;
            5: rx_word_bad = rx_word_bad || host_rx_data != 32'h504c4845;
            6: rx_word_bad = rx_word_bad || host_rx_data[7:0] != 8'd1 ||
                host_rx_data[15:8] != PEER || host_rx_data[31:24] != 0 || !rx_count_ok;
            7: rx_word_bad = rx_word_bad || host_rx_data != rx_expected_sequence;
            13, 14, 15: rx_word_bad = rx_word_bad || host_rx_data != 0;
            default: rx_word_bad = rx_word_bad;
        endcase
    end

    assign link_rx_valid = reset_n && rx_state == EMIT;
    assign link_rx = {rx_output_index == rx_word_count - 1'b1,
        rx_words[rx_output_index]};
    wire link_rx_take = link_rx_valid && link_rx_ready;
    assign link_rx_frame_delivered = link_rx_take && link_rx[32];
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            rx_state <= COLLECT;
            rx_index <= 0;
            rx_word_count <= 0;
            rx_output_index <= 0;
            rx_expected_sequence <= 0;
            rx_bad <= 0;
            rx_protocol_fault <= 0;
            for (i = 0; i < 5; i = i + 1) rx_words[i] <= 0;
        end else begin
            if (host_rx_take) begin
                if (rx_index == 6) rx_word_count <= host_rx_data[23:16];
                if (rx_index >= 8 && rx_index <= 12)
                    rx_words[rx_index - 8] <= host_rx_data;
                rx_bad <= rx_bad || rx_word_bad;
                if (rx_index == 15) begin
                    rx_index <= 0;
                    rx_bad <= 0;
                    if (rx_bad || rx_word_bad) rx_protocol_fault <= 1;
                    else begin
                        rx_state <= EMIT;
                        rx_output_index <= 0;
                        rx_expected_sequence <= rx_expected_sequence + 1'b1;
                    end
                end else rx_index <= rx_index + 1'b1;
            end
            if (link_rx_take) begin
                if (link_rx[32]) begin
                    rx_state <= COLLECT;
                    rx_output_index <= 0;
                end else rx_output_index <= rx_output_index + 1'b1;
            end
        end
    end

    wire tx_invalid;
    reg tx_invalid_seen;
    always @(posedge clock or negedge reset_n)
        if (!reset_n) tx_invalid_seen <= 0;
        else if (tx_invalid) tx_invalid_seen <= 1;

    ethernet_dma_packets bridge(
        .clock(clock), .reset_n(reset_n), .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_active_n(tx_active_n), .rx_active_n(rx_active_n),
        .host_tx_data(host_tx_data), .host_tx_valid(host_tx_valid),
        .host_tx_last(host_tx_last), .host_tx_ready(host_tx_ready),
        .host_rx_data(host_rx_data), .host_rx_valid(host_rx_valid),
        .host_rx_last(host_rx_last), .host_rx_ready(host_rx_ready),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_ready(rx_ready),
        .tx_invalid(tx_invalid)
    );
    assign fault = {29'b0, rx_protocol_fault, tx_protocol_fault, tx_invalid_seen};
endmodule
