-module(hls_statem_reduction_tests).

-include_lib("eunit/include/eunit.hrl").

count_reduction_completes_through_internal_event_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    try
        ok = hls_statem_reduction_fixture:begin_count(PID, 17),
        ok = hls_statem_reduction_fixture:count_value(PID, 17, 11),
        Partial = hls_statem:info(PID),
        ?assertMatch(
            #{
                name := sum,
                key := 17,
                population := {count, 2},
                received := 1,
                remaining := 1
            },
            maps:get(reduction, Partial)
        ),
        ?assertEqual(0,
            maps:get(committed, maps:get(mailbox, Partial))),
        ok = hls_statem_reduction_fixture:count_value(PID, 17, 5),
        ?assertEqual({observation, 1, 16, 0, 1}, observation()),
        Info = hls_statem:info(PID),
        ?assertEqual(complete, maps:get(phase, Info)),
        ?assertEqual(idle, maps:get(reduction, Info))
    after
        stop_if_alive(PID)
    end.

fixed_member_reduction_accepts_arbitrary_order_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    try
        ok = hls_statem_reduction_fixture:begin_members(PID, 23),
        ok = hls_statem_reduction_fixture:member_value(PID, 23, 3, 8),
        ok = hls_statem_reduction_fixture:member_value(PID, 23, 0, 1),
        ok = hls_statem_reduction_fixture:member_value(PID, 23, 2, 4),
        ok = hls_statem_reduction_fixture:member_value(PID, 23, 1, 2),
        ?assertEqual({observation, 1, 15, 0, 1}, observation()),
        ?assertEqual(idle,
            maps:get(reduction, hls_statem:info(PID)))
    after
        stop_if_alive(PID)
    end.

completion_precedes_already_queued_application_input_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link_disconnected(8),
    try
        ok = hls_statem_reduction_fixture:begin_count(PID, 31),
        ok = hls_statem_reduction_fixture:count_value(PID, 31, 7),
        ok = hls_statem_reduction_fixture:count_value(PID, 31, 9),
        ok = hls_statem_reduction_fixture:probe(PID),
        ok = hls_statem_reduction_fixture:connect(PID, self()),
        ?assertEqual({observation, 1, 16, 0, 1}, observation()),
        ?assertEqual({observation, 2, 16, 0, 1}, observation()),
        ?assertEqual(reported, maps:get(phase, hls_statem:info(PID)))
    after
        stop_if_alive(PID)
    end.

mismatched_epoch_is_postponed_then_retried_after_next_open_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    try
        ok = hls_statem_reduction_fixture:begin_chain(PID, 40),
        ok = hls_statem_reduction_fixture:count_value(PID, 41, 5),
        Mismatched = hls_statem:info(PID),
        ?assertEqual(1, maps:get(postponed, Mismatched)),
        ?assertMatch(
            #{key := 40, received := 0, remaining := 2},
            maps:get(reduction, Mismatched)
        ),

        ok = hls_statem_reduction_fixture:count_value(PID, 40, 3),
        ok = hls_statem_reduction_fixture:count_value(PID, 40, 4),
        Retried = hls_statem:info(PID),
        ?assertEqual(chain_first, maps:get(phase, Retried)),
        ?assertEqual(0, maps:get(postponed, Retried)),
        ?assertMatch(
            #{key := 41, received := 1, remaining := 1},
            maps:get(reduction, Retried)
        ),

        ok = hls_statem_reduction_fixture:count_value(PID, 41, 6),
        ?assertEqual({observation, 1, 11, 7, 2}, observation())
    after
        stop_if_alive(PID)
    end.

contribution_before_open_is_postponed_then_retried_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    try
        ok = hls_statem_reduction_fixture:count_value(PID, 45, 3),
        BeforeOpen = hls_statem:info(PID),
        ?assertEqual(idle, maps:get(reduction, BeforeOpen)),
        ?assertEqual(1, maps:get(postponed, BeforeOpen)),

        ok = hls_statem_reduction_fixture:begin_count(PID, 45),
        AfterOpen = hls_statem:info(PID),
        ?assertEqual(0, maps:get(postponed, AfterOpen)),
        ?assertMatch(
            #{key := 45, received := 1, remaining := 1},
            maps:get(reduction, AfterOpen)
        ),
        ok = hls_statem_reduction_fixture:count_value(PID, 45, 4),
        ?assertEqual({observation, 1, 7, 0, 1}, observation())
    after
        stop_if_alive(PID)
    end.

duplicate_member_fails_the_actor_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_members(PID, 50),
    ok = hls_statem_reduction_fixture:member_value(PID, 50, 0, 1),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:member_value(PID, 50, 0, 99),
    expect_down(PID, Monitor, fun
        ({hls_statem_reduction_failure,
                {duplicate_member, 0}, _Message}) -> true;
        (_) -> false
    end).

unexpected_member_fails_the_actor_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_members(PID, 51),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:member_value(PID, 51, 7, 99),
    expect_down(PID, Monitor, fun
        ({hls_statem_reduction_failure,
                {unexpected_member, 7}, _Message}) -> true;
        (_) -> false
    end).

phase_exit_with_partial_reduction_fails_the_actor_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_count(PID, 60),
    ok = hls_statem_reduction_fixture:count_value(PID, 60, 1),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:escape(PID),
    expect_down(PID, Monitor, fun
        ({hls_statem_reduction_incomplete,
                #{key := 60, received := 1, remaining := 1},
                {escape, 0}}) ->
            true;
        (_) -> false
    end).

phase_repeat_with_partial_reduction_fails_the_actor_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_count(PID, 61),
    ok = hls_statem_reduction_fixture:count_value(PID, 61, 1),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:repeat_phase(PID),
    expect_down(PID, Monitor, fun
        ({hls_statem_reduction_incomplete,
                #{key := 61, received := 1, remaining := 1},
                {escape, 1}}) ->
            true;
        (_) -> false
    end).

contribution_cannot_mutate_callback_data_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_count(PID, 70),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:mutating_value(PID, 70, 9),
    expect_down(PID, Monitor, fun
        ({{bad_hls_statem_contribution_state,
                counting, _MutatedCell}, _Stack}) -> true;
        (_) -> false
    end).

contribution_cannot_mutate_callback_phase_test() ->
    {ok, PID} = hls_statem_reduction_fixture:start_link(self()),
    ok = hls_statem_reduction_fixture:begin_count(PID, 71),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem_reduction_fixture:phase_mutating_value(PID, 71, 9),
    expect_down(PID, Monitor, fun
        ({{bad_hls_statem_contribution_state,
                escaped, _UnchangedCell}, _Stack}) -> true;
        (_) -> false
    end).

observation() ->
    receive
        {'$gen_cast', Observation = {observation, _, _, _, _}} ->
            Observation
    after 1000 ->
        error(missing_reduction_observation)
    end.

expect_down(PID, Monitor, Matches) ->
    receive
        {'DOWN', Monitor, process, PID, Reason} ->
            ?assert(Matches(Reason))
    after 1000 ->
        error({machine_did_not_fail, PID})
    end.

stop_if_alive(PID) ->
    case is_process_alive(PID) of
        true -> hls_statem:stop(PID);
        false -> ok
    end.
