-module(xls_protocol_network).
-moduledoc "Composes source-bound receiver and transport clock functions in DSLX. Wiring uses old-state offers and eligibility, followed by one registered transition per component.".
-export([write/2]).

-doc "Writes network DSLX, a mechanical pin adapter and a manifest beside a fresh transport build. Requires hls_protocol_network's source-bound plan and boundary checks. Reuses each receiver and transport state without new queues or payload copies. startup_done reports only consumption of declared records, not application readiness. Every clock samples external ready pins; all components share reset. Outputs include each actor's source failure and publisher fault. This is executable composition, not capacity, progress or physical qualification.".
-spec write(map(),file:filename()) -> map().
write(#{fabric:=Fabric=#{sources:=Sources,links:=Links,boundaries:=Boundaries},receivers:=Receivers},Directory) ->
    Path=filename:join(Directory,"network"), ok=file:make_dir(Path),
    Inputs=[{"reset",1}]++[{boundary(B)++"_ready",1}||B<-Boundaries],
    Outputs=[{"startup_done",1}]++lists:append([[{actor(I)++"_failure",16},{actor(I)++"_fault",1}]||#{index:=I}<-Sources])++
        lists:append([[{boundary(B)++"_valid",1},{boundary(B)++"_data",W}]
            ||B=#{output:=#{width:=W}}<-Boundaries]),
    {ok,Clock}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_network_clock.x.in")),
    Source=["import transport;\n",[["import receiver_",n(I)," as ",actor(I),";\n"]||#{index:=I}<-Sources],
        structure("Inputs",Inputs),structure("Outputs",Outputs),
        "// Component states remain independent; composition adds no registers.\npub struct State { transport: transport::State,\n",
        [[actor(I),": ",actor(I),"::LocalInboxState,\n"]||#{index:=I}<-Sources],"}\n",
        "// Next component states and pre-edge external observations.\npub struct Tick { state: State, output: Outputs }\n",
        "// Offers/eligibility read old state. Preview outputs ignore take/release;\n",
        "// the second pure transport call supplies their actual next-state inputs.\n",
        "pub fn tick(s: State, io: Inputs) -> Tick {\n",
        [["let batch_",n(I)," = ",actor(I),"::local_inbox_batch(s.",actor(I),", io.reset);\n",
          "let eligible_",n(I)," = ",actor(I),"::local_inbox_eligible(s.",actor(I),", io.reset);\n"]||#{index:=I}<-Sources],
        "let offer = transport::Inputs { reset: io.reset,\n",
        [[source(I),"_",K,": batch_",n(I),".",K,",\n"]||#{index:=I}<-Sources,K<-["valid","layout","payload"]],
        [[link_name(I),"_eligible: eligible_",n(D),"[",n(offset(I,Links)),"+:bits[",n(N),"]],\n"]
            ||#{index:=I,destination_index:=D,slots:=N}<-Links],
        [[boundary(B),"_ready: io.",boundary(B),"_ready,\n"]||B<-Boundaries],"..zero!<transport::Inputs>() };\n",
        "let preview = transport::tick(s.transport, offer).output;\n",
        [receiver(R,Links)||R<-Receivers],
        "let transport_step = transport::tick(s.transport, transport::Inputs {\n",
        [[link_name(I),"_take: or_reduce(step_",n(D),".output.take[",n(offset(I,Links)),"+:bits[",n(N),"]]),\n",
          link_name(I),"_release_valid: step_",n(D),".output.release[",n(offset(I,Links)),"+:bits[",n(N),"]],\n"]
            ||#{index:=I,destination_index:=D,slots:=N}<-Links],"..offer });\n",
        "Tick { state: State { transport: transport_step.state,\n",
        [[actor(I),": step_",n(I),".state,\n"]||#{index:=I}<-Sources],"}, output: Outputs {\n",
        "startup_done: ",lists:join(" && ",[[actor(I),"::local_inbox_startup_done(s.",actor(I),", io.reset)"]||#{index:=I}<-Sources]),",\n",
        [[actor(I),"_failure: step_",n(I),".output.owner.failure, ",actor(I),"_fault: preview.",source(I),"_fault,\n"]||#{index:=I}<-Sources],
        [[boundary(B),"_",K,": preview.",boundary(B),"_",K,",\n"]||B<-Boundaries,K<-["valid","data"]],"} } }\n",Clock],
    Dslx=filename:join(Path,"network.x"), ok=file:write_file(Dslx,Source,[exclusive]),
    ok=sv_protocol_ports:write(Inputs,Outputs,filename:join(Path,"protocol_network.sv"),"protocol_network","protocol_network_core"),
    Manifest=#{top=>protocol_network,clock_proc=>network_clock,actor_runtime=>true,eligible=>false,
        actors=>length(Sources),links=>length(Links),additional_state_bits=>0,
        capacity=>unestablished,network_progress=>unestablished,
        initialization=>source_init_and_declared_startup,publication=>atomic_old_outbox_batch,
        startup_messages=>lists:sum([N||#{manifest:=#{inbox:=#{startup:=#{count:=N}}}}<-Receivers]),
        startup_done=>all_declared_records_consumed_not_application_readiness,
        reset=>common_clock_cancels_all_ownership,
        inputs=>fields(Inputs),outputs=>fields(Outputs),
        dslx_sha256=>binary:encode_hex(crypto:hash(sha256,Source),lowercase),
        components=>[#{file=>list_to_binary(F),sha256=>hash(filename:join(Directory,F))}
            ||F<-["dslx/transport.x"|[binary_to_list(maps:get(file,R))||R<-Receivers]]],
        boundaries=>[#{source_index=>I,output_index=>D,name=>list_to_binary(boundary(B))}
            ||B=#{source_index:=I,output:=#{index:=D}}<-maps:get(boundaries,Fabric)]},
    ok=file:write_file(filename:join(Path,"manifest.json"),json:encode(Manifest),[exclusive]), Manifest.

%% Match the exact field order and per-destination slot flattening used by inbox attachment.
-spec receiver(map(),[map()]) -> iodata().
receiver(#{index:=I},Links) ->
    ["let step_",n(I)," = ",actor(I),"::local_inbox_batch_tick(s.",actor(I),", ",actor(I),"::LocalInboxInputs {\n",
     "reset: io.reset, output_ready: preview.",source(I),"_ready,\n",
     [[link_name(K),"_",Field,": preview.",link_name(K),"_",Field,",\n"]
        ||#{index:=K,destination_index:=D}<-Links,D=:=I,Field<-["selected","available","payloads"]],"});\n"].

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
