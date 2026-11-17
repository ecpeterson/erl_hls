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

%% A wildcard caller still has a runtime handle for its immediate reply.
-spec wildcard_caller_test() -> ok.
wildcard_caller_test() ->
    [Call] = normalized("handle_call(#request{}, _, Data) -> {reply, #response{}, Data}.", call),
    ?assertMatch({clause, _, [{tuple, _, [_, {match, _, {var, _, Name}, {var, _, '_'}}]}, _, _], _, _}
        when Name =/= '_', Call).

%% Only a qualified literal error at a callback result becomes explicit failure.
-spec terminal_error_test() -> ok.
terminal_error_test() ->
    [Clause] = normalized("handle_cast(#cast_request{}, Data) -> case Data of 0 -> erlang:error(broken); _ -> {noreply, Data} end.", cast),
    Leaves = xls_callback_result:results(Clause),
    ?assert(lists:any(fun({tuple, _, [{atom, _, hls_server}, _, {atom, _, fail}]}) -> true; (_) -> false end, Leaves)),
    %% Do not reorder or suppress an exception occurring inside a reply field.
    [ValueClause] = normalized("handle_call(#request{}, _, Data) -> {reply, erlang:error(in_value), Data}.", call),
    {clause, _, [{tuple, _, [_, {match, _, {var, _, Handle}, _}]}, _,
        {match, _, {var, _, Original}, _}], _, Body} = ValueClause,
    Bindings = lists:foldl(fun(Name, Bs) -> erl_eval:add_binding(Name, 0, Bs) end,
        erl_eval:new_bindings(), ['Data', Handle, Original]),
    ?assertError(in_value, erl_eval:exprs(Body, Bindings)),
    ?assertException(error, {invalid_hls_server_result, _},
        normalized("handle_cast(#cast_request{}, _) -> error(local_helper_argument).", cast)).

%% Normalize a minimal retained server without executing or loading a source module.
-spec normalized(string(), call | cast) -> [erl_parse:abstract_clause()].
normalized(Text, Kind) ->
    Prefix = ["-module(server_normalization).", "-behaviour(hls_gs).", "-hls_data(cell).",
        "-hls_tags([request, response, cast_request]).",
        "-record(request, {}).", "-record(response, {}).", "-record(cast_request, {}).", "-hls_replies([{request, [response]}]).",
        "-hls_pending_calls(1).", "init([]) -> 0."],
    Call = case Kind of call -> []; cast -> ["handle_call(#request{}, _, Data) -> {reply, #response{}, Data}."] end,
    Forms = [begin {ok, Tokens, _} = erl_scan:string(T), {ok, Form} = erl_parse:parse_form(Tokens), Form end
             || T <- Prefix ++ Call ++ [Text]],
    {Normalized, _} = hls_server_source:normalize(Forms),
    {function, _, hls_server, 3, Clauses} = lists:keyfind(hls_server, 3,
        [F || F = {function, _, _, _, _} <- Normalized]),
    case Kind of call -> lists:nthtail(1, Clauses); cast -> lists:nthtail(2, Clauses) end.
