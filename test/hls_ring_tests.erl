-module(hls_ring_tests).
-include_lib("eunit/include/eunit.hrl").

%% Vary capacity, insertion position, and physical wrap; a list is the independent oracle.
-spec ordered_history_test() -> ok.
ordered_history_test() ->
    lists:foreach(fun(N) -> history(N, 90, hls_type:zero(hls_ring:ring(hls_nums:u8(), N)), []) end,
        [1, 2, 3, 4, 7]).

%% Move every suffix one continuation at a time, checking exact step count.
-spec history(pos_integer(), non_neg_integer(), hls_ring:ring(integer(), pos_integer()), [integer()]) -> ok.
history(_, 0, _, _) -> ok;
history(N, K, Q, Model) ->
    {Q0, M0} = case length(Model) =:= N of
        true -> {hls_ring:pop(Q), tl(Model)};
        false -> {Q, Model}
    end,
    P = K rem (length(M0) + 1) + 1,
    At = lists:foldl(fun(_, C) -> hls_ring:next(C) end, hls_ring:rewind(Q0), lists:seq(1, P-1)),
    Started = hls_ring:begin_insert(At),
    ?assertError(badarg, hls_ring:front(Started)),
    ?assertError(badarg, hls_ring:rewind(Started)),
    {Q1, Steps} = install(K, Started, 0),
    ?assertEqual(length(M0) - P + 2, Steps),
    {Before, After} = lists:split(P-1, M0),
    Expected = Before ++ [K] ++ After,
    ?assertEqual(Expected, contents(Q1)),
    ?assertEqual(K, hls_ring:current(Q1)),
    Type = hls_ring:ring(hls_nums:u8(), N),
    Packed = hls_type:pack(Q1, Type),
    ?assertEqual({Q1, <<13:5>>}, hls_type:unpack(<<Packed/bitstring, 13:5>>, Type)),
    history(N, K-1, Q1, Expected).

%% Finish only the already-started insertion, imposing a finite safety bound.
-spec install(integer(), hls_ring:ring(integer(), pos_integer()), non_neg_integer()) ->
    {hls_ring:ring(integer(), pos_integer()), pos_integer()}.
install(V, Q, Steps) when Steps < 8 ->
    case hls_ring:insert_step(V, Q) of
        {true, Done} -> {Done, Steps + 1};
        {false, Next} -> install(V, Next, Steps + 1)
    end.

%% Observe logical order without relying on the private tuple or its physical slots.
-spec contents(hls_ring:ring(integer(), pos_integer())) -> [integer()].
contents(Q) -> collect(hls_ring:rewind(Q)).
%% Consume a copied cursor; the source ring remains unchanged.
-spec collect(hls_ring:ring(integer(), pos_integer())) -> [integer()].
collect(Q) ->
    case hls_ring:at_end(Q) of
        true -> [];
        false -> [hls_ring:current(Q) | collect(hls_ring:next(Q))]
    end.

%% Empty/exhausted/full misuse and invalid metadata must reject, not overwrite values.
-spec rejected_operations_test() -> ok.
rejected_operations_test() ->
    ?assertError(badarg, hls_ring:ring(hls_nums:u8(), 0)),
    ?assertError(badarg, hls_ring:ring(hls_nums:u8(), 1 bsl 31)),
    Q = hls_type:zero(hls_ring:ring(hls_nums:u8(), 1)),
    ?assert(hls_ring:empty(Q)), ?assert(hls_ring:at_end(Q)),
    [?assertError(badarg, F()) || F <- [fun() -> hls_ring:front(Q) end,
        fun() -> hls_ring:current(Q) end, fun() -> hls_ring:next(Q) end,
        fun() -> hls_ring:replace(3, Q) end, fun() -> hls_ring:pop(Q) end,
        fun() -> hls_ring:begin_insert(Q) end, fun() -> hls_ring:insert_step(3, Q) end]],
    {Full, 1} = install(3, hls_ring:begin_insert(hls_ring:rewind(Q)), 0),
    ?assert(hls_ring:full(Full)), ?assertEqual(3, hls_ring:front(Full)),
    ?assertError(badarg, hls_ring:begin_insert(Full)),
    Replaced = hls_ring:replace(4, Full), ?assertEqual([4], contents(Replaced)),
    Empty = hls_ring:pop(Replaced), ?assert(hls_ring:at_end(Empty)),
    ?assertError(badarg, hls_ring:current(Empty)),
    ?assertError(badarg, hls_type:pack({ring, [1], 2, 0, 0, 0}, hls_ring:ring(hls_nums:u8(), 1))).

%% Nested codecs, atom identity and element padding remain owned by hls_type.
-spec compound_codec_test() -> ok.
compound_codec_test() ->
    E = {hls_type, hls_record, sample, [{mode, hls_enum:enum([cold, warm])}, {flag, hls_bool:bool()}]},
    T = hls_ring:ring(E, 2), Q = hls_type:zero(T),
    {true, Q1} = hls_ring:insert_step({sample, warm, true}, hls_ring:begin_insert(hls_ring:rewind(Q))),
    ?assertEqual({Q1, <<>>}, hls_type:unpack(hls_type:pack(Q1, T), T)),
    ?assertEqual({sample, warm, true}, hls_ring:front(Q1)),
    ?assertEqual(128 + 2 * hls_type:value_width(E), hls_type:value_width(T)).
