// Bounded conservation at the generated Service's public interface. Requests
// may contain arbitrary data, but need a previously accepted admission credit.
// Readiness and later resets are otherwise arbitrary. This is a safety check,
// not a fairness or eventual-progress proof.
module direct_admission_formal(
    input clk, reset, request_valid, admission_ready, egress_ready,
    input [127:0] request,
    output ok, legal);
    wire request_ready, admission, admission_valid, egress_valid;
    wire [135:0] egress;
    reg [2:0] balance = 0;
    reg initialized = 0;
    reg held_credit = 0, held_effect = 0;
    reg [135:0] previous_effect = 0;
    direct_admission_service dut (
        .clk(clk), .reset(reset), ._req_in(request), ._req_in_vld(request_valid),
        ._req_in_rdy(request_ready), ._egress_out(egress),
        ._egress_out_vld(egress_valid), ._egress_out_rdy(egress_ready),
        ._admission_out(admission), ._admission_out_vld(admission_valid),
        ._admission_out_rdy(admission_ready)
    );
    wire issued = admission_valid && admission_ready;
    wire accepted = request_valid && request_ready;
    assign legal = !initialized || reset || !request_valid || balance != 0;
    always @(posedge clk) begin
        initialized <= 1;
        if (reset) begin
            balance <= 0;
            held_credit <= 0;
            held_effect <= 0;
        end else begin
            balance <= balance + {2'b0, issued} - {2'b0, accepted};
            held_credit <= admission_valid && !admission_ready;
            held_effect <= egress_valid && !egress_ready;
        end
        previous_effect <= egress;
    end
    assign ok = !initialized || reset || (
        balance <= 1 && (!admission_valid || admission) &&
        (!held_credit || admission_valid) &&
        (!held_effect || (egress_valid && egress == previous_effect)));
endmodule
