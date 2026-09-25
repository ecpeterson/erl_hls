-module(hls_serial_lowering_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Calls and record fields discover the companion without manual imports.
-spec provider_and_failure_origins_test() -> ok.
provider_and_failure_origins_test() ->
    Source = "test/hls_serial_fixture.erl",
    {ok, Forms} = xls_parse:parse_file(Source),
    ?assert(lists:member(hls_serial, xls_dslx_imports:from_forms(Forms))),
    {_, Origins} = xls_failure_sites:prepare(Forms),
    Generated = xls_parse:to_xls(Source),
    Sites = xls_failure_sites:from_artifact(Origins, Generated),
    Failures = [Site || Site = #{kind := badarg} <- Sites],
    ?assertEqual(2, length(Failures)),
    lists:foreach(fun(#{code := Code, file := File, line := Line}) ->
        ?assertEqual(14, Code band 15),
        ?assertEqual(<<"hls_serial_fixture.erl">>, File),
        ?assert(Line > 0)
    end, Failures).

%% Record codecs normalize counter fields and callbacks cross zero in both directions.
-spec actor_rollover_test() -> ok.
actor_rollover_test() ->
    Clock = hls_serial_fixture:init([]),
    {reply, {report, 1, 3, false}, Next} =
        hls_serial_fixture:handle_call({advance, 3}, Clock),
    ?assertEqual({reply, {report, 1, 3, false}, Next},
        hls_serial_fixture:handle_call({inspect, 16#fffffffe, true}, Next)),
    ?assertEqual({reply, {report, 1, 0, false}, Next},
        hls_serial_fixture:handle_call({inspect, 16#80000001, false}, Next)),
    ?assertError(badarg,
        hls_serial_fixture:handle_call({inspect, 16#80000001, true}, Next)),
    {reply, {report, 16#fffffffe, -3, false}, _} =
        hls_serial_fixture:handle_call({advance, -3}, Next),
    Packed = hls_serial_fixture:pack({load, (1 bsl 1000) + 7}),
    ?assertEqual(<<7:32/little>>, Packed).
