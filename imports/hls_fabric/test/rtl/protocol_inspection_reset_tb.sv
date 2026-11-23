// Finite public-port witness: common reset retires partial requests and stalled replies.
module tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [31:0] input_word=0;
    reg input_valid=0,input_last=0,output_ready=0;
    wire input_ready,output_valid,output_last;
    wire [31:0] output_word;
    wire [3:0] output_keep;
    reg [31:0] reply[0:14];
    reg [31:0] fingerprint[0:7];
    integer i;
    protocol_application_top dut(.clk(clk),.reset(reset),
        .s_app_tdata(32'd0),.s_app_tlast(1'b0),.s_app_tvalid(1'b0),.m_app_tready(1'b1),
        .s_dbg_tdata(input_word),.s_dbg_tkeep(4'hf),.s_dbg_tlast(input_last),.s_dbg_tvalid(input_valid),.s_dbg_tready(input_ready),
        .m_dbg_tdata(output_word),.m_dbg_tkeep(output_keep),.m_dbg_tlast(output_last),.m_dbg_tvalid(output_valid),.m_dbg_tready(output_ready));

    // Retire transport ownership together with application/debug registers, then reject stale replies.
    task restart;
        begin
            @(negedge clk);reset=1;input_valid=0;output_ready=0;
            repeat(3) @(negedge clk);
            reset=0;
            repeat(8) begin @(negedge clk);if(output_valid)$fatal(1,"reply survived reset");end
        end
    endtask

    // Preserve a beat until acceptance, with a finite bound on simulation progress.
    task send(input [31:0] word,input last);
        integer n;
        begin : sending
            @(negedge clk);input_word=word;input_last=last;input_valid=1;
            for(n=0;n<100;n=n+1)begin
                @(posedge clk);
                if(input_ready)begin @(negedge clk);input_valid=0;disable sending;end
            end
            $fatal(1,"debug input timeout");
        end
    endtask

    // One routed process query; transaction IDs distinguish retired and fresh incarnations.
    task query(input [7:0] transaction,input [31:0] resource);
        begin send(32'h00010002,0);send({8'h11,8'd0,transaction,8'd1},0);send(resource,1);end
    endtask

    // Require an actual held reply and stable public words while its reader stalls.
    task stalled;
        integer n;
        reg [31:0] held;
        reg held_last;
        begin : waiting
            for(n=0;n<100;n=n+1)begin
                @(negedge clk);
                if(output_valid)begin
                    held=output_word;held_last=output_last;
                    repeat(7)begin @(negedge clk);
                        if(!output_valid||output_word!==held||output_last!==held_last||output_keep!==15)
                            $fatal(1,"blocked debug reply changed");
                    end
                    disable waiting;
                end
            end
            $fatal(1,"debug reply timeout");
        end
    endtask

    // Retain the full public frame and exact last position with bounded receive time.
    task receive_frame(input integer count);
        integer n,k;
        begin : receiving
            k=0;@(negedge clk);output_ready=1;
            for(n=0;n<200;n=n+1)begin
                @(posedge clk);
                if(output_valid)begin
                    reply[k]=output_word;
                    if(output_keep!==15||output_last!==(k==count-1))$fatal(1,"reply framing");
                    k=k+1;
                    if(k==count)begin @(negedge clk);output_ready=0;disable receiving;end
                end
            end
            $fatal(1,"incomplete debug reply");
        end
    endtask

    initial begin
        @@FINGERPRINT@@
        restart();send(32'h00010002,0);restart();
        send(32'h00010002,0);send(32'h11000101,0);restart();
        query(2,0);stalled();restart();
        query(3,0);stalled();
        @(negedge clk);output_ready=1;repeat(2)@(posedge clk);
        @(negedge clk);output_ready=0;stalled();restart();
        send(32'h00010002,0);send(32'h10000500,1);receive_frame(15);
        if(reply[0]!==32'h00020001||reply[1]!==32'h9000050d||reply[2]!==5||reply[3]!==9||
           reply[4]!==0||reply[5]!==0||reply[6]!==9)$fatal(1,"fresh INFO mismatch");
        for(i=0;i<8;i=i+1)if(reply[7+i]!==fingerprint[i])$fatal(1,"fresh fingerprint mismatch");
        query(6,8);receive_frame(9);
        if(reply[0]!==32'h00020001||reply[1]!==32'h91000607||reply[2]!==8||
           !reply[5][25]||reply[5][24:9]!==0)$fatal(1,"fresh process query mismatch");
        repeat(8)begin @(negedge clk);if(output_valid)$fatal(1,"unexpected trailing reply");end
        $display("PROTOCOL_INSPECTION_RESET_PASS interruptions=4 fresh_info=1 fresh_query=1");$finish;
    end
    // No stalled or missing handshake may make this witness unbounded.
    initial begin #50000;$fatal(1,"reset witness horizon");end
endmodule
