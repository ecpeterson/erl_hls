-module(xls_statem_tests).

-behaviour(xls_statem).

-include_lib("eunit/include/eunit.hrl").

-export([callback_mode/0, init/1, handle_event/4]).

postponed_retry_requires_outer_state_change_test_() ->
    {setup,
        fun() ->
            {ok, PID} = xls_statem:start_link(
                ?MODULE,
                [],
                [{mailbox_capacity, 8}]
            ),
            PID
        end,
        fun(PID) ->
            xls_statem:stop(PID)
        end,
        fun(PID) ->
            [?_test(postponed_retry_boundary(PID))]
        end}.

callback_mode() ->
    handle_event_function.

init([]) ->
    {ok, waiting, #{
        attempts => 0,
        eligible => false,
        handled => false,
        log => []
    }}.

handle_event(cast, deferred, waiting, Data) ->
    {keep_state,
        log(deferred_waiting, Data#{
            attempts := maps:get(attempts, Data) + 1
        }),
        [postpone]};
handle_event(cast, data_change, waiting, Data) ->
    {keep_state, log(data_change, Data#{eligible := true})};
handle_event(cast, same_state_transition, waiting, Data) ->
    {next_state, waiting, log(same_state_transition, Data)};
handle_event(info, informational, waiting, Data) ->
    {keep_state, log(informational, Data)};
handle_event(cast, younger, waiting, Data) ->
    {keep_state, log(younger, Data)};
handle_event(cast, advance, waiting, Data) ->
    {next_state, ready, log(advance, Data)};
handle_event(cast, deferred, ready, Data) ->
    true = maps:get(eligible, Data),
    {keep_state,
        log(deferred_ready, Data#{
            attempts := maps:get(attempts, Data) + 1,
            handled := true
        })}.

postponed_retry_boundary(PID) ->
    ok = xls_statem:cast(PID, deferred),
    ok = xls_statem:cast(PID, data_change),
    ok = xls_statem:cast(PID, same_state_transition),
    PID ! informational,
    ok = xls_statem:cast(PID, younger),

    Before = xls_statem:info(PID),
    ?assertEqual(waiting, maps:get(state_name, Before)),
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

    ok = xls_statem:cast(PID, advance),
    After = xls_statem:info(PID),
    ?assertEqual(ready, maps:get(state_name, After)),
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

log(Event, Data) ->
    Data#{log := maps:get(log, Data) ++ [Event]}.
