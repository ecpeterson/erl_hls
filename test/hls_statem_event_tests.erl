-module(hls_statem_event_tests).
-moduledoc "Checks internal-step priority and private scheduler storage.".
-include_lib("eunit/include/eunit.hrl").

%% A phase change must enter first, run the whole burst, then retry old input.
-spec phase_entry_and_internal_events_precede_postponed_input_test() -> ok.
phase_entry_and_internal_events_precede_postponed_input_test() ->
    {ok, Pid} = hls_statem:start_link(hls_statem_event_fixture, [], [{mailbox_capacity, 4}]),
    try
        hls_statem:cast(Pid, {later, 99}),
        hls_statem:cast(Pid, {start, 3}),
        ok = hls_statem:connect(Pid, #{out => self()}),
        ?assertEqual([1, 2, 3, 99], [receive {'$gen_cast', {value, V}} -> V after 1000 -> timeout end || _ <- lists:seq(1, 4)]),
        #{data := {cell, 0, 99}, postponed := 0} = hls_statem:info(Pid),
        ok
    after hls_statem:stop(Pid) end.

%% The event name occupies private state without altering the record's wire codec.
-spec generated_event_storage_test() -> ok.
generated_event_storage_test() ->
    Interface = hls_actor_interface:from_module(hls_statem_event_fixture),
    ?assertEqual(8, maps:get(continuation_width, Interface)),
    Generated = iolist_to_binary(xls_parse:to_xls("test/hls_statem_event_fixture.erl")),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"next_event: u8">>)),
    ok.

%% Unsupported actions must fail during translation, before any hardware is produced.
-spec invalid_call_directive_test() -> ok.
invalid_call_directive_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_statem_reply_fixture.erl"),
    Changed = [case Form of
        {function, L, waiting, 3, Clauses} ->
            {function, L, waiting, 3, [postpone_call(C) || C <- Clauses]};
        _ -> Form
    end || Form <- Forms],
    ?assertError({unsupported_hls_statem_call_directive, _},
        xls_statem_lower:lower("invalid_call.erl", Changed, [waiting, draining])).

%% Change just one caller conclusion; declarations and other callbacks remain realistic.
-spec postpone_call(erl_parse:abstract_clause()) -> erl_parse:abstract_clause().
postpone_call({clause, L, [{tuple, _, [{atom, _, call}, _]}, {record, _, read, _}, _] = Head, Guards, _}) ->
    {clause, L, Head, Guards, [{tuple, L, [{atom, L, waiting}, {var, L, 'Cell'}, {atom, L, postpone}]}]};
postpone_call(Clause) -> Clause.

%% The shared action vocabulary rejects queues and undeclared names on both adapters.
-spec bounded_action_vocabulary_test() -> ok.
bounded_action_vocabulary_test() ->
    ?assertError({undeclared_hls_continuation, missing},
        hls_callback_actions:split([{next_event, internal, missing}], statem, [drain])),
    ?assertError({invalid_hls_callback_actions, statem, _},
        hls_callback_actions:split([{next_event, internal, drain}, {reply, 1, {result, 0}}], statem, [drain])),
    ?assertError({invalid_hls_callback_actions, statem, _},
        hls_callback_actions:split([{next_event, internal, drain}, {next_event, internal, drain}], statem, [drain])).
