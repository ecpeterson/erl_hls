-module(hls_record_codec_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% A retained codec preserves nested provider order, padding and ordinary normalization.
-spec nested_record_test() -> ok.
nested_record_test() ->
    Nested = {hls_type, hls_record, inner,
        [{flag, hls_bool:bool()}, {value, hls_nums:uN(9)}]},
    Fields = [{signed, hls_nums:sN(3)}, {padded, hls_bits:padded(hls_nums:uN(5), 9)},
        {values, hls_vec:vector(hls_serial:counter(3), 2)}, {empty, hls_bits:bits(0)},
        {nested, Nested}],
    Codec = hls_record_codec:bind(message, Fields),
    Copy = binary_to_term(term_to_binary(Codec)),
    Value = {message, -3, 17, [9, -1], <<>>, {inner, true, 257}},
    Normalized = {message, -3, 17, [1, 7], <<>>, {inner, true, 257}},
    Expected = <<-3:3/signed-little, 17:5/little, 0:4, 7:3/little, 1:3/little,
        1:1, 257:9/little>>,
    ?assertEqual(28, hls_record_codec:width(Copy)),
    ?assertEqual(Expected, hls_record_codec:pack(Copy, Value)),
    ?assertEqual({Normalized, <<5:3>>}, hls_record_codec:unpack(Copy, <<Expected/bitstring, 5:3>>)),
    ?assertEqual(Expected, hls_record_codec:pack(Copy, Normalized)),
    ?assertEqual(lists:sort([hls_record, hls_nums, hls_bits, hls_vec, hls_serial, hls_bool]),
        hls_type:providers({hls_type, hls_record, message, Fields})),
    Empty = hls_record_codec:bind(empty, []),
    ?assertEqual(0, hls_record_codec:width(Empty)),
    ?assertEqual(<<>>, hls_record_codec:pack(Empty, {empty})),
    ?assertEqual({{empty}, <<3:2>>}, hls_record_codec:unpack(Empty, <<3:2>>)),
    ok.

%% Same-width provider replacement must fail before either value callback runs.
-spec provider_replacement_test() -> ok.
provider_replacement_test() ->
    Provider = hls_record_codec_provider_fixture,
    with_modules([Provider], fun(Directory) ->
        load(Directory, Provider, provider_exports(false), provider(0, none)),
        Type = {hls_type, Provider, value, []},
        Codec = hls_record_codec:bind(message, [{value, Type}]),
        ?assertEqual(<<37>>, hls_record_codec:pack(Codec, {message, 37})),
        ?assertEqual({{message, 37}, <<>>}, hls_record_codec:unpack(Codec, <<37>>)),
        load(Directory, Provider, provider_exports(false), provider(255, none)),
        erase(codec_callback),
        ?assertError({stale_record_codec_provider, Provider}, hls_record_codec:check(Codec)),
        ?assertError({stale_record_codec_provider, Provider}, hls_record_codec:pack(Codec, {message, 37})),
        ?assertError({stale_record_codec_provider, Provider}, hls_record_codec:unpack(Codec, <<37>>)),
        ?assertEqual(undefined, get(codec_callback)),
        ?assertEqual(8, hls_record_codec:width(Codec)),
        Current = hls_record_codec:bind(message, [{value, Type}]),
        ?assertEqual(<<218>>, hls_record_codec:pack(Current, {message, 37})),
        ?assertError(badarg, hls_record_codec:pack(Current, {message, invalid})),
        ok
    end).

%% Nested descriptors and declared helper cycles form one finite checked dependency set.
-spec hidden_helper_replacement_test() -> ok.
hidden_helper_replacement_test() ->
    Provider = hls_record_codec_provider_fixture,
    First = hls_record_codec_helper_fixture,
    Leaf = hls_record_codec_leaf_fixture,
    with_modules([Provider, First, Leaf], fun(Directory) ->
        load(Directory, Leaf, "[mask/0, codec_dependencies/0]",
            "mask() -> 0.\ncodec_dependencies() -> [hls_record_codec_helper_fixture].\n"),
        load(Directory, First, "[mask/0, codec_dependencies/0]",
            "mask() -> hls_record_codec_leaf_fixture:mask().\n"
            "codec_dependencies() -> [hls_record_codec_leaf_fixture].\n"),
        load(Directory, Provider, provider_exports(true), provider(0, First)),
        Type = {hls_type, Provider, value, []},
        Fields = [{nested, {hls_type, hls_record, inner,
            [{values, hls_vec:vector(hls_bits:padded(Type, 9), 2)}]}}],
        Codec = hls_record_codec:bind(message, Fields),
        Value = {message, {inner, [5, 17]}},
        ?assertEqual(<<17, 0:1, 5, 0:1>>, hls_record_codec:pack(Codec, Value)),
        load(Directory, Leaf, "[mask/0, codec_dependencies/0]",
            "mask() -> 255.\ncodec_dependencies() -> [hls_record_codec_helper_fixture].\n"),
        erase(codec_callback),
        ?assertError({stale_record_codec_provider, Leaf}, hls_record_codec:pack(Codec, Value)),
        ?assertEqual(undefined, get(codec_callback)),
        code:purge(Leaf), code:delete(Leaf),
        ?assertError({record_codec_provider_unavailable, Leaf, nofile}, hls_record_codec:check(Codec)),
        ?assertError({record_codec_provider_unavailable, Leaf, nofile}, hls_record_codec:bind(message, Fields)),
        ok
    end).

%% These generated fixtures deliberately alter only code, keeping the declared width fixed.
-spec provider_exports(boolean()) -> string().
provider_exports(false) -> "[width/2, pack/3, unpack/3]";
provider_exports(true) -> "[width/2, pack/3, unpack/3, codec_dependencies/0]".

%% Side effects are test-only probes proving stale identities reject before callbacks.
-spec provider(byte(), none | module()) -> iodata().
provider(Mask, Helper) ->
    Expression = case Helper of
        none -> integer_to_list(Mask);
        _ -> atom_to_list(Helper) ++ ":mask()"
    end,
    ["width(value, []) -> 8.\n",
     "pack(V, value, []) when is_integer(V), V >= 0, V < 256 ->\n",
     "  put(codec_callback, pack), <<(V bxor ", Expression, "):8>>;\n",
     "pack(_, value, []) -> error(badarg).\n",
     "unpack(<<V:8, Rest/bitstring>>, value, []) ->\n",
     "  put(codec_callback, unpack), {V bxor ", Expression, ", Rest}.\n",
     case Helper of none -> []; _ ->
         ["codec_dependencies() -> [", atom_to_list(Helper), "].\n"] end].

%% Compile fixtures to memory so deleting a loaded helper cannot silently reload a beam file.
-spec load(file:filename(), module(), string(), iodata()) -> ok.
load(Directory, Module, Exports, Functions) ->
    Path = filename:join(Directory, atom_to_list(Module) ++ ".erl"),
    ok = file:write_file(Path, ["-module(", atom_to_list(Module), ").\n-export(", Exports,
        ").\n", Functions]),
    {ok, Module, Beam} = compile:file(Path, [binary, debug_info, report_errors]),
    code:purge(Module), code:delete(Module),
    {module, Module} = code:load_binary(Module, Path, Beam),
    ok.

%% Fixed fixture names are local to this serial test module and removed after each witness.
-spec with_modules([module()], fun((file:filename()) -> ok)) -> ok.
with_modules(Modules, Test) ->
    Directory = filename:join("_build", "record-codecs-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_dir(filename:join(Directory, "fixture.erl")),
    try Test(Directory)
    after
        lists:foreach(fun(Module) -> code:purge(Module), code:delete(Module) end, Modules),
        erase(codec_callback),
        ok = file:del_dir_r(Directory)
    end.
