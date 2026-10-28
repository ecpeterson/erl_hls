// Closed sequential placement fixture. MODE selects five/six-input logic,
// dual-output LUTs, carry logic, distributed RAM, or shift registers. Kept
// primitives prevent the synthesizer from replacing the resource under test.
module lut_legality_fixture #(parameter MODE=0, N=64)(
    input wire clock, output wire activity
);
    wire [N-1:0] q, d, extra;
    genvar i;
    generate for(i=0;i<N;i=i+1) begin: lane
        (* keep *) FDRE #(.INIT(i%2)) state_ff(
            .C(clock), .CE(1'b1), .R(1'b0), .D(d[i]), .Q(q[i]));
        if (MODE==1) begin: six
            (* keep *) LUT6 #(.INIT(64'h12ab45cd6789ef01)) logic_lut(
                .I0(q[(i+1)%N]), .I1(q[(i+3)%N]), .I2(q[(i+7)%N]),
                .I3(q[(i+15)%N]), .I4(q[(i+31)%N]), .I5(q[(i+47)%N]), .O(d[i]));
            assign extra[i]=0;
        end else if (MODE==2) begin: dual
            wire other;
            (* keep *) LUT6_2 #(.INIT(64'h12ab45cd6789ef01)) logic_lut(
                .I0(q[(i+1)%N]), .I1(q[(i+3)%N]), .I2(q[(i+7)%N]),
                .I3(q[(i+15)%N]), .I4(q[(i+31)%N]), .I5(1'b1), .O5(d[i]), .O6(other));
            (* keep *) FDRE other_ff(.C(clock), .CE(1'b1), .R(1'b0), .D(other), .Q(extra[i]));
        end else if (MODE==4) begin: ram
            (* keep *) RAM32X1D #(.INIT(32'h12345678)) storage(
                .A0(q[(i+1)%N]), .A1(q[(i+3)%N]), .A2(q[(i+7)%N]),
                .A3(q[(i+15)%N]), .A4(q[(i+31)%N]),
                .DPRA0(q[(i+2)%N]), .DPRA1(q[(i+4)%N]), .DPRA2(q[(i+8)%N]),
                .DPRA3(q[(i+16)%N]), .DPRA4(q[(i+32)%N]),
                .WCLK(clock), .WE(q[(i+5)%N]), .D(q[(i+6)%N]), .SPO(d[i]), .DPO(extra[i]));
        end else if (MODE==5) begin: srl
            (* keep *) SRLC32E #(.INIT(32'h12345678)) storage(
                .CLK(clock), .CE(1'b1), .D(q[(i+6)%N]),
                .A({q[(i+31)%N],q[(i+15)%N],q[(i+7)%N],q[(i+3)%N],q[(i+1)%N]}),
                .Q(d[i]), .Q31());
            assign extra[i]=0;
        end else begin: five
            (* keep *) LUT5 #(.INIT(32'h6789ef01)) logic_lut(
                .I0(q[(i+1)%N]), .I1(q[(i+3)%N]), .I2(q[(i+7)%N]),
                .I3(q[(i+15)%N]), .I4(q[(i+31)%N]), .O(d[i]));
            assign extra[i]=0;
        end
    end endgenerate
    generate if (MODE==3) begin: carry
        reg [31:0] counter=1;
        always @(posedge clock) counter <= counter + 1;
        assign activity=^{q,extra,counter};
    end else begin: other
        assign activity=^{q,extra};
    end endgenerate
endmodule
