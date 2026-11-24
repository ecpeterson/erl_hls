// Four-Phi scheduler BRAM mode with an observable address, data and arithmetic result.
// The optional output register adds one read cycle. WRITE_FIRST exercises the unsupported mode.
module top #(parameter OUTPUT_REG=0, parameter MODE="READ_FIRST")
    (input wire clock, output wire activity);
    reg [8:0] addr = 0;
    reg [31:0] sum = 1;
    wire [31:0] q;
    always @(posedge clock) begin
        addr <= addr + 1'b1;
        sum <= q + sum;
    end
    assign activity = ^sum;
    RAMB36E1 #(.RAM_MODE("SDP"), .READ_WIDTH_A(72), .WRITE_WIDTH_A(0),
        .READ_WIDTH_B(0), .WRITE_WIDTH_B(72), .DOA_REG(OUTPUT_REG), .DOB_REG(OUTPUT_REG),
        .WRITE_MODE_A(MODE), .WRITE_MODE_B(MODE)) memory (
        .CLKARDCLK(clock), .CLKBWRCLK(clock), .ADDRARDADDR({1'b0,addr,6'b0}),
        .ADDRBWRADDR({1'b0,addr,6'b0}), .DIADI(sum), .DIBDI(~sum), .DIPADIP(4'b0),
        .DIPBDIP(4'b0), .DOADO(q), .WEBWE(8'hff), .WEA(4'b0),
        .ENARDEN(1'b1), .ENBWREN(1'b1), .REGCEAREGCE(1'b1), .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0), .RSTRAMB(1'b0), .RSTREGARSTREG(1'b0), .RSTREGB(1'b0),
        .CASCADEINA(1'b0), .CASCADEINB(1'b0), .INJECTDBITERR(1'b0), .INJECTSBITERR(1'b0));
endmodule
