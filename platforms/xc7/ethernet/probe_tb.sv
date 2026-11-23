`timescale 1ns/1ps
// Exercise the diagnostic generator/checker and coherent counter transfer using
// independent control/source clocks. The packet/PCS tests cover the actual wire.
module ethernet_probe_tb;
    reg clock=0, source=0, reset_n=0, stopped=0, enable=0, allow=1, corrupt=0;
    always #20 clock=!clock;
    always #4 if(!stopped) source=!source;
    wire valid,last,ready;
    wire [7:0] data;
    wire [31:0] sent,received,bad;
    wire [63:0] sampled;
    integer offset=0, frames=0;
    reg stalled=0;
    reg [8:0] held;
    wire [7:0] delivered=data ^ ((corrupt && offset==25) ? 8'h01 : 8'h00);
`ifdef MAPPED_PROBE
    ethernet_probe_traffic traffic(
`else
    ethernet_probe_traffic #(.GAP_CYCLES(40)) traffic(
`endif
        .tx_clock(source), .tx_reset_n(reset_n), .rx_clock(source), .rx_reset_n(reset_n), .enable(enable),
        .tx_valid(valid), .tx_last(last), .tx_data(data), .tx_ready(ready && allow),
        .rx_valid(valid && allow), .rx_last(last), .rx_data(delivered), .rx_ready(ready),
        .sent(sent), .received(received), .bad_frames(bad)
    );
`ifdef MAPPED_PROBE
    ethernet_snapshot snapshot(clock,source,reset_n,{bad,received},sampled);
`else
    ethernet_snapshot #(.WIDTH(64)) snapshot(clock,source,reset_n,{bad,received},sampled);
`endif
    // Header is an independent byte string, including network-order EtherType.
    localparam [111:0] HEADER=112'hffffffffffff02000000000188b5;
    always @(posedge source) if(reset_n) begin
        if(stalled && (!valid || {last,data}!==held)) $fatal(1,"producer changed held beat");
        stalled=valid && !allow; held={last,data};
        if(valid && allow) begin
            if(data !== (offset<14 ? HEADER[111-offset*8 -: 8] : (offset ^ 8'ha5)))
                $fatal(1,"probe pattern/header differs at %0d",offset);
            if(last !== (offset==63)) $fatal(1,"probe frame length");
            if(last) begin frames=frames+1; offset=0; end else offset=offset+1;
        end
    end
    initial begin
        repeat(8) @(negedge clock); reset_n=1; enable=1;
        wait(offset==20); @(negedge source); allow=0;
        repeat(12) @(negedge clock); allow=1;
        wait(frames==1); @(negedge source); enable=0;
        repeat(12) @(negedge clock);
        if(sent!=1 || received!=1 || bad!=0 || sampled!==64'h0000000000000001)
            $fatal(1,"good-frame counters/snapshot");
        corrupt=1; enable=1;
        wait(frames==2); @(negedge source); enable=0;
        repeat(12) @(negedge clock);
        if(sent!=2 || received!=2 || bad!=1 || sampled!==64'h0000000100000002)
            $fatal(1,"corruption/snapshot not observed");
        @(negedge source); stopped=1;
        repeat(20) @(negedge clock);
        if(sampled!==64'h0000000100000002) $fatal(1,"stopped clock corrupted snapshot");
        reset_n=0; repeat(4) @(negedge clock);
        if(sampled!==0) $fatal(1,"stopped source blocked snapshot reset");
        stopped=0; corrupt=0; offset=0; frames=0; stalled=0;
        repeat(8) @(negedge clock); reset_n=1; enable=1;
        wait(frames==1); @(negedge source); enable=0;
        repeat(12) @(negedge clock);
        if(sampled!==64'h0000000000000001) $fatal(1,"restart retained old counts");
        $display("PASS: probe frame header/pattern, stalls, corruption, coherent snapshots and stopped-source reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"probe timeout"); end
endmodule
