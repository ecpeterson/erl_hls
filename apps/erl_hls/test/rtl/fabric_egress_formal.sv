// Track ownership and the single accepted beat not yet emitted. Payload values
// and all stalls/gaps are arbitrary. A separate proved refinement invariant
// relates the public-port monitor to implementation state for induction.
module fabric_egress_formal #(
    parameter integer PORTS=3,
    parameter [16*PORTS-1:0] ENDPOINTS={16'd42,16'd9,16'd2}
)(input clk,reset,input [32*PORTS-1:0] s_data,
  input [4*PORTS-1:0] s_keep,input [PORTS-1:0] s_last,s_valid,
  input [16*PORTS-1:0] s_destination,input m_ready,output ok,legal);
    wire [PORTS-1:0] s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_last,m_valid;
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) dut(.*);
    localparam integer W=PORTS>1?$clog2(PORTS):1;
    reg initialized=0,active=0,route=0,buffered=0;
    reg [W-1:0] owner=0, cursor=0;
    // Connected by the proof script after flattening, never assumed. These
    // refinement invariants make the public-port contract inductive even if
    // a route word is stalled forever and its buffered payload is unobserved.
    wire [1:0] impl_state;
    wire [W-1:0] impl_selected, impl_next_port;
    wire [15:0] impl_destination;
    wire [36:0] impl_first;
    wire refinement = active==(impl_state!=0) && route==(impl_state==1) &&
        buffered==(impl_state==1 || impl_state==2) && cursor==impl_next_port &&
        cursor<PORTS && (!active || (owner==impl_selected && owner<PORTS &&
        destination==impl_destination && (!buffered || saved==impl_first)));
    reg [36:0] saved=0;
    reg [15:0] destination=0;
    reg [PORTS-1:0] held=0, in_packet=0;
    reg [32*PORTS-1:0] prev_data=0;
    reg [4*PORTS-1:0] prev_keep=0;
    reg [PORTS-1:0] prev_last=0;
    reg [16*PORTS-1:0] prev_destination=0;
    reg held_output=0;
    reg [36:0] prev_output=0;
    wire [PORTS-1:0] accepted=s_valid&s_ready;
    wire emitted=m_valid&&m_ready;
    reg inputs_legal,inputs_ok;
    reg [W-1:0] accepting;
    reg [PORTS-1:0] choice;
    integer distance, best;
    // Minimize circular distance rather than reproducing the DUT scan.
    always @* begin
        choice=0;best=PORTS;
        for(integer k=0;k<PORTS;k=k+1) begin
            distance=k>=cursor?k-cursor:k+PORTS-cursor;
            if(s_valid[k] && distance<best) begin choice=1<<k;best=distance;end
        end
    end
    integer p;
    always @* begin
        accepting=0;inputs_legal=1;inputs_ok=1;
        for(p=0;p<PORTS;p=p+1) begin
            if(accepted[p]) begin
                accepting=p;
                if(active && (owner!=p || route || buffered)) inputs_ok=0;
            end
            if(held[p] && (!s_valid[p] ||
               {s_data[32*p+:32],s_keep[4*p+:4],s_last[p]} !=
               {prev_data[32*p+:32],prev_keep[4*p+:4],prev_last[p]} ||
               (!in_packet[p] && s_destination[16*p+:16]!=prev_destination[16*p+:16]))) inputs_legal=0;
        end
    end
    wire onehot=(accepted & (accepted-1'b1))==0;
    wire [36:0] expected=buffered?saved:
        {s_last[owner],s_keep[4*owner+:4],s_data[32*owner+:32]};
    wire output_ok=!m_valid || (active && (route ?
        {m_last,m_keep,m_data}=={1'b0,4'hf,ENDPOINTS[16*owner+:16],destination} :
        (buffered || s_valid[owner]) && {m_last,m_keep,m_data}==expected));
    assign legal=!initialized || reset || inputs_legal;
    assign ok=!initialized || (reset ? (!m_valid && s_ready==0) : (
        refinement && onehot && inputs_ok && output_ok &&
        (active || accepted==choice) &&
        (!held_output || (m_valid && {m_last,m_keep,m_data}==prev_output)) &&
        // In the streaming phase, accepted and emitted beats are identical.
        (!(|accepted) || !active || emitted) &&
        (!emitted || route || buffered || accepted[owner]) &&
        // No silent deadlock: registered words and offered owner beats are valid.
        (m_valid == (active && (route || buffered || s_valid[owner])))));
    always @(posedge clk) begin
        initialized<=1;
        prev_data<=s_data;prev_keep<=s_keep;prev_last<=s_last;prev_destination<=s_destination;
        prev_output<={m_last,m_keep,m_data};
        if(reset) begin
            active<=0;route<=0;buffered<=0;owner<=0;destination<=0;saved<=0;
            held<=0;held_output<=0;in_packet<=0;cursor<=0;
        end else begin
            for(integer k=0;k<PORTS;k=k+1) if(accepted[k]) in_packet[k]<=!s_last[k];
            held<=s_valid&~s_ready;held_output<=m_valid&&!m_ready;
            if(!active && (|accepted)) begin
                active<=1;route<=1;buffered<=1;owner<=accepting;
                destination<=s_destination[16*accepting+:16];
                saved<={s_last[accepting],s_keep[4*accepting+:4],s_data[32*accepting+:32]};
            end
            if(emitted) begin
                if(route) route<=0;
                else begin
                    buffered<=0;
                    if(m_last) begin
                        active<=0;
                        cursor<=owner==PORTS-1?0:owner+1'b1;
                    end
                end
            end
        end
    end
endmodule
