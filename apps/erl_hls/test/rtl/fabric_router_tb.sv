`timescale 1ns/1ps
// Public-port scoreboards: arbitrary payload/keep, changing return addresses,
// gaps inside packets, independent stalls, non-contiguous IDs, and later reset.
module fabric_router_tb;
    parameter integer PORTS = 3;
    parameter integer PACKETS = 100;
    parameter integer CONTINUOUS = 0;
    function automatic [16*PORTS-1:0] ids;
        integer p;
        begin for (p=0; p<PORTS; p=p+1) ids[16*p+:16]=7+13*p; end
    endfunction
    localparam [16*PORTS-1:0] ENDPOINTS = ids();
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [31:0] random_state=32'h983791a2;
    function automatic [31:0] step(input [31:0] x);
        reg [31:0] y;
        begin y=x^(x<<13); y=y^(y>>17); step=y^(y<<5); end
    endfunction
    reg [32*PORTS-1:0] s_data=0;
    reg [4*PORTS-1:0] s_keep=0;
    reg [PORTS-1:0] s_last=0, s_valid=0;
    reg [16*PORTS-1:0] s_destination=0;
    wire [PORTS-1:0] s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_last, m_valid;
    reg m_ready=0;
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) mux(.*);

    integer packet[0:PORTS-1], beat[0:PORTS-1], gap[0:PORTS-1];
    integer waiting[0:PORTS-1], completed[0:PORTS-1];
    reg pending[0:PORTS-1];
    reg [PORTS-1:0] accepted=0;
    // The DUT may accept only its one first-beat register ahead of output.
    reg [36:0] saved;
    reg saved_valid=0;
    reg [15:0] destination;
    integer owner=-1, route_count=0, accepted_count=0, emitted_count=0;
    integer p, count, first_port, cycle=0, epochs=0, body_gaps=0, stalls=0;
    reg need_route=0, held=0;
    reg [36:0] held_word;
    function automatic integer length(input integer port, input integer frame);
        length = 1 + (frame*7+port*3)%17;
    endfunction
    function automatic [31:0] word(input integer port, input integer frame, input integer offset);
        word = (port<<24) | (frame<<8) | offset;
    endfunction
    always @(posedge clk) begin
        cycle=cycle+1;
        accepted=s_valid & s_ready;
        if (reset) begin
            owner=-1; need_route=0; saved_valid=0; held=0;
            route_count=0; accepted_count=0; emitted_count=0;
            for(p=0;p<PORTS;p=p+1) begin
                packet[p]=0;beat[p]=0;gap[p]=p;waiting[p]=0;pending[p]=0;completed[p]=0;
            end
        end else begin
            if (held && (!m_valid || {m_last,m_keep,m_data} !== held_word))
                $fatal(1,"stalled mux output changed");
            held=m_valid && !m_ready;held_word={m_last,m_keep,m_data};
            if(held) stalls=stalls+1;
            count=0;first_port=-1;
            for(p=0;p<PORTS;p=p+1) begin
                if(s_valid[p] && beat[p]==0 && !pending[p]) begin pending[p]=1;waiting[p]=0;end
                if(s_valid[p] && s_ready[p]) begin
                    count=count+1;accepted_count=accepted_count+1;
                    if(owner==-1) begin
                        owner=p;first_port=p;need_route=1;
                        destination=s_destination[16*p+:16];
                        route_count=route_count+1;pending[p]=0;
                    end else if(owner!=p) $fatal(1,"packet interleaved from %0d into %0d",p,owner);
                    if(saved_valid) $fatal(1,"more than one accepted beat buffered");
                    saved={s_last[p],s_keep[4*p+:4],s_data[32*p+:32]};saved_valid=1;
                    if(saved[36]) begin packet[p]=packet[p]+1;beat[p]=0;end
                    else beat[p]=beat[p]+1;
                    random_state=step(random_state);gap[p]=CONTINUOUS ? 0 : random_state%5;
                end
            end
            if(CONTINUOUS && owner>=0 && first_port<0 && !m_valid)
                $fatal(1,"bubble inside an available packet");
            if(count>1) $fatal(1,"multiple accepted inputs");
            if(m_valid && m_ready) begin
                if(owner<0) $fatal(1,"unowned output");
                if(need_route) begin
                    if({m_last,m_keep,m_data} !== {1'b0,4'hf,ENDPOINTS[16*owner+:16],destination})
                        $fatal(1,"route changed or wrong");
                    need_route=0;
                end else begin
                    if(!saved_valid || {m_last,m_keep,m_data} !== saved)
                        $fatal(1,"lost, duplicated, reordered or corrupted beat");
                    saved_valid=0;emitted_count=emitted_count+1;
                    if(m_last) begin
                        completed[owner]=completed[owner]+1;
                        for(p=0;p<PORTS;p=p+1) if(pending[p]) begin
                            waiting[p]=waiting[p]+1;
                            // A request can appear during an already-owned packet.
                            if(waiting[p]>PORTS) $fatal(1,"packet fairness bound exceeded");
                        end
                        owner=-1;
                    end
                end
            end
            if(owner>=0 && !need_route && !saved_valid && !s_valid[owner]) body_gaps=body_gaps+1;
            if(accepted_count-emitted_count != (saved_valid?1:0)) $fatal(1,"beat conservation");
        end
    end
    // Independent producers obey hold-until-ready, including first-beat route
    // metadata. All stimulus changes happen on falling edges.
    integer done;
    always @(negedge clk) begin
        if(reset) begin s_valid=0; m_ready=0; end
        else begin
            random_state=step(random_state);m_ready=CONTINUOUS || (random_state%4!=0);
            for(p=0;p<PORTS;p=p+1) begin
                if(s_valid[p] && !accepted[p]) begin end
                else begin
                    s_valid[p]=packet[p]<PACKETS && gap[p]==0;
                    if(gap[p]>0) gap[p]=gap[p]-1;
                    s_data[32*p+:32]=word(p,packet[p],beat[p]);
                    s_keep[4*p+:4]=(packet[p]+beat[p])%16;
                    s_last[p]=beat[p]+1==length(p,packet[p]);
                    s_destination[16*p+:16]=16'h8000+packet[p]*PORTS+p;
                end
            end
        end
    end
    // Ingress has an independent driver and scoreboard, so mux fairness cannot
    // hide an ingress rejection or wrong endpoint. Payload keep is not a filter.
    reg [31:0] in_data=0;
    reg [3:0] in_keep=15;
    reg in_last=0,in_valid=0;
    wire in_ready,out_last;
    wire [31:0] out_data;
    wire [3:0] out_keep;
    wire [15:0] out_source;
    wire [PORTS-1:0] out_valid;
    reg [PORTS-1:0] out_ready=0;
    wire [1:0] route_error;
    hls_fabric_ingress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) demux(
        .clk(clk),.reset(reset),.s_data(in_data),.s_keep(in_keep),.s_last(in_last),
        .s_valid(in_valid),.s_ready(in_ready),.m_data(out_data),.m_keep(out_keep),
        .m_last(out_last),.m_source(out_source),.m_valid(out_valid),.m_ready(out_ready),
        .route_error(route_error));
    integer selected=-1, input_packets=0, rejected=0, delivered=0, n,j,kind,target;
    reg address=1;
    reg [15:0] source;
    reg [1:0] expected_error;
    always @(negedge clk) out_ready={PORTS{1'b1}} ^ (1 << (cycle%(PORTS+2)));
    always @(posedge clk) begin
        if(reset) begin address=1;selected=-1;end
        else begin
            if(in_valid && in_ready) begin
                if(address) begin
                    selected=-1;source=in_data[31:16];
                    for(integer k=0;k<PORTS;k=k+1)
                        if(in_data[15:0]==ENDPOINTS[16*k+:16]) selected=k;
                    expected_error=in_keep!=15 ? 1 : in_last ? 3 : selected<0 ? 2 : 0;
                    if(route_error!==expected_error) $fatal(1,"route error mismatch");
                    if(expected_error!=0) begin selected=-1;rejected=rejected+1;end
                    if(out_valid!=0) $fatal(1,"routing beat leaked");
                    input_packets=input_packets+1;
                end else if(selected>=0) begin
                    if(out_valid !== (1<<selected) || !out_ready[selected] ||
                        {out_last,out_keep,out_data,out_source} !== {in_last,in_keep,in_data,source})
                        $fatal(1,"ingress corruption or wrong destination");
                    delivered=delivered+1;
                end else if(out_valid!=0) $fatal(1,"rejected packet leaked");
                address=in_last;
            end
            if((out_valid & out_ready)!=0 && !(in_valid && in_ready)) $fatal(1,"invented input");
        end
    end
    task automatic send(input [31:0] data,input [3:0] keep,input last);
        begin
            @(negedge clk);in_data=data;in_keep=keep;in_last=last;in_valid=1;
            @(posedge clk);while(!in_ready) @(posedge clk);
            @(negedge clk);in_valid=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        // Reset during every early traffic phase, including owned/stalled frames.
        for(epochs=0;epochs<12;epochs=epochs+1) begin
            repeat(11+epochs) @(negedge clk);
            reset=1;repeat(2) @(negedge clk);reset=0;
        end
        for(n=0;n<300;n=n+1) begin
            kind=n%5;target=n%PORTS;
            send({16'h4200+n[15:0],kind==1 ? 16'hffff : ENDPOINTS[16*target+:16]},
                 kind==2 ? 4'h3 : 4'hf,kind==3);
            if(kind!=3) for(j=0;j<(kind==4 ? 257 : 1+n%9);j=j+1)
                send(j, j%16, j+1==(kind==4 ? 257 : 1+n%9));
        end
        // Abandon an unterminated ingress packet; next route starts only on reset.
        send(32'h0042ffff,15,0);send(ENDPOINTS[15:0],15,0);
        @(negedge clk);reset=1;repeat(2) @(negedge clk);reset=0;
        send({16'habcd,ENDPOINTS[15:0]},15,0);send(32'habcdef01,15,1);
        done=0;
        while(!done) begin
            @(negedge clk);done=owner==-1;
            for(integer k=0;k<PORTS;k=k+1) if(completed[k]!=PACKETS) done=0;
        end
        if((!CONTINUOUS && (body_gaps==0 || stalls==0)) || rejected!=181 || delivered==0)
            $fatal(1,"missing exercise: gaps=%0d stalls=%0d rejects=%0d",body_gaps,stalls,rejected);
        $display("PASS: %0d ports, %0d outgoing packets, %0d routed inputs, %0d rejects, %0d beats; gaps/stalls/reset/fairness",PORTS,PORTS*PACKETS,input_packets,rejected,emitted_count);
        $finish;
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
