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
            {error, {not_sent, inactive}},
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

%% Aliased opposite neighbors must no longer suppress all moves on the smallest torus.
-spec distance_two_noisy_closeout_test() -> ok.
distance_two_noisy_closeout_test() ->
    First = distance_two_witness(),
    ?assertEqual(First, distance_two_witness()),
    ?assertMatch(#{correction_count := 34, closeout_step := 17,
        data_counts := #{commutes := 8, anticommutes := 0}}, phi_memory_demo:summary(First)).

%% Give each run independent actors, deterministic noise and the ordinary cutoff/query protocol.
-spec distance_two_witness() -> phi_memory_experiment:witness().
distance_two_witness() ->
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(2, ?NOISE_RATE),
    try
        Options = #{distance => 2, first_quiet_step => 16,
            line_y => 2, measurement => z, request_id => 16#504849},
        {ok, Runner} = phi_memory_runner:start_link(Fabric, Options, 2000),
        try
            {ok, Witness} = phi_memory_runner:await(Runner),
            Witness
        after phi_memory_runner:stop(Runner) end
    after phi_memory_cpu_fabric:stop(Fabric) end.

maybe_write_witness(Envelope) ->
    case os:getenv("ERL_HLS_PHI_CPU_WITNESS") of
        false ->
            ok;
        Path ->
            file:write_file(Path, io_lib:format("~tp.~n", [Envelope]))
    end.
