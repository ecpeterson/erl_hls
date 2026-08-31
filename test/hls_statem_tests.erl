-module(hls_statem_tests).

-behavior(hls_statem).

-include_lib("eunit/include/eunit.hrl").

-export([init/1, handle_enter/3, handle_cast/3]).

initial_enter_precedes_first_cast_test() ->
    {ok, PID} = start(4),
    try
        receive {'$gen_cast', started} -> ok end,
        ok = hls_statem:cast(PID, probe),
        Data = maps:get(data, hls_statem:info(PID)),
        ?assertEqual(
            [{enter, waiting, waiting}, probe],
            maps:get(log, Data)
        )
    after
        stop_if_alive(PID)
    end.

conditional_entry_cast_can_be_suppressed_test() ->
    {ok, PID} = hls_statem:start_link(
        ?MODULE,
        {emit, false},
        [{mailbox_capacity, 1}, {outputs, #{out => self()}}]
    ),
    try
        ?assertEqual(waiting, maps:get(phase, hls_statem:info(PID))),
        receive
            {'$gen_cast', started} ->
                error(disabled_entry_cast_was_sent)
        after 10 ->
            ok
        end
    after
        stop_if_alive(PID)
    end.

postponed_retry_requires_phase_change_test() ->
    {ok, PID} = start(8),
    try
        receive {'$gen_cast', started} -> ok end,
        postponed_retry_boundary(PID)
    after
        stop_if_alive(PID)
    end.

ordinary_same_phase_does_not_reenter_or_retry_test() ->
    {ok, PID} = start(8),
    try
        receive {'$gen_cast', started} -> ok end,
        ok = hls_statem:cast(PID, {repeat_deferred, first}),
        ok = hls_statem:cast(PID, same_phase_transition),

        Info = hls_statem:info(PID),
        ?assertEqual(waiting, maps:get(phase, Info)),
        ?assertEqual(1, maps:get(postponed, Info)),
        ?assertEqual(
            [
                {enter, waiting, waiting},
                {repeat_deferred, first, postponed},
                same_phase_transition
            ],
            maps:get(log, maps:get(data, Info))
        ),
        receive
            {'$gen_cast', started} ->
                error(unexpected_same_phase_entry)
        after 0 ->
            ok
        end
    after
        stop_if_alive(PID)
    end.

repeat_phase_enters_before_replaying_in_arrival_order_test() ->
    {ok, PID} = start(8),
    try
        receive {'$gen_cast', started} -> ok end,
        ok = hls_statem:cast(PID, {repeat_deferred, first}),
        ok = hls_statem:cast(PID, {repeat_deferred, second}),
        ok = hls_statem:cast(PID, repeat_boundary),
        receive
            {'$gen_cast', started} -> ok
        after 1000 ->
            error(missing_repeat_phase_entry_cast)
        end,

        Info = hls_statem:info(PID),
        ?assertEqual(waiting, maps:get(phase, Info)),
        ?assertEqual(0, maps:get(postponed, Info)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, Info))),
        ?assertEqual(
            [
                {enter, waiting, waiting},
                {repeat_deferred, first, postponed},
                {repeat_deferred, second, postponed},
                repeat_boundary,
                {enter, waiting, waiting},
                {repeat_deferred, first, replayed},
                {repeat_deferred, second, replayed}
            ],
            maps:get(log, maps:get(data, Info))
        )
    after
        stop_if_alive(PID)
    end.

repeat_phase_waits_for_connection_test() ->
    {ok, PID} = start_deferred(4),
    try
        ok = hls_statem:cast(PID, repeat_boundary),
        Before = hls_statem:info(PID),
        ?assertEqual([], maps:get(log, maps:get(data, Before))),
        ?assertEqual(1, maps:get(committed, maps:get(mailbox, Before))),

        ok = hls_statem:connect(PID, #{out => self()}),
        receive {'$gen_cast', started} -> ok end,
        receive {'$gen_cast', started} -> ok end,
        After = hls_statem:info(PID),
        ?assertEqual(
            [
                {enter, waiting, waiting},
                repeat_boundary,
                {enter, waiting, waiting}
            ],
            maps:get(log, maps:get(data, After))
        ),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, After)))
    after
        stop_if_alive(PID)
    end.

invalid_repeat_phase_directives_are_fail_stop_test_() ->
    [
        ?_test(reject_repeat_phase_directive(Directive))
        || Directive <- [postpone, fail]
    ].

mailbox_overflow_is_fail_stop_test() ->
    {ok, PID} = start(1),
    receive {'$gen_cast', started} -> ok end,
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, block),
    ok = hls_statem:cast(PID, overflow),
    receive
        {'DOWN', Monitor, process, PID, {mailbox_full, overflow}} -> ok
    after 1000 ->
        error(machine_did_not_stop_on_overflow)
    end.

invalid_conclusion_is_fail_stop_test() ->
    {ok, PID} = start(1),
    receive {'$gen_cast', started} -> ok end,
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, invalid_conclusion),
    receive
        {'DOWN', Monitor, process, PID,
                {{bad_hls_statem_conclusion, waiting, invalid}, _Stack}} ->
            ok
    after 1000 ->
        error(machine_did_not_reject_invalid_conclusion)
    end.

capacity_matches_lowered_u8_bound_test() ->
    ?assertError(badarg, start(256)).

repeat_phase_is_reserved_from_application_phases_test() ->
    Previous = process_flag(trap_exit, true),
    try
        ?assertMatch(
            {error, {{bad_hls_statem_phase, repeat_phase}, _InitStack}},
            hls_statem:start_link(
                ?MODULE,
                repeat_phase,
                [{mailbox_capacity, 1}, {outputs, #{out => self()}}]
            )
        ),
        receive
            {'EXIT', _PID,
                {{bad_hls_statem_phase, repeat_phase}, _ExitStack}} ->
                ok
        after 0 ->
            ok
        end
    after
        process_flag(trap_exit, Previous)
    end.

outputs_may_be_connected_after_start_test() ->
    {ok, PID} = start_deferred(4),
    try
        Info = hls_statem:info(PID),
        ?assertNot(maps:get(connected, Info)),
        ?assertEqual([], maps:get(outputs, Info))
    after
        stop_if_alive(PID)
    end.

two_stage_connection_supports_cycles_test() ->
    {ok, Left} = start_deferred(4),
    {ok, Right} = start_deferred(4),
    try
        ok = hls_statem:connect(Left, #{out => Right}),
        ok = hls_statem:connect(Right, #{out => Left}),
        await_log(Left, peer_started),
        await_log(Right, peer_started),
        ?assert(maps:get(connected, hls_statem:info(Left))),
        ?assert(maps:get(connected, hls_statem:info(Right))),
        ?assertEqual(
            {error, already_connected},
            hls_statem:connect(Left, #{out => Right})
        )
    after
        stop_if_alive(Left),
        stop_if_alive(Right)
    end.

ordinary_message_is_not_a_cast_test() ->
    {ok, PID} = start(1),
    receive {'$gen_cast', started} -> ok end,
    unlink(PID),
    Monitor = monitor(process, PID),
    PID ! unexpected_info,
    receive
        {'DOWN', Monitor, process, PID,
                {unsupported_hls_statem_info, unexpected_info}} ->
            ok
    after 1000 ->
        error(machine_did_not_reject_info_message)
    end.

init([]) ->
    {ok, waiting, #{
        attempts => 0,
        eligible => false,
        emit => true,
        handled => false,
        log => []
    }};
init({emit, Enabled}) when is_boolean(Enabled) ->
    {ok, waiting, #{
        attempts => 0,
        eligible => false,
        emit => Enabled,
        handled => false,
        log => []
    }};
init(repeat_phase) ->
    {ok, repeat_phase, #{}}.

handle_enter(OldPhase, waiting, Data) ->
    {log({enter, OldPhase, waiting}, Data), [
        {cast_if, maps:get(emit, Data), out, started}
    ]};
handle_enter(OldPhase, ready, Data) ->
    {log({enter, OldPhase, ready}, Data), [{cast, out, handled}]}.

handle_cast(probe, waiting, Data) ->
    {waiting, log(probe, Data), consume};
handle_cast(started, waiting, Data) ->
    {waiting, log(peer_started, Data), consume};
handle_cast(deferred, waiting, Data) ->
    NextData = log(deferred_waiting, Data#{
        attempts := maps:get(attempts, Data) + 1
    }),
    {waiting, NextData, postpone};
handle_cast(data_change, waiting, Data) ->
    NextData = log(data_change, Data#{eligible := true}),
    {waiting, NextData, consume};
handle_cast(same_phase_transition, waiting, Data) ->
    {waiting, log(same_phase_transition, Data), consume};
handle_cast({repeat_deferred, Label}, waiting,
        Data = #{eligible := false}) ->
    NextData = log({repeat_deferred, Label, postponed}, Data),
    {waiting, NextData, postpone};
handle_cast({repeat_deferred, Label}, waiting,
        Data = #{eligible := true}) ->
    NextData = log({repeat_deferred, Label, replayed}, Data),
    {waiting, NextData, consume};
handle_cast(repeat_boundary, waiting, Data) ->
    NextData = log(repeat_boundary, Data#{eligible := true}),
    {repeat_phase, NextData, consume};
handle_cast({invalid_repeat_phase, Directive}, waiting, Data) ->
    {repeat_phase, Data, Directive};
handle_cast(informational, waiting, Data) ->
    {waiting, log(informational, Data), consume};
handle_cast(younger, waiting, Data) ->
    {waiting, log(younger, Data), consume};
handle_cast(advance, waiting, Data) ->
    {ready, log(advance, Data), consume};
handle_cast(deferred, ready, Data) ->
    true = maps:get(eligible, Data),
    NextData = log(deferred_ready, Data#{
        attempts := maps:get(attempts, Data) + 1,
        handled := true
    }),
    {ready, NextData, consume};
handle_cast(block, waiting, Data) ->
    {waiting, Data, postpone};
handle_cast(invalid_conclusion, waiting, Data) ->
    {waiting, Data, invalid}.

start(Capacity) ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, Capacity}, {outputs, #{out => self()}}]
    ).

start_deferred(Capacity) ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, Capacity}]
    ).

postponed_retry_boundary(PID) ->
    ok = hls_statem:cast(PID, deferred),
    ok = hls_statem:cast(PID, data_change),
    ok = hls_statem:cast(PID, same_phase_transition),
    ok = hls_statem:cast(PID, informational),
    ok = hls_statem:cast(PID, younger),

    Before = hls_statem:info(PID),
    ?assertEqual(waiting, maps:get(phase, Before)),
    ?assertEqual(1, maps:get(postponed, Before)),
    ?assertEqual(1, maps:get(attempts, maps:get(data, Before))),
    ?assertEqual(
        [
            {enter, waiting, waiting},
            deferred_waiting,
            data_change,
            same_phase_transition,
            informational,
            younger
        ],
        maps:get(log, maps:get(data, Before))
    ),

    ok = hls_statem:cast(PID, advance),
    receive
        {'$gen_cast', handled} -> ok
    after 1000 ->
        error(missing_phase_entry_cast)
    end,
    After = hls_statem:info(PID),
    ?assertEqual(ready, maps:get(phase, After)),
    ?assertEqual(0, maps:get(postponed, After)),
    ?assertEqual(2, maps:get(attempts, maps:get(data, After))),
    ?assert(maps:get(handled, maps:get(data, After))),
    ?assertEqual(
        [
            {enter, waiting, waiting},
            deferred_waiting,
            data_change,
            same_phase_transition,
            informational,
            younger,
            advance,
            {enter, waiting, ready},
            deferred_ready
        ],
        maps:get(log, maps:get(data, After))
    ),
    Mailbox = maps:get(mailbox, After),
    ?assertEqual(0, maps:get(committed, Mailbox)).

reject_repeat_phase_directive(Directive) ->
    {ok, PID} = start(1),
    receive {'$gen_cast', started} -> ok end,
    unlink(PID),
    Monitor = monitor(process, PID),
    ok = hls_statem:cast(PID, {invalid_repeat_phase, Directive}),
    receive
        {'DOWN', Monitor, process, PID,
                {{bad_hls_statem_conclusion, repeat_phase, Directive},
                    _Stack}} ->
            ok
    after 1000 ->
        error({machine_did_not_reject_repeat_phase_directive, Directive})
    end.

stop_if_alive(PID) ->
    case is_process_alive(PID) of
        true -> hls_statem:stop(PID);
        false -> ok
    end.

await_log(PID, Entry) ->
    await_log(PID, Entry, 100).

await_log(_PID, Entry, 0) ->
    error({missing_log_entry, Entry});
await_log(PID, Entry, Attempts) ->
    Data = maps:get(data, hls_statem:info(PID)),
    case lists:member(Entry, maps:get(log, Data)) of
        true -> ok;
        false ->
            receive after 1 -> ok end,
            await_log(PID, Entry, Attempts - 1)
    end.

log(Message, Data) ->
    Data#{log := maps:get(log, Data) ++ [Message]}.
