// Fixed-latency storage behind XLS's external 1R1W RAM ports.
//
// The array deliberately has no reset or initializer: trace metadata prevents
// reads from unwritten rows, while leaving the storage untouched allows FPGA
// synthesis to infer block RAM instead of thousands of flip-flops. Logical
// ping-pong banks are encoded in the most-significant address bit.
module xls_trace_ram_1r1w #(
    parameter integer ADDR_WIDTH = 6,
    parameter integer DATA_WIDTH = 128
) (
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  wr_en
);
    localparam integer DEPTH = 1 << ADDR_WIDTH;

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en)
            memory[wr_addr] <= wr_data;
        if (rd_en)
            rd_data <= memory[rd_addr];
    end
endmodule
