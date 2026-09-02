-module(hls_actor_interface_tests).

-include_lib("eunit/include/eunit.hrl").

phi_interface_records_protocol_facts_test() ->
    Interface = hls_actor_interface:from_module(phi_halo_cell),
    ?assertEqual(configuring, maps:get(initial_phase, Interface)),
    ?assertEqual(5, hls_actor_interface:max_entry_effects(Interface)),
    ?assertEqual(
        [anyon_move, phi, phi0],
        hls_actor_interface:output_schemas(Interface, north)
    ),
    ?assertEqual(
        [phenom_request],
        hls_actor_interface:output_schemas(Interface, syndrome)
    ),
    ?assertEqual(
        [phi_correction],
        hls_actor_interface:output_schemas(Interface, correction)
    ),
    ?assertEqual(
        [anyon_move, phenom_anyon, phi, phi0, phi_config],
        hls_actor_interface:dispatched_schemas(Interface)
    ),
    ?assertEqual([], hls_actor_interface:initial_effects(Interface)),
    Gathering = [
        Effect
        || Effect <- maps:get(entry_effects, Interface),
           maps:get(phase, Effect) =:= gathering
    ],
    ?assertEqual(
        [
            {0, north, phi},
            {1, east, phi},
            {2, west, phi},
            {3, south, phi}
        ],
        [
            {maps:get(order, Effect),
                maps:get(port, Effect),
                maps:get(schema, Effect)}
            || Effect <- Gathering
        ]
    ),
    Flipping = [
        Effect
        || Effect <- maps:get(entry_effects, Interface),
           maps:get(phase, Effect) =:= flipping
    ],
    ?assertEqual(
        [
            {0, north, anyon_move},
            {1, east, anyon_move},
            {2, west, anyon_move},
            {3, south, anyon_move},
            {4, correction, phi_correction}
        ],
        [
            {maps:get(order, Effect),
                maps:get(port, Effect),
                maps:get(schema, Effect)}
            || Effect <- Flipping
        ]
    ),
    [CorrectionEffect] = [
        Effect
        || Effect <- Flipping,
           maps:get(port, Effect) =:= correction
    ],
    ?assert(maps:get(conditional, CorrectionEffect)),
    ?assertEqual(
        [{step, u32}, {flags, u32}, {x, u16}, {y, u16}],
        schema_fields(Interface, phenom_anyon)
    ),
    ?assertEqual(
        [{step, u32}, {x, u16}, {y, u16}, {direction, u32}],
        schema_fields(Interface, phi_correction)
    ),
    ?assertEqual(
        [{seed, u32}],
        schema_fields(Interface, phi_config)
    ),
    ?assertEqual(
        11,
        maps:get(selector, hls_actor_interface:schema(
            Interface,
            phi_correction
        ))
    ),
    ?assertEqual(
        12,
        maps:get(selector, hls_actor_interface:schema(
            Interface,
            phi_config
        ))
    ),
    #{name := cell, fields := StateFields, width := 528} =
        hls_actor_interface:state(Interface),
    ?assertEqual(
        [step, diffusion_round, phi, phi_sum, phi_received, seen_sources,
            best_phi0, best_direction, moves_received, anyon, random_state,
            x, y, noise_quiet, status_valid],
        [maps:get(name, Field) || Field <- StateFields]
    ).

phenomenological_interfaces_are_distinct_test() ->
    Data = hls_actor_interface:from_module(phenom_data_cell),
    Syndrome = hls_actor_interface:from_module(phenom_syndrome_cell),
    ?assertEqual(4, hls_actor_interface:max_entry_effects(Data)),
    ?assertEqual(4, hls_actor_interface:max_entry_effects(Syndrome)),
    ?assertEqual(
        [noise_cutoff, pauli_query, pauli_update,
            phenom_config, phenom_query],
        hls_actor_interface:dispatched_schemas(Data)
    ),
    ?assertEqual(
        [phenom_data],
        hls_actor_interface:output_schemas(Data, east)
    ),
    ?assertEqual(
        [pauli_reply],
        hls_actor_interface:output_schemas(Data, measurement)
    ),
    ?assertEqual(
        [noise_cutoff, phenom_config, phenom_data, phenom_request],
        hls_actor_interface:dispatched_schemas(Syndrome)
    ),
    ?assertEqual(
        [phenom_query],
        hls_actor_interface:output_schemas(Syndrome, south)
    ),
    ?assertEqual(
        [phenom_anyon],
        hls_actor_interface:output_schemas(Syndrome, phi)
    ),
    ?assertEqual(
        [{seed, u32}, {threshold, u32}, {x, u16}, {y, u16}],
        schema_fields(Syndrome, phenom_config)
    ),
    ?assertEqual(
        [{step, u32}, {flags, u32}, {x, u16}, {y, u16}],
        schema_fields(Syndrome, phenom_anyon)
    ),
    ?assertEqual(
        [{request_id, u32}, {measurement, pauli}],
        schema_fields(Data, pauli_query)
    ),
    ?assertEqual(
        [{request_id, u32}, {x, u16}, {y, u16}, {anticommutes, u32}],
        schema_fields(Data, pauli_reply)
    ),
    ?assertMatch(
        #{name := data_cell, width := 416},
        hls_actor_interface:state(Data)
    ),
    ?assertMatch(
        #{name := syndrome, width := 416},
        hls_actor_interface:state(Syndrome)
    ).

source_and_compiled_interfaces_agree_test_() ->
    [
        {atom_to_list(Module), fun() ->
            ?assertEqual(
                xls_parse:actor_interface(Path),
                hls_actor_interface:from_module(Module)
            )
        end}
        || {Module, Path} <- [
            {phi_halo_cell, "src/examples/phi_decoder/phi_halo_cell.erl"},
            {phenom_data_cell, "src/examples/phi_decoder/phenom_data_cell.erl"},
            {phenom_syndrome_cell,
                "src/examples/phi_decoder/phenom_syndrome_cell.erl"}
        ]
    ].

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

hls_gs_interface_inference_is_deferred_test() ->
    Path = "src/examples/regsvc/regsvc.erl",
    ?assertError(
        {unsupported_hls_actor_interface, Path, hls_gs},
        xls_parse:actor_interface(Path)
    ).

unsupported_interface_inference_does_not_narrow_cpu_compilation_test() ->
    Module = hls_statem_dynamic_actions_fixture,
    ?assertEqual({module, Module}, code:ensure_loaded(Module)),
    ?assertError(
        {missing_hls_actor_interface, Module},
        hls_actor_interface:from_module(Module)
    ).

schema_fields(Interface, Name) ->
    [
        {maps:get(name, Field), element(3, maps:get(type, Field))}
        || Field <- maps:get(
            fields,
            hls_actor_interface:schema(Interface, Name)
        )
    ].

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
        "-export([handle_cast/3, handle_enter/3, init/1]).~n"
        "-record(message, {~n"
        "  value = hls_type:zero() :: hls_nums:~p()~n"
        "}).~n"
        "-record(cell, {~n"
        "  value = hls_type:zero() :: hls_nums:~p()~n"
        "}).~n"
        "init([]) -> {ok, waiting, #cell{}}.~n"
        "handle_enter(_Old, waiting, Cell) ->~n"
        "  {Cell, [{cast, out, #message{value = Cell#cell.value}}]}.~n"
        "handle_cast(#message{value = Value}, waiting, Cell) ->~n"
        "  {waiting, Cell#cell{value = Value}, consume}.~n",
        [Module, Width, Width]
    )).
