// Finite public-wire witness of coordinated reset and mismatched attachment rejection.
module tb;
reg clk=0,reset=1;
reg [31:0] s_app_tdata=0;
reg s_app_tlast=0,s_app_tvalid=0,m_app_tready=1;
wire s_app_tready,m_app_tlast,m_app_tvalid;
wire [31:0] m_app_tdata;
wire running;
protocol_application_top dut(.clk(clk),.reset(reset),.s_app_tdata(s_app_tdata),
 .s_app_tlast(s_app_tlast),.s_app_tvalid(s_app_tvalid),.s_app_tready(s_app_tready),
 .m_app_tdata(m_app_tdata),.m_app_tlast(m_app_tlast),.m_app_tvalid(m_app_tvalid),
 .m_app_tready(m_app_tready),.running(running));
reg [31:0] identity[0:7];
integer cycle=0,phase=0,source=0,index=0,op=0,attached=0,faults=0,stalls=0;
reg blocked=0,prior_last=0;
reg [31:0] prior=0;

// Observe only accepted public words; a reset discards the whole partial frame.
task tick;
begin
 clk=0;#5;
 if(!reset)begin
  if(blocked&&(!m_app_tvalid||m_app_tdata!==prior||m_app_tlast!==prior_last))
   $fatal(1,"stalled application word changed");
  blocked=m_app_tvalid&&!m_app_tready;prior=m_app_tdata;prior_last=m_app_tlast;
  if(blocked)stalls=stalls+1;
  if(m_app_tvalid&&m_app_tready)begin
   if(phase==0)begin source=m_app_tdata[31:16];phase=1;end
   else if(phase==1)begin op=m_app_tdata[31:24];phase=2;index=0;end
   else begin
    if(source==7&&op=='h81&&m_app_tdata!==identity[index])$fatal(1,"stale/mismatched identity response");
    index=index+1;
   end
   if(m_app_tlast)begin
    if(source==7&&op=='h81)begin if(index!=8)$fatal(1,"bad attach length");attached=attached+1;end
    if(source==7&&op=='hff)faults=faults+1;
    phase=0;
   end
  end
 end else begin blocked=0;phase=0;index=0;end
 clk=1;#5;cycle=cycle+1;
 if(cycle>12000)$fatal(1,"application reset witness timeout");
end
endtask

// A beat is held until the actual public ready/valid handshake.
task beat(input [31:0] word,input last);
integer waited;
begin
 s_app_tdata=word;s_app_tlast=last;s_app_tvalid=1;waited=0;
 clk=0;#1;
 while(!s_app_tready)begin tick();clk=0;#1;waited=waited+1;if(waited>1000)$fatal(1,"input stalled");end
 tick();s_app_tvalid=0;
end
endtask

// Coordinated reset cancels source, bridge and gateway state together.
task restart;
begin reset=1;s_app_tvalid=0;m_app_tready=1;repeat(8)tick();reset=0;repeat(8)tick();
 if(running)$fatal(1,"old activation survived reset");end
endtask

// Wrong identity changes one payload bit, retaining valid framing.
task attach(input wrong);
integer i;
begin
 beat(32'h00010007,0);beat(32'h01000008,0);
 for(i=0;i<8;i=i+1)beat(identity[i]^((wrong&&i==0)?1:0),i==7);
end
endtask

task await_attach(input integer expected);
integer i;
begin i=0;while(attached<expected&&i<1000)begin tick();i=i+1;end
 if(attached!=expected)$fatal(1,"attachment missing after reset");end
endtask

initial begin
 @@IDENTITY@@
 restart();beat(32'h00010007,0);beat(32'h01000008,0);beat(identity[0],0);
 restart();attach(0);await_attach(1);
 // Reset after a partially assembled setup command.
 beat(32'h00010007,0);beat(32'h02000005,0);beat(32'h00000000,0);beat(32'h00000000,0);
 restart();attach(0);await_attach(2);
 // Reset with a blocked external packet; its old framing cannot enter the next attachment.
 m_app_tready=0;repeat(100)tick();if(stalls==0)$fatal(1,"no blocked output exercised");
 restart();attach(0);await_attach(3);
 restart();attach(1);repeat(200)tick();
 if(faults!=1||attached!=3)$fatal(1,"wrong identity was not rejected");
 attach(0);repeat(200)tick();if(attached!=3)$fatal(1,"poisoned gateway accepted reattachment");
 $display("PROTOCOL_APPLICATION_RESET_PASS resets=3 identity_rejection=1 stalls=%0d",stalls);$finish;
end
endmodule
