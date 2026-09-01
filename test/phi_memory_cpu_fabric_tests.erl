-module(phi_memory_cpu_fabric_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 3).
-define(NOISE_RATE, 16#80000000).

cutoff_is_the_activation_boundary_test() ->
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(?DISTANCE, ?NOISE_RATE),
    try
        Contract = phi_memory_boundary:contract(?DISTANCE),
        Query = {control_router, data, {0, 4, 2, 4}, #pauli_query{
            request_id = 1,
            measurement = z
        }},
        {ok, Route, Header, Payload} = phi_memory_wire:encode_command(
            Query,
            Contract
        ),
        ?assertEqual(
            {error, inactive},
            hls_fabric:send(Fabric, Route, Header, Payload)
        )
    after
        phi_memory_cpu_fabric:stop(Fabric)
    end.

distance_three_noisy_closeout_test_() ->
    {timeout, 10, ?_test(begin
        Fixture = phi_memory_demo:fixture(),
        Actual = phi_memory_demo:run_cpu(),
        ?assertEqual(ok, phi_memory_demo:verify(Actual)),
        Envelope = phi_memory_demo:witness_envelope(Actual),
        Options = maps:get(options, Fixture),
        ?assertEqual(
            {ok, Options, Actual},
            phi_memory_demo:decode_witness_envelope(Envelope)
        ),
        ok = maybe_write_witness(Envelope)
    end)}.

maybe_write_witness(Envelope) ->
    case os:getenv("ERL_HLS_PHI_CPU_WITNESS") of
        false ->
            ok;
        Path ->
            file:write_file(Path, io_lib:format("~tp.~n", [Envelope]))
    end.
