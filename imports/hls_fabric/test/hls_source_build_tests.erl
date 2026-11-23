-module(hls_source_build_tests).
-moduledoc "Source toolchain configuration and command boundary regressions; no hardware qualification.".
-include_lib("eunit/include/eunit.hrl").

%% Application terms retain the established whole, split and mixed ownership policies.
-spec repetition_config_test() -> ok.
repetition_config_test() ->
    {application, #{actor_limit := 6, sources := Sources, device := board, host := 1,
        topology := {phi_repetition_topology, topology, [2, 16#80000000]}}} = phi_protocol_config:repetition(2, #{}),
    ?assertEqual(4, length(Sources)),
    {deployment, #{devices := Devices}} = phi_protocol_config:repetition(6, #{split => 3}),
    #{0 := #{native_actors := A, service := 7}, 1 := #{native_actors := B, service := 17}} = Devices,
    ?assertEqual(9, length(A)), ?assertEqual(9, length(B)),
    ?assertEqual([], A -- (A -- B)),
    ?assertEqual(lists:sort([{F, X, 0} || F <- [data, syndrome, phi], X <- lists:seq(0, 5)]), lists:sort(A ++ B)),
    {mixed, #{native_actors := Native}} = phi_protocol_config:repetition(3, #{mixed => true}),
    ?assertEqual(6, length(Native)),
    ?assertEqual([], [Id || Id = {data, _, _} <- Native]),
    {application, #{arithmetic_groups := [[{phi,0,0},{phi,1,0},{phi,2,0}]], inspection := process}} =
        phi_protocol_config:repetition(3, #{share_arithmetic => true, inspect => true}),
    ok.

%% Invalid combinations fail at configuration, before any emitter writes hardware.
-spec repetition_rejection_test() -> ok.
repetition_rejection_test() ->
    ?assertError({repetition_width, 1}, phi_protocol_config:repetition(1, #{})),
    ?assertError({repetition_width, 17}, phi_protocol_config:repetition(17, #{})),
    ?assertError({repetition_split, 0}, phi_protocol_config:repetition(6, #{split => 0})),
    ?assertError({repetition_split, 6}, phi_protocol_config:repetition(6, #{split => 6})),
    ?assertError({repetition_split, 3}, phi_protocol_config:repetition(6, #{split => 3, inspect => true})),
    ?assertError({repetition_split, 3}, phi_protocol_config:repetition(6, #{split => 3, mixed => true})),
    ?assertError(repetition_mixed_inspection, phi_protocol_config:repetition(3, #{mixed => true, inspect => true})),
    ?assertError(repetition_shared_placement, phi_protocol_config:repetition(4, #{share_arithmetic => true})),
    ?assertError({repetition_flag, mixed, yes}, phi_protocol_config:repetition(3, #{mixed => yes})),
    ok.

%% CLI errors are deterministic and do not silently ignore unsupported options.
-spec cli_rejection_test() -> ok.
cli_rejection_test() ->
    ?assertException(error, {hls_diagnostic, #{code := unknown_command}}, hls_fabric_cli:run(["build"])),
    ?assertException(error, {hls_diagnostic, #{code := missing_option}}, hls_fabric_cli:run(["emit"])),
    ?assertException(error, {hls_diagnostic, #{code := unknown_emitter}}, hls_fabric_cli:run(["emit", "--kind", "foreign"])),
    ?assertError({repetition_width, 17},
        phi_protocol_cli:run(["--output", "unused", "--width", "bad", "--width", "17"])),
    ?assertException(error, {hls_diagnostic, #{code := invalid_integer}}, phi_protocol_cli:run(["--output", "unused", "--width", "bad"])),
    ?assertException(error, {hls_diagnostic, #{code := unknown_option}}, hls_fabric_cli:run(["emit", "--xls", "path"])),
    ?assertException(error, {hls_diagnostic, #{code := missing_option_value}}, hls_fabric_cli:run(["emit", "--config", "--output", "fresh"])),
    ok.
