// Simulation model for the application RAM's all-zero configured startup state.
// The assembled Zynq payload is checked separately for zero RAMB INIT fields.
module hls_1r1w_ram #(
    parameter integer WIDTH = 1,
    parameter integer ADDRESS_WIDTH = 1
) (
    input  wire                     clk,
    input  wire [ADDRESS_WIDTH-1:0] rd_addr,
    input  wire                     rd_en,
    output reg  [WIDTH-1:0]         rd_data,
    input  wire [ADDRESS_WIDTH-1:0] wr_addr,
    input  wire [WIDTH-1:0]         wr_data,
    input  wire                     wr_en
);
    localparam integer DEPTH = 1 << ADDRESS_WIDTH;
    (* ram_style = "block" *) reg [WIDTH-1:0] memory [0:DEPTH-1];
    integer index;

    initial begin
        rd_data = 0;
        for (index = 0; index < DEPTH; index = index + 1)
            memory[index] = 0;
    end

    always @(posedge clk) begin
        if (wr_en)
            memory[wr_addr] <= wr_data;
    end

    always @(posedge clk) begin
        if (rd_en)
            rd_data <= memory[rd_addr];
    end
endmodule
