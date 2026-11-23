`timescale 1ns/1ps
module return_routes_tb;
    parameter integer SLOTS=3;
    parameter integer CAST_TXID=255;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [31:0] s_data=0, reply_data=0;
    reg [3:0] s_keep=15, reply_keep=15;
    reg s_last=0, s_valid=0, request_ready=1;
    reg reply_last=0, reply_valid=0, m_ready=1;
    reg [15:0] s_source=0;
    wire s_ready, request_last, request_valid, reply_ready, m_last, m_valid;
    wire [31:0] request_data,m_data;
    wire [3:0] request_keep,m_keep;
    wire [15:0] m_destination;
    wire [SLOTS-1:0] context_busy;
    wire dropped_reply;
    integer slots[0:SLOTS-1];
    integer slot, extra, before_count, drops=0;
    reg [31:0] offered;
    hls_return_routes #(.SLOTS(SLOTS),.CAST_TXID(CAST_TXID)) dut(.*);
    always @(negedge clk) if(dropped_reply) drops=drops+1;
    initial begin #1000000; $fatal(1,"timeout"); end

    task request(input integer source, tx, words, output integer allocated);
        @(negedge clk);
        s_data={8'h05,8'h00,8'(tx),8'(words)};s_source=source;
        s_last=words==0;s_valid=1;
        do @(posedge clk); while(!s_ready);
        if(!request_valid || request_keep!=15 || request_last!=(words==0)) $fatal(1,"request handshake");
        allocated=request_data[15:8];
        if(request_data[31:16]!=16'h0500 || request_data[7:0]!=words) $fatal(1,"request header");
        for(integer n=0;n<words;n=n+1) begin
            @(negedge clk);s_data=32'hcafe0000+n;s_last=n==words-1;
            do @(posedge clk); while(!s_ready);
            if(request_data!=s_data || request_last!=s_last) $fatal(1,"request payload");
        end
        @(negedge clk);s_valid=0;s_last=0;
    endtask

    task response(input integer allocated, source, tx, words, discard);
        @(negedge clk);
        reply_data={8'h85,8'h00,8'(allocated),8'(words)};
        reply_last=words==0;reply_valid=1;m_ready=0;
        if(!discard) begin
            repeat(2) begin
                @(posedge clk);
                if(reply_ready || !m_valid || m_destination!=source ||
                    m_data!={8'h85,8'h00,8'(tx),8'(words)}) $fatal(1,"stalled response identity");
            end
            @(negedge clk);m_ready=1;
        end
        do @(posedge clk); while(!reply_ready);
        if(discard ? m_valid : (!m_valid || m_destination!=source || m_data[15:8]!=tx))
            $fatal(1,"response identity/drop");
        for(integer n=0;n<words;n=n+1) begin
            @(negedge clk);reply_data=32'hface0000+n;reply_last=n==words-1;
            if(!discard) m_ready=0;
            @(posedge clk);
            if(!discard && (!m_valid || m_data!=reply_data || m_destination!=source)) $fatal(1,"response payload stall");
            if(discard && m_valid) $fatal(1,"discard payload");
            if(!discard) begin
                @(negedge clk);m_ready=1;
                do @(posedge clk); while(!reply_ready);
            end
        end
        @(negedge clk);reply_valid=0;reply_last=0;m_ready=1;
    endtask

    initial begin
        repeat(3) @(posedge clk);
        @(negedge clk);reset=0;
        // Same caller TXID on every route; service wire IDs must remain unique.
        for(integer n=0;n<SLOTS;n=n+1) begin
            request(n+1,0,n%3,slots[n]);
            if(slots[n]!=n) $fatal(1,"allocation collision");
        end
        if(context_busy!={SLOTS{1'b1}}) $fatal(1,"capacity");
        if(CAST_TXID>=0) begin
            request(700,CAST_TXID,2,extra);
            if(extra!=CAST_TXID || context_busy!={SLOTS{1'b1}}) $fatal(1,"cast reserved slot");
            before_count=drops;
            response(CAST_TXID,0,0,1,1);
            if(drops!=before_count+1) $fatal(1,"cast error not drained");
        end
        // Full capacity backpressures a new header. A completion makes it
        // eligible only after the old response's final accepted beat.
        fork
            begin request(900,77,1,slot); end
            begin
                repeat(3) @(posedge clk);
                if(s_ready || request_valid) $fatal(1,"accepted with full context table");
                response(slots[SLOTS-1],SLOTS,0,2,0);
            end
        join
        if(slot!=SLOTS-1) $fatal(1,"wrong reclaimed slot");
        response(slot,900,77,0,0);
        for(integer n=SLOTS-2;n>=0;n=n-1) response(slots[n],n+1,0,n%3,0);
        if(context_busy!=0) $fatal(1,"context leak");

        if(SLOTS>=3) begin
            request(11,41,0,slots[0]);
            request(12,42,1,slots[1]);
            request_ready=0;
            fork
                begin request(13,43,0,slot); end
                begin
                    repeat(3) @(posedge clk);
                    offered=request_data;
                    if(offered[15:8]!=2) $fatal(1,"wrong offered slot");
                    response(slots[0],11,41,0,0);
                    repeat(3) begin
                        @(posedge clk);
                        if(request_data!=offered || !request_valid) $fatal(1,"offered header changed under stall");
                    end
                    @(negedge clk);request_ready=1;
                end
            join
            if(slot!=2) $fatal(1,"offered slot not retained");
            response(slot,13,43,2,0);
            response(slots[1],12,42,1,0);
        end
        // On a debug stream 255 is an ordinary caller transaction ID.
        request(65535,CAST_TXID<0 ? 255 : 254,2,slot);
        response(slot,65535,CAST_TXID<0 ? 255 : 254,2,0);
        request(55,66,1,slot);
        @(negedge clk);reset=1;
        @(posedge clk);@(negedge clk);reset=0;
        if(context_busy!=0) $fatal(1,"reset context");
        before_count=drops;
        response(slot,0,0,2,1);
        if(drops!=before_count+1) $fatal(1,"unowned reply not drained");
        request(99,88,0,slot);response(slot,99,88,0,0);
        $display("PASS: %0d contexts, CAST_TXID=%0d; same-TXID origins, capacity, backpressure, reorder, casts, reset",SLOTS,CAST_TXID);
        $finish;
    end
endmodule
