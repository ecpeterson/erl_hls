// Synchronous 1R1W indexed-gather payload memory. Member m occupies bits
// [m*ELEMENT_BITS +: ELEMENT_BITS]; wr_mask[m] enables that entire member.
// Reads take one rising edge, hold while disabled, and observe old data during a
// same-address write. Ownership must prevent writes to borrowed collection rows.
// There is no reset or initialization: membership, not stored bits, defines validity.
module hls_indexed_gather_ram #(
    parameter integer ELEMENT_BITS = 46,
    parameter integer MEMBERS = 6,
    parameter integer ADDRESS_WIDTH = 1,
    parameter RAM_STYLE = "distributed"
) (
    input  wire                              clk,
    input  wire [ADDRESS_WIDTH-1:0]          rd_addr,
    input  wire                              rd_en,
    output reg  [ELEMENT_BITS*MEMBERS-1:0]   rd_data,
    input  wire [ADDRESS_WIDTH-1:0]          wr_addr,
    input  wire [ELEMENT_BITS*MEMBERS-1:0]   wr_data,
    input  wire [MEMBERS-1:0]                wr_mask,
    input  wire                              wr_en
);
    localparam integer DEPTH = 1 << ADDRESS_WIDTH;

    (* ram_style = RAM_STYLE *) reg [ELEMENT_BITS*MEMBERS-1:0] memory [0:DEPTH-1];
    integer member;

    always @(posedge clk) begin
        if (rd_en)
            rd_data <= memory[rd_addr];
        for (member = 0; member < MEMBERS; member = member + 1)
            if (wr_en && wr_mask[member])
                memory[wr_addr][member*ELEMENT_BITS +: ELEMENT_BITS] <=
                    wr_data[member*ELEMENT_BITS +: ELEMENT_BITS];
    end
endmodule
