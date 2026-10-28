-module(telemetry_example_tests).
-moduledoc "Checks the connected telemetry CPU example, independent arithmetic and portable bundle contract without external tools.".
-include_lib("eunit/include/eunit.hrl").
-include("../src/examples/telemetry/telemetry.hrl").

%% Saturation is strict; signed endpoints themselves are not clipped.
-spec oracle_boundaries_test() -> ok.
oracle_boundaries_test() ->
    Commands = [#configure{offset = 0, gain = 1},
        #raw{sequence = 7, value = -32768}, #raw{sequence = 7, value = 32767},
        #raw{sequence = 2, value = 0}, #raw{sequence = 65535, value = -1}],
    Expected = [#summary{sequence = 65535, sum = -2, minimum = -32768,
        maximum = 32767, clipped = 0}],
    ?assertEqual(Expected, telemetry_example_fixture:oracle(Commands)),
    ?assertEqual(Expected, telemetry:run(Commands)),
    ZeroGain = [#configure{offset = 32767, gain = 0} | tl(Commands)],
    ZeroExpected = [#summary{sequence = 65535, sum = 131068, minimum = 32767,
        maximum = 32767, clipped = 0}],
    ?assertEqual(ZeroExpected, telemetry_example_fixture:oracle(ZeroGain)),
    ?assertEqual(ZeroExpected, telemetry:run(ZeroGain)).

%% Both actual actor processes must agree with arithmetic independent of callbacks.
-spec connected_cpu_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
connected_cpu_test_() -> {timeout, 30, fun() ->
    Commands = telemetry_example_fixture:commands(),
    Reports = telemetry_example_fixture:oracle(Commands),
    ?assertEqual(#summary{sequence = 3, sum = -501, minimum = -32768,
        maximum = 32767, clipped = 2}, hd(Reports)),
    ?assertEqual(8, length(Reports)),
    ?assertEqual(Reports, telemetry:run(Commands)),
    Example = telemetry:example_commands(),
    ?assertEqual(telemetry_example_fixture:oracle(Example), telemetry:run(Example))
end}.

%% The topology's calibrator output cannot disappear silently during composition.
-spec missing_route_is_rejected_test() -> ok.
missing_route_is_rejected_test() ->
    Spec = telemetry_topology:topology(),
    ?assertError({unrouted_outputs, [{calibrator, readings}]},
        hls_topology:normalize(Spec#{routes := [{{window, report}, [{external, reports}]}]})).

%% Emission invokes only Erlang lowering; native tools are exercised by the local case.
-spec portable_bundle_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
portable_bundle_test_() -> {timeout, 60, fun portable_bundle/0}.

%% Published source and support hashes describe every retained input exactly.
-spec portable_bundle() -> ok.
portable_bundle() ->
    Root = filename:join("_build", "telemetry-bundle-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    try
        #{units := [Unit], inputs := Inputs} = telemetry:write_bundle(Root),
        ?assertMatch(#{source := <<"telemetry_topology.x">>, top := <<"Top">>,
            module := <<"telemetry_top">>, output := <<"telemetry.v">>}, Unit),
        Flags = maps:get(codegen_flags, Unit),
        ?assert(lists:member(<<"--pipeline_stages=2">>, Flags)),
        ?assert(lists:member(<<"--worst_case_throughput=1">>, Flags)),
        lists:foreach(fun(#{file := Name, sha256 := Expected}) ->
            {ok, Bytes} = file:read_file(filename:join(Root, Name)),
            ?assertEqual(Expected, binary:encode_hex(crypto:hash(sha256, Bytes), lowercase))
        end, Inputs),
        Names = [Name || #{file := Name} <- Inputs],
        ?assert(lists:member(<<"telemetry_calibrator.x">>, Names)),
        ?assert(lists:member(<<"telemetry_window.x">>, Names)),
        ?assert(lists:member(<<"telemetry_topology.x">>, Names)),
        AbsoluteRoot = filename:absname(Root),
        ?assertError({source_output_exists, AbsoluteRoot}, telemetry:write_bundle(Root))
    after
        ok = file:del_dir_r(Root)
    end.

%% Reserve a configuration slot, reject incomplete input, and delegate field bounds to the codecs.
-spec host_admission_test() -> ok.
host_admission_test() ->
    Config = #configure{offset = 1, gain = 2},
    Samples = [#raw{sequence = I, value = I} || I <- lists:seq(0, 3)],
    ?assertError(configuration_required, telemetry:run(Samples ++ [Config])),
    {Early, [Last]} = lists:split(3, Samples),
    ?assertEqual([#summary{sequence = 3, sum = 16, minimum = 1, maximum = 7, clipped = 0}],
        telemetry:run(Early ++ [Config, Last])),
    ?assertError({incomplete_window, 1}, telemetry:run([Config, Last])),
    ?assertError(badarg, telemetry:run([#configure{offset = 0, gain = 256}])),
    ?assertError(badarg, telemetry:run([Config, #raw{sequence = 0, value = 32768}])).
