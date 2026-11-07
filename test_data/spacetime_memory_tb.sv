// Finite passive-observation witness for the existing synchronous RAM primitive.
// Two four-bit lanes implement an eight-bit word with independently enabled nibbles.
// The extra result register makes a request sampled at C observable before edge C+2.
// This exercises RTL semantics; it does not establish native BRAM inference or timing.
module spacetime_memory_fixture (
    input wire clk, reset,
    input wire read_enable, read_address,
    input wire write_enable, write_address,
    input wire [7:0] write_data, write_mask,
    output wire result_valid,
    output reg [7:0] result_data
);
    wire [7:0] ram_data;
    reg read_pending = 0;
    reg delayed_valid = 0;
    assign result_valid = !reset && delayed_valid;

    hls_1r1w_ram #(.WIDTH(4), .ADDRESS_WIDTH(1)) low_lane (
        .clk(clk), .rd_addr(read_address), .rd_en(!reset && read_enable),
        .rd_data(ram_data[3:0]), .wr_addr(write_address),
        .wr_data(write_data[3:0]), .wr_en(!reset && write_enable && |write_mask[3:0])
    );
    hls_1r1w_ram #(.WIDTH(4), .ADDRESS_WIDTH(1)) high_lane (
        .clk(clk), .rd_addr(read_address), .rd_en(!reset && read_enable),
        .rd_data(ram_data[7:4]), .wr_addr(write_address),
        .wr_data(write_data[7:4]), .wr_en(!reset && write_enable && |write_mask[7:4])
    );

    // Reset retires pending responses; neither RAM lane has a reset input.
    always @(posedge clk) begin
        if (reset) begin
            read_pending <= 0;
            delayed_valid <= 0;
        end else begin
            read_pending <= read_enable;
            delayed_valid <= read_pending;
            if (read_pending) result_data <= ram_data;
        end
    end
endmodule

module spacetime_memory_tb;
    reg clk = 0, reset = 1;
    reg read_enable = 0, read_address = 0;
    reg write_enable = 0, write_address = 0;
    reg [7:0] write_data = 0, write_mask = 0;
    wire result_valid;
    wire [7:0] result_data;
    spacetime_memory_fixture dut(.*);
    integer trace, cycle;
    string trace_path;
    string observed_result_term;
    reg [7:0] old0, old1, new0, new1, observed_result;
    reg observed_valid;

    // Unknown power-on RAM contents stay explicit rather than becoming invented zeros.
    function automatic string word_term(input reg [7:0] value);
        if ($isunknown(value)) word_term = "unknown";
        else word_term = $sformatf("16#%02h", value);
    endfunction

    // Only whole-nibble masks are supported by this two-lane fixture.
    task automatic drive(input integer c);
        begin
            reset = c < 2 || c == 11;
            read_enable = 0; read_address = 0;
            write_enable = 0; write_address = 0;
            write_data = 0; write_mask = 0;
            case (c)
                2, 3: begin write_enable = 1; write_data = 8'ha5; write_mask = 8'hff; end
                5: begin
                    write_enable = 1; write_data = 8'h03; write_mask = 8'h0f;
                    read_enable = 1;
                end
                6: begin
                    write_enable = 1; write_address = 1;
                    write_data = 8'h5a; write_mask = 8'hff;
                end
                7: read_enable = 1;
                8: begin
                    write_enable = 1; write_data = 8'hc0; write_mask = 8'hf0;
                    read_enable = 1; read_address = 1;
                end
                9, 12: read_enable = 1;
                10: begin read_enable = 1; read_address = 1; end
                13: begin
                    write_enable = 1; write_address = 1;
                    write_data = 8'h5a; write_mask = 8'hff;
                    read_enable = 1; read_address = 1;
                end
                default: begin end
            endcase
        end
    endtask

    // Record every clock's controls and before/after contents without driving RAM state.
    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path)) $fatal(1, "TRACE path required");
        trace = $fopen(trace_path, "w");
        if (!trace) $fatal(1, "cannot create trace");
        for (cycle = 0; cycle < 17; cycle = cycle + 1) begin
            clk = 0;
            drive(cycle);
            #1;
            old0 = {dut.high_lane.memory[0], dut.low_lane.memory[0]};
            old1 = {dut.high_lane.memory[1], dut.low_lane.memory[1]};
            observed_valid = result_valid;
            observed_result = result_data;
            if (observed_valid) observed_result_term = word_term(observed_result);
            else observed_result_term = "unknown";
            clk = 1;
            #1;
            new0 = {dut.high_lane.memory[0], dut.low_lane.memory[0]};
            new1 = {dut.high_lane.memory[1], dut.low_lane.memory[1]};
            $fdisplay(trace,
                "#{cycle => %0d, reset => %0d, read_enable => %0d, read_address => %0d, write_enable => %0d, write_address => %0d, write_data => 16#%02h, write_mask => 16#%02h, old => [%s,%s], new => [%s,%s], result_valid => %0d, result_data => %s}.",
                cycle, reset, read_enable, read_address, write_enable, write_address,
                write_data, write_mask, word_term(old0), word_term(old1), word_term(new0),
                word_term(new1), observed_valid,
                observed_result_term);
        end
        $fdisplay(trace, "#{end_cycle => 17, rows => 17, complete => true, collision => read_first}.");
        $fclose(trace);
        $display("SPACETIME_MEMORY_CAPTURE_PASS cycles=17");
        $finish;
    end
endmodule
