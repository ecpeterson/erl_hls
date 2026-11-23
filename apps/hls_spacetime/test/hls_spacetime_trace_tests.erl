-module(hls_spacetime_trace_tests).
-include_lib("eunit/include/eunit.hrl").

%% Repeated equal controls still represent three sampled edges, not one event.
-spec equal_samples_test() -> ok.
equal_samples_test() ->
    with_trace([header(), "S\t0\t3\t", values(), "\nF\t3\tcomplete\t3\t1\t4402\tok\n"],
        fun(P) -> T = hls_spacetime_trace:read(P),
            ?assertEqual([2,1,0], hls_spacetime_trace:fold(fun(C,_,A)->[C|A] end, [], T)) end).

%% Missing endings, invented coverage and unsafe numbers cannot pass the reader.
-spec corruptions_test_() -> [term()].
corruptions_test_() ->
    [?_test(with_trace([header(), Body], fun(P) ->
        ?assertException(error, {spacetime_trace, _}, hls_spacetime_trace:read(P)) end)) || Body <-
        [ ["S\t0\t1\t", values(), "\n"],
          ["S\t1\t1\t", values(), "\nF\t2\tcomplete\t2\t1\t4294\tok\n"],
          ["S\t0\t1\t", values(), "\nF\t2\tcomplete\t2\t1\t4294\tok\n"],
          ["S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t4294\toverflow\n"],
          ["S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t4294\tok"],
          ["S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t1\tok\n"],
          ["S\t0\t4000001\t", values(), "\n"],
          ["S\t0\t1\t2\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n"],
          ["S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t4294\tok\ntrailing\n"] ]].

%% Explicit truncation survives for diagnosis without becoming complete evidence.
-spec incomplete_test() -> ok.
incomplete_test() ->
    with_trace([header(), "S\t0\t1\t", values(), "\nF\t1\tincomplete\t1\t1\t4294\tcycle_limit\n"],
        fun(P) -> ?assertMatch(#{complete := false, cause := <<"cycle_limit">>}, hls_spacetime_trace:read(P)) end).

%% Wide hardware values retain all bits across the simulator-file boundary.
-spec wide_tap_test() -> ok.
wide_tap_test() ->
    with_trace([header(), "T\tword\t80\tTOP.dut.word\nS\t0\t1\t", values(),
                "\tffffffffffffffffffff\nF\t1\tcomplete\t1\t1\t4338\tok\n"],
        fun(P) -> T = hls_spacetime_trace:read(P),
            ?assertEqual((1 bsl 80)-1, hls_spacetime_trace:fold(fun(_,S,_)->maps:get(<<"word">>,S) end, 0, T)) end).

%% Metadata bytes and per-expanded-row overhead have one exact cross-language accounting rule.
-spec decoded_bound_test_() -> [term()].
decoded_bound_test_() ->
    [?_test(with_trace([header(), "S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t", Bound, "\tok\n"],
        fun(P) -> ?assertException(error, {spacetime_trace, decoded_limit}, hls_spacetime_trace:read(P)) end))
     || Bound <- ["4293", "4295"]].

%% Leading zeroes and case variations are rejected before numerical equivalence can hide them.
-spec canonical_numerals_test_() -> [term()].
canonical_numerals_test_() ->
    Good = iolist_to_binary([header(), "S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t4294\tok\n"]),
    [?_test(with_trace(binary:replace(Good, From, To), fun(P) ->
        ?assertException(error, {spacetime_trace, Reason}, hls_spacetime_trace:read(P)) end))
     || {From, To, Reason} <-
        [{<<"S\t0\t">>, <<"S\t00\t">>, decimal},
         {<<"S\t0\t1\t">>, <<"S\t0\t01\t">>, decimal},
         {<<"F\t1\t">>, <<"F\t01\t">>, decimal},
         {<<"\t4294\t">>, <<"\t04294\t">>, decimal},
         {<<"S\t0\t1\t0\t0\t0\t">>, <<"S\t0\t1\t0\t0\t00\t">>, hex},
         {<<"S\t0\t1\t0\t0\t0\t">>, <<"S\t0\t1\t0\t0\tA\t">>, hex}]].

%% A resource alias may name the same sampled wire while retaining its own signal identity.
-spec shared_path_test() -> ok.
shared_path_test() ->
    Taps = ["T\tone\t8\tTOP.dut.word\n", "T\ttwo\t8\tTOP.dut.word\n"],
    with_trace([header(), Taps, "S\t0\t1\t", values(), "\tab\tab\nF\t1\tcomplete\t1\t1\t4342\tok\n"],
        fun(P) ->
            T = hls_spacetime_trace:read(P),
            ?assertEqual({171,171}, hls_spacetime_trace:fold(fun(_,S,_)->
                {maps:get(<<"one">>,S), maps:get(<<"two">>,S)} end, none, T))
        end).

%% Signal namespaces, widths and ASCII fields must agree before data interpretation.
-spec tap_metadata_test_() -> [term()].
tap_metadata_test_() ->
    [?_test(with_trace([header(), Tap], fun(P) ->
        ?assertException(error, {spacetime_trace, Reason}, hls_spacetime_trace:read(P)) end))
     || {Tap,Reason} <-
        [{"T\tword\t080\tTOP.word\n", decimal},
         {"T\treset\t1\tTOP.reset\n", duplicate_signal},
         {"T\ta\t8\tTOP.word\nT\tb\t16\tTOP.word\n", shared_tap_width},
         {<<"T\tword\t8\tTOP.",255,"\n">>, tap_identity},
         {"T\tword\t8\tTOP.\rword\n", tap_identity}]].

%% File-line normalization changes neither logical row accounting nor sampled values.
-spec crlf_normalization_test() -> ok.
crlf_normalization_test() ->
    LF = iolist_to_binary([header(), "S\t0\t1\t", values(), "\nF\t1\tcomplete\t1\t1\t4294\tok\n"]),
    CRLF = binary:replace(LF, <<"\n">>, <<"\r\n">>, [global]),
    with_trace(CRLF, fun(P) ->
        ?assertMatch(#{complete := true, end_cycle := 1, records := 1}, hls_spacetime_trace:read(P))
    end).

%% Cause tokens must match recorder spelling; a complete marker cannot hide free-form loss prose.
-spec cause_token_test_() -> [term()].
cause_token_test_() ->
    [?_test(with_trace([header(), "S\t0\t1\t", values(), "\nF\t1\tincomplete\t1\t1\t4294\t", Cause, "\n"],
        fun(P) -> ?assertException(error, {spacetime_trace, footer_cause}, hls_spacetime_trace:read(P)) end))
     || Cause <- ["wall deadline", lists:duplicate(201, $x), <<255>>]].

%% Public field order is part of the recorder protocol, independent of backend taps.
-spec header() -> iodata().
header() -> "H\tspacetime_cycle_trace\t1\nP\treset\tinput_valid\tinput_data\tinput_last\toutput_ready\tinput_ready\toutput_valid\toutput_data\toutput_last\tfault\trunning\n".

%% A valid all-zero public pre-edge sample.
-spec values() -> iodata().
values() -> "0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0".

%% Test-owned temporary input is always removed, including deliberate rejects.
-spec with_trace(iodata(), fun((file:filename()) -> term())) -> ok.
with_trace(Bytes, Fun) ->
    Name = filename:join("/tmp", "spacetime-trace-" ++ integer_to_list(erlang:unique_integer([positive,monotonic]))),
    ok = file:write_file(Name, Bytes, [exclusive]),
    try Fun(Name), ok after ok = file:delete(Name) end.
