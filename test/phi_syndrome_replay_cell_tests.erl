-module(phi_syndrome_replay_cell_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

request_stream_is_deterministic_and_nontrivial_test() ->
    Seed = 16#9e3779b9,
    Threshold = 16#80000000,
    {ok, configuring, Empty} = phi_syndrome_replay_cell:init([]),
    {waiting, Configured, consume} = phi_syndrome_replay_cell:handle_cast(
        #phenom_config{seed = Seed, threshold = Threshold, x = 1, y = 2},
        configuring,
        Empty
    ),
    FirstRandom = hls_prng:xorshift32(Seed),
    FirstMeasurement = measurement(FirstRandom, Threshold),
    {announcing, First, consume} = phi_syndrome_replay_cell:handle_cast(
        #phenom_request{step = 0}, waiting, Configured
    ),
    {First, [{cast, phi, #phenom_anyon{
        step = 0,
        flags = FirstMeasurement,
        x = 1,
        y = 2
    }}]} = phi_syndrome_replay_cell:handle_enter(
        waiting, announcing, First
    ),

    SecondRandom = hls_prng:xorshift32(FirstRandom),
    SecondMeasurement = measurement(SecondRandom, Threshold),
    SecondAnnouncement = SecondMeasurement bxor FirstMeasurement,
    {repeat_phase, Second, consume} =
        phi_syndrome_replay_cell:handle_cast(
            #phenom_request{step = 1}, announcing, First
        ),
    {Second, [{cast, phi, #phenom_anyon{
        step = 1,
        flags = SecondAnnouncement,
        x = 1,
        y = 2
    }}]} = phi_syndrome_replay_cell:handle_enter(
        announcing, announcing, Second
    ),
    ?assertMatch(
        {announcing, Second, fail},
        phi_syndrome_replay_cell:handle_cast(
            #phenom_request{step = 1}, announcing, Second
        )
    ).

measurement(Random, Threshold) when Random < Threshold -> 1;
measurement(_Random, _Threshold) -> 0.
