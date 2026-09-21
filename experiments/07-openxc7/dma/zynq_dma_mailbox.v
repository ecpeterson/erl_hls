// One TX and one RX packet slot between AXI3 memory accesses and 32-bit streams.
// Software fills TX RAM, then publishes its byte length; RX RAM is immutable
// from TLAST until acknowledged. Frames contain 2..MAX_WORDS full words, with
// 2 <= MAX_WORDS <= 511. No packet
// storage is reset: ownership/length prevent reads of uninitialized RX words.
// One AXI transaction per direction, no WID interleaving. RAM supports aligned
// 32-bit INCR bursts; registers require single beats. Errors return SLVERR;
// writes before a later burst error may already have altered unpublished RAM.
module zynq_dma_mailbox #(
    parameter [31:0] BASE_ADDR = 32'h40000000,
    parameter MAX_WORDS = 257, parameter [31:0] IDENTITY = 32'h484c444d
)(
    input wire clock, input wire reset_n,
    input wire [11:0] awid, input wire [31:0] awaddr,
    input wire [3:0] awlen, input wire [2:0] awsize,
    input wire [1:0] awburst, input wire [1:0] awlock,
    input wire awvalid, output wire awready,
    input wire [11:0] wid, input wire [31:0] wdata,
    input wire [3:0] wstrb, input wire wlast, input wire wvalid, output wire wready,
    output reg [11:0] bid, output reg [1:0] bresp,
    output reg bvalid, input wire bready,
    input wire [11:0] arid, input wire [31:0] araddr,
    input wire [3:0] arlen, input wire [2:0] arsize,
    input wire [1:0] arburst, input wire [1:0] arlock,
    input wire arvalid, output wire arready,
    output reg [11:0] rid, output wire [31:0] rdata,
    output reg [1:0] rresp, output wire rlast,
    output wire rvalid, input wire rready,
    output wire [31:0] tx_data, output wire tx_last,
    output wire tx_valid, input wire tx_ready,
    input wire [31:0] rx_data, input wire rx_last,
    input wire rx_valid, output wire rx_ready,
    output wire irq
);
    localparam [31:0] TX_END = 32'h1000 + 4*(MAX_WORDS-1);
    localparam [31:0] RX_END = 32'h2000 + 4*(MAX_WORDS-1);
    localparam [1:0] IDLE = 0, FETCH = 1, SEND = 2;
    reg [1:0] tx_state, read_state;
    reg [8:0] tx_index, tx_words, rx_count, rx_words;
    reg rx_full, rx_discard, tx_done, fault;
    reg [2:0] irq_mask;
    wire [2:0] events = {fault, rx_full, tx_done};
    wire tx_busy = tx_state != IDLE;

    reg write_active, write_error, write_ram;
    reg [31:0] write_addr, read_addr;
    reg [3:0] write_left, read_left;
    reg read_error, read_ram;
    reg [31:0] register_data;
    wire [31:0] aw_offset = awaddr - BASE_ADDR;
    wire [31:0] ar_offset = araddr - BASE_ADDR;
    wire [31:0] ar_end = ar_offset + {26'b0, arlen, 2'b00};
    wire [31:0] aw_end = aw_offset + {26'b0, awlen, 2'b00};
    wire write_bad = write_error || wid != bid || wlast != (write_left == 0);
    wire write_beat = wvalid && wready;
    wire register_write = write_beat && !write_bad && !write_ram && wstrb == 4'hf;
    wire publish = register_write && write_addr == 12 && !tx_busy &&
                   wdata >= 8 && wdata <= 4*MAX_WORDS && wdata[1:0] == 0;
    wire ack = register_write && write_addr == 20;
    wire set_mask = register_write && write_addr == 24;
    wire ram_write = write_beat && !write_bad && write_ram && !tx_busy;
    wire register_ok = publish || ack || set_mask;

    // Separate clocked RAM ports preserve BRAM inference (no reset or clear).
    (* ram_style = "block" *) reg [31:0] tx_ram [0:511];
    (* ram_style = "block" *) reg [31:0] rx_ram [0:511];
    reg [31:0] tx_q, rx_q;
    integer lane;
    always @(posedge clock) begin
        if (ram_write)
            for (lane = 0; lane < 4; lane = lane + 1)
                if (wstrb[lane]) tx_ram[write_addr[10:2]][8*lane +: 8] <= wdata[8*lane +: 8];
        if (tx_state == FETCH) tx_q <= tx_ram[tx_index];
        if (rx_valid && rx_ready && !rx_discard && rx_count < MAX_WORDS)
            rx_ram[rx_count] <= rx_data;
        if (read_state == FETCH && read_ram && !read_error)
            rx_q <= rx_ram[read_addr[10:2]];
    end

    assign awready = reset_n && !write_active && !bvalid;
    assign wready = reset_n && write_active;
    assign arready = reset_n && read_state == IDLE;
    assign rvalid = reset_n && read_state == SEND;
    assign rlast = read_left == 0;
    assign rdata = read_ram && !read_error ? rx_q : register_data;
    assign tx_valid = reset_n && tx_state == SEND;
    assign tx_last = tx_index == tx_words - 1'b1;
    assign tx_data = tx_q;
    assign rx_ready = reset_n && !rx_full;
    assign irq = |(events & irq_mask);

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            tx_state <= IDLE; tx_index <= 0; tx_words <= 0;
            rx_count <= 0; rx_words <= 0; rx_full <= 0; rx_discard <= 0;
            tx_done <= 0; fault <= 0; irq_mask <= 0;
            write_active <= 0; write_error <= 0; write_ram <= 0;
            write_addr <= 0; write_left <= 0;
            bid <= 0; bresp <= 0; bvalid <= 0;
            read_state <= IDLE; read_addr <= 0; read_left <= 0;
            read_error <= 0; read_ram <= 0;
            rid <= 0; rresp <= 0; register_data <= 0;
        end else begin
            if (ack) begin
                if (wdata[0]) tx_done <= 0;
                if (wdata[1]) begin rx_full <= 0; rx_words <= 0; end
                if (wdata[2]) fault <= 0;
            end
            if (set_mask) irq_mask <= wdata[2:0];
            if (publish) begin
                tx_words <= wdata[10:2]; tx_index <= 0;
                tx_state <= FETCH; tx_done <= 0;
            end
            if (tx_state == FETCH) tx_state <= SEND;
            if (tx_valid && tx_ready) begin
                if (tx_last) begin tx_state <= IDLE; tx_done <= 1; end
                else begin tx_index <= tx_index + 1'b1; tx_state <= FETCH; end
            end
            // Oversized frames drain to TLAST without exposing a truncated packet.
            if (rx_valid && rx_ready) begin
                if (rx_last) begin
                    if (!rx_discard && rx_count >= 1 && rx_count < MAX_WORDS) begin
                        rx_words <= rx_count + 1'b1; rx_full <= 1;
                    end else fault <= 1;
                    rx_count <= 0; rx_discard <= 0;
                end else if (rx_count == MAX_WORDS) begin
                    rx_discard <= 1; fault <= 1;
                end else rx_count <= rx_count + 1'b1;
            end

            if (bvalid && bready) bvalid <= 0;
            if (awvalid && awready) begin
                bid <= awid; write_active <= 1; write_left <= awlen;
                write_addr <= aw_offset;
                write_ram <= aw_offset >= 32'h1000 && aw_offset <= TX_END && aw_end <= TX_END;
                write_error <= awsize != 2 || awlock != 0 || awaddr[1:0] != 0 ||
                    !((awburst == 1 && aw_offset >= 32'h1000 && aw_offset <= TX_END && aw_end <= TX_END && !tx_busy) ||
                      (awlen == 0 && (awburst == 0 || awburst == 1) && aw_offset < 32'h20));
            end
            if (write_beat) begin
                write_error <= write_bad || (write_ram ? tx_busy : !register_ok);
                if (write_left == 0) begin
                    write_active <= 0; bvalid <= 1;
                    bresp <= (write_bad || (write_ram ? tx_busy : !register_ok)) ? 2'b10 : 0;
                end else begin
                    write_left <= write_left - 1'b1; write_addr <= write_addr + 4;
                end
            end

            if (arvalid && arready) begin
                rid <= arid; read_addr <= ar_offset; read_left <= arlen;
                read_ram <= ar_offset >= 32'h2000 && ar_offset <= RX_END && ar_end <= RX_END;
                read_error <= arsize != 2 || arlock != 0 || araddr[1:0] != 0 ||
                    !((arburst == 1 && ar_offset >= 32'h2000 && ar_offset <= RX_END && ar_end <= RX_END &&
                       rx_full && ar_end < 32'h2000 + {21'b0, rx_words, 2'b00}) ||
                      (arlen == 0 && (arburst == 0 || arburst == 1) && ar_offset < 32'h20));
                read_state <= FETCH;
            end
            if (read_state == FETCH) begin
                register_data <= 0; rresp <= read_error ? 2'b10 : 0;
                if (!read_error && !read_ram) begin
                    case (read_addr)
                        0: register_data <= IDENTITY;
                        4: register_data <= 1;
                        8: register_data <= {28'b0, (rx_count != 0 || rx_discard), fault, rx_full, tx_busy};
                        16: register_data <= {21'b0, rx_words, 2'b00};
                        24: register_data <= {29'b0, irq_mask};
                        28: register_data <= {29'b0, events};
                        default: rresp <= 2'b10;
                    endcase
                end
                read_state <= SEND;
            end
            if (rvalid && rready) begin
                if (read_left == 0) read_state <= IDLE;
                else begin
                    read_left <= read_left - 1'b1; read_addr <= read_addr + 4;
                    read_state <= FETCH;
                end
            end
        end
    end
endmodule
