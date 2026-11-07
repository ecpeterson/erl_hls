-module(hls_spacetime_sdf_arcs_tests).
-include_lib("eunit/include/eunit.hrl").

%% Synthetic SDF checks annotation extraction, not native correctness.
-spec complete_annotation_projection_test() -> ok.
complete_annotation_projection_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ns) (CELL (CELLTYPE \"LUT2\") (INSTANCE dut/lut\\[0\\]) (DELAY (ABSOLUTE (IOPATH I0 O (.1:.2:.3) (.2:.3:.4)) (COND A == 1 (IOPATH I1 O (1:2:3) (2:3:4)))))))">>, fun(P) ->
        #{arcs := [A, B], issues := []} = hls_spacetime_sdf_arcs:project(P),
        ?assertEqual(<<"dut/lut[0]">>, maps:get(cell, A)),
        ?assertEqual(400.0, maps:get(max_ps, A)),
        ?assertEqual(4000, maps:get(max_ps, B)),
        ?assertEqual([], maps:get(guards, A)),
        ?assertEqual(1, length(maps:get(guards, B))),
        ?assertEqual(2, length(maps:get(delay, B))),
        ?assertEqual(<<"I1">>, maps:get(from, B))
    end).

%% Sequential C-to-Q annotations stay available but do not turn into D-to-Q combinational edges.
-spec transition_and_interconnect_test() -> ok.
transition_and_interconnect_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"FDRE\") (INSTANCE ff) (DELAY (ABSOLUTE (IOPATH (posedge C) Q (1:2:3) (4:5:6))))) (CELL (CELLTYPE \"top\") (INSTANCE) (DELAY (ABSOLUTE (INTERCONNECT ff/Q lut/I0 (10:20:30) (11:21:31))))))">>, fun(P) ->
        #{arcs := [A, B]} = hls_spacetime_sdf_arcs:project(P),
        ?assertEqual(<<"posedge">>, maps:get(transition, A)),
        ?assertEqual(<<"C">>, maps:get(from, A)),
        ?assertEqual(interconnect, maps:get(kind, B)),
        ?assertEqual(<<>>, maps:get(cell, B)),
        ?assertEqual(<<"ff/Q">>, maps:get(from, B)),
        ?assertEqual(31, maps:get(max_ps, B))
    end).

%% Unknown slots and incremental values cannot manufacture an absolute delay.
-spec missing_incremental_and_unknown_test() -> ok.
missing_incremental_and_unknown_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY (ABSOLUTE (IOPATH I0 O (::3) (1:2:3))) (INCREMENT (IOPATH I0 O (1) (2))) (UNFAMILIAR (x)))))">>, fun(P) ->
        #{arcs := [A, B], issues := [Issue]} = hls_spacetime_sdf_arcs:project(P),
        ?assertEqual(null, maps:get(max_ps, A)),
        ?assertEqual(null, maps:get(max_ps, B)),
        ?assertEqual(1, length(maps:get(guards, B))),
        ?assertEqual(<<"uninterpreted_delay_form">>, maps:get(reason, Issue))
    end).

%% Signed and exponent decimal spellings remain bounded numeric annotations.
-spec decimal_envelope_test() -> ok.
decimal_envelope_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY (ABSOLUTE (IOPATH I0 O (-.2:+.3:1e2) (2E1))))))">>, fun(P) ->
        #{arcs := [A]} = hls_spacetime_sdf_arcs:project(P),
        ?assertEqual(100.0, maps:get(max_ps, A))
    end).

%% Recognized malformed arcs fail rather than returning a misleading prefix.
-spec malformed_arc_test() -> ok.
malformed_arc_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY (ABSOLUTE (IOPATH I0 O)))))">>, fun(P) ->
        ?assertError({spacetime_sdf_arcs, missing_delay}, hls_spacetime_sdf_arcs:project(P))
    end).

%% The lexical reader is not a complete grammar validator; omitted mode is not ABSOLUTE.
-spec missing_delay_mode_test() -> ok.
missing_delay_mode_test() ->
    lists:foreach(fun(Arc) ->
        with_sdf(iolist_to_binary([
            <<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY ">>,
            Arc, <<")))">>
        ]), fun(P) ->
            ?assertError({spacetime_sdf_arcs, missing_delay_mode}, hls_spacetime_sdf_arcs:project(P))
        end)
    end, [
        <<"(IOPATH I0 O (1:2:3))">>,
        <<"(INTERCONNECT ff/Q lut/I0 (1:2:3))">>,
        <<"(COND A == 1 (IOPATH I0 O (1:2:3)))">>,
        <<"(CONDELSE (IOPATH I0 O (1:2:3)))">>
    ]).

%% A nested ABSOLUTE wrapper cannot turn incremental values into absolute timing.
-spec nested_delay_mode_test() -> ok.
nested_delay_mode_test() ->
    with_sdf(<<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY (INCREMENT (ABSOLUTE (IOPATH I0 O (1:2:3)))))))">>, fun(P) ->
        ?assertError({spacetime_sdf_arcs, nested_delay_mode}, hls_spacetime_sdf_arcs:project(P))
    end).

%% Temporary fixtures use the existing authenticated parser and disappear after each test.
-spec with_sdf(binary(), fun((hls_spacetime_sdf:parsed()) -> term())) -> ok.
with_sdf(Bytes, Fun) ->
    Name = filename:join("/tmp", "spacetime-sdf-arcs-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = file:write_file(Name, Bytes),
    try
        Digest = binary:encode_hex(crypto:hash(sha256, Bytes), lowercase),
        Parsed = hls_spacetime_sdf:read(Name, #{sha256 => Digest, corner => slow, mode => sta}),
        Fun(Parsed), ok
    after file:delete(Name) end.
