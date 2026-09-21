// Optional DMA/Ethernet diagnostic fixture, not application routing.
// Host packets: u32 little-endian byte length, then ceil(length/4) words whose
// least-significant byte comes first. Length is 14..1514; last marks the final
// word. Ethernet ports carry bytes before FCS; MAC padding is visible on RX.
//
// Each direction has one whole-frame CDC slot. reset_n is a shared device reset
// requiring quiescent AXI users. Directional active_n signals may stop/restart
// Ethernet independently: incomplete RX is discarded; completed RX survives;
// an unconsumed TX slot restarts from its beginning. Acceptance is not delivery.
// Directional reset assertion is asynchronous; release is synchronized locally.
// No link recovery resets the host stream, mailbox or AXI transaction.
module ethernet_dma_packets(
    input wire clock, reset_n, tx_clock, rx_clock,
    input wire tx_active_n, rx_active_n,
    input wire [31:0] host_tx_data,
    input wire host_tx_valid, host_tx_last,
    output wire host_tx_ready,
    output wire [31:0] host_rx_data,
    output wire host_rx_valid, host_rx_last,
    input wire host_rx_ready,
    output wire [7:0] tx_data,
    output wire tx_valid, tx_last,
    input wire tx_ready,
    input wire [7:0] rx_data,
    input wire rx_valid, rx_last,
    output wire rx_ready,
    output reg tx_invalid
);
    localparam FETCH=0, SEND=1;
    localparam HEADER=0, RX_FETCH=1, RX_SEND=2;
    wire host_reset_n;
    wire tx_cursor_reset_n, rx_cursor_reset_n;
    zynq_probe_reset hr(clock, reset_n, host_reset_n);
    zynq_probe_reset tr(tx_clock, reset_n && tx_active_n, tx_cursor_reset_n);
    zynq_probe_reset rr(rx_clock, reset_n && rx_active_n, rx_cursor_reset_n);

    // Host admission checks the length envelope before publishing the TX slot.
    reg collecting, invalid;
    reg [10:0] incoming_length;
    reg [8:0] incoming_words, write_index;
    wire tx_free, tx_pending;
    wire host_write = host_tx_valid && host_tx_ready;
    wire tx_publish = host_write && collecting && host_tx_last && !invalid &&
                      write_index == incoming_words - 1'b1;
    assign host_tx_ready = host_reset_n && tx_free;
    always @(posedge clock or negedge host_reset_n) begin
        if (!host_reset_n) begin
            collecting<=0; invalid<=0; incoming_length<=0; incoming_words<=0;
            write_index<=0; tx_invalid<=0;
        end else if (host_write) begin
            if (!collecting) begin
                incoming_length<=host_tx_data[10:0];
                incoming_words<=(host_tx_data[10:0]+11'd3)>>2;
                write_index<=0;
                invalid<=host_tx_data<14 || host_tx_data>1514;
                collecting<=!host_tx_last;
                if (host_tx_last) tx_invalid<=1;
            end else if (host_tx_last) begin
                collecting<=0; invalid<=0;
                if (!tx_publish) tx_invalid<=1;
            end else if (write_index == 378) invalid<=1;
            else write_index<=write_index+1'b1;
        end
    end

    // A link interruption resets only this cursor, retaining any pending slot.
    reg tx_state;
    reg [10:0] tx_index;
    wire [31:0] tx_word;
    wire [10:0] tx_length;
    wire tx_release = tx_valid && tx_ready && tx_last;
    ethernet_cdc_slot tx_slot(
        .reset_n(reset_n), .write_clock(clock), .read_clock(tx_clock),
        .write_enable(host_write && collecting && !invalid), .publish(tx_publish),
        .write_address(write_index), .write_data(host_tx_data), .write_length(incoming_length),
        .write_ready(tx_free), .read_enable(tx_cursor_reset_n && tx_pending && tx_state==FETCH),
        .release_packet(tx_release), .read_address(tx_index[10:2]), .read_data(tx_word),
        .read_length(tx_length), .read_valid(tx_pending)
    );
    assign tx_valid = tx_cursor_reset_n && tx_pending && tx_state==SEND;
    assign tx_data = tx_word[8*tx_index[1:0] +: 8];
    assign tx_last = tx_index == tx_length-1'b1;
    always @(posedge tx_clock or negedge tx_cursor_reset_n) begin
        if (!tx_cursor_reset_n) begin tx_state<=FETCH; tx_index<=0; end
        else if (tx_pending) begin
            if (tx_state==FETCH) tx_state<=SEND;
            else if (tx_ready) begin
                if (tx_last) begin tx_state<=FETCH; tx_index<=0; end
                else begin
                    tx_index<=tx_index+1'b1;
                    if (tx_index[1:0]==3) tx_state<=FETCH;
                end
            end
        end
    end

    // RX writes complete words or a zero-padded tail; only TLAST publishes them.
    reg [10:0] rx_count;
    reg rx_discard;
    reg [31:0] rx_word;
    reg [31:0] next_word;
    wire rx_free, rx_pending;
    wire rx_transfer = rx_valid && rx_ready;
    wire rx_publish = rx_transfer && rx_last && !rx_discard && rx_count>=13 && rx_count<1514;
    always @* begin
        next_word = rx_count[1:0]==0 ? 0 : rx_word;
        next_word[8*rx_count[1:0] +: 8] = rx_data;
    end
    assign rx_ready = rx_cursor_reset_n && rx_free;
    always @(posedge rx_clock or negedge rx_cursor_reset_n) begin
        if (!rx_cursor_reset_n) begin rx_count<=0; rx_word<=0; rx_discard<=0; end
        else if (rx_transfer) begin
            rx_word<=next_word;
            if (rx_last) begin rx_count<=0; rx_discard<=0; end
            else if (rx_count==1514) rx_discard<=1;
            else rx_count<=rx_count+1'b1;
        end
    end

    // Host reads a length header and complete words, retaining a stalled beat.
    reg [1:0] rx_state;
    reg [8:0] read_index;
    wire [31:0] read_word;
    wire [10:0] rx_length;
    wire [8:0] rx_words = (rx_length+11'd3)>>2;
    wire rx_release = host_rx_valid && host_rx_ready && host_rx_last;
    ethernet_cdc_slot rx_slot(
        .reset_n(reset_n), .write_clock(rx_clock), .read_clock(clock),
        .write_enable(rx_transfer && !rx_discard && rx_count<1514 && (rx_last || rx_count[1:0]==3)),
        .publish(rx_publish), .write_address(rx_count[10:2]), .write_data(next_word),
        .write_length(rx_count+11'd1), .write_ready(rx_free),
        .read_enable(rx_pending && rx_state==RX_FETCH), .release_packet(rx_release),
        .read_address(read_index), .read_data(read_word), .read_length(rx_length), .read_valid(rx_pending)
    );
    assign host_rx_valid = host_reset_n && rx_pending && rx_state!=RX_FETCH;
    assign host_rx_data = rx_state==HEADER ? {21'b0,rx_length} : read_word;
    assign host_rx_last = rx_state==RX_SEND && read_index==rx_words-1'b1;
    always @(posedge clock or negedge host_reset_n) begin
        if (!host_reset_n) begin rx_state<=HEADER; read_index<=0; end
        else if (rx_pending) begin
            if (rx_state==RX_FETCH) rx_state<=RX_SEND;
            else if (host_rx_ready) begin
                if (rx_state==HEADER) rx_state<=RX_FETCH;
                else if (host_rx_last) begin rx_state<=HEADER; read_index<=0; end
                else begin read_index<=read_index+1'b1; rx_state<=RX_FETCH; end
            end
        end
    end
endmodule
