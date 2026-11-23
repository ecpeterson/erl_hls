// Imported two-output LUT placement with an explicit shared pin assignment.
// MODE=7 ties several inputs high to exercise merged logical input origins.
module lut_legality_fixture #(parameter MODE=6)(
    input wire clock, output wire activity
);
    reg [4:0] q=5'b10101;
    always @(posedge clock) q <= {q[3:0],q[4]^q[1]};
    wire a, b, qa, qb;
    (* keep, BEL="SLICE_X4Y99/A5LUT" *) LUT5 #(.INIT(32'h6789ef01)) low(
        .I0(q[0]), .I1(MODE==7 ? 1'b1 : q[1]), .I2(MODE==7 ? 1'b1 : q[2]),
        .I3(MODE==7 ? 1'b1 : q[3]), .I4(MODE==7 ? 1'b1 : q[4]), .O(a));
    (* keep, BEL="SLICE_X4Y99/A6LUT" *) LUT6 #(.INIT(64'h12ab45cd00000000)) high(
        .I0(q[0]), .I1(MODE==7 ? 1'b1 : q[1]), .I2(MODE==7 ? 1'b1 : q[2]),
        .I3(MODE==7 ? 1'b1 : q[3]), .I4(MODE==7 ? 1'b1 : q[4]), .I5(1'b1), .O(b));
    (* keep *) FDRE low_ff(.C(clock), .CE(1'b1), .R(1'b0), .D(a), .Q(qa));
    (* keep *) FDRE high_ff(.C(clock), .CE(1'b1), .R(1'b0), .D(b), .Q(qb));
    assign activity=^{q,qa,qb};
endmodule
