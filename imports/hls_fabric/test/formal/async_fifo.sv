module async_fifo_formal;
    (* anyseq *) reg wr_clk, rd_clk, reset;
    (* anyseq *) reg in_valid, out_ready;
    (* anyseq *) reg [1:0] in_data;
    reg [1:0] expected [0:7];
    reg [2:0] written = 0, consumed = 0;
    wire [1:0] out_data;
    wire in_ready, out_valid;
    reg started = 0;
    wire [2:0] queued = written - consumed;
    always @($global_clock) begin
        started <= 1;
        if (!started) assume(reset);
    end
    hls_async_fifo #(.WIDTH(2), .ADDR_BITS(2)) dut(.*);
    always @(posedge wr_clk or posedge reset)
        if (reset) written <= 0;
        else if (in_valid && in_ready) begin
            expected[written] <= in_data;
            written <= written + 1;
        end
    always @(posedge rd_clk or posedge reset)
        if (reset) consumed <= 0;
        else if (out_valid && out_ready) consumed <= consumed + 1;
    always @(posedge rd_clk) if (started && !reset && out_valid) begin
        assert(queued != 0);
        assert(out_data == expected[consumed]);
    end
    always @($global_clock) if (started) begin
        if (!reset) assert(queued <= 4);
        if (reset) begin
            assert(!in_ready);
            assert(!out_valid);
        end
        cover(written == 6 && consumed == 5);
    end
endmodule
