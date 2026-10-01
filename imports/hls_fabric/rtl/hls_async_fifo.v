// Bounded ready/valid crossing. Both sides share one reset epoch.
// Reset may assert without either clock; each side releases after two edges.
// ADDR_BITS >= 2; capacity is 2**ADDR_BITS complete WIDTH-bit words.
module hls_async_fifo #(
    parameter WIDTH = 33,
    parameter ADDR_BITS = 3
)(
    input wire reset,
    input wire wr_clk,
    input wire [WIDTH-1:0] in_data,
    input wire in_valid,
    output wire in_ready,
    input wire rd_clk,
    output wire [WIDTH-1:0] out_data,
    output wire out_valid,
    input wire out_ready
);
    localparam PTR_BITS = ADDR_BITS + 1;
    localparam [PTR_BITS-1:0] FULL_MASK = (1 << ADDR_BITS) | (1 << (ADDR_BITS-1));
    wire wr_reset, rd_reset;
    hls_clock_reset wr_release(.clk(wr_clk), .reset(reset), .local_reset(wr_reset));
    hls_clock_reset rd_release(.clk(rd_clk), .reset(reset), .local_reset(rd_reset));

    // The read port is asynchronous, so this intentionally targets distributed
    // memory, not BRAM. Pointers protect a word until its reader accepts it.
    (* ram_style = "distributed" *) reg [WIDTH-1:0] memory [0:(1<<ADDR_BITS)-1];
    reg [PTR_BITS-1:0] wr_binary, wr_gray, rd_binary, rd_gray;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_BITS-1:0] rd_gray_w1, rd_gray_w2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_BITS-1:0] wr_gray_r1, wr_gray_r2;
    reg full;
    // Both pointers below belong to the read domain. Keeping this comparison
    // combinational exposes a newly synchronized write without a third clock.
    wire empty = rd_gray == wr_gray_r2;
    wire push = in_valid && in_ready;
    wire pop = out_valid && out_ready;
    wire [PTR_BITS-1:0] wr_next = wr_binary + push;
    wire [PTR_BITS-1:0] rd_next = rd_binary + pop;
    wire [PTR_BITS-1:0] wr_gray_next = (wr_next >> 1) ^ wr_next;
    wire [PTR_BITS-1:0] rd_gray_next = (rd_next >> 1) ^ rd_next;

    assign in_ready = !wr_reset && !full;
    assign out_valid = !rd_reset && !empty;
    assign out_data = memory[rd_binary[ADDR_BITS-1:0]];

    always @(posedge wr_clk) if (push)
        memory[wr_binary[ADDR_BITS-1:0]] <= in_data;

    always @(posedge wr_clk or posedge wr_reset) begin
        if (wr_reset) begin
            wr_binary <= 0;
            wr_gray <= 0;
            full <= 0;
            rd_gray_w1 <= 0;
            rd_gray_w2 <= 0;
        end else begin
            wr_binary <= wr_next;
            wr_gray <= wr_gray_next;
            full <= wr_gray_next == (rd_gray_w2 ^ FULL_MASK);
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
        end
    end

    always @(posedge rd_clk or posedge rd_reset) begin
        if (rd_reset) begin
            rd_binary <= 0;
            rd_gray <= 0;
            wr_gray_r1 <= 0;
            wr_gray_r2 <= 0;
        end else begin
            rd_binary <= rd_next;
            rd_gray <= rd_gray_next;
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
        end
    end

    initial begin
        if (WIDTH < 1 || ADDR_BITS < 2 || ADDR_BITS > 16)
            $error("hls_async_fifo requires WIDTH >= 1 and 2 <= ADDR_BITS <= 16");
    end
endmodule

// Asynchronous assertion is necessary when a device clock has stopped. The
// caller must reset both endpoints and all transport storage in the same epoch.
module hls_clock_reset(input wire clk, reset, output wire local_reset);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] release_pipe;
    always @(posedge clk or posedge reset) begin
        if (reset) release_pipe <= 2'b11;
        else release_pipe <= {release_pipe[0], 1'b0};
    end
    assign local_reset = release_pipe[1];
endmodule
