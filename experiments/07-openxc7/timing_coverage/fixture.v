// Compile-only timing probes. MODE chooses FF logic, synchronous BRAM,
// registered BRAM, a combinational DSP, a pipelined DSP, or BRAM feeding DSP.
// The clock and activity pins are the same two-pin harness as phi_timing.py.
module timing_coverage_fixture #(parameter MODE = 0)(
    input wire clock,
    output wire activity
);
    reg [31:0] flow = 32'h12345678;
    (* keep = "true" *) reg [31:0] argument = 0;
    reg [47:0] digest = 0;
    wire [47:0] result;
    always @(posedge clock) begin
        flow <= {flow[30:0], flow[31]^flow[21]^flow[1]^flow[0]};
        argument <= flow ^ {flow[15:0], flow[31:16]};
        digest <= {digest[46:0], digest[47]} ^ result;
    end
    generate
        if (MODE == 0) begin: logic_probe
            assign result = {16'd0, argument + flow};
        end else begin: hard_probe
            wire [31:0] memory_value;
            if (MODE == 1 || MODE == 2 || MODE == 5) begin: ram_probe
                // Read on B and write on A; DOB_REG selects the optional
                // hard output register rather than a fabric FF after the RAM.
                RAMB36E1 #(
                    .RAM_MODE("TDP"), .READ_WIDTH_A(0), .WRITE_WIDTH_A(36),
                    .READ_WIDTH_B(36), .WRITE_WIDTH_B(0),
                    .DOA_REG(0), .DOB_REG(MODE == 2),
                    .WRITE_MODE_A("READ_FIRST"), .WRITE_MODE_B("READ_FIRST")
                ) memory (
                    .CLKARDCLK(clock), .CLKBWRCLK(clock),
                    .ADDRARDADDR({1'b0, flow[9:0], 5'd0}),
                    .ADDRBWRADDR({1'b0, flow[19:10], 5'd0}),
                    .DIADI(argument), .DIPADIP(4'd0), .DIBDI(32'd0), .DIPBDIP(4'd0),
                    .DOBDO(memory_value), .WEA({4{flow[31]}}), .WEBWE(8'd0),
                    .ENARDEN(1'b1), .ENBWREN(1'b1), .REGCEAREGCE(1'b1), .REGCEB(1'b1),
                    .RSTRAMARSTRAM(1'b0), .RSTRAMB(1'b0), .RSTREGARSTREG(1'b0), .RSTREGB(1'b0),
                    .CASCADEINA(1'b0), .CASCADEINB(1'b0),
                    .INJECTDBITERR(1'b0), .INJECTSBITERR(1'b0)
                );
            end else begin: no_ram
                assign memory_value = argument;
            end
            if (MODE == 1 || MODE == 2) begin: ram_result
                assign result = {16'd0, memory_value};
            end else begin: dsp_probe
                // Explicit modes keep this a test of endpoint coverage, rather
                // than of synthesis's choice to absorb external registers.
                DSP48E1 #(
                    .AREG(0), .BREG(0), .ACASCREG(0), .BCASCREG(0),
                    .CREG(0), .DREG(0), .ADREG(0),
                    .MREG(MODE == 4), .PREG(MODE == 4),
                    .ALUMODEREG(0), .CARRYINREG(0), .CARRYINSELREG(0),
                    .INMODEREG(0), .OPMODEREG(0),
                    .USE_MULT("MULTIPLY"), .USE_SIMD("ONE48")
                ) multiplier (
                    .CLK(clock), .A({{5{memory_value[24]}}, memory_value[24:0]}),
                    .B(flow[17:0]), .C(48'd0), .D(25'd0), .P(result),
                    .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
                    .OPMODE(7'b0000101), .ALUMODE(4'd0), .INMODE(5'd0),
                    .CARRYIN(1'b0), .CARRYCASCIN(1'b0), .CARRYINSEL(3'd0), .MULTSIGNIN(1'b0),
                    .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1),
                    .CEC(1'b1), .CED(1'b1), .CEAD(1'b1), .CEM(1'b1), .CEP(1'b1),
                    .CEALUMODE(1'b1), .CECARRYIN(1'b1), .CECTRL(1'b1), .CEINMODE(1'b1),
                    .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTD(1'b0),
                    .RSTM(1'b0), .RSTP(1'b0), .RSTALUMODE(1'b0),
                    .RSTALLCARRYIN(1'b0), .RSTCTRL(1'b0), .RSTINMODE(1'b0)
                );
            end
        end
    endgenerate
    assign activity = digest[0];
endmodule
