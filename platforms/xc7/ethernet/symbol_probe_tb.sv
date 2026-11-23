// Exercise phase discovery, coherent snapshots and hard-align-like phase change.
module symbol_probe_tb;
    localparam [19:0] PATTERN = {10'h283, 10'h17c};
    reg clock=0, source_clock=0, reset_n=0, enable=0;
    reg [19:0] word=0;
    wire [31:0] raw_phase, words, patterns, aligned, swapped, phase_changes;
    wire fresh;
    always #20 clock=~clock;
    always #8 source_clock=~source_clock;

`ifdef MAPPED
    ethernet_symbol_probe_sample_mapped dut(
`else
    ethernet_symbol_probe_sample dut(
`endif
        .clock(clock), .source_clock(source_clock), .reset_n(reset_n), .enable(enable),
        .word(word), .raw_phase(raw_phase), .words(words), .patterns(patterns),
        .aligned(aligned), .swapped(swapped), .phase_changes(phase_changes), .fresh(fresh));

    function automatic [19:0] rotate(input [19:0] value, input integer amount);
        rotate = (value << amount) | (value >> (20-amount));
    endfunction

    reg [31:0] before_words, before_patterns, before_changes;
    initial begin
        #100; reset_n=1; enable=1; word=rotate(PATTERN,3);
        repeat(1000) @(posedge clock);
        if(!raw_phase[25] || raw_phase[24:20]==0 || raw_phase[24:20]==10)
            $fatal(1,"unaligned phase was not discovered: %h",raw_phase);
        if(patterns < words-8 || aligned || swapped || phase_changes)
            $fatal(1,"unexpected unaligned counters: %0d/%0d/%0d/%0d/%0d",
                   words,patterns,aligned,swapped,phase_changes);
        before_words=words; before_patterns=patterns; before_changes=phase_changes;
        word=PATTERN;
        repeat(1000) @(posedge clock);
        if(!raw_phase[25] || raw_phase[24:20]!=0 || raw_phase[19:0]!=PATTERN)
            $fatal(1,"aligned phase/raw word missing: %h",raw_phase);
        if(words-before_words<2000 || patterns-before_patterns<2000 || aligned<2000)
            $fatal(1,"aligned stream did not progress: %0d/%0d/%0d",
                   words-before_words,patterns-before_patterns,aligned);
        if(swapped || phase_changes-before_changes!=1)
            $fatal(1,"unexpected aligned orientation/change count: %0d/%0d",
                   swapped,phase_changes-before_changes);
        enable=0; repeat(20) @(posedge clock);
        if(raw_phase[25]) $fatal(1,"phase validity survived disabled measurement");
        $display("PASS: raw symbol phase, alignment counters and coherent snapshots");
        $finish;
    end
    initial begin #100000; $fatal(1,"symbol probe timeout"); end
endmodule
