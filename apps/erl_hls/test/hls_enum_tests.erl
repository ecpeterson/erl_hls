-module(hls_enum_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Host values are atoms; only the retained descriptor fixes their wire codes.
-spec codec_test() -> ok.
codec_test() ->
    Type = hls_enum:enum([none, actor, backend]),
    ?assertEqual(2, hls_type:width(Type)),
    ?assertEqual(none, hls_type:zero(Type)),
    [?assertEqual(<<Code:2>>, hls_type:pack_exact(Value, Type))
        || {Value, Code} <- [{none, 0}, {actor, 1}, {backend, 2}]],
    ?assertEqual({actor, <<5:3>>}, hls_type:unpack(<<1:2, 5:3>>, Type)),
    ?assertError({invalid_hls_enum_value, 1, [none, actor, backend]}, hls_type:pack(1, Type)),
    ?assertError({invalid_hls_enum_value, unknown, [none, actor, backend]}, hls_type:pack(unknown, Type)),
    ?assertError({invalid_hls_enum_code, 3, [none, actor, backend]}, hls_type:unpack(<<3:2>>, Type)).

%% Singleton domains retain one physical bit, whose other code is invalid.
-spec singleton_test() -> ok.
singleton_test() ->
    Type = hls_enum:enum([idle]),
    ?assertEqual(1, hls_type:width(Type)),
    ?assertEqual(<<0:1>>, hls_type:pack_exact(idle, Type)),
    ?assertError({invalid_hls_enum_code, 1, [idle]}, hls_type:unpack(<<1:1>>, Type)).

%% Empty, duplicated and nonatom codebooks cannot define an encoding.
-spec malformed_descriptor_test_() -> [term()].
malformed_descriptor_test_() ->
    [?_assertError({invalid_hls_enum, Members}, hls_enum:enum(Members))
        || Members <- [[], [a, a], [a, 1]]].
