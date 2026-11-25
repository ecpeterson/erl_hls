// Exercise all data and parity lanes of one 512 x 72 simple dual-port block RAM.
module parity_memory(input wire clk, input wire wr, input wire rd,
                     input wire [8:0] wa, ra, input wire [71:0] d,
                     output reg [71:0] q);
    (* ram_style = "block" *) reg [71:0] memory [0:511];
    always @(posedge clk) begin
        if (wr) memory[wa] <= d;
        if (rd) q <= memory[ra];
    end
endmodule
