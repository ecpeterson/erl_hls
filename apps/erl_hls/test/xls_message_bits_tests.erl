-module(xls_message_bits_tests).
-moduledoc "Checks known-bit joins and emitted-frame identity against the independent generated BEAM record packer.".
-include_lib("eunit/include/eunit.hrl").

%% All 256 idle cells and eight representable dynamic directions; invalid host values are rejected by the ordinary packer.
-spec emitted_frame_identity_test() -> ok.
emitted_frame_identity_test() ->
    File = "test_data/xls_message_facts_fixture.erl",
    {ok, M, Beam} = compile:file(File, [binary]),
    {module, M} = code:load_binary(M, File, Beam),
    try
        {_, Facts} = xls_message_facts:from_file(File, []),
        lists:foreach(fun(Ports) ->
            Bound = xls_message_facts:frame_bits(Facts, Ports),
            lists:foreach(fun({Phase, V}) ->
                {_, Effects} = M:Phase(enter, idle, {cell, V}),
                lists:foreach(fun({cast, Port, Message}) ->
                    case lists:member(Port, Ports) of
                        true -> assert_identity(M, Message, Bound);
                        false -> ok
                    end
                end, Effects)
            end, [{idle, V} || V <- lists:seq(0, 255)] ++ [{dynamic, V} || V <- lists:seq(0, 7)])
        end, [[west], [east], [relation], [mixed], [west, east], [west, mixed]]),
        lists:foreach(fun(V) -> ?assertError(badarg, M:pack({piece, V, 9})) end, lists:seq(8,255))
    after code:delete(M), code:purge(M) end.

%% Independent ordinary generated packer establishes the full physical stream.
-spec assert_identity(module(), tuple(), map()) -> ok.
assert_identity(M, Message, #{mask := Mask, value := Known}) ->
    Stream = M:pack(Message), N = bit_size(Stream),
    <<Payload:96/little>> = <<Stream/bitstring, 0:(96-N)>>,
    Frame = (Payload bsl 32) bor (M:pack_tag(element(1, Message)) bsl 24) bor ((N+31) div 32),
    ?assertEqual(Known, Frame band Mask),
    ?assertEqual(Frame, (Frame band bnot(Mask)) bor Known).

%% Dynamic inputs and generated reply alternatives never create assumptions.
-spec unknown_and_silent_test() -> ok.
unknown_and_silent_test() ->
    {_, F} = xls_message_facts:from_file("test_data/xls_message_facts_fixture.erl", []),
    ?assertEqual(#{mask => 0, value => 0}, xls_message_facts:frame_bits(F, [silent])),
    {_, R} = xls_message_facts:from_file("test/hls_statem_reply_fixture.erl", []),
    ?assertEqual(#{mask => 0, value => 0}, xls_message_facts:frame_bits(R, [reply])).

%% Finite joins keep precisely the common known bits, including disagreement.
-spec joins_test() -> ok.
joins_test() ->
    ?assertEqual(#{mask => 2#1100, value => 2#1000},
        xls_message_bits:join([#{mask => 15, value => 8}, #{mask => 15, value => 11}])),
    ?assertEqual(#{mask => 0, value => 0},
        xls_message_bits:join([#{mask => 15, value => 8}, #{mask => 0, value => 0}])).

%% Schema-conditioned bounds preserve ABI bits that a cross-schema join loses.
-spec schema_cases_identity_test() -> ok.
schema_cases_identity_test() ->
    File = "test_data/xls_message_facts_fixture.erl",
    {ok, M, Beam} = compile:file(File, [binary]),
    {module, M} = code:load_binary(M, File, Beam),
    try
        {_, F} = xls_message_facts:from_file(File, []),
        Cases = xls_message_facts:frame_cases(F, [mixed]),
        #{mask := Common} = xls_message_facts:frame_bits(F, [mixed]),
        ?assert(lists:any(fun(#{mask := Mask}) -> Mask =/= Common end, Cases)),
        lists:foreach(fun(Message) ->
            Op = M:pack_tag(element(1, Message)),
            [Bound] = [C || C = #{op := O} <- Cases, O =:= Op],
            assert_identity(M, Message, Bound)
        end, [{piece, V, 9} || V <- lists:seq(0, 7)] ++ [{alternate, -3, 0}]),
        ?assertEqual([], xls_message_facts:frame_cases(F, [silent])),
        {_, R} = xls_message_facts:from_file("test/hls_statem_reply_fixture.erl", []),
        ?assertEqual(unknown, xls_message_facts:frame_cases(R, [reply]))
    after code:delete(M), code:purge(M) end.

%% Aliased producers cannot retain a fact present in only one source alternative.
-spec join_schema_cases_test() -> ok.
join_schema_cases_test() ->
    A = [#{op => 3, mask => 15, value => 8}, #{op => 4, mask => 15, value => 2}],
    B = [#{op => 3, mask => 15, value => 11}],
    Expected = [#{op => 3, mask => 12, value => 8}, #{op => 4, mask => 15, value => 2}],
    ?assertEqual(Expected, xls_message_bits:join_cases([A, B, []])),
    ?assertEqual(Expected, xls_message_bits:join_cases([B, A])),
    ?assertEqual(unknown, xls_message_bits:join_cases([A, unknown])),
    ?assertEqual([], xls_message_bits:join_cases([[], []])).
