-module(xls_machine_layout_tests).
-moduledoc "Checks the physical actor-row ABI against small source-derived representations and finite DSLX witnesses.".
-include_lib("eunit/include/eunit.hrl").
-export([write/1]).

%% Every case crosses source analysis, physical placement, code generation, RAM and inspection.
-spec representations_test_() -> term().
representations_test_() ->
    {timeout, 120, [{atom_to_list(Name), fun() -> check(Name) end} || Name <- cases()]}.

%% The public local-owner descriptor includes event storage in both reported row widths.
-spec local_descriptor_test() -> ok.
local_descriptor_test() ->
    lists:foreach(fun({Module, Width, EventOffset, EventWidth}) ->
        [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
        Source = hls_local_actor:prepare("test/" ++ atom_to_list(Module) ++ ".erl", Context),
        #{machine_layout := Layout, machine_bits := Width, continuation_bits := EventWidth} =
            hls_local_actor:descriptor(Source),
        ?assertEqual(Width, maps:get(width, Layout)),
        ?assertEqual(#{offset => EventOffset, width => EventWidth}, maps:get(next_event, Layout)),
        ?assertEqual(#{offset => Width, width => 0}, maps:get(replies, Layout))
    end, [{hls_scheduler_build_fixture, 41, 41, 0}, {hls_statem_event_fixture, 105, 97, 8}]).

-doc "Writes seven standalone actor modules with independent packed-bit and finite execution tests. Run each with the XLS evaluator; no RTL scheduler or whole application is generated.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "ordinary.x")),
    lists:foreach(fun(Name) ->
        {_, _, Artifact} = prepare(Name),
        ok = file:write_file(filename:join(Stage, atom_to_list(Name) ++ ".x"),
            [xls_emitted:bytes(Artifact), checks(Name)], [exclusive])
    end, cases()).

%% One combined reduction/caller fixture checks the two appended fields together.
-spec cases() -> [atom()].
cases() -> [ordinary, events, reduction_replies, gather, gather_external, projected, projected_empty].

%% Numeric boundaries are fixed historical ABI expectations, independent of the production layout builder.
-spec expected(atom()) -> [{atom(), non_neg_integer(), non_neg_integer()}].
expected(Name) ->
    {Data, Reduction, Gather, Event, Replies, Total} = case Name of
        ordinary -> {8, 41, 41, 41, 41, 41};
        events -> {64, 97, 97, 97, 105, 105};
        reduction_replies -> {96, 129, 215, 215, 223, 391};
        gather -> {40, 73, 73, 169, 169, 169};
        gather_external -> {40, 73, 73, 145, 145, 145};
        projected -> {7, 40, 40, 40, 40, 40};
        projected_empty -> {0, 33, 33, 33, 33, 33}
    end,
    [{phase, 0, 8}, {entered_from, 8, 8}, {data, 16, Data},
     {enter_pending, 16 + Data, 1}, {failure, 17 + Data, 16},
     {reduction, Reduction, Gather - Reduction}, {gather, Gather, Event - Gather},
     {next_event, Event, Replies - Event}, {replies, Replies, Total - Replies}].

%% Independently expected row dimensions must agree across retained source and physical consumers.
-spec check(atom()) -> ok.
check(Name) ->
    {Generation, Spec, Artifact} = prepare(Name),
    Expected = maps:from_list([{F, #{offset => O, width => W}} || {F, O, W} <- expected(Name)]),
    #{offset := Tail, width := TailWidth} = maps:get(replies, Expected),
    Width = Tail + TailWidth,
    Layout = xls_machine_layout:from_spec(Spec),
    ?assertEqual(Expected#{width => Width}, xls_machine_layout:fields(Layout)),
    lists:foreach(fun({Field, Value}) ->
        ?assertEqual(Value, xls_machine_layout:field(Layout, Field))
    end, maps:to_list(Expected)),
    #{scheduler := Scheduler = #{groups := [Group]}, interfaces := Interfaces} =
        xls_fabric_topology_dslx:analysis(Generation),
    ?assertEqual(xls_machine_layout:fields(Layout),
        xls_machine_layout:fields(xls_machine_layout:from_group(Group))),
    [Binding] = xls_scheduler_ram_v:bindings(Scheduler, hls_frame_layout:default(), Interfaces),
    ?assertEqual(Width, maps:get(state_width, Binding)),
    #{module := Module} = Group,
    #{<<"banks">> := [Bank]} = xls_scheduler_debug:projection(Generation, #{Module => Artifact}),
    ?assertEqual(Width, maps:get(<<"width">>, Bank)),
    lists:foreach(fun(Field) ->
        #{offset := Offset, width := Bits} = maps:get(Field, Expected),
        ?assertEqual(#{<<"offset">> => Offset, <<"width">> => Bits},
            maps:get(atom_to_binary(Field), maps:get(<<"fields">>, Bank)))
    end, [phase, enter_pending, failure]),
    ?assertNotEqual(nomatch, binary:match(xls_emitted:bytes(Artifact),
        iolist_to_binary(["pub type MachineBits = bits[", integer_to_list(Width), "]"]))),
    ok.

%% Use actual profile requirements, including source-validated per-slot state projection.
-spec prepare(atom()) -> {xls_fabric_topology_dslx:plan(), map(), xls_emitted:artifact()}.
prepare(Name) ->
    {Module, Inputs, Outputs} = fixture(Name),
    {Topology, Members, Policy} = topology(Name, Module, Inputs, Outputs),
    Groups = #{workers => maps:merge(#{members => Members,
        state_storage => block_ram, mailbox_storage => block_ram}, Policy)},
    Generation = xls_fabric_topology_dslx:plan(Topology,
        #{name => machine_layout_fixture, channel_depth => 1,
          actor_egress_depth => burst, scheduler_groups => Groups}),
    Options = maps:get(Module, xls_fabric_topology_dslx:artifact_requirements(Generation)),
    [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
    Source = filename:join("test", atom_to_list(Module) ++ ".erl"),
    Spec = maps:merge(xls_parse:actor_artifact(Source, Context), Options),
    {Generation, Spec, xls_scheduler_actor:to_artifact(Source, Options#{source_options => Context})}.

%% These source modules each fit in one small actor without decoder/application dependencies.
-spec fixture(atom()) -> {module(), [atom()], [{atom(), [atom()]}]}.
fixture(ordinary) -> {hls_scheduler_build_fixture, [work], [{out, [work]}]};
fixture(events) -> {hls_statem_event_fixture, [start, later], [{out, [value]}]};
fixture(reduction_replies) -> {hls_statem_reduction_reply_fixture, [run, value, release], [{reply, [result]}]};
fixture(Name) when Name =:= gather; Name =:= gather_external ->
    {hls_indexed_debug_fixture, [piece], [{Port, [report]} || Port <- [out_a, out_b, out_c, out_d]]};
fixture(Name) when Name =:= projected; Name =:= projected_empty ->
    {hls_projection_fixture, [], [{out, [put]}]}.

%% Closed startup configuration establishes projection; ordinary cases retain a public input lane.
-spec topology(atom(), module(), [atom()], [{atom(), [atom()]}]) -> {hls_topology:plan(), [term()], map()}.
topology(Name, Module, _Inputs, _Outputs) when Name =:= projected; Name =:= projected_empty ->
    Startup = case Name of
        projected -> [{a, [{configure, 4567, -731}]}, {b, [{configure, 1234, 513}]}];
        projected_empty -> []
    end,
    {hls_topology:normalize(#{version => 1, actors => #{a => Module, b => Module},
        families => #{}, externals => [], route_relations => [], ingresses => [],
        routes => [{{a, out}, [{actor, a}]}, {{b, out}, [{actor, b}]}], startup => Startup}),
        [{actor, a}, {actor, b}], #{specialize_state => true}};
topology(Name, Module, Inputs, Outputs) ->
    {hls_topology:normalize(#{version => 1, actors => #{a => Module}, families => #{},
        ingresses => [{commands, {rectangle, [1, 1]}, [{input, Inputs, [{actor, a, {at, [0, 0]}}]}]}],
        externals => [{Port, out, Tags} || {Port, Tags} <- Outputs], route_relations => [],
        routes => [{{a, Port}, [{external, Port}]} || {Port, _} <- Outputs], startup => []}),
        [{actor, a}], case Name of gather_external -> #{gather_collection => true}; _ -> #{} end}.

%% Shared finite execution checks complement raw ABI probes; gather has two physical storage policies.
-spec checks(atom()) -> iodata().
checks(Name) ->
    File = case Name of gather_external -> gather; _ -> Name end,
    {ok, RowChecks} = file:read_file(filename:join("test/xls", "machine_row_" ++ atom_to_list(File) ++ ".xinc")),
    Prefix = case Name of
        gather -> "const STORED_GATHER_VALUES = true;\n";
        gather_external -> "const STORED_GATHER_VALUES = false;\n";
        _ -> []
    end,
    Existing = case Name of
        events -> "test_data/xls_statem_event_semantics.inc.x";
        reduction_replies -> "test_data/xls_statem_reduction_reply_semantics.inc.x";
        projected -> "test/xls/state_projection_checks.xinc";
        _ -> none
    end,
    ["\n", Prefix, RowChecks, case Existing of
        none -> [];
        _ -> {ok, SemanticChecks} = file:read_file(Existing), SemanticChecks
    end].
