-module(phi_memory_wire_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

boundary_contract_tracks_normalized_topology_test() ->
    Distance = 3,
    Contract = phi_memory_boundary:contract(Distance),
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance, 0)),
    ?assertEqual(
        [maps:get(id, External) || External <- maps:get(externals, Plan)],
        [maps:get(id, Output) || Output <- maps:get(outputs, Contract)]
    ),
    ?assertEqual(
        lists:seq(2, 6),
        [maps:get(endpoint, Output) || Output <- maps:get(outputs, Contract)]
    ),
    [Ingress] = maps:get(ingresses, Plan),
    ?assertEqual(
        maps:get(shape, Ingress),
        maps:get(shape, maps:get(ingress, Contract))
    ),
    ?assertEqual(
        [maps:get(id, Target) || Target <- maps:get(targets, Ingress)],
        [maps:get(id, Target)
            || Target <- maps:get(targets, maps:get(ingress, Contract))]
    ),
    ?assertEqual(
        [
            {maps:get(id, Target), maps:get(schemas, Target)}
            || Target <- maps:get(targets, Ingress)
        ],
        [
            {maps:get(id, Target), [
                maps:get(name, Schema)
                || Schema <- maps:get(schemas, Target)
            ]}
            || Target <- maps:get(targets, maps:get(ingress, Contract))
        ]
    ),
    assert_output_modules_match_plan(Contract, Plan).

assert_output_modules_match_plan(#{outputs := Outputs}, Plan) ->
    FamilyIndex = maps:from_list([
        {maps:get(id, Family), maps:get(module, Family)}
        || Family <- maps:get(families, Plan)
    ]),
    Relations = maps:get(route_relations, Plan),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External}
        || External <- maps:get(externals, Plan)
    ]),
    lists:foreach(
        fun(#{id := External, modules := Modules, schemas := Schemas}) ->
            Expected = lists:usort([
                maps:get(Source, FamilyIndex)
                || #{source := {Source, _Port}, recipients := Recipients} <-
                       Relations,
                   lists:member({external, External}, Recipients)
            ]),
            ?assertEqual(Expected, Modules),
            ?assertEqual(
                maps:get(schemas, maps:get(External, ExternalIndex)),
                [maps:get(name, Schema) || Schema <- Schemas]
            )
        end,
        Outputs
    ).

boundary_commands_use_u16_rectangles_test() ->
    Command = {control_router, data, {1, 2, 3, 4}, #pauli_query{
        request_id = 16#12345678,
        measurement = x
    }},
    Contract = phi_memory_boundary:contract(5),
    {ok, {0, 1}, {13, 0, 1}, Payload} =
        phi_memory_wire:encode_command(Command, Contract),
    ?assertEqual(
        <<
            1:16/little,
            2:16/little,
            3:16/little,
            4:16/little,
            16#12345678:32/little,
            2:32/little
        >>,
        Payload
    ).

command_codecs_round_trip_test() ->
    Contract = phi_memory_boundary:contract(3),
    Commands = [
        {control_router, noise, {0, 0, 2, 5}, #noise_cutoff{
            first_quiet_step = 17
        }},
        {control_router, data, {1, 4, 1, 4}, #pauli_update{
            pauli = y
        }},
        {control_router, data, {0, 2, 2, 2}, #pauli_query{
            request_id = 16#12345678,
            measurement = z
        }}
    ],
    lists:foreach(
        fun(Command) ->
            {ok, Route, Header, Payload} =
                phi_memory_wire:encode_command(Command, Contract),
            ?assertEqual(
                {ok, Command},
                phi_memory_wire:decode_command(
                    Route, Header, Payload, Contract
                )
            )
        end,
        Commands
    ).

event_codecs_round_trip_test() ->
    Contract = phi_memory_boundary:contract(3),
    Events = [
        {data_measurements, #pauli_reply{
            request_id = 7, x = 1, y = 4, anticommutes = 1
        }},
        {x_announcements, #phenom_anyon{
            step = 8, flags = 3, x = 2, y = 1
        }},
        {z_announcements, #phenom_anyon{
            step = 9, flags = 0, x = 0, y = 2
        }},
        {x_decoder_events, #phi_correction{
            step = 10, x = 1, y = 0, direction = ?PHI_EAST_MASK
        }},
        {x_decoder_events, #phi_status{
            step = 10, x = 1, y = 0, flags = 2
        }},
        {z_decoder_events, #phi_correction{
            step = 11, x = 2, y = 2, direction = ?PHI_NORTH_MASK
        }},
        {z_decoder_events, #phi_status{
            step = 11, x = 2, y = 2, flags = 1
        }}
    ],
    lists:foreach(
        fun({Stream, Event}) ->
            {ok, Route, Header, Payload} =
                phi_memory_wire:encode_event(Stream, Event, Contract),
            ?assertEqual(
                {ok, Stream, Event},
                phi_memory_wire:decode_event(
                    Route, Header, Payload, Contract
                )
            )
        end,
        Events
    ).

event_codecs_match_the_actor_frame_payload_test() ->
    Records = [
        {phenom_syndrome_cell, #phenom_anyon{
            step = 0, flags = 0, x = 0, y = 0
        }},
        {phi_halo_cell, #phi_correction{
            step = 0, x = 0, y = 0, direction = 0
        }},
        {phi_halo_cell, #phi_status{
            step = 0, x = 0, y = 0, flags = 0
        }},
        {phenom_data_cell, #pauli_reply{
            request_id = 0, x = 0, y = 0, anticommutes = 0
        }}
    ],
    lists:foreach(
        fun({Module, Record}) ->
            Schema = element(1, Record),
            ?assertEqual(Module:pack_width(Schema), bit_size(Module:pack(Record)))
        end,
        Records
    ).

invalid_rectangle_is_rejected_test() ->
    Command = {control_router, noise, {0, 0, 3, 6}, #noise_cutoff{
        first_quiet_step = 1
    }},
    Contract = phi_memory_boundary:contract(3),
    ?assertEqual(
        {error, rectangle},
        phi_memory_wire:encode_command(Command, Contract)
    ).

wrong_event_route_and_version_are_rejected_test() ->
    Payload = phenom_data_cell:pack(#pauli_reply{
        request_id = 0, x = 0, y = 0, anticommutes = 0
    }),
    Tag = phenom_data_cell:pack_tag(pauli_reply),
    Contract = phi_memory_boundary:contract(3),
    ?assertEqual(
        {error, route},
        phi_memory_wire:decode_event(
            {99, 0}, {Tag, 0, 1}, Payload, Contract
        )
    ),
    ?assertEqual(
        {error, frame},
        phi_memory_wire:decode_event(
            {2, 0}, {Tag, 0, 2}, Payload, Contract
        )
    ).

invalid_command_frames_are_rejected_test() ->
    Contract = phi_memory_boundary:contract(3),
    Command = {control_router, data, {0, 0, 2, 0}, #pauli_query{
        request_id = 1,
        measurement = x
    }},
    {ok, Route, {Tag, 0, Version}, Payload} =
        phi_memory_wire:encode_command(Command, Contract),
    <<Bounds:8/binary, RequestId:4/binary, _Pauli:4/binary>> = Payload,
    ?assertEqual(
        {error, route},
        phi_memory_wire:decode_command(
            {99, 1}, {Tag, 0, Version}, Payload, Contract
        )
    ),
    ?assertEqual(
        {error, frame},
        phi_memory_wire:decode_command(
            Route, {Tag, 1, Version}, Payload, Contract
        )
    ),
    ?assertEqual(
        {error, selector},
        phi_memory_wire:decode_command(
            Route, {255, 0, Version}, Payload, Contract
        )
    ),
    ?assertEqual(
        {error, payload},
        phi_memory_wire:decode_command(
            Route, {Tag, 0, Version}, Bounds, Contract
        )
    ),
    ?assertEqual(
        {error, rectangle},
        phi_memory_wire:decode_command(
            Route,
            {Tag, 0, Version},
            <<0:16/little, 0:16/little, 3:16/little, 0:16/little,
                RequestId/binary, 2:32/little>>,
            Contract
        )
    ),
    ?assertEqual(
        {error, message},
        phi_memory_wire:decode_command(
            Route,
            {Tag, 0, Version},
            <<Bounds/binary, RequestId/binary, 4:32/little>>,
            Contract
        )
    ).

invalid_events_are_rejected_before_encoding_test() ->
    Contract = phi_memory_boundary:contract(3),
    ?assertEqual(
        {error, event},
        phi_memory_wire:encode_event(
            x_decoder_events,
            #phi_correction{
                step = 1,
                x = 0,
                y = 0,
                direction = 0
            },
            Contract
        )
    ),
    ?assertEqual(
        {error, event},
        phi_memory_wire:encode_event(
            x_announcements,
            #phenom_anyon{step = 1, flags = 0, x = 3, y = 0},
            Contract
        )
    ),
    ?assertEqual(
        {error, event},
        phi_memory_wire:encode_event(
            x_announcements,
            #phi_status{step = 1, flags = 0, x = 0, y = 0},
            Contract
        )
    ).
