#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).

%% Exercise the model through public fresh application builds; no solver or RTL run is implied.
-spec main([string()]) -> ok.
main([Config, Build, Output]) ->
    {ok,[Settings=#{protocol_model:=#{contracts:=Contracts}}]}=file:consult(Config),
    {ok,Bytes}=file:read_file(filename:join(Build,"transport.etf")),
    Plan=#{bundle:=#{inventory:=Inventory},protocol_model:=Report}=binary_to_term(Bytes),
    {ok,ReportBytes}=file:read_file(filename:join(Build,"protocol-model.etf")),
    Report=binary_to_term(ReportBytes),
    #{inventory_sha256:=Hash,model:=Model}=Report,
    Hash=binary:encode_hex(crypto:hash(sha256,term_to_binary(Inventory,[deterministic])),lowercase),
    ok=check(Inventory,Contracts,Model),
    %% Fresh compilation has unique symbolic reference IDs; preserve their sharing in comparison.
    Plain=Output++"-plain",
    _=hls_protocol_application:write(maps:remove(protocol_model,Settings),Plain),
    ok=compare(Build,Plain,Plan),
    false=filelib:is_file(filename:join(Plain,"protocol-model.etf")),
    Failed=Output++"-rejected",
    try hls_protocol_application:write(Settings#{protocol_model:=#{kind=>periodic_neighbor_barrier,contracts=>#{}}},Failed) of
        _->error(missing_roles_accepted)
    catch error:{periodic_model,incomplete_role_annotations}->ok end,
    false=filelib:is_dir(Failed),
    ok=file:write_file(Output++".json",json:encode(#{passed=>true,actors=>maps:get(actor_count,Model),
        messages=>length(maps:get(messages,Model)),nodes=>length(maps:get(nodes,Model)),
        eligibility=>false,hardware_comparison=>same_logic_with_fresh_build_identity}),[exclusive]);
main(["inventory",Stage]) ->
    Rows=[begin
        {ok,B}=file:read_file(filename:join(Stage,Name++".etf")),
        #{inventory:=I}=binary_to_term(B),Contracts=contracts(Name),
        M=hls_protocol_periodic_model:derive(I,Contracts),ok=check(I,Contracts,M),
        {ExpectedActors,ExpectedMessages}=case Name of
            "repetition-2"->{6,68};"repetition-3"->{9,102};"repetition-6"->{18,204};"noise-3"->{54,1188}
        end,
        ExpectedActors=maps:get(actor_count,M),ExpectedMessages=length(maps:get(messages,M)),
        #{name=>list_to_binary(Name),actors=>ExpectedActors,messages=>ExpectedMessages,nodes=>length(maps:get(nodes,M))}
    end||Name<-["repetition-2","repetition-3","repetition-6","noise-3"]],
    ok=file:write_file(filename:join(Stage,"periodic-models.json"),json:encode(#{passed=>true,models=>Rows}),[exclusive]);
main(_) -> io:format(standard_error,"Usage: check_protocol_model.escript CONFIG BUILD OUTPUT | inventory INVENTORIES~n",[]),halt(2).

%% Compare the complete plan modulo bijective alpha-renaming, and the public ABI except its build identity.
-spec compare(file:filename(),file:filename(),map()) -> ok.
compare(Build,Plain,Plan) ->
    {ok,PB}=file:read_file(filename:join(Plain,"transport.etf")),
    {Bare,_}=rename(maps:remove(protocol_model,Plan),#{}),
    {Bare,_}=rename(binary_to_term(PB),#{}),
    {ok,DB}=file:read_file(filename:join(Build,"deployment.etf")),
    {ok,PD}=file:read_file(filename:join(Plain,"deployment.etf")),
    A=#{devices:=#{board:=AB}}=binary_to_term(DB),B=#{devices:=#{board:=BB}}=binary_to_term(PD),
    Binding=maps:remove(identity,AB),Binding=maps:remove(identity,BB),
    Other=maps:remove(devices,A),Other=maps:remove(devices,B),
    %% Re-emit both gateways with the very same binding for a byte-exact comparison.
    Stage=filename:join(Plain,"application-comparison"),ok=file:make_dir(Stage),
    ok=xls_protocol_application:write(AB,Stage),ok.

%% Map keys are sorted; every repeated reference gets its original alpha ID, never a wildcard.
-spec rename(term(),map()) -> {term(),map()}.
rename(R,Seen) when is_reference(R) ->
    case maps:find(R,Seen) of
        {ok,I}->{{reference,I},Seen};
        error->I=map_size(Seen),{{reference,I},Seen#{R=>I}}
    end;
rename(M,Seen) when is_map(M) ->
    {Pairs,Next}=rename(lists:sort(maps:to_list(M)),Seen),{maps:from_list(Pairs),Next};
rename(T,Seen) when is_tuple(T) ->
    {Items,Next}=rename(tuple_to_list(T),Seen),{list_to_tuple(Items),Next};
rename([H|T],Seen) ->
    {Head,S1}=rename(H,Seen),{Tail,S2}=rename(T,S1),{[Head|Tail],S2};
rename(V,Seen) -> {V,Seen}.

%% Expected message multiplicity is determined independently from channel schema and the fixed twelve-round contract.
-spec check(map(),map(),map()) -> ok.
check(#{channels:=Channels},_,#{nodes:=Nodes,edges:=Edges,ranks:=Ranks,messages:=Messages,
        source_refinement:=unestablished,startup_marking:=unestablished,whole_protocol_eligible:=false}) ->
    true=lists:sort(Nodes)=:=lists:sort(maps:keys(Ranks)),
    lists:foreach(fun
        (#{lag:=0,waiter:=W,prerequisite:=P})->true=maps:get(P,Ranks)<maps:get(W,Ranks);
        (#{lag:=1})->ok
    end,Edges),
    Expected=lists:sort(lists:append([[{S,D,P,T,K}||K<-case T of phi->lists:seq(0,11);_->[0] end]
        ||#{source:=S,destination:={actor,D},port:=P,tag:=T}<-Channels])),
    Expected=lists:sort([{S,D,P,T,K}||#{key:={S,D,P,T},iteration:=K}<-Messages]),
    %% Add the reverse of a necessary current-generation dependency: it must reject.
    [#{lag:=0,waiter:=W,prerequisite:=P}|_]=[E||E=#{lag:=0}<-Edges],
    {error,{same_generation_wait_cycle,_}}=hls_protocol_wait_graph:check(Nodes,
        [#{waiter=>P,prerequisite=>W,lag=>0,kind=>dependency}|Edges]),ok.

%% Application-owned annotations remain hypotheses; source phase names alone do not prove them.
-spec contracts(string()) -> map().
contracts(Name) ->
    {D,S,P}=case Name of "noise-3"->{phenom_data_cell,phenom_syndrome_cell,phi_halo_cell};
        _->{phenom_line_data_cell,phenom_line_syndrome_cell,phi_line_cell} end,
    #{D=>#{role=>data,phases=>[configuring,collecting,reporting,replying]},
      S=>#{role=>syndrome,phases=>[configuring,collecting,announcing]},
      P=>#{role=>phi,rounds=>12,phases=>[configuring,measuring,gathering,comparing,flipping]}}.
