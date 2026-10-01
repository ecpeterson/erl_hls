-module(hls_serial_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Codec normalization is idempotent, including bignums and non-byte widths.
-spec codecs_test() -> ok.
codecs_test() ->
    lists:foreach(fun(W) ->
        Type = hls_serial:counter(W),
        ?assertEqual(W, hls_type:width(Type)),
        ?assertEqual(W, hls_type:value_width(Type)),
        ?assertEqual(0, hls_type:zero(Type)),
        lists:foreach(fun(Value) ->
            Expected = Value band ((1 bsl W) - 1),
            Packed = hls_type:pack(Value, Type),
            ?assertEqual(<<Expected:W/little>>, Packed),
            ?assertEqual({Expected, <<5:3>>},
                hls_type:unpack(<<Packed/bitstring, 5:3>>, Type)),
            ?assertEqual(Expected, hls_type:normalize(Type, Value)),
            ?assertEqual(Expected, hls_type:normalize(Type, Expected)),
            ?assertEqual(Packed, hls_type:pack(Expected, Type)),
            ?assertEqual(Packed, hls_type:pack_exact(Expected, Type))
        end, [-1, 0, 1, (1 bsl W) - 1, 1 bsl W, -(1 bsl 1000) + 3,
            (1 bsl 1000) + 7])
    end, [1, 3, 8, 9, 32, 64, 65]),
    Type = hls_serial:counter(8),
    ?assertError({inexact_packing, Type}, hls_type:pack_exact(256, Type)),
    lists:foreach(fun(Value) ->
        ?assertError(badarg, hls_type:pack(Value, Type))
    end, [1.0, wrong, <<1>>]),
    Vector = hls_vec:vector(hls_serial:counter(3), 3),
    ?assertEqual([7, 0, 1], hls_type:normalize(Vector, [-1, 8, 9])).

%% Width validation also covers descriptors produced directly from annotations.
-spec invalid_widths_test() -> ok.
invalid_widths_test() ->
    lists:foreach(fun(W) ->
        ?assertError(badarg, hls_serial:counter(W)),
        ?assertError(badarg, hls_type:width({hls_type, hls_serial, counter, [W]}))
    end, [0, -1, 1.5, wrong]).

%% This is the unwrapped-time oracle: every nearby signed offset must be
%% recovered regardless of where the initial counter lies in its byte range.
-spec exhaustive_nearby_steps_test() -> ok.
exhaustive_nearby_steps_test() ->
    Type = hls_serial:counter(8),
    lists:foreach(fun(N) ->
        lists:foreach(fun(K) ->
            Next = hls_serial:add(Type, N, K),
            ?assertEqual((N + K + 256) rem 256, Next),
            ?assertEqual(K, hls_serial:difference(Type, Next, N)),
            ?assertEqual(-K, hls_serial:difference(Type, N, Next)),
            ?assertEqual(K > 0, hls_serial:before(Type, N, Next)),
            ?assertEqual(K < 0, hls_serial:before(Type, Next, N))
        end, lists:seq(-127, 127))
    end, lists:seq(0, 255)).

%% Opposite residues fail in either direction; no arbitrary order is invented.
-spec half_range_ambiguity_test() -> ok.
half_range_ambiguity_test() ->
    lists:foreach(fun(W) ->
        Type = hls_serial:counter(W),
        Half = 1 bsl (W - 1),
        lists:foreach(fun(N) ->
            Other = hls_serial:add(Type, N, Half),
            ?assertError(badarg, hls_serial:difference(Type, N, Other)),
            ?assertError(badarg, hls_serial:difference(Type, Other, N)),
            ?assertError(badarg, hls_serial:before(Type, N, Other)),
            ?assertError(badarg, hls_serial:before(Type, Other, N))
        end, [0, 1, Half - 1, Half, 2 * Half - 1])
    end, [1, 3, 8, 32, 65]).

%% Check wide boundaries and repeated revolutions against true nearby times.
-spec wide_steps_test() -> ok.
wide_steps_test() ->
    lists:foreach(fun(W) ->
        Type = hls_serial:counter(W),
        Half = 1 bsl (W - 1),
        lists:foreach(fun(N) ->
            lists:foreach(fun(K) ->
                A = hls_serial:wrap(Type, N),
                B = hls_serial:wrap(Type, N + K),
                ?assertEqual(K, hls_serial:difference(Type, B, A)),
                ?assertEqual(K, hls_serial:difference(Type, N + K, N)),
                ?assertEqual(B, hls_serial:add(Type, A, K))
            end, [-Half + 1, -1, 0, 1, Half - 1])
        end, [Half - 1, 2 * Half - 2, 2 * Half - 1, 2 * Half,
            (1 bsl 200) + 17, -(1 bsl 200) - 17])
    end, [3, 32, 64, 65]).

%% Values spanning more than one half-range cannot form a global total order.
-spec ordering_is_local_test() -> ok.
ordering_is_local_test() ->
    Type = hls_serial:counter(8),
    ?assert(hls_serial:before(Type, 0, 100)),
    ?assert(hls_serial:before(Type, 100, 200)),
    ?assert(hls_serial:before(Type, 200, 0)),
    ?assertNot(hls_serial:before(Type, 0, 256)).
