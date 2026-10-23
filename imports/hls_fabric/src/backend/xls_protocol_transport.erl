-module(xls_protocol_transport).
-moduledoc "Lowers a source-bound transport plan to DSLX clock transitions. XLS owns all transport registers, selection and routing logic; the Verilog adapter only packs named pins.".
-export([write/2]).

-doc "Writes a DSLX proc, pin adapter and port manifest to a fresh directory. Requires the complete checked fabric plan. Partition crossings add canonical frame ports and one sticky fault bit per incoming link; outgoing state remains in its original publication. Compile with one pipeline stage and no input/output flops; both XLS channel handshakes are permanently enabled by the adapter. Recipient readiness remains ordinary input data and cannot stall the whole proc. This is hardware generation, not application capacity or progress admission.".
-spec write(map(),file:filename()) -> ok.
write(Plan=#{sources:=Sources,links:=Links},Directory) ->
    ok=file:make_dir(Directory),
    ok=xls_protocol_partition:write(Plan,Directory),
    Crossing=xls_protocol_partition:fragments(Plan),
    Keys=lists:usort([source_shape(S)||S<-Sources]),
    Definitions=[K#{index=>I}||{I,K}<-lists:enumerate(0,Keys)],
    Ids=maps:from_list([{K,I}||{I,K}<-lists:enumerate(0,Keys)]),
    Instances=[S#{shape=>maps:get(source_shape(S),Ids)}||S<-Sources],
    {Inputs,Outputs}=ports(Plan),
    {ok,Clock}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_clock.x.in")),
    Source=["import protocol_transport as p;\nimport axis;\nconst_assert!(axis::FRAME_BITS == u32:128);\n",
        maps:get(imports,Crossing),structure("Inputs",Inputs),structure("Outputs",Outputs),
        [source(S)||S<-Definitions],[link_shape(L)||L<-shapes(Links)],
        "pub struct State {\n",[[sname(I),": S",n(Shape),",\n"]||#{index:=I,shape:=Shape}<-Instances],
        [[lname(I),": L",n(Shape),",\n"]||#{index:=I,shape:=Shape}<-Links],maps:get(state,Crossing),"}\n",tick(Plan#{sources=>Instances}),Clock],
    ok=file:write_file(filename:join(Directory,"transport.x"),Source,[exclusive]),
    ok=sv_protocol_ports:write(Inputs,Outputs,filename:join(Directory,"protocol_fabric.sv")),
    file:write_file(filename:join(Directory,"ports.json"),json:encode(
        #{inputs=>[#{name=>list_to_binary(K),width=>W}||{K,W}<-Inputs],
          outputs=>[#{name=>list_to_binary(K),width=>W}||{K,W}<-Outputs]}),[exclusive]).

%% Only identical ordered payload shapes share functions; instances keep separate state.
-spec shapes([map()]) -> [map()].
shapes(Links) -> [L||{_,L}<-lists:sort(maps:to_list(maps:from_list([{maps:get(shape,L),L}||L<-Links])))].

%% Only fields read by source/1 enter this key. Equal definitions may be shared,
%% but every topology instance still gets its own publication and fault state.
-spec source_shape(map()) -> map().
source_shape(S=#{outputs:=Outputs}) ->
    (maps:with([payload_width,destinations,sequence_slots,output_width,masks],S))#{outputs=>[
        (maps:with([index,width],O))#{rows=>[maps:with([layout,sequence,bits,capture_slot],R)||R<-Rows]}
        ||O=#{rows:=Rows}<-Outputs]}.


%% Port order is the DSLX struct bit order and the adapter's concatenation order.
-spec ports(map()) -> {[{string(),pos_integer()}],[{string(),pos_integer()}]}.
ports(Plan=#{sources:=Sources,links:=Links,boundaries:=Boundaries}) ->
    {RemoteInputs,RemoteOutputs}=xls_protocol_partition:ports(Plan),
    Inputs=[{"reset",1}]++lists:append([[{sname(I)++"_valid",1},{sname(I)++"_layout",8},
        {sname(I)++"_payload",W}]||#{index:=I,payload_width:=W}<-Sources])++
        lists:append([[{lname(I)++"_take",1},{lname(I)++"_eligible",N},
            {lname(I)++"_release_valid",N}]||#{index:=I,slots:=N}<-Links])++
        [{bname(I,D)++"_ready",1}||#{source_index:=I,output:=#{index:=D}}<-Boundaries],
    Outputs=lists:append([[{sname(I)++"_ready",1},{sname(I)++"_fault",1}]||#{index:=I}<-Sources])++
        lists:append([[{lname(I)++"_capture",1},{lname(I)++"_capture_slot",8},
            {lname(I)++"_selected",N},{lname(I)++"_available",N},{lname(I)++"_leased",N},
            {lname(I)++"_payloads",W}]||#{index:=I,slots:=N,payload_bits:=W}<-Links])++
        lists:append([[{bname(I,D)++"_valid",1},{bname(I,D)++"_data",W}]
            ||#{source_index:=I,output:=#{index:=D,width:=W}}<-Boundaries]),
    {Inputs++RemoteInputs,Outputs++RemoteOutputs}.

%% Concrete actor payload types instantiate the reusable parametric publication state.
-spec source(map()) -> iolist().
source(#{index:=I,payload_width:=W,destinations:=D,sequence_slots:=N,
        outputs:=Outputs,output_width:=Total,masks:=Masks}) ->
    Id=n(I),Pub=["p::Publication<",n(W+8),",",n(D),",",n(N),">"],
    ["type S",Id," = (",Pub,", bool);\n",
     structure("V"++Id,[{"ready",1},{"fault",1},{"valid",D},{"data",Total},{"channel",D*8}]),
     "fn mask_",Id,"(layout: u8) -> (bool, ",bits(D*N),") { match layout {\n",
     [["u8:",n(L)," => (true, ",bits(D*N),":",n(M),"),\n"]||#{layout:=L,mask:=M}<-Masks],
     "_ => (false, ",bits(D*N),":0), } }\n",
     "fn view_",Id,"(s: S",Id,", reset: bool, offered_layout: u8) -> V",Id," {\n",
     "let (valid, indices) = p::publication_view(s.0, reset);\n",
     "let payload = s.0.payload as ",bits(W),"; let layout = (s.0.payload >> u32:",n(W),") as u8;\n",
     [["let (data_",n(K),", class_",n(K),") = match (layout, indices[u32:",n(K),"]) {\n",
        [["(u8:",n(L),", u8:",n(Seq),") => (",expression(Bs++lists:duplicate(Width-length(Bs),0)),
          ", u8:",n(C),"),\n"]||#{layout:=L,sequence:=Seq,bits:=Bs,capture_slot:=C}<-Rows],
        "_ => (",bits(Width),":0, u8:0), };\n"]||#{index:=K,width:=Width,rows:=Rows}<-Outputs],
     "V",Id," { ready: !reset && !s.0.busy && mask_",Id,"(offered_layout).0, fault: s.1, valid, data: ",
     concat(["data_"++n(K)||#{index:=K}<-lists:reverse(Outputs)],bits(Total)++":0"),", channel: ",
     concat(["class_"++n(K)||#{index:=K}<-lists:reverse(Outputs)],bits(D*8)++":0")," } }\n",
     "fn next_",Id,"(s: S",Id,", reset: bool, valid: bool, layout: u8, payload: ",bits(W),
     ", ready: ",bits(D),") -> S",Id," {\nlet (supported, mask) = mask_",Id,"(layout);\n",
     "(p::publication_next(s.0, reset, valid && supported, layout ++ payload, mask, ready),\n",
     "!reset && (s.1 || (!s.0.busy && valid && !supported))) }\n"].

%% Heterogeneous fixed slots retain separate payload fields, not a maximum-width RAM array.
-spec link_shape(map()) -> iolist().
link_shape(#{shape:=Shape,widths:=Widths,slots:=N,payload_bits:=Total,input_bits:=Max}) ->
    Id=n(Shape),Rows=lists:enumerate(0,Widths),
    ["type L",Id," = (",[["p::Capture<",n(W),">,"]||W<-Widths],"p::Order<",n(N),">);\n",
     structure("LV"++Id,[{"ready",1},{"selected",N},{"available",N},{"leased",N},{"payloads",Total}]),
     "fn link_view_",Id,"(s: L",Id,", reset: bool, eligible: ",bits(N),", slot: u8) -> LV",Id," {\n",
     "LV",Id," { ready: !reset && (",lists:join(" || ",[["(slot == u8:",n(K)," && s.",n(K),".owner == u2:0)"]||{K,_}<-Rows]),"),\n",
     "selected: p::select(s.",n(N),", reset, eligible), available: ",
     concat([["(!reset && s.",n(K),".owner == u2:1)"]||{K,_}<-lists:reverse(Rows)],"false"),", leased: ",
     concat([["(!reset && s.",n(K),".owner == u2:2)"]||{K,_}<-lists:reverse(Rows)],"false"),", payloads: ",
     concat([["s.",n(K),".payload"]||{K,_}<-lists:reverse(Rows)],"false")," } }\n",
     "fn link_next_",Id,"(s: L",Id,", reset: bool, valid: bool, slot: u8, payload: ",bits(Max),
     ", take: bool, release: ",bits(N),", view: LV",Id,") -> L",Id," {\n",
     [["let arrive_",n(K)," = valid && view.ready && slot == u8:",n(K),";\n"]||{K,_}<-Rows],
     "(",[["p::capture_next(s.",n(K),", reset, arrive_",n(K),", payload as ",bits(W),", ",
        bit("view.selected",K)," && take, ",bit("release",K),"),\n"]||{K,W}<-Rows],
     "p::order_next(s.",n(N),", reset, ",concat(["arrive_"++n(K)||{K,_}<-lists:reverse(Rows)],"false"),
     ", view.selected, take)) }\n"].

%% Read old source and slot state before computing acceptance and next state.
-spec tick(map()) -> iolist().
tick(Plan=#{sources:=Sources,links:=Links,boundaries:=Boundaries}) ->
    {_,Ports}=ports(Plan),
    Crossing=xls_protocol_partition:fragments(Plan),
    Views=[["let ",sname(I)," = view_",n(Shape),"(s.",sname(I),", io.reset, io.",sname(I),"_layout);\n"]||#{index:=I,shape:=Shape}<-Sources],
    LinkViews=[["let ",lname(I),"_slot = ",link_slot(L),";\n",
        "let ",lname(I)," = link_view_",n(Shape),"(s.",lname(I),", io.reset, io.",lname(I),"_eligible, ",lname(I),"_slot);\n"]
        ||L=#{index:=I,shape:=Shape}<-Links],
    SourceNext=[[sname(I),": next_",n(Shape),"(s.",sname(I),", io.reset, io.",sname(I),"_valid, io.",sname(I),
        "_layout, io.",sname(I),"_payload, ",concat([ready(I,O,Links++maps:get(crossings,Plan,[]))||O<-lists:reverse(Os)],bits(D)++":0"),"),\n"]
        ||#{index:=I,shape:=Shape,destinations:=D,outputs:=Os}<-Sources],
    LinkNext=[[lname(I),": link_next_",n(Shape),"(s.",lname(I),", io.reset, ",link_valid(L),
        ", ",lname(I),"_slot, ",link_payload(L),", io.",lname(I),"_take, io.",lname(I),
        "_release_valid, ",lname(I),"),\n"]||L=#{index:=I,shape:=Shape}<-Links],
    Values=maps:from_list(lists:append([[{sname(I)++"_ready",sname(I)++".ready"},{sname(I)++"_fault",sname(I)++".fault"}]
        ||#{index:=I}<-Sources])++lists:append([[{lname(I)++"_capture",[link_valid(L)," && ",lname(I),".ready"]},
        {lname(I)++"_capture_slot",lname(I)++"_slot"}]++[{lname(I)++"_"++K,lname(I)++"."++K}||K<-["selected","available","leased","payloads"]]
        ||L=#{index:=I}<-Links])++lists:append([
        [{bname(I,D)++"_valid",bit(sname(I)++".valid",D)}, {bname(I,D)++"_data",slice(sname(I)++".data",At,W)}]
        ||#{source_index:=I,output:=#{index:=D,offset:=At,width:=W}}<-Boundaries])++maps:get(values,Crossing)),
    ["// Observations use old state; take/release and boundary ready affect next state only.\n",
        "pub struct Tick { state: State, output: Outputs }\n",
        "pub fn tick(s: State, io: Inputs) -> Tick {\n",Views,LinkViews,maps:get(views,Crossing),
        "Tick { state: State {",SourceNext,LinkNext,maps:get(next,Crossing),"}, output: Outputs {",
        [[K,": ",maps:get(K,Values),",\n"]||{K,_}<-Ports],"} } }\n"].

%% A native recipient uses local ownership; a crossing uses its peer's sampled credit.
-spec ready(non_neg_integer(),map(),[map()]) -> iolist().
ready(I,#{index:=D,destination:={external,_}},_) -> ["io.",bname(I,D),"_ready"];
ready(I,#{index:=D},Links) ->
    [L]=lists:usort([L||L=#{source_index:=S,output_index:=O}<-Links,S=:=I,O=:=D]),
    case L of
        #{index:=K,direction:=outgoing}->["io.",xls_protocol_partition:name(K),"_ready"];
        #{index:=K}->[lname(K),".ready"]
    end.

%% Incoming boundary offers replace only the missing source's slot/data wires.
-spec link_slot(map()) -> iodata().
link_slot(#{index:=I,direction:=incoming}) -> ["io.",xls_protocol_partition:name(I),"_slot"];
link_slot(#{source_index:=S,output_index:=D}) -> slice(sname(S)++".channel",D*8,8).

%% Canonical admission gates capture; malformed frames never enter native storage.
-spec link_valid(map()) -> iodata().
link_valid(#{index:=I,direction:=incoming}) -> [xls_protocol_partition:name(I),".capture"];
link_valid(#{source_index:=S,output_index:=D}) -> bit(sname(S)++".valid",D).

%% The peer frame is projected by the same source-bound codec used by the receiver.
-spec link_payload(map()) -> iodata().
link_payload(#{index:=I,direction:=incoming}) -> [xls_protocol_partition:name(I),"_payload"];
link_payload(#{source_index:=S,output:=#{offset:=At,width:=W}}) -> slice(sname(S)++".data",At,W).

%% These bits reference the retained ordinary payload, with numeric low-bit-first planning.
-spec expression([hls_protocol_projection:bit()]) -> iolist().
expression(Bits) -> concat([case B of {payload,J}->["payload[",n(J),"+:u1]"];_->["u1:",n(B)] end
    ||B<-lists:reverse(Bits)],"u1:0").

%% Static packed records keep ABI ordering visible in generated DSLX.
-spec structure(string(),[{string(),pos_integer()}]) -> iolist().
structure(Name,Fields) -> ["pub struct ",Name," {",[[K,": ",bits(W),",\n"]||{K,W}<-Fields],"}\n"].
%% Empty recipients still use the planner's harmless one-bit physical placeholder.
-spec concat([iodata()],iodata()) -> iolist().
concat([],Default) -> [Default];
concat(Parts,_) -> ["(",lists:join(" ++ ",Parts),")"].
%% Fixed slices are wires after XLS lowering.
-spec slice(string(),non_neg_integer(),pos_integer()) -> iolist().
slice(Value,At,W) -> [Value,"[",n(At),"+:",bits(W),"]"].
%% A one-bit projection is a boolean in DSLX.
-spec bit(string(),non_neg_integer()) -> iolist().
bit(Value,J) -> [Value,"[",n(J),"+:u1]"].
%% All dimensions are known at elaboration.
-spec bits(pos_integer()) -> string().
bits(N) -> "bits["++n(N)++"]".
%% Actor identities come from deterministic topology enumeration.
-spec sname(non_neg_integer()) -> string().
sname(I) -> "source_"++n(I).
%% Each logical sender/destination pair owns separate state.
-spec lname(non_neg_integer()) -> string().
lname(I) -> "link_"++n(I).
%% Boundary identity includes both logical source and recipient.
-spec bname(non_neg_integer(),non_neg_integer()) -> string().
bname(I,D) -> "boundary_"++n(I)++"_"++n(D).
%% Only elaborated integers enter DSLX identifiers or literals.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
