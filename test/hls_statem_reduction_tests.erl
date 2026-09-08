-module(hls_statem_reduction_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIXTURE, hls_statem_reduction_fixture).

count_reduction_completes_through_internal_event_test() ->
    {ok, PID} = start(),
    try
        ok = hls_statem:cast(PID, {begin_count, epoch}),
        ?assertMatch(
            #{
                phase := counting,
                reduction := #{
                    name := sum,
                    key := epoch,
                    population := {count, 2},
                    received := 0,
                    remaining := 2
                }
            },
            hls_statem:info(PID)
        ),

        ok = hls_statem:cast(PID, {count, epoch, 4}),
        ?assertMatch(
            #{reduction := #{received := 1, remaining := 1}},
            hls_statem:info(PID)
        ),
        ok = hls_statem:cast(PID, {count, epoch, 5}),

        ?assertEqual({observation, 1, 9, 0, 1}, observation()),
        ?assertMatch(
            #{phase := complete, reduction := idle,
                data := #{value := 9, completions := 1}},
            hls_statem:info(PID)
        )
    after
        stop_if_alive(PID)
    end.

fixed_members_complete_in_arrival_independent_order_test() ->
    {ok, PID} = start(),
    try
        ok = hls_statem:cast(PID, {begin_members, epoch}),
        ok = hls_statem:cast(PID, {member, epoch, 2, 3}),
        ok = hls_statem:cast(PID, {member, epoch, 0, 4}),
        ok = hls_statem:cast(PID, {member, epoch, 3, 5}),
        ok = hls_statem:cast(PID, {member, epoch, 1, 6}),
        ?assertEqual({observation, 1, 18, 0, 1}, observation())
    after
        stop_if_alive(PID)
    end.

completion_precedes_an_already_queued_external_message_test() ->
    {ok, PID} = start_deferred(),
    try
        ok = hls_statem:cast(PID, {begin_count, epoch}),
        ok = hls_statem:cast(PID, {count, epoch, 4}),
        ok = hls_statem:cast(PID, {count, epoch, 5}),
        ok = hls_statem:cast(PID, probe),
        ok = hls_statem:connect(PID, #{out => self()}),

        ?assertEqual({observation, 1, 9, 0, 1}, observation()),
        ?assertEqual({observation, 2, 9, 0, 1}, observation()),
        ?assertMatch(
            #{phase := reported, reduction := idle,
                mailbox := #{committed := 0}},
            hls_statem:info(PID)
        )
    after
        stop_if_alive(PID)
    end.

contribution_before_open_is_postponed_then_retried_test() ->
    {ok, PID} = start(),
    try
        ok = hls_statem:cast(PID, {count, epoch, 4}),
        ?assertMatch(
            #{phase := idle, postponed := 1, reduction := idle},
            hls_statem:info(PID)
        ),
        ok = hls_statem:cast(PID, {begin_count, epoch}),
        ?assertMatch(
            #{phase := counting, postponed := 0,
                reduction := #{received := 1, remaining := 1}},
            hls_statem:info(PID)
        ),
        ok = hls_statem:cast(PID, {count, epoch, 5}),
        ?assertEqual({observation, 1, 9, 0, 1}, observation())
    after
        stop_if_alive(PID)
    end.

future_key_is_retried_after_the_next_reduction_opens_test() ->
    {ok, PID} = start(),
    try
        ok = hls_statem:cast(PID, {begin_chain, 10}),
        ok = hls_statem:cast(PID, {count, 11, 7}),
        ok = hls_statem:cast(PID, {count, 10, 2}),
        ok = hls_statem:cast(PID, {count, 10, 3}),

        ?assertMatch(
            #{
                phase := chain,
                postponed := 0,
                data := #{key := 11, prior := 5, completions := 1},
                reduction := #{key := 11, received := 1, remaining := 1}
            },
            hls_statem:info(PID)
        ),
        ok = hls_statem:cast(PID, {count, 11, 8}),
        ?assertEqual({observation, 1, 15, 5, 2}, observation())
    after
        stop_if_alive(PID)
    end.

unrelated_same_phase_work_remains_legal_test() ->
    {ok, PID} = start(),
    try
        ok = hls_statem:cast(PID, {begin_count, epoch}),
        ok = hls_statem:cast(PID, same_phase),
        ?assertMatch(
            #{
                phase := counting,
                data := #{unrelated := true},
                reduction := #{received := 0, remaining := 2}
            },
            hls_statem:info(PID)
        )
    after
        stop_if_alive(PID)
    end.

member_protocol_violations_fail_test_() ->
    Cases = [
        {
            duplicate,
            [{member, epoch, 0, 1}, {member, epoch, 0, 2}],
            {duplicate_member, 0}
        },
        {
            unexpected,
            [{member, epoch, 9, 1}],
            {unexpected_member, 9}
        },
        {wrong_mode, [{count, epoch, 1}], wrong_mode}
    ],
    [?_test(member_protocol_violation(Messages, Reason))
        || {_Label, Messages, Reason} <- Cases].

incomplete_reduction_forbids_a_phase_boundary_test_() ->
    [?_test(incomplete_boundary(Message)) || Message <- [leave, repeat]].

contribution_must_not_mutate_actor_state_test_() ->
    Messages = [
        {mutate_data, epoch, 7},
        {mutate_phase, epoch, 7}
    ],
    [?_test(contribution_state_mutation(Message)) || Message <- Messages].

member_protocol_violation(Messages, ExpectedReason) ->
    {ok, PID} = start(),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, {begin_members, epoch}),
    lists:foreach(fun(Message) -> hls_statem:cast(PID, Message) end, Messages),
    receive
        {'DOWN', Monitor, process, PID,
            {hls_statem_reduction_failure, ExpectedReason, _Message}} ->
            ok
    after 1000 ->
        error({machine_did_not_reject_contribution, ExpectedReason})
    end.

incomplete_boundary(Message) ->
    {ok, PID} = start(),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, {begin_count, epoch}),
    ok = hls_statem:cast(PID, {count, epoch, 1}),
    ok = hls_statem:cast(PID, Message),
    receive
        {'DOWN', Monitor, process, PID,
            {hls_statem_reduction_incomplete,
                #{received := 1, remaining := 1}, Message}} ->
            ok
    after 1000 ->
        error({machine_crossed_incomplete_reduction, Message})
    end.

contribution_state_mutation(Message) ->
    {ok, PID} = start(),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, {begin_count, epoch}),
    ok = hls_statem:cast(PID, Message),
    receive
        {'DOWN', Monitor, process, PID,
            {{bad_hls_statem_contribution_state, _Phase, _Data}, _Stack}} ->
            ok
    after 1000 ->
        error({machine_accepted_contribution_state_mutation, Message})
    end.

start() ->
    hls_statem:start_link(
        ?FIXTURE,
        [],
        [{mailbox_capacity, 16}, {outputs, #{out => self()}}]
    ).

start_deferred() ->
    hls_statem:start_link(
        ?FIXTURE,
        [],
        [{mailbox_capacity, 16}]
    ).

observation() ->
    receive
        {'$gen_cast', Observation = {observation, _, _, _, _}} ->
            Observation
    after 1000 ->
        error(missing_reduction_observation)
    end.

stop_if_alive(PID) ->
    case is_process_alive(PID) of
        true -> hls_statem:stop(PID);
        false -> ok
    end.
