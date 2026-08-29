-module(xls_statem_tests).

-behaviour(xls_statem).

-include_lib("eunit/include/eunit.hrl").

-export([init/1, transition/2]).

postponed_retry_requires_outer_state_change_test() ->
    {ok, PID} = xls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, 8}]
    ),
    try
        postponed_retry_boundary(PID)
    after
        case is_process_alive(PID) of
            true -> xls_statem:stop(PID);
            false -> ok
        end
    end.

mailbox_overflow_is_fail_stop_test() ->
    {ok, PID} = xls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, 1}]
    ),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = xls_statem:send(PID, block),
    ok = xls_statem:send(PID, overflow),
    receive
        {'DOWN', Monitor, process, PID, {mailbox_full, overflow}} -> ok
    after 1000 ->
        error(machine_did_not_stop_on_overflow)
    end.

invalid_conclusion_is_fail_stop_test() ->
    {ok, PID} = xls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, 1}]
    ),
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = xls_statem:send(PID, invalid_emit),
    receive
        {'DOWN', Monitor, process, PID,
                {{bad_xls_statem_conclusion, true, waiting, postpone},
                 _Stack}} ->
            ok
    after 1000 ->
        error(machine_did_not_reject_invalid_conclusion)
    end.

capacity_matches_lowered_u8_bound_test() ->
    ?assertError(
        badarg,
        xls_statem:start_link(
            ?MODULE,
            [],
            [{mailbox_capacity, 256}]
        )
    ).

init([]) ->
    {{false, none}, {waiting, #{
        attempts => 0,
        eligible => false,
        handled => false,
        log => []
    }}}.

transition(deferred, {waiting, Data}) ->
    NextData = log(deferred_waiting, Data#{
        attempts := maps:get(attempts, Data) + 1
    }),
    {{false, none}, {waiting, NextData}, postpone};
transition(data_change, {waiting, Data}) ->
    NextData = log(data_change, Data#{eligible := true}),
    {{false, none}, {waiting, NextData}, consume};
transition(same_state_transition, {waiting, Data}) ->
    {{false, none}, {waiting, log(same_state_transition, Data)}, consume};
transition(informational, {waiting, Data}) ->
    {{false, none}, {waiting, log(informational, Data)}, consume};
transition(younger, {waiting, Data}) ->
    {{false, none}, {waiting, log(younger, Data)}, consume};
transition(advance, {waiting, Data}) ->
    {{false, none}, {ready, log(advance, Data)}, consume};
transition(deferred, {ready, Data}) ->
    true = maps:get(eligible, Data),
    NextData = log(deferred_ready, Data#{
        attempts := maps:get(attempts, Data) + 1,
        handled := true
    }),
    {{true, handled}, {ready, NextData}, consume};
transition(block, {waiting, Data}) ->
    {{false, none}, {waiting, Data}, postpone};
transition(invalid_emit, {waiting, Data}) ->
    {{true, forbidden}, {waiting, Data}, postpone}.

postponed_retry_boundary(PID) ->
    ok = xls_statem:send(PID, deferred),
    ok = xls_statem:send(PID, data_change),
    ok = xls_statem:send(PID, same_state_transition),
    PID ! informational,
    ok = xls_statem:send(PID, younger),

    Before = xls_statem:info(PID),
    ?assertEqual(waiting, maps:get(phase, Before)),
    ?assertEqual(1, maps:get(postponed, Before)),
    ?assertEqual(1, maps:get(attempts, maps:get(data, Before))),
    ?assertEqual(
        [
            deferred_waiting,
            data_change,
            same_state_transition,
            informational,
            younger
        ],
        maps:get(log, maps:get(data, Before))
    ),

    ok = xls_statem:send(PID, advance),
    receive
        {xls_statem, PID, handled} -> ok
    after 1000 ->
        error(missing_bounded_output)
    end,
    After = xls_statem:info(PID),
    ?assertEqual(ready, maps:get(phase, After)),
    ?assertEqual(0, maps:get(postponed, After)),
    ?assertEqual(2, maps:get(attempts, maps:get(data, After))),
    ?assert(maps:get(handled, maps:get(data, After))),
    ?assertEqual(
        [
            deferred_waiting,
            data_change,
            same_state_transition,
            informational,
            younger,
            advance,
            deferred_ready
        ],
        maps:get(log, maps:get(data, After))
    ),
    Mailbox = maps:get(mailbox, After),
    ?assertEqual(0, maps:get(committed, Mailbox)).

log(Message, Data) ->
    Data#{log := maps:get(log, Data) ++ [Message]}.
