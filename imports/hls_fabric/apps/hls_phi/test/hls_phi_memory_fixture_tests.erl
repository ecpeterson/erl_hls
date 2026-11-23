-module(hls_phi_memory_fixture_tests).
-moduledoc "Board-sized and D3 experiments retain complete correction and measurement witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Independent schedules agree on every correction, quiet status and final data result.
-spec noisy_measurement_test() -> ok.
noisy_measurement_test() ->
    {_, _, Options} = hls_phi_memory_fixture:fixture(board_memory),
    First = hls_phi_memory_fixture:cpu(Options, 2000),
    ?assertEqual(First, hls_phi_memory_fixture:cpu(Options, 2000)),
    ?assertMatch(#{correction_count := 34, closeout_step := 17,
        data_counts := #{commutes := 8, anticommutes := 0}}, phi_memory_demo:summary(First)).

%% Zero-noise D2 exercises the same fence without correction feedback.
-spec quiet_measurement_test() -> ok.
quiet_measurement_test() ->
    {_, _, Options} = hls_phi_memory_fixture:fixture(board_quiet),
    Witness = hls_phi_memory_fixture:cpu(Options, 2000),
    ?assertMatch(#{correction_count := 0, closeout_step := 18,
        data_counts := #{commutes := 8, anticommutes := 0}}, phi_memory_demo:summary(Witness)).

%% The default experiment remains the public D3 regression golden.
-spec d3_closeout_test() -> ok.
d3_closeout_test() ->
    #{options := Options, noise_rate := Rate} = phi_memory_demo:fixture(),
    Witness = hls_phi_memory_fixture:cpu(Options#{noise_rate => Rate}, 2000),
    ?assertEqual(ok, phi_memory_demo:verify({ok, Witness})).
