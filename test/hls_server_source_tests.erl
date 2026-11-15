-module(hls_server_source_tests).
-include_lib("eunit/include/eunit.hrl").

%% Source declarations now reach the same checked actor/program interfaces.
-spec server_interfaces_test() -> ok.
server_interfaces_test() ->
    lists:foreach(fun(Module) ->
        Path = "test/" ++ atom_to_list(Module) ++ ".erl",
        Interface = xls_parse:actor_interface(Path),
        ?assertEqual([hls_server], maps:get(phases, Interface)),
        ?assertMatch(#{}, hls_actor_interface:from_module(Module)),
        ?assertMatch(#{source_kind := server}, xls_parse:actor_artifact(Path, []))
    end, [hls_reply_fixture, hls_deferred_fixture]).

%% Immediate calls carry no persistent transaction slot or allocation sequence.
-spec no_immediate_table_test() -> ok.
no_immediate_table_test() ->
    Spec = xls_parse:actor_artifact("test/hls_reply_fixture.erl", []),
    ?assertEqual(32, xls_statem_reply_codegen:width(Spec)),
    ?assertEqual(32, maps:get(reply_storage_width, xls_parse:actor_interface("test/hls_reply_fixture.erl"))),
    ?assertEqual(96 + 72 * 2, xls_statem_reply_codegen:width(
        xls_parse:actor_artifact("test/hls_deferred_fixture.erl", []))).

%% Capturing before tuple normalization preserves the first observable exception.
-spec result_evaluation_order_test() -> ok.
result_evaluation_order_test() ->
    {ok, Tokens, _} = erl_scan:string("f() -> {reply, 1 div 0, begin false = true, 9 end}."),
    {ok, {function, _, f, 0, [Clause]}} = erl_parse:parse_form(Tokens),
    {clause, _, _, _, Body} = xls_callback_result:map_evaluated_actions(Clause,
        fun({tuple, L, [_Reply, A, B]}) -> {tuple, L, [B, A]} end),
    ?assertError(badarith, erl_eval:exprs(Body, erl_eval:new_bindings())).

%% Native-only helpers retain atom requests and ignore unsupported info without invoking source.
-spec native_facade_test() -> ok.
native_facade_test() ->
    {ok, Pid} = hls_gs:start_link(hls_server_native_fixture, []),
    try
        gen_server:cast(Pid, add),
        Pid ! ignored,
        Pid ! {'DOWN', make_ref(), process, self(), normal},
        ?assertEqual(1, gen_server:call(Pid, read))
    after hls_gs:stop(Pid) end.
