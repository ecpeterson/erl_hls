// Two five-input functions share a physical LUT. Both register controls are exercised externally.
module top(input wire clock, enable, reset, output wire activity);
    wire [1:0] q, d;
    LUT6_2 #(.INIT(64'h3333333366666666)) functions (
        .I0(q[0]), .I1(q[1]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b1),
        .O5(d[0]), .O6(d[1]));
    FDRE #(.INIT(1'b0)) low (.C(clock), .CE(enable), .R(reset), .D(d[0]), .Q(q[0]));
    FDRE #(.INIT(1'b1)) high (.C(clock), .CE(enable), .R(reset), .D(d[1]), .Q(q[1]));
    assign activity = ^q;
endmodule
