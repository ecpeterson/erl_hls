-module(xls_ir_arithmetic_tests).
-moduledoc "Admission and unchanged-output boundaries for the opt-in arithmetic passes; separate SAT checks establish finite circuit equivalence.".
-include_lib("eunit/include/eunit.hrl").

%% No rewrite may index nodes from two functions, another entity, or a reserved namespace.
-spec scope_rejected_test() -> ok.
scope_rejected_test() ->
    [begin
        I = addition(16, 1, "zero_ext(y, new_bit_count=16)", "add(x, ext)"),
        ?assertException(error, {badmatch, _}, M:rewrite(<<I/binary, I/binary>>)),
        ?assertException(error, {badmatch, _}, M:rewrite(<<I/binary, "proc other() {\n}\n">>)),
        ?assertException(error, {badmatch, _}, M:rewrite(<<I/binary, "block other() {\n}\n">>)),
        ?assertException(error, {badmatch, _}, M:rewrite(<<"// ", Prefix/binary, "\n", I/binary>>))
    end || {M, Prefix} <- passes()],
    ok.

%% Wide/unknown operands and ordinary arithmetic cannot be guessed to be small increments.
-spec unknown_preserved_test() -> ok.
unknown_preserved_test() ->
    [begin
        I = addition(16, 16, "identity(y)", Op),
        ?assertEqual({I, []}, M:rewrite(I))
    end || {M, _} <- passes(), Op <- ["add(x, ext)", "sub(x, ext)", "xor(x, ext)"]],
    ok.

%% Tiny additions stay unchanged; sign extension and nonzero prefixes do not establish bounds.
-spec bounds_test() -> ok.
bounds_test() ->
    [begin
        I = addition(8, K, "zero_ext(y, new_bit_count=8)", "add(x, ext)"),
        ?assertEqual({I, []}, M:rewrite(I))
    end || {M, _} <- passes(), K <- [1, 2, 4]],
    [begin
        I = addition(16, K, "sign_ext(y, new_bit_count=16)", "add(ext, x)"),
        ?assertEqual({I, []}, M:rewrite(I))
    end || {M, _} <- passes(), K <- [1, 2, 4]],
    I = addition(16, 5, "zero_ext(y, new_bit_count=16)", "add(x, ext)"),
    ?assertEqual({I, []}, xls_ir_small_add:rewrite(I)),
    ok.

%% Chosen additions retain the return identity and location metadata; reapplication fails closed.
-spec metadata_and_reapplication_test() -> ok.
metadata_and_reapplication_test() ->
    [begin
        I = addition(16, K, "zero_ext(y, new_bit_count=16)", "add(x, ext)"),
        {Out, [#{node := <<"result">>, width := 16}]} = M:rewrite(I),
        ?assertNotEqual(nomatch, binary:match(Out, <<"ret result: bits[16] = add(">>)),
        ?assertNotEqual(nomatch, binary:match(Out, <<"id=4, pos=[(0,1,2)]">>)),
        ?assertException(error, {badmatch, _}, M:rewrite(Out))
    end || {M, K} <- [{xls_ir_conditional_increment, 1}, {xls_ir_small_add, 3}]],
    ok.

%% Passes use distinct namespaces but the same admission contract.
-spec passes() -> [{module(), binary()}].
passes() -> [{xls_ir_increment_compare, <<"hls_inc_">>},
    {xls_ir_conditional_increment, <<"hls_wordinc_">>},
    {xls_ir_small_add, <<"hls_smalladd_">>}].

%% Explicit nodes mimic standard XLS formatting without relying on an application frontend.
-spec addition(pos_integer(), pos_integer(), string(), string()) -> binary().
addition(W, K, Extension, Operation) ->
    Ext = lists:droplast(Extension),
    Op = lists:droplast(Operation),
    iolist_to_binary(io_lib:format("package test\nfile_number 0 \"test.x\"\n"
        "top fn test(x: bits[~B] id=1, y: bits[~B] id=2) -> bits[~B] {\n"
        "  ext: bits[~B] = ~s, id=3)\n"
        "  ret result: bits[~B] = ~s, id=4, pos=[(0,1,2)])\n}\n",
        [W, K, W, W, Ext, W, Op])).

%% A nonzero concatenation prefix is data, not an unsigned-small range certificate.
-spec nonzero_prefix_preserved_test() -> ok.
nonzero_prefix_preserved_test() ->
    [begin
        I = iolist_to_binary(io_lib:format("package test\n"
            "top fn test(x: bits[16] id=1, y: bits[~B] id=2) -> bits[16] {\n"
            "  high: bits[~B] = literal(value=1, id=3)\n"
            "  ext: bits[16] = concat(high, y, id=4)\n"
            "  ret result: bits[16] = add(x, ext, id=5)\n}\n", [K, 16-K])),
        ?assertEqual({I, []}, M:rewrite(I))
    end || {M, K} <- [{xls_ir_conditional_increment, 1}, {xls_ir_small_add, 3}]],
    ok.

%% Refuse an occupied audit path before writing IR; successful audit hashes bind exact bytes.
-spec fresh_output_test() -> ok.
fresh_output_test() ->
    Dir = filename:join("_build", "ir-arithmetic-" ++ integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_dir(filename:join(Dir, "input.ir")),
    Input = filename:join(Dir, "input.ir"),
    Output = filename:join(Dir, "candidate.ir"),
    Blocked = filename:join(Dir, "blocked.ir"),
    Source = addition(16, 1, "zero_ext(y, new_bit_count=16)", "add(x, ext)"),
    ok = file:write_file(Input, Source, [exclusive]),
    ok = file:write_file(Blocked ++ ".json", <<"retain">>, [exclusive]),
    ?assertException(error, {badmatch, _}, xls_ir_conditional_increment:write(Input, Blocked)),
    ?assertEqual({error, enoent}, file:read_file(Blocked)),
    ?assertEqual({ok, <<"retain">>}, file:read_file(Blocked ++ ".json")),
    ok = xls_ir_conditional_increment:write(Input, Output),
    {ok, Bytes} = file:read_file(Output),
    {ok, Audit} = file:read_file(Output ++ ".json"),
    Data = json:decode(Audit),
    ?assertEqual(binary:encode_hex(crypto:hash(sha256, Source), lowercase), maps:get(<<"input_sha256">>, Data)),
    ?assertEqual(binary:encode_hex(crypto:hash(sha256, Bytes), lowercase), maps:get(<<"output_sha256">>, Data)),
    ?assertException(error, {badmatch, _}, xls_ir_conditional_increment:write(Input, Output)),
    ok.
