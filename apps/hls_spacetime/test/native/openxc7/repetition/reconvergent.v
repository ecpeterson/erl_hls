// The launch FF feeds both mux arms. One arm traverses a carry before its LUT.
module top(input wire clock, output wire activity);
    wire q, d, short_arm, long_arm, ci, select_q;
    wire [3:0] carry;
    FDRE #(.INIT(1'b1)) launch (.C(clock), .D(d), .Q(q), .CE(1'b1), .R(1'b0));
    FDRE #(.INIT(1'b0)) select_ff (.C(clock), .D(q), .Q(select_q), .CE(1'b1), .R(1'b0));
    FDRE #(.INIT(1'b0)) carry_ff (.C(clock), .D(select_q), .Q(ci), .CE(1'b1), .R(1'b0));
    CARRY4 chain (.CI(1'b0), .CYINIT(ci), .DI({4{q}}), .S({4{select_q}}), .CO(carry));
    LUT2 #(.INIT(4'h6)) short_lut (.I0(q), .I1(select_q), .O(short_arm));
    LUT2 #(.INIT(4'h8)) long_lut (.I0(q), .I1(carry[3]), .O(long_arm));
    MUXF7 join_arms (.I0(short_arm), .I1(long_arm), .S(select_q), .O(d));
    assign activity = q;
endmodule
