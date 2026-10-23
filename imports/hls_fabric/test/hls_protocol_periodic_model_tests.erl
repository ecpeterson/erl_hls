-module(hls_protocol_periodic_model_tests).
-moduledoc "Synthetic dependency-model checks; role annotations do not prove source semantics.".
-include_lib("eunit/include/eunit.hrl").

%% Two labelled ports to one PID remain distinct ordered publications, not a deduplicated neighbor.
-spec repeated_neighbor_test() -> ok.
repeated_neighbor_test() ->
    {Inventory, Contracts} = fixture(),
    #{messages := Messages, edges := Edges, source_refinement := unestablished,
      startup_marking := unestablished, whole_protocol_eligible := false} =
        hls_protocol_periodic_model:derive(Inventory, Contracts),
    ?assertEqual(28, length(Messages)),
    lists:foreach(fun(K) ->
        First = {capture,a,b,east,phi,K}, Last = {capture,a,b,west,phi,K},
        ?assert(lists:member(#{waiter=>Last,prerequisite=>First,lag=>0,kind=>sender_order}, Edges))
    end, lists:seq(0,11)).

%% Distinct layouts do not impose a source order between mutually exclusive publications.
-spec alternatives_test() -> ok.
alternatives_test() ->
    {I=#{channels:=[C|Cs]}, Contracts} = fixture(),
    #{edges:=Edges} = hls_protocol_periodic_model:derive(
        I#{channels:=[C#{alternatives:=[#{phase=>gathering,layout=>other,order=>0}]}|Cs]},Contracts),
    ?assertEqual(2, length([E || E=#{kind:=sender_order} <- Edges])).

%% Missing, duplicate and incompatible annotations/edges must reject, not disappear from the model.
-spec rejected_model_test() -> ok.
rejected_model_test() ->
    {I=#{actors:=Actors,channels:=[C|Cs]}, Contracts=#{owner:=Role}} = fixture(),
    ?assertError({periodic_model,incomplete_role_annotations},hls_protocol_periodic_model:derive(I,#{})),
    ?assertError({periodic_model,incomplete_role_annotations},hls_protocol_periodic_model:derive(I,Contracts#{unused=>Role})),
    ?assertError({periodic_model,duplicate_or_empty_actor_population},hls_protocol_periodic_model:derive(I#{actors:=Actors++Actors},Contracts)),
    ?assertError({periodic_model,duplicate_periodic_channel},hls_protocol_periodic_model:derive(I#{channels:=[C,C|Cs]},Contracts)),
    ?assertError({periodic_model,{phase_coverage,owner}},hls_protocol_periodic_model:derive(I,Contracts#{owner:=Role#{phases:=[gathering]}})),
    ?assertError({periodic_model,{unsupported_role,owner,unknown}},hls_protocol_periodic_model:derive(I,Contracts#{owner:=Role#{role:=unknown}})),
    lists:foreach(fun(R)->
        ?assertError({periodic_model,{rounds,owner,R}},hls_protocol_periodic_model:derive(I,Contracts#{owner:=Role#{rounds:=R}}))
    end,[0,257,1.5]),
    ?assertError({periodic_model,{publication_phase,a,east,phi}},hls_protocol_periodic_model:derive(
        I#{channels:=[C#{alternatives:=[#{phase=>flipping,layout=>1,order=>0}]}|Cs]},Contracts)),
    ?assertError({periodic_model,{unsupported_schema,unexpected}},hls_protocol_periodic_model:derive(I#{channels:=[C#{tag:=unexpected}|Cs]},Contracts)),
    ?assertError({periodic_model,{source_diagnostics,[unsupported]}},hls_protocol_periodic_model:derive(I#{diagnostics:=[unsupported]},Contracts)),
    ?assertError({badkey,absent},hls_protocol_periodic_model:derive(I#{channels:=[C#{destination:={actor,absent}}|Cs]},Contracts)).

%% A deliberately limited proposed model makes no assertion that these synthetic owners execute it.
-spec fixture() -> {map(),map()}.
fixture() ->
    Phases=[configuring,measuring,gathering,comparing,flipping],
    Channels=[#{source=>a,destination=>{actor,b},port=>Port,tag=>Tag,
        alternatives=>[#{phase=>Phase,layout=>Phase,order=>Order}]} ||
        {Tag,Phase}<-[{phi,gathering},{phi0,comparing},{anyon_move,flipping}],
        {Port,Order}<-[{east,0},{west,1}]],
    {#{actors=>[#{id=>a,module=>owner},#{id=>b,module=>owner}],channels=>Channels,
       modules=>#{owner=>#{phases=>Phases}},diagnostics=>[]},
     #{owner=>#{role=>phi,phases=>Phases,rounds=>12}}}.
