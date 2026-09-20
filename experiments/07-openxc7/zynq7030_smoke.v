// Compile-only exercise of synchronous BRAM, an 18x17 unsigned multiply and recurrent logic.
// Each clock replaces one RAM word and folds the previously read word's product
// into digest. Outputs are deterministic from configuration; there is no reset.
module zynq7030_resources(input wire clock, output reg [31:0] digest = 0);
    (* ram_style = "block" *) reg [31:0] memory [0:511];
    reg [8:0] address = 0;
    // DSP input registers power up at zero; XNOR feedback escapes that seed.
    reg [31:0] noise = 0;
    reg [31:0] read_data = 0;
    reg [34:0] product = 0;
    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            memory[i] = 0;
    end
    always @(posedge clock) begin
        read_data <= memory[address];
        memory[address] <= noise;
        address <= address + 1'b1;
        noise <= {noise[30:0], ~(noise[31] ^ noise[21] ^ noise[1] ^ noise[0])};
        product <= read_data[17:0] * noise[16:0];
        digest <= {digest[30:0], digest[31]} ^ product[31:0] ^ {29'b0, product[34:32]} ^ read_data;
    end
endmodule

// A two-pin shell retains the resource pipeline through a recurrent digest.
module zynq7030_smoke(input wire clock, output wire activity);
    wire [31:0] digest;
    zynq7030_resources resources(clock, digest);
    assign activity = ^digest;
endmodule
