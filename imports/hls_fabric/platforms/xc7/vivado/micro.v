// Compile-only timing corpus: registered logic, two BRAM output modes and
// combinational/pipelined signed multiplication. Every result feeds activity.
module timing_micro(input wire clock, output wire activity);
    reg [31:0] flow = 32'h12345678;
    (* keep = "true" *) reg [31:0] arithmetic = 0;
    (* ram_style = "block" *) reg [31:0] memory [0:1023];
    (* ram_style = "block" *) reg [31:0] registered_memory [0:1023];
    reg [31:0] read_plain, read_stage, read_registered;
    (* keep = "true" *) reg signed [24:0] a = 1;
    (* keep = "true" *) reg signed [17:0] b = 1;
    reg signed [24:0] pipeline_a = 1;
    reg signed [17:0] pipeline_b = 1;
    (* use_dsp = "yes", keep = "true" *) wire signed [42:0] product = a * b;
    (* use_dsp = "yes" *) reg signed [42:0] pipelined_product;
    reg signed [42:0] pipeline_output;
    reg [31:0] digest = 0;
    always @(posedge clock) begin
        flow <= {flow[30:0], flow[31]^flow[21]^flow[1]^flow[0]};
        arithmetic <= (arithmetic + flow) ^ {flow[15:0], flow[31:16]};
        if (flow[28]) memory[flow[9:0]] <= arithmetic;
        if (flow[29]) registered_memory[flow[19:10]] <= flow;
        read_plain <= memory[flow[19:10]];
        read_stage <= registered_memory[flow[9:0]];
        read_registered <= read_stage;
        a <= arithmetic[24:0];
        b <= flow[17:0];
        pipeline_a <= arithmetic[24:0] ^ 25'h15234;
        pipeline_b <= flow[17:0] ^ 18'h278;
        pipelined_product <= pipeline_a * pipeline_b;
        pipeline_output <= pipelined_product;
        digest <= {digest[30:0],digest[31]} ^ arithmetic ^ read_plain ^ read_registered ^
                  product[31:0] ^ {21'b0,product[42:32]} ^
                  pipeline_output[31:0] ^ {21'b0,pipeline_output[42:32]};
    end
    assign activity = digest[0];
endmodule
