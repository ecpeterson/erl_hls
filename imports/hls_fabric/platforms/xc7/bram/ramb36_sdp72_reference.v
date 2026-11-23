// Vendor-reference fixture for one unregistered 72-bit SDP RAMB36E1.
// The cell and its location are retained so its configuration can be compared
// with native FASM; this design is never a board payload.
module ramb36_sdp72_reference;
    wire [31:0] data_a;
    wire [31:0] data_b;
    wire [3:0] parity_a;
    wire [3:0] parity_b;

    (* DONT_TOUCH = "yes", LOC = "RAMB36_X2Y39" *)
    RAMB36E1 #(
        .RAM_MODE("SDP"),
        .READ_WIDTH_A(72),
        .READ_WIDTH_B(0),
        .WRITE_WIDTH_A(0),
        .WRITE_WIDTH_B(72),
        .DOA_REG(0),
        .DOB_REG(0),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST")
    ) memory (
        .CLKARDCLK(1'b0),
        .CLKBWRCLK(1'b0),
        .ADDRARDADDR(16'd0),
        .ADDRBWRADDR(16'd0),
        .DIADI(32'd0),
        .DIBDI(32'd0),
        .DIPADIP(4'd0),
        .DIPBDIP(4'd0),
        .DOADO(data_a),
        .DOBDO(data_b),
        .DOPADOP(parity_a),
        .DOPBDOP(parity_b),
        .WEA(4'd0),
        .WEBWE(8'd0),
        .ENARDEN(1'b0),
        .ENBWREN(1'b0),
        .REGCEAREGCE(1'b0),
        .REGCEB(1'b0),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .CASCADEINA(1'b0),
        .CASCADEINB(1'b0),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0)
    );
endmodule
