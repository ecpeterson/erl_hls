-module(hls_spacetime_sdf_tests).
-include_lib("eunit/include/eunit.hrl").

%% Fixtures exercise preserved SDF syntax; their invented values are not vendor measurements.
-spec preserved_forms_test() -> ok.
preserved_forms_test() ->
    with_file(fixture(), fun(Path, Options) ->
        Parsed = hls_spacetime_sdf:read(Path, Options),
        #{cells := [Top, Register], timescale := #{magnitude := <<"1">>, unit := ps}} = Parsed,
        ?assertEqual(<<>>, maps:get(instance, Top)),
        ?assertEqual(<<"dut/r\\[0\\]">>, maps:get(instance, Register)),
        ?assertEqual(<<"FDRE">>, maps:get(celltype, Register)),
        Form = maps:get(form, Register),
        ?assert(lists:member(<<"-25.0:-23.0:-23.0">>, tokens(Form))),
        ?assert(lists:member(<<"::0.3">>, tokens(Form))),
        ?assert(lists:member(<<"TIMINGCHECK">>, tokens(Form))),
        ?assert(lists:member(<<"COND">>, tokens(Form))),
        ?assert(lists:member(<<"UNFAMILIAR">>, tokens(Form))),
        ?assert(lists:member(<<"\"(preserved)\"">>, tokens(Form))),
        Description = hls_spacetime_sdf:describe(Parsed),
        ?assertEqual(ok, hls_spacetime_sdf:validate_description(Description)),
        ?assertNot(maps:is_key(cells, Description)),
        ?assertNot(maps:is_key(headers, Description)),
        ?assertMatch(#{<<"counts">> := #{<<"cells">> := 2}},
            json:decode(iolist_to_binary(json:encode(Description))))
    end).

%% Digest/provenance mismatches must fail before any timing evidence is admitted.
-spec provenance_test() -> ok.
provenance_test() ->
    with_file(fixture(), fun(Path, Options) ->
        ?assertError({spacetime_sdf, digest_mismatch},
            hls_spacetime_sdf:read(Path, Options#{sha256 := binary:copy(<<"0">>, 64)})),
        ?assertError({spacetime_sdf, process_corner},
            hls_spacetime_sdf:read(Path, Options#{corner := typical})),
        ?assertError({spacetime_sdf, provenance},
            hls_spacetime_sdf:read(Path, Options#{mode := simulation}))
    end).

%% Malformed framing, contradictory metadata and bounded nesting reject without partial results.
-spec malformed_test_() -> [term()].
malformed_test_() ->
    [?_test(with_file(Bytes, fun(Path, Options) ->
        ?assertException(error, {spacetime_sdf, _}, hls_spacetime_sdf:read(Path, Options))
    end)) || Bytes <- [
        <<"(DELAYFILE (TIMESCALE 1ps)">>,
        <<"(DELAYFILE (TIMESCALE 1ps)) (EXTRA)">>,
        <<"(OTHER (TIMESCALE 1ps))">>,
        <<"(DELAYFILE (TIMESCALE 1ps) (TIMESCALE 1ns))">>,
        <<"(DELAYFILE (TIMESCALE 0ps))">>,
        <<"(DELAYFILE (TIMESCALE 1fortnight))">>,
        <<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"FDRE\")))">>,
        <<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"FDRE\") (INSTANCE a) (INSTANCE b)))">>,
        <<"(DELAYFILE (TIMESCALE 1ps) (VENDOR \"unfinished))">>,
        <<"(DELAYFILE (TIMESCALE 1ps)) /* unfinished">>,
        iolist_to_binary([binary:copy(<<"(">>, 129), binary:copy(<<")">>, 129)])
    ]].

%% Adjacent unit spelling and comments do not change the declared timing unit.
-spec adjacent_timescale_test() -> ok.
adjacent_timescale_test() ->
    with_file(<<"// heading\n(DELAYFILE /* middle */ (TIMESCALE 10ns)) // tail">>,
        fun(Path, Options) ->
            ?assertMatch(#{timescale := #{magnitude := <<"10">>, unit := ns}},
                hls_spacetime_sdf:read(Path, Options))
        end).

%% Serialized metadata/counts cannot contradict the forms preserved in the same artifact.
-spec derived_metadata_test() -> ok.
derived_metadata_test() ->
    with_file(fixture(), fun(Path, Options) ->
        P = hls_spacetime_sdf:read(Path, Options),
        #{cells := [C | Cs], counts := Counts} = P,
        ?assertError({spacetime_sdf, cell_metadata},
            hls_spacetime_sdf:validate(P#{cells := [C#{instance := <<"wrong">>} | Cs]})),
        ?assertError({spacetime_sdf, node_count},
            hls_spacetime_sdf:validate(P#{counts := Counts#{nodes := 1}})),
        ?assertError({spacetime_sdf, timescale_mismatch},
            hls_spacetime_sdf:validate(P#{timescale := #{magnitude => <<"1">>, unit => ns}})),
        D = hls_spacetime_sdf:describe(P),
        ?assertError({spacetime_sdf, population_digest},
            hls_spacetime_sdf:validate_description(D#{instance_population_sha256 := <<"wrong">>}))
    end).

%% Serialized tokens must obey the same lexical boundary as the raw reader, without trimming.
-spec serialized_tokens_test() -> ok.
serialized_tokens_test() ->
    with_file(<<"(DELAYFILE (TIMESCALE 1ps) (EXT x))">>, fun(Path, Options) ->
        P = hls_spacetime_sdf:read(Path, Options),
        #{headers := [Scale, [Extension, _]]} = P,
        Validate = fun(Kind, Lexeme) ->
            hls_spacetime_sdf:validate(P#{
                headers := [Scale, [Extension, #{kind => Kind, lexeme => Lexeme}]]
            })
        end,
        lists:foreach(fun({Kind, Lexeme}) ->
            ?assertEqual(ok, Validate(Kind, Lexeme))
        end, [
            {symbol, <<"plain">>},
            {symbol, <<"escaped\\ space">>},
            {symbol, <<"dut/r\\[0\\]">>},
            {string, <<"\"escaped\\\"quote\"">>}
        ]),
        lists:foreach(fun({Kind, Lexeme}) ->
            ?assertException(error, {spacetime_sdf, _}, Validate(Kind, Lexeme))
        end, [
            {symbol, <<"(">>},
            {symbol, <<")">>},
            {symbol, <<"(a)">>},
            {symbol, <<"a b">>},
            {symbol, <<" a">>},
            {symbol, <<"a ">>},
            {symbol, <<"/* comment */a">>},
            {symbol, <<"// comment\na">>},
            {symbol, <<"a /* comment */">>},
            {symbol, <<"a\\">>},
            {symbol, <<"\"a\"">>},
            {string, <<"a">>},
            {string, <<"\"a\"b\"">>},
            {string, <<"\"a\" \"b\"">>},
            {string, <<" \"a\"">>},
            {string, <<"\"a\" ">>},
            {string, <<"\"a\\\"">>}
        ])
    end).

%% Includes actual Vivado form shapes and deliberately unfamiliar extensions without interpreting them.
-spec fixture() -> binary().
fixture() ->
    <<"(DELAYFILE\n"
      " (SDFVERSION \"3.0\") (TIMESCALE 1 ps) (DIVIDER /)\n"
      " (VENDOR_EXT (x \"opaque\"))\n"
      " (CELL (CELLTYPE \"top\") (INSTANCE)\n"
      "   (DELAY (ABSOLUTE (INTERCONNECT a/O dut/r\\[0\\]/D (1::3) (2:4:6)))))\n"
      " (CELL (CELLTYPE \"FDRE\") (INSTANCE dut/r\\[0\\])\n"
      "   (DELAY (PATHPULSEPERCENT (30.0))\n"
      "     (ABSOLUTE (COND CE (IOPATH (posedge C) Q (-0.1::0.2) (::0.3)))))\n"
      "   (TIMINGCHECK (SETUPHOLD (posedge D) (posedge C) (-25.0:-23.0:-23.0) (46.0:46.0:46.0)))\n"
      "   (UNFAMILIAR x \"(preserved)\")))\n">>.

%% Collect token spellings only for fixture assertions; the maintained reader preserves nested shapes.
-spec tokens(hls_spacetime_sdf:form()) -> [binary()].
tokens(#{lexeme := Lexeme}) -> [Lexeme];
tokens(List) -> lists:append([tokens(N) || N <- List]).

%% Test-owned temporary sidecars always disappear, including after deliberate rejections.
-spec with_file(binary(), fun((file:filename(), hls_spacetime_sdf:options()) -> term())) -> ok.
with_file(Bytes, Fun) ->
    Path = filename:join("/tmp", "spacetime-sdf-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = file:write_file(Path, Bytes, [exclusive]),
    Options = #{corner => fast, mode => sta,
        sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase)},
    try Fun(Path, Options), ok after ok = file:delete(Path) end.
