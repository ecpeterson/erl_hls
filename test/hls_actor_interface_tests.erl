-module(hls_actor_interface_tests).

-include_lib("eunit/include/eunit.hrl").

%% Interface inference retains source effect order and each port's schema union.
-spec source_interface_records_protocol_facts_test() -> ok.
source_interface_records_protocol_facts_test() ->
    Interface = hls_actor_interface:from_module(hls_grid_cell_fixture),
    ?assertEqual(configuring, maps:get(initial_phase, Interface)),
    ?assertEqual(5, hls_actor_interface:max_entry_effects(Interface)),
    ?assertEqual([delta, move, sample], hls_actor_interface:output_schemas(Interface, north)),
    ?assertEqual([request], hls_actor_interface:output_schemas(Interface, query)),
    ?assertEqual([result], hls_actor_interface:output_schemas(Interface, result)),
    ?assertEqual([delta, move, report, sample, seed],
        hls_actor_interface:dispatched_schemas(Interface)),
    ?assertEqual([], hls_actor_interface:initial_effects(Interface)),
    Effects = [E || E = #{phase := sampling} <- maps:get(entry_effects, Interface)],
    ?assertEqual([{0, north, sample}, {1, east, sample}, {2, west, sample},
        {3, south, sample}, {4, query, request}],
        [{maps:get(order, E), maps:get(port, E), maps:get(schema, E)} || E <- Effects]),
    ?assertEqual([{step, u32}, {flags, u32}, {x, u16}, {y, u16}], schema_fields(Interface, report)),
    ?assertEqual([{seed, u32}], schema_fields(Interface, seed)),
    ?assertEqual(32, schema_width(Interface, seed)),
    ?assertEqual(96, schema_width(Interface, result)).

%% Distinct receiver contracts remain distinct even when their shared tags agree.
-spec receiver_interfaces_are_distinct_test() -> ok.
receiver_interfaces_are_distinct_test() ->
    Data = hls_actor_interface:from_module(hls_data_cell_fixture),
    Query = hls_actor_interface:from_module(hls_query_cell_fixture),
    ?assertEqual([config, query], hls_actor_interface:dispatched_schemas(Data)),
    ?assertEqual([reply], hls_actor_interface:output_schemas(Data, north)),
    ?assertEqual([config, reply, request], hls_actor_interface:dispatched_schemas(Query)),
    ?assertEqual([query], hls_actor_interface:output_schemas(Query, north)),
    ?assertEqual([report], hls_actor_interface:output_schemas(Query, grid)),
    ?assertEqual(schema_fields(Data, config), schema_fields(Query, config)).

%% Checks source and compiled interfaces agree.
-spec source_and_compiled_interfaces_agree_test_() -> [term()].
source_and_compiled_interfaces_agree_test_() ->
    [
        {atom_to_list(Module), fun() ->
            ?assertEqual(
                xls_parse:actor_interface(Path),
                hls_actor_interface:from_module(Module)
            )
        end}
        || {Module, Path} <- [
            {hls_grid_cell_fixture, "test/hls_grid_cell_fixture.erl"},
            {hls_data_cell_fixture, "test/hls_data_cell_fixture.erl"},
            {hls_query_cell_fixture, "test/hls_query_cell_fixture.erl"}
        ]
    ].

%% Checks repeated tag blocks keep selector order.
-spec repeated_tag_blocks_keep_selector_order_test() -> ok.
repeated_tag_blocks_keep_selector_order_test() ->
    Interface = xls_parse:actor_interface(
        "test_data/hls_tags_statem_fixture.erl"
    ),
    ?assertEqual(waiting, maps:get(initial_phase, Interface)),
    ?assertEqual(
        [{first, 3}, {shared, 4}, {last, 5}],
        [
            {maps:get(name, Schema), maps:get(selector, Schema)}
            || Schema <- maps:get(schemas, Interface)
        ]
    ),
    ?assertEqual(
        [first],
        hls_actor_interface:output_schemas(Interface, out)
    ).

%% Checks hls gs interface inference is deferred.
-spec hls_gs_interface_inference_is_deferred_test() -> ok.
hls_gs_interface_inference_is_deferred_test() ->
    Path = "src/examples/regsvc/regsvc.erl",
    ?assertError(
        {unsupported_hls_actor_interface, Path, hls_gs},
        xls_parse:actor_interface(Path)
    ).

%% Checks unsupported interface inference does not narrow cpu compilation.
-spec unsupported_interface_inference_does_not_narrow_cpu_compilation_test() -> ok.
unsupported_interface_inference_does_not_narrow_cpu_compilation_test() ->
    Module = hls_statem_dynamic_actions_fixture,
    ?assertEqual({module, Module}, code:ensure_loaded(Module)),
    ?assertError(
        {missing_hls_actor_interface, Module},
        hls_actor_interface:from_module(Module)
    ).

%% Checks reduction interface survives parse transform.
-spec reduction_interface_survives_parse_transform_test() -> 'ok'.
reduction_interface_survives_parse_transform_test() ->
    Module = hls_statem_reduction_lower_fixture,
    Path = "test_data/hls_statem_reduction_lower_fixture.erl",
    _ = code:purge(Module),
    _ = code:delete(Module),
    {ok, Module, Binary} = compile:file(Path, [binary, debug_info]),
    {module, Module} = code:load_binary(Module, Path, Binary),
    try
        Interface = hls_actor_interface:from_module(Module),
        ?assertEqual(xls_parse:actor_interface(Path), Interface),
        ?assertEqual(96,
            hls_actor_interface:reduction_storage_width(Interface))
    after
        true = code:delete(Module),
        _ = code:purge(Module)
    end.

%% Reads ordered field names and integer provider constructors.
-spec schema_fields(hls_actor_interface:summary(), atom()) -> [{atom(), atom()}].
schema_fields(Interface, Name) ->
    [
        {maps:get(name, Field), element(3, maps:get(type, Field))}
        || Field <- maps:get(
            fields,
            hls_actor_interface:schema(Interface, Name)
        )
    ].

%% Checks stale embedded interface is rejected.
-spec stale_embedded_interface_is_rejected_test() -> ok.
stale_embedded_interface_is_rejected_test() ->
    Module = hls_actor_stale_fixture,
    Path = filename:join("_build", atom_to_list(Module) ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, interface_fixture_source(Module, u32)),
    {ok, Module, Binary} = compile:file(Path, [binary, debug_info]),
    {module, Module} = code:load_binary(Module, Path, Binary),
    try
        ok = file:write_file(Path, interface_fixture_source(Module, u64)),
        try hls_actor_interface:from_module(Module) of
            _ -> ?assert(false)
        catch
            error:{stale_hls_actor_interface, Module, _Source} -> ok
        end
    after
        true = code:delete(Module),
        _ = code:purge(Module),
        ok = file:delete(Path)
    end.

%% Constructs two source revisions differing only in the message word width.
-spec interface_fixture_source(module(), atom()) -> binary().
interface_fixture_source(Module, Width) ->
    iolist_to_binary(io_lib:format(
        "-module(~p).~n"
        "-behavior(hls_statem).~n"
        "-compile({parse_transform, hls_pack}).~n"
        "-hls_data(cell).~n"
        "-hls_phases([waiting]).~n"
        "-hls_outputs([out]).~n"
        "-hls_mailbox_capacity(1).~n"
        "-hls_tags([message]).~n"
        "-export([waiting/3, init/1]).~n"
        "-record(message, {~n"
        "  value = hls_type:zero() :: hls_nums:~p()~n"
        "}).~n"
        "-record(cell, {~n"
        "  value = hls_type:zero() :: hls_nums:~p()~n"
        "}).~n"
        "init([]) -> {ok, waiting, #cell{}}.~n"
        "waiting(enter, _Old, Cell) ->~n"
        "  {Cell, [{cast, out, #message{value = Cell#cell.value}}]};~n"
        "waiting(cast, #message{value = Value}, Cell) ->~n"
        "  {waiting, Cell#cell{value = Value}, consume}.~n",
        [Module, Width, Width]
    )).

%% Uses the shared record codec to measure the ordered interface fields.
-spec schema_width(hls_actor_interface:summary(), atom()) -> non_neg_integer().
schema_width(Interface, Name) ->
    #{fields := Fields} = hls_actor_interface:schema(Interface, Name),
    hls_record:width(Name, [{Field, Type} || #{name := Field, type := Type} <- Fields]).
