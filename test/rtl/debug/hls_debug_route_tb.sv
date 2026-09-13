`timescale 1ns/1ps
module hls_debug_route_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [31:0] s_data=0;
    reg [3:0] s_keep=15;
    reg s_last=0, s_valid=0;
    wire s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_last, m_valid;
    reg m_ready=0;
    wire [31:0] request_data;
    wire [3:0] request_keep;
    wire request_last;
    wire [2:0] request_valid, response_ready;
    reg [2:0] request_ready=0, response_valid=0, response_last=0;
    reg [95:0] response_data=0;
    reg [11:0] response_keep=0;
    integer cycle=0, requests=0, replies=0;
    integer i;
    reg [31:0] checksum[0:2];
    // Non-contiguous endpoint IDs and a non-power-of-two service count.
    hls_debug_route #(.PORTS(3), .ENDPOINTS({16'd9,16'd1,16'd2})) dut (.*);

    always @(negedge clk) begin
        cycle=cycle+1;
        request_ready={cycle%5!=0,cycle%3!=0,cycle%7!=0};
        m_ready=cycle%4==0 || cycle%4==1;
    end
    always @(posedge clk) begin
        if(reset) begin
            response_valid<=0; response_last<=0;
            for(i=0;i<3;i=i+1) checksum[i]<=0;
        end else begin
            if ((request_valid & (request_valid-1)) != 0 ||
                (response_ready & (response_ready-1)) != 0)
                $fatal(1,"more than one service owns the frame");
            for(i=0;i<3;i=i+1) begin
                if(request_valid[i] && request_ready[i]) begin
                    checksum[i]<=checksum[i]^request_data^{28'b0,request_keep};
                    if(request_last) begin
                        requests=requests+1;
                        response_valid[i]<=1;
                        response_last[i]<=0;
                        response_data[32*i+:32]<=32'h81000000+i;
                        response_keep[4*i+:4]<=15;
                    end
                end
                if(response_valid[i] && response_ready[i]) begin
                    if(response_last[i]) begin
                        replies=replies+1;
                        response_valid[i]<=0;
                        checksum[i]<=0;
                    end else begin
                        response_last[i]<=1;
                        response_data[32*i+:32]<=checksum[i];
                        response_keep[4*i+:4]<=3;
                    end
                end
            end
        end
    end
    // Holding a next request on the input cannot change a stalled reply.
    reg held=0;
    reg [36:0] previous;
    always @(posedge clk) begin
        if(!reset && held && {m_last,m_keep,m_data} !== previous)
            $fatal(1,"stalled response changed");
        held<=!reset && m_valid && !m_ready;
        previous<={m_last,m_keep,m_data};
    end
    task automatic send(input [31:0] data,input [3:0] keep,input last);
        begin
            @(negedge clk); s_data=data;s_keep=keep;s_last=last;s_valid=1;
            @(posedge clk); while(!s_ready) @(posedge clk);
            @(negedge clk);s_valid=0;
        end
    endtask
    task automatic receive_word(input [31:0] data,input [3:0] keep,input last);
        begin
            @(posedge clk); while(!(m_valid && m_ready)) @(posedge clk);
            if({m_last,m_keep,m_data} !== {last,keep,data})
                $fatal(1,"reply mismatch: got %h expected %h",{m_last,m_keep,m_data},{last,keep,data});
        end
    endtask
    task automatic transaction(input integer index,input [15:0] endpoint,input [15:0] source);
        begin
            fork
                begin
                    send({source,endpoint},15,0);
                    send(32'h12345678,15,0);
                    send(32'h90abcdef,5,1); // TKEEP reaches the service unchanged.
                end
                begin
                    receive_word({endpoint,source},15,0);
                    receive_word(32'h81000000+index,15,0);
                    receive_word(32'h12345678^32'h90abcdef^10,3,1);
                end
            join
        end
    endtask
    integer n;
    initial begin
        repeat(5) @(negedge clk); reset=0;
        // Unknown routes, short route-only frames, and partial route words drain.
        send(32'h12340007,15,0);send(32'hdeadbeef,15,1);
        send(32'h12340002,15,1);
        send(32'h12340001,3,0);send(32'hdeadbeef,15,1);
        if(requests!=0) $fatal(1,"malformed route reached service");
        for(n=0;n<100;n=n+1) begin
            transaction(0,2,n);
            transaction(1,1,16'hff00+n);
            transaction(2,9,16'hab00+n);
        end
        if(requests!=300 || replies!=300) $fatal(1,"lost reply");
        // Reset a partly delivered request and recover on a different endpoint.
        send(32'h12340002,15,0);send(32'h11111111,15,0);
        @(negedge clk); reset=1;
        repeat(3) @(negedge clk);reset=0;
        transaction(1,1,16'h789a);
        $display("PASS: shared debug frame ownership, routes, keep, stalls and reset");$finish;
    end
    initial begin #1000000; $fatal(1,"timeout");end
endmodule
