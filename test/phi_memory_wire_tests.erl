-module(phi_memory_wire_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

boundary_commands_use_u16_rectangles_test() ->
    Command = {control_router, data, {1, 2, 3, 4}, #pauli_query{
        request_id = 16#12345678,
        measurement = x
    }},
    {ok, {0, 1}, {13, 0, 1}, Payload} =
        phi_memory_wire:encode_command(Command, 5),
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
            ?assertEqual(96, bit_size(Module:pack(Record)))
        end,
        Records
    ).

invalid_rectangle_is_rejected_test() ->
    Command = {control_router, noise, {0, 0, 3, 6}, #noise_cutoff{
        first_quiet_step = 1
    }},
    ?assertEqual(
        {error, rectangle},
        phi_memory_wire:encode_command(Command, 3)
    ).

wrong_event_route_and_version_are_rejected_test() ->
    Payload = phenom_data_cell:pack(#pauli_reply{
        request_id = 0, x = 0, y = 0, anticommutes = 0
    }),
    Tag = phenom_data_cell:pack_tag(pauli_reply),
    ?assertEqual(
        {error, route},
        phi_memory_wire:decode_event({99, 0}, {Tag, 0, 1}, Payload, 3)
    ),
    ?assertEqual(
        {error, frame},
        phi_memory_wire:decode_event({2, 0}, {Tag, 0, 2}, Payload, 3)
    ).
