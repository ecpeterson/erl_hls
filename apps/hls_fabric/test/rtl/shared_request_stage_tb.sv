// The production register must sustain II=1 and retain ownership through stalls.
module shared_request_stage_tb;
    reg clk=0, reset=1, input_valid=0, output_ready=0;
    reg [15:0] input_data=0;
    wire input_ready, output_valid;
    wire [15:0] output_data;
    always #5 clk=~clk;
    request_stage dut(.clk(clk), .reset(reset),
        ._input_request(input_data), ._input_request_vld(input_valid), ._input_request_rdy(input_ready),
        ._output_request(output_data), ._output_request_vld(output_valid), ._output_request_rdy(output_ready));

    // Discard a held activation exactly as the enclosing whole-design reset does.
    task clear;
        begin
            @(negedge clk); reset=1; input_valid=0; output_ready=0;
            repeat(3) @(negedge clk);
            reset=0;
            repeat(3) begin
                @(negedge clk);
                if (output_valid) $fatal(1,"stale activation after reset");
            end
        end
    endtask

    // Distinct payloads expose loss, duplication and replacement of held work.
    task exercise(input integer base, input integer stalled);
        integer sent, received, cycle, previous;
        begin
            sent=0; received=0; cycle=0; previous=-1;
            while (received<128 && cycle<2000) begin
                @(negedge clk);
                input_valid=(sent<128); input_data=base+sent;
                output_ready=!stalled || (cycle%3!=0 && !(cycle>=40 && cycle<90));
                @(posedge clk);
                if (input_valid && input_ready) sent=sent+1;
                if (output_valid && output_ready) begin
                    if (output_data!==16'(base+received)) $fatal(1,"out-of-order request %0d",received);
                    if (!stalled && previous>=0 && cycle!=previous+1) $fatal(1,"II exceeds one");
                    previous=cycle; received=received+1;
                end
                cycle=cycle+1;
            end
            if (received!=128 || sent!=128) $fatal(1,"lost request");
            @(negedge clk); input_valid=0; output_ready=1;
            repeat(10) begin
                @(negedge clk);
                if (output_valid) $fatal(1,"duplicate request after drain");
            end
        end
    endtask

    initial begin
        clear(); exercise(1000,0);
        @(negedge clk); input_data=16'hdead; input_valid=1; output_ready=0;
        repeat(8) @(negedge clk);
        clear(); exercise(2000,1);
        $display("PASS: request retention, II=1, stalls and reset");
        $finish;
    end
    initial begin #50000; $fatal(1,"request-stage timeout"); end
endmodule
