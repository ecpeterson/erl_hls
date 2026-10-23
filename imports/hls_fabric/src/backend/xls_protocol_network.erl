-module(xls_protocol_network).
-moduledoc "Composes source-bound receiver and transport clock functions in DSLX. Wiring uses old-state offers and eligibility, followed by one registered transition per component.".
-export([write/2]).

-doc "Writes network DSLX, a mechanical pin adapter and a manifest beside a fresh transport build. Requires hls_protocol_network's source-bound plan and boundary checks. Reuses each receiver and transport state. Optional host ingress adds one shared frame, per-actor pending bits and a sticky fault; payload is not copied per recipient. Explicit activation adds one monotone bit and gates internal eligibility only; local entry work, startup, host commands and publications continue while stopped. startup_done reports only consumption of declared records, not application readiness. Every clock samples external ready pins; all components share reset. Outputs include each actor's source failure and publisher fault. The manifest also binds every boundary stream to its declared external endpoint, retaining unused declarations and rendering their Erlang IDs as text. Optional process inspection selects metadata from old committed machines and has no input to application state or handshakes. Raw crossing pins pass through to canonical transport admission; crossing_state_bits counts the incoming fault registers already inside transport. This is executable composition, not capacity, progress or physical qualification.".
-spec write(map(),file:filename()) -> map().
write(Plan=#{inspection:=Inspection,fabric:=Fabric=#{sources:=Sources,links:=Links,boundaries:=Boundaries},receivers:=Receivers,ingress:=Ingress,activation:=Activation,
        bundle:=#{topology:=#{externals:=Externals}}},Directory) ->
    Path=filename:join(Directory,"network"), ok=file:make_dir(Path),
    {RemoteInputs,RemoteOutputs}=xls_protocol_partition:ports(Fabric),
    Crossings=maps:get(crossings,Fabric,[]),
    Incoming=[I||#{index:=I,direction:=incoming}<-Crossings],
    Inspect=Inspection=:=process,
    Debug=case Inspect of true->hls_protocol_inspection:write(Plan,Path);false->none end,
    Host=Ingress=/=none, Explicit=Activation=:=explicit_start,
    case Host of true->ok=xls_protocol_ingress:write(Ingress,filename:join(Directory,"dslx"));false->ok end,
    Inputs=[{"reset",1}]++optional(Inspect,[{"inspect_address",32}])++optional(Explicit,[{"start_valid",1}])++optional(Host,[{"ingress_valid",1},{"ingress_data",194}])++[{boundary(B)++"_ready",1}||B<-Boundaries]++RemoteInputs,
    Outputs=[{"startup_done",1}]++optional(Inspect,[{"inspect_value",128}])++optional(Explicit,[{"start_ready",1},{"running",1}])++optional(Host,[{"ingress_ready",1},{"ingress_fault",1}])++lists:append([[{actor(I)++"_failure",16},{actor(I)++"_fault",1}]||#{index:=I}<-Sources])++
        lists:append([[{boundary(B)++"_valid",1},{boundary(B)++"_data",W}]
            ||B=#{output:=#{width:=W}}<-Boundaries])++RemoteOutputs,
    {ok,Clock}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_network_clock.x.in")),
    Source=["import transport;\n",optional(Inspect,"import process_observation as inspection;\n"),optional(Explicit,"import protocol_activation as activation;\n"),optional(Host,"import ingress;\n"),[["import receiver_",n(I)," as ",actor(I),";\n"]||#{index:=I}<-Sources],
        structure("Inputs",Inputs),structure("Outputs",Outputs),
        "// Component states remain independent; optional ingress owns one shared command.\npub struct State { transport: transport::State,\n",
        [[actor(I),": ",actor(I),"::LocalInboxState,\n"]||#{index:=I}<-Sources],optional(Host,"ingress: ingress::State,\n"),optional(Explicit,"activation: activation::State,\n"),"}\n",
        "// Next component states and pre-edge external observations.\npub struct Tick { state: State, output: Outputs }\n",
        "// Offers/eligibility read old state. Preview outputs ignore take/release;\n",
        "// the second pure transport call supplies their actual next-state inputs.\n",
        "pub fn tick(s: State, io: Inputs) -> Tick {\n",
        "let startup_done = ",lists:join(" && ",[[actor(I),"::local_inbox_startup_done(s.",actor(I),", io.reset)"]||#{index:=I}<-Sources]),";\n",
        optional(Host,"let ingress_offer = ingress::observe(s.ingress, io.reset, startup_done);\n"),
        [["let batch_",n(I)," = ",actor(I),"::local_inbox_batch(s.",actor(I),", io.reset);\n",
          "let eligible_",n(I)," = ",actor(I),"::local_inbox_eligible(s.",actor(I),", io.reset);\n"]||#{index:=I}<-Sources],
        "let offer = transport::Inputs { reset: io.reset,\n",
        [[source(I),"_",K,": batch_",n(I),".",K,",\n"]||#{index:=I}<-Sources,K<-["valid","layout","payload"]],
        [[link_name(I),"_eligible: ",eligibility(Explicit,D,offset(I,Links),N),",\n"]
            ||#{index:=I,destination_index:=D,slots:=N}<-Links],
        [[boundary(B),"_ready: io.",boundary(B),"_ready,\n"]||B<-Boundaries],[[K,": io.",K,",\n"]||{K,_}<-RemoteInputs],"..zero!<transport::Inputs>() };\n",
        "let preview = transport::tick(s.transport, offer).output;\n",
        [receiver(R,Links)||R<-Receivers],
        optional(Host,["let ingress_step = ingress::tick(s.ingress, io.reset, startup_done, io.ingress_valid,\n",
          "ingress::decode(io.ingress_data), ",host_mask(Ingress,Receivers),");\n"]),
        "let transport_step = transport::tick(s.transport, transport::Inputs {\n",
        [[link_name(I),"_take: or_reduce(step_",n(D),".output.take[",n(offset(I,Links)),"+:bits[",n(N),"]]),\n",
          link_name(I),"_release_valid: step_",n(D),".output.release[",n(offset(I,Links)),"+:bits[",n(N),"]],\n"]
            ||#{index:=I,destination_index:=D,slots:=N}<-Links],"..offer });\n",
        activation_step(Explicit,Host,Sources,Incoming),
        "Tick { state: State { transport: transport_step.state,\n",
        [[actor(I),": step_",n(I),".state,\n"]||#{index:=I}<-Sources],optional(Host,"ingress: ingress_step,\n"),optional(Explicit,"activation: activation_step.state,\n"),"}, output: Outputs {\n",
        optional(Inspect,["inspect_value: match io.inspect_address {\n",
            [["u32:",n(I)," => inspection::observe_",n(I),"(s.",actor(I),".owner.machine, s.",actor(I),".started, io.reset),\n"]||#{index:=I}<-Sources],
            "_ => bits[128]:0, },\n"]),
        "startup_done,\n",optional(Explicit,"start_ready: activation_step.output.start_ready, running: activation_step.output.running,\n"),optional(Host,"ingress_ready: ingress_offer.ready, ingress_fault: ingress_offer.fault,\n"),
        [[actor(I),"_failure: step_",n(I),".output.owner.failure, ",actor(I),"_fault: preview.",source(I),"_fault,\n"]||#{index:=I}<-Sources],
        [[boundary(B),"_",K,": preview.",boundary(B),"_",K,",\n"]||B<-Boundaries,K<-["valid","data"]],[[K,": preview.",K,",\n"]||{K,_}<-RemoteOutputs],"} } }\n",Clock],
    Dslx=filename:join(Path,"network.x"), ok=file:write_file(Dslx,Source,[exclusive]),
    ok=sv_protocol_ports:write(Inputs,Outputs,filename:join(Path,"protocol_network.sv"),"protocol_network","protocol_network_core"),
    Manifest=#{top=>protocol_network,clock_proc=>network_clock,actor_runtime=>true,eligible=>false,
        actors=>length(Sources),links=>length(Links),additional_state_bits=>(case Host of true->maps:get(state_bits,Ingress);false->0 end)+(case Explicit of true->1;false->0 end),
        activation=>Activation,inspection=>Debug,
        native_indices=>[I||#{index:=I}<-Sources],
        crossings=>[#{index=>I,direction=>D,source_index=>S,destination_index=>T,slots=>N,
            classes=>[maps:with([slot,codec],C)||C<-Cs]}
            ||#{index:=I,direction:=D,source_index:=S,destination_index:=T,slots:=N,classes:=Cs}<-Crossings],
        crossing_state_bits=>length(Incoming),
        ingress=>Ingress,
        capacity=>unestablished,network_progress=>unestablished,
        initialization=>source_init_and_declared_startup,publication=>atomic_old_outbox_batch,
        startup_messages=>lists:sum([N||#{manifest:=#{inbox:=#{startup:=#{count:=N}}}}<-Receivers]),
        startup_done=>all_declared_records_consumed_not_application_readiness,
        reset=>common_clock_cancels_all_ownership,
        inputs=>fields(Inputs),outputs=>fields(Outputs),
        dslx_sha256=>binary:encode_hex(crypto:hash(sha256,Source),lowercase),
        components=>[#{file=>list_to_binary(F),sha256=>hash(filename:join(Directory,F))}
            ||F<-["dslx/transport.x"|[binary_to_list(maps:get(file,R))||R<-Receivers]]++xls_protocol_partition:files(Fabric)++optional(Host,["dslx/ingress.x"])++optional(Inspect,["network/process_observation.x"])],
        externals=>[#{index=>I,id=>iolist_to_binary(io_lib:format("~0tp",[Id]))}||{I,#{id:=Id}}<-lists:enumerate(0,Externals)],
        boundaries=>[#{source_index=>I,output_index=>D,name=>list_to_binary(boundary(B)),external_index=>external_index(Id,Externals)}
            ||B=#{source_index:=I,output:=#{index:=D,destination:={external,Id}}}<-maps:get(boundaries,Fabric)]},
    ok=file:write_file(filename:join(Path,"manifest.json"),json:encode(Manifest),[exclusive]), Manifest.

%% Running is registered: start_valid cannot open captures on its handshake edge.
-spec eligibility(boolean(),non_neg_integer(),non_neg_integer(),pos_integer()) -> iodata().
eligibility(Explicit,Actor,Offset,Width) ->
    Mask=["eligible_",n(Actor),"[",n(Offset),"+:bits[",n(Width),"]]"],
    case Explicit of
        true->["activation::eligible(s.activation, io.reset, ",Mask,")"];
        false->Mask
    end.

%% These observations use old ownership/faults, never same-edge consume or ready.
%% Initialization/entry work and already published captures need not be drained.
-spec activation_step(boolean(),boolean(),[map()],[non_neg_integer()]) -> iodata().
activation_step(false,_,_,_) -> [];
activation_step(true,Host,Sources,Incoming) ->
    ["let activation_step = activation::tick(s.activation, activation::Conditions {\n",
     "reset: io.reset, startup_done, ingress_idle: ",case Host of true->"ingress_offer.ready";false->"true" end,
     ", ingress_valid: ",case Host of true->"io.ingress_valid";false->"false" end,",\n",
     "fault: ",optional(Host,"ingress_offer.fault || "),
     [["preview.",xls_protocol_partition:name(I),"_fault || "]||I<-Incoming],
     lists:join(" || ",[["step_",n(I),".output.owner.failure != u16:0 || preview.",source(I),"_fault"]||#{index:=I}<-Sources]),
     " }, io.start_valid);\n"].

%% Match the exact field order and per-destination slot flattening used by inbox attachment.
-spec receiver(map(),[map()]) -> iodata().
receiver(#{index:=I,manifest:=#{inbox:=#{host:=#{slots:=Host}}}},Links) ->
    ["let step_",n(I)," = ",actor(I),"::local_inbox_batch_tick(s.",actor(I),", ",actor(I),"::LocalInboxInputs {\n",
     "reset: io.reset, output_ready: preview.",source(I),"_ready,\n",
     optional(Host=:=1,["host_valid: ingress_offer.valid[",n(I),"+:u1], host_frame: ingress_offer.frame,\n"]),
     [[link_name(K),"_",Field,": preview.",link_name(K),"_",Field,",\n"]
        ||#{index:=K,destination_index:=D}<-Links,D=:=I,Field<-["selected","available","payloads"]],"});\n"].

%% Host masks retain full-topology indices even when this role has holes.
-spec host_mask(none | map(),[map()]) -> iodata().
host_mask(none,_) -> [];
host_mask(#{actors:=N},Receivers) ->
    ByIndex=maps:from_list([{I,R}||R=#{index:=I}<-Receivers]),
    lists:join(" ++ ",[host_take(maps:get(I,ByIndex,#{}))||I<-lists:seq(N-1,0,-1)]).

%% Host retirement is a source disposition, not initial inbox reservation.
-spec host_take(map()) -> iodata().
host_take(#{index:=I,manifest:=#{inbox:=#{host:=#{slots:=1,offset:=At}}}}) ->
    ["step_",n(I),".output.take[",n(At),"+:u1]"];
host_take(_) -> "u1:0".

%% Omitted interfaces introduce no state or unused pins.
-spec optional(boolean(),list()) -> list().
optional(true,Value) -> Value;
optional(false,_) -> [].

%% Slot zero belongs to the first incoming pair, exactly as in hls_protocol_inbox.
-spec offset(non_neg_integer(),[map()]) -> non_neg_integer().
offset(I,Links) ->
    [#{destination_index:=D}]=[L||L=#{index:=K}<-Links,K=:=I],
    lists:sum([N||#{index:=K,destination_index:=Other,slots:=N}<-Links,K<I,Other=:=D]).

%% Packed field order is shared by the DSLX record, pin adapter and JSON consumer.
-spec structure(string(),[{string(),pos_integer()}]) -> iodata().
structure(Name,Fields) -> ["// Sampled network clock interface.\npub struct ",Name," {\n",
    [[K,": bits[",n(W),"],\n"]||{K,W}<-Fields],"}\n"].

%% JSON retains the same exact widths rather than inferring them from generated text.
-spec fields([{string(),pos_integer()}]) -> [map()].
fields(Fields) -> [#{name=>list_to_binary(K),width=>W}||{K,W}<-Fields].

%% Bind generated imports to their fresh source build; partial reads fail the build.
-spec hash(file:filename()) -> binary().
hash(Path) -> {ok,Bytes}=file:read_file(Path), binary:encode_hex(crypto:hash(sha256,Bytes),lowercase).

%% Names follow deterministic elaborated instance and recipient identities.
-spec actor(non_neg_integer()) -> string().
actor(I) -> "actor_"++n(I).
%% Publisher identities agree with the existing transport port manifest.
-spec source(non_neg_integer()) -> string().
source(I) -> "source_"++n(I).
%% Avoid the Erlang link BIF name for physical pair identifiers.
-spec link_name(non_neg_integer()) -> string().
link_name(I) -> "link_"++n(I).
%% External destinations stay separate streams; there is no implicit merger.
-spec boundary(map()) -> string().
boundary(#{source_index:=I,output:=#{index:=D}}) -> "boundary_"++n(I)++"_"++n(D).
%% Only checked elaboration integers enter generated identifiers and slices.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).

%% Canonical normalized topology order is shared by the boundary and host binding.
-spec external_index(atom() | non_neg_integer() | tuple(),[map()]) -> non_neg_integer().
external_index(Id,Externals) ->
    [Index]=[I||{I,#{id:=Name}}<-lists:enumerate(0,Externals),Name=:=Id],Index.
