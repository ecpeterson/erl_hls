-module(xls_protocol_spacetime_workflow_tests).
-moduledoc "Localized producer-file boundary checks. Synthetic samples exercise publication and integrity; they are not a generated hardware witness.".
-include_lib("eunit/include/eunit.hrl").

%% A fresh preparation can be interpreted after the original input paths disappear.
-spec independent_capture_test() -> ok.
independent_capture_test() ->
    with_directory(fun(Root) ->
        Prepared = filename:join(Root, "prepared"),
        Plan = fixture(),
        Preparation = #{plan => Plan, files => #{<<"rtl/core.v">> => <<"module core; endmodule\n">>},
            rtl => [<<"rtl/core.v">>], inputs => #{source => <<"/does/not/exist">>}},
        #{complete := true} = xls_protocol_spacetime_workflow:write(Preparation, Prepared),
        ?assertEqual(Plan, xls_protocol_spacetime_workflow:read_plan(Prepared)),
        Trace = filename:join(Root, "capture.tsv"),
        ok = file:write_file(Trace, trace(Plan)),
        Output = filename:join(Root, "capture"),
        Manifest = xls_protocol_spacetime_workflow:write_capture(Prepared, Trace, Output),
        ?assertMatch(#{complete := true, capture_complete := true, unit := cycle}, Manifest),
        {ok, Bytes} = file:read_file(filename:join(Output, "bundle.etf")),
        #{events := Events, versions := Versions} = Bundle = binary_to_term(Bytes, [safe]),
        ?assertEqual(2, length(Events)),
        ?assertEqual(5, length(Versions)),
        {ok, Json} = file:read_file(filename:join(Output, "bundle.json")),
        ?assertEqual(json:decode(iolist_to_binary(hls_spacetime:encode(Bundle))), json:decode(Json)),
        ?assertException(error, {badmatch, {error, eexist}},
            xls_protocol_spacetime_workflow:write_capture(Prepared, Trace, Output)),
        ok = file:write_file(filename:join(Prepared, "observation.etf"), <<131, 80, 0>>),
        ?assertException(error, _, xls_protocol_spacetime_workflow:read_plan(Prepared))
    end).

%% Valid manifests cannot legitimize compressed, trailing or executable plan encodings.
-spec encoded_plan_guard_test() -> ok.
encoded_plan_guard_test() ->
    with_directory(fun(Root) ->
        Prepared = filename:join(Root, "prepared"),
        Plan = fixture(),
        xls_protocol_spacetime_workflow:write(#{plan => Plan, files => #{}, rtl => [], inputs => #{}}, Prepared),
        Bytes = term_to_binary(Plan, [deterministic]),
        Invalid = [term_to_binary(Plan, [compressed]), <<Bytes/binary, 0>>,
            term_to_binary(Plan#{extra => fun() -> ok end}), term_to_binary(Plan#{extra => self()})],
        lists:foreach(fun(Encoded) ->
            replace_plan(Prepared, Encoded),
            ?assertException(error, _, xls_protocol_spacetime_workflow:read_plan(Prepared))
        end, Invalid)
    end).

%% Mutate both the bytes and descriptor so parser checks cannot rely solely on hash mismatch.
-spec replace_plan(file:filename(), binary()) -> ok.
replace_plan(Prepared, Encoded) ->
    Path = filename:join(Prepared, "manifest.json"),
    {ok, Bytes} = file:read_file(Path),
    #{<<"files">> := Files} = Manifest = json:decode(Bytes),
    Descriptor = #{<<"bytes">> => byte_size(Encoded),
        <<"sha256">> => binary:encode_hex(crypto:hash(sha256, Encoded), lowercase)},
    ok = file:write_file(filename:join(Prepared, "observation.etf"), Encoded),
    file:write_file(Path, json:encode(Manifest#{<<"files">> := Files#{<<"observation.etf">> := Descriptor}})).

%% Generated shell arguments preserve unusual literal filenames without executing substitutions.
-spec build_script_quoting_test() -> ok.
build_script_quoting_test() ->
    with_directory(fun(Root) ->
        Prepared = filename:join(Root, "prepared"),
        Name = <<"rtl/quoted ' $literal file.v">>,
        xls_protocol_spacetime_workflow:write(#{plan => fixture(),
            files => #{Name => <<"RTL">>}, rtl => [Name], inputs => #{}}, Prepared),
        {ok, Script} = file:read_file(filename:join(Prepared, "build-simulator.sh")),
        ?assertNotEqual(nomatch, binary:match(Script, <<"'rtl/quoted '\\'' $literal file.v'">>)),
        ?assertNotEqual(nomatch, binary:match(Script, <<"-j 1">>)),
        ?assertNotEqual(nomatch, binary:match(Script, <<"--vpi --public-flat-rw">>))
    end).

%% Unknown options fail before file lookup or source interpretation.
-spec option_rejection_test() -> ok.
option_rejection_test() ->
    ?assertException(error, {badmatch, _}, xls_protocol_spacetime_workflow:prepare(#{unknown => true})).

%% Explicit storage scope discloses omissions and creates no semantic stream attribution.
-spec storage_scope_test() -> ok.
storage_scope_test() ->
    with_directory(fun(Root) ->
        Plan = (fixture())#{observation_scope => storage,
            unavailable_semantics => #{unsupported_controls => [#{meaning => <<"accept">>}]}},
        Prepared = filename:join(Root, "prepared"),
        xls_protocol_spacetime_workflow:write(#{plan => Plan, files => #{}, rtl => [], inputs => #{}}, Prepared),
        Trace = filename:join(Root, "capture.tsv"),
        ok = file:write_file(Trace, trace(Plan)),
        Output = filename:join(Root, "capture"),
        ?assertMatch(#{observation_scope := storage, unavailable_semantics := #{unsupported_controls := [_]}},
            xls_protocol_spacetime_workflow:write_capture(Prepared, Trace, Output)),
        {ok, Bytes} = file:read_file(filename:join(Output, "bundle.etf")),
        #{events := Events, capture := #{evidence := Scope}} = binary_to_term(Bytes, [safe]),
        ?assertNotEqual(nomatch, binary:match(Scope, <<"Storage-only">>)),
        ?assertEqual([write, write], [maps:get(kind, maps:get(access, E)) || E <- Events]),
        {ok, Stream} = file:read_file(filename:join(Output, "stream.json")),
        ?assertEqual([], maps:get(<<"frames">>, json:decode(Stream)))
    end).

%% A new VM must load schema atoms itself before accepting ordinary catalogue and comparison terms.
-spec qualify_fresh_process_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
qualify_fresh_process_test_() -> {timeout, 15, fun qualify_fresh_process/0}.

%% Invented native objects qualify file/control plumbing only, never physical correspondence.
-spec qualify_fresh_process() -> ok.
qualify_fresh_process() ->
    with_directory(fun(Root) ->
        Plan = fixture(), Prepared = filename:join(Root, "prepared"),
        xls_protocol_spacetime_workflow:write(#{plan => Plan, files => #{}, rtl => [], inputs => #{}}, Prepared),
        Trace = filename:join(Root, "capture.tsv"), ok = file:write_file(Trace, trace(Plan)),
        Capture = filename:join(Root, "capture"),
        xls_protocol_spacetime_workflow:write_capture(Prepared, Trace, Capture),
        {ok, CapturedBytes} = file:read_file(filename:join(Capture, "bundle.etf")),
        Synthetic = (binary_to_term(CapturedBytes, [safe]))#{evidence := synthetic_fixture},
        SyntheticFile = filename:join(Root, "synthetic-bundle.etf"),
        ok = file:write_file(SyntheticFile, term_to_binary(Synthetic, [deterministic])),
        Build = #{source => <<"fixture-source">>, rtl => <<"fixture-rtl">>,
            observation => xls_protocol_spacetime:observation_digest(Plan)},
        Identity = #{build => Build, checkpoint => <<"synthetic-checkpoint">>,
            netlist => <<"synthetic-netlist">>, probe => <<"synthetic-probes">>},
        Cell = #{id => <<"ff">>, kind => <<"FDRE">>, site => <<"SLICE_X0Y0">>,
            bel => <<"AFF">>, x => 0, y => 0, properties => #{}},
        Pin = #{cell => <<"ff">>, pin => <<"Q">>, native => <<"ff/Q">>, direction => output},
        Catalogue = #{build => Build, checkpoint => <<"synthetic-checkpoint">>,
            evidence => synthetic_fixture, coordinate_unit => tile_grid,
            cells => [Cell], nets => [#{id => <<"qnet">>, pins => [Pin]}], generated => [], bindings => []},
        Bit = #{bit => 0, cell => <<"ff">>, pin => <<"Q">>, native_pin => <<"ff/Q">>,
            primitive => <<"FDRE">>, parent_net => <<"qnet">>},
        Candidates = #{identity => Identity, probes => [#{id => <<"probe">>, resource => <<"register/q">>,
            generated => <<"fixture.core.q">>, width => 16, bits => [Bit]}]},
        Row = #{id => <<"probe">>, width => 16, mask => 1, mismatch_samples => 0, unknown_samples => 0,
            mismatch_mask => 0, unknown_mask => 0, observed_ones => 1, observed_zeroes => 1,
            expected_ones => 1, expected_zeroes => 1},
        Witness = #{identity => Identity, cases => [#{id => <<"synthetic-case">>, cycles => 2,
            nonreset_cycles => 2, complete => true, public_passed => true, rows => [Row]}]},
        lists:foreach(fun({Name, Term}) ->
            ok = file:write_file(filename:join(Root, Name), term_to_binary(Term, [deterministic]))
        end, [{"catalogue.etf", Catalogue}, {"candidates.etf", Candidates}, {"witness.etf", Witness}]),
        Output = filename:join(Root, "claims"),
        Args = ["+S", "2:2", "-noshell", "-pa"] ++ code:get_path() ++
            ["-s", "xls_protocol_spacetime_cli", "main", "-extra", "qualify",
             filename:join(Root, "catalogue.etf"), SyntheticFile,
             filename:join(Root, "candidates.etf"), filename:join(Root, "witness.etf"), Output],
        Port = open_port({spawn_executable, filename:join([code:root_dir(), "bin", "erl"])},
            [binary, exit_status, stderr_to_stdout, {args, Args}]),
        _ = await(Port, erlang:monotonic_time(millisecond) + 10000, <<>>),
        {ok, ClaimsBytes} = file:read_file(filename:join(Output, "claims.etf")),
        #{bindings := [#{bits := Bits}]} = binary_to_term(ClaimsBytes, [safe]),
        ?assertEqual(1, length([B || B = #{status := supported} <- Bits])),
        ?assertEqual(15, length([B || B = #{status := unknown} <- Bits]))
    end).

%% A stuck CLI or excessive diagnostic output fails this localized process test.
-spec await(port(), integer(), binary()) -> binary().
await(Port, Deadline, Output) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} when byte_size(Output) + byte_size(Bytes) =< 65536 ->
            await(Port, Deadline, <<Output/binary, Bytes/binary>>);
        {Port, {exit_status, 0}} -> Output;
        {Port, {exit_status, Status}} -> error({workflow_child_failed, Status, Output});
        {Port, {data, _}} -> port_close(Port), error(workflow_child_output_limit)
    after Left -> port_close(Port), error(workflow_child_timeout)
    end.

%% The fixture records two enabled writes to one encoded word, including an equal write.
-spec fixture() -> map().
fixture() ->
    Names = [{<<"input_reset">>, 1}, {<<"p0_stage_done">>, 1},
        {<<"q">>, 16}, {<<"d">>, 16}, {<<"enable">>, 1}],
    #{schema => 1, actors => [], unsupported => [],
      signals => [#{id => <<"signal/", N/binary>>, name => N, width => W,
          path => <<"fixture.core.", N/binary>>, actor => null, meaning => <<"fixture">>,
          evidence => <<"Synthetic producer boundary fixture">>} || {N, W} <- Names],
      registers => [#{name => <<"q">>, width => 16, enable => <<"enable">>, data => <<"d">>,
          rule => enabled_same_edge_register_write}],
      state => [#{tuple_path => [0, 0], signal => <<"q">>, source_width => 16, physical_width => 16}],
      inputs => #{rtl => <<"fixture-rtl">>, source_build => <<"fixture-source">>}}.

%% Footer accounting follows the recorder dialect exactly, including declaration bytes.
-spec trace(map()) -> iodata().
trace(Plan) ->
    Header = <<"H\tspacetime_cycle_trace\t1\nP\treset\tinput_valid\tinput_data\tinput_last\toutput_ready\tinput_ready\toutput_valid\toutput_data\toutput_last\tfault\trunning\n">>,
    Taps = [["T\t", maps:get(id, S), "\t", integer_to_binary(maps:get(width, S)),
        "\t", maps:get(path, S), "\n"] || S <- maps:get(signals, Plan)],
    Public = lists:duplicate(11, <<"0">>),
    Rows = [Public ++ [<<"0">>, <<"1">>, <<"0">>, <<"7">>, <<"1">>],
        Public ++ [<<"0">>, <<"1">>, <<"7">>, <<"7">>, <<"1">>]],
    Bound = 4096 + byte_size(Header) + iolist_size(Taps) +
        lists:sum([32 + lists:sum([byte_size(V) + 1 || V <- Row]) || Row <- Rows]),
    [Header, Taps, [["S\t", integer_to_binary(C), "\t1\t", lists:join("\t", Values), "\n"]
        || {C, Values} <- lists:enumerate(0, Rows)],
        "F\t2\tcomplete\t2\t2\t", integer_to_binary(Bound), "\tok\n"].

%% Isolate small temporary inputs without depending on the historical capture archive.
-spec with_directory(fun((file:filename()) -> term())) -> ok.
with_directory(Fun) ->
    Root = filename:absname(filename:join(["_build", "workflow-tests", integer_to_list(erlang:unique_integer([positive]))])),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    try _ = Fun(Root), ok after ok = file:del_dir_r(Root) end.
