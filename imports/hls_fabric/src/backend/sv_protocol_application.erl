-module(sv_protocol_application).
-moduledoc "Mechanically connects the shared gateway, activation bridge and freshly emitted source boundary.".
-export([emit/2, write/3]).

-doc "Writes pin wiring for the source-checked application binding and boundary manifest. Reuses hls_partition_activation unchanged; no new behavioral Verilog is emitted. Converts each ordinary actor bit frame to the gateway's Frame struct exactly once. All components must share clock/reset; exposed source faults do not constitute a gateway protocol-fault response.".
-spec write(map(),map(),file:filename()) -> ok.
write(Binding, Boundary, Directory) ->
    file:write_file(filename:join(Directory, "protocol_application_top.sv"),
        emit(Binding, Boundary), [exclusive]).

-doc "Returns mechanical application pin wiring from the checked binding and boundary. Retains frame/header bit order and optional inspection connections; no output files are created.".
-spec emit(map(), map()) -> iodata().
emit(#{events:=Events,control_adapter:=#{input_bits:=IngressBits,command_bits:=CommandBits,activation_module:=Activation}},
        #{frame_layout:=Layout,externals:=Externals,outputs:=Outputs,inspection:=Inspection}) ->
    FrameBits=hls_frame_layout:frame_bits(Layout),
    true=map_size(Events)=:=length(Externals),
    Diagnostics=[P||P=#{name:=Name}<-Outputs,not lists:prefix("external_",binary_to_list(Name)),
        Name=/=<<"ingress_ready">>,Name=/=<<"start_ready">>,Name=/=<<"inspect_value">>],
    Declarations=[["output wire [",n(W-1),":0] ",Name]||#{name:=Name,width:=W}<-Diagnostics],
    Ports=[".clk(clk)",".reset(reset)",".ingress_data(ingress)",".ingress_valid(ingress_valid)",
        ".ingress_ready(ingress_ready)",".start_valid(start_valid)",".start_ready(start_ready)"]++
        (case Inspection of none->[];_->[".inspect_address(inspect_address)",".inspect_value(inspect_value)"] end)++
        [[".",Name,"(",Name,")"]||#{name:=Name}<-Diagnostics]++
        [[".external_",n(I),"_",Field,"(event",n(I),"_",Field,")"]||#{index:=I}<-Externals,Field<-["data","valid","ready"]],
    Source=["// Mechanical application pin wiring; shared components own all behavior.\n",
      "module protocol_application_top(input wire clk,reset,input wire [31:0] s_app_tdata,\n",
      "input wire s_app_tlast,s_app_tvalid,output wire s_app_tready,output wire [31:0] m_app_tdata,\n",
      "output wire m_app_tlast,m_app_tvalid,input wire m_app_tready,\n",lists:join(",\n",Declarations),sv_protocol_inspection:ports(Inspection),");\n",
      case Inspection of none->[];_->"wire [31:0] inspect_address;wire [127:0] inspect_value;\n" end,
      "wire [",n(CommandBits-1),":0] command;wire command_valid,command_ready,started,started_valid,started_ready;\n",
      "wire [",n(IngressBits-1),":0] ingress;wire ingress_valid,ingress_ready,start_valid,start_ready;\n",
      [["wire [",n(FrameBits-1),":0] event",n(I),"_data;wire event",n(I),"_valid,event",n(I),"_ready;\n"]||#{index:=I}<-Externals],
      "application_gateway gateway(.clk(clk),.reset(reset),._app_in({s_app_tlast,s_app_tdata}),\n",
      "._app_in_vld(s_app_tvalid),._app_in_rdy(s_app_tready),._app_out({m_app_tlast,m_app_tdata}),\n",
      "._app_out_vld(m_app_tvalid),._app_out_rdy(m_app_tready),._commands_out(command),\n",
      "._commands_out_vld(command_valid),._commands_out_rdy(command_ready),\n",
      "._started_in(started),._started_in_vld(started_valid),._started_in_rdy(started_ready)",
      [event(I,FrameBits)||#{index:=I}<-Externals],");\n",
      Activation," #(.INGRESS_BITS(",n(IngressBits),")) activation(.clk(clk),.reset(reset),.command(command),.command_valid(command_valid),.command_ready(command_ready),\n",
      ".ingress_data(ingress),.ingress_valid(ingress_valid),.ingress_ready(ingress_ready),.start_valid(start_valid),.start_ready(start_ready),\n",
      ".started(started),.started_valid(started_valid),.started_ready(started_ready));\n",
      "protocol_boundary network(",lists:join(",",Ports),");\n",sv_protocol_inspection:body(Inspection),"endmodule\n"],
    Source.

%% Actor bit order is payload:op:flags:txid:words; the DSLX struct reverses header fields.
-spec event(non_neg_integer(),pos_integer()) -> iodata().
event(I,FrameBits) ->
    E="event"++n(I),
    [",\n._events_in__",n(I),"({",E,"_data[7:0],",E,"_data[15:8],",E,"_data[23:16],",E,"_data[31:24],",E,"_data[",n(FrameBits-1),":32]}),",
     "._events_in__",n(I),"_vld(",E,"_valid),._events_in__",n(I),"_rdy(",E,"_ready)"].

%% Checked elaborated indices are the only numbers used in identifiers.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
