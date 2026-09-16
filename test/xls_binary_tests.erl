-module(xls_binary_tests).
-include_lib("eunit/include/eunit.hrl").

bitstring_codec_test() ->
    lists:foreach(fun(Width) ->
        Type = hls_bits:bits(Width),
        ?assertEqual(Width, hls_type:width(Type)),
        ?assertEqual(Width, hls_type:value_width(Type)),
        ?assertEqual(<<0:Width>>, hls_type:zero(Type)),
        lists:foreach(fun(N) ->
            Value = <<N:Width>>,
            ?assertEqual(Value, hls_type:pack_exact(Value, Type)),
            ?assertEqual({Value, <<5:3>>}, hls_type:unpack(<<Value/bits, 5:3>>, Type))
        end, [0, 1, -1, 16#123456789abcdef]),
        [?assertError(badarg, hls_type:pack(V, Type))
            || V <- [0, false, <<0:(Width + 1)>>, <<0:(max(0, Width - 1))>>], bit_size_safe(V) =/= Width]
    end, [0, 1, 3, 7, 8, 9, 16, 17, 23, 24, 65, 127]).

bit_size_safe(V) when is_bitstring(V) -> bit_size(V);
bit_size_safe(_) -> -1.

collections_and_padding_test() ->
    Type = hls_vec:vector(hls_bits:padded(hls_bits:bits(3), 5), 2),
    Value = [<<5:3>>, <<3:3>>],
    ?assertEqual(<<3:3, 0:2, 5:3, 0:2>>, hls_type:pack(Value, Type)),
    ?assertEqual(Value, hls_type:normalize(Type, Value)).

source_rejections_test_() ->
    [?_assertException(error, {unsupported_xls_bit_syntax, _, _}, lower(Source)) || Source <- [
        "<<X:Size>>.", "<<1:(-1)>>.", "<<1:(1 div 0)>>.",
        "<<X:32/float>>.", "<<X/utf8>>.", "<<X:16/native>>.",
        "case B of <<A/binary, _:8>> -> A end."]].

lower(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Body} = erl_parse:parse_exprs(Tokens),
    xls_parse:clause_outcome({clause, 1, [{var, 1, 'X'}, {var, 1, 'B'}], [], Body},
        ["x", "b"], unused, #{}).

size_bif_resolution_test() ->
    {ok, Forms} = epp:parse_file("test/xls_binary_fixture.erl", [], []),
    Prepared = xls_binary_lower:prepare(Forms),
    ?assertNotEqual(Forms, Prepared),
    Bif = {call, 1, {atom, 1, bit_size}, [{var, 1, 'X'}]},
    Definition = {function, 1, bit_size, 1, []},
    ?assertEqual([Definition, Bif], xls_binary_lower:prepare([Definition, Bif])),
    Disabled = {attribute, 1, compile, {no_auto_import, [{bit_size, 1}]}},
    ?assertEqual([Disabled, Bif], xls_binary_lower:prepare([Disabled, Bif])),
    Qualified = {call, 1, {remote, 1, {atom, 1, local_module}, {atom, 1, bit_size}}, [{var, 1, 'X'}]},
    LocalForms = [{attribute, 1, module, local_module}, {attribute, 1, hls_data, unused},
        {attribute, 1, hls_tags, []},
        {function, 1, probe, 1, [{clause, 1, [{var, 1, 'X'}], [], [Qualified]}]}],
    %% Localizing a qualified call must not make it look auto-imported.
    ?assertError({undefined_xls_helper, 1, {bit_size, 1}},
        xls_helpers:prepare(LocalForms, [{probe, 1}])).

source_failure_sites_test() ->
    {ok, Forms0} = epp:parse_file("test/xls_binary_fixture.erl", [], []),
    {Forms, Origins} = xls_failure_sites:prepare(Forms0),
    Bodies = [begin
        [Clause] = xls_parse:find_function(Forms, Name, 2),
        #{body := Body, failure := Failure} =
            xls_parse:clause_outcome(Clause, ["x", "b"], unused, #{}),
        xls_parse:print([Body, Failure])
    end || Name <- [bad_prefix, assignment, same_bits]],
    Sites = xls_failure_sites:allocate(Origins, Bodies),
    ?assert(lists:any(fun(#{kind := K}) -> K =:= badarg end, Sites)),
    ?assert(lists:any(fun(#{kind := K}) -> K =:= match_failure end, Sites)),
    ?assert(lists:all(fun(#{line := L, file := F}) ->
        L > 0 andalso F =:= <<"xls_binary_fixture.erl">>
    end, Sites)),
    ?assertEqual(Sites, xls_failure_sites:from_artifact(Origins,
        xls_failure_sites:emit(Origins, Bodies))).

cpu_service_test() ->
    {ok, PID} = hls_gs:start_link(packed_samples, [], []),
    try
        ?assertEqual({receipt, <<5:3, 0:5, 0:16/little>>, 0, 0}, gen_server:call(PID, {read, 0})),
        ?assertEqual({receipt, <<5:3, 7:5, -129:16/little>>, 1, -129},
            gen_server:call(PID, {sample, <<5:3, 7:5, -129:16/little>>})),
        ?assertEqual({receipt, <<5:3, 3:5, 871:16/little>>, 2, 871},
            gen_server:call(PID, {sample, <<5:3, 3:5, 1000:16/little>>}))
    after gen_server:stop(PID) end.
