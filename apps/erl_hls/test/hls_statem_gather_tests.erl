-module(hls_statem_gather_tests).
-moduledoc "CPU witnesses for indexed gathering, bounded scheduling and atomic entry.".
-include_lib("eunit/include/eunit.hrl").

%% A gathered value is invisible until completion, even when equal to padding.
-spec partial_visibility_and_mask_capture_test() -> ok.
partial_visibility_and_mask_capture_test() ->
    with_actor(#{}, fun(Pid) ->
        cast(Pid, open), cast(Pid, {value, items, 7, 2, padding}),
        ?assertMatch(#{data := #{values := hidden}, reduction := idle,
            gather := #{expected := 13, seen := 4, remaining := 2}}, hls_statem:info(Pid)),
        cast(Pid, change_mask),
        cast(Pid, {value, items, 7, 0, first}), cast(Pid, {value, items, 7, 3, last}),
        completed([first, padding, padding, last]),
        ?assertMatch(#{gather := idle, data := #{completed_mask := 13}}, hls_statem:info(Pid))
    end).

%% All six arrival orders produce the same fixed-index result without a reduce/3 callback.
-spec all_arrival_orders_test() -> ok.
all_arrival_orders_test() ->
    lists:foreach(fun(Order) ->
        with_actor(#{}, fun(Pid) ->
            cast(Pid, open),
            lists:foreach(fun({Member, Value}) -> cast(Pid, {value, items, 7, Member, Value}) end, Order),
            completed([first, padding, middle, last])
        end)
    end, permutations([{0, first}, {2, middle}, {3, last}])).

%% Before opening, matching traffic retains mailbox capacity and retries on phase entry.
-spec before_open_postpones_test() -> ok.
before_open_postpones_test() ->
    with_actor(#{mask => 1}, fun(Pid) ->
        cast(Pid, {value, items, 7, 0, first}),
        ?assertMatch(#{postponed := 1, gather := idle}, hls_statem:info(Pid)),
        cast(Pid, open), completed([first, padding, padding, padding]),
        ?assertMatch(#{postponed := 0, mailbox := #{committed := 0}}, hls_statem:info(Pid))
    end).

%% A successor epoch waits until completion reenters and opens its captured window.
-spec future_key_retries_test() -> ok.
future_key_retries_test() ->
    with_actor(#{mask => 1, mode => chain}, fun(Pid) ->
        cast(Pid, open), cast(Pid, {value, items, 8, 0, next}),
        ?assertMatch(#{postponed := 1, gather := #{key := 7, seen := 0}}, hls_statem:info(Pid)),
        cast(Pid, {value, items, 7, 0, first}), completed([next, padding, padding, padding]),
        ?assertMatch(#{data := #{completions := 2}, postponed := 0}, hls_statem:info(Pid))
    end).

%% A different collection name neither mutates the current gather nor becomes an error.
-spec different_name_postpones_test() -> ok.
different_name_postpones_test() ->
    with_actor(#{}, fun(Pid) ->
        cast(Pid, open), cast(Pid, {value, other, 7, 0, ignored}),
        ?assertMatch(#{postponed := 1, gather := #{seen := 0, remaining := 3}}, hls_statem:info(Pid))
    end).

%% Empty initial entry commits its data before completion, which needs no external trigger.
-spec empty_initial_entry_test() -> ok.
empty_initial_entry_test() ->
    with_actor(#{initial => collecting, mask => 0}, fun(Pid) ->
        completed([padding, padding, padding, padding]),
        ?assertMatch(#{phase := finished, gather := idle, data := #{completions := 1}}, hls_statem:info(Pid))
    end).

%% Completion entry and its continuation precede an already queued external message.
-spec completion_next_event_order_test() -> ok.
completion_next_event_order_test() ->
    {ok, Pid} = hls_statem:start_link(hls_statem_gather_fixture, #{mask => 1}, [{mailbox_capacity, 8}]),
    try
        cast(Pid, open), cast(Pid, {value, items, 7, 0, first}), cast(Pid, probe),
        ok = hls_statem:connect(Pid, #{out => self()}),
        completed([first, padding, padding, padding]), ?assertEqual(probe, observation())
    after stop(Pid) end.

%% Duplicates and foreign members fail after selection; an unfinished gather cannot be abandoned.
-spec protocol_failures_test() -> ok.
protocol_failures_test() ->
    ?assertMatch({hls_statem_gather_failure, {duplicate_member, 0}, _},
        failure(#{}, [open, {value, items, 7, 0, a}, {value, items, 7, 0, b}])),
    lists:foreach(fun(Member) ->
        ?assertMatch({hls_statem_gather_failure, {unexpected_member, Member}, _},
            failure(#{}, [open, {value, items, 7, Member, invalid}]))
    end, [-1, 1, 4, invalid]),
    lists:foreach(fun(Message) ->
        ?assertMatch({hls_statem_gather_incomplete, #{remaining := 2}, Message},
            failure(#{}, [open, {value, items, 7, 0, a}, Message]))
    end, [leave, repeat]),
    ?assertMatch({{bad_hls_statem_contribution_state, _, _}, _}, failure(#{}, [open, {mutate, 0}])),
    ?assertMatch({hls_statem_failure, fail}, failure(#{}, [open, fail])).

%% Invalid entry never publishes earlier casts or an empty completion; openings cannot coexist.
-spec atomic_entry_and_open_conflicts_test() -> ok.
atomic_entry_and_open_conflicts_test() ->
    lists:foreach(fun(Mask) ->
        ?assertMatch({{unknown_hls_statem_output, missing}, _}, failure(#{mask => Mask, mode => invalid_tail}, [open])),
        ?assertEqual(none, unexpected_observation())
    end, [0, 13]),
    ?assertMatch({hls_statem_open_gather_must_be_first, _}, failure(#{mode => double_gather}, [open])),
    ?assertMatch({hls_statem_open_reduction_must_be_first, _}, failure(#{mode => mixed_collection}, [open])),
    ?assertMatch({hls_statem_open_gather_must_be_first, _}, failure(#{mode => late_open}, [open])),
    ?assertEqual(none, unexpected_observation()).

%% Completion exceptions and direct replies fail without publishing a successor entry.
-spec completion_failures_test() -> ok.
completion_failures_test() ->
    ?assertMatch({completion_failed, _}, failure(#{mask => 1, mode => completion_failure}, [open, {value, items, 7, 0, a}])),
    ?assertMatch({hls_statem_gather_actions_unsupported, _}, failure(#{mask => 1, mode => completion_reply}, [open, {value, items, 7, 0, a}])),
    ?assertEqual(none, unexpected_observation()).

%% The existing reduction callback now supports the same post-entry continuation order.
-spec reduction_completion_continuation_test() -> ok.
reduction_completion_continuation_test() ->
    {ok, Pid} = hls_statem:start_link(hls_statem_collection_fixture, normal,
        [{mailbox_capacity, 4}, {outputs, #{out => self()}}]),
    try
        cast(Pid, open), cast(Pid, {value, 19}),
        ?assertEqual(reduced_entry, observation()),
        ?assertEqual({reduced, 19}, observation()),
        ?assertMatch(#{reduction := idle, gather := idle}, hls_statem:info(Pid))
    after stop(Pid) end.

%% Neither opening order may install both a scalar reduction and an indexed gather.
-spec mixed_collection_openings_test() -> ok.
mixed_collection_openings_test() ->
    lists:foreach(fun({Mode, Expected}) ->
        {ok, Pid} = hls_statem:start_link(hls_statem_collection_fixture, Mode,
            [{mailbox_capacity, 4}, {outputs, #{out => self()}}]),
        unlink(Pid), Ref = monitor(process, Pid), cast(Pid, open),
        receive {'DOWN', Ref, process, Pid, Reason} -> ?assertMatch({Expected, _}, Reason)
        after 1000 -> stop(Pid), error(expected_opening_conflict) end
    end, [{reduction_first, hls_statem_open_gather_must_be_first},
        {gather_first, hls_statem_open_reduction_must_be_first}]).

%% Keep each witness isolated and stop successful actors even when an assertion fails.
-spec with_actor(map(), fun((pid()) -> term())) -> ok.
with_actor(Options, Test) ->
    {ok, Pid} = hls_statem:start_link(hls_statem_gather_fixture, Options,
        [{mailbox_capacity, 16}, {outputs, #{out => self()}}]),
    try Test(Pid), ok after stop(Pid) end.

%% Wait for an expected adapter failure without propagating its linked exit to EUnit.
-spec failure(map(), [term()]) -> term().
failure(Options, Messages) ->
    {ok, Pid} = hls_statem:start_link(hls_statem_gather_fixture, Options,
        [{mailbox_capacity, 16}, {outputs, #{out => self()}}]),
    unlink(Pid), Ref = monitor(process, Pid),
    lists:foreach(fun(Message) -> cast(Pid, Message) end, Messages),
    receive {'DOWN', Ref, process, Pid, Reason} -> Reason
    after 1000 -> stop(Pid), error(expected_failure) end.

%% Same-sender mailbox ordering makes subsequent info queries a synchronization boundary.
-spec cast(pid(), term()) -> ok.
cast(Pid, Message) -> hls_statem:cast(Pid, Message).

%% Entry publication must precede the completion's named continuation publication.
-spec completed(list()) -> ok.
completed(Values) ->
    ?assertEqual({entry, Values}, observation()),
    ?assertEqual({finished, Values}, observation()).

%% Observe only fixture effects, with a bounded timeout to diagnose missing progress.
-spec observation() -> term().
observation() -> receive {'$gen_cast', Value} -> Value after 1000 -> error(missing_observation) end.

%% Failure paths must leave no committed output effect.
-spec unexpected_observation() -> none | term().
unexpected_observation() -> receive {'$gen_cast', Value} -> Value after 0 -> none end.

%% Avoid sending a stop request to an actor already terminated by a failure witness.
-spec stop(pid()) -> ok.
stop(Pid) -> case is_process_alive(Pid) of true -> hls_statem:stop(Pid); false -> ok end.

%% Exhaust the small distinct-member arrival-order space deterministically.
-spec permutations([T]) -> [[T]].
permutations([]) -> [[]];
permutations(Values) -> [[Value | Tail] || Value <- Values, Tail <- permutations(lists:delete(Value, Values))].
