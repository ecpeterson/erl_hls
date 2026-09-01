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
