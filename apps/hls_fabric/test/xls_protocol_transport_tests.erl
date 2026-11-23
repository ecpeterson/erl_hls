-module(xls_protocol_transport_tests).
-moduledoc "Checks retained transport dependency structure before source rendering. Runtime transition behavior is exercised by the finite transport and partition RTL witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Readiness and observations cannot use retirement inputs from the current edge.
-spec pre_edge_dependencies_test() -> ok.
pre_edge_dependencies_test() ->
    Build = hls_protocol_transport:plan(config()),
    #{transition := #{observe := Observe, select := Select, crossing := [],
        commit := Commit, observations := Outputs}} = hls_protocol_transport:descriptor(Build),
    ObservationInputs = inputs([Observe, Select, Outputs]),
    ?assert(lists:member("reset", ObservationInputs)),
    ?assert(lists:any(fun(Name) -> lists:suffix("_eligible", Name) end, ObservationInputs)),
    ?assertEqual([], [Name || Name <- ObservationInputs, retirement(Name)]),
    CommitInputs = inputs(Commit),
    ?assert(lists:any(fun(Name) -> lists:suffix("_take", Name) end, CommitInputs)),
    ?assert(lists:any(fun(Name) -> lists:suffix("_release_valid", Name) end, CommitInputs)),
    Targets = [Name || {Name,_} <- Commit],
    ?assertEqual(length(Targets), length(lists:usort(Targets))),
    ?assert(lists:member("source_0", Targets)),
    ?assert(lists:member("link_0", Targets)).

%% Sparse placement retains canonical-validation nodes before the same native capture commit.
-spec crossing_validation_is_retained_test() -> ok.
crossing_validation_is_retained_test() ->
    Build = hls_protocol_transport:plan((config())#{native_actors => [left, sink]}),
    #{transition := #{crossing := Crossing, select := Select, commit := Commit}} =
        hls_protocol_transport:descriptor(Build),
    ?assert(Crossing =/= []),
    ?assert(lists:any(fun(Name) -> lists:suffix("_frame", Name) end, inputs(Crossing))),
    ?assertEqual([], [Name || Name <- inputs([Crossing, Select]), retirement(Name)]),
    ?assert(lists:any(fun({Name,_}) -> lists:prefix("remote_",Name) end, Commit)),
    ?assert(has_call("crossing_control::observe", Crossing)),
    ?assert(has_call("crossing_control::next", Commit)).

%% The fixture has two independently publishing sources, a sink and feedback paths.
-spec config() -> hls_source_config:transport().
config() -> #{sources => [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []},
    {"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}],
    topology => {hls_protocol_network_fixture, framed, []}, actor_limit => 3, control => rectangle}.

%% These two sampled inputs affect only the committed transition.
-spec retirement(string()) -> boolean().
retirement(Name) -> lists:suffix("_take",Name) orelse lists:suffix("_release_valid",Name).

%% Inspect explicit field nodes only; no emitted source is parsed to recover dependencies.
-spec inputs(term()) -> [string()].
inputs({xls_dslx,field,{xls_dslx,ref,"io"},Name}) -> [Name];
inputs(Term) when is_tuple(Term) -> inputs(tuple_to_list(Term));
inputs(Term) when is_list(Term) -> lists:usort(lists:append([inputs(Value) || Value <- Term]));
inputs(_) -> [].

%% Structured calls remain visible across blocks and match alternatives.
-spec has_call(string(), term()) -> boolean().
has_call(Name, {xls_dslx,call,Name,_}) -> true;
has_call(Name, Term) when is_tuple(Term) -> has_call(Name,tuple_to_list(Term));
has_call(Name, Term) when is_list(Term) -> lists:any(fun(Value) -> has_call(Name,Value) end,Term);
has_call(_, _) -> false.
