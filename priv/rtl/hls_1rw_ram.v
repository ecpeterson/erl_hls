// Synchronous one-read/write memory for XLS explicit RAM channels.
module hls_1rw_ram #(
    parameter integer WIDTH = 1,
    parameter integer ADDRESS_WIDTH = 1
) (
    input  wire                     clk,
    input  wire [ADDRESS_WIDTH-1:0] addr,
    input  wire [WIDTH-1:0]         wr_data,
    input  wire                     we,
    input  wire                     re,
    output reg  [WIDTH-1:0]         rd_data
);
    localparam integer DEPTH = 1 << ADDRESS_WIDTH;

    (* ram_style = "block" *) reg [WIDTH-1:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            memory[addr] <= wr_data;
        if (re)
            rd_data <= memory[addr];
    end
endmodule
