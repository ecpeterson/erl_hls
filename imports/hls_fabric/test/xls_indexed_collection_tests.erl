-module(xls_indexed_collection_tests).
-moduledoc "Checks indexed collection placement before physical code generation.".
-include_lib("eunit/include/eunit.hrl").

%% Startup bypasses the reserved receiver and must not split collection ownership.
-spec reserved_startup_test() -> ok.
reserved_startup_test() ->
    Module = hls_indexed_adapter_fixture,
    Plan = hls_topology:normalize(#{version => 1, actors => #{sink => Module}, families => #{}, ingresses => [],
        externals => [{results, out, [piece]}], route_relations => [],
        routes => [{{sink, out}, [{external, results}]}],
        startup => [{sink, [{piece, 0, 0, 42}]}]}),
    Group = #{members => [{actor, sink}], state_storage => block_ram,
        mailbox_storage => block_ram, gather_collection => true},
    Profile = #{name => indexed_test, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => #{workers => Group}},
    ?assertError({reserved_gather_startup, sink},
        xls_fabric_topology_dslx:artifact_requirements(Plan, Profile)),
    ?assertMatch(#{Module := #{gather_collection := true}},
        xls_fabric_topology_dslx:artifact_requirements(Plan#{startup := []}, Profile)),
    ?assertMatch(#{Module := _}, xls_fabric_topology_dslx:artifact_requirements(
        Plan, Profile#{scheduler_groups := #{workers => Group#{gather_collection := false}}})).

%% Only a sole reserved tag is made literal; multiple tags preserve the selected frame.
-spec selected_frame_codegen_test() -> ok.
selected_frame_codegen_test() ->
    Spec = (xls_parse:actor_artifact("test/hls_indexed_adapter_fixture.erl", []))#{gather_collection => true},
    #{gathers := Gathers = #{sites := [Site = #{contributions := [Contribution]}]},
        message_words := Words} = Spec,
    Single = iolist_to_binary(xls_dslx:render(xls_indexed_collection_codegen:helpers(Spec))),
    Literal = <<"fn indexed_selected_frame(frame: axis::Frame) -> axis::Frame {\n"
        "  axis::Frame { header: axis::Header { op: Tag::PIECE as u8, ..frame.header }, ..frame }\n}">>,
    Identity = <<"fn indexed_selected_frame(frame: axis::Frame) -> axis::Frame { frame }">>,
    ?assertNotEqual(nomatch, binary:match(Single, Literal)),
    ?assertEqual(nomatch, binary:match(Single, Identity)),
    %% Duplicate only the emitter metadata to exercise its multiple-tag branch.
    MultiSite = Site#{contributions := [Contribution, Contribution#{tag := other_piece}]},
    MultiSpec = Spec#{gathers := Gathers#{sites := [MultiSite]},
        message_words := Words#{other_piece => maps:get(piece, Words)}},
    Multi = iolist_to_binary(xls_dslx:render(xls_indexed_collection_codegen:helpers(MultiSpec))),
    ?assertNotEqual(nomatch, binary:match(Multi, Identity)),
    ?assertEqual(nomatch, binary:match(Multi, Literal)).
