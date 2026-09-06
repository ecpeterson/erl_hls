-module(phi_syndrome_replay_cell_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

request_stream_is_deterministic_and_nontrivial_test() ->
    Seed = 16#9e3779b9,
    Threshold = 16#80000000,
    {ok, configuring, Empty} = phi_syndrome_replay_cell:init([]),
    {next_state, waiting, Configured} = phi_syndrome_replay_cell:configuring(
        cast,
        #phenom_config{seed = Seed, threshold = Threshold, x = 1, y = 2},
        Empty
    ),
    FirstRandom = hls_prng:xorshift32(Seed),
    FirstMeasurement = measurement(FirstRandom, Threshold),
    {next_state, announcing, First} = phi_syndrome_replay_cell:waiting(
        cast,
        #phenom_request{step = 0}, Configured
    ),
    {keep_state, First, [{cast, phi, #phenom_anyon{
        step = 0,
        flags = FirstMeasurement,
        x = 1,
        y = 2
    }}]} = phi_syndrome_replay_cell:announcing(
        enter,
        waiting, First
    ),

    SecondRandom = hls_prng:xorshift32(FirstRandom),
    SecondMeasurement = measurement(SecondRandom, Threshold),
    SecondAnnouncement = SecondMeasurement bxor FirstMeasurement,
    {repeat_phase, Second} =
        phi_syndrome_replay_cell:announcing(
            cast,
            #phenom_request{step = 1}, First
        ),
    {keep_state, Second, [{cast, phi, #phenom_anyon{
        step = 1,
        flags = SecondAnnouncement,
        x = 1,
        y = 2
    }}]} = phi_syndrome_replay_cell:announcing(
        enter,
        announcing, Second
    ),
    ?assertMatch(
        {stop, fail, Second},
        phi_syndrome_replay_cell:announcing(
            cast,
            #phenom_request{step = 1}, Second
        )
    ).

measurement(Random, Threshold) when Random < Threshold -> 1;
measurement(_Random, _Threshold) -> 0.
