// Independent public-port monitor; reset aborts the current packet. No bounds
// on packet length, source gaps or sink stalls are assumed for safety.
module fabric_ingress_formal #(
    parameter integer PORTS=3,
    parameter [16*PORTS-1:0] ENDPOINTS={16'd42,16'd9,16'd2}
)(input clk,reset,input [31:0] s_data,input [3:0] s_keep,
  input s_last,s_valid,input [PORTS-1:0] m_ready,output ok,legal);
    wire s_ready,m_last;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire [15:0] m_source;
    wire [PORTS-1:0] m_valid;
    wire [1:0] route_error;
    hls_fabric_ingress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) dut(.*);
    reg initialized=0, address=1, held=0;
    reg [PORTS-1:0] recipients=0;
    reg [15:0] source=0;
    reg [36:0] previous=0;
    reg [PORTS-1:0] matches;
    integer p;
    always @* begin
        matches=0;
        for(p=0;p<PORTS;p=p+1) matches[p]=s_data[15:0]==ENDPOINTS[16*p+:16];
    end
    wire [1:0] impl_state;
    wire [15:0] impl_source;
    wire [(PORTS>1?$clog2(PORTS):1)-1:0] impl_selected;
    wire refinement=address==(impl_state==0) &&
        (address || (impl_state==2 ? recipients==0 :
          impl_state==1 && recipients==(1<<impl_selected) && impl_selected<PORTS)) &&
        source==impl_source;
    wire accepted=s_valid && s_ready;
    wire [PORTS-1:0] expected=(!address && s_valid)?recipients:0;
    wire [1:0] error_kind=s_keep!=15?1:s_last?3:matches==0?2:0;
    assign legal=!initialized || reset || !held ||
        (s_valid && {s_last,s_keep,s_data}==previous);
    assign ok=!initialized || (reset ? (m_valid==0 && !s_ready && route_error==0) : (
        refinement && m_valid==expected &&
        (s_ready==(address || recipients==0 || (|(recipients & m_ready)))) &&
        (!(|m_valid) || {m_last,m_keep,m_data,m_source}=={s_last,s_keep,s_data,source}) &&
        route_error==(address && accepted?error_kind:0)));
    always @(posedge clk) begin
        initialized<=1;
        previous<={s_last,s_keep,s_data};
        if(reset) begin address<=1;recipients<=0;source<=0;held<=0;end
        else begin
            held<=s_valid && !s_ready;
            if(accepted) begin
                if(address) begin
                    recipients<=error_kind==0?matches:0;
                    source<=s_data[31:16];
                end
                address<=s_last;
            end
        end
    end
endmodule
