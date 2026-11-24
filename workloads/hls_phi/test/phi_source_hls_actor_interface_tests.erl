-module(phi_source_hls_actor_interface_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks phi interface records protocol facts for the retained Phi application.
-spec phi_interface_records_protocol_facts_test() -> ok.
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
    #{name := cell, fields := StateFields, width := 320} =
        hls_actor_interface:state(Interface),
    ?assertEqual(
        [step, diffusion_epoch, phi, best_direction, anyon, random_state,
            x, y, noise_quiet, status_valid],
        [maps:get(name, Field) || Field <- StateFields]
    ),
    ?assertEqual(187,
        hls_actor_interface:reduction_storage_width(Interface)),
    #{sites := ReductionSites} = maps:get(reductions, Interface),
    ?assertEqual(
        [
            {diffusion, count, 4, true},
            {comparison, members, 4, true},
            {movement, count, 4, true}
        ],
        [
            {maps:get(name, Site),
                maps:get(mode, maps:get(population, Site)),
                maps:get(size, maps:get(population, Site)),
                maps:get(source_capture_total, Site)}
            || Site <- ReductionSites
        ]
    ).

%% Checks phenomenological interfaces are distinct for the retained Phi application.
-spec phenomenological_interfaces_are_distinct_test() -> ok.
phenomenological_interfaces_are_distinct_test() ->
    Data = hls_actor_interface:from_module(phenom_data_cell),
    Syndrome = hls_actor_interface:from_module(phenom_syndrome_cell),
    ?assertEqual(4, hls_actor_interface:max_entry_effects(Data)),
    ?assertEqual(5, hls_actor_interface:max_entry_effects(Syndrome)),
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
        #{name := data_cell, width := 354},
        hls_actor_interface:state(Data)
    ),
    ?assertMatch(
        #{name := syndrome, width := 354},
        hls_actor_interface:state(Syndrome)
    ).

%% Checks source and compiled interfaces agree for the retained Phi application.
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
            {phi_halo_cell, "workloads/hls_phi/src/phi_halo_cell.erl"},
            {phenom_data_cell, "workloads/hls_phi/src/phenom_data_cell.erl"},
            {phenom_syndrome_cell,
                "workloads/hls_phi/src/phenom_syndrome_cell.erl"}
        ]
    ].

%% Reads ordered field names and provider constructors from the actual actor interface.
-spec schema_fields(hls_actor_interface:summary(), atom()) -> [{atom(), atom()}].
schema_fields(Interface, Name) ->
    [
        {maps:get(name, Field), element(3, maps:get(type, Field))}
        || Field <- maps:get(
            fields,
            hls_actor_interface:schema(Interface, Name)
        )
    ].
