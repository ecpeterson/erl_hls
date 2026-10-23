-module(xls_protocol_bridge).
-moduledoc "Elaborates static partition pins around the shared typed DSLX bridge and unchanged source boundary.".
-export([write/3]).

-doc "Writes one fresh sampled-clock bridge around a freshly built boundary. Static link/class identities come from hls_protocol_bridge; old boundary observations supply credit and retained offers, and only the final call applies accepted transfers. Adds bounded framing and reservation state, no replicated native payloads. Output fault includes any native actor/transport failure; retirement masks both directions until coordinated reset. Returns exact emitted-input hashes and state accounting with eligibility false.".
-spec write(map(),map(),file:filename()) -> map().
write(Bridge=#{identity:=Identity,host:=Host,service:=Service,incoming:=Incoming,outgoing:=Outgoing,credits:=Credits},
        Boundary=#{outputs:=NativeOutputs,externals:=Externals},Directory) ->
    Path=filename:join(Directory,"bridge"),ok=file:make_dir(Path),
    I=length(Incoming),C=length(Credits),O=length(Outgoing),E=length(Externals),
    Dimensions=lists:join(",",[n(N)||N<-[I,C,O,E]]),StateDimensions=lists:join(",",[n(N)||N<-[I,C,O]]),
    Inputs=[{"reset",1},{"retire",1},{"s_app_tdata",32},{"s_app_tlast",1},{"s_app_tvalid",1},{"m_app_tready",1}],
    Outputs=[{"s_app_tready",1},{"m_app_tdata",32},{"m_app_tlast",1},{"m_app_tvalid",1},{"fault",1},{"running",1}],
    Faults=[Name||#{name:=Name}<-NativeOutputs,lists:suffix("_fault",binary_to_list(Name)) orelse lists:suffix("_failure",binary_to_list(Name))],
    {ok,Clock}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_boundary_clock.x.in")),
    Source=["import boundary;\nimport protocol_bridge as b;\nimport protocol_rectangle as control;\n",structure("Inputs",Inputs),structure("Outputs",Outputs),
      "// Shared source state plus the sole framed transport owner.\npub struct State { network: boundary::State, bridge: b::State<",StateDimensions,"> }\n",
      "// Next state and pre-edge public pins.\npub struct Tick { state: State, output: Outputs }\n",
      "// Read retained observations, then apply accepted transfers once.\npub fn tick(s: State, io: Inputs) -> Tick {\n",
      "let packet = b::unpack(s.bridge.rx.payload as bits[256]);\n",
      "let command = control::decode(s.bridge.rx.payload[64+:bits[256]],s.bridge.rx.header[0+:u8]-u8:2);\n",
      "let sample = boundary::Inputs { reset: io.reset,\n",
      [[remote(L),"_slot: packet.slot, ",remote(L),"_frame: packet.frame,\n"]||L<-Incoming],
      "..zero!<boundary::Inputs>() };\nlet old = boundary::tick(s.network, sample).output;\n",
      "let step = b::tick(s.bridge, b::Inputs<",Dimensions,"> { reset:io.reset,retire:io.retire,\n",
      "child_fault: ",lists:join(" || ",[["old.",Name," != bits[",n(W),"]:0"]||#{name:=Name,width:=W}<-NativeOutputs,lists:member(Name,Faults)]),",\n",
      "word:io.s_app_tdata,last:io.s_app_tlast,valid:io.s_app_tvalid,ready:io.m_app_tready,\n",
      "incoming_links: [",lists:join(",",[["u16:",n(N)]||#{index:=N}<-Incoming]),"],\n",
      "incoming_ready: [",lists:join(",",[["old.",remote(L),"_ready"]||L<-Incoming]),"],\n",
      "credits: [",lists:join(",",[["b::Credit { link:u16:",n(N),",slot:u8:",n(K),",free:old.remote_",n(N),"_free[",n(K),"+:u1] }"]||#{link:=N,slot:=K}<-Credits]),"],\n",
      "outgoing_links: [",lists:join(",",[["u16:",n(N)]||#{index:=N}<-Outgoing]),"],\n",
      "outgoing: [",lists:join(",",[offer(remote(L),"slot","frame")||L<-Outgoing]),"],\n",
      "externals: [",lists:join(",",[offer("external_"++n(N),"zero","data")||#{index:=N}<-Externals]),"],\n",
      "control_legal:command.valid,control_ready:old.ingress_ready,start_ready:old.start_ready }, bits[256]:",integer_to_list(binary:decode_unsigned(Identity,little)),
      ", u16:",n(Host),", u16:",n(Service),");\n",
      "let network = boundary::tick(s.network, boundary::Inputs {\n",
      "ingress_valid:step.output.control_valid,ingress_data:command.ingress,start_valid:step.output.start_valid,\n",
      [[remote(L),"_valid:step.output.incoming_valid[",n(K),"],\n"]||{K,L}<-lists:enumerate(0,Incoming)],
      [[remote(L),"_ready:step.output.outgoing_ready[",n(K),"],\n"]||{K,L}<-lists:enumerate(0,Outgoing)],
      [["external_",n(N),"_ready:step.output.external_ready[",n(N),"],\n"]||#{index:=N}<-Externals],
      "..sample });\nTick { state:State {network:network.state,bridge:step.state},output:Outputs {\n",
      "s_app_tready:step.output.ready,m_app_tdata:step.output.word,m_app_tlast:step.output.last,\n",
      "m_app_tvalid:step.output.valid,fault:step.output.fault,running:old.running && step.output.active } } }\n",
      binary:replace(Clock,<<"boundary_clock">>,<<"bridge_clock">>,[global])],
    ok=file:write_file(filename:join(Path,"bridge.x"),Source,[exclusive]),
    ok=sv_protocol_ports:write(Inputs,Outputs,filename:join(Path,"protocol_bridge_top.sv"),"protocol_bridge_top","protocol_bridge_core"),
    %% RX=360, TX=310; attachment/fault=67, event sequence/cursor=48.
    StateBits=785+32*I+C+42*O,
    Manifest=(maps:without([identity,incoming,outgoing,credits,links],Bridge))#{top=>protocol_bridge_top,
      links=>[#{index=>N,direction=>D,source_index=>S,destination_index=>T,slots=>Slots,
        classes=>[maps:with([slot,codec],Cl)||Cl<-Cs]}
        ||#{index:=N,direction:=D,source_index:=S,destination_index:=T,slots:=Slots,classes:=Cs}<-maps:get(links,Bridge)],
      identity=>binary:encode_hex(Identity,lowercase),bridge_state_bits=>StateBits,boundary=>Boundary,
      reset=>retire_deployment_transports_then_coordinated_reset,ordering=>per_logical_sender_destination,
      inputs=>[#{name=>list_to_binary(N),width=>W}||{N,W}<-Inputs],
      outputs=>[#{name=>list_to_binary(N),width=>W}||{N,W}<-Outputs],
      dslx_sha256=>hash(filename:join(Path,"bridge.x")),
      components=>[#{file=>list_to_binary(F),sha256=>hash(filename:join(Directory,F))}
        ||F<-["boundary/boundary.x","bridge/protocol_bridge_top.sv"]]},
    ok=file:write_file(filename:join(Path,"manifest.json"),json:encode(Manifest),[exclusive]),Manifest.

%% Static retained offers preserve the ordinary low-header frame ABI.
-spec offer(string(),string(),string()) -> iodata().
offer(P,Slot,Frame) ->
    ["b::Offer {valid:old.",P,"_valid,slot:",case Slot of "zero"->"u8:0";_->["old.",P,"_",Slot] end,
      ",frame:old.",P,"_",Frame,"}"].
%% Only original global link indices determine raw crossing names.
-spec remote(map()) -> string().
remote(#{index:=I}) -> xls_protocol_partition:name(I).
%% Named pins follow DSLX struct order in the mechanical adapter.
-spec structure(string(),[{string(),pos_integer()}]) -> iodata().
structure(Name,Fields) -> ["// Sampled bridge pins.\npub struct ",Name," {\n",[[N,":bits[",n(W),"],\n"]||{N,W}<-Fields],"}\n"].
%% Exact emitted bytes bind the separate XLS invocation.
-spec hash(file:filename()) -> binary().
hash(File) -> {ok,B}=file:read_file(File),binary:encode_hex(crypto:hash(sha256,B),lowercase).
%% Only checked dimensions and indices enter generated text.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
