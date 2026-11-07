-module(xls_protocol_spacetime_capture_tests).
-include_lib("eunit/include/eunit.hrl").

%% Synthetic adapter fixtures qualify rejection behavior, never measured hardware.
-spec exact_binding_rejections_test() -> ok.
exact_binding_rejections_test() ->
    {Plan, Trace, Build} = fixture([[0, 0, 1, 0, 7, 1]]),
    Signals = maps:get(signals, Trace),
    [Public, Tap | Rest] = Signals,
    ?assertException(
        error,
        {spacetime_tap_binding, _, _, _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace#{signals := [Public | Rest]}, Build)
    ),
    ?assertException(
        error,
        {spacetime_tap_binding, _, _, _},
        xls_protocol_spacetime_capture:bundle(
            Plan, Trace#{signals := [Public, Tap#{width := 2} | Rest]}, Build
        )
    ),
    ?assertException(
        error,
        {spacetime_tap_binding, _, _, _},
        xls_protocol_spacetime_capture:bundle(
            Plan, Trace#{signals := [Public, Tap#{path := <<"other.core.reset">>} | Rest]}, Build
        )
    ),
    ?assertException(
        error,
        {spacetime_build_binding, rtl, _, _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build#{rtl := <<"other-rtl">>})
    ),
    ?assertException(
        error,
        {spacetime_build_binding, source, _, _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build#{source := <<"other-source">>})
    ),
    ?assertException(
        error,
        {spacetime_build_binding, observation, _, _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build#{
            observation := <<"other-observation">>
        })
    ).

%% Narrowed owner codes cannot be interpreted as the original free/full/leased values.
-spec narrowed_owner_encoding_test() -> ok.
narrowed_owner_encoding_test() ->
    {Plan, Trace, Build} = owner_fixture(#{
        signal => <<"owner">>, source_width => 2, physical_width => 1
    }),
    ?assertException(
        error,
        {unsupported_owner_encoding, [0, 0, 1, 0, 0], _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build)
    ).

%% An eliminated owner is a missing observation, even if a source tuple path survives.
-spec eliminated_owner_encoding_test() -> ok.
eliminated_owner_encoding_test() ->
    {Plan, Trace, Build} = owner_fixture(#{signal => null, source_width => 2}),
    ?assertException(
        error,
        {unsupported_owner_encoding, [0, 0, 1, 0, 0], _},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build)
    ).

%% No semantic sampling is needed to reject an unsupported declared capture owner.
-spec owner_fixture(map()) -> {map(), map(), map()}.
owner_fixture(Owner) ->
    {Original, Trace, Build} = fixture([[0, 0, 1, 0, 7, 1]]),
    Actor = #{actor => 0, inbox => #{<<"slots">> => [#{<<"link">> => 0, <<"slot">> => 0}]}},
    Plan = Original#{
        actors := [Actor],
        state := [Owner#{tuple_path => [0, 0, 1, 0, 0]} | maps:get(state, Original)]
    },
    {Plan, Trace, Build#{observation := observation_digest(Plan)}}.

%% Adjacent observations must honor the actual prior enable and selected D value.
-spec corrupt_register_transition_test() -> ok.
corrupt_register_transition_test() ->
    {Plan, Trace, Build} = fixture([[0, 0, 1, 0, 7, 1], [0, 0, 1, 8, 7, 1]]),
    ?assertException(
        error,
        {spacetime_register_transfer, <<"q">>, 7, 8},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build)
    ).

%% Equal-valued enabled writes still create separate word versions and occurrences.
-spec same_value_write_test() -> ok.
same_value_write_test() ->
    {Plan, Trace, Build} = fixture([[0, 0, 1, 0, 7, 1], [0, 0, 1, 7, 7, 1]]),
    #{events := Events} = xls_protocol_spacetime_capture:bundle(Plan, Trace, Build),
    Versions = [V || #{access := #{kind := write, after_version := V}} <- Events],
    ?assertEqual(2, length(Versions)),
    ?assertEqual(2, length(lists:usort(Versions))).

%% A disabled write does not mint a storage version merely because D differs.
-spec disabled_write_test() -> ok.
disabled_write_test() ->
    {Plan, Trace, Build} = fixture([[0, 0, 1, 0, 7, 0], [0, 0, 1, 0, 7, 0]]),
    #{events := Events, versions := Versions} = xls_protocol_spacetime_capture:bundle(
        Plan, Trace, Build
    ),
    ?assertEqual([], Events),
    ?assertEqual([], Versions).

%% Reset identity must be observed at both the wrapper and compiled boundary.
-spec reset_binding_test() -> ok.
reset_binding_test() ->
    {Plan, Trace, Build} = fixture([[1, 0, 1, 0, 0, 0]]),
    ?assertException(
        error,
        {spacetime_reset_binding, 0, true, false},
        xls_protocol_spacetime_capture:bundle(Plan, Trace, Build)
    ).

%% The reset edge starts a fresh incarnation; new word roots cannot reuse old ones.
-spec reset_incarnation_test() -> ok.
reset_incarnation_test() ->
    {Plan, Trace, Build} = fixture([
        [0, 0, 1, 0, 7, 1],
        [1, 1, 1, 7, 0, 0],
        [0, 0, 1, 0, 9, 1],
        [0, 0, 1, 9, 9, 1]
    ]),
    #{capture := #{incarnations := Epochs}, versions := Versions} = xls_protocol_spacetime_capture:bundle(
        Plan, Trace, Build
    ),
    ?assertEqual(
        [
            #{id => <<"reset/0">>, first_cycle => 0, end_cycle => 1},
            #{id => <<"reset/1">>, first_cycle => 1, end_cycle => 4}
        ],
        Epochs
    ),
    Roots = [
        {I, V}
     || #{id := V, incarnation := I, producer := root, storage := #{resource := _}} <- Versions
    ],
    ?assertEqual(2, length(Roots)),
    ?assertEqual([<<"reset/0">>, <<"reset/1">>], lists:sort([I || {I, _} <- Roots])).

%% A terminating failure cannot be relabeled complete before reaching the adapter.
-spec false_complete_footer_test() -> ok.
false_complete_footer_test() ->
    Path = filename:join(
        "/tmp", "spacetime_false_complete_" ++ integer_to_list(erlang:unique_integer([positive]))
    ),
    Text =
        <<"H\tspacetime_cycle_trace\t1\n",
            "P\treset\tinput_valid\tinput_data\tinput_last\toutput_ready\tinput_ready\toutput_valid\toutput_data\toutput_last\tfault\trunning\n",
            "S\t0\t1\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n", "F\t1\tcomplete\t1\t1\t4294\tkilled\n">>,
    ok = file:write_file(Path, Text),
    try
        ?assertException(error, {spacetime_trace, footer_cause}, hls_spacetime_trace:read(Path))
    after
        ok = file:delete(Path)
    end.

%% The source manifest digest cannot certify a modified file behind the same name.
-spec changed_source_input_test() -> ok.
changed_source_input_test() ->
    Directory = filename:join(
        "/tmp", "spacetime_source_binding_" ++ integer_to_list(erlang:unique_integer([positive]))
    ),
    ok = file:make_dir(Directory),
    Source = filename:join(Directory, "receiver.x"),
    Manifest = filename:join(Directory, "source-build.json"),
    Expected = binary:encode_hex(crypto:hash(sha256, <<"original source">>), lowercase),
    ok = file:write_file(Source, <<"modified source">>),
    ok = file:write_file(
        Manifest, json:encode(#{inputs => [#{file => <<"receiver.x">>, sha256 => Expected}]})
    ),
    try
        ?assertException(
            error,
            {spacetime_source_binding, <<"receiver.x">>, Expected, _},
            xls_protocol_spacetime:plan(
                Directory, "unreachable-raw", "unreachable-opt", "unreachable-rtl"
            )
        )
    after
        ok = file:delete(Source),
        ok = file:delete(Manifest),
        ok = file:del_dir(Directory)
    end.

%% One synthetic physical register is enough to exercise transfer/binding contracts.
-spec fixture([[non_neg_integer()]]) -> {map(), map(), map()}.
fixture(Rows) ->
    Signals = [
        tap(Name, Width)
     || {Name, Width} <- [
            {<<"input_reset">>, 1},
            {<<"p0_stage_done">>, 1},
            {<<"q">>, 16},
            {<<"d">>, 16},
            {<<"enable">>, 1}
        ]
    ],
    Plan = #{
        schema => 1,
        signals => Signals,
        actors => [],
        unsupported => [],
        registers => [
            #{
                name => <<"q">>,
                width => 16,
                enable => <<"enable">>,
                data => <<"d">>,
                rule => enabled_same_edge_register_write
            }
        ],
        state => [
            #{tuple_path => [0, 0], signal => <<"q">>, source_width => 16, physical_width => 16}
        ],
        inputs => #{rtl => <<"rtl">>, source_build => <<"source">>}
    },
    Trace = #{
        signals => [#{id => <<"reset">>, width => 1, path => <<"public">>} | Signals],
        spans => [
            #{first => I, count => 1, values => Values}
         || {I, Values} <- lists:enumerate(0, Rows)
        ],
        end_cycle => length(Rows),
        complete => true,
        cause => <<"ok">>,
        records => length(Rows)
    },
    {Plan, Trace, #{
        source => <<"source">>, rtl => <<"rtl">>, observation => observation_digest(Plan)
    }}.

%% Test bindings follow the production native-plan identity convention exactly.
-spec observation_digest(map()) -> binary().
observation_digest(Plan) ->
    xls_protocol_spacetime:observation_digest(Plan).

%% The test declares module-local paths without pretending to bind a real RTL build.
-spec tap(binary(), pos_integer()) -> map().
tap(Name, Width) ->
    #{
        id => <<"signal/", Name/binary>>,
        name => Name,
        width => Width,
        path => <<"test.core.", Name/binary>>,
        actor => null,
        meaning => <<"fixture">>,
        evidence => <<"Synthetic adapter contract fixture">>
    }.
