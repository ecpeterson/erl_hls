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

%% Compatible provider and helper implementations retain bytes through ordinary reloads.
-spec compatible_reload_test() -> ok.
compatible_reload_test() ->
    Provider = hls_record_codec_provider_fixture,
    Helper = hls_record_codec_helper_fixture,
    with_modules([Provider, Helper], fun(Directory) ->
        load(Directory, Helper, "[mask/1, revision/0]", helper(1)),
        load(Directory, Provider, exports(), provider(8, 1, Helper)),
        Type = {hls_type, Provider, value, [v1]},
        Codec = hls_record_codec:bind(message, [{value, Type}]),
        ?assertEqual(<<37>>, hls_record_codec:pack(Codec, {message, 37})),
        load(Directory, Provider, exports(), provider(8, 2, Helper)),
        load(Directory, Helper, "[mask/1, revision/0]", helper(2)),
        ?assertEqual(ok, hls_record_codec:check(Codec)),
        ?assertEqual(<<37>>, hls_record_codec:pack(Codec, {message, 37})),
        ?assertEqual({pack, 2}, get(codec_callback)),
        ?assertEqual({{message, 37}, <<>>}, hls_record_codec:unpack(Codec, <<37>>)),
        ?assertEqual({unpack, 2}, get(codec_callback)),
        ?assertEqual(Codec, hls_record_codec:bind(message, [{value, Type}])),
        ?assertError(badarg, hls_record_codec:pack(Codec, {message, invalid})),
        ok
    end).

%% Explicit constructor arguments let one current provider serve old and new wire encodings.
-spec versioned_encodings_test() -> ok.
versioned_encodings_test() ->
    Provider = hls_record_codec_provider_fixture,
    with_modules([Provider], fun(Directory) ->
        load(Directory, Provider, exports(), provider(8, 1, 0)),
        Old = hls_record_codec:bind(message, [{value, {hls_type, Provider, value, [v1]}}]),
        load(Directory, Provider, exports(), provider(8, 2, 0)),
        New = hls_record_codec:bind(message, [{value, {hls_type, Provider, value, [v2]}}]),
        ?assertEqual(8, hls_record_codec:width(Old)),
        ?assertEqual(8, hls_record_codec:width(New)),
        ?assertEqual(<<37>>, hls_record_codec:pack(Old, {message, 37})),
        ?assertEqual(<<218>>, hls_record_codec:pack(New, {message, 37})),
        ?assertEqual({{message, 37}, <<>>}, hls_record_codec:unpack(Old, <<37>>)),
        ?assertEqual({{message, 37}, <<>>}, hls_record_codec:unpack(New, <<218>>)),
        ok
    end).

%% Checks catch missing providers and callbacks before invoking a value codec.
-spec unavailable_codec_test() -> ok.
unavailable_codec_test() ->
    Provider = hls_record_codec_provider_fixture,
    with_modules([Provider], fun(Directory) ->
        load(Directory, Provider, exports(), provider(8, 1, 0)),
        Fields = [{value, {hls_type, Provider, value, [v1]}}],
        Codec = hls_record_codec:bind(message, Fields),
        load(Directory, Provider, "[width/2, pack/3]", provider(8, 2, 0)),
        erase(codec_callback),
        Missing = {missing_record_codec_callback, Provider, unpack, 3},
        ?assertError(Missing, hls_record_codec:check(Codec)),
        ?assertError(Missing, hls_record_codec:pack(Codec, {message, 37})),
        ?assertError(Missing, hls_record_codec:unpack(Codec, <<37>>)),
        ?assertError(Missing, hls_record_codec:bind(message, Fields)),
        ?assertEqual(undefined, get(codec_callback)),
        code:purge(Provider), code:delete(Provider),
        Unavailable = {record_codec_provider_unavailable, Provider, nofile},
        ?assertError(Unavailable, hls_record_codec:check(Codec)),
        ?assertError(Unavailable, hls_record_codec:pack(Codec, {message, 37})),
        ?assertError(Unavailable, hls_record_codec:unpack(Codec, <<37>>)),
        ?assertError(Unavailable, hls_record_codec:bind(message, Fields)),
        ?assertEqual(undefined, get(codec_callback)),
        ok
    end).

%% The retained total width catches an incompatible expansion before packing or decoding.
-spec changed_width_test() -> ok.
changed_width_test() ->
    Provider = hls_record_codec_provider_fixture,
    with_modules([Provider], fun(Directory) ->
        load(Directory, Provider, exports(), provider(8, 1, 0)),
        Fields = [{value, {hls_type, Provider, value, [v1]}}],
        Codec = hls_record_codec:bind(message, Fields),
        load(Directory, Provider, exports(), provider(9, 2, 0)),
        erase(codec_callback),
        Changed = {record_codec_width_changed, message, 8, 9},
        ?assertError(Changed, hls_record_codec:check(Codec)),
        ?assertError(Changed, hls_record_codec:pack(Codec, {message, 37})),
        ?assertError(Changed, hls_record_codec:unpack(Codec, <<37>>)),
        ?assertEqual(undefined, get(codec_callback)),
        ?assertEqual(8, hls_record_codec:width(Codec)),
        ?assertEqual(9, hls_record_codec:width(hls_record_codec:bind(message, Fields))),
        ok
    end).

%% A deliberately violated stable-constructor contract demonstrates the check's semantic limit.
-spec same_width_semantics_are_provider_contract_test() -> ok.
same_width_semantics_are_provider_contract_test() ->
    Provider = hls_record_codec_provider_fixture,
    with_modules([Provider], fun(Directory) ->
        load(Directory, Provider, exports(), provider(8, 1, 0)),
        Codec = hls_record_codec:bind(message, [{value, {hls_type, Provider, value, [v1]}}]),
        ?assertEqual(<<37>>, hls_record_codec:pack(Codec, {message, 37})),
        load(Directory, Provider, exports(), provider(8, 2, 255)),
        ?assertEqual(ok, hls_record_codec:check(Codec)),
        ?assertEqual(<<218>>, hls_record_codec:pack(Codec, {message, 37})),
        ?assertEqual({{message, 37}, <<>>}, hls_record_codec:unpack(Codec, <<218>>)),
        ok
    end).

%% The provider's required public codec functions are independent of its helper implementation.
-spec exports() -> string().
exports() -> "[width/2, pack/3, unpack/3]".

%% Test-only callback probes identify the current implementation without changing its encoding.
-spec provider(pos_integer(), pos_integer(), byte() | module()) -> iodata().
provider(Width, Revision, Mask) ->
    W = integer_to_list(Width),
    R = integer_to_list(Revision),
    ["width(value, [_Version]) -> ", W, ".\n",
     "pack(V, value, [Version]) when is_integer(V), V >= 0, V < (1 bsl ", W, ") ->\n",
     "  put(codec_callback, {pack, ", R, "}), <<(V bxor mask(Version)):", W, ">>;\n",
     "pack(_, value, _) -> error(badarg).\n",
     "unpack(<<V:", W, ", Rest/bitstring>>, value, [Version]) ->\n",
     "  put(codec_callback, {unpack, ", R, "}), {V bxor mask(Version), Rest}.\n",
     case Mask of
         M when is_atom(M) -> ["mask(Version) -> ", atom_to_list(M), ":mask(Version).\n"];
         M -> ["mask(v1) -> ", integer_to_list(M), ";\n",
             "mask(v2) -> ", integer_to_list(M bxor 255), ".\n"]
     end].

%% Changing the helper's revision leaves both explicitly versioned encodings unchanged.
-spec helper(pos_integer()) -> iodata().
helper(Revision) ->
    ["revision() -> ", integer_to_list(Revision), ".\n",
     "mask(v1) -> revision() - revision();\nmask(v2) -> 255.\n"].

%% Compile fixtures to memory so deleting a loaded provider cannot silently reload a beam file.
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
