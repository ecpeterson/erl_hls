// Prove the cascade identities against Yosys's DSP48E1 primitive model.
// All data and mode inputs are symbolic; all internal registers are bypassed.
module dsp_cascade_miter(
  input [29:0] a, acin,
  input [17:0] b, bcin,
  input [47:0] c, pcin,
  input [24:0] d,
  input [6:0] opmode,
  input [4:0] inmode,
  input [3:0] alumode,
  input [2:0] carryinsel,
  input carryin, carrycascin, multsignin,
  output bad
);
  wire [3:0] mismatch;
  genvar mode;
  generate for (mode = 0; mode < 4; mode = mode + 1) begin: modes
    wire [29:0] acout;
    wire [17:0] bcout;
    DSP48E1 #(
      .A_INPUT((mode & 1) ? "CASCADE" : "DIRECT"),
      .B_INPUT((mode & 2) ? "CASCADE" : "DIRECT"),
      .AREG(0), .BREG(0), .ACASCREG(0), .BCASCREG(0),
      .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(0),
      .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
      .CARRYINREG(0), .CARRYINSELREG(0)
    ) dsp(
      .A(a), .ACIN(acin), .B(b), .BCIN(bcin), .C(c), .D(d), .PCIN(pcin),
      .OPMODE(opmode), .INMODE(inmode), .ALUMODE(alumode),
      .CARRYINSEL(carryinsel), .CARRYIN(carryin), .CARRYCASCIN(carrycascin),
      .MULTSIGNIN(multsignin), .CLK(1'b0), .ACOUT(acout), .BCOUT(bcout)
    );
    assign mismatch[mode] = (acout != ((mode & 1) ? acin : a)) ||
                           (bcout != ((mode & 2) ? bcin : b));
  end endgenerate
  assign bad = |mismatch;
endmodule
